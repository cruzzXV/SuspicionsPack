-- SuspicionsPack Options — Silvermoon map icons

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

GUI.RegisterPage{
    id       = "silvermoonmapicon",
    name     = "Silvermoon map icons",
    category = "interface",
    dbKey    = "silvermoonMapIcon",
    keywords = "silvermoon map icon pin poi waypoint trainer profession auction bank",
    build = function(parent)
        local page = GUI.ModulePage(parent, "silvermoonMapIcon", "SilvermoonMapIcon",
            "Silvermoon map icons",
            "Adds pins to the Silvermoon City world map — profession trainers, auction house, " ..
            "bank, transmogrifier, catalyst, crafting orders and more. Left-click a pin to " ..
            "place a waypoint. Pins only appear while Silvermoon City is the active map.",
            "Enable map icons")

        local c2 = page:Card("Filter")
        c2:Toggle{
            key   = "showOnlyProfessions",
            label = "Show only learned professions",
            desc  = "Hides trainer pins for professions this character has not learned.",
            -- Repainting the pins is enough; a full module Refresh would rebuild
            -- the whole pin provider for a filter change.
            onChange = function()
                local m = SP.SilvermoonMapIcon
                if m and m.RefreshPins then m:RefreshPins() end
            end,
        }

        page:Finish()
    end,
}
