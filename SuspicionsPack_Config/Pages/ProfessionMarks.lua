-- SuspicionsPack Options — Profession marks (WoW: Forever only)
--
-- Listed only where the module is: the .toc line carries the same
-- [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic] gate.
--
-- Everything goes through the page's standard onChange, which reaches
-- ProfessionMarks:Refresh -> Activate -> repaint the open bags.

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "professionmarks",
    name     = "Profession marks",
    category = "items",
    dbKey    = "professionMarks",
    keywords = "profession professions logo icon mark bag bags reagent material tool recipe craft " ..
               "crafting keep sell vendor tooltip",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "professionMarks", "ProfessionMarks",
            "Profession marks",
            "Puts a profession's icon on the bag items it wants: reagents, tools and recipes " ..
            "you have not learned. Only for this character's professions.",
            nil, "Display")

        c1:Toggle{ key = "tooltip", label = "Tooltip line",
                   desc = "Says which professions use the item, yours and the others." }

        page:Finish()
    end,
}
