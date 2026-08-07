-- SuspicionsPack Options — Copy anything
--
-- The old builder wrote db.modifier = "ctrl" into SavedVariables simply by
-- opening the page, so every profile that ever visited it carried a setting the
-- UI never exposed. The binding's own default covers it; the write is gone.

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "copytooltip",
    name     = "Copy anything",
    category = "interface",
    dbKey    = "copyTooltip",
    keywords = "copy tooltip id spell item npc aura macro clipboard ctrl",
    build = function(parent)
        local page = GUI.ModulePage(parent, "copyTooltip", "CopyTooltip",
            "Copy anything",
            "Hover any tooltip and press Ctrl+C to copy its ID into a dialog, ready to paste.",
            "Enable copy anything")

        local c2 = page:Card("Supported types")
        c2:Note(
            "Spells — copies the spell ID.\n" ..
            "Items — copies the item ID.\n" ..
            "Units and NPCs — copies the NPC ID, or the player name.\n" ..
            "Auras, buffs and debuffs — copies the aura ID.\n" ..
            "Macros — copies the underlying spell or item ID.")

        page:Finish()
    end,
}
