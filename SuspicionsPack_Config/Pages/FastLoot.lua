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
    build = function(parent)
        local page = GUI.ModulePage(parent, "fastLoot", "FastLoot",
            "Fast loot",
            "Empties loot windows as fast as the server allows, instead of one " ..
            "item per client tick.",
            "Enable fast loot")
        page:Finish()
    end,
}
