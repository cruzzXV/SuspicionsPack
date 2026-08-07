-- SuspicionsPack Options — Gateway alert
--
-- Every key this page binds -- fontFace, fontSize, fontOutline, colorSource,
-- color, frameStrata, the anchor and the offsets -- is in
-- SP.DEFAULTS.profile.gatewayAlert, so nothing here states a default of its own.
-- Card:Fill, Card:ColorSource and Card:AnchorRow look all of them up.

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "gatewayalert",
    name     = "Gateway alert",
    category = "combat",
    dbKey    = "gatewayAlert",
    keywords = "gateway demonic warlock portal ready alert 188152",
    build = function(parent)
        local page = GUI.ModulePage(parent, "gatewayAlert", "GatewayAlert",
            "Gateway alert",
            "Flashes a text alert on screen when your Demonic Gateway item " ..
            "(188152) is off cooldown and ready to use.",
            "Enable gateway alert")

        local c2 = page:Card("Appearance", "The font, size and colour of the alert text.")
        c2:FontDropdown{ key = "fontFace", label = "Font face" }
        c2:Pair(
            { kind = "slider",   key = "fontSize",    label = "Font size", min = 8, max = 32, step = 1 },
            { kind = "dropdown", key = "fontOutline", label = "Outline",
              options = { "NONE", "OUTLINE", "THICKOUTLINE" } })
        c2:ColorSource{
            label    = "Text colour",
            srcKey   = "colorSource",
            colorKey = "color",
        }

        local c3 = page:Card("Position", "Where the alert appears on screen.")
        c3:AnchorRow{}
        c3:Pair(
            { kind = "slider", key = "x", label = "X offset", min = -2000, max = 2000, step = 1 },
            { kind = "slider", key = "y", label = "Y offset", min = -2000, max = 2000, step = 1 })

        page:Finish()
    end,
}
