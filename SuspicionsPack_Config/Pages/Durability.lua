-- SuspicionsPack Options — Repair warning
--
-- REFERENCE PAGE: the canonical module shape -- a master toggle, a few settings,
-- an appearance card and a position card. The old version of this page was 159
-- lines, 36 of them a hand-rolled EditBox and 12 of them bookkeeping tables for
-- the enable cascade.

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "durability",
    name     = "Repair warning",
    category = "items",
    dbKey    = "durability",
    keywords = "durability repair broken gear armour armor warning threshold",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "durability", "Durability",
            "Repair warning",
            "Shows a warning on screen when your gear drops below the threshold. " ..
            "Never shown during combat.",
            "Enable repair warning")

        c1:Slider{
            key   = "threshold",
            label = "Warning threshold",
            desc  = "Warn once your lowest item falls to this percentage.",
            suffix = "%", min = 1, max = 100, step = 1,
        }
        c1:EditBox{
            key   = "warningText",
            label = "Warning text",
            maxLen = 64,
        }

        local c2 = page:Card("Appearance")
        c2:FontDropdown{ key = "fontFace", label = "Font face" }
        c2:Pair(
            { kind = "slider",   key = "fontSize",    label = "Font size", min = 8, max = 60, step = 1 },
            { kind = "dropdown", key = "fontOutline", label = "Outline", options = GUI.OUTLINES })
        c2:ColorSource{
            label    = "Text colour",
            srcKey   = "colorSource",
            colorKey = "color",
        }

        local c3 = page:Card("Position")
        c3:AnchorRow{}
        c3:Pair(
            { kind = "slider", key = "x", label = "X offset", min = -2000, max = 2000, step = 1 },
            { kind = "slider", key = "y", label = "Y offset", min = -2000, max = 2000, step = 1 })

        page:Finish()
    end,
}
