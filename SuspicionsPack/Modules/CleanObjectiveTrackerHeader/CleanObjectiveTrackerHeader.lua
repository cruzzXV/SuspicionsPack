-- SuspicionsPack — CleanObjectiveTrackerHeader Module
-- Hides the "Objectives" header at the top of the quest tracker.
local SP = SuspicionsPack

local COTH = SP:NewSPModule("CleanObjectiveTrackerHeader", "cleanObjectiveTrackerHeader")
SP.CleanObjectiveTrackerHeader = COTH

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
-- Activate / Deactivate
-- Everything else (Refresh / OnEnable / OnDisable) comes from SP.ModuleMixin.
-- ============================================================
function COTH:Activate()
    -- ObjectiveTrackerFrame is lazy-loaded — defer to be safe
    C_Timer.After(1, function()
        -- C_Timer.After cannot be cancelled, so re-read the setting instead:
        -- the user may have switched the module off inside this one-second window.
        if not self:IsOn() then return end
        HideHeader()
        -- Hook Show() once so Blizzard re-shows don't fight us
        local tracker = _G.ObjectiveTrackerFrame
        if tracker and tracker.Header and not hooked then
            hooked = true
            -- hooksecurefunc can never be removed, so the hook stays installed
            -- for the whole session and gates itself on the live setting.
            hooksecurefunc(tracker.Header, "Show", function()
                if self:IsOn() then
                    HideHeader()
                end
            end)
        end
    end)
end

function COTH:Deactivate()
    ShowHeader()
end
