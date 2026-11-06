-- SuspicionsPack Options — Macro Action Bar (WoW: Forever only)
--
-- Listed only where the module is: the .toc line carries the same
-- [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic] gate.
--
-- Only the settings the original addon kept in its Options > AddOns panel live
-- here. Everything else is on its spellbook page: the cog for the page, a
-- right-click for each macro. The module reads these two live, so the page's
-- standard onChange (MacroActionBar:Refresh) has nothing to redraw.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

GUI.RegisterPage{
    id       = "macroactionbar",
    name     = "Macro Action Bar",
    category = "interface",
    dbKey    = "macroActionBar",
    keywords = "macro macros action bar bars spellbook spell book tab mouseover focus cursor modifier " ..
               "shift ctrl alt sequence castsequence tooltip",
    tip      = "Adds a spellbook tab with a macro for each of your spells, ready to drag to your bars. Right-click one to choose who it casts on, like your mouseover or your focus.",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "macroActionBar", "MacroActionBar",
            "Macro Action Bar",
            "A spellbook tab of one-click macros for your class's spells. Right-click one, on " ..
            "the page or on your action bars, to choose where it casts and what it does around the cast.",
            nil, "General")

        c1:Toggle{ key = "barMacroText", label = "Macro text on Alt",
                   desc = "Hold Alt over a macro on your action bars to read its text." }
        c1:Toggle{ key = "macrosFullPopup", label = "Warn when macros are full",
                   desc = "A window says so when there is no free macro slot left." }
        c1:ButtonRow{
            text  = "Open",
            width = 100,
            desc  = "Opens the spellbook on the macro page. Also /spack macros. Not in combat.",
            onClick = function()
                if SP.MacroActionBar then SP.MacroActionBar.OpenPage() end
            end,
        }

        local c2 = page:Card("Good to know")
        if SP.MacroActionBar and SP.MacroActionBar.IsBlocked() then
            c2:Note("Off for now: the Macro Action Bar addon is loaded. Disable it in the AddOns list and reload.")
        end
        c2:Note("The page is the \"M\" tab on the spellbook's right edge. Closing the spellbook leaves it, so the spellbook always reopens on your spells.")
        c2:Note("Turning it on or off needs a reload: the spellbook tab and the action bar menus are set up at login.")
        c2:Note("The page's own settings are on its cog, next to the search box.")
        c2:Note("Disable the Macro Action Bar addon if you have it: both edit the same macros.")
        c2:Note("Based on Macro Action Bar by NotStraws (MIT license).")

        page:Finish()
    end,
}
