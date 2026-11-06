-- SuspicionsPack Options — CraftShopper

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "craftshopper",
    name     = "CraftShopper",
    category = "items",
    dbKey    = "craftShopper",
    keywords = "craft crafting profession recipe reagent shopping list auction house quick buy search",
    tip      = "Turns the recipes you track into a shopping list of the reagents you are missing, shown beside the Auction House. Nothing is bought until you confirm the quantity and total price.",
    build = function(parent)
        local page = GUI.ModulePage(parent, "craftShopper", "CraftShopper",
            "CraftShopper",
            "Builds a shopping list of the basic reagents your tracked recipes need and " ..
            "you do not have, counting your bags and bank. Each tracked recipe counts as " ..
            "one craft. While the Auction House is open the list sits beside it, with a " ..
            "Search and a Buy button per item. The list is rebuilt while you are resting.",
            "Enable CraftShopper")
        page:Finish()
    end,
}
