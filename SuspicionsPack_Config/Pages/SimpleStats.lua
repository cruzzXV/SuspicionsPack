-- SuspicionsPack Options — Simple item stats (WoW: Forever only)
--
-- Listed only where the module is: the .toc line carries the same
-- [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic] gate.
--
-- The example is the client's own spell power line, shortened by the module itself: if
-- the rules fail to build on a client, the page shows it.

local ADDON, ns = ...
local GUI = ns.GUI

-- Two rows whatever the setting: the note measures its height once, so the shortened
-- lines share one row.
local function ExampleText()
    local SS = SuspicionsPack.SimpleStats
    local before, after = SS and SS.Example(12)
    if not before then return "No example: this client has no spell power line." end
    return before .. "\n|cff1eff00" .. (after or before):gsub("\n", "   ") .. "|r"
end

GUI.RegisterPage{
    id       = "simplestats",
    name     = "Simple item stats",
    category = "items",
    dbKey    = "simpleStats",
    keywords = "stats stat item items tooltip spell power damage healing hit crit mana equip bonus " ..
               "short shorten simplify simplified",
    tip      = "Item bonus lines in short: \"+12 Spell Power\" instead of a whole sentence. In every client language.",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "simpleStats", "SimpleStats",
            "Simple item stats",
            "Rewrites an item's long bonus lines in short, in their own green: spell power, " ..
            "damage by school, hit, crit, mana and health per 5 sec, defense, skills. " ..
            "Only on the tooltips you read: other addons still get the original text.")

        local example
        c1:Toggle{ key = "merge", label = "One Spell Power line",
                   desc = "When damage and healing come from one figure. Off: a spell damage line " ..
                          "and a spell healing line.",
                   onChange = function(v)
                       page.apply(v)
                       if example then example.fs:SetText(ExampleText()) end
                   end }

        local c2 = page:Card("Example")
        example = c2:Note(ExampleText())

        page:Finish()
    end,
}
