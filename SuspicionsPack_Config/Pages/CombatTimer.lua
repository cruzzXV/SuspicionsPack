-- SuspicionsPack Options — Combat timer
--
-- REFERENCE PAGE: the complex module shape. Shows a nested defaults table
-- (backdrop), several colour-with-source rows, an anchor row with a non-default
-- strata, and a sub-gate. The old version was 200 lines with four bookkeeping
-- tables and eight AddSeparator calls.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

GUI.RegisterPage{
    id       = "combattimer",
    name     = "Combat timer",
    category = "combat",
    dbKey    = "combatTimer",
    keywords = "combat timer duration fight length stopwatch clock",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "combatTimer", "CombatTimer",
            "Combat timer",
            "Runs a timer for as long as you are in combat.",
            "Enable combat timer")

        -- The STORED values are the only two strings the module understands:
        -- FormatTime in Modules/CombatTimer/CombatTimer.lua branches on
        -- "MM:SS:MS" and falls through to "MM:SS" for everything else, so any
        -- other key silently means "MM:SS" while the control claims otherwise.
        c1:Dropdown{ key = "format", label = "Format", options = {
            { key = "MM:SS",    label = "Minutes and seconds" },
            { key = "MM:SS:MS", label = "Minutes, seconds and tenths" },
        } }
        c1:Toggle{ key = "printToChat", label = "Print duration to chat",
                   desc = "Posts the fight length when combat ends." }
        c1:Toggle{ key = "showLastDuration", label = "Show last duration on frame",
                   desc = "Keeps the final time on screen instead of hiding it.",
                   -- The module's Activate has a SHOW path for this flag and no
                   -- hide path, so switching it off used to leave the stale time
                   -- on screen until the next combat ended. The show side still
                   -- comes from Activate; the page only ever takes it away, and
                   -- never while the clock is actually running.
                   onToggle = function(v)
                       if v then return end
                       local mod = SP.CombatTimer
                       if mod and mod.frame and not mod.running then mod.frame:Hide() end
                   end }

        local c2 = page:Card("Position", "Where the timer sits on screen.")
        c2:AnchorRow{ defaultStrata = "TOOLTIP" }
        c2:Pair(
            { kind = "slider", key = "x", label = "X offset", min = -2000, max = 2000, step = 1 },
            { kind = "slider", key = "y", label = "Y offset", min = -2000, max = 2000, step = 1 })

        local c3 = page:Card("Font")
        c3:FontDropdown{ key = "fontFace", label = "Font face", default = "Expressway" }
        c3:Pair(
            { kind = "slider",   key = "fontSize", label = "Font size", min = 8, max = 60, step = 1 },
            { kind = "dropdown", key = "outline",  label = "Outline", options = GUI.OUTLINES })

        local c4 = page:Card("Font shadow", "A drop shadow makes the timer readable over bright terrain.")
        local shadowOn = c4:Toggle{ key = "shadowEnabled", label = "Enable font shadow", default = false }
        c4:GateBelow(shadowOn)
        c4:ColorSource{ label = "Shadow colour", srcKey = "shadowColorSource",
                        colorKey = "shadowColor", default = { 0, 0, 0 } }
        c4:Pair(
            { kind = "slider", key = "shadowX", label = "Shadow X", min = -5, max = 5, step = 1, default = 1 },
            { kind = "slider", key = "shadowY", label = "Shadow Y", min = -5, max = 5, step = 1, default = -1 })

        local c5 = page:Card("Colours", "The timer can read differently in and out of combat.")
        c5:ColorSource{ label = "In combat", srcKey = "colorInCombatSource",
                        colorKey = "colorInCombat", default = { 1, 0.2, 0.2, 1 } }
        c5:ColorSource{ label = "Out of combat", srcKey = "colorOutOfCombatSource",
                        colorKey = "colorOutOfCombat", default = { 1, 1, 1, 0.7 } }

        -- The backdrop settings live in db.backdrop, so this card points its DB
        -- and its default lookup one level deeper.
        db.backdrop = db.backdrop or {}
        local bdDefaults = SP.DEFAULTS and SP.DEFAULTS.profile
                           and SP.DEFAULTS.profile.combatTimer
                           and SP.DEFAULTS.profile.combatTimer.backdrop
        local c6 = page:Card("Backdrop", "A panel behind the timer text.", bdDefaults)
        local bdOn = c6:Toggle{ db = db.backdrop, key = "enabled", label = "Enable backdrop" }
        c6:GateBelow(bdOn)
        c6:Slider{ db = db.backdrop, key = "borderSize", label = "Border size", min = 1, max = 10, step = 1 }
        c6:Pair(
            { kind = "slider", db = db.backdrop, key = "paddingW", label = "Padding X", min = 0, max = 40, step = 1 },
            { kind = "slider", db = db.backdrop, key = "paddingH", label = "Padding Y", min = 0, max = 40, step = 1 })
        c6:DualColor{
            a = { db = db.backdrop, key = "color",       label = "Background", alpha = true },
            b = { db = db.backdrop, key = "borderColor", label = "Border",     alpha = true },
        }

        page:Finish()
    end,
}
