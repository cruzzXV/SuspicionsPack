-- SuspicionsPack Options — Teleport menu (WoW: Forever only)
--
-- Listed only where the module is: the .toc line carries the same
-- [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic] gate.
--
-- Everything goes through the page's standard onChange, which reaches
-- TeleportMenu:Refresh -> Activate, and the column is redrawn the next time
-- the game menu opens.

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "teleportmenu",
    name     = "Teleport menu",
    category = "interface",
    dbKey    = "teleportMenu",
    keywords = "teleport teleports portal portals hearthstone hearth astral recall moonglade mage shaman druid " ..
               "engineering ripper transporter everlook gadgetzan hyjal atiesh karazhan game menu escape",
    tip      = "Beside the game menu, buttons for your Hearthstone, Astral Recall, Moonglade, the mage's teleports and portals, and engineering transporters. Click one to cast it.",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "teleportMenu", "TeleportMenu",
            "Teleport menu",
            "Opens your teleports beside the game menu (Escape): the Hearthstone, Astral Recall, " ..
            "Teleport: Moonglade, engineering transporters and Atiesh, with the mage's teleports and " ..
            "portals in rows.")

        c1:Slider{ key = "size", label = "Button size", min = 28, max = 48, step = 2 }
        c1:Toggle{ key = "closeMenu", label = "Close the game menu after a click",
                   desc = "Escape would cancel the cast, so the game menu closes once you click a teleport. " ..
                          "It stays open when the teleport is on cooldown or the click equips an item." }
        c1:Toggle{ key = "portals", label = "Show mage portals",
                   desc = "A second row under the mage's teleports." }

        local c2 = page:Card("Good to know")
        c2:Note("Only what this character knows or carries is shown.")
        c2:Note("An engineering trinket that is not worn gets equipped by the first click. Click it again to use it.")
        c2:Note("Nothing shows in combat: teleports cannot be cast then.")

        page:Finish()
    end,
}
