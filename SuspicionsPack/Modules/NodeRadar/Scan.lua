-- SuspicionsPack — NodeRadar's minimap scan (WoW: Forever only, see the .toc gate)
--
-- Since build 70862 the minimap names only the dot under the real mouse (tasks/wow-api-notes.md,
-- 2026-11-09). So a scan moves the real minimap under the mouse, one point a frame, by its own
-- offsets, and reads the name on the next frame. Copy.lua draws the minimap's picture in its
-- place meanwhile.
--
-- The copy fades in over the minimap, still at its place, and the minimap goes once the copy
-- is fully in; at the end the minimap is back at once and the copy fades out over it
-- (NodeSight's Fade in and out: the minimap itself cannot fade, a copy over it can).
--
-- How it is hidden is NodeSight's way, the one that held on Cruzz's client with EllesmereUI and
-- MoveAny (probes 8 and 8b): anything more fired their hooks, and the minimap and its pieces
-- jumped about under the mouse.
--   * the minimap: an empty mask, set through the metatable's own method (past other addons'
--     hooks); its alpha is never touched (EllesmereUI writes it back on every visibility
--     event); icons tiny (dots and arrows); the quest areas' tracking off; wheel and clicks off,
--     mouse motion kept (passing it on to the world stops the minimap answering);
--   * its children, its regions and the frames anchored to it or to them: alpha 0, mouse off
--     down their tree, shrunk when hidden (hover buttons that fade in), hidden again every
--     frame. Nothing is re-parented or re-anchored.
-- The world gets no click while the minimap is under the mouse: it must have the mouse to
-- answer. A whole minimap is some 230 points, five seconds (Cruzz lost his clicks half the
-- time). So a scan reads at most a few dozen points, a few tenths of a second: the places not
-- read lately, nearest first; the next scans read the rest as you go. A button pressed ends it
-- at once, so your click lands (NodeSight 1.9+ found the same), and so does the cursor going
-- onto the minimap or its buttons. None while resting (cities, inns).
--
-- Two small see-through frames take turns under the mouse, one shown each frame. Showing one
-- makes the game work out the mouse focus in that same frame, and its OnEnter says it did: a
-- point placed in a frame without it is read again later rather than trusted. As the game
-- looks under the cursor in the frame the minimap is placed, a moving mouse does not matter:
-- the scan reads on (NodeSight does too, by guessing where the cursor will be).
--
-- The scan waits while the mouse is over a window or an NPC's window is
-- open: the minimap comes home, still hidden, the copy stays. It goes on where it was, or
-- ends after a second of waiting in one go or three in all. A zoom, combat or the minimap
-- hidden ends it. Everything is put back in the frame it ends, even after an error; an error
-- stops scanning until a /reload.

local SP = SuspicionsPack
local Scan = {}
SP.NodeRadarScan = Scan
-- Its hooks get their own rows in a /spack perf report.
local hooksecurefunc = SP.Perf.HookFunc("NodeRadar")

local Copy = SP.NodeRadarCopy
local _issecretvalue = issecretvalue or function() return false end
local floor, min, max, abs = math.floor, math.min, math.max, math.abs

local STEP = 20          -- minimap units between points: a dot answers ~24 wide (probe 4)
local WIDE = 24          -- minimap units a dot answers across: one dot's answers lie within it
local MAX_WAIT = 1       -- seconds a scan may wait in one go before it gives up
local MAX_WAITED = 3     -- and in all: a scan that keeps stopping drags on (74 s once, in game)
local MAX_TRIES = 2      -- a point read again at most this many times
local QUIET = 0.25       -- seconds the minimap's tooltip stays hidden after a scan
local SQUARE_REACH = 1.42
local TINY = 0.05        -- the minimap's icon scale during a scan (NodeSight's value)
local SHRUNK = 0.001     -- the scale of a hidden piece, so it stays unseen if its owner shows it
local DEPTH = 6          -- levels down a piece's tree its mouse is turned off
local MAX_SCAN = 30      -- seconds a scan may last at all, a last guard
local SEEN = 12          -- minimap units around a point read that count as read: a dot answers within 12,
                         -- and no place is further than 11.5 from a point of the honeycomb
local KEY = "NodeRadarScan"
local EMPTY_MASK = "Interface\\AddOns\\SuspicionsPack\\Media\\NodeRadar\\EmptyMask" -- 8 x 8, alpha 0
local FOREVER_MASK = "ui-hud-minimap-frame-generic-mask" -- Blizzard_Minimap's, set before addons load

local scan                -- the scan running, or nil
local failed = false      -- an error: no scan until a /reload
local quietUntil = 0
local last = {}           -- what the last scan did, for /spack radar status
local helpers = {}        -- the two see-through frames
local entered             -- the helper whose OnEnter ran last

-- Points a scan reads at most; seconds a place read is not read again; seconds it is
-- remembered as read; seconds the copy fades in and out; one scan in this many reads the
-- places of the nodes already known again (the others pass over them). Changed by the tests.
Scan.limits = { points = 24, fresh = 20, memory = 120, fade = 0.3, check = 3 }
local limits = Scan.limits

-- ============================================================
-- What others set on the minimap, kept to give back
-- ============================================================
-- The mask has no getter: the last one others set is kept (EllesmereUI sets its own, 130937
-- for a square map, after addons load), else a square or the game's own.
local maskSet, ourMask = nil, false
if Minimap and Minimap.SetMaskTexture then
    hooksecurefunc(Minimap, "SetMaskTexture", function(_, mask)
        if ourMask then return end
        maskSet = mask
        if scan then scan.maskChanged = true end
    end)
end

local function RealMask()
    if maskSet ~= nil then return maskSet end
    if GetMinimapShape then
        local ok, shape = pcall(GetMinimapShape)
        if ok and shape == "SQUARE" then return "Interface\\BUTTONS\\WHITE8X8" end
    end
    if C_Texture and C_Texture.GetAtlasExists and C_Texture.GetAtlasExists(FOREVER_MASK) then return FOREVER_MASK end
    return "Textures\\MinimapMask"
end

-- The empty mask through the metatable's own method: an addon hooking SetMaskTexture to put its
-- mask straight back (Leatrix Plus) would undo it. The real one goes back the usual way.
local function SetMask(empty)
    if not Minimap.SetMaskTexture then return false end
    local set = Minimap.SetMaskTexture
    local mt = empty and getmetatable(Minimap)
    if type(mt) == "table" and type(mt.__index) == "table" and type(mt.__index.SetMaskTexture) == "function" then
        set = mt.__index.SetMaskTexture
    end
    ourMask = true
    local ok = pcall(set, Minimap, empty and EMPTY_MASK or RealMask())
    ourMask = false
    return ok
end

-- The icon scale others set (Edit Mode, EllesmereUI), to give back, and set tiny again if they
-- change it mid-scan. Tiny dots still answer over the same area (probe 8b).
local iconScale, iconSets, ourScale = 1, 0, false
if Minimap and Minimap.SetIconScale then
    hooksecurefunc(Minimap, "SetIconScale", function(_, scale)
        if ourScale then return end
        if type(scale) == "number" and not _issecretvalue(scale) then iconScale = scale end
        iconSets = iconSets + 1
    end)
end

local function SetIcons(scale)
    if not Minimap.SetIconScale then return end
    ourScale = true
    pcall(Minimap.SetIconScale, Minimap, scale)
    ourScale = false
end

local function QuestAreasIndex()
    local kinds = Enum and Enum.MinimapTrackingFilter
    if not (C_Minimap.GetTrackingFilter and kinds and kinds.QuestPOIs) then return nil end
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local filter = C_Minimap.GetTrackingFilter(i)
        if type(filter) == "table" and not _issecretvalue(filter) and not _issecretvalue(filter.filterID)
            and filter.filterID == kinds.QuestPOIs then return i end
    end
    return nil
end

-- The quest areas back on (the game keeps them always on: off can only be a scan cut short
-- by a logout or a crash). True when they are on.
function Scan.QuestAreasBack()
    local index = QuestAreasIndex()
    if not index then return false end
    return pcall(C_Minimap.SetTracking, index, true)
end

-- ============================================================
-- For /spack radar status
-- ============================================================
local function DebugName(f)
    if f == Minimap then return "Minimap" end
    if f == WorldFrame then return "World" end
    if f ~= nil and (f == helpers[1] or f == helpers[2]) then return "helper" end
    local ok, name = pcall(function() return f:GetDebugName() end)
    if ok and type(name) == "string" and name ~= "" then return name end
    return "?"
end

-- A few names: the first ones, and how many.
local function Note(list, name, cap)
    if list[name] then
        list[name] = list[name] + 1
    elseif (list.n or 0) < (cap or 6) then
        list[name] = 1
        list.n = (list.n or 0) + 1
    end
end

local function Summary(list)
    local parts = {}
    for name, count in pairs(list) do
        if name ~= "n" then parts[#parts + 1] = name .. " x" .. count end
    end
    table.sort(parts)
    return parts[1] and table.concat(parts, ", ") or "none"
end

-- Who else moves the minimap during a scan: the first addon file and line in the caller's
-- stack; nothing when the call is the radar's own or no addon is in it.
local function Caller()
    if not debugstack then return nil end
    local stack = debugstack(3, 12, 0)
    if type(stack) ~= "string" or stack:find("NodeRadar[/\\]") then return nil end
    for line in stack:gmatch("[^\n]+") do
        local file, number = line:match('AddOns[/\\]([^"%]:]+)"?%]?:(%d+)')
        if file then return file .. ":" .. number end
    end
    return nil
end

-- The scan only adds offsets to the minimap's anchors. Anchored anew by someone else (a UI
-- laying it out again), it sits at its place, without them: the point placed then is read
-- again, and the next move starts from there.
local ANCHORS = { SetPoint = true, ClearAllPoints = true, SetAllPoints = true }

for _, method in ipairs({ "SetPoint", "ClearAllPoints", "SetAllPoints", "SetParent", "SetScale", "SetSize", "AdjustPointsOffset" }) do
    if Minimap and type(Minimap[method]) == "function" then
        hooksecurefunc(Minimap, method, function()
            if not scan then return end
            if ANCHORS[method] then
                scan.offX, scan.offY, scan.anchored = 0, 0, true
            end
            local who = Caller()
            if who then Note(scan.movers, method .. " from " .. who, 4) end
        end)
    end
end

-- ============================================================
-- Asking the game
-- ============================================================
local function Held()
    return IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
        or (IsMouselooking and IsMouselooking()) or false
end

local NPC_WINDOWS = { "Merchant", "Gossip", "QuestGiver", "Banker", "MailInfo", "Auctioneer",
    "TradePartner", "Trainer", "TaxiNode", "GuildBanker" }

local function AtNpc()
    local manager, kinds = C_PlayerInteractionManager, Enum and Enum.PlayerInteractionType
    if not (manager and manager.IsInteractingWithNpcOfType and kinds) then return false end
    for _, name in ipairs(NPC_WINDOWS) do
        local kind = kinds[name]
        if kind and manager.IsInteractingWithNpcOfType(kind) then return true end
    end
    return false
end

-- Busy (NodeSight 1.10's way): aiming a spell, the next click places it; casting or
-- gathering; a loot window open. A secret answer counts as busy.
local function Aiming()
    if not SpellIsTargeting then return false end
    local on = SpellIsTargeting()
    return _issecretvalue(on) or on == true
end

local function Busy()
    if Aiming() then return "aiming a spell" end
    local cast = UnitCastingInfo and UnitCastingInfo("player")
    if _issecretvalue(cast) or cast then return "casting" end
    local channel = UnitChannelInfo and UnitChannelInfo("player")
    if _issecretvalue(channel) or channel then return "casting" end
    local loot = GetNumLootItems and GetNumLootItems()
    if _issecretvalue(loot) or (type(loot) == "number" and loot > 0) then return "looting" end
    return nil
end

-- A unit under the mouse (a mob, its corpse to loot, a player): you are about to click it. The
-- game sees none under a moved minimap, so this is asked before a scan only.
-- Dead or a ghost: nothing can be gathered, and the minimap takes the spirit world's blue
-- (measured 2026-11-10: red 0.77, green 0.91, blue 1.08 of the copy's), which no copy matches.
local function Dead()
    if not UnitIsDeadOrGhost then return false end
    local dead = UnitIsDeadOrGhost("player")
    return _issecretvalue(dead) or dead == true
end

local function UnitUnderMouse()
    if not UnitExists then return false end
    local there = UnitExists("mouseover")
    return _issecretvalue(there) or there == true
end

local function IsHelper(f) return f ~= nil and (f == helpers[1] or f == helpers[2]) end

-- Something above the minimap (or above the world, the minimap home) under the mouse, but our
-- helpers: a window. The foci run top down.
local function Covered()
    local foci = GetMouseFoci and GetMouseFoci()
    if type(foci) ~= "table" then return false end
    for i = 1, #foci do
        local f = foci[i]
        if f == Minimap or f == WorldFrame then return false end
        if not IsHelper(f) then return true end
    end
    return false
end

-- Why a scan must wait now, or nil. A button held ends it instead: you are clicking.
local function WaitReason()
    if Covered() then return "mouse over a window" end
    if AtNpc() then return "NPC window open" end
    return nil
end

-- ============================================================
-- The minimap's pieces: hidden where they are, never moved
-- ============================================================
local function IsUnderMinimap(frame)
    local f = frame
    for _ = 1, 12 do
        if type(f) ~= "table" then return false end
        if f == Minimap then return true end
        local ok, up = pcall(f.GetParent, f)
        if not ok then return false end
        f = up
    end
    return false
end

-- Anchored to the minimap or to something on it: it moves with the minimap.
local function Follows(frame)
    local ok, n = pcall(frame.GetNumPoints, frame)
    if not ok or _issecretvalue(n) or type(n) ~= "number" then return false end
    for i = 1, n do
        local okp, _, rel = pcall(frame.GetPoint, frame, i)
        if okp and not _issecretvalue(rel) and type(rel) == "table" and (rel == Minimap or IsUnderMinimap(rel)) then
            return true
        end
    end
    return false
end

-- Frames elsewhere that follow the minimap (LibDBIcon buttons, PlayerCoords, the addon
-- drawer's tab, a UI's layout frame...), walked again at every scan.
local function Followers()
    local list, seen = {}, {}
    local function Walk(frame, depth)
        if depth > 3 or seen[frame] then return end
        seen[frame] = true
        if frame == Minimap or (frame.IsForbidden and frame:IsForbidden()) or IsUnderMinimap(frame) then return end
        if Follows(frame) then list[#list + 1] = frame end
        local ok, kids = pcall(function() return { frame:GetChildren() } end)
        if ok then
            for _, kid in ipairs(kids) do Walk(kid, depth + 1) end
        end
    end
    Walk(UIParent, 0)
    if MinimapCluster then Walk(MinimapCluster, 0) end
    return list
end

-- Mouse off, down a piece's tree: one that keeps the mouse (a full-size click catcher) stops
-- the dots being named.
local function Mute(s, frame, depth)
    if s.quiet[frame] or depth > DEPTH then return end
    if frame.IsMouseClickEnabled and frame.SetMouseClickEnabled then
        s.quiet[frame] = { clicks = frame:IsMouseClickEnabled(), motion = frame:IsMouseMotionEnabled() }
        pcall(frame.SetMouseClickEnabled, frame, false)
        pcall(frame.SetMouseMotionEnabled, frame, false)
    end
    if frame.GetChildren then
        local ok, kids = pcall(function() return { frame:GetChildren() } end)
        if ok then
            for _, kid in ipairs(kids) do
                if not _issecretvalue(kid) then Mute(s, kid, depth + 1) end
            end
        end
    end
end

-- A piece: alpha 0 (a piece may ignore its parent's alpha: MoveAny sets that), shrunk when
-- hidden so a hover button fading in stays unseen, mouse off. Not shrunk: regions, and the
-- addon compartment (EllesmereUI's SetScale hook would snap it back on the minimap).
local function Hide(s, piece)
    if s.pieces[piece] then return end
    local okA, alpha = pcall(piece.GetAlpha, piece)
    if not okA or _issecretvalue(alpha) or type(alpha) ~= "number" then return end
    local kind = piece.GetObjectType and piece:GetObjectType()
    local region = kind == "Texture" or kind == "FontString"
    local info = { alpha = alpha }
    info.noScale = region or piece == _G.AddonCompartmentFrame or not piece.SetScale or not piece.GetScale
    if not info.noScale then info.scale = piece:GetScale() end
    s.pieces[piece] = info
    s.count = s.count + 1
    pcall(piece.SetAlpha, piece, 0)
    if not info.noScale and piece.IsShown and not piece:IsShown() then
        info.shrunk = true
        pcall(piece.SetScale, piece, SHRUNK)
    end
    if not region then Mute(s, piece, 0) end
end

-- The pieces: the minimap's children and regions, and the frames that follow it.
local function PiecesNow()
    local list = {}
    for _, child in ipairs({ Minimap:GetChildren() }) do list[#list + 1] = child end
    for _, region in ipairs({ Minimap:GetRegions() }) do list[#list + 1] = region end
    for _, frame in ipairs(Followers()) do list[#list + 1] = frame end
    return list
end

-- Photocopied in their place (Copy.lua) as the scan starts. A copy that fails leaves them
-- vanishing for the scan, as they did before there was a copy.
local function CopyPieces(list)
    local ok, err = pcall(Copy.ShowPieces, list)
    if ok then
        last.copied, last.copiedOut, last.copiedWhy = Copy.Pieces()
    else
        last.copied, last.copiedOut, last.copiedWhy = 0, 0, "error: " .. tostring(err):sub(1, 80)
    end
end

-- Every frame: what came back is hidden again and shrunk (EllesmereUI shows the zoom buttons
-- every 0.2 s while the minimap has the mouse), new children hidden, the mask and the icons
-- set again if someone changed them.
local function KeepHidden(s)
    for piece, info in pairs(s.pieces) do
        local ok, alpha = pcall(piece.GetAlpha, piece)
        if ok and not _issecretvalue(alpha) and type(alpha) == "number" and alpha > 0 then
            s.reshown = s.reshown + 1
            pcall(piece.SetAlpha, piece, 0)
            if not info.noScale and not info.shrunk then
                info.shrunk = true
                pcall(piece.SetScale, piece, SHRUNK)
            end
        end
    end
    for _, child in ipairs({ Minimap:GetChildren() }) do Hide(s, child) end
    for _, region in ipairs({ Minimap:GetRegions() }) do Hide(s, region) end
    if s.maskChanged then
        s.maskChanged = false
        SetMask(true)
    end
    if iconSets ~= s.iconSets then
        s.iconSets = iconSets
        SetIcons(TINY)
    end
end

-- Once the copy is fully in: the minimap's empty mask, its pieces see-through, its icons tiny,
-- its clicks and wheel off, the quest areas off (remembered by the radar, so a logout mid-scan
-- puts them back at the next login).
local function Disguise(s)
    s.hidden = true
    SetMask(true)
    for _, piece in ipairs(s.list) do Hide(s, piece) end
    SetIcons(TINY)
    if s.clicks ~= nil then Minimap:SetMouseClickEnabled(false) end
    if s.wheel ~= nil then Minimap:EnableMouseWheel(false) end
    local index = QuestAreasIndex()
    local info = index and C_Minimap.GetTrackingInfo(index)
    if type(info) == "table" and not _issecretvalue(info) and info.active == true then
        if s.opts.questAreas then s.opts.questAreas(false) end
        s.questOff = pcall(C_Minimap.SetTracking, index, false)
    end
end

-- ============================================================
-- Moving the minimap, by its own offsets
-- ============================================================
local function MoveTo(s, x, y, cx, cy)
    local dx = cx / s.scale - (s.left + x)
    local dy = cy / s.scale - (s.bottom + y)
    Minimap:AdjustPointsOffset(dx - s.offX, dy - s.offY)
    s.offX, s.offY = dx, dy
end

-- A UI that keeps the minimap on the screen (EllesmereUI: SetClampedToScreen, with clamp
-- insets) stops it at the edge when a point would push it past: the point read is then not
-- the one placed, and a node is missed or put beside its place (NodeSight fixed the same on
-- 2026-11-11). Does the minimap, put with (x, y) under the cursor, stay on the screen?
local function Fits(s, x, y, cx, cy)
    if not s.clamped then return true end
    local left, bottom, m = cx / s.scale - x, cy / s.scale - y, s.margin
    return left - m >= 0 and bottom - m >= 0
        and left + s.width + m <= s.screenW and bottom + s.height + m <= s.screenH
end

-- The next point that fits, swapped in first; false when none does (the mouse near an edge).
local function TakeFitting(s, cx, cy)
    for i = s.next, #s.points do
        local p = s.points[i]
        if Fits(s, p.x, p.y, cx, cy) then
            s.points[s.next], s.points[i] = p, s.points[s.next]
            return true
        end
    end
    return false
end

local function GoHome(s)
    if s.offX ~= 0 or s.offY ~= 0 then
        Minimap:AdjustPointsOffset(-s.offX, -s.offY)
        s.offX, s.offY = 0, 0
    end
end

local function MakeHelper()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetSize(8, 8)
    f:EnableMouse(true)
    if f.SetPropagateMouseMotion then f:SetPropagateMouseMotion(true) end
    if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
    f:SetScript("OnEnter", function(self) entered = self end)
    f:Hide()
    return f
end

-- Shows the other helper under the mouse and hides this one: the game redoes the mouse focus
-- in this frame, and the shown one's OnEnter will say so.
local function Nudge(s, cx, cy)
    local show = s.helper == helpers[1] and helpers[2] or helpers[1]
    local ui = UIParent:GetEffectiveScale()
    show:ClearAllPoints()
    show:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / ui, cy / ui)
    show:Show()
    if s.helper then s.helper:Hide() end
    s.helper = show
    entered = nil
end

-- ============================================================
-- Tooltips
-- ============================================================
-- The moved minimap's tooltip (Blizzard's Minimap_OnUpdate) pops up at the cursor otherwise,
-- and a minimap button's (LibDBIcon). Not while the scan waits: the mouse may be on a bag.
local function Quiet()
    if scan and not scan.waitSince then return true end
    return GetTime() < quietUntil
end

local hooked = {}
local function HookTooltip(tip)
    if type(tip) ~= "table" or hooked[tip] or not tip.HookScript then return end
    hooked[tip] = true
    tip:HookScript("OnShow", SP.Perf.Wrap("NodeRadar", "tooltip OnShow", function(self)
        if Quiet() then self:Hide() end
    end))
end

local function HookTooltips()
    HookTooltip(_G.LibDBIconTooltip)
    if not hooked.minimap and GameTooltip and GameTooltip.SetMinimapMouseover then
        hooked.minimap = true
        hooksecurefunc(GameTooltip, "SetMinimapMouseover", function(self) if Quiet() then self:Hide() end end)
    end
end

-- ============================================================
-- What was read lately
-- ============================================================
-- Places read, in yards on their map, with the yards around them a dot would have answered
-- from, and when. A scan reads the places never read first, nearest first, then the ones read
-- longest ago; none read in the last limits.fresh seconds.
local seen = {}
local scans = 0           -- scans since the last Forget: one in limits.check reads the known nodes again

local function Prune(now)
    local kept = {}
    for i = 1, #seen do
        if now - seen[i].t < limits.memory then kept[#kept + 1] = seen[i] end
    end
    seen = kept
end

-- When the place (map, x, y) was last read, or nil.
local function LastRead(list, map, x, y)
    local at
    for i = 1, #list do
        local p = list[i]
        if p.map == map and (not at or p.t > at) then
            local dx, dy = x - p.x, y - p.y
            if dx * dx + dy * dy < p.r * p.r then at = p.t end
        end
    end
    return at
end

-- Everything to be read again: another finder on, a loading screen, the radar switched off.
function Scan.Forget()
    seen, scans = {}, 0
end

-- Did the last scan read the place of (map, mx, my)? A node there that did not answer is gone.
function Scan.Saw(map, mx, my, mapWidth, mapHeight)
    return LastRead(last.read or {}, map, mx * mapWidth, my * mapHeight) ~= nil
end

-- ============================================================
-- The points
-- ============================================================
-- A honeycomb over the minimap out to the radar's reach, nearest first: a scan cut short has
-- still looked near you. Shifted a third of a step each scan, to fill the gaps in turn.
local function Honeycomb(width, height, reach, phase)
    local list = {}
    local cx, cy = width / 2, height / 2
    local rowStep = STEP * 0.866
    local shift = (phase or 0) * STEP / 3
    local rows, cols = floor(reach / rowStep) + 1, floor(reach / STEP) + 1
    for j = -rows, rows do
        local y = cy + j * rowStep
        local off = (j % 2 == 0) and 0 or STEP / 2
        for i = -cols, cols do
            local x = cx + i * STEP + off + shift
            local dx, dy = x - cx, y - cy
            local d = dx * dx + dy * dy
            if x >= 0 and x <= width and y >= 0 and y <= height and d <= reach * reach then
                list[#list + 1] = { x = x, y = y, d = d, tries = 0 }
            end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    return list
end

-- ============================================================
-- Ending
-- ============================================================
local function End(s, why)
    SP.Tick.Remove(KEY)
    if scan ~= s then return end
    scan = nil
    -- In this frame: the minimap home and its mask back, then its pieces as they were.
    pcall(GoHome, s)
    if s.hidden then
        SetMask(false)
        for piece, info in pairs(s.pieces) do
            if info.shrunk then pcall(piece.SetScale, piece, info.scale) end
            pcall(piece.SetAlpha, piece, info.alpha)
        end
        for frame, info in pairs(s.quiet) do
            pcall(frame.SetMouseClickEnabled, frame, info.clicks)
            pcall(frame.SetMouseMotionEnabled, frame, info.motion)
        end
        if s.clicks ~= nil then pcall(Minimap.SetMouseClickEnabled, Minimap, s.clicks) end
        if s.wheel ~= nil then pcall(Minimap.EnableMouseWheel, Minimap, s.wheel) end
        SetIcons(iconScale)
    end
    for _, h in ipairs(helpers) do pcall(h.Hide, h) end
    -- The copy fades out over the minimap, back in this frame.
    if not pcall(Copy.FadeOut, limits.fade) then pcall(Copy.Hide) end
    -- Last: turning the quest areas back on is heard at once (MINIMAP_UPDATE_TRACKING).
    if s.questOff then
        if Scan.QuestAreasBack() and s.opts.questAreas then s.opts.questAreas(true) end
    end
    quietUntil = GetTime() + QUIET
    last.ended = why
    last.seconds = GetTime() - s.started
    last.placed, last.reads, last.again, last.answers = s.placedCount, s.reads, s.again, s.answers
    last.hidden, last.reshown, last.moved = s.count, s.reshown, s.moved
    last.empty, last.waits, last.movers = Summary(s.empty), Summary(s.waits), Summary(s.movers)
    last.read = s.read
    last.known = s.known
    last.unread = s.never - s.readNew
    SP:Debug("NodeRadar", "scan ended:", why, "placed", s.placedCount, "reads", s.reads, "answers", s.answers,
        "again", s.again, "hidden", s.count, "reshown", s.reshown, ("%.2f s"):format(last.seconds))
end

-- ============================================================
-- One frame
-- ============================================================
local function Again(s, point)
    s.again = s.again + 1
    point.tries = point.tries + 1
    if point.tries <= MAX_TRIES then s.points[#s.points + 1] = point end
end

local function Read(s)
    local placed = s.placed
    s.placed = nil
    -- Put back at its place meanwhile (none was, probe 8b): the minimap was not under the mouse.
    local anchored = s.anchored
    s.anchored = false
    if anchored then s.moved = s.moved + 1 end
    if anchored or entered ~= placed.helper then
        Again(s, placed.point)
        return
    end
    s.reads = s.reads + 1
    if placed.point.at == -math.huge then s.readNew = s.readNew + 1 end
    local place = { map = placed.map, x = placed.x, y = placed.y, r = SEEN * s.radius / s.half, t = GetTime() }
    s.read[#s.read + 1] = place
    seen[#seen + 1] = place
    local data = C_TooltipInfo.GetMinimapMouseover()
    local rows = not _issecretvalue(data) and type(data) == "table" and data.lines
    if _issecretvalue(rows) or type(rows) ~= "table" or not rows[1] then
        -- Nothing named: what had the mouse (an empty place, or something over the minimap).
        local foci = GetMouseFoci and GetMouseFoci()
        local names = {}
        if type(foci) == "table" then
            for i = 1, min(#foci, 3) do names[i] = DebugName(foci[i]) end
        end
        Note(s.empty, names[1] and table.concat(names, " > ") or "nothing")
        return
    end
    s.answers = s.answers + 1
    s.opts.read(data, placed.map, placed.mx, placed.my)
end

local function StepScan(elapsed)
    local s = scan
    if InCombatLockdown() and not s.opts.combat then return End(s, "combat") end
    if Dead() then return End(s, "dead") end
    if not Minimap:IsVisible() then return End(s, "minimap hidden") end
    if GetTime() - s.started > MAX_SCAN then return End(s, "too long") end
    local radius = C_Minimap.GetViewRadius()
    if _issecretvalue(radius) or radius ~= s.radius then return End(s, "zoom") end
    -- A button pressed: you are clicking (or turning the camera, and nothing would answer).
    if Held() then return End(s, "mouse button held") end
    -- A spell being aimed: the next click places it.
    if Aiming() then return End(s, "aiming a spell") end
    -- The cursor onto the minimap's place or its buttons: you want them, they come back.
    local cx, cy = GetCursorPosition()
    if Copy.Covers(cx, cy) then return End(s, "mouse on the minimap") end
    local map, x, y, mapWidth, mapHeight = s.opts.position()
    -- Fading in: the copy comes over the minimap, still at its place.
    if not s.hidden then
        local t = limits.fade > 0 and (GetTime() - s.started) / limits.fade or 1
        if t < 1 then
            Copy.Update(s.opts.nodes, map, x, y, mapWidth, mapHeight)
            Copy.SetAlpha(t)
            return
        end
        Copy.SetAlpha(1)
        Disguise(s)
    end
    if s.placed then Read(s) end
    KeepHidden(s)
    Copy.Update(s.opts.nodes, map, x, y, mapWidth, mapHeight)
    local why = WaitReason()
    if not why and s.points[s.next] and not TakeFitting(s, cx, cy) then why = "mouse near the screen's edge" end
    if why then
        Note(s.waits, why)
        s.waited = s.waited + (elapsed or 0)
        if s.waited > MAX_WAITED then return End(s, why) end
        if not s.waitSince then
            s.waitSince = GetTime()
            GoHome(s)
            if s.helper then s.helper:Hide() end
        elseif GetTime() - s.waitSince > MAX_WAIT then
            return End(s, why)
        end
        return
    end
    s.waitSince = nil
    if not map then return End(s, "no map position") end
    local point = s.points[s.next]
    if not point then return End(s, "done") end
    s.next = s.next + 1
    MoveTo(s, point.x, point.y, cx, cy)
    s.anchored = false
    Nudge(s, cx, cy)
    -- Where that point is on the map now: you may be moving.
    local ypu = s.radius / s.half
    local east, north = (point.x - s.half) * ypu, (point.y - s.halfH) * ypu
    s.placed = { point = point, helper = s.helper, cx = cx, cy = cy, map = map,
        mx = x + east / mapWidth, my = y - north / mapHeight, x = x * mapWidth + east, y = y * mapHeight - north }
    s.placedCount = s.placedCount + 1
end

local stepElapsed = 0
local function StepNow() return StepScan(stepElapsed) end

local function Step(elapsed)
    stepElapsed = elapsed or 0
    local s = scan
    if not s then
        SP.Tick.Remove(KEY)
        return
    end
    if not xpcall(StepNow, geterrorhandler()) then
        failed = true
        End(s, "error")
    end
    if scan == nil and s.opts.done then s.opts.done(last.ended) end
end

-- ============================================================
-- Starting
-- ============================================================
-- Can a scan start now? Nil, or why not.
function Scan.Refusal(combatOK)
    if failed then return "stopped after an error until a /reload" end
    if scan then return "already scanning" end
    if not Minimap:IsVisible() or not Minimap:GetLeft() then return "minimap hidden" end
    if InCombatLockdown() and not combatOK then return "in combat" end
    if IsResting() then return "resting (a city or an inn)" end
    if Dead() then return "dead" end
    if IsInInstance() then return "in an instance" end
    if UnitOnTaxi("player") then return "on a flight path" end
    if IsFlying() then return "flying" end
    if C_CVar.GetCVar("rotateMinimap") == "1" then return "rotating minimap" end
    local can, why = Copy.CanDraw()
    if not can then return why end
    local radius = C_Minimap.GetViewRadius()
    if _issecretvalue(radius) or not radius or radius <= 0 then return "no minimap radius" end
    if Held() then return "mouse button held" end
    local foci = GetMouseFoci and GetMouseFoci()
    if type(foci) == "table" and foci[1] ~= nil and foci[1] ~= WorldFrame then return "mouse over a window" end
    if AtNpc() then return "NPC window open" end
    local busy = Busy()
    if busy then return busy end
    if UnitUnderMouse() then return "unit under the mouse" end
    return nil
end

-- Starts a scan; it runs from the next frame. opts:
--   position() -> map, x, y, mapWidth, mapHeight: the radar's map position
--   read(data, map, mx, my): one minimap answer, and the map place it was read at
--   done(why): at the end, "done" when every point was read (not after Scan.Stop)
--   reach: yards out from you; round: the minimap's shape; nodes: what the copy draws;
--   combat: may scan in combat; phase: 0 to 2; questAreas(on): the quest areas turned off and on
-- Nil, or why it did not start ("read lately" when every place in reach was).
function Scan.Start(opts)
    local refusal = Scan.Refusal(opts.combat)
    if refusal then return refusal end
    local map, x, y, mapWidth, mapHeight = opts.position()
    if not map then return "no map position" end
    if not helpers[1] then helpers[1], helpers[2] = MakeHelper(), MakeHelper() end
    HookTooltips()
    local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
    local width, height = Minimap:GetWidth(), Minimap:GetHeight()
    local radius = C_Minimap.GetViewRadius()
    local half = width / 2
    local reach = min(opts.reach / radius * half, half * (opts.round and 1 or SQUARE_REACH))
    -- A few points: never read first, nearest first; then the ones read longest ago.
    local all = Honeycomb(width, height, reach, opts.phase)
    local ypu = radius / half
    local now = GetTime()
    Prune(now)
    -- The places of the nodes already known: passed over, but one scan in limits.check, which
    -- looks whether they are still there (NodeSight's way).
    local nodesKnown = {}
    if (scans + 1) % limits.check ~= 0 and type(opts.nodes) == "table" then
        local inside = (WIDE / 2 - 2) * ypu
        for _, node in ipairs(opts.nodes) do
            if node.map == map and node.mx and node.my then
                nodesKnown[#nodesKnown + 1] = { map = map, x = node.mx * mapWidth, y = node.my * mapHeight, r = inside, t = 0 }
            end
        end
    end
    local order, fresh, never, known = {}, 0, 0, 0
    for i, point in ipairs(all) do
        local east, north = (point.x - half) * ypu, (point.y - height / 2) * ypu
        local px, py = x * mapWidth + east, y * mapHeight - north
        local at = not LastRead(nodesKnown, map, px, py) and LastRead(seen, map, px, py)
        if at == false then
            known = known + 1
        elseif at and now - at < limits.fresh then
            fresh = fresh + 1
        else
            point.at, point.rank = at or -math.huge, i
            order[#order + 1] = point
            if not at then never = never + 1 end
        end
    end
    if not order[1] then return "read lately" end
    scans = scans + 1
    table.sort(order, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        return a.rank < b.rank
    end)
    local points = {}
    for i = 1, min(#order, limits.points) do points[i] = order[i] end
    local s = {
        opts = opts, started = GetTime(), radius = radius, half = half, halfH = height / 2,
        left = left, bottom = bottom, scale = Minimap:GetEffectiveScale(), offX = 0, offY = 0,
        width = width, height = height, clamped = false, margin = 0,
        points = points, next = 1, read = {}, never = never, readNew = 0, known = known, list = {},
        pieces = {}, quiet = {}, count = 0, reshown = 0,
        clicks = Minimap.IsMouseClickEnabled and Minimap:IsMouseClickEnabled() or nil,
        wheel = Minimap.IsMouseWheelEnabled and Minimap:IsMouseWheelEnabled() or nil,
        placedCount = 0, reads = 0, again = 0, answers = 0, moved = 0, waited = 0, anchored = false,
        empty = {}, waits = {}, movers = {}, iconSets = iconSets,
    }
    -- Kept on the screen? Then the screen in minimap units, and the clamp insets as a margin.
    local okC, clamped = pcall(Minimap.IsClampedToScreen, Minimap)
    if okC and (_issecretvalue(clamped) or clamped) then
        s.clamped = true
        local ui = UIParent:GetEffectiveScale()
        s.screenW, s.screenH = UIParent:GetWidth() * ui / s.scale, UIParent:GetHeight() * ui / s.scale
        local okI, l, r, t, b = pcall(Minimap.GetClampRectInsets, Minimap)
        if okI then
            for _, v in ipairs({ l or 0, r or 0, t or 0, b or 0 }) do
                if not _issecretvalue(v) and type(v) == "number" then s.margin = max(s.margin, abs(v)) end
            end
        end
    end
    scan = s
    last = { started = s.started, points = #points, candidates = #all, fresh = fresh,
        left = #order - #points, wide = WIDE * radius / half }
    -- In this frame, before it is drawn: the copy over the minimap's place, its pieces
    -- photocopied; it fades in from the next frame, or with no fade the minimap goes now.
    local ok, err = pcall(function()
        Copy.Show(left, bottom, width, height, Minimap:GetFrameStrata(), Minimap:GetFrameLevel() + 1,
            opts.round, opts.nodes, map, x, y, mapWidth, mapHeight)
        s.list = PiecesNow()
        CopyPieces(s.list)
        if limits.fade > 0 then
            Copy.SetAlpha(0)
        else
            Copy.SetAlpha(1)
            Disguise(s)
        end
    end)
    if not ok then
        failed = true
        End(s, "error")
        geterrorhandler()(err)
        return "error"
    end
    SP:Debug("NodeRadar", "scan started:", #s.points, "points, reach", ("%.0f"):format(reach), "units, pieces", s.count)
    SP.Tick.Add(KEY, Step)
    return nil
end

function Scan.Stop(why)
    if scan then End(scan, why or "stopped") end
end

function Scan.Running() return scan ~= nil end
function Scan.Failed() return failed end
function Scan.Last() return last end
