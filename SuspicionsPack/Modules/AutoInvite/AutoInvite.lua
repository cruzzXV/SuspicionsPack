-- SuspicionsPack — AutoInvite Module
-- Automatically invites players who whisper a keyword.
-- Default keywords: "inv", "123"
local SP = SuspicionsPack

local AutoInvite = SP:NewSPModule("AutoInvite", "autoInvite")
SP.AutoInvite = AutoInvite

-- ============================================================
-- Helpers
-- ============================================================
local function StripRealm(name)
    return (name:match("^([^%-]+)")) or name
end

-- ============================================================
-- Guild member cache (rebuilt on GUILD_ROSTER_UPDATE)
-- Keys are lowercase short names (no realm).
-- ============================================================
local guildCache = {}

local function UpdateGuildCache()
    wipe(guildCache)
    local n = GetNumGuildMembers()
    for i = 1, n do
        local name = GetGuildRosterInfo(i)
        if name then
            guildCache[StripRealm(name):lower()] = true
        end
    end
end

-- ============================================================
-- Relationship checks
-- ============================================================
local function IsFriend(senderName, senderGUID)
    -- Primary: GUID-based check (works for offline friends too)
    if senderGUID and senderGUID ~= "" then
        if C_FriendList.IsFriend and C_FriendList.IsFriend(senderGUID) then
            return true
        end
    end
    -- Fallback: scan friends list by name
    local shortName = StripRealm(senderName):lower()
    local numFriends = C_FriendList.GetNumFriends()
    for i = 1, numFriends do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.name and StripRealm(info.name):lower() == shortName then
            return true
        end
    end
    return false
end

local function IsGuildMember(senderName)
    return guildCache[StripRealm(senderName):lower()] == true
end

-- ============================================================
-- Keyword matching — exact, case-insensitive, trims whitespace
-- ============================================================
local function MatchesKeyword(message, keywords)
    -- Some whispers (system messages, protected channels) are "secret string values".
    -- No string operation is allowed on them — issecretvalue() guards against the crash.
    if issecretvalue and issecretvalue(message) then return false end
    local msg = string.match(string.lower(message), "^%s*(.-)%s*$")
    for _, kw in ipairs(keywords) do
        if msg == string.match(string.lower(kw), "^%s*(.-)%s*$") then
            return true
        end
    end
    return false
end

-- ============================================================
-- Module lifecycle
-- OnEnable / OnDisable / Refresh come from SP.ModuleMixin.
-- ============================================================
function AutoInvite:Activate()
    self:RegisterEvent("CHAT_MSG_WHISPER", "OnWhisper")
    self:ApplyGuildWatch()
end

function AutoInvite:Deactivate()
    self:UnregisterEvent("CHAT_MSG_WHISPER")
    self:UnregisterEvent("GUILD_ROSTER_UPDATE")
    wipe(guildCache)
end

-- The guild cache is read from exactly one place: the `db.inviteGuild` branch of
-- OnWhisper, which is only reachable when inviteAll is explicitly false. With
-- any other setting the whole roster was being walked on every
-- GUILD_ROSTER_UPDATE to build a table nothing ever looked at, so the event is
-- only registered when the cache is actually needed.
--
-- Note `db.inviteAll == false`, not `not db.inviteAll`: nil means "key predates
-- this option", which OnWhisper treats as invite-everyone.
function AutoInvite:ApplyGuildWatch()
    local db = self:GetDB()
    if db and db.inviteAll == false and db.inviteGuild then
        self:RegisterEvent("GUILD_ROSTER_UPDATE", "OnRosterUpdate")
        if IsInGuild() then
            C_GuildInfo.GuildRoster()
            UpdateGuildCache()
        end
    else
        self:UnregisterEvent("GUILD_ROSTER_UPDATE")
        wipe(guildCache)
    end
end

function AutoInvite:OnRosterUpdate()
    UpdateGuildCache()
end

-- CHAT_MSG_WHISPER params:
--   event, message, sender, language, channelStr, target, flags,
--   _, channelNum, channelName, _, lineID, senderGUID
function AutoInvite:OnWhisper(_, message, sender, _, _, _, _, _, _, _, _, _, senderGUID)
    local db = self:GetDB()
    if not db or not db.enabled then return end

    -- Keyword check
    local keywords = db.keywords
    if not keywords or #keywords == 0 then return end
    if not MatchesKeyword(message, keywords) then return end

    -- Must be group leader (or not in a group yet) to invite
    if IsInGroup() and not UnitIsGroupLeader("player") then return end

    -- Group full check
    local maxSize = IsInRaid() and 40 or 5
    local curSize = GetNumGroupMembers()
    if curSize >= maxSize then return end

    -- Relationship check
    -- Treat nil as true for inviteAll: handles existing SavedVariables that pre-date
    -- the inviteAll key (AceDB may not have merged it yet on first load).
    local canInvite = false
    if db.inviteAll ~= false then
        canInvite = true
    elseif db.inviteFriends and IsFriend(sender, senderGUID) then
        canInvite = true
    elseif db.inviteGuild and IsGuildMember(sender) then
        canInvite = true
    end

    if canInvite then
        C_PartyInfo.InviteUnit(sender)
        print("|cffe51039SuspicionsPack|r : invited |cffffffff" .. StripRealm(sender) .. "|r")
    end
end
