-- SuspicionsPack — Datatexts (WoW: Forever only, see the .toc gate)
--
-- Bars of small live texts (gold, durability, clock, guild...), the feature
-- Simple DataTexts provides, drawn in the pack's Forever style. Written from
-- scratch: SDT (GPL-3) was read as a feature reference only.
--
-- THE PIECES
--   * A datatext is a table registered by id (DT.Register), in Texts\*.lua.
--   * A bar is a frame split into up to MAX_SLOTS slots; each slot shows one id.
--   * A provider is one per id IN USE, not one per slot: one frame for its
--     events, one ticker for its interval. Its text is computed once and pushed
--     to every slot showing that id, and an id that leaves every slot releases
--     its events. (SDT keeps one frame per slot, and only the last slot of a
--     given datatext refreshes.)
--
-- STYLE VS LAYOUT
--   Refresh() re-runs Activate() on every option change, a slider drag
--   included, so everything here is created once and reused.
--   * ApplyStyle(): fonts and colours. Safe at any time.
--   * RequestLayout(): sizes, positions, slot assignments, skins and the
--     Hearthstone's secure button. In combat it only notes the request and
--     runs on PLAYER_REGEN_ENABLED, so a slot and its secure button never
--     disagree.
--
-- THE SECURE BUTTON
--   Hearthstone needs a SecureActionButtonTemplate. A protected frame protects
--   its parent and whatever it is anchored to, so it is NOT a child of the
--   slot: it sits on UIParent, placed over the slot by absolute coordinates
--   out of combat. The bars stay plain frames that can be shown, hidden and
--   moved at any time.

local SP = SuspicionsPack

local DT = SP:NewSPModule("Datatexts", "datatexts")
SP.Datatexts = DT

local MAX_SLOTS = 8
local NONE      = "none"
DT.MAX_SLOTS    = MAX_SLOTS
DT.NONE         = NONE
DT.MIN_HEIGHT   = 16   -- below it the Plumber box's 16 px corners turn inside out

-- ============================================================
-- Registry
-- ============================================================
local defs  = {}   -- id -> definition
local order = {}   -- ids in registration order
DT.defs = defs

-- A definition:
--   name     shown in the slot lists          group   sorts the lists
--   label    text before the value (nil: none) showLabel  its default
--   events   game events  unitEvents  player unit events  interval  seconds
--   Text(o, p)             -> value[, label]   (o reads this id's options)
--   Tooltip(o, tt, slot)   fills the tooltip
--   Click(o, slot, button) Wheel(o, slot, delta)
--   Hover(o, slot) / Leave(o, slot)  replace the tooltip (Guild, Friends)
--   Secure(o, button)      sets a secure button's attributes (Hearthstone)
--   OnEvent(o, event, ...) OnStart(o, p) OnStop(o, p)
--   options  { { kind, key, label, default, ... } } for the options page
function DT.Register(id, def)
    def.id       = id
    def.options  = def.options or {}
    def._defaults = {}
    if def.label then
        table.insert(def.options, 1, {
            kind = "toggle", key = "showLabel", label = "Show label",
            default = def.showLabel ~= false,
        })
    end
    for _, opt in ipairs(def.options) do def._defaults[opt.key] = opt.default end
    if not defs[id] then order[#order + 1] = id end
    defs[id] = def
    DT._listCache = nil
    -- A late registration (a LibDataBroker object created after login) may be
    -- one a saved slot is waiting for.
    if DT._active then DT.RequestLayout() end
end

-- The slot lists of the options page: { key, label } sorted by group then
-- name, "none" first.
function DT.List()
    if DT._listCache then return DT._listCache end
    local list = {}
    for _, id in ipairs(order) do list[#list + 1] = id end
    table.sort(list, function(a, b)
        local da, db = defs[a], defs[b]
        local ga, gb = da.group or "~", db.group or "~"
        if ga ~= gb then return ga < gb end
        return (da.name or a) < (db.name or b)
    end)
    local out = { { key = NONE, label = "(empty)" } }
    for _, id in ipairs(list) do
        local d = defs[id]
        out[#out + 1] = { key = id, label = (d.group and (d.group .. ": ") or "") .. (d.name or id) }
    end
    DT._listCache = out
    return out
end

-- ============================================================
-- Per-datatext options
-- ============================================================
local readers = {}

-- o.key: the saved value, or the option's default. `nil` tested explicitly:
-- a saved false or 0 is a real choice.
local function O(id)
    local r = readers[id]
    if r then return r end
    r = setmetatable({}, { __index = function(_, k)
        local db = DT:GetDB()
        local t  = db and db.texts and db.texts[id]
        local v  = t and t[k]
        if v == nil then
            local d = defs[id]
            v = d and d._defaults[k]
        end
        return v
    end })
    readers[id] = r
    return r
end
DT.O = O

function DT.SetOption(id, key, value)
    local db = DT:GetDB()
    if not db then return end
    if type(db.texts) ~= "table" then db.texts = {} end
    local t = db.texts[id]
    if type(t) ~= "table" then t = {}; db.texts[id] = t end
    t[key] = value
end

-- ============================================================
-- Colours
-- ============================================================
local function Hex(r, g, b)
    return string.format("|cff%02x%02x%02x",
        math.floor((r or 1) * 255 + 0.5), math.floor((g or 1) * 255 + 0.5), math.floor((b or 1) * 255 + 0.5))
end
DT.Hex = Hex

-- From red at 0 through yellow to green at 1, for percentages.
function DT.Gradient(f)
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    if f < 0.5 then return Hex(1, f * 2, 0) end
    return Hex(2 - f * 2, 1, 0)
end

local labelHex, valueHex = "|cffffd100", "|cffd7c0a3"

local function RefreshColors()
    local db = DT:GetDB()
    if not db then return end
    labelHex = Hex(SP.GetColorFromSource(db.labelSource, db.labelColor))
    valueHex = Hex(SP.GetColorFromSource(db.valueSource, db.valueColor))
end

local function Compose(id, value, label)
    local d = defs[id]
    if label == nil then label = d.label end
    value = value or ""
    if label and O(id).showLabel then
        return labelHex .. label .. "|r " .. valueHex .. value .. "|r"
    end
    return valueHex .. value .. "|r"
end

-- ============================================================
-- Providers
-- ============================================================
local providers = {}   -- id -> { id, frame, slots = { [slot] = true }, text, on }
local live      = {}   -- id -> true while shown in at least one slot

local function Update(id)
    local p, d = providers[id], defs[id]
    if not (p and d) then return end
    local ok, value, label = pcall(d.Text, O(id), p)
    local text
    if ok then
        text = Compose(id, value, label)
    else
        text = "|cffff5555" .. (d.name or id) .. "|r"
        -- Once per datatext: an interval datatext would otherwise repeat the
        -- same error every second.
        if not p.errorShown then
            p.errorShown = true
            geterrorhandler()(value)
        end
    end
    p.text = text
    for slot in pairs(p.slots) do slot.text:SetText(text) end
end
DT.Update = Update

-- A burst of events (BAG_UPDATE, UNIT_AURA...) becomes one update on the next
-- frame.
local function Queue(p)
    if p.queued then return end
    p.queued = true
    C_Timer.After(0, function()
        p.queued = false
        if live[p.id] then Update(p.id) end
    end)
end

local function GetProvider(id)
    local p = providers[id]
    if p then return p end
    p = { id = id, slots = {}, text = "" }
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function(_, event, ...)
        SP:Debug("Datatexts", id, event, ...)
        local d = defs[id]
        if d and d.OnEvent then d.OnEvent(O(id), event, ...) end
        Queue(p)
    end)
    p.frame = f
    providers[id] = p
    return p
end

-- Registering an event the client does not know throws; a datatext written
-- for one client must not take the bar down on another.
local function SafeRegister(f, method, event, unit)
    local ok = pcall(f[method], f, event, unit)
    if not ok then SP:Debug("Datatexts", "unknown event", event) end
end

local function Start(id)
    local d, p = defs[id], GetProvider(id)
    if p.on then return end
    p.on = true
    for _, e in ipairs(d.events or {}) do SafeRegister(p.frame, "RegisterEvent", e) end
    for _, e in ipairs(d.unitEvents or {}) do SafeRegister(p.frame, "RegisterUnitEvent", e, "player") end
    if d.interval then
        p.ticker = p.ticker or SP.Tick.NewAnimTicker(function()
            if p.on then Update(id) end
            return p.on
        end, d.interval)
        p.ticker.Start()
    end
    if d.OnStart then d.OnStart(O(id), p) end
end

local function Stop(id)
    local p = providers[id]
    if not (p and p.on) then return end
    p.on = false
    p.frame:UnregisterAllEvents()
    if p.ticker then p.ticker.Stop() end
    local d = defs[id]
    if d and d.OnStop then d.OnStop(O(id), p) end
end

-- ============================================================
-- Default bars: one generic bar in the middle of the screen, for the user to
-- name, move, fill and add to. Profiles seeded before 2026-10-23 keep the
-- three bars they were given then (Chat, Details, Minimap): seeding runs once
-- per profile (`_seeded`).
-- ============================================================
local DEFAULT_BARS = {
    { name = "Bar 1", width = 360, height = 22, scale = 100, numSlots = 3,
      point = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
      slots = { "durability", "gold", "time" } },
}

-- A complete bar record. Slots are always keys 1..MAX_SLOTS, "none" when
-- empty: a nil gap would break ipairs and #, and a profile import.
local function MakeBar(src)
    local b = {
        name         = src.name or "Bar",
        width        = src.width or 300,
        height       = src.height or 22,
        scale        = src.scale or 100,
        skin         = src.skin or "box",
        numSlots     = src.numSlots or 3,
        hideInCombat = src.hideInCombat or false,
        openEdge     = src.openEdge or "none",   -- what the border leaves off (Skins.edges)
        bgOpacity    = src.bgOpacity or 100,     -- % of the skin's fill shown
        point        = {
            point         = src.point and src.point.point or "CENTER",
            relativePoint = src.point and src.point.relativePoint or "CENTER",
            x             = src.point and src.point.x or 0,
            y             = src.point and src.point.y or 0,
        },
        slots        = {},
    }
    for i = 1, MAX_SLOTS do b.slots[i] = (src.slots and src.slots[i]) or NONE end
    return b
end
DT.MakeBar = MakeBar

-- Seeds the default bars once. Called by the module and by the options page,
-- so the page is never empty while the module is still off. A profile that
-- already holds bars (an import) is left alone; deleting every bar afterwards
-- does not bring them back.
function DT.EnsureSeeded()
    local db = DT:GetDB()
    if not db or db._seeded then return end
    if type(db.bars) ~= "table" then db.bars = {} end
    if #db.bars == 0 then
        for i, b in ipairs(DEFAULT_BARS) do db.bars[i] = MakeBar(b) end
    end
    db._seeded = true
end

function DT.RestoreDefaultBars()
    local db = DT:GetDB()
    if not db then return end
    db.bars = {}
    for i, b in ipairs(DEFAULT_BARS) do db.bars[i] = MakeBar(b) end
    db._seeded = true
    DT.RequestLayout()
end

function DT.NewBar()
    local db = DT:GetDB()
    if not db then return end
    if type(db.bars) ~= "table" then db.bars = {} end
    local n = #db.bars + 1
    db.bars[n] = MakeBar({ name = "Bar " .. n })
    DT.RequestLayout()
    return n
end

function DT.DeleteBar(i)
    local db = DT:GetDB()
    if not (db and db.bars and db.bars[i]) then return end
    table.remove(db.bars, i)
    DT.RequestLayout()
end

function DT.ResetPosition(i)
    local db = DT:GetDB()
    local b  = db and db.bars and db.bars[i]
    if not b then return end
    b.point = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
    DT.RequestLayout()
end

function DT.GetBarConfig(i)
    local db = DT:GetDB()
    return db and type(db.bars) == "table" and db.bars[i] or nil
end

-- ============================================================
-- Bars and slots
-- ============================================================
local bars     = {}   -- frame pool by index; a deleted bar's frame is reused
local inCombat = false
local pendingLayout, pendingSecure = false, false

local GOLD = SP.Skin.FOREVER_TEXT.gold

local function BarDragStart(bar)
    local db = DT:GetDB()
    if not db or db.locked or InCombatLockdown() then return end
    bar._moving = true
    bar:StartMoving()
end

local function BarDragStop(bar)
    if not bar._moving then return end
    bar._moving = false
    bar:StopMovingOrSizing()
    -- StartMoving marks a named frame as user-placed, and the client would
    -- then restore it from layout-local.txt on top of our own position.
    bar:SetUserPlaced(false)
    local cfg = DT.GetBarConfig(bar.index)
    if cfg then
        local point, _, relPoint, x, y = bar:GetPoint(1)
        cfg.point = { point = point, relativePoint = relPoint, x = x, y = y }
    end
    DT.RequestLayout()
    -- The options window's X and Y offsets show the new position.
    if SP.GUI and SP.GUI.RefreshAll then SP.GUI.RefreshAll() end
end

local function SlotEnter(s)
    local id = s.id
    local d  = id and defs[id]
    if not d then return end
    if d.Hover then d.Hover(O(id), s) return end
    if d.Tooltip and DT.ShowTooltip then DT.ShowTooltip(s, d) end
end

local function SlotLeave(s)
    local id = s.id
    local d  = id and defs[id]
    if d and d.Leave then d.Leave(O(id), s) end
    if DT.HideTooltip then DT.HideTooltip() end
end

local function SlotClick(s, button)
    local id = s.id
    local d  = id and defs[id]
    if not (d and d.Click) then return end
    d.Click(O(id), s, button)
    Update(id)
    -- The click may have changed what the tooltip shows (Volume's stream).
    if DT.TooltipOwner and DT.TooltipOwner() == s then SlotEnter(s) end
end

local function SlotWheel(s, delta)
    local id = s.id
    local d  = id and defs[id]
    if not (d and d.Wheel) then return end
    d.Wheel(O(id), s, delta)
    Update(id)
    if DT.TooltipOwner and DT.TooltipOwner() == s then SlotEnter(s) end
end
DT.SlotEnter, DT.SlotLeave, DT.SlotClick = SlotEnter, SlotLeave, SlotClick

local function GetSlot(bar, i)
    local s = bar.slots[i]
    if s then return s end
    s = CreateFrame("Button", nil, bar)
    s:SetFrameLevel(bar:GetFrameLevel() + 2)
    s:RegisterForClicks("AnyUp")
    s:RegisterForDrag("LeftButton")
    local fs = s:CreateFontString(nil, "OVERLAY")
    -- A font before any text: SetText on a FontString with none throws "Font
    -- not set". ApplyStyle puts the chosen one on it right after.
    SP.SetFontSafe(fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "")
    fs:SetPoint("LEFT", s, "LEFT", 4, 0)
    fs:SetPoint("RIGHT", s, "RIGHT", -4, 0)
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    s.text = fs
    s:SetScript("OnEnter", SlotEnter)
    s:SetScript("OnLeave", SlotLeave)
    s:SetScript("OnClick", SlotClick)
    s:SetScript("OnMouseWheel", SlotWheel)
    s:SetScript("OnDragStart", function(self) BarDragStart(self:GetParent()) end)
    s:SetScript("OnDragStop",  function(self) BarDragStop(self:GetParent()) end)
    s.bar = bar
    bar.slots[i] = s
    return s
end

-- The unlocked look: a gold outline round the bar and its name above it.
local function BuildMover(bar)
    local m = CreateFrame("Frame", nil, bar)
    m:SetAllPoints(bar)
    m:SetFrameLevel(bar:GetFrameLevel() + 6)
    local function Edge(p1, p2, w, h)
        local t = m:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
        t:SetPoint(p1); t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 1)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    Edge("TOPLEFT", "BOTTOMLEFT", 1, nil)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
    local name = m:CreateFontString(nil, "OVERLAY")
    SP.SetFontSafe(name, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    name:SetTextColor(GOLD[1], GOLD[2], GOLD[3], 1)
    name:SetPoint("BOTTOM", m, "TOP", 0, 4)
    m.name = name
    m:Hide()
    return m
end

local function GetBar(i)
    local bar = bars[i]
    if bar then return bar end
    bar = CreateFrame("Frame", "SP_DatatextBar" .. i, UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetFrameLevel(5)
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", BarDragStart)
    bar:SetScript("OnDragStop", BarDragStop)
    bar.index = i
    bar.slots = {}
    bar.mover = BuildMover(bar)
    bars[i] = bar
    return bar
end

local function Clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function LayoutBar(bar, cfg, db, used)
    local n = math.floor(Clamp(cfg.numSlots, 1, MAX_SLOTS))
    local w = Clamp(cfg.width, 40, 4000)
    local h = Clamp(cfg.height, DT.MIN_HEIGHT, 200)
    bar:SetScale(Clamp(cfg.scale, 30, 300) / 100)
    bar:SetSize(w, h)
    bar:ClearAllPoints()
    local pt = cfg.point
    if type(pt) == "table" and pt.x and pt.y then
        bar:SetPoint(pt.point or "CENTER", UIParent, pt.relativePoint or "CENTER", pt.x, pt.y)
    else
        bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    local slotW = w / n
    for i = 1, MAX_SLOTS do
        local s = bar.slots[i]
        if i <= n then
            s = GetSlot(bar, i)
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", bar, "TOPLEFT", (i - 1) * slotW, 0)
            s:SetSize(slotW, h)
            local id = type(cfg.slots) == "table" and cfg.slots[i]
            -- An id nobody registered (an LDB object not created yet): shown
            -- empty, and kept in the saved slot for when it arrives.
            if not (id and id ~= NONE and defs[id]) then id = nil end
            s.id = id
            s:EnableMouseWheel(id and defs[id].Wheel and true or false)
            if id then
                used[id] = true
                local p = GetProvider(id)
                p.slots[s] = true
                s.text:SetText(p.text or "")
            else
                s.text:SetText(db.locked and "" or "|cff808080(empty)|r")
            end
            s:Show()
        elseif s then
            s.id = nil
            s:Hide()
        end
    end

    if DT.Skins then
        -- An Open edge key (Skins.edges); anything else draws the whole border.
        local open = cfg.openEdge
        -- A bar saved before the setting existed has none: the skin as drawn.
        local opacity = cfg.bgOpacity
        if opacity == nil then opacity = 100 end
        DT.Skins.Apply(bar, cfg.skin, n, slotW, w, h, open, Clamp(opacity, 0, 100) / 100)
    end

    bar.mover.name:SetText(cfg.name or ("Bar " .. bar.index))
    bar.mover:SetShown(not db.locked)
    bar:EnableMouse(not db.locked)
end

local function ShouldShow(i)
    if not DT:IsOn() then return false end
    local db  = DT:GetDB()
    local cfg = db.bars and db.bars[i]
    if not cfg then return false end
    if not db.locked then return true end
    if inCombat and (cfg.hideInCombat or db.hideInCombat) then return false end
    return true
end

local function ApplyVisibility()
    for i, bar in pairs(bars) do bar:SetShown(ShouldShow(i)) end
end

-- ---- the secure buttons --------------------------------------------------
local secure = {}   -- slot -> secure button

local function SecurePreClick(btn, button)
    local s = btn.slot
    local d = s and s.id and defs[s.id]
    if d and d.PreClick and not InCombatLockdown() then d.PreClick(O(s.id), btn, button) end
end

local function SecurePostClick(btn, button)
    if button ~= "LeftButton" and btn.slot then SlotClick(btn.slot, button) end
end

local function GetSecure(slot)
    local b = secure[slot]
    if b then return b end
    b = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp")
    -- Fire on release. Required, not cosmetic: an addon's button is not a
    -- "secure mouse press" to SecureActionButton_OnClick, so without this the
    -- ActionButtonUseKeyDown CVar applies and, when on, an "AnyUp" button
    -- never fires (SecureTemplates.lua, branch forever).
    b:SetAttribute("useOnKeyDown", false)
    b.slot = slot
    b:SetScript("OnEnter", function(self) SlotEnter(self.slot) end)
    b:SetScript("OnLeave", function(self) SlotLeave(self.slot) end)
    b:SetScript("PreClick", SecurePreClick)
    b:SetScript("PostClick", SecurePostClick)
    secure[slot] = b
    return b
end

-- Places `b` over `slot` in UIParent's coordinates. False when the slot has
-- no rect yet (the first frames after login).
local function PlaceOver(b, slot)
    local l, bot, w, h = slot:GetRect()
    if not (l and w and w > 0) then return false end
    local k = slot:GetEffectiveScale() / UIParent:GetEffectiveScale()
    b:ClearAllPoints()
    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * k, bot * k)
    b:SetSize(w * k, h * k)
    b:SetFrameStrata(slot:GetFrameStrata())
    b:SetFrameLevel(slot:GetFrameLevel() + 10)
    return true
end

local retries = 0
function DT.SyncSecure()
    if InCombatLockdown() then pendingSecure = true; return end
    pendingSecure = false
    local want = {}
    local db = DT:GetDB()
    local missed = false
    if DT:IsOn() and db and db.locked then
        for i, bar in pairs(bars) do
            local cfg = db.bars and db.bars[i]
            if cfg and bar:IsShown() then
                for _, s in pairs(bar.slots) do
                    local d = s:IsShown() and s.id and defs[s.id]
                    if d and d.Secure then
                        local b = GetSecure(s)
                        if PlaceOver(b, s) then
                            d.Secure(O(s.id), b)
                            want[b] = true
                            -- The bar hides in combat, so the button must too,
                            -- and only a state driver can hide it then.
                            if cfg.hideInCombat or db.hideInCombat then
                                RegisterStateDriver(b, "visibility", "[combat] hide; show")
                            else
                                UnregisterStateDriver(b, "visibility")
                                b:Show()
                            end
                        else
                            missed = true
                        end
                    end
                end
            end
        end
    end
    for _, b in pairs(secure) do
        if not want[b] then
            UnregisterStateDriver(b, "visibility")
            b:Hide()
        end
    end
    -- Slots with no rect yet (the first frames after login): a few more tries,
    -- then wait for the next layout.
    if missed and retries < 5 then
        retries = retries + 1
        C_Timer.After(0.2, function() DT.SyncSecure() end)
    elseif not missed then
        retries = 0
    end
end

-- Re-reads a secure button's attributes (a different hearthstone picked).
-- Out of combat only; in combat it waits with the rest.
function DT.RefreshSecure(id)
    if InCombatLockdown() then pendingSecure = true; return end
    for s, b in pairs(secure) do
        if s.id == id and b:IsShown() then defs[id].Secure(O(id), b) end
    end
end

-- ---- layout ---------------------------------------------------------------
local function Layout()
    pendingLayout = false
    local db = DT:GetDB()
    local on = DT:IsOn() and db
    local list = on and type(db.bars) == "table" and db.bars or {}

    for _, p in pairs(providers) do wipe(p.slots) end
    local used = {}
    if on then
        for i, cfg in ipairs(list) do LayoutBar(GetBar(i), cfg, db, used) end
    end
    for i, bar in pairs(bars) do
        if not list[i] then
            for _, s in pairs(bar.slots) do s.id = nil end
        end
    end

    for id in pairs(live) do
        if not used[id] then live[id] = nil; Stop(id) end
    end
    for id in pairs(used) do
        if not live[id] then live[id] = true; Start(id) end
    end

    ApplyVisibility()
    DT.ApplyStyle()
    DT.SyncSecure()
    -- Once more next frame: a rect read in the same tick as the SetScale and
    -- SetPoint above may still be the old one.
    C_Timer.After(0, function() if not InCombatLockdown() then DT.SyncSecure() end end)
end

function DT.RequestLayout()
    if InCombatLockdown() then pendingLayout = true; return end
    Layout()
end

function DT.InCombatPending() return pendingLayout end

-- Fonts and colours, then every live text again (the colours are baked in).
function DT.ApplyStyle()
    local db = DT:GetDB()
    if not db then return end
    RefreshColors()
    local path    = SP.ResolveFont(db.fontFace)
    local outline = db.fontOutline
    if outline == nil or outline == "NONE" then outline = "" end
    local size = db.fontSize or 12
    for _, bar in pairs(bars) do
        for _, s in pairs(bar.slots) do
            SP.SetFontSafe(s.text, path, size, outline)
            s.text:SetShadowColor(0, 0, 0, 0.9)
            s.text:SetShadowOffset(1, -1)
        end
    end
    for id in pairs(live) do Update(id) end
end

-- ============================================================
-- Combat
--
-- A frame of its own rather than the module's AceEvent: switching the module
-- off in combat leaves a secure button to hide, and AceAddon's OnDisable
-- unregisters every event the module object holds.
-- ============================================================
-- A new UI scale or window size: laid out again. The secure button is placed
-- in UIParent's coordinates and the leather skin's lines are sized in physical
-- pixels, so both move with it.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_REGEN_DISABLED")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:RegisterEvent("UI_SCALE_CHANGED")
watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
watcher:SetScript("OnEvent", function(_, event)
    if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
        if DT._active then DT.RequestLayout() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        if DT._active then ApplyVisibility() end
        if DT.Roster then DT.Roster.Hide() end
    else
        inCombat = false
        if pendingLayout then
            Layout()
        else
            if DT._active then ApplyVisibility() end
            if pendingSecure then DT.SyncSecure() end
        end
    end
end)

-- The module's state, for /dump in game and for the offline tests. Read only.
DT._internal = { providers = providers, live = live, bars = bars, secure = secure, watcher = watcher }

-- ============================================================
-- Lifecycle (Core\Module.lua)
-- ============================================================
function DT:Activate()
    DT.EnsureSeeded()
    DT._active = true
    inCombat = InCombatLockdown() and true or false
    DT.RequestLayout()
    DT.ApplyStyle()
end

function DT:Deactivate()
    DT._active = false
    for id in pairs(live) do live[id] = nil; Stop(id) end
    for _, p in pairs(providers) do wipe(p.slots) end
    for _, bar in pairs(bars) do bar:Hide() end
    if DT.HideTooltip then DT.HideTooltip() end
    if DT.Roster then DT.Roster.Hide() end
    DT.SyncSecure()
end
