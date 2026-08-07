-- SuspicionsPack Options — Filter expansion only

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "filterexpansiononly",
    name     = "Filter expansion only",
    category = "items",
    dbKey    = "filterExpansionOnly",
    keywords = "auction house crafting orders browser filter current expansion legacy hide old items",
    build = function(parent)
        local page = GUI.ModulePage(parent, "filterExpansionOnly", "FilterExpansionOnly",
            "Filter expansion only",
            "Ticks the Current Expansion Only filter for you whenever the Auction " ..
            "House or the Crafting Orders browser opens, so items and orders from " ..
            "older expansions stay out of the way.",
            "Enable filter expansion only")
        page:Finish()
    end,
}
