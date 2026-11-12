-- SuspicionsPack — NodeRadar (WoW: Forever only, see the .toc gate)
--
-- The nearest herbs and veins you can gather, as icons around your character, like
-- compass needles: each turns to point where its node is, stays at the same distance,
-- and has a small arrow between it and the middle. The nearest is drawn in front, full
-- size and with its distance; the others are smaller.
--
-- The game gives addons no list of nodes, but the minimap's tracking dots can be read.
-- Since build 70862 only under the real mouse: Scan.lua moves the minimap under it one
-- point a frame, with Copy.lua's picture in its place, and hands each answer here. Answers
-- of one name close together are one node. Its place is kept in map coordinates, so it
-- can be followed between scans. A scan runs as you walk (every few yards, at most every
-- few seconds), never standing still unless something asks for one (a zoom, a finder
-- switched, a loading screen). With NodeSight loaded, its scan is used instead: two
-- scans would fight over the minimap.
--
-- So the radar sees what the minimap shows: it needs the minimap on screen and Find
-- Herbs or Find Minerals on, and the minimap's zoom sets how far it reaches. Up is the
-- way your character faces, not the camera.
--
-- Icons move every frame: your facing is read again each time, and a node whose place
-- changed glides to it, as in WaypointUI. Distances and choices are updated 20 times a
-- second, which is plenty for them.
--
-- Idle costs nothing: the scan's per-frame driver, the follow ticker and the per-frame
-- drawing all stop when they have nothing to do, and with no finder on only an event
-- starts them again.

local SP = SuspicionsPack

local NR = SP:NewSPModule("NodeRadar", "nodeRadar")
SP.NodeRadar = NR

local Data = SP.NodeRadarData
local NODES, Key = Data.nodes, Data.Key
local Scan = SP.NodeRadarScan
local Copy = SP.NodeRadarCopy

local _issecretvalue = issecretvalue or function() return false end
local sin, cos, atan2, sqrt, exp, pi = math.sin, math.cos, math.atan2, math.sqrt, math.exp, math.pi
local floor, min, max = math.floor, math.min, math.max

-- The scan.
local CHECK     = 1     -- seconds between looks at whether a scan is due, while one could be
local RETRY     = 5     -- somewhere no scan can run (indoors, flying...): looked at again after
local ASKED     = 2     -- seconds after a scan before one asked for (zoom, finder) may run
local GROUP     = 20    -- yards: answers of one name closer than this are one node
local PICKED    = 8     -- yards: after loot, a node this close was the one gathered
local SQUARE_REACH = 1.42 -- a square minimap's corner, per its radius
local MAX_LINES = 300   -- tooltip lines remembered
local MAX_UNKNOWN = 200 -- unknown names remembered
local KEY_DRAW  = "NodeRadarDraw"
-- Why a scan did not start, when it is worth looking again soon (else after RETRY).
local SOON = {
    ["mouse button held"] = true, ["mouse over a window"] = true, ["NPC window open"] = true,
    ["in combat"] = true, ["flying"] = true, ["already scanning"] = true, ["no map position"] = true,
    ["aiming a spell"] = true, ["casting"] = true, ["looting"] = true, ["unit under the mouse"] = true,
}
-- A scan you cut short (a click, the cursor on the move, a window): none asked for after it,
-- it would take the mouse from you again. What it did not read, the next one reads.
local YOURS = {
    ["mouse button held"] = true, ["mouse over a window"] = true, ["NPC window open"] = true,
    ["mouse on the minimap"] = true, ["aiming a spell"] = true, ["mouse near the screen's edge"] = true,
}

-- The nodes.
local MERGE     = 15    -- yards: a node seen again within this keeps its place, averaged
local AVERAGE   = 8     -- scans the average runs over
local SKIP      = 5     -- yards: the node you are standing at is passed over
local KEEP      = 5     -- yards: another node must be this much closer to take over
local FOLLOW    = 0.05  -- seconds between updates of distances and choices (20 per second)
local GLIDE     = 20    -- per second: how fast a moved node's icon catches up, a 35 ms half-life
local SETTLED   = 0.0005 -- radians: closer than this, it is there

-- The look, at the size settings' 100%.
local ICON_WIDTH = 30
local ARROW_SIZE = 16   -- the art's square; the dart inside it is 13 by 10
local FONT_SIZE = 12
local UNIT = GetLocale() == "frFR" and "m" or "yd"
local ARROW = "Interface\\AddOns\\SuspicionsPack\\Media\\NodeRadar\\arrow.png"
local MAX_NODES = 8     -- the settings page's limit
-- The settings page's Preview, up to MAX_NODES: a name and a way, in radians.
local SAMPLES = {
    { "Peacebloom", 0.9 }, { "Copper Vein", 3 }, { "Silverleaf", 5 }, { "Tin Vein", 2 },
    { "Mageroyal", 4 }, { "Silver Vein", 0.1 }, { "Briarthorn", 5.6 }, { "Iron Deposit", 1.5 },
}

-- ============================================================
-- State
-- ============================================================
local active   = false
local inCombat = false
local moving   = false
local previewing = false

local nodes  = {}        -- the last scan's nodes
local lastId = 0         -- each node's id, kept by Smooth from one scan to the next
local target = nil       -- the nearest node shown, in front
local others = {}        -- the other nodes, nearest first, reused at every update
local range  = nil       -- yards: the setting or the minimap's reach, whichever is less
local viewRadius = nil   -- the minimap's reach at the last scan
local finderOn = nil     -- nil until asked
local skills = {}        -- [kind] = skill level, false if the game will not say
local unknown, unknownCount = {}, 0   -- names seen on the minimap that are not nodes

local hits     = {}      -- the running scan's answers: { key, map, mx, my, gray }
local lastScan = nil     -- what the last one found, for /spack radar status
local lastStart = nil    -- when and where the last scan started: { time, map, x, y }
local pending  = false   -- something asks for a scan even standing still
local unread   = false   -- places on the minimap never read: the next scan at the clock, even standing still
local comparing = nil    -- /spack radar compare: when the copy beside the minimap goes; no scan till then
local refusal  = nil     -- why the last try did not start
local phase    = 0       -- the honeycomb's shift, turned each scan
local scheduled = 0      -- the live timer's number: an older one does nothing
local scanDue = nil      -- when it fires
local useNodeSight = false -- NodeSight scans; its symbols are read instead

local frame, ticker
local frameOn = false
local slots = {}         -- one per node on screen, the nearest first; each remembers
                         -- what it shows, so only changes reach the client
local StartScan
local Dismiss

-- ============================================================
-- The game
-- ============================================================
-- Facing in radians (counterclockwise from north), or nil.
local function Facing()
    local facing = GetPlayerFacing()
    if _issecretvalue(facing) then return nil end
    return facing
end

-- A node seen on another map (you crossed into the next zone, or into a place with a map of
-- its own): its place on this map, through the world's coordinates, so it still counts. False
-- when the game cannot say (another continent); not asked again until the map changes.
local function Rebase(node, map)
    if node.map == map then return true end
    if node.stuck == map then return false end
    local toWorld, toMap, x, y = C_Map.GetWorldPosFromMapPos, C_Map.GetMapPosFromWorldPos, nil, nil
    if toWorld and toMap and CreateVector2D then
        local ok, continent, world = pcall(toWorld, node.map, CreateVector2D(node.mx, node.my))
        if ok and continent and world and not _issecretvalue(continent) and not _issecretvalue(world) then
            local okMap, _, place = pcall(toMap, continent, world, map)
            if okMap and place and not _issecretvalue(place) then x, y = place:GetXY() end
        end
    end
    if _issecretvalue(x) or _issecretvalue(y) or type(x) ~= "number" or type(y) ~= "number" then
        node.stuck = map
        return false
    end
    node.map, node.mx, node.my, node.stuck = map, x, y, nil
    return true
end

-- Map, your place on it (0 to 1) and its size in yards; nil if unknown.
local function MapPosition()
    local map = C_Map.GetBestMapForUnit("player")
    if _issecretvalue(map) or not map then return nil end
    local position = C_Map.GetPlayerMapPosition(map, "player")
    if _issecretvalue(position) or not position then return nil end
    local x, y = position:GetXY()
    if _issecretvalue(x) or _issecretvalue(y) or not x or not y then return nil end
    local width, height = C_Map.GetMapWorldSize(map)
    if _issecretvalue(width) or _issecretvalue(height) or not width or not height
        or width <= 0 or height <= 0 then return nil end
    return map, x, y, width, height
end

-- Is a finder we want on? Yes if the game will not say.
local function ReadFinders()
    local db = NR:GetDB()
    for index = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(index)
        if _issecretvalue(info) then return true end
        if info then
            local spell, on = info.spellID, info.active
            if _issecretvalue(spell) or _issecretvalue(on) then return true end
            local kind = Data.finders[spell]
            if on and ((kind == "herb" and db.herbs) or (kind == "ore" and db.ore)) then return true end
        end
    end
    return false
end

-- Which finders are on, as text: a tracking change that is not about them (the scan turning
-- the quest areas off and on) asks for no scan. "?" if the game will not say.
local function FinderKinds()
    local kinds = ""
    for index = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(index)
        if _issecretvalue(info) then return "?" end
        if info then
            local spell, on = info.spellID, info.active
            if _issecretvalue(spell) or _issecretvalue(on) then return "?" end
            if on and Data.finders[spell] then kinds = kinds .. Data.finders[spell] end
        end
    end
    return kinds
end
local trackedKinds = nil

-- Your skill for a kind of node, false if the game will not say.
local function Skill(kind)
    local known = skills[kind]
    if known ~= nil then return known end
    known = false
    local info = C_SkillInfo.GetSkillLineInfoByID(Data.skillLine[kind])
    if not _issecretvalue(info) and info then
        local rank, bonus = info.rank, info.modifier
        if not _issecretvalue(rank) and not _issecretvalue(bonus) and type(rank) == "number" then
            known = rank + (type(bonus) == "number" and bonus or 0)
        end
    end
    skills[kind] = known
    return known
end

-- A round minimap needs fewer points. EllesmereUI comes first: its minimap replaces
-- the stock one.
local function MinimapIsRound()
    local ui = EllesmereUI
    local module = type(ui) == "table" and type(ui._ModuleNS) == "table" and ui._ModuleNS.EllesmereUIMinimap
    if type(module) == "table" and type(module.MinimapShape) == "function" then
        local ok, shape = pcall(module.MinimapShape)
        if ok and (shape == "square" or shape == "rectangular") then return false end
        if ok and (shape == "circle" or shape == "textured_circle") then return true end
    end
    if GetMinimapShape then
        local ok, shape = pcall(GetMinimapShape)
        return not ok or shape == nil or shape == "ROUND"
    end
    return true
end

-- ============================================================
-- Reading the minimap tooltip
-- ============================================================
-- Gray text means a node in a cave.
local function IsGray(r, g, b)
    if _issecretvalue(r) or _issecretvalue(g) or _issecretvalue(b) or not r or not g or not b then return false end
    return math.abs(r - g) < 0.1 and math.abs(g - b) < 0.1 and r < 0.9
end

local function Clean(text)
    text = text:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return (text:match("^%s*(.-)%s*$"))
end

-- A line's names, one per row, kept by text: the same lines come back on every scan.
local lines, lineCount = {}, 0
local function NamesIn(text)
    local list = lines[text]
    if list then return list end
    list = {}
    for raw in text:gmatch("[^\n]+") do
        local r, g, b = raw:match("|c%x%x(%x%x)(%x%x)(%x%x)")
        local name = Clean(raw)
        if name ~= "" then
            list[#list + 1] = {
                name = name, key = Key(name),
                gray = r and IsGray(tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255) or nil,
            }
        end
    end
    if lineCount >= MAX_LINES then lines, lineCount = {}, 0 end
    lines[text] = list
    lineCount = lineCount + 1
    return list
end

-- What is a name doing on the minimap? Quest progress ("Peacebloom 3/8") is no name.
local function NoteUnknown(name)
    if unknown[name] or unknownCount >= MAX_UNKNOWN or name:find("[%d:/]") then return end
    unknown[name] = true
    unknownCount = unknownCount + 1
end

-- One minimap answer from the scan, and the map place it was read at: the nodes it names.
local function Collect(data, map, mx, my)
    local rows = data.lines
    for i = 1, #rows do
        local row = rows[i]
        local text = row.leftText
        if not _issecretvalue(text) and text then
            local color = row.leftColor
            local rowGray = not _issecretvalue(color) and color and IsGray(color.r, color.g, color.b)
            local list = NamesIn(text)
            for n = 1, #list do
                local entry = list[n]
                if NODES[entry.key] then
                    local gray = entry.gray
                    if gray == nil then gray = rowGray end
                    hits[#hits + 1] = { key = entry.key, map = map, mx = mx, my = my, gray = gray and true or false }
                else
                    NoteUnknown(entry.name)
                end
            end
        end
    end
end

-- ============================================================
-- From answers to nodes
-- ============================================================
-- Answers of one name within GROUP yards of a group's middle join it, or within the width a
-- dot answers across when that is more (zoomed out, two points that see one dot can be 33
-- yards apart); each group is a node, at the middle of its answers, in a cave when most of
-- them said so.
local function Gather(width, height)
    local near = max(GROUP, Scan.Last().wide or 0)
    local groups = {}
    for _, hit in ipairs(hits) do
        local into
        for _, g in ipairs(groups) do
            if g.key == hit.key and g.map == hit.map
                and ((g.mx - hit.mx) * width) ^ 2 + ((g.my - hit.my) * height) ^ 2 < near * near then
                into = g
                break
            end
        end
        if into then
            into.n = into.n + 1
            into.mx = into.mx + (hit.mx - into.mx) / into.n
            into.my = into.my + (hit.my - into.my) / into.n
            if hit.gray then into.gray = into.gray + 1 end
        else
            groups[#groups + 1] = { key = hit.key, map = hit.map, mx = hit.mx, my = hit.my, n = 1, gray = hit.gray and 1 or 0 }
        end
    end
    local found = {}
    for _, g in ipairs(groups) do
        lastId = lastId + 1
        found[#found + 1] = {
            key = g.key, info = NODES[g.key], map = g.map, count = 1, id = lastId,
            gray = g.gray * 2 > g.n, mx = g.mx, my = g.my,
        }
    end
    return found
end

-- The node found again, so a place does not jump between scans and the radar stays on it:
-- within MERGE yards, or the width a dot answers across when that is more (zoomed out, the
-- next scan's shifted points see one dot that far from where the last ones did).
-- Returns the old nodes it matched.
local function Smooth(found, before, width, height)
    local merge = max(MERGE, Scan.Last().wide or 0)
    local used = {}
    for _, node in ipairs(found) do
        local best, gap
        for _, old in ipairs(before) do
            if old.map == node.map and old.key == node.key and not used[old] then
                local d = ((old.mx - node.mx) * width) ^ 2 + ((old.my - node.my) * height) ^ 2
                if d < merge * merge and (not gap or d < gap) then best, gap = old, d end
            end
        end
        if best then
            used[best] = true
            local n = min(best.count, AVERAGE)
            node.mx = (best.mx * n + node.mx) / (n + 1)
            node.my = (best.my * n + node.my) / (n + 1)
            node.count = n + 1
            node.id = best.id
            node.picked = best.picked
            node.dismissed = best.dismissed
            if best == target then target = node end
        end
    end
    if target then
        local still = false
        for _, node in ipairs(found) do
            if node == target then still = true; break end
        end
        if not still then target = nil end
    end
    return used
end

-- ============================================================
-- The display
-- ============================================================
-- The first slot is the nearest node's: on top of the others, and the only one with a
-- distance. The arrows are on the frame itself, so under every icon.
local function MakeSlot(index)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(1, 1)
    -- A right-click on an icon takes its node off the radar (WaypointUI's right-click to
    -- clear). The left button passes through to the world, and no hover is taken.
    holder:EnableMouse(false)
    holder:SetMouseClickEnabled(true)
    if holder.SetPassThroughButtons then holder:SetPassThroughButtons("LeftButton") end
    holder:SetScript("OnMouseDown", function(_, button)
        if button == "RightButton" then Dismiss(index) end
    end)
    holder:SetFrameLevel(frame:GetFrameLevel() + MAX_NODES + 1 - index)
    -- Both off the pixel grid: they move by fractions of a pixel, and a snapped texture
    -- would step a whole one at a time, and shimmer as it turns.
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER", holder, "CENTER")
    icon:SetTexelSnappingBias(0)
    icon:SetSnapToPixelGrid(false)
    local arrow = frame:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(ARROW)
    arrow:SetTexelSnappingBias(0)
    arrow:SetSnapToPixelGrid(false)
    local slot = { holder = holder, icon = icon, arrow = arrow, on = true, arrowOn = true }
    if index == 1 then
        local label = holder:CreateFontString(nil, "OVERLAY")
        SP.SetFontSafe(label, SP.ResolveFont("Expressway"), FONT_SIZE, "OUTLINE")
        label:SetPoint("TOP", icon, "BOTTOM", 0, -1)
        slot.label = label
    end
    slots[index] = slot
    return slot
end

local function EnsureFrames()
    if frame then return end
    frame = CreateFrame("Frame", "SP_NodeRadar", UIParent)
    frame:SetSize(1, 1)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(false)
    frame:Hide()
    MakeSlot(1)
end

local function ShowFrame()
    if not frameOn then
        frameOn = true
        frame:Show()
    end
end

local function HideFrame()
    SP.Tick.Remove(KEY_DRAW)
    if frameOn then
        frameOn = false
        frame:Hide()
    end
end

-- Every slot from this one on.
local function HideSlots(first)
    for i = first, #slots do
        local slot = slots[i]
        if slot.on then
            slot.on, slot.arrowOn = false, false
            slot.holder:Hide()
            slot.arrow:Hide()
        end
    end
end

local function ShowPicture(slot, info)
    if slot.info == info then return end
    slot.info = info
    slot.icon:SetAtlas(Data.symbol[info.kind].atlas)
    -- Gray first: a colour on the gold art would come out as a muddy mix of both.
    slot.icon:SetDesaturated(true)
    slot.icon:SetVertexColor(info.r, info.g, info.b)
    slot.arrow:SetVertexColor(info.r, info.g, info.b)
end

local function SizeIcon(slot, info, width)
    local height = floor(width * Data.symbol[info.kind].ratio + 0.5)
    if slot.width == width and slot.height == height then return end
    slot.width, slot.height = width, height
    slot.icon:SetSize(width, height)
    slot.holder:SetSize(width, height)   -- what a right-click hits
end

-- The icon and its arrow where the slot's angle puts them, if it moved: its node's way
-- from north, plus your facing. Not rounded: the textures are off the pixel grid, so they
-- glide instead of stepping a pixel at a time. The arrow's art points up, and SetRotation
-- turns counterclockwise.
local function Place(slot, facing)
    local way = slot.world + facing
    if way == slot.drawn then return end
    slot.drawn = way
    local s, c = sin(way), cos(way)
    slot.holder:SetPoint("CENTER", frame, "CENTER", slot.orbit * s, slot.orbit * c)
    if slot.arrowOn then
        slot.arrow:SetPoint("CENTER", frame, "CENTER", slot.at * s, slot.at * c)
        slot.arrow:SetRotation(-way)
    end
end

-- One node in a slot. Yards away, its way in radians clockwise from north, and its id,
-- which stays the same from one scan to the next. A new node is put straight in place; the
-- same node, moved, glides there (DrawStep).
local function Assign(index, info, yards, world, id)
    local db = NR:GetDB()
    local slot = slots[index] or MakeSlot(index)
    if not slot.on then
        slot.on = true
        slot.holder:Show()
    end
    local part = index == 1 and 1 or db.otherScale / 100
    local full = floor(ICON_WIDTH * db.scale / 100 + 0.5)
    SizeIcon(slot, info, floor(full * part + 0.5))
    ShowPicture(slot, info)
    -- The arrow halfway from the middle to the nearest icon's edge: one circle for all.
    local at = max(0, (db.orbit - full / 2) / 2)
    if db.orbit ~= slot.orbit or at ~= slot.at then
        slot.orbit, slot.at, slot.drawn = db.orbit, at, nil
    end
    if db.showArrows then
        local size = floor(ARROW_SIZE * db.arrowScale / 100 * part + 0.5)
        if size ~= slot.arrowSize then
            slot.arrowSize = size
            slot.arrow:SetSize(size, size)
        end
        if not slot.arrowOn then
            slot.arrowOn, slot.drawn = true, nil
            slot.arrow:Show()
        end
    elseif slot.arrowOn then
        slot.arrowOn = false
        slot.arrow:Hide()
    end
    if id ~= slot.id then
        slot.id, slot.world = id, world
    end
    slot.goal = world
    if slot.label then
        local text = db.showDistance and (floor(yards + 0.5) .. " " .. UNIT) or ""
        if text ~= slot.text then
            slot.text = text
            slot.label:SetText(text)
        end
    end
end

-- Every frame while icons are shown: your facing, read again, so turning is smooth, and
-- each node's way eased towards the last update's, so the 20 updates a second and the
-- scans' corrections do not show as jumps. Facing is one cheap call; the map position,
-- which makes a table each time, stays in Follow.
local function DrawStep(elapsed)
    local facing = Facing()
    if not facing then return end
    local ease = 1 - exp(-elapsed * GLIDE)
    for i = 1, #slots do
        local slot = slots[i]
        if slot.on then
            local gap = (slot.goal - slot.world + pi) % (2 * pi) - pi
            if gap > SETTLED or gap < -SETTLED then
                slot.world = slot.world + gap * ease
            else
                slot.world = slot.goal
            end
            Place(slot, facing)
        end
    end
end

-- ============================================================
-- Following
-- ============================================================
local function Wanted(info, db)
    if info.kind == "herb" then
        if not db.herbs then return false end
    elseif not db.ore then
        return false
    end
    local skill = Skill(info.kind)
    return skill == false or info.skill <= skill
end

local function Eligible(node, db)
    local yards = node.yards
    return yards and yards >= SKIP and yards <= range and not node.gray and not node.dismissed
        and Wanted(node.info, db)
end

-- The nearest; the one shown stays until another is clearly nearer, or the icon would
-- jump between two nodes at about the same distance.
local function PickTarget(db)
    local best
    for i = 1, #nodes do
        local node = nodes[i]
        if Eligible(node, db) and (not best or node.yards < best.yards) then best = node end
    end
    if target and best and best ~= target and Eligible(target, db) and best.yards > target.yards - KEEP then
        return target
    end
    return best
end

local function ByRank(a, b) return a.rank < b.rank end

-- The next nearest after the target, as many as there is room for; how many. One already
-- shown counts as KEEP yards nearer, for the same reason as above.
local function PickOthers(db)
    local count = 0
    for i = 1, #nodes do
        local node = nodes[i]
        if node ~= target and Eligible(node, db) then
            count = count + 1
            others[count] = node
            node.rank = node.yards - (node.picked and KEEP or 0)
        end
    end
    for i = #others, count + 1, -1 do others[i] = nil end
    table.sort(others, ByRank)
    for i = 1, #nodes do nodes[i].picked = false end
    count = min(count, db.maxNodes - 1)
    for i = 1, count do others[i].picked = true end
    if target then target.picked = true end
    return count
end

local function Follow()
    if previewing then return false end
    if not active or not nodes[1] or not range then
        HideFrame()
        target = nil
        return false
    end
    local db = NR:GetDB()
    local map, x, y, width, height = MapPosition()
    local facing = Facing()
    if not map or not facing then
        HideFrame()
        return false
    end
    for i = 1, #nodes do
        local node = nodes[i]
        if Rebase(node, map) then
            local east, north = (node.mx - x) * width, (y - node.my) * height
            node.yards = sqrt(east * east + north * north)
            node.world = atan2(east, north)
        else
            node.yards = nil
        end
    end
    target = PickTarget(db)
    local count = PickOthers(db)
    if target then
        Assign(1, target.info, target.yards, target.world, target.id)
        slots[1].node = target
        for i = 1, count do
            local node = others[i]
            Assign(i + 1, node.info, node.yards, node.world, node.id)
            slots[i + 1].node = node
        end
        HideSlots(count + 2)
        for i = 1, count + 1 do Place(slots[i], facing) end
        ShowFrame()
        SP.Tick.Add(KEY_DRAW, DrawStep)
    else
        HideFrame()
    end
    return true
end

-- The node an icon shows, right-clicked: off the radar, and kept off when a scan finds it
-- again (it keeps the flag through Smooth); a scan that reads its place and finds it gone
-- drops it as any other.
Dismiss = function(index)
    local slot = slots[index]
    local node = slot and slot.on and slot.node
    if previewing or not node then return end
    node.dismissed = true
    if target == node then target = nil end
    Follow()
end

local function StartFollowing()
    if not active or not nodes[1] then return end
    if not ticker then ticker = SP.Tick.NewAnimTicker(Follow, FOLLOW, "NodeRadar", "follow") end
    ticker.Start()
    Follow()
end

local function ClearNodes()
    if nodes[1] then nodes = {} end
    target = nil
    if not previewing and frame then HideFrame() end
end

-- ============================================================
-- Scanning
-- ============================================================
local function Schedule(delay)
    scheduled = scheduled + 1
    local number = scheduled
    scanDue = GetTime() + delay
    C_Timer.After(delay, function()
        if number ~= scheduled then return end
        scanDue = nil
        StartScan()
    end)
end

-- Something happened: look within this many seconds, sooner if a look is due anyway.
local function Wake(delay)
    if not active or useNodeSight or Scan.Running() then return end
    if scanDue and scanDue - GetTime() <= delay then return end
    Schedule(delay)
end

-- The minimap's reach, and the radar's: the setting or the minimap's, whichever is less.
-- A square minimap shows further than its radius in the corners.
local function SetRange()
    local radius = C_Minimap.GetViewRadius()
    if _issecretvalue(radius) or not radius or radius <= 0 then return false end
    viewRadius = MinimapIsRound() and radius or radius * SQUARE_REACH
    range = min(NR:GetDB().range, viewRadius)
    return true
end

-- The nodes found, smoothed onto the ones found again. An old node not found again stays
-- while the scan did not read its place (a scan reads only part of the minimap) and it is
-- within the minimap's reach; saw(node) says whether its place was read.
local function TakeNodes(found, width, height, saw)
    local map, x, y = MapPosition()
    if map then
        for _, node in ipairs(found) do Rebase(node, map) end
        for _, old in ipairs(nodes) do Rebase(old, map) end
    end
    local used = Smooth(found, nodes, width, height)
    local reach = viewRadius or 0
    for _, old in ipairs(nodes) do
        if not used[old] and old.map == map and not saw(old)
            and ((old.mx - x) * width) ^ 2 + ((old.my - y) * height) ^ 2 <= reach * reach then
            found[#found + 1] = old
        end
    end
    nodes = found
    if nodes[1] then StartFollowing() else ClearNodes() end
end

-- A scan ended: its answers become the nodes. Then keep looking while one could be due.
local function FinishScan(why)
    local map, _, _, width, height = MapPosition()
    if map and SetRange() then
        local found = Gather(width, height)
        lastScan = ("%d node(s), %s, %d answer(s)"):format(#found, tostring(why), #hits)
        TakeNodes(found, width, height, function(old) return Scan.Saw(old.map, old.mx, old.my, width, height) end)
    end
    hits = {}
    -- Cut short by combat, a zoom, the minimap hidden: the next one is asked for, even
    -- standing still. Not when you cut it short.
    if why ~= "done" and why ~= "error" and not YOURS[why] then pending = true end
    -- Places on the minimap never read yet (a scan reads a few): read on, even standing still,
    -- a moment after a whole scan, at the usual clock after one you cut short.
    if why ~= "error" and (Scan.Last().unread or 0) > 0 then
        if why == "done" then pending = true else unread = true end
    end
    Wake(CHECK)
end

-- A scan stopped from here: what it read still counts if the place it was read in is still
-- there (combat), not after a loading screen.
local function CutScan(why, keep)
    if not Scan.Running() then return end
    Scan.Stop(why)
    if keep and hits[1] then FinishScan(why) else hits = {} end
end

-- Is a scan due? Every scanYards walked, at most every scanSeconds; something that asked for
-- one (a zoom, a finder, a loading screen, a scan cut short) waits only a moment, even
-- standing still. A second value: the seconds until the clock allows one.
local function Due(db)
    if not active or useNodeSight or Scan.Running() or Scan.Failed() then return false end
    if inCombat and not db.scanCombat then return false end
    if finderOn == nil then finderOn = ReadFinders() end
    if not finderOn then
        ClearNodes()
        return false
    end
    if lastStart then
        local wait = lastStart.time + (pending and ASKED or db.scanSeconds) - GetTime()
        if wait > 0 then return false, wait end
    end
    if pending or unread or not lastStart then return true end
    local map, x, y, width, height = MapPosition()
    if not map then return false end
    if map ~= lastStart.map then return true end
    -- The yards walked are owed even if you stopped since: the scan runs once the clock allows.
    local east, north = (x - lastStart.x) * width, (y - lastStart.y) * height
    return east * east + north * north >= db.scanYards * db.scanYards
end

StartScan = function()
    -- The copy beside the minimap for a screenshot: a scan would take it back.
    if comparing then
        refusal = "comparing the copy"
        Schedule(CHECK)
        return
    end
    local db = NR:GetDB()
    local due, wait = Due(db)
    if not due then
        if wait then
            Schedule(wait)
        elseif moving and active and not useNodeSight and not Scan.Running() and not Scan.Failed() then
            Schedule(CHECK)
        end
        return
    end
    local map, x, y = MapPosition()
    hits = {}
    phase = (phase + 1) % 3
    local why = Scan.Start({
        position = MapPosition, read = Collect, done = FinishScan, nodes = nodes,
        reach = db.range, round = MinimapIsRound(), combat = db.scanCombat, phase = phase,
        -- The quest areas off for the scan: remembered, so a logout mid-scan puts them back.
        questAreas = function(on) db._questOff = (not on) or nil end,
    })
    if why then
        refusal = why
        Schedule(SOON[why] and CHECK or RETRY)
        return
    end
    refusal, pending, unread = nil, false, false
    lastStart = { time = GetTime(), map = map, x = x, y = y }
end

-- NodeSight's symbols after each of its scans (NodeSightAPI.RegisterCallback): herbs and ore
-- it names the way the radar knows them.
local function FromNodeSight(symbols)
    if not active or not useNodeSight or type(symbols) ~= "table" then return end
    local map, _, _, width, height = MapPosition()
    if not map or not SetRange() then return end
    local found = {}
    for _, symbol in ipairs(symbols) do
        local key = type(symbol) == "table" and type(symbol.name) == "string" and Key(symbol.name)
        if key and NODES[key] and symbol.map and symbol.x and symbol.y then
            lastId = lastId + 1
            found[#found + 1] = { key = key, info = NODES[key], map = symbol.map, mx = symbol.x, my = symbol.y,
                count = 1, id = lastId, gray = false }
        end
    end
    lastScan = ("%d node(s) from NodeSight"):format(#found)
    TakeNodes(found, width, height, function() return true end)
end

local nodeSightHooked = false
local function UseNodeSight()
    local api = _G.NodeSightAPI
    if type(api) ~= "table" or type(api.RegisterCallback) ~= "function" or type(api.GetSymbols) ~= "function" then
        return false
    end
    if not nodeSightHooked then
        nodeSightHooked = true
        api.RegisterCallback(FromNodeSight)
    end
    return true
end

-- ============================================================
-- Events
-- ============================================================
function NR:OnEnteringWorld()
    moving = false
    hits = {}
    ClearNodes()
    Scan.Forget()
    pending = true
    if useNodeSight then
        local ok, symbols = pcall(NodeSightAPI.GetSymbols)
        if ok then FromNodeSight(symbols) end
        return
    end
    Wake(2)
end

function NR:OnLeavingWorld()
    CutScan("loading screen", false)
end

function NR:OnCombatStart()
    inCombat = true
    if not self:GetDB().scanCombat then CutScan("combat", true) end
end

-- A fight over: one scan, even standing still (NodeSight 1.10 does the same). Nodes near a
-- fight may have been gathered meanwhile, or come up.
function NR:OnCombatEnd()
    inCombat = false
    pending = true
    Wake(0.5)
end

function NR:OnStartedMoving()
    moving = true
    Wake(CHECK)
end

function NR:OnStoppedMoving()
    moving = false
end

-- A running scan sees the zoom itself, and ends; the next one is asked for either way.
function NR:OnZoom()
    pending = true
    Wake(0.3)
end

-- A finder switched on or off asks for a scan; another tracking change does not (the scan's
-- own quest areas, off then on, would ask for one after every scan).
function NR:OnTracking()
    local kinds = FinderKinds()
    if kinds == trackedKinds and kinds ~= "?" then return end
    trackedKinds = kinds
    finderOn = nil
    Scan.Forget()
    pending = true
    Wake(0.3)
end

-- Loot closed: you may have just gathered the node you stand at. It goes, rather than a scan
-- standing still; one still there comes back with the next scan.
function NR:OnLootClosed()
    if not nodes[1] then return end
    local kept, gone = {}, false
    for _, node in ipairs(nodes) do
        if node.yards and node.yards < PICKED then gone = true else kept[#kept + 1] = node end
    end
    if not gone then return end
    nodes = kept
    if target and not (target.yards and target.yards >= PICKED) then target = nil end
    if nodes[1] then Follow() else ClearNodes() end
end

function NR:OnSkills()
    skills = {}
end

-- ============================================================
-- /spack radar compare
-- ============================================================
-- The copy beside the real minimap, at the same size and with the tint a scan gives it, so a
-- screenshot shows both at once: its tint was measured in one place only (Thousand Needles,
-- by day), and in Tirisfal the real minimap was bluer. What decides the colour is printed
-- with it. Again, or after 30 seconds, and it goes; no scan meanwhile.
local COMPARE_KEY, COMPARE_SECONDS, COMPARE_GAP = "NodeRadarCompare", 30, 12

local function StopCompare()
    comparing = nil
    SP.Tick.Remove(COMPARE_KEY)
    if not Scan.Running() then Copy.Hide() end
end

local function CompareStep()
    if not comparing or GetTime() > comparing then return StopCompare() end
    local map, x, y, width, height = MapPosition()
    Copy.Update(nodes, map, x, y, width, height)
end

function NR.Comparing() return comparing ~= nil end

function NR.Compare()
    if comparing then
        StopCompare()
        print("SuspicionsPack: node radar: the copy is gone.")
        return
    end
    local can, why = Copy.CanDraw()
    local map, x, y, width, height = MapPosition()
    if not can or not map then
        print(("SuspicionsPack: node radar: no copy here (%s)."):format(tostring(why or "no map position")))
        return
    end
    -- A scan running has the minimap away: it comes home first.
    CutScan("compare", true)
    local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
    if not left or _issecretvalue(left) or _issecretvalue(bottom) then
        print("SuspicionsPack: node radar: no copy here (the minimap's place is not known).")
        return
    end
    local w, h = Minimap:GetWidth(), Minimap:GetHeight()
    Copy.Show(left - w - COMPARE_GAP, bottom, w, h, Minimap:GetFrameStrata(), Minimap:GetFrameLevel() + 1,
        MinimapIsRound(), nodes, map, x, y, width, height)
    Copy.SetAlpha(1)
    comparing = GetTime() + COMPARE_SECONDS
    SP.Tick.Add(COMPARE_KEY, CompareStep)
    local _, tx, ty, u, v = Copy.Where()
    local r, g, b = Copy.Tint()
    local hours, minutes = 0, 0
    if GetGameTime then hours, minutes = GetGameTime() end
    print(("SuspicionsPack: node radar: the copy, left of the minimap, for %d s (/spack radar compare again takes it away). Take your screenshot now."):format(COMPARE_SECONDS))
    print(("  %s, map %s, tile %d,%d at %.3f,%.3f, game time %02d:%02d, indoors %s, tint %.3f %.3f %.3f"):format(
        tostring(GetZoneText and GetZoneText() or "?"), tostring(map), tx, ty, u, v,
        tonumber(hours) or 0, tonumber(minutes) or 0, tostring(IsIndoors()), r, g, b))
end

-- ============================================================
-- Lifecycle
-- ============================================================
local function ApplyPosition()
    local db = NR:GetDB()
    frame:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
end

local function DrawPreview()
    local db = NR:GetDB()
    -- Still: the samples do not turn with you.
    SP.Tick.Remove(KEY_DRAW)
    for i = 1, db.maxNodes do
        local sample = SAMPLES[i]
        Assign(i, NODES[Key(sample[1])], db.range / 2, sample[2], -i)
        Place(slots[i], 0)
    end
    HideSlots(db.maxNodes + 1)
    ShowFrame()
end

-- Runs again on every settings change.
function NR:Activate()
    EnsureFrames()
    ApplyPosition()
    active = true
    inCombat = InCombatLockdown() and true or false
    finderOn = nil
    if viewRadius then range = min(self:GetDB().range, viewRadius) end
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
    self:RegisterEvent("PLAYER_STARTED_MOVING", "OnStartedMoving")
    self:RegisterEvent("PLAYER_STOPPED_MOVING", "OnStoppedMoving")
    self:RegisterEvent("MINIMAP_UPDATE_ZOOM", "OnZoom")
    self:RegisterEvent("MINIMAP_UPDATE_TRACKING", "OnTracking")
    self:RegisterEvent("LOOT_CLOSED", "OnLootClosed")
    self:RegisterEvent("SKILL_LINES_CHANGED", "OnSkills")
    self:RegisterEvent("PLAYER_LEAVING_WORLD", "OnLeavingWorld")
    trackedKinds = FinderKinds()
    -- A scan cut short by a logout left the quest areas off: back on.
    local db = self:GetDB()
    if db._questOff and Scan.QuestAreasBack() then db._questOff = nil end
    useNodeSight = UseNodeSight()
    if previewing then DrawPreview() end
    StartFollowing()
    if useNodeSight then
        local ok, symbols = pcall(NodeSightAPI.GetSymbols)
        if ok then FromNodeSight(symbols) end
    else
        pending = true
        Wake(0.2)
    end
end

function NR:Deactivate()
    active, previewing, moving = false, false, false
    scheduled = scheduled + 1
    scanDue, unread = nil, false
    if comparing then StopCompare() end
    CutScan("off", false)
    Scan.Forget()
    if ticker then ticker.Stop() end
    ClearNodes()
    if frame then HideFrame() end
end

-- The settings page's Preview: icons where you can see them, without any node.
function NR:SetPreview(on)
    if on and not active then return end
    previewing = on and true or false
    if previewing then
        DrawPreview()
    elseif nodes[1] then
        StartFollowing()
    elseif frame then
        HideFrame()
    end
end

function NR:IsPreviewing()
    return previewing
end

-- /spack radar status: why an icon is or is not there, at the moment you ask.
function NR.PrintStatus()
    local db = NR:GetDB()
    print(("SuspicionsPack: node radar: on %s, %s, failed %s, combat %s, finder %s, minimap shown %s"):format(
        tostring(active), useNodeSight and "NodeSight scans" or "own scan", tostring(Scan.Failed()),
        tostring(inCombat), tostring(finderOn), tostring(Minimap:IsVisible())))
    print(("  reach %s yd, range setting %d yd, used %s yd, %d node(s), scanning %s, last scan %s"):format(
        tostring(viewRadius), db.range, tostring(range), #nodes, tostring(Scan.Running()), tostring(lastScan)))
    local info = Scan.Last()
    if not useNodeSight then
        print(("  last try: %s; last scan ended %s after %.1f s, %s point(s) placed, %s read, %s answered, %s again, minimap put back by another addon %s time(s); every %d yd, at most every %d s, in combat %s"):format(
            refusal and ("not started, " .. refusal) or "started", tostring(info.ended), info.seconds or 0,
            tostring(info.placed), tostring(info.reads), tostring(info.answers), tostring(info.again),
            tostring(info.moved), db.scanYards, db.scanSeconds, tostring(db.scanCombat)))
        print(("  points: %s to read of %s in reach, %s read lately, %s over known nodes, %s left for the next scans, %s never read"):format(
            tostring(info.points), tostring(info.candidates), tostring(info.fresh), tostring(info.known),
            tostring(info.left), tostring(info.unread)))
        print(("  read empty, what had the mouse: %s"):format(tostring(info.empty)))
        print(("  waited for: %s"):format(tostring(info.waits)))
        print(("  moved by others during the scan: %s"):format(tostring(info.movers)))
        print(("  pieces hidden: %s, shown again by their owners and hidden again: %s time(s)"):format(
            tostring(info.hidden), tostring(info.reshown)))
        print(("  pieces copied in their place: %s drawn, %s left out (%s)"):format(
            tostring(info.copied), tostring(info.copiedOut), tostring(info.copiedWhy)))
    end
    for i = 1, #nodes do
        local node = nodes[i]
        print(("  %s: %s yd, skill %d of %s, cave %s%s%s"):format(
            node.key, node.yards and floor(node.yards + 0.5) or "other map", node.info.skill,
            tostring(Skill(node.info.kind)), tostring(node.gray),
            node == target and ", shown in front" or node.picked and ", shown" or "",
            node.dismissed and ", taken off by a right-click" or ""))
    end
end

-- /spack radar names: what the minimap named that is not in the list.
function NR.PrintUnknown()
    local list = {}
    for name in pairs(unknown) do list[#list + 1] = name end
    table.sort(list)
    if not list[1] then
        print("SuspicionsPack: node radar, no unknown name on the minimap so far.")
    else
        print("SuspicionsPack: node radar, names it does not know: " .. table.concat(list, ", "))
    end
end
