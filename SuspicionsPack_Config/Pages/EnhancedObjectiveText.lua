-- SuspicionsPack Options — Enhanced objective text
--
-- The Preview button used to be reachable with the module switched off: the old
-- cascade only faded it, and EOT.Preview() calls Apply(), which resizes and
-- repositions UIErrorsFrame. With the module off nothing ever called Restore(),
-- so a click on a greyed-out button left Blizzard's error frame permanently
-- resized. GateAll blocks the input outright.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

GUI.RegisterPage{
    id       = "enhancedobjectivetext",
    name     = "Enhanced objective text",
    category = "interface",
    dbKey    = "enhancedObjectiveText",
    keywords = "objective error text ui errors frame message size quest complete",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "enhancedObjectiveText", "EnhancedObjectiveText",
            "Enhanced objective text",
            "Replaces WoW's small stacked error and objective messages with a single large " ..
            "centred line, so spell errors, objective completions and system notices are " ..
            "readable at a glance during combat.",
            "Enable enhanced objective text")

        c1:ButtonRow{
            text = "Preview",
            desc = "Shows a sample message with the current settings.",
            onClick = function()
                if SP.EnhancedObjectiveText then SP.EnhancedObjectiveText.Preview() end
            end,
        }

        local c2 = page:Card("Appearance", "Size and vertical position of the on-screen text.")
        c2:Slider{ key = "fontSize", label = "Font size", min = 14, max = 40, step = 1 }
        c2:Slider{ key = "y", label = "Vertical position",
                   desc = "Offset from the centre of the screen.",
                   min = -400, max = 400, step = 1 }

        page:Finish()
    end,
}
