-- SuspicionsPack Options — Micro menu skin
--
-- The old page had a master toggle, 13 sub-settings across four cards, and NO
-- cascade of any kind: turning the skin off left every colour, slider and toggle
-- live, so a user could spend a while tuning a module that was not running.
-- GUI.ModulePage wires page:GateAll(master), which fixes it outright, and the
-- "Override size and spacing" toggle now gates the two sliders it owns.
--
-- Two shapes do not match the widget layer directly and are adapted here rather
-- than migrated in the module:
--
--   * The colours are stored as {r=,g=,b=,a=} hashes, not the {r,g,b,a} arrays
--     every colour widget binds to.
--   * iconZoom and highlightAlpha are stored 0-1 but were always presented as
--     percentages.
--
-- Both adapters derive their default from SP.DEFAULTS instead of restating it.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

GUI.RegisterPage{
    id       = "micromenuskin",
    name     = "Micro menu skin",
    category = "interface",
    dbKey    = "microMenuSkin",
    keywords = "micro menu skin button backdrop border icon zoom flat elvui reskin",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "microMenuSkin", "MicroMenuSkin",
            "Micro menu skin",
            "Reskins the micro menu buttons (character, spellbook, talents, collections and " ..
            "the rest) in a flat style: dark backdrop, thin border, accent border on hover, " ..
            "and Blizzard's button frame art stripped away so only the icon shows. Placement " ..
            "stays under Edit Mode; only size and spacing can be overridden below. Switching " ..
            "the skin off needs a /reload to fully restore Blizzard's original art.",
            "Enable micro menu skin")

        local D = SP.DEFAULTS and SP.DEFAULTS.profile and SP.DEFAULTS.profile.microMenuSkin

        -- {r=,g=,b=,a=} in the DB, {r,g,b,a} at the widget.
        local function HashColor(spec)
            local key = spec.key
            spec.key   = nil
            spec.alpha = true
            spec.get = function()
                local c = db[key]
                if type(c) ~= "table" then return nil end
                return { c.r, c.g, c.b, c.a }
            end
            spec.set = function(v)
                local c = db[key]
                if type(c) ~= "table" then c = {}; db[key] = c end
                c.r, c.g, c.b = v[1], v[2], v[3]
                if v[4] ~= nil then c.a = v[4] end
            end
            local d = D and D[key]
            if d then spec.default = { d.r, d.g, d.b, d.a } end
            return spec
        end

        -- 0-1 in the DB, 0-100 on the slider.
        local function Percent(spec)
            local key = spec.key
            spec.key    = nil
            spec.suffix = "%"
            spec.get = function() return math.floor((db[key] or 0) * 100 + 0.5) end
            spec.set = function(v) db[key] = v / 100 end
            local d = D and D[key]
            if d then spec.default = math.floor(d * 100 + 0.5) end
            return spec
        end

        local c2 = page:Card("Colours")
        c2:DualColor{
            a = HashColor{ key = "backdropColor", label = "Backdrop" },
            b = HashColor{ key = "borderColor",   label = "Border" },
        }
        c2:Color(HashColor{
            key   = "hoverColor",
            label = "Hover and pushed accent",
            desc  = "Border colour while the cursor is over a button, and while it is held down.",
        })
        c2:Toggle{ key = "showBackdrop", label = "Show backdrop" }
        c2:Toggle{ key = "showBorder",   label = "Show border" }

        local c3 = page:Card("Sizing")
        c3:Slider{ key = "borderSize", label = "Border thickness", min = 1, max = 4, step = 1 }
        c3:Slider{ key = "iconInset", label = "Icon inset",
                   desc = "How far the icon sits inside the button edge.",
                   min = 0, max = 8, step = 1 }
        c3:Slider(Percent{ key = "iconZoom", label = "Icon zoom",
                   desc = "Crops the icon inward to remove Blizzard's transparent padding.",
                   min = 0, max = 40, step = 1 })
        c3:Slider(Percent{ key = "highlightAlpha", label = "Highlight opacity",
                   desc = "Strength of the white overlay drawn while the cursor is over a button.",
                   min = 0, max = 60, step = 1 })

        local c4 = page:Card("Size and spacing",
            "Takes over the button size and the gap between them, then lets Blizzard's own " ..
            "grid re-lay everything out. Leave off to keep Blizzard's sizing.")
        local override = c4:Toggle{ key = "overrideLayout", label = "Override size and spacing" }
        c4:GateBelow(override)
        c4:Slider{ key = "buttonSize", label = "Button size", min = 12, max = 48, step = 1 }
        c4:Slider{ key = "buttonSpacing", label = "Spacing",
                   desc = "0 puts the backdrops edge to edge. Blizzard's native value is -5.",
                   min = -8, max = 20, step = 1 }
        c4:Slider{ key = "iconsPerRow", label = "Icons per row",
                   desc = "Wraps the bar onto as many rows as it needs — 6 gives you the " ..
                          "two-row block. 0 leaves the layout to Blizzard, which is what the " ..
                          "vehicle and pet battle bars expect.",
                   min = 0, max = 12, step = 1 }

        local c45 = page:Card("Opacity")
        c45:Slider{ key = "alpha", label = "Bar opacity",
                    desc = "Applies to the whole bar, backdrops and borders included.",
                    min = 0, max = 100, step = 5, suffix = "%" }
        c45:Toggle{ key = "fadeOnHover", label = "Full opacity on mouseover",
                    desc = "Returns to 100% while the cursor is over the bar." }

        local c5 = page:Card("Extras")
        c5:Toggle{ key = "desaturate", label = "Desaturate icons",
                   desc = "Greyscale icons that colour back in on hover." }

        page:Finish()
    end,
}
