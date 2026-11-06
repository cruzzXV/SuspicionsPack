-- SuspicionsPack Options — Player dragon

local ADDON, ns = ...
local GUI = ns.GUI

local STYLES = {
    { key = "silver", label = "Silver (rare)" },
    { key = "gold",   label = "Gold (elite)" },
    { key = "boss",   label = "Gold winged (boss)" },
}

GUI.RegisterPage{
    id       = "playerdragon",
    name     = "Player dragon",
    category = "interface",
    dbKey    = "playerDragon",
    keywords = "player frame portrait dragon elite rare silver gold boss border ring unit frame ellesmereui",
    tip      = "Wraps your own portrait in the dragon the target frame shows for elites and rares, turned to face outward.",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "playerDragon", "PlayerDragon",
            "Player dragon",
            "Puts the dragon the target frame shows for elite and rare mobs around your " ..
            "own portrait, turned to face outward. Works on Blizzard's player frame and on " ..
            "EllesmereUI's Blizzard Style and WoW Forever frames; EllesmereUI's own look " ..
            "has a Player Frame Dragon of its own. On Blizzard's frame it is hidden while " ..
            "the vehicle frame is up.")

        c1:Dropdown{ key = "style", label = "Dragon", options = STYLES,
                     desc = "The same art as on the target frame for that kind of mob." }

        page:Finish()
    end,
}
