-- SuspicionsPack — Datatexts: Guild, Friends
--
-- Their text is an online count; hovering opens the roster panel
-- (Roster.lua) instead of a tooltip, where a row can be clicked.

local SP = SuspicionsPack
local DT = SP.Datatexts

DT.Register("guild", {
    name   = "Guild",
    group  = "Social",
    label  = "Guild",
    events = { "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "PLAYER_ENTERING_WORLD" },
    OnStart = function()
        DT.Roster.RequestData("guild")
    end,
    -- PLAYER_GUILD_UPDATE: the guild is known now, ask for its roster.
    -- GUILD_ROSTER_UPDATE carries canRequestRosterUpdate; when true the
    -- server will take a new request, as Blizzard's Communities frame does.
    OnEvent = function(o, event, canRequest)
        if event == "PLAYER_GUILD_UPDATE" or (event == "GUILD_ROSTER_UPDATE" and canRequest == true) then
            DT.Roster.RequestData("guild")
        end
        DT.Roster.Refresh("guild")
    end,
    Text = function()
        if not IsInGuild() then return "|cff999999none|r" end
        local _, online = GetNumGuildMembers()
        return tostring(online or 0)
    end,
    Hover = function(o, slot)
        DT.Roster.Show(slot, "guild")
    end,
    Click = function(o, slot, button)
        if button == "LeftButton" and not InCombatLockdown() and ToggleGuildFrame then ToggleGuildFrame() end
    end,
})

DT.Register("friends", {
    name   = "Friends",
    group  = "Social",
    label  = "Friends",
    events = { "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
               "BN_FRIEND_ACCOUNT_OFFLINE", "BN_CONNECTED", "BN_DISCONNECTED", "PLAYER_ENTERING_WORLD" },
    OnStart = function()
        DT.Roster.RequestData("friends")
    end,
    OnEvent = function()
        DT.Roster.Refresh("friends")
    end,
    Text = function()
        local n = C_FriendList and C_FriendList.GetNumOnlineFriends and C_FriendList.GetNumOnlineFriends() or 0
        if BNGetNumFriends then
            local _, online = BNGetNumFriends()
            n = n + (online or 0)
        end
        return tostring(n)
    end,
    Hover = function(o, slot)
        DT.Roster.Show(slot, "friends")
    end,
    Click = function(o, slot, button)
        if button == "LeftButton" and not InCombatLockdown() and ToggleFriendsFrame then ToggleFriendsFrame() end
    end,
})
