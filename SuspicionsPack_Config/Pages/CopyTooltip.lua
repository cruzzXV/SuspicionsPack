-- SuspicionsPack Options — Copy anything
--
-- The old builder wrote db.modifier = "ctrl" into SavedVariables simply by
-- opening the page, so every profile that ever visited it carried a setting the
-- UI never exposed. The binding's own default covers it; the write is gone.
--
-- Both keys ARE exposed now. CheckModifier in the module handles five
-- combinations and db.key any single letter, and neither had a control -- so the
-- shortcut was Ctrl+C for everyone whatever the module could actually do.

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "copytooltip",
    name     = "Copy anything",
    category = "interface",
    dbKey    = "copyTooltip",
    keywords = "copy tooltip id spell item npc aura macro clipboard ctrl",
    build = function(parent)
        local page, db = GUI.ModulePage(parent, "copyTooltip", "CopyTooltip",
            "Copy anything",
            "Hover any tooltip and press the shortcut to copy its ID into a dialog, ready " ..
            "to paste.",
            "Enable copy anything")

        local c1 = page:Card("Shortcut",
            "Held while hovering a tooltip. Ctrl+C by default.")
        c1:Dropdown{ key = "modifier", label = "Modifier",
                     options = { { key = "ctrl",       label = "Ctrl" },
                                 { key = "shift",      label = "Shift" },
                                 { key = "alt",        label = "Alt" },
                                 { key = "ctrl+shift", label = "Ctrl + Shift" },
                                 { key = "ctrl+alt",   label = "Ctrl + Alt" } } }
        c1:EditBox{ key = "key", label = "Key", maxLen = 1,
                    desc = "A single letter. The module upper-cases it, so case does not matter.",
                    set = function(v)
                        -- One letter, upper-cased: the module compares against
                        -- WoW's key names, which are single upper-case letters.
                        -- A digit or a two-character entry would never match and
                        -- the shortcut would silently stop working.
                        v = (v or ""):upper():gsub("[^A-Z]", "")
                        db.key = (v ~= "" and v:sub(1, 1)) or "C"
                    end }

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
