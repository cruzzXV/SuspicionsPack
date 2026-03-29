-- SuspicionsPack — TankMD Module
-- Forked from the TankMD addon by Weximus.
-- Creates hidden SecureActionButtons (TankMDButton1–5) that always target
-- the current tanks (or healers for Innervate) so macros like
--   /click TankMDButton1
-- always fire on the right person without needing to set a focus.
local SP = SuspicionsPack

local TankMD = SP:NewModule("TankMD", "AceEvent-3.0")
SP.TankMD = TankMD

-- ============================================================
-- Constants
-- ============================================================
local NUM_BUTTONS = 5

-- Spell used per class. Defaults to Misdirection (Hunter) for unknown classes.
local SPELL_IDS = {
    HUNTER  = 34477,  -- Misdirection
    ROGUE   = 57934,  -- Tricks of the Trade
    DRUID   = 29166,  -- Innervate
    EVOKER  = 360827, -- Rescue
    PALADIN = 1044,   -- Hand of Freedom / Blessing of Freedom
}

-- Role that each class should target
local TARGET_ROLES = {
    HUNTER  = "TANK",
    ROGUE   = "TANK",
    DRUID   = "HEALER",
    EVOKER  = "TANK",
    PALADIN = "TANK",
}

-- Whether the class wants the player themselves as a last-resort fallback
local ADD_PLAYER_FALLBACK = {
    EVOKER = true,
}

-- Whether the class falls back to its own pet
local ADD_PET_FALLBACK = {
    HUNTER = true,
    EVOKER = true,
}

local RAID_UNITS = {
    "raid1",  "raid2",  "raid3",  "raid4",  "raid5",
    "raid6",  "raid7",  "raid8",  "raid9",  "raid10",
    "raid11", "raid12", "raid13", "raid14", "raid15",
    "raid16", "raid17", "raid18", "raid19", "raid20",
    "raid21", "raid22", "raid23", "raid24", "raid25",
    "raid26", "raid27", "raid28", "raid29", "raid30",
    "raid31", "raid32", "raid33", "raid34", "raid35",
    "raid36", "raid37", "raid38", "raid39", "raid40",
}
local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }

-- ============================================================
-- State
-- ============================================================
local buttons        = {}   -- array of SecureActionButton frames
local isUpdateQueued = false

-- ============================================================
-- Helpers
-- ============================================================
local function GetDB()
    return SP.GetDB().tankMD
end

local function GetPlayerClass()
    local _, class = UnitClass("player")
    return class
end

-- Returns sorted list of player NAMES for the appropriate role,
-- optionally pre-pending the focus target.
-- Mirrors exactly how the original TankMD addon resolves targets:
-- group members → UnitName(), focus → UnitName("focus"), pet → "pet", self → "player".
local function GetTargets()
    local db      = GetDB()
    local class   = GetPlayerClass()
    local role    = TARGET_ROLES[class] or "TANK"
    local method  = db.selectionMethod or "tankRoleOnly"
    local units   = IsInRaid() and RAID_UNITS or PARTY_UNITS

    -- Collect names that match the desired role
    local names = {}
    local seen  = {}
    for _, unit in ipairs(units) do
        local name = UnitName(unit)
        if name and name ~= UNKNOWNOBJECT and not seen[name] then
            local assignedRole = UnitGroupRolesAssigned(unit)
            local isMainTank   = GetPartyAssignment("MAINTANK", unit, true)

            local include = false
            if method == "tankRoleOnly" then
                include = (assignedRole == role)
            elseif method == "tanksAndMainTanks" then
                include = (assignedRole == role) or isMainTank
            elseif method == "prioritizeMainTanks" then
                -- main tanks go in a separate pass below
                include = (assignedRole == role and not isMainTank)
            elseif method == "mainTanksOnly" then
                include = isMainTank
            end

            if include then
                seen[name] = true
                table.insert(names, name)
            end
        end
    end

    -- For prioritizeMainTanks: collect main tanks separately and prepend
    if method == "prioritizeMainTanks" then
        local mainTanks = {}
        for _, unit in ipairs(units) do
            local name = UnitName(unit)
            if name and name ~= UNKNOWNOBJECT and GetPartyAssignment("MAINTANK", unit, true) then
                if not seen[name] then
                    seen[name] = true
                    table.insert(mainTanks, name)
                end
            end
        end
        table.sort(mainTanks)
        table.sort(names)
        -- prepend main tanks
        for i = #mainTanks, 1, -1 do
            table.insert(names, 1, mainTanks[i])
        end
    else
        table.sort(names)
    end

    -- Prepend focus (if enabled and focus is in group with correct role).
    -- Use the player name, not the "focus" token — matches original TankMD.
    if db.prioritizeFocus then
        local focusGUID = UnitGUID("focus")
        if focusGUID and IsGUIDInGroup(focusGUID) then
            local focusName = UnitName("focus")
            if focusName then
                -- remove from sorted list if present, put at front
                for i, n in ipairs(names) do
                    if n == focusName then
                        table.remove(names, i)
                        break
                    end
                end
                table.insert(names, 1, focusName)
            end
        end
    end

    -- Class-specific fallbacks. Use "pet" / "player" unit tokens,
    -- exactly as the original TankMD does in TargetSelector.Pet() / .Player().
    if ADD_PET_FALLBACK[class] then
        local petName = UnitName("pet")
        if petName and not seen[petName] then
            table.insert(names, "pet")
        end
    end
    if ADD_PLAYER_FALLBACK[class] then
        local playerName = UnitName("player")
        if playerName and not seen[playerName] then
            table.insert(names, "player")
        end
    end

    return names
end

local function SetButtonTarget(button, target)
    if target then
        button:SetAttribute("type", "spell")
        button:SetAttribute("unit", target)
    else
        button:SetAttribute("type", nil)
        button:SetAttribute("unit", nil)
    end
end

-- ============================================================
-- Button creation — must happen outside combat lockdown
-- ============================================================
local function CreateButtons()
    if #buttons > 0 then return end
    local class   = GetPlayerClass()
    local spellID = SPELL_IDS[class] or SPELL_IDS["HUNTER"]

    for i = 1, NUM_BUTTONS do
        local name = string.format("TankMDButton%d", i)
        local btn  = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
        btn:Hide()
        btn:SetAttribute("type",               "spell")  -- matches original: always "spell" at creation
        btn:SetAttribute("spell",              spellID)
        btn:SetAttribute("checkselfcast",      false)
        btn:SetAttribute("checkfocuscast",     false)
        btn:SetAttribute("allowVehicleTarget", false)
        -- Ensures the action fires on Down regardless of ActionButtonUseKeyDown CVar.
        -- Required on mainline (TWW / Midnight) — copied exactly from original TankMD.
        if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then
            btn:SetAttribute("pressAndHoldAction", "1")
            btn:SetAttribute("typerelease",        "spell")
        end
        btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        buttons[i] = btn
    end
end

-- ============================================================
-- Update loop
-- ============================================================
local function ProcessUpdate()
    if InCombatLockdown() then
        isUpdateQueued = true
        return
    end
    isUpdateQueued = false

    local db = GetDB()
    if not db or not db.enabled then
        -- Disable all buttons
        for _, btn in ipairs(buttons) do
            SetButtonTarget(btn, nil)
        end
        return
    end

    local targets = GetTargets()
    for i, btn in ipairs(buttons) do
        SetButtonTarget(btn, targets[i])
    end
end

local function QueueUpdate()
    if isUpdateQueued then return end  -- already pending, don't stack timers
    isUpdateQueued = true
    -- Defer to next frame to break any tainted execution chain coming from
    -- third-party addon CallbackHandlers (e.g. AccWideUILayoutSelection).
    -- UnitName() comparisons inside ProcessUpdate throw taint errors when
    -- called directly from a foreign secure callback.
    C_Timer.After(0, ProcessUpdate)
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function TankMD:OnEnable()
    CreateButtons()

    self:RegisterEvent("GROUP_ROSTER_UPDATE",    "OnRosterChange")
    self:RegisterEvent("PLAYER_FOCUS_CHANGED",   "OnRosterChange")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",  "OnRosterChange")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",   "OnLeaveCombat")

    QueueUpdate()
end

function TankMD:OnDisable()
    self:UnregisterAllEvents()
    isUpdateQueued = false
    -- Clear all button targets
    for _, btn in ipairs(buttons) do
        if not InCombatLockdown() then
            SetButtonTarget(btn, nil)
        end
    end
end

function TankMD:OnRosterChange()
    QueueUpdate()
end

function TankMD:OnLeaveCombat()
    if isUpdateQueued then
        ProcessUpdate()
    end
end

-- ============================================================
-- Slash command: /tankmd
-- ============================================================
SLASH_TANKMD1 = "/tankmd"
SlashCmdList["TANKMD"] = function()
    local found = false
    for i, btn in ipairs(buttons) do
        local target = btn:GetAttribute("unit")
        if target then
            found = true
            print(string.format("|cffe51039TankMD|r Button %d → %s", i, target))
        end
    end
    if not found then
        print("|cffe51039TankMD|r No targets assigned (no tanks/healers in group, or module disabled).")
    end
end

-- Called by GUI enable toggle
function TankMD:Refresh()
    local db = GetDB()
    if db and db.enabled then
        self:Activate()
    else
        self:Deactivate()
    end
end

function TankMD:Activate()
    if not self:IsEnabled() then self:Enable() end
    QueueUpdate()
end

function TankMD:Deactivate()
    self:Disable()
end
