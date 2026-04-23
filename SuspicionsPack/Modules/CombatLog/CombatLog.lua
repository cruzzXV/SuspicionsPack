-- SuspicionsPack — CombatLog Module
-- Logic mirrors NaowhQOL's CombatLoggerDisplay.lua exactly.
-- Adaptation: no ZoneUtil → zone data built from GetInstanceInfo() on PLAYER_ENTERING_WORLD.
local SP = SuspicionsPack

local CombatLog = SP:NewModule("CombatLog", "AceEvent-3.0")
SP.CombatLog = CombatLog

local isLogging = false

-- ============================================================
-- Helpers
-- ============================================================
local function GetDB()
    return SP.GetDB().combatLog
end

local function GetAccentHex()
    local T = SP.Theme
    if T and T.accent then
        return string.format("%02X%02X%02X",
            math.floor(T.accent[1] * 255),
            math.floor(T.accent[2] * 255),
            math.floor(T.accent[3] * 255))
    end
    return "e51039"
end

-- ============================================================
-- ACL prompt (mirrors NaowhQOL_ACL_PROMPT)
-- ============================================================
StaticPopupDialogs["SUSPICIONSPACK_ACL_PROMPT"] = {
    text = "%s",
    button1 = "Enable",
    button2 = "Skip",
    OnAccept = function()
        C_CVar.SetCVar("advancedCombatLogging", 1)
        ReloadUI()
    end,
    timeout        = 0,
    whileDead      = false,
    hideOnEscape   = true,
    preferredIndex = 3,
}

local function CheckAdvancedLogging()
    local acl = C_CVar.GetCVar("advancedCombatLogging")
    if acl ~= "1" then
        local promptText = "|cff" .. GetAccentHex() .. "Suspicion's Pack|r\n\n"
            .. "Advanced Combat Logging is not enabled.\nEnable it now? (Requires reload)"
        StaticPopup_Show("SUSPICIONSPACK_ACL_PROMPT", promptText)
        return false
    end
    return true
end

-- ============================================================
-- Per-instance prompt (mirrors NAOWHQOL_COMBATLOG_PROMPT)
-- ============================================================
StaticPopupDialogs["SUSPICIONSPACK_COMBATLOG_PROMPT"] = {
    text = "%s",
    button1 = "Enable",
    button2 = "Skip",
    OnAccept = function(self)
        local data = self.data
        if not data then return end

        local db = GetDB()
        if not db then return end
        db.instances = db.instances or {}

        local key = data.instanceID .. ":" .. data.difficulty
        db.instances[key] = {
            enabled  = true,
            name     = data.zoneName      or "",
            diffName = data.difficultyName or "",
        }

        if CheckAdvancedLogging() then
            LoggingCombat(true)
            isLogging = true
        end
    end,
    OnCancel = function(self)
        local data = self.data
        if not data then return end

        local db = GetDB()
        if not db then return end
        db.instances = db.instances or {}

        local key = data.instanceID .. ":" .. data.difficulty
        db.instances[key] = {
            enabled  = false,
            name     = data.zoneName      or "",
            diffName = data.difficultyName or "",
        }

        if isLogging then
            LoggingCombat(false)
            isLogging = false
        end
    end,
    timeout        = 0,
    whileDead      = false,
    hideOnEscape   = true,
    preferredIndex = 3,
}

-- ============================================================
-- Zone logic (mirrors NaowhQOL OnZoneChanged exactly)
-- ============================================================
local function OnZoneChanged(zoneData)
    local db = GetDB()
    if not db or not db.enabled then
        if isLogging then
            LoggingCombat(false)
            isLogging = false
        end
        return
    end

    local shouldTrack = false
    if zoneData.instanceType == "raid" then
        shouldTrack = true
    elseif zoneData.instanceType == "party" and zoneData.difficulty == 8 then
        shouldTrack = true
    end

    if not shouldTrack then
        if isLogging then
            LoggingCombat(false)
            isLogging = false
        end
        return
    end

    db.instances = db.instances or {}
    local key = zoneData.instanceID .. ":" .. zoneData.difficulty
    local saved = db.instances[key]

    if saved and saved.enabled == true then
        if not isLogging then
            if CheckAdvancedLogging() then
                LoggingCombat(true)
                isLogging = true
            end
        end
    elseif saved and saved.enabled == false then
        if isLogging then
            LoggingCombat(false)
            isLogging = false
        end
    else
        if not isLogging then
            if not CheckAdvancedLogging() then
                return
            end
            LoggingCombat(true)
            isLogging = true
        end

        local promptText = "|cff" .. GetAccentHex() .. "Suspicion's Pack|r\n\n"
            .. string.format(
                "Enable combat logging for\n|cffFF8C00%s|r (%s)?",
                zoneData.zoneName,
                zoneData.difficultyName
            )

        local dialog = StaticPopup_Show("SUSPICIONSPACK_COMBATLOG_PROMPT", promptText)
        if dialog then
            dialog.data = {
                instanceID     = zoneData.instanceID,
                difficulty     = zoneData.difficulty,
                zoneName       = zoneData.zoneName,
                difficultyName = zoneData.difficultyName,
            }
        end
    end
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function CombatLog:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnterWorld")
    self:RegisterEvent("CHALLENGE_MODE_START",  "OnChallengeMode")

    local db = GetDB()
    db.instances = db.instances or {}

    isLogging = LoggingCombat()

    if db.enabled then
        CheckAdvancedLogging()
    end
end

function CombatLog:OnDisable()
    self:UnregisterAllEvents()
    if isLogging then
        LoggingCombat(false)
        isLogging = false
    end
end

-- Mirrors NaowhQOL PLAYER_ENTERING_WORLD + ZoneUtil callback combined
function CombatLog:OnEnterWorld()
    isLogging = LoggingCombat()

    local zoneName, instanceType, difficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()
    OnZoneChanged({
        instanceType   = instanceType,
        difficulty     = difficultyID,
        instanceID     = instanceID,
        zoneName       = zoneName      or "",
        difficultyName = difficultyName or "",
    })
end

-- Mirrors NaowhQOL CHALLENGE_MODE_START handler exactly
function CombatLog:OnChallengeMode()
    local db = GetDB()
    if db and db.enabled and not isLogging then
        if CheckAdvancedLogging() then
            LoggingCombat(true)
            isLogging = true
        end
    end
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

-- Mirrors NaowhQOL ForceZoneCheck
function CombatLog.ForceZoneCheck()
    CheckAdvancedLogging()
    local zoneName, instanceType, difficultyID, difficultyName, _, _, _, instanceID = GetInstanceInfo()
    OnZoneChanged({
        instanceType   = instanceType,
        difficulty     = difficultyID,
        instanceID     = instanceID,
        zoneName       = zoneName      or "",
        difficultyName = difficultyName or "",
    })
end
