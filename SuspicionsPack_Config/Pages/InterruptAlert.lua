-- SuspicionsPack Options — Interrupt alert
--
-- Toutes les clés liées ici -- text, showIcon, duration, fontFace, fontSize,
-- fontOutline, colorSource, color, l'ancrage et les décalages -- vivent dans
-- SP.DEFAULTS.profile.interruptAlert, donc cette page n'énonce aucun défaut
-- pour son compte. Card:Fill, Card:ColorSource et Card:AnchorRow les cherchent.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

GUI.RegisterPage{
    id       = "interruptalert",
    name     = "Interrupt alert",
    category = "combat",
    dbKey    = "interruptAlert",
    keywords = "interrupt kick kicked counterspell pummel mind freeze silence announce",
    build = function(parent)
        local page = GUI.ModulePage(parent, "interruptAlert", "InterruptAlert",
            "Interrupt alert",
            "Flashes a line on screen when YOU interrupt a cast, naming the " ..
            "spell you kicked. Your pet's interrupt counts as yours.",
            "Enable interrupt alert")

        local c1 = page.cards[1]
        c1:EditBox{
            key   = "text",
            label = "Prefix",
            desc  = "The word shown before the spell name.",
        }
        c1:Toggle{
            key   = "showIcon",
            label = "Show the spell icon",
            desc  = "Inserts the kicked spell's icon before its name.",
        }
        c1:Slider{
            key = "duration", label = "Duration", suffix = " s",
            min = 1, max = 10, step = 0.5,
            desc = "How long the line stays on screen.",
        }

        -- Dire tout de suite si la spé jouée a un kick du tout. Sacré Paladin,
        -- Discipline et Sacré Prêtre n'en ont pas : sans cette ligne, le module
        -- semblerait simplement cassé pour eux.
        local sets = SP.InterruptAlert and SP.InterruptAlert.InterruptSets
        if sets then
            local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
                            or _G.GetSpecialization
            local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo)
                            or _G.GetSpecializationInfo
            local specID
            if getSpec and getInfo then
                local i = getSpec()
                if type(i) == "number" and i >= 1 then specID = getInfo(i) end
            end
            if specID and not sets[specID] then
                c1:Note("Your current specialization has no interrupt, so nothing " ..
                        "will be announced while you play it.")
            end
        end

        local c2 = page:Card("Appearance", "The font, size and colour of the line.")
        c2:FontDropdown{ key = "fontFace", label = "Font face" }
        c2:Pair(
            { kind = "slider",   key = "fontSize",    label = "Font size", min = 8, max = 48, step = 1 },
            { kind = "dropdown", key = "fontOutline", label = "Outline",
              options = { "NONE", "OUTLINE", "THICKOUTLINE" } })
        c2:ColorSource{
            label    = "Text colour",
            srcKey   = "colorSource",
            colorKey = "color",
        }

        local c3 = page:Card("Position", "Where the line appears on screen.")
        c3:AnchorRow{}
        c3:Pair(
            { kind = "slider", key = "x", label = "X offset", min = -2000, max = 2000, step = 1 },
            { kind = "slider", key = "y", label = "Y offset", min = -2000, max = 2000, step = 1 })
        c3:ButtonRow{
            text  = "Preview",
            width = 110,
            onClick = function()
                local IA = SP.InterruptAlert
                if not IA then return end
                if IA.isPreview then IA:HidePreview() else IA:ShowPreview() end
            end,
        }

        page:Finish()
    end,
}
