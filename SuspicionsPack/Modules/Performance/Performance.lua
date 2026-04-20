-- SuspicionsPack — Performance Module
-- Provides FPS-improving tools:
--   • Auto-clear combat log entries on login
--   • Hide screenshot saved/failed notification
local SP = SuspicionsPack

local Performance = SP:NewModule("Performance", "AceEvent-3.0")
SP.Performance = Performance

local function GetDB()
    return SP.GetDB().performance
end

-- ============================================================
-- Quest Watch Cleaner — called by the GUI button
-- Prints phantom watch info to chat, then removes all watches.
-- ============================================================
function Performance.ClearQuestWatches()
    -- Command 1: total count
    local total = C_QuestLog.GetNumQuestLogEntries()
    print(total)

    -- Command 2: full list with Hidden + Header flags for every entry
    for i = 1, total do
        local q = C_QuestLog.GetInfo(i)
        if q then
            print(format("[%d] %s (Hidden: %s, Header: %s)",
                q.questID, q.title, tostring(q.isHidden), tostring(q.isHeader)))
        end
    end

    -- Command 3: remove all quest watches
    for i = 1, 200000 do
        C_QuestLog.RemoveQuestWatch(i)
    end
end

-- ============================================================
-- Hide Screenshot Notification
-- Mirrors EnhanceQoL's approach: unregister/re-register the
-- screenshot events on the ActionStatus frame.
-- Fully reversible — no hook required.
-- ============================================================
local function ApplyScreenshotSetting(enable)
    local actionStatus = _G.ActionStatus
    if not actionStatus or not actionStatus.UnregisterEvent or not actionStatus.RegisterEvent then return end
    if enable then
        actionStatus:UnregisterEvent("SCREENSHOT_STARTED")
        actionStatus:UnregisterEvent("SCREENSHOT_SUCCEEDED")
        actionStatus:UnregisterEvent("SCREENSHOT_FAILED")
        if actionStatus.Hide then actionStatus:Hide() end
    else
        actionStatus:RegisterEvent("SCREENSHOT_STARTED")
        actionStatus:RegisterEvent("SCREENSHOT_SUCCEEDED")
        actionStatus:RegisterEvent("SCREENSHOT_FAILED")
    end
end

-- ============================================================
-- Sound channel count — mirrors the WeakAura "Set Audio Channels"
-- Sets Sound_NumChannels CVar on login if different from desired.
-- ============================================================
local function ApplySoundChannels(db)
    if not (db and db.setSoundChannels) then return end
    local desired = math.max(32, tonumber(db.soundChannelCount) or 32)
    local current = tonumber(C_CVar.GetCVar("Sound_NumChannels")) or 0
    if current ~= desired then
        C_CVar.SetCVar("Sound_NumChannels", desired)
        if db.soundChannelNotify then
            local T   = SP.Theme
            local ac  = T.accent
            local hex = string.format("|cff%02x%02x%02x", math.floor(ac[1]*255), math.floor(ac[2]*255), math.floor(ac[3]*255))
            print(hex .. "Suspicion's Pack|r  Audio channels set to " .. desired .. " (was " .. current .. ")")
        end
    end
end

-- ============================================================
-- Auto-clear combat log on login
-- ============================================================
function Performance:OnLogin()
    local db = GetDB()
    if db and db.autoClearCombatLog then CombatLogClearEntries() end
    ApplySoundChannels(db)
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function Performance:OnEnable()
    self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
    local db = GetDB()
    ApplyScreenshotSetting(db and db.hideScreenshotMsg or false)
end

function Performance:OnDisable()
    self:UnregisterAllEvents()
    ApplyScreenshotSetting(false)
end

function Performance.Refresh()
    local db  = GetDB()
    local mod = SP.Performance
    if not mod then return end

    -- Master enable gate
    if not (db and db.enabled) then
        if mod:IsEnabled() then mod:Disable() end
        ApplyScreenshotSetting(false)
        return
    end

    local needsModule = db.autoClearCombatLog or db.hideScreenshotMsg or db.setSoundChannels
    if needsModule then
        if not mod:IsEnabled() then mod:Enable() end
    else
        if mod:IsEnabled() then mod:Disable() end
        return
    end

    ApplyScreenshotSetting(db and db.hideScreenshotMsg or false)
end
