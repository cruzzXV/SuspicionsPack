-- SuspicionsPack — CleanObjectiveTrackerHeader Module
-- Hides the "Objectives" header at the top of the quest tracker.
local SP = SuspicionsPack

local COTH = SP:NewModule("CleanObjectiveTrackerHeader", "AceEvent-3.0")
SP.CleanObjectiveTrackerHeader = COTH

-- ============================================================
-- DB helper
-- ============================================================
local function GetDB()
    return SP.GetDB().cleanObjectiveTrackerHeader
end

-- ============================================================
-- Apply / Restore
-- ============================================================
local hooked = false

local function HideHeader()
    local tracker = _G.ObjectiveTrackerFrame
    if not tracker then return end
    if tracker.Header then
        tracker.Header.Background:Hide()
        tracker.Header.Text:Hide()
    end
end

local function ShowHeader()
    local tracker = _G.ObjectiveTrackerFrame
    if not tracker then return end
    if tracker.Header then
        tracker.Header.Background:Show()
        tracker.Header.Text:Show()
    end
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function COTH:Activate()
    -- ObjectiveTrackerFrame is lazy-loaded — defer to be safe
    C_Timer.After(1, function()
        HideHeader()
        -- Hook Show() once so Blizzard re-shows don't fight us
        local tracker = _G.ObjectiveTrackerFrame
        if tracker and tracker.Header and not hooked then
            hooked = true
            hooksecurefunc(tracker.Header, "Show", function()
                local db = GetDB()
                if db and db.enabled then
                    HideHeader()
                end
            end)
        end
    end)
end

function COTH:Deactivate()
    ShowHeader()
end

function COTH.Refresh()
    local db  = GetDB()
    local mod = SP.CleanObjectiveTrackerHeader
    if not mod then return end
    if db and db.enabled then
        if not mod:IsEnabled() then mod:Enable() end
        mod:Activate()
    else
        if mod:IsEnabled() then mod:Disable() end
        mod:Deactivate()
    end
end

function COTH:OnEnable()
    if IsLoggedIn() then
        local db = GetDB()
        if db and db.enabled then self:Activate() end
    else
        self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
    end
end

function COTH:OnLogin()
    self:UnregisterEvent("PLAYER_LOGIN")
    local db = GetDB()
    if db and db.enabled then self:Activate() end
end

function COTH:OnDisable()
    self:UnregisterAllEvents()
    self:Deactivate()
end
