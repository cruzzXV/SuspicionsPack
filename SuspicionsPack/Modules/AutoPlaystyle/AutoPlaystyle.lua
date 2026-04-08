-- SuspicionsPack — AutoPlaystyle Module
-- Forked from Lantern's AutoPlaystyle.
-- Automatically pre-selects your preferred playstyle (Learning / Relaxed /
-- Competitive / Carry Offered) whenever you open the Group Finder listing
-- creation dialog for a Mythic+ group.
--
-- Implementation note:
--   Blizzard_GroupFinder is demand-loaded (only when the player opens the Group
--   Finder UI for the first time). Hooks are installed either immediately if
--   the addon is already loaded, or lazily via ADDON_LOADED otherwise.
--   hooksecurefunc hooks cannot be removed — the module.enabled check inside
--   ApplyPlaystyle handles the on/off state without touching the hooks.
local SP = SuspicionsPack

local AutoPlaystyle = SP:NewModule("AutoPlaystyle", "AceEvent-3.0")
SP.AutoPlaystyle = AutoPlaystyle

-- ============================================================
-- Playstyle table
-- ============================================================
local PLAYSTYLE_GLOBALS = {
    "GROUP_FINDER_GENERAL_PLAYSTYLE1",
    "GROUP_FINDER_GENERAL_PLAYSTYLE2",
    "GROUP_FINDER_GENERAL_PLAYSTYLE3",
    "GROUP_FINDER_GENERAL_PLAYSTYLE4",
}

-- Fallback labels used when Blizzard_GroupFinder hasn't loaded yet
AutoPlaystyle.Labels = {
    [1] = "Learning",
    [2] = "Relaxed",
    [3] = "Competitive",
    [4] = "Carry Offered",
}

local function GetLabel(index)
    return _G[PLAYSTYLE_GLOBALS[index]] or AutoPlaystyle.Labels[index] or tostring(index)
end

-- ============================================================
-- DB helper
-- ============================================================
local function GetDB()
    return SP.GetDB().autoPlaystyle
end

-- ============================================================
-- Core logic
-- ============================================================
local function ApplyPlaystyle(entryCreation)
    if not entryCreation then return end
    local db = GetDB()
    if not db or not db.enabled then return end

    local playstyle = db.playstyle or 3
    if playstyle < 1 or playstyle > 4 then return end

    -- This field is read by the "List Group" confirmation button
    entryCreation.generalPlaystyle = playstyle

    -- Sync the dropdown's visible text
    local dropdown = entryCreation.PlayStyleDropdown
    if dropdown and dropdown.SetText then
        local label = GetLabel(playstyle)
        if label then dropdown:SetText(label) end
    end
end

-- ============================================================
-- Hook installation (once, permanent)
-- ============================================================
local _hooked = false

local function InstallHooks()
    if _hooked then return end
    _hooked = true

    -- Fires when the listing creation dialog is shown (activity already chosen)
    hooksecurefunc("LFGListEntryCreation_Show", function(entryCreation)
        ApplyPlaystyle(entryCreation)
    end)

    -- Fires when the player manually picks an activity in the dialog
    hooksecurefunc("LFGListEntryCreation_Select", function(entryCreation, filters, categoryID, groupID, activityID)
        if not activityID then return end
        local activityInfo = C_LFGList.GetActivityInfoTable(activityID)
        if not activityInfo or not activityInfo.isMythicPlusActivity then return end
        ApplyPlaystyle(entryCreation)
    end)
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function AutoPlaystyle:OnEnable()
    -- Install hooks now if Blizzard_GroupFinder is already loaded,
    -- otherwise wait for its ADDON_LOADED event
    if type(LFGListEntryCreation_Show) == "function" then
        InstallHooks()
    else
        self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded")
    end
end

function AutoPlaystyle:OnAddonLoaded(_, name)
    if name == "Blizzard_GroupFinder" then
        InstallHooks()
        self:UnregisterEvent("ADDON_LOADED")
    end
end

function AutoPlaystyle:OnDisable()
    self:UnregisterAllEvents()
    -- Hooks are permanent; ApplyPlaystyle's db.enabled check handles the off state
end

-- Called by the GUI on any setting change
function AutoPlaystyle.Refresh()
    local db  = GetDB()
    local mod = SP.AutoPlaystyle
    if db and db.enabled then
        if not mod:IsEnabled() then mod:Enable() end
    end
end
