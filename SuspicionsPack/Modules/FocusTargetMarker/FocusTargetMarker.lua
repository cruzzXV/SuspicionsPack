-- SuspicionsPack — FocusTargetMarker
local SP = SuspicionsPack

local FTM = SP:NewSPModule("FocusTargetMarker", "focusTargetMarker")
SP.FocusTargetMarker = FTM

local MACRO_NAME = "FocusTargetMarker"
local MACRO_ICON = 132219

-- WoW chat icon syntax: {rt1}–{rt8} renders the actual marker icon in chat
local MARKER_TEXT = {
    [1] = "{rt1}", [2] = "{rt2}", [3] = "{rt3}", [4] = "{rt4}",
    [5] = "{rt5}", [6] = "{rt6}", [7] = "{rt7}", [8] = "{rt8}",
}

-- Kept as a file local: MaybeAnnounce() is a file-scope function with no `self`.
local function GetDB()
    return SP.GetDB().focusTargetMarker
end

-- ============================================================
-- Announce gate
--
-- Healers do not take kick assignments, so announcing "my kick marker is X" in
-- party chat is noise from them. Restoration Shaman is the deliberate
-- exception -- Wind Shear is off the GCD with a 12 s cooldown, so Resto shamans
-- are routinely put on the kick rotation.
--
-- This gates the CHAT MESSAGE only. The macro is still written and kept up to
-- date on every spec: a healer may well still want the focus + marker bind,
-- they just should not broadcast it.
-- ============================================================
local BLOCKED_SPECS = {
    [105]  = true,  -- Restoration Druid
    [1468] = true,  -- Preservation Evoker
    [270]  = true,  -- Mistweaver Monk
    [65]   = true,  -- Holy Paladin
    [256]  = true,  -- Discipline Priest
    [257]  = true,  -- Holy Priest
    -- 264 Restoration Shaman is intentionally ABSENT: Wind Shear means they
    -- take kick assignments like a DPS.
}

local function GetSpecID()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
                    or _G.GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo)
                    or _G.GetSpecializationInfo
    if not (getSpec and getInfo) then return nil end

    local index = getSpec()
    -- 0 is truthy in Lua, and GetSpecialization returns it when no spec is
    -- chosen yet -- so this needs an explicit range test, not `index and`.
    if type(index) ~= "number" or index < 1 then return nil end
    return (getInfo(index))
end

-- Unknown spec (early login, no spec chosen) is treated as allowed: a ready
-- check cannot realistically fire before the spec resolves, and failing open
-- keeps a missing API from silencing everyone.
local function IsAnnounceAllowed()
    local specID = GetSpecID()
    if not specID then return true end
    return not BLOCKED_SPECS[specID]
end

local function WriteMacro(markerIndex)
    if InCombatLockdown() then return end
    local content = "/focus [@mouseover,harm,nodead][]\n/tm [@mouseover,harm,nodead][] " .. markerIndex
    local ok = pcall(function()
        local slot = GetMacroIndexByName(MACRO_NAME)
        if slot and slot > 0 then
            EditMacro(slot, MACRO_NAME, MACRO_ICON, content)
        else
            CreateMacro(MACRO_NAME, MACRO_ICON, content, nil)
        end
    end)
    if not ok then
        SP:Debug("FocusTargetMarker", "Macro write failed")
    end
end

local function MaybeAnnounce(markerIndex)
    local db = GetDB()
    if not db or not db.announce then return end
    -- Healers don't take kick assignments; announcing one is noise. Evaluated
    -- live at announce time, so a spec swap needs no bookkeeping.
    if not IsAnnounceAllowed() then return end
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" or InCombatLockdown() then return end
    C_ChatInfo.SendChatMessage("My kick marker is " .. (MARKER_TEXT[markerIndex] or "?"), "PARTY")
end

function FTM:OnWorldEnter()
    WriteMacro(GetDB().marker or 5)
end

function FTM:OnReadyCheck()
    local db = GetDB()
    WriteMacro(db.marker or 5)
    MaybeAnnounce(db.marker or 5)
end

-- ============================================================
-- Activate / Deactivate
-- Everything else (Refresh / OnEnable / OnDisable) comes from SP.ModuleMixin.
-- ============================================================
function FTM:Activate()
    -- The GUI's marker dropdown calls Activate() directly to rewrite the macro,
    -- so the setting is re-checked here rather than only in Refresh().
    if not self:IsOn() then return end
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnWorldEnter")
    self:RegisterEvent("READY_CHECK",           "OnReadyCheck")
    WriteMacro(GetDB().marker or 5)
end

function FTM:Deactivate()
    self:UnregisterAllEvents()
end
