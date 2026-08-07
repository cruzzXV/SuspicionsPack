-- SuspicionsPack Options — M+ auto playstyle
--
-- The playstyle labels come from Blizzard_GroupFinder, which is load-on-demand,
-- so the list is supplied through optionsFn and re-read on every refresh instead
-- of being frozen at build time.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

local FALLBACK = { "Learning", "Relaxed", "Competitive", "Carry Offered" }

local function PlaystyleOptions()
    local AP  = SP.AutoPlaystyle
    local out = {}
    for i = 1, 4 do
        local label = (AP and AP.Labels and AP.Labels[i]) or FALLBACK[i]
        local live  = _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. i]
        if live and live ~= "" then label = live end
        out[i] = { key = i, label = label }
    end
    return out
end

GUI.RegisterPage{
    id       = "autoplaystyle",
    name     = "M+ auto playstyle",
    category = "mythic",
    dbKey    = "autoPlaystyle",
    keywords = "playstyle mythic plus group finder listing learning relaxed competitive carry",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "autoPlaystyle", "AutoPlaystyle",
            "M+ auto playstyle",
            "Pre-selects your preferred playstyle whenever you open the group " ..
            "finder's listing dialog for a Mythic+ group. Applied every time the " ..
            "dialog opens, including after switching activity.",
            "Enable M+ auto playstyle")

        c1:Dropdown{
            key       = "playstyle",
            label     = "Playstyle",
            desc      = "The playstyle your own listings are created with.",
            optionsFn = PlaystyleOptions,
        }

        page:Finish()
    end,
}
