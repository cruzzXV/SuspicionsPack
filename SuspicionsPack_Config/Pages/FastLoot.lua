-- SuspicionsPack Options — Fast Loot
--
-- REFERENCE PAGE: the minimal shape. A module with nothing but an on/off switch
-- is now four lines of content.

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "fastloot",
    name     = "Fast loot",
    category = "items",
    dbKey    = "fastLoot",
    keywords = "loot looting speed autoloot fast pickup",
    tip      = "Takes every item from a loot window the moment it opens. It also forces the game's Auto Loot on, and holding the Auto Loot key no longer lets you pick items by hand.",
    build = function(parent)
        local page = GUI.ModulePage(parent, "fastLoot", "FastLoot",
            "Fast loot",
            "Takes every item as soon as a loot window opens, with one more pass a tenth " ..
            "of a second later for anything left. While it is on, the game's Auto Loot is " ..
            "kept on, so holding the Auto Loot key no longer lets you pick items by hand.",
            "Enable fast loot")
        page:Finish()
    end,
}
