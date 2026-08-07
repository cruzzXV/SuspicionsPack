-- SuspicionsPack Options — Combat cross
--
-- Three settings on the old page wrote to the DB and never called
-- ApplySettings: both range-colour toggles and the out-of-range swatch. Changing
-- them did nothing until the next reload. Here every row goes through the page's
-- own onChange, so there is nowhere left for that to hide.

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "combatcross",
    name     = "Combat cross",
    category = "combat",
    dbKey    = "combatCross",
    keywords = "crosshair cross combat centre center range out of range aim reticle",
    build = function(parent)
        local page = GUI.ModulePage(parent, "combatCross", "CombatCross",
            "Combat cross",
            "Draws a \"+\" crosshair on screen while you are in combat. " ..
            "It can turn red when your target is out of range.",
            "Enable combat cross")

        local c2 = page:Card("Appearance", "The size, outline and colour of the cross.")
        c2:Slider{
            key   = "thickness",
            label = "Thickness",
            desc  = "How heavy the strokes of the cross are.",
            min = 4, max = 40, step = 1,
        }
        c2:Toggle{
            key   = "outline",
            label = "Outline",
            desc  = "Adds a dark edge so the cross stays readable over bright terrain.",
        }
        c2:ColorSource{
            label    = "Cross colour",
            srcKey   = "colorSource",
            colorKey = "color",
        }

        local c3 = page:Card("Range colour",
            "Recolours the cross when your target is beyond the range of your " ..
            "spec's main ability.")
        c3:Toggle{ key = "rangeColorMeleeEnabled",  label = "Enable for melee specs" }
        c3:Toggle{ key = "rangeColorRangedEnabled", label = "Enable for ranged specs" }
        c3:Color{
            key   = "outOfRangeColor",
            label = "Out-of-range colour",
            desc  = "Used while the target is out of range.",
        }

        local c4 = page:Card("Position", "Where the cross sits on screen.")
        c4:AnchorRow{}
        c4:Pair(
            { kind = "slider", key = "x", label = "X offset", min = -2000, max = 2000, step = 1 },
            { kind = "slider", key = "y", label = "Y offset", min = -2000, max = 2000, step = 1 })

        page:Finish()
    end,
}
