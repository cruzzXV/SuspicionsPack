-- SuspicionsPack — GroupJoinedReminder Module
-- Forked from ItruliaQOL's GroupJoinedReminder.
-- Prints a chat message when you join a Mythic or Mythic+ group via the group finder.
local SP = SuspicionsPack

local GroupJoinedReminder = SP:NewModule("GroupJoinedReminder", "AceEvent-3.0")
SP.GroupJoinedReminder = GroupJoinedReminder

-- ============================================================
-- DB helper
-- ============================================================
local function GetDB()
    return SP.GetDB().groupJoinedReminder
end

-- ============================================================
-- Internal state
-- ============================================================
local pendingGroupName = nil

-- ============================================================
-- Event handlers
-- ============================================================
function GroupJoinedReminder:OnGroupLeft()
    pendingGroupName = nil
end

function GroupJoinedReminder:OnLFGEvent(event, ...)
    local db = GetDB()
    if not db or not db.enabled then return end

    -- Cache the group name from the join event
    if event == "LFG_LIST_JOINED_GROUP" then
        local _, groupName = ...
        pendingGroupName = groupName
    end

    -- Both events pass `created` as their first vararg
    local created = ...
    if not created then return end

    local entryData = C_LFGList.GetActiveEntryInfo()
    if not entryData then return end

    -- Grab first activity ID
    local activityId = nil
    for _, id in ipairs(entryData.activityIDs) do
        activityId = id
        break
    end
    if not activityId then return end

    local activityInfo = C_LFGList.GetActivityInfoTable(activityId)
    if not activityInfo then return end

    -- Only fire for Mythic and Mythic+ activities
    if not (activityInfo.isMythicPlusActivity or activityInfo.isMythicActivity) then return end

    local namePart  = activityInfo.fullName or ""
    local groupPart = pendingGroupName and (" " .. pendingGroupName) or ""
    local fullName  = namePart .. groupPart

    local ac  = (SP.Theme and SP.Theme.accent) or { 1, 0, 0 }
    local hex = string.format("|cff%02X%02X%02X",
        math.floor(ac[1] * 255 + 0.5),
        math.floor(ac[2] * 255 + 0.5),
        math.floor(ac[3] * 255 + 0.5))
    print(hex .. "SuspicionsPack|r : Joined |cffffffff" .. fullName .. "|r")
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function GroupJoinedReminder:OnEnable()
    local db = GetDB()
    if db and db.enabled then
        self:RegisterEvent("GROUP_LEFT",                   "OnGroupLeft")
        self:RegisterEvent("LFG_LIST_JOINED_GROUP",        "OnLFGEvent")
        self:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", "OnLFGEvent")
    end
end

function GroupJoinedReminder:OnDisable()
    self:UnregisterAllEvents()
end

-- Called by the GUI enable toggle
function GroupJoinedReminder.Refresh()
    local db  = GetDB()
    local mod = SP.GroupJoinedReminder
    if db and db.enabled then
        if not mod:IsEnabled() then mod:Enable() end
        mod:RegisterEvent("GROUP_LEFT",                   "OnGroupLeft")
        mod:RegisterEvent("LFG_LIST_JOINED_GROUP",        "OnLFGEvent")
        mod:RegisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", "OnLFGEvent")
    else
        mod:UnregisterEvent("GROUP_LEFT")
        mod:UnregisterEvent("LFG_LIST_JOINED_GROUP")
        mod:UnregisterEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE")
    end
end
