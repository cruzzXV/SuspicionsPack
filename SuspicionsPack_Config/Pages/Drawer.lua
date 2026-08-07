-- SuspicionsPack Options — Minimap drawer
--
-- The old builder was 318 lines, of which roughly 90 were a hand-rolled
-- ColorPickerFrame swatch for the tab colour. That swatch had a SECOND enable
-- axis the page's own UpdateChildState knew nothing about: SetTabSwatchEnabled
-- greyed it when the colour source was not "custom", while UpdateChildState
-- re-enabled it from the master toggle, and whichever ran last won. Picking
-- "Theme colour" and then toggling anything else left the custom swatch live.
-- c:ColorSource derives that state from both inputs in one place, so the bespoke
-- swatch is gone entirely.
--
-- Two dropdowns (border style, and one per addon in Button rules) were built
-- with the private CreateDropdown and hand-anchored inside a raw frame, skipping
-- the label/row layout, the modified dot and the enable cascade. They are normal
-- rows now.
--
-- The Button rules card still varies in height at runtime: it emits one row per
-- addon reported by SP.Drawer.GetKnownNames(), and keeps the empty-state branch
-- for a first run where nothing has been scanned yet.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

local RULE_OPTIONS = {
    { key = "",       label = "Drawer" },
    { key = "ignore", label = "Minimap" },
    { key = "hide",   label = "Hide" },
}

GUI.RegisterPage{
    id       = "drawer",
    name     = "Minimap drawer",
    category = "interface",
    dbKey    = "drawer",
    keywords = "drawer minimap button addon icon tab collect hide tray",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "drawer", "Drawer",
            "Minimap drawer",
            "Collects addon minimap buttons into a sliding drawer.",
            "Enable drawer")

        local defaults = SP.DEFAULTS and SP.DEFAULTS.profile and SP.DEFAULTS.profile.drawer

        c1:Dropdown{
            key   = "side",
            label = "Drawer side",
            desc  = "Which edge of the minimap the tab sits on.",
            options = {
                { key = "LEFT",   label = "Left" },
                { key = "RIGHT",  label = "Right" },
                { key = "TOP",    label = "Top" },
                { key = "BOTTOM", label = "Bottom" },
            },
            onChange = function(v) if SP.Drawer then SP.Drawer.SetSide(v) end end,
        }

        -- hideDelay is stored in seconds but has always been edited in tenths.
        -- A 0.1-step slider is not an option: the value box would read
        -- 0.30000000000000004 for the default.
        c1:Slider{
            label = "Hide delay",
            desc  = "Tenths of a second the drawer stays open after the cursor leaves it.",
            min = 1, max = 20, step = 1,
            get = function() return math.floor((db.hideDelay or 0) * 10 + 0.5) end,
            set = function(v) db.hideDelay = v / 10 end,
            default = defaults and defaults.hideDelay
                      and math.floor(defaults.hideDelay * 10 + 0.5) or nil,
        }

        local c2 = page:Card("Tab", "The handle that opens the drawer.")
        c2:Pair(
            { kind = "slider", key = "tabW", label = "Tab width",  min = 4,  max = 48, step = 1 },
            { kind = "slider", key = "tabH", label = "Tab height", min = 16, max = 80, step = 1 })
        c2:Toggle{ key = "showTabBorder", label = "Tab border",
                   desc = "Draws a thin black outline around the handle." }
        c2:Toggle{ key = "errorAlert", label = "Error alert",
                   desc = "Turns the tab red when BugGrabber catches a Lua error this session." }
        c2:ColorSource{ label = "Tab colour", srcKey = "tabColorSource", colorKey = "tabColor" }

        local c3 = page:Card("Button layout",
            "The panel border, button padding and icon sizing inside the drawer.")
        local borderOn = c3:Toggle{ key = "showBorder", label = "Panel border" }
        c3:GateBelow(borderOn)
        c3:Dropdown{
            key   = "borderColorSource",
            label = "Border colour",
            options = {
                { key = "theme", label = "Theme accent" },
                { key = "class", label = "Class colour" },
            },
        }
        c3:EndGate()
        c3:Pair(
            { kind = "slider", key = "btnSize",  label = "Button size", min = 14, max = 40, step = 1 },
            { kind = "slider", key = "iconSize", label = "Icon size",   min = 10, max = 36, step = 1 })
        c3:Pair(
            { kind = "slider", key = "btnPad",  label = "Button padding", min = 2, max = 16, step = 1 },
            { kind = "slider", key = "maxCols", label = "Max columns",    min = 1, max = 10, step = 1 })

        local c4 = page:Card("Minimap button borders",
            "Style of the circular ring on buttons you keep on the minimap instead of in the drawer.")
        c4:Dropdown{
            key   = "buttonBorderStyle",
            label = "Border style",
            options = {
                { key = "default", label = "Gold" },
                { key = "dark",    label = "Dark" },
                { key = "none",    label = "None" },
            },
            onChange = function()
                if SP.Drawer then SP.Drawer.ApplyAllBorderStyles() end
            end,
        }

        -- One row per addon button seen in the last scan, so this card's height
        -- depends on what the player has installed.
        db.buttonRules = db.buttonRules or {}
        local names = (SP.Drawer and SP.Drawer.GetKnownNames) and SP.Drawer.GetKnownNames() or {}

        local c5 = page:Card("Button rules",
            #names > 0 and "Where each addon's minimap button ends up." or nil)
        if #names == 0 then
            c5:Note("No buttons detected yet — enable the drawer and enter the world first.")
        else
            for _, name in ipairs(names) do
                c5:Dropdown{
                    db      = db.buttonRules,
                    key     = name,
                    label   = name,
                    options = RULE_OPTIONS,
                    default = "",
                    onChange = function(v)
                        -- "Drawer" is the absence of a rule, not a stored value.
                        if v == "" then db.buttonRules[name] = nil end
                        if SP.Drawer then SP.Drawer.CaptureButtons() end
                    end,
                }
            end
        end

        page:Finish()
    end,
}
