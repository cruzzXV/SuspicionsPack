-- SuspicionsPack Options — Clean objective header

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "cleanobjectivetrackerheader",
    name     = "Clean objective header",
    category = "interface",
    dbKey    = "cleanObjectiveTrackerHeader",
    keywords = "objective tracker quest header title clean hide space",
    build = function(parent)
        local page = GUI.ModulePage(parent, "cleanObjectiveTrackerHeader", "CleanObjectiveTrackerHeader",
            "Clean objective header",
            "Hides the \"Objectives\" title line at the top of the quest tracker on the left " ..
            "of the screen, saving one line of vertical space.",
            "Hide tracker header")
        page:Finish()
    end,
}
