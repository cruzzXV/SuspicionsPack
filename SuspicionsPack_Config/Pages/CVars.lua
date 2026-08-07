-- SuspicionsPack Options — CVars
--
-- Fully data-driven. The list, the labels and the descriptions all live in
-- SP.CVars.DEFS, so adding a console variable to the module adds a row here for
-- free -- the old page already iterated DEFS but restated nothing else, and
-- threw away the `desc` the module carries.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

GUI.RegisterPage{
    id       = "cvars",
    name     = "CVars",
    category = "customise",
    -- No dbKey on purpose. The `cvars` profile section is a bare key -> value
    -- map with no `enabled` field -- SP.CVars even overrides IsOn() to say so,
    -- because every variable has its own switch and the module has no master.
    -- The sidebar dot reads exactly that field, so declaring the key here would
    -- paint a permanent "off" dot on a page that is always live.
    keywords = "cvar console variable sharpen nameplate class colour preload graphics",
    build = function(parent)
        local db   = SP.GetDB().cvars
        local mod  = SP.CVars
        local page = GUI.NewPage(parent, db, nil, "cvars")

        local c = page:Card("CVars",
            "Game console variables, applied immediately and re-applied on login.")

        for _, def in ipairs(mod and mod.DEFS or {}) do
            local key = def.key
            c:Toggle{
                -- The label is the module's, not the page's: one definition
                -- table, one place to edit.
                label = def.label,
                desc  = def.desc,
                -- get/set rather than key: the value's home is the game client.
                -- The profile only caches what the module has seen, so a
                -- variable the player has never touched through this window has
                -- no DB entry at all and has to be read live -- otherwise the
                -- switch shows "off" for something already on.
                get = function()
                    local v = db[key]
                    if v ~= nil then return v end
                    return C_CVar and C_CVar.GetCVar(key) == "1"
                end,
                set = function(v)
                    if mod and mod.SetCVar then mod.SetCVar(key, v) end
                end,
                -- Deliberately no `default`: the default of a console variable
                -- is whatever the client shipped with, which the addon does not
                -- know. Inventing one here would light the modified dot and make
                -- the revert arrow write a value nobody chose.
            }
        end

        page:Finish()
    end,
}
