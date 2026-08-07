-- SuspicionsPack — Performance Module
-- Provides FPS-improving tools:
--   • Auto-clear combat log entries on login
--   • Hide screenshot saved/failed notification
local SP = SuspicionsPack

local Performance = SP:NewSPModule("Performance", "performance")
SP.Performance = Performance

-- ============================================================
-- Quest Watch Cleaner — called by the GUI button
--
-- Prints the quest log, then sweeps RemoveQuestWatch across the whole questID
-- space to clear "phantom" watches: a known Blizzard bug leaves quests tracked
-- that are no longer in your quest log.
--
-- The brute-force sweep is DELIBERATE and must not be replaced by walking
-- C_QuestLog.GetNumQuestWatches(): GetQuestIDForQuestWatchIndex returns nil for
-- exactly those phantom entries, so an index walk skips the only thing this
-- button exists to fix.
--
-- The sweep is spread over frames rather than run in one go. 200,000 API calls
-- in a single frame froze the client for several seconds; chunking does the
-- identical work with no visible hitch.
-- ============================================================
local QUEST_ID_MAX   = 200000
local SWEEP_CHUNK    = 4000      -- ~50 frames total
local sweepRunning   = false

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

    -- Command 3: remove all quest watches, chunked across frames
    if sweepRunning then return end
    sweepRunning = true

    local i = 1
    local function Step()
        local stop = math.min(i + SWEEP_CHUNK - 1, QUEST_ID_MAX)
        for id = i, stop do
            C_QuestLog.RemoveQuestWatch(id)
        end
        i = stop + 1
        if i <= QUEST_ID_MAX then
            C_Timer.After(0, Step)
        else
            sweepRunning = false
        end
    end
    Step()
end

-- ============================================================
-- Hide Screenshot Notification
-- Unregisters/re-registers screenshot events on the ActionStatus frame.
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
-- Sound channel count — sets Sound_NumChannels CVar on login if different from desired.
--
-- Sound_NumChannels belongs to Blizzard, not to this module, so the player's own
-- value is snapshotted before the first overwrite and put back on Deactivate.
-- ============================================================
local _origSoundChannels = nil

local function ApplySoundChannels(db)
    -- db.enabled first: AceAddon enables every module at login regardless of the
    -- user's setting, so this used to rewrite Sound_NumChannels every session
    -- even with the Performance module turned off.
    if not (db and db.enabled and db.setSoundChannels) then return end
    local desired = math.max(32, tonumber(db.soundChannelCount) or 32)
    local raw     = C_CVar.GetCVar("Sound_NumChannels")
    local current = tonumber(raw) or 0
    if current ~= desired then
        -- `raw ~= ""` matters: an empty string is truthy in Lua and would be
        -- stored as a restore value that means nothing to the client.
        if _origSoundChannels == nil and raw and raw ~= "" then
            _origSoundChannels = raw
        end
        C_CVar.SetCVar("Sound_NumChannels", tostring(desired))
        if db.soundChannelNotify then
            local T   = SP.Theme
            local ac  = T.accent
            local hex = string.format("|cff%02x%02x%02x", math.floor(ac[1]*255), math.floor(ac[2]*255), math.floor(ac[3]*255))
            print(hex .. "Suspicion's|r |cffFFFFFFPack  Audio channels set to " .. desired .. " (was " .. current .. ")|r")
        end
    end
end

local function RestoreSoundChannels()
    if _origSoundChannels == nil then return end
    C_CVar.SetCVar("Sound_NumChannels", _origSoundChannels)
    _origSoundChannels = nil
end

-- ============================================================
-- Module lifecycle
--
-- OnEnable is overridden rather than inherited from SP.ModuleMixin for one
-- reason: Activate needs to know whether it is running the login pass or a GUI
-- refresh. CombatLogClearEntries used to hang off a PLAYER_LOGIN handler and so
-- ran exactly once per session; without the marker it would fire again every
-- time the user flips a checkbox on the Performance page.
--
-- Refresh / OnDisable come from the mixin.
-- ============================================================
local _atLogin = false

function Performance:OnEnable()
    if IsLoggedIn() then
        self:LoginRefresh()
    else
        self:RegisterEvent("PLAYER_LOGIN", "LoginRefresh")
    end
end

function Performance:LoginRefresh()
    self:UnregisterEvent("PLAYER_LOGIN")
    -- Once per session. ModuleMixin:Refresh re-Enables when the user switches
    -- the module on, which re-enters OnEnable -> LoginRefresh -- so without this
    -- guard the combat log was cleared on every toggle.
    if self._didLoginPass then self:Refresh(); return end
    self._didLoginPass = true
    _atLogin = true
    self:Refresh()
    _atLogin = false
end

function Performance:Activate()
    local db = self:GetDB()
    if _atLogin and db and db.autoClearCombatLog then CombatLogClearEntries() end
    ApplyScreenshotSetting(db and db.hideScreenshotMsg or false)
    ApplySoundChannels(db)
end

function Performance:Deactivate()
    ApplyScreenshotSetting(false)
    RestoreSoundChannels()
end
