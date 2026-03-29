-- SuspicionsPack — MeterReset Module
-- Forked from WildUTools "Ask to reset damage meter in instances".
-- When you enter a dungeon or raid instance, a popup asks if you want
-- to reset your damage meter. Supports Details!, Skada, and Recount.
local SP = SuspicionsPack

local MeterReset = SP:NewModule("MeterReset", "AceEvent-3.0")
SP.MeterReset = MeterReset

-- ============================================================
-- Helpers
-- ============================================================
local function GetDB()
    return SP.GetDB().meterReset
end

-- Reset Blizzard's built-in damage meter.
-- Details! is now a reskin of this same system, so one call covers both.
local function ResetAllMeters()
    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        pcall(C_DamageMeter.ResetAllCombatSessions)
    end
end

-- ============================================================
-- Static popup definition (guarded so reload never double-defines it)
-- ============================================================
local DIALOG_KEY = "SP_METER_RESET_CONFIRM"

if not StaticPopupDialogs[DIALOG_KEY] then
    StaticPopupDialogs[DIALOG_KEY] = {
        text         = "Do you want to reset damage meter?",
        button1      = "Yes",
        button2      = "No",
        OnAccept     = function() ResetAllMeters() end,
        timeout      = 0,
        whileDead    = false,
        hideOnEscape = true,
    }
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function MeterReset:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnterWorld")
    self:RegisterEvent("PLAYER_LEAVING_WORLD",  "OnLeavingWorld")
end

function MeterReset:OnDisable()
    self:UnregisterAllEvents()
    StaticPopup_Hide(DIALOG_KEY)
end

function MeterReset:OnLeavingWorld()
    -- Hide the popup immediately if the player zones out before answering
    StaticPopup_Hide(DIALOG_KEY)
end

function MeterReset:OnEnterWorld(_, isLogin, isReload)
    -- Skip the very first login / UI reload; only fire on actual zone transitions
    if isLogin or isReload then return end

    local db = GetDB()
    if not db or not db.enabled then return end

    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "party" or instanceType == "raid") then
        -- Wait for Blizzard's own entry popups to settle before showing ours
        C_Timer.After(1.5, function()
            local still = IsInInstance()
            if still then
                StaticPopup_Hide(DIALOG_KEY)   -- clear any stale copy first
                StaticPopup_Show(DIALOG_KEY)
            end
        end)
    end
end

-- Called by GUI enable toggle
function MeterReset.Refresh()
    local db = GetDB()
    local mod = SP.MeterReset
    if db and db.enabled then
        if not mod:IsEnabled() then mod:Enable() end
    else
        if mod:IsEnabled() then mod:Disable() end
    end
end
