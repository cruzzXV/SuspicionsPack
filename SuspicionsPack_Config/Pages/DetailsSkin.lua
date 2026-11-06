-- SuspicionsPack Options — Details skin (WoW: Forever only)
--
-- Listed only where the module is: the .toc line carries the same
-- [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic] gate.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

GUI.RegisterPage{
    id       = "detailsskin",
    name     = "Details skin",
    category = "customise",
    dbKey    = "detailsSkin",
    keywords = "details skin damage meter war within tww look theme forever bronze arrow ring",
    tip      = "Adds two skins to Details!, a port of the War Within skin and a slimmer Forever one. Your windows keep their current skin until you pick one.",
    build = function(parent)
        local page, db, card = GUI.ModulePage(parent, "detailsSkin", "DetailsSkin",
            "Details skin",
            "Adds two looks to Details! on WoW: Forever, where the original Details_TWW " ..
            "addon is not available: a port of Karl-Heinz Schneider's \"The War Within\" " ..
            "skin (MIT), and a Forever look made from it, slimmer so 7 rows fit where the " ..
            "first shows 5. Spec icons are off: Forever has no specialisations.",
            nil, "Skin")

        card:Note("Once installed, both are also listed under Details options > Skins. " ..
                  "Switching this module off keeps a skin on windows already using it " ..
                  "until you pick another one there.")

        local function Apply(skinName)
            local ok = SP.DetailsSkin and SP.DetailsSkin:ApplyToAll(skinName)
            if not ok then
                print("|cffe51039Suspicion|r|cffffffffPack|r: Details! is not loaded.")
            end
        end

        card:ButtonRow{
            text  = "Apply Forever to all windows",
            desc  = "Puts the Forever look on every open Details window. " ..
                    "Windows already using it get the skin's settings back.",
            width = 240,
            onClick = function() Apply(SP.DetailsSkin and SP.DetailsSkin.FOREVER_NAME) end,
        }

        card:ButtonRow{
            text  = "Apply The War Within to all windows",
            desc  = "Puts the War Within look on every open Details window. " ..
                    "Windows already using it get the skin's settings back.",
            width = 240,
            onClick = function() Apply(SP.DetailsSkin and SP.DetailsSkin.SKIN_NAME) end,
        }

        page:Finish()
    end,
}
