-- SuspicionsPack — CombatLog Module
-- Automatically starts the combat log (LoggingCombat) when entering a dungeon
-- or raid instance. Optionally stops it when leaving.
local SP = SuspicionsPack

local CombatLog = SP:NewModule("CombatLog", "AceEvent-3.0")
SP.CombatLog = CombatLog

-- ============================================================
-- Helpers
-- ============================================================
local function GetDB()
    return SP.GetDB().combatLog
end

-- ============================================================
-- Event handlers
-- ============================================================
function CombatLog:OnEnterWorld()
    local db = GetDB()
    if not db or not db.enabled then return end

    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "party" or instanceType == "raid") then
        if not LoggingCombat() then
            LoggingCombat(true)
        end
    end
end

function CombatLog:OnLeavingWorld()
    local db = GetDB()
    if not db or not db.enabled then return end
    if not db.stopOnLeave then return end

    if LoggingCombat() then
        LoggingCombat(false)
    end
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function CombatLog:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnterWorld")
    self:RegisterEvent("PLAYER_LEAVING_WORLD",  "OnLeavingWorld")
end

function CombatLog:OnDisable()
    self:UnregisterAllEvents()
end

-- Called by GUI toggle
function CombatLog.Refresh()
    local db  = GetDB()
    local mod = SP.CombatLog
    if db and db.enabled then
        if not mod:IsEnabled() then mod:Enable() end
    else
        if mod:IsEnabled() then mod:Disable() end
    end
end
