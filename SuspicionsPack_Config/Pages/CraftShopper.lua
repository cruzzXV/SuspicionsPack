-- SuspicionsPack Options — CraftShopper

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "craftshopper",
    name     = "CraftShopper",
    category = "items",
    dbKey    = "craftShopper",
    keywords = "craft crafting profession recipe reagent shopping list auction house quick buy search",
    build = function(parent)
        local page = GUI.ModulePage(parent, "craftShopper", "CraftShopper",
            "CraftShopper",
            "Tracks how many of each recipe you want to craft and builds a shopping " ..
            "list of the reagents you are missing. While the Auction House is open " ..
            "the list sits beside it, with a Search and a Quick-Buy button per item.",
            "Enable CraftShopper")
        page:Finish()
    end,
}
