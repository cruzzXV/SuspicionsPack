-- SuspicionsPack — CleanObjectiveTrackerHeader Module
-- Hides the "Objectives" header at the top of the quest tracker.
local SP = SuspicionsPack

local COTH = SP:NewSPModule("CleanObjectiveTrackerHeader", "cleanObjectiveTrackerHeader")
SP.CleanObjectiveTrackerHeader = COTH

-- ============================================================
-- Apply / Restore
-- ============================================================
local hooked = false
local buttonHidden = false  -- true only while WE hid the minimize button

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

-- The red "collapse all" button at the right end of the header. It stays
-- while the tracker is collapsed: with the header gone, it is the only way to
-- open the tracker again.
local function UpdateMinimizeButton()
    local tracker = _G.ObjectiveTrackerFrame
    local button  = tracker and tracker.Header and tracker.Header.MinimizeButton
    if not button then return end
    local db   = COTH:GetDB()
    local hide = COTH:IsOn() and db.hideMinimizeButton and not tracker:IsCollapsed()
    if hide then
        button:Hide()
        buttonHidden = true
    elseif buttonHidden then
        -- Only undo our own Hide.
        buttonHidden = false
        button:Show()
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
        UpdateMinimizeButton()
        -- Hook Show() once so Blizzard re-shows don't fight us
        local tracker = _G.ObjectiveTrackerFrame
        if tracker and tracker.Header and not hooked then
            hooked = true
            -- hooksecurefunc can never be removed, so the hook stays installed
            -- for the whole session and gates itself on the live setting.
            -- The tracker re-shows its header on every update, collapsing and
            -- expanding included, which is when the button has to follow.
            hooksecurefunc(tracker.Header, "Show", function()
                if self:IsOn() then
                    HideHeader()
                end
                UpdateMinimizeButton()
            end)
            -- Forever shows the button again when leaving gamepad mode.
            tracker.Header.MinimizeButton:HookScript("OnShow", UpdateMinimizeButton)
        end
    end)
end

function COTH:Deactivate()
    ShowHeader()
    UpdateMinimizeButton()
end
