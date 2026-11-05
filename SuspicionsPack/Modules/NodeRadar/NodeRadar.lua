-- SuspicionsPack — NodeRadar (WoW: Forever only, see the .toc gate)
--
-- The nearest herbs and veins you can gather, as icons around your character, like
-- compass needles: each turns to point where its node is, stays at the same distance,
-- and has a small arrow between it and the middle. The nearest is drawn in front, full
-- size and with its distance; the others are smaller.
--
-- The game gives addons no list of nodes, but the minimap's tracking dots can be read.
-- A pretend mouse (Minimap:UpdateMouseoverAtPoint) visits a grid of points, a few per
-- frame, and the minimap tooltip names the dots under it. Points that hit the same name
-- and touch each other are one node. Its place is kept in map coordinates, so it can be
-- followed between scans.
--
-- So the radar sees what the minimap shows: it needs the minimap on screen and Find
-- Herbs or Find Minerals on, and the minimap's zoom sets how far it reaches. Up is the
-- way your character faces, not the camera.
--
-- Idle costs nothing: the scan's per-frame driver and the follow ticker both stop when
-- they have nothing to do, and with no finder on only an event starts them again.

local SP = SuspicionsPack

local NR = SP:NewSPModule("NodeRadar", "nodeRadar")
SP.NodeRadar = NR

local Data = SP.NodeRadarData
local NODES, Key = Data.nodes, Data.Key

local _issecretvalue = issecretvalue or function() return false end
local sin, cos, atan2, sqrt = math.sin, math.cos, math.atan2, math.sqrt
local floor, min, max, rad, deg = math.floor, math.min, math.max, math.rad, math.deg

-- The scan.
local STEP      = 10    -- grid spacing, minimap units
local PER_FRAME = 40    -- points probed per frame
local SCAN_WAIT = 1     -- seconds between scans while moving
local IDLE_WAIT = 2     -- and while standing still with something found
local MAX_WAIT  = 8     -- longest wait after empty scans
local RETRY     = 5     -- minimap hidden or no position: no event says when that ends
local SQUARE_REACH = 1.42 -- a square minimap's corner, per its radius
local MAX_LINES = 300   -- tooltip lines remembered
local MAX_UNKNOWN = 200 -- unknown names remembered
local KEY_SCAN  = "NodeRadarScan"
-- Grid points are keyed x * 1000 + y; these are the 8 neighbours.
local AROUND = { -1001, -1000, -999, -1, 1, 999, 1000, 1001 }

-- The nodes.
local MERGE     = 15    -- yards: a node seen again within this keeps its place, averaged
local AVERAGE   = 8     -- scans the average runs over
local SKIP      = 5     -- yards: the node you are standing at is passed over
local KEEP      = 5     -- yards: another node must be this much closer to take over
local FOLLOW    = 0.05  -- seconds between updates (20 per second)

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
local failed   = false   -- a probe threw: no more scans until a /reload
local inCombat = false
local moving   = false
local previewing = false

local nodes  = {}        -- the last scan's nodes
local target = nil       -- the nearest node shown, in front
local others = {}        -- the other nodes, nearest first, reused at every update
local range  = nil       -- yards: the setting or the minimap's reach, whichever is less
local viewRadius = nil   -- the minimap's reach at the last scan
local finderOn = nil     -- nil until asked
local skills = {}        -- [kind] = skill level, false if the game will not say
local unknown, unknownCount = {}, 0   -- names seen on the minimap that are not nodes

local scan    = nil      -- the scan in progress
local lastScan = nil     -- what the last one found, for /spack radar status
local empties = 0        -- empty scans in a row
local scheduled = 0      -- the live timer's number: an older one does nothing
local scanDue = nil      -- when it fires
local grid, gridWidth, gridRound

local frame, ticker
local frameOn = false
local slots = {}         -- one per node on screen, the nearest first; each remembers
                         -- what it shows, so only changes reach the client
local StartScan

-- ============================================================
-- The game
-- ============================================================
-- Facing in radians (counterclockwise from north), or nil.
local function Facing()
    local facing = GetPlayerFacing()
    if _issecretvalue(facing) then return nil end
    return facing
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

-- Moves the pretend mouse and records the nodes the tooltip names.
local function Probe(left, bottom, scale, point, hits)
    local x, y = floor(point / 1000) * STEP, point % 1000 * STEP
    Minimap:UpdateMouseoverAtPoint((left + x) * scale, (bottom + y) * scale)
    local data = C_TooltipInfo.GetMinimapMouseover()
    if _issecretvalue(data) or not data then return end
    local rows = data.lines
    if _issecretvalue(rows) or not rows then return end
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
                    local set = hits[entry.key]
                    if not set then
                        set = {}
                        hits[entry.key] = set
                    end
                    local gray = entry.gray
                    if gray == nil then gray = rowGray end
                    set[point] = gray and "gray" or true
                else
                    NoteUnknown(entry.name)
                end
            end
        end
    end
end

-- ============================================================
-- From points to nodes
-- ============================================================
-- Sets of touching points.
local function Groups(set)
    local groups, seen = {}, {}
    for first in pairs(set) do
        if not seen[first] then
            seen[first] = true
            local stack, keys = { first }, {}
            while #stack > 0 do
                local point = stack[#stack]
                stack[#stack] = nil
                keys[#keys + 1] = point
                for i = 1, #AROUND do
                    local other = point + AROUND[i]
                    if set[other] and not seen[other] then
                        seen[other] = true
                        stack[#stack + 1] = other
                    end
                end
            end
            groups[#groups + 1] = keys
        end
    end
    return groups
end

-- The node found again, so a place does not jump between scans and the radar stays on it.
local function Smooth(found, before, width, height)
    local used = {}
    for _, node in ipairs(found) do
        local best, gap
        for _, old in ipairs(before) do
            if old.map == node.map and old.key == node.key and not used[old] then
                local d = ((old.mx - node.mx) * width) ^ 2 + ((old.my - node.my) * height) ^ 2
                if d < MERGE * MERGE and (not gap or d < gap) then best, gap = old, d end
            end
        end
        if best then
            used[best] = true
            local n = min(best.count, AVERAGE)
            node.mx = (best.mx * n + node.mx) / (n + 1)
            node.my = (best.my * n + node.my) / (n + 1)
            node.count = n + 1
            node.picked = best.picked
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
end

-- ============================================================
-- The display
-- ============================================================
-- The first slot is the nearest node's: on top of the others, and the only one with a
-- distance. The arrows are on the frame itself, so under every icon.
local function MakeSlot(index)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(1, 1)
    holder:EnableMouse(false)
    holder:SetFrameLevel(frame:GetFrameLevel() + MAX_NODES + 1 - index)
    local icon = holder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER", holder, "CENTER")
    local arrow = frame:CreateTexture(nil, "ARTWORK")
    arrow:SetTexture(ARROW)
    -- Off the pixel grid, or a small texture shimmers as it turns.
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
end

-- The arrow, this many pixels from the middle, on the way to its node. The art points up
-- and SetRotation turns counterclockwise. Whole degrees, or every update would turn it.
local function DrawArrow(slot, way, at, size)
    local x, y = floor(at * sin(way) + 0.5), floor(at * cos(way) + 0.5)
    if x ~= slot.arrowX or y ~= slot.arrowY then
        slot.arrowX, slot.arrowY = x, y
        slot.arrow:SetPoint("CENTER", frame, "CENTER", x, y)
    end
    local turn = floor(deg(way) + 0.5)
    if turn ~= slot.turn then
        slot.turn = turn
        slot.arrow:SetRotation(-rad(turn))
    end
    if size ~= slot.arrowSize then
        slot.arrowSize = size
        slot.arrow:SetSize(size, size)
    end
    if not slot.arrowOn then
        slot.arrowOn = true
        slot.arrow:Show()
    end
end

-- One node. Yards away, and the way in radians clockwise from where your character faces.
local function DrawNode(index, info, yards, way)
    local db = NR:GetDB()
    local slot = slots[index] or MakeSlot(index)
    if not slot.on then
        slot.on = true
        slot.holder:Show()
    end
    local x, y = floor(db.orbit * sin(way) + 0.5), floor(db.orbit * cos(way) + 0.5)
    if x ~= slot.x or y ~= slot.y then
        slot.x, slot.y = x, y
        slot.holder:SetPoint("CENTER", frame, "CENTER", x, y)
    end
    local part = index == 1 and 1 or db.otherScale / 100
    local full = floor(ICON_WIDTH * db.scale / 100 + 0.5)
    SizeIcon(slot, info, floor(full * part + 0.5))
    ShowPicture(slot, info)
    if db.showArrows then
        -- Halfway from the middle to the nearest icon's edge, one circle for all of them.
        -- A whole number, or rounding puts it a pixel nearer on one side than the other.
        DrawArrow(slot, way, floor(max(0, (db.orbit - full / 2) / 2) + 0.5),
            floor(ARROW_SIZE * db.arrowScale / 100 * part + 0.5))
    elseif slot.arrowOn then
        slot.arrowOn = false
        slot.arrow:Hide()
    end
    if slot.label then
        local text = db.showDistance and (floor(yards + 0.5) .. " " .. UNIT) or ""
        if text ~= slot.text then
            slot.text = text
            slot.label:SetText(text)
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
    return yards and yards >= SKIP and yards <= range and not node.gray and Wanted(node.info, db)
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
        if node.map == map then
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
        DrawNode(1, target.info, target.yards, target.world + facing)
        for i = 1, count do
            local node = others[i]
            DrawNode(i + 1, node.info, node.yards, node.world + facing)
        end
        HideSlots(count + 2)
        ShowFrame()
    else
        HideFrame()
    end
    return true
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

-- Something happened: scan within this many seconds, sooner if one is due anyway.
local function Wake(delay)
    if not active or failed or scan then return end
    if scanDue and scanDue - GetTime() <= delay then return end
    Schedule(delay)
end

local function StopScan()
    scan = nil
    SP.Tick.Remove(KEY_SCAN)
end

-- The grid's points turned into nodes, and the next scan's wait.
local function FinishScan()
    local hits, width = scan.hits, scan.width
    StopScan()
    local radius = C_Minimap.GetViewRadius()
    local map, x, y, mapWidth, mapHeight = MapPosition()
    local rotating = C_CVar.GetCVar("rotateMinimap") == "1"
    local facing = Facing()
    if _issecretvalue(radius) or not radius or radius <= 0 or not map or (rotating and not facing) then
        ClearNodes()
        Schedule(RETRY)
        return
    end
    -- A square minimap shows further than its radius in the corners.
    viewRadius = gridRound and radius or radius * SQUARE_REACH
    range = min(NR:GetDB().range, viewRadius)
    local half = width / 2
    local found = {}
    for key, set in pairs(hits) do
        for _, keys in ipairs(Groups(set)) do
            local sumX, sumY, gray = 0, 0, 0
            for i = 1, #keys do
                local point = keys[i]
                sumX = sumX + floor(point / 1000) * STEP
                sumY = sumY + point % 1000 * STEP
                if set[point] == "gray" then gray = gray + 1 end
            end
            local dx, dy = sumX / #keys - half, sumY / #keys - half
            local yards = sqrt(dx * dx + dy * dy) / half * radius
            local bearing = atan2(dx, dy)              -- clockwise from the minimap's top
            local world = rotating and bearing - facing or bearing   -- clockwise from north
            found[#found + 1] = {
                key = key, info = NODES[key], map = map, count = 1,
                gray = gray * 2 > #keys,
                mx = x + yards * sin(world) / mapWidth,
                my = y - yards * cos(world) / mapHeight,
            }
        end
    end
    Smooth(found, nodes, mapWidth, mapHeight)
    nodes = found
    lastScan = #found .. " node(s)"
    if found[1] then
        empties = 0
        Schedule(moving and SCAN_WAIT or IDLE_WAIT)
    else
        empties = empties + 1
        Schedule(min(MAX_WAIT, SCAN_WAIT * 2 ^ empties))
    end
    if found[1] then StartFollowing() else ClearNodes() end
end

local function ProbeSome()
    local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
    local scale = Minimap:GetEffectiveScale()
    local points, hits = scan.points, scan.hits
    local last = min(scan.next + PER_FRAME - 1, #points)
    Minimap:SetUsingSoftCursor(true)
    for i = scan.next, last do
        Probe(left, bottom, scale, points[i], hits)
    end
    Minimap:SetUsingSoftCursor(false)
    scan.next = last + 1
end

-- A failed probe would fail again every frame with the pretend mouse left on. It is
-- reported once, the mouse is let go, and the radar stays off until a /reload.
local function ScanStep()
    if not scan then
        SP.Tick.Remove(KEY_SCAN)
        return
    end
    if not Minimap:IsVisible() or not Minimap:GetLeft() then
        StopScan()
        Schedule(RETRY)
        return
    end
    if not xpcall(ProbeSome, geterrorhandler()) then
        pcall(Minimap.SetUsingSoftCursor, Minimap, false)
        failed = true
        StopScan()
        ClearNodes()
        return
    end
    if scan.next > #scan.points then FinishScan() end
end

local function BuildGrid(width)
    local round = MinimapIsRound()
    if grid and gridWidth == width and gridRound == round then return grid end
    grid, gridWidth, gridRound = {}, width, round
    local half = width / 2
    for x = 0, floor(width / STEP) do
        for y = 0, floor(width / STEP) do
            local dx, dy = x * STEP - half, y * STEP - half
            if not round or dx * dx + dy * dy <= half * half then
                grid[#grid + 1] = x * 1000 + y
            end
        end
    end
    return grid
end

StartScan = function()
    if not active or scan or inCombat then return end
    if finderOn == nil then finderOn = ReadFinders() end
    if not finderOn then
        ClearNodes()
        return
    end
    if not Minimap:IsVisible() or not Minimap:GetLeft() or not MapPosition() then
        ClearNodes()
        Schedule(RETRY)
        return
    end
    local width = Minimap:GetWidth()
    scan = { points = BuildGrid(width), width = width, next = 1, hits = {} }
    SP.Tick.Add(KEY_SCAN, ScanStep)
end

-- ============================================================
-- Events
-- ============================================================
function NR:OnEnteringWorld()
    moving = false
    if scan then StopScan() end
    ClearNodes()
    Wake(1)
end

function NR:OnCombatStart()
    inCombat = true
    if scan then StopScan() end
end

function NR:OnCombatEnd()
    inCombat = false
    Wake(0.2)
end

function NR:OnStartedMoving()
    moving = true
    empties = 0
    Wake(SCAN_WAIT)
end

function NR:OnStoppedMoving()
    moving = false
end

function NR:OnZoom()
    empties = 0
    Wake(0.2)
end

function NR:OnTracking()
    finderOn = nil
    empties = 0
    Wake(0.2)
end

function NR:OnLootClosed()
    empties = 0
    Wake(0.2)
end

function NR:OnSkills()
    skills = {}
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
    for i = 1, db.maxNodes do
        local sample = SAMPLES[i]
        DrawNode(i, NODES[Key(sample[1])], db.range / 2, sample[2])
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
    if previewing then DrawPreview() end
    StartFollowing()
    Wake(0.2)
end

function NR:Deactivate()
    active, previewing, moving = false, false, false
    empties = 0
    scheduled = scheduled + 1
    scanDue = nil
    if scan then StopScan() end
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
    print(("SuspicionsPack: node radar: on %s, failed %s, combat %s (no scan), finder %s, minimap shown %s"):format(
        tostring(active), tostring(failed), tostring(inCombat),
        tostring(finderOn), tostring(Minimap:IsVisible())))
    print(("  reach %s yd, range setting %d yd, used %s yd, %d node(s), scanning %s, last scan %s"):format(
        tostring(viewRadius), db.range, tostring(range), #nodes, tostring(scan ~= nil), tostring(lastScan)))
    for i = 1, #nodes do
        local node = nodes[i]
        print(("  %s: %s yd, skill %d of %s, cave %s%s"):format(
            node.key, node.yards and floor(node.yards + 0.5) or "other map", node.info.skill,
            tostring(Skill(node.info.kind)), tostring(node.gray),
            node == target and ", shown in front" or node.picked and ", shown" or ""))
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
