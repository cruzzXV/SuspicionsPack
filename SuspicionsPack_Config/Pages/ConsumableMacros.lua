-- SuspicionsPack Options — Consumable macros (WoW: Forever only)
--
-- Listed only where the module is: the .toc line carries the same
-- [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic] gate.
--
-- Everything goes through the page's standard onChange, which reaches
-- ConsumableMacros:Refresh -> Activate -> rewrite the macros.

local ADDON, ns = ...
local GUI = ns.GUI

local PRIORITIES = {
    { key = "stone",  label = "Healthstone" },
    { key = "potion", label = "Healing potion" },
    { key = "spell",  label = "Custom spell" },
    { key = "none",   label = "Nothing" },
}

local RESETS = {
    { key = "combat", label = "Leaving combat" },
    { key = "target", label = "Changing target" },
    { key = "10",     label = "After 10 seconds" },
    { key = "30",     label = "After 30 seconds" },
    { key = "60",     label = "After 60 seconds" },
}

GUI.RegisterPage{
    id       = "consumablemacros",
    name     = "Consumable macros",
    category = "items",
    dbKey    = "consumableMacros",
    keywords = "macro macros food drink water eat bandage first aid health healthstone potion mana " ..
               "conjured consumable castsequence",
    tip      = "Four macros that always point at the best of what you carry: drink, buff food, bandage and healing. Only the buff food macro eats food that gives a buff.",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "consumableMacros", "ConsumableMacros",
            "Consumable macros",
            "Keeps four macros on the best item in your bags. Drag them from the General " ..
            "tab of the macro window (/macro). They update out of combat.",
            nil, "Food and drink")

        local foodOn = c1:Toggle{ key = "foodDrink", label = "Food and drink macro",
                                  desc = "SPFoodDrink: drinks, and eats if you ask it to, out of combat." }
        c1:GateBelow(foodOn)
        c1:Toggle{ key = "includeFood", label = "Include food",
                   desc = "Needed for classes without mana. Items that restore both are always used." }
        c1:Toggle{ key = "preferConjured", label = "Prefer conjured food and water",
                   desc = "Uses them first, even over something stronger." }
        c1:Toggle{ key = "manaPotionInCombat", label = "Mana potion in combat",
                   desc = "In combat, the macro uses your best mana potion or gem." }
        c1:Slider{ key = "minManaPercent", label = "Minimum mana restored",
                   desc = "Ignores drinks restoring less than this share of your maximum mana.",
                   min = 0, max = 100, step = 1 }
        c1:EndGate()

        local cBuff = page:Card("Buff food")
        cBuff:Toggle{ key = "buffFood", label = "Buff food macro",
                      desc = "SPBuffFood: the buff food with the highest required level, then the biggest restore. Food only, no drinks." }

        local c2 = page:Card("Bandage")
        c2:Toggle{ key = "bandage", label = "Bandage macro",
                   desc = "SPBandage: the strongest bandage your First Aid allows." }

        local c3 = page:Card("Health")
        local healthOn = c3:Toggle{ key = "health", label = "Health macro",
                                    desc = "SPHealth: a sequence of the items below, used in the order you pick." }
        c3:GateBelow(healthOn)
        c3:Toggle{ key = "stopCasting", label = "Stop casting first",
                   desc = "Cancels what you are casting, so a heal is never blocked by a cast." }
        c3:Dropdown{ key = "priority1", label = "First",  options = PRIORITIES }
        c3:Dropdown{ key = "priority2", label = "Second", options = PRIORITIES }
        c3:Dropdown{ key = "priority3", label = "Third",  options = PRIORITIES }
        c3:Dropdown{ key = "reset", label = "Start the sequence over", options = RESETS }
        c3:EditBox{ key = "customSpells", label = "Custom spells",
                    desc = "Spell IDs, separated by commas. The macro uses the one you know that is ready soonest.",
                    maxLen = 64 }
        c3:EndGate()

        local c4 = page:Card("Good to know")
        c4:Note("Only the buff food macro eats buff food: the others keep it for its buff. " ..
                "Switching a macro off leaves it as it is, so it stays on your action bars until you delete it.")

        page:Finish()
    end,
}
