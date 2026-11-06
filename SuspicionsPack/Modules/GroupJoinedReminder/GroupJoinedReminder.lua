-- SuspicionsPack — GroupJoinedReminder Module
-- Prints a chat message when you join a Mythic or Mythic+ group via the group finder.
local SP = SuspicionsPack

local GroupJoinedReminder = SP:NewSPModule("GroupJoinedReminder", "groupJoinedReminder")
SP.GroupJoinedReminder = GroupJoinedReminder

-- ============================================================
-- Event handler
--
-- LFG_LIST_JOINED_GROUP passes (searchResultID, groupName), and Blizzard's own
-- join dialog reads the activity from that search result (LFGList.lua,
-- LFGListInviteDialog_Show). LFG_LIST_ACTIVE_ENTRY_UPDATE is not listened to
-- any more: its argument is true when you CREATE a listing, so listing your
-- own Mythic+ group printed "Joined".
-- ============================================================
function GroupJoinedReminder:OnJoinedGroup(_, searchResultID, groupName)
    if not self:IsOn() then return end

    local info       = searchResultID and C_LFGList.GetSearchResultInfo(searchResultID)
    local activityId = info and info.activityIDs and info.activityIDs[1]
    if not activityId then return end

    local activityInfo = C_LFGList.GetActivityInfoTable(activityId)
    if not activityInfo then return end

    -- Only fire for Mythic and Mythic+ activities
    if not (activityInfo.isMythicPlusActivity or activityInfo.isMythicActivity) then return end

    local namePart  = activityInfo.fullName or ""
    local groupPart = groupName and (" " .. groupName) or ""
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
-- OnEnable / OnDisable / Refresh come from SP.ModuleMixin.
-- ============================================================
function GroupJoinedReminder:Activate()
    self:RegisterEvent("LFG_LIST_JOINED_GROUP", "OnJoinedGroup")
end

function GroupJoinedReminder:Deactivate()
    self:UnregisterEvent("LFG_LIST_JOINED_GROUP")
end
