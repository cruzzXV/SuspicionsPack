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
    keywords = "details skin damage meter war within tww look theme forever",
    build = function(parent)
        local page, db, card = GUI.ModulePage(parent, "detailsSkin", "DetailsSkin",
            "Details skin",
            "Adds the \"The War Within\" look to Details! on WoW: Forever, where the " ..
            "original Details_TWW addon is not available. Port of Karl-Heinz Schneider's " ..
            "skin (MIT). Spec icons are off: Forever has no specialisations.",
            nil, "Skin")

        card:Note("Once installed, the skin is also listed under Details options > Skins. " ..
                  "Switching this module off keeps the skin on windows already using it " ..
                  "until you pick another one there.")

        local row
        row = card:ButtonRow{
            text  = "Apply to all Details windows",
            desc  = "Installs the skin if needed, then puts it on every open window.",
            width = 240,
            onClick = function()
                local ok = SP.DetailsSkin and SP.DetailsSkin:ApplyToAll()
                if not ok then
                    print("|cffe51039Suspicion|r|cffffffffPack|r: Details! is not loaded.")
                end
            end,
        }

        page:Finish()
    end,
}
