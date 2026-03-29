-- SuspicionsPack — FocusTargetMarker
-- Forked from ItruliaQoL by Itrulia.
local SP = SuspicionsPack

local FTM = SP:NewModule("FocusTargetMarker", "AceEvent-3.0")
SP.FocusTargetMarker = FTM

local MACRO_NAME = "FocusTargetMarker"
local MACRO_ICON = 132219

local MARKER_TEXT = {
    [1] = "Star", [2] = "Circle", [3] = "Diamond", [4] = "Triangle",
    [5] = "Moon",  [6] = "Square", [7] = "Cross",   [8] = "Skull",
}

local function GetDB()
    return SP.GetDB().focusTargetMarker
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
    local inInstance, instanceType = IsInInstance()
    if not inInstance or instanceType ~= "party" or InCombatLockdown() then return end
    C_ChatInfo.SendChatMessage(("My kick marker is {%s}"):format(MARKER_TEXT[markerIndex] or "?"), "PARTY")
end

function FTM:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnWorldEnter")
    self:RegisterEvent("READY_CHECK",           "OnReadyCheck")
    WriteMacro(GetDB().marker or 5)
end

function FTM:OnDisable()
    self:UnregisterAllEvents()
end

function FTM:OnWorldEnter()
    WriteMacro(GetDB().marker or 5)
end

function FTM:OnReadyCheck()
    local db = GetDB()
    WriteMacro(db.marker or 5)
    MaybeAnnounce(db.marker or 5)
end

function FTM:Refresh()
    local db = GetDB()
    if db and db.enabled then self:Activate() else self:Deactivate() end
end

function FTM:Activate()
    if not self:IsEnabled() then self:Enable() end
    WriteMacro(GetDB().marker or 5)
end

function FTM:Deactivate()
    self:Disable()
end
