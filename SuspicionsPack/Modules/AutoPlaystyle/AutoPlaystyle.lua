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
-- Auto-select Mythic+ group when dialog opens
-- ============================================================

--- Find the groupID for Mythic+ within a given categoryID.
--- Uses pcall around C_LFGList calls so unknown API variants don't hard-error.
local function FindMythicPlusGroupID(categoryID)
    if not categoryID then return nil end

    local ok, groups = pcall(C_LFGList.GetAvailableActivityGroups, categoryID)
    if not ok or type(groups) ~= "table" then
        SP:Debug("AutoPlaystyle", "[M+Auto] GetAvailableActivityGroups failed for cat=", categoryID)
        return nil
    end

    for _, groupID in ipairs(groups) do
        local ok2, acts = pcall(C_LFGList.GetAvailableActivities, categoryID, groupID)
        if ok2 and type(acts) == "table" then
            for _, aID in ipairs(acts) do
                local info = C_LFGList.GetActivityInfoTable(aID)
                if info and info.isMythicPlusActivity then
                    SP:Debug("AutoPlaystyle", "[M+Auto] Found M+ groupID=", groupID)
                    return groupID
                end
            end
        end
    end
    return nil
end

--- Called from the LFGListEntryCreation_Show hook.
--- Deferred by one frame so the dialog finishes initialising before we redirect.
local function SelectDefaultMythicPlusGroup(entryCreation, openActivityID)
    local db = GetDB()
    if not db or not db.enabled or not db.defaultMythicPlus then return end

    -- Per CLAUDE.md: debug print to verify args before relying on them.
    SP:Debug("AutoPlaystyle", "[M+Auto] Show fired openActivityID=", tostring(openActivityID),
        "entryCreation.categoryID=", tostring(entryCreation and entryCreation.categoryID))

    C_Timer.After(0, function()
        if not entryCreation or not entryCreation:IsShown() then return end

        -- Derive categoryID: try the passed activityID first, then frame field.
        local categoryID = nil
        if openActivityID then
            local info = C_LFGList.GetActivityInfoTable(openActivityID)
            SP:Debug("AutoPlaystyle", "[M+Auto] openActivity isMythicPlus=",
                tostring(info and info.isMythicPlusActivity), "cat=", tostring(info and info.categoryID))
            if info then categoryID = info.categoryID end
        end
        if not categoryID then
            categoryID = entryCreation.categoryID  -- may be nil; safe to pass to FindMythicPlusGroupID
        end

        local mpGroupID = FindMythicPlusGroupID(categoryID)

        if mpGroupID then
            SP:Debug("AutoPlaystyle", "[M+Auto] Auto-selecting M+ groupID=", mpGroupID, "cat=", categoryID)
            LFGListEntryCreation_Select(entryCreation, nil, categoryID, mpGroupID, nil)
        else
            SP:Debug("AutoPlaystyle", "[M+Auto] M+ group not found for categoryID=", tostring(categoryID))
        end
    end)
end

-- ============================================================
-- Hook installation (once, permanent)
-- ============================================================
local _hooked = false

local function InstallHooks()
    if _hooked then return end
    _hooked = true

    -- Fires when the listing creation dialog is shown (activity already chosen)
    hooksecurefunc("LFGListEntryCreation_Show", function(entryCreation, activityID)
        ApplyPlaystyle(entryCreation)
        SelectDefaultMythicPlusGroup(entryCreation, activityID)
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
