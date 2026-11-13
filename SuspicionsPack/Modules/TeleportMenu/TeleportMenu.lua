-- SuspicionsPack — TeleportMenu (WoW: Forever only, see the .toc gate)
--
-- Beside the game menu (Escape), the teleports this character has: the Hearthstone, the
-- shaman's Astral Recall, the druid's Moonglade, the engineering transporters and Atiesh in
-- a column, then the mage's teleports and portals in two rows. A click casts it, and the game
-- menu closes: Escape would cancel the cast otherwise.
--
-- After TeleportMenu on retail (Justwait, no licence): read for what it does, our own code.
--
-- Secure buttons, so:
--   * They sit on UIParent, neither children of GameMenuFrame nor anchored to it. A protected
--     frame protects its parent and what it is anchored to, and Blizzard (and EllesmereUI)
--     resize the menu while it shows. The holder is placed by absolute coordinates read off
--     the menu, out of combat, and follows it every frame while it shows: MoveAny drags and
--     scales the menu, EllesmereUI sets its height.
--   * They only change out of combat. While the menu is open a state driver hides them in
--     combat, the one thing that can. A menu closed during a fight is put away when the
--     fight ends: the driver has to go, or it shows the holder again.
--   * On GameMenuFrame itself: HookScript only. No field written, no Blizzard method called
--     except HideUIPanel, which hands the work to Blizzard's secure panel manager.
--
-- Idle costs nothing: no events while the menu is closed, besides the end of a fight.

local SP = SuspicionsPack

local TM = SP:NewSPModule("TeleportMenu", "teleportMenu")
SP.TeleportMenu = TM

local _issecretvalue = issecretvalue or function() return false end
local floor = math.floor

-- ============================================================
-- The game's data, DB2 build 1.60.1.70888
-- ============================================================
-- Spells and items that teleport (effect 252), by id: names are never compared, the client
-- is French. A spell shows when known, an item when carried or worn.
local COLUMN = {
    { kind = "item",  id = 6948 },      -- Hearthstone
    { kind = "spell", id = 556 },       -- Astral Recall (shaman)
    { kind = "spell", id = 18960 },     -- Teleport: Moonglade (druid)
    { kind = "item",  id = 18984 },     -- Dimensional Ripper - Everlook
    { kind = "item",  id = 260820 },    -- SAF-T Emergency Ripper: Everlook (trinket)
    { kind = "item",  id = 18986 },     -- Ultrasafe Transporter: Gadgetzan
    { kind = "item",  id = 260819 },    -- EZ-Thro Field Transporter: Gadgetzan (trinket)
    { kind = "item",  id = 260823 },    -- Dimensional Transporter - Mt. Hyjal
    { kind = "item",  id = 260821 },    -- EZ and SAF Field Transporter: Mt. Hyjal (trinket)
    -- Atiesh, Greatstaff of the Guardian: one per class, all casting Portal: Karazhan. The
    -- last four have no ItemSparse row in this build but use the same spell.
    { kind = "item",  id = 22589 }, { kind = "item", id = 22630 },
    { kind = "item",  id = 22631 }, { kind = "item", id = 22632 },
    { kind = "item",  id = 236398 }, { kind = "item", id = 236399 },
    { kind = "item",  id = 236400 }, { kind = "item", id = 236401 },
}
-- Mage, nearest the menu first. A character only ever knows its own faction's.
local TELEPORTS = {
    3561, 3562, 3565,       -- Stormwind, Ironforge, Darnassus
    3567, 3563, 3566,       -- Orgrimmar, Undercity, Thunder Bluff
    1297659,                -- Dalaran
}
local PORTALS = {
    10059, 11416, 11419,    -- Stormwind, Ironforge, Darnassus
    11417, 11418, 11420,    -- Orgrimmar, Undercity, Thunder Bluff
}

-- ============================================================
-- Settings that are not settings
-- ============================================================
local WHEN_OPEN = "[combat] hide; show"
local GAP = 6               -- pixels between the menu and the column
local SPACING = 4           -- pixels between two buttons
local ICON_CROP = 0.08
local GLOBAL_COOLDOWN = 1.5 -- seconds: a cooldown this short is not the teleport's own

-- For the setup tour's example menu, drawn with the same lists and spacing.
TM.COLUMN, TM.TELEPORTS, TM.PORTALS = COLUMN, TELEPORTS, PORTALS
TM.LOOK = { GAP = GAP, SPACING = SPACING, ICON_CROP = ICON_CROP }
local OPEN_EVENTS = {
    "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN",                     -- the swipes
    "BAG_UPDATE_DELAYED", "SPELLS_CHANGED", "PLAYER_EQUIPMENT_CHANGED", -- what is on it
}

-- ============================================================
-- State
-- ============================================================
local active    = false
local hooked    = false     -- GameMenuFrame's scripts carry ours
local driven    = false     -- the driver runs: the column is up
local retried   = false     -- the menu had no position: one more try was made
local onButtons = nil       -- what the buttons show, so they are only touched on a change
local placedX, placedY      -- where the holder sits, so it is only moved on a change

local holder
local buttons = {}

local Sync

-- ============================================================
-- The game
-- ============================================================
local function Known(id)
    return C_SpellBook.IsSpellKnown(id) and true or false
end

-- GetItemCount counts what is worn too; the second test only makes sure of it.
local function Carried(id)
    return C_Item.GetItemCount(id) > 0 or C_Item.IsEquippedItem(id)
end

local function Has(entry)
    if entry.kind == "spell" then return Known(entry.id) end
    return Carried(entry.id)
end

local function ReadCooldown(entry)
    if entry.kind == "spell" then
        -- Secret first: the game refuses a truth test on a secret value.
        local info = C_Spell.GetSpellCooldown(entry.id)
        if _issecretvalue(info) or not info then return nil end
        return info.startTime, info.duration
    end
    return C_Container.GetItemCooldown(entry.id)
end

-- The teleport's own cooldown, or nil: none, only the global one, or secret.
local function OwnCooldown(entry)
    local start, duration = ReadCooldown(entry)
    if _issecretvalue(start) or _issecretvalue(duration) then return nil end
    if not (start and duration) or duration <= GLOBAL_COOLDOWN then return nil end
    return start, duration
end

-- Seconds before it can be used again; 0 when ready or unknowable.
local function Remaining(entry)
    local start, duration = OwnCooldown(entry)
    if not start then return 0 end
    local left = start + duration - GetTime()
    return left > 0 and left or 0
end

-- A worn-only item that is not worn: the click equips it instead of using it.
local function EquipsOnClick(entry)
    return entry.kind == "item" and C_Item.IsEquippableItem(entry.id) and not C_Item.IsEquippedItem(entry.id)
end

-- What goes on the menu: { kind, id, row, col }, rows top to bottom, columns away from it.
local function ReadEntries()
    local list, row = {}, 0
    for _, entry in ipairs(COLUMN) do
        if Has(entry) then
            list[#list + 1] = { kind = entry.kind, id = entry.id, row = row, col = 0 }
            row = row + 1
        end
    end
    local function Row(ids)
        local col = 0
        for _, id in ipairs(ids) do
            if Known(id) then
                list[#list + 1] = { kind = "spell", id = id, row = row, col = col }
                col = col + 1
            end
        end
        if col > 0 then row = row + 1 end
    end
    Row(TELEPORTS)
    if TM:GetDB().portals then Row(PORTALS) end
    return list
end

local function Icon(entry)
    if entry.kind == "spell" then return C_Spell.GetSpellTexture(entry.id) end
    return C_Item.GetItemIconByID(entry.id)
end

-- ============================================================
-- The frames
-- ============================================================
local function ButtonEnter(b)
    GameTooltip:SetOwner(b, "ANCHOR_LEFT")
    if b.entry.kind == "spell" then GameTooltip:SetSpellByID(b.entry.id) else GameTooltip:SetItemByID(b.entry.id) end
    GameTooltip:Show()
end

local function ButtonLeave()
    GameTooltip:Hide()
end

-- Decided before the click: equipping changes the answer. A click that did nothing
-- (on cooldown) or only equipped the item leaves the menu open, to click again.
local function ButtonPreClick(b, mouse)
    b.closes = mouse == "LeftButton" and not EquipsOnClick(b.entry) and Remaining(b.entry) <= 0
end

-- The cast has started: Escape would cancel it, so the menu goes. Its OnHide puts the
-- column away.
local function ButtonPostClick(b)
    if b.closes and TM:GetDB().closeMenu and not InCombatLockdown() and GameMenuFrame:IsShown() then
        HideUIPanel(GameMenuFrame)
    end
end

-- Top right of the column against the menu's top left, in UIParent's units. False until the
-- menu has a position.
local function Place()
    local menu = GameMenuFrame
    local left, top = menu:GetLeft(), menu:GetTop()
    if not (left and top) then return false end
    local scale = menu:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x, y = left * scale - GAP, top * scale
    if x ~= placedX or y ~= placedY then
        holder:ClearAllPoints()
        holder:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x, y)
        placedX, placedY = x, y
    end
    return true
end

-- Runs while the column shows, so never with the menu closed. The driver hides it in combat,
-- but its first check may come a frame after the lockdown.
local function Follow()
    if not InCombatLockdown() then Place() end
end

local function EnsureHolder()
    if holder then return end
    holder = CreateFrame("Frame", "SP_TeleportMenu", UIParent)
    holder:SetSize(1, 1)
    holder:SetFrameStrata("DIALOG")
    holder:Hide()
    holder:SetScript("OnUpdate", SP.Perf.Wrap("TeleportMenu", "follow OnUpdate", Follow))
end

local function NewButton(index)
    local b = CreateFrame("Button", nil, holder, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp")
    -- Fire on release. Without this the ActionButtonUseKeyDown CVar applies, and when on,
    -- an "AnyUp" button never fires (same as the Hearthstone datatext).
    b:SetAttribute("useOnKeyDown", false)

    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints(b)
    edge:SetColorTexture(0, 0, 0, 1)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

    b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cooldown:SetAllPoints(b.icon)

    -- Like the action bars mark a worn item.
    b.worn = b:CreateTexture(nil, "OVERLAY")
    b.worn:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.worn:SetBlendMode("ADD")
    b.worn:SetVertexColor(0, 1, 0, 0.7)
    b.worn:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.worn:Hide()

    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", ButtonEnter)
    b:SetScript("OnLeave", ButtonLeave)
    b:SetScript("PreClick", ButtonPreClick)
    b:SetScript("PostClick", ButtonPostClick)
    buttons[index] = b
    return b
end

-- "*": with a modifier held, a left click still casts.
local function SetAction(b, entry)
    local spell = entry.kind == "spell"
    b:SetAttribute("*type1", entry.kind)
    b:SetAttribute("*spell1", spell and entry.id or nil)
    b:SetAttribute("*item1", (not spell) and ("item:" .. entry.id) or nil)
    b.entry = entry
    b.icon:SetTexture(Icon(entry))
end

local function Layout(list, size)
    local step = size + SPACING
    local rows, cols = 0, 0
    for i, entry in ipairs(list) do
        local b = buttons[i] or NewButton(i)
        b:SetSize(size, size)
        b.worn:SetSize(size * 62 / 36, size * 62 / 36)   -- the border art is 62 px for a 36 px button
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -entry.col * step, -entry.row * step)
        SetAction(b, entry)
        b:Show()
        rows = math.max(rows, entry.row + 1)
        cols = math.max(cols, entry.col + 1)
    end
    for i = #list + 1, #buttons do
        buttons[i]:Hide()
        buttons[i].entry = nil      -- no more cooldown or border reads for it
    end
    holder:SetSize(cols * step - SPACING, rows * step - SPACING)
    -- A button changed or hidden under the mouse never hears OnLeave.
    for _, b in ipairs(buttons) do
        if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
    end
end

-- Allowed in combat: a cooldown frame is not protected.
local function UpdateCooldowns()
    for _, b in ipairs(buttons) do
        if b.entry then
            local start, duration = OwnCooldown(b.entry)
            if start then b.cooldown:SetCooldown(start, duration) else b.cooldown:Clear() end
        end
    end
end

local function UpdateWorn()
    for _, b in ipairs(buttons) do
        b.worn:SetShown(b.entry ~= nil and b.entry.kind == "item" and C_Item.IsEquippedItem(b.entry.id))
    end
end

-- ============================================================
-- Keeping it true
-- ============================================================
local events = CreateFrame("Frame")

local function Listen(on)
    for _, event in ipairs(OPEN_EVENTS) do
        if on then events:RegisterEvent(event) else events:UnregisterEvent(event) end
    end
end

local function Signature(list, size)
    local parts = { size }
    for i, entry in ipairs(list) do
        parts[i + 1] = entry.kind .. entry.id .. "@" .. entry.row .. "," .. entry.col
    end
    return table.concat(parts, " ")
end

local function Open(list)
    EnsureHolder()
    local size = TM:GetDB().size
    local signature = Signature(list, size)
    if signature ~= onButtons then
        Layout(list, size)
        onButtons = signature
    end
    -- The menu may not have a position yet in the frame it shows: try again on the next,
    -- once, rather than every frame for as long as it stays open.
    if not Place() then
        if not retried then
            retried = true
            C_Timer.After(0, Sync)
        end
        return
    end
    retried = false
    UpdateCooldowns()
    UpdateWorn()
    Listen(true)
    if not driven then
        RegisterStateDriver(holder, "visibility", WHEN_OPEN)
        driven = true
    end
end

local function Close()
    Listen(false)
    retried = false
    if not holder then return end
    if driven then
        UnregisterStateDriver(holder, "visibility")
        driven = false
    end
    if holder:IsShown() then holder:Hide() end
end

-- The one place the column changes. In combat it waits: PLAYER_REGEN_ENABLED runs it again.
function Sync()
    if InCombatLockdown() then return end
    local list = active and GameMenuFrame and GameMenuFrame:IsShown() and ReadEntries()
    if list and list[1] then Open(list) else Close() end
end

-- HookScript only, once: a hook cannot be taken back, so each one asks `active` (in Sync).
local function HookMenu()
    if hooked then return true end
    if not GameMenuFrame then return false end
    hooked = true
    GameMenuFrame:HookScript("OnShow", SP.Perf.Wrap("TeleportMenu", "menu OnShow", function() Sync() end))
    GameMenuFrame:HookScript("OnHide", SP.Perf.Wrap("TeleportMenu", "menu OnHide", function() Sync() end))
    return true
end

-- Not AceEvent: a switch-off in combat has to outlive the module's own events to finish
-- when the fight does.
events:SetScript("OnEvent", SP.Perf.WrapEvent("TeleportMenu", function(self, event)
    if event == "ADDON_LOADED" then
        if HookMenu() then self:UnregisterEvent("ADDON_LOADED") end
        return
    end
    if event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
        UpdateCooldowns()
        return
    end
    Sync()
    if not active and not InCombatLockdown() then self:UnregisterAllEvents() end
end))

-- ============================================================
-- The module
-- ============================================================
-- Runs again on every settings change.
function TM:Activate()
    active = true
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    if not HookMenu() then events:RegisterEvent("ADDON_LOADED") end
    Sync()
end

function TM:Deactivate()
    active = false
    if InCombatLockdown() then
        events:UnregisterEvent("ADDON_LOADED")
    else
        events:UnregisterAllEvents()
    end
    Sync()
end

-- /spack teleport status: what the menu sees at the moment you ask.
function TM.PrintStatus()
    local menu = GameMenuFrame
    print(("SuspicionsPack: teleport menu: on %s, game menu %s, hooked %s, up %s, in combat %s"):format(
        tostring(active), tostring(menu and menu:IsShown()), tostring(hooked), tostring(driven),
        tostring(InCombatLockdown())))
    local function Line(entry, label)
        local name, have
        if entry.kind == "spell" then
            name, have = C_Spell.GetSpellName(entry.id), "known " .. tostring(Known(entry.id))
        else
            name, have = C_Item.GetItemNameByID(entry.id), "carried " .. tostring(Carried(entry.id))
        end
        print(("  %s %s (%d): %s, cooldown %d s"):format(label, tostring(name), entry.id, have,
            floor(Remaining(entry))))
    end
    for _, entry in ipairs(COLUMN) do
        if Has(entry) then Line(entry, entry.kind) end
    end
    for _, id in ipairs(TELEPORTS) do
        if Known(id) then Line({ kind = "spell", id = id }, "teleport") end
    end
    for _, id in ipairs(PORTALS) do
        if Known(id) then Line({ kind = "spell", id = id }, "portal") end
    end
    print("  Anything this character has that is missing above: say which, with its name.")
end
