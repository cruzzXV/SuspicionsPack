-- SuspicionsPack Options — Clean objective header

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "cleanobjectivetrackerheader",
    name     = "Clean objective header",
    category = "interface",
    dbKey    = "cleanObjectiveTrackerHeader",
    keywords = "objective tracker quest header title clean hide space collapse minimize button",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "cleanObjectiveTrackerHeader", "CleanObjectiveTrackerHeader",
            "Clean objective header",
            "Hides the \"Objectives\" title line at the top of the quest tracker on the left " ..
            "of the screen, saving one line of vertical space.",
            "Hide tracker header")

        c1:Toggle{ key = "hideMinimizeButton", label = "Hide collapse button",
                   desc = "Also hides the red button at the right end of the header. It comes " ..
                          "back while the tracker is collapsed, so it can always be opened again." }

        page:Finish()
    end,
}
