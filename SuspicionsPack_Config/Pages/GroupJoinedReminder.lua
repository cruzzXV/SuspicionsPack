-- SuspicionsPack Options — Group joined reminder
--
-- A module with nothing but an on/off switch: the whole page is the master
-- toggle, as with Fast loot.

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "groupjoinedreminder",
    name     = "Group joined reminder",
    category = "mythic",
    dbKey    = "groupJoinedReminder",
    keywords = "group joined reminder mythic keystone group finder lfg chat message",
    build = function(parent)
        local page = GUI.ModulePage(parent, "groupJoinedReminder", "GroupJoinedReminder",
            "Group joined reminder",
            "Prints the name of the group in chat when you join a Mythic or " ..
            "Mythic+ group through the group finder, so you can tell at a glance " ..
            "which listing you were accepted into.",
            "Enable group joined reminder")
        page:Finish()
    end,
}
