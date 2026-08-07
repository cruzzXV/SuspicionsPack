-- SuspicionsPack Options — sidebar categories
--
-- Order here is the order in the sidebar. Pages attach themselves to a category
-- by id in their own RegisterPage call, so adding a module means touching one
-- file instead of three.

local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterCategory("general",   "General")
GUI.RegisterCategory("combat",    "Combat")
GUI.RegisterCategory("mythic",    "Mythic plus")
GUI.RegisterCategory("items",     "Items")
GUI.RegisterCategory("social",    "Social")
GUI.RegisterCategory("interface", "Interface")
GUI.RegisterCategory("customise", "Customise")

-- ============================================================
-- Shared helpers for page builders
-- ============================================================

local SP = SuspicionsPack

-- The on/off toast, in the middle of the screen.
--
-- 32 toggles fired this before the rebuild and the migration dropped it, on the
-- reasoning that the new sidebar dot says the same thing. It does not: the dot
-- only tells you anything if you happen to be looking at the sidebar, and you
-- are looking at the switch you just clicked.
--
-- The accent is read live rather than baked at build time, so the toast follows
-- a theme change like everything else.
local function Hex(c)
    return string.format("%02X%02X%02X",
        math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

function GUI.Toast(name, on)
    if not (SP.ShowNotification and name) then return end
    local a = GUI.T.accent
    -- The state word is the accent lerped halfway to white: same colour family,
    -- without competing with the module name for attention.
    local light = { a[1] + (1 - a[1]) * 0.5, a[2] + (1 - a[2]) * 0.5, a[3] + (1 - a[3]) * 0.5 }
    SP.ShowNotification(("|cff%s%s:|r |cff%s%s|r")
        :format(Hex(a), name, Hex(light), on and "On" or "Off"))
end

-- The apply callback for a module: re-runs its Refresh so a settings change is
-- visible in game immediately. Modules all carry Refresh from SP.ModuleMixin.
function GUI.Applier(moduleName)
    return function()
        local mod = SP[moduleName]
        if mod and mod.Refresh then mod:Refresh() end
    end
end

-- The standard boilerplate at the top of a module page: the page object, its
-- DB section, and the enable toggle that gates everything below it.
--
--   local page, db, c = GUI.ModulePage(parent, "durability", "Durability",
--                                      "Repair warning",
--                                      "Warns when your gear needs repairing.")
--
-- The page's name and blurb go in the header block, with the master switch on
-- the right; the returned card is a plain settings group. `cardTitle` names that
-- group -- "General" unless the page says otherwise. The sixth argument used to
-- be the master toggle's own label, which the header makes redundant, so it is
-- accepted and ignored for the pages that still pass one.
function GUI.ModulePage(parent, dbKey, moduleName, title, desc, _legacyLabel, cardTitle)
    local db    = SP.GetDB()[dbKey]
    local apply = GUI.Applier(moduleName)
    local page  = GUI.NewPage(parent, db, apply, dbKey)

    local _, master = page:Header(title, desc, {
        key      = "enabled",
        db       = db,
        default  = page.defaults and page.defaults.enabled,
        onChange = apply,
        onToggle = function(v) GUI.UpdateDots(); GUI.Toast(title, v) end,
    })

    page:GateAll(master)
    return page, db, page:Card(cardTitle or "General"), master
end

GUI.OUTLINES = { "NONE", "OUTLINE", "THICKOUTLINE", "SOFTOUTLINE" }
GUI.CHANNELS = { "Master", "SFX", "Music", "Ambience", "Dialog" }
