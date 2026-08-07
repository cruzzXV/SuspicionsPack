-- SuspicionsPack Options — Spell effect alpha
--
-- Forty per-spec sliders, one card per class.
--
-- The first version packed three or four sliders onto a single line through a
-- custom row widget. Once rows became "label left, control right" that could not
-- work: a slider needs its label, a rail and a value readout, and four of those
-- in a 640px card leaves ~150px each. The labels vanished and the page rendered
-- as anonymous stacks of rails. One card per class costs vertical space on a page
-- that is inherently long anyway, and needs no custom widget at all.
--
-- Per-spec writes are always saved but only pushed to the CVar when the slider
-- belongs to the spec you are currently playing; the others land on the next
-- PLAYER_SPECIALIZATION_CHANGED.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

local CLASS_GROUPS = {
    { name = "Death Knight", specs = { 250, 251, 252 } },
    { name = "Demon Hunter", specs = { 577, 581, 1480 } },
    { name = "Druid",        specs = { 102, 103, 104, 105 } },
    { name = "Evoker",       specs = { 1467, 1468, 1473 } },
    { name = "Hunter",       specs = { 253, 254, 255 } },
    { name = "Mage",         specs = { 62, 63, 64 } },
    { name = "Monk",         specs = { 268, 269, 270 } },
    { name = "Paladin",      specs = { 65, 66, 70 } },
    { name = "Priest",       specs = { 256, 257, 258 } },
    { name = "Rogue",        specs = { 259, 260, 261 } },
    { name = "Shaman",       specs = { 262, 263, 264 } },
    { name = "Warlock",      specs = { 265, 266, 267 } },
    { name = "Warrior",      specs = { 71, 72, 73 } },
}

GUI.RegisterPage{
    id       = "spelleffectalpha",
    name     = "Spell effect alpha",
    category = "combat",
    dbKey    = "spellEffectAlpha",
    keywords = "spell effect alpha proc glow overlay opacity activation highlight spec",
    build = function(parent)
        local page, db = GUI.ModulePage(parent, "spellEffectAlpha", "SpellEffectAlpha",
            "Spell effect alpha",
            "Controls the opacity of spell activation overlays -- the glow around " ..
            "an action button when a proc fires. 0 hides them completely, 100 is " ..
            "the Blizzard default.",
            nil, "Global default")

        local c1 = page.cards[1]
        c1:Slider{
            key    = "globalDefault",
            label  = "Default opacity",
            desc   = "Used for any specialization without an override below.",
            suffix = "%", min = 0, max = 100, step = 1,
        }

        -- The per-spec values live in db.specs, so each class card points its DB
        -- and its default lookup one level deeper.
        db.specs = db.specs or {}
        local specDefaults = SP.DEFAULTS and SP.DEFAULTS.profile
                             and SP.DEFAULTS.profile.spellEffectAlpha
                             and SP.DEFAULTS.profile.spellEffectAlpha.specs

        -- Writes always land in the profile; the CVar is only touched when the
        -- slider is for the spec being played right now.
        local function ApplyIfCurrent(specID)
            local index = GetSpecialization and GetSpecialization() or 0
            local cur   = (index and index > 0 and GetSpecializationInfo)
                          and GetSpecializationInfo(index) or 0
            if cur == specID then page.apply() end
        end

        local names = SP.SpellEffectAlpha and SP.SpellEffectAlpha.SpecNames or {}
        local icons = SP.SpellEffectAlpha and SP.SpellEffectAlpha.SpecIcons or {}

        for _, group in ipairs(CLASS_GROUPS) do
            local card = page:Card(group.name, nil, specDefaults)
            for _, specID in ipairs(group.specs) do
                local name = names[specID] or ("Spec " .. specID)
                local icon = icons[specID]
                card:Slider{
                    db      = db.specs,
                    key     = specID,
                    default = specDefaults and specDefaults[specID],
                    label   = icon and ("|T" .. icon .. ":14:14:0:0|t  " .. name) or name,
                    min = 0, max = 100, step = 1, suffix = "%",
                    onChange = function() ApplyIfCurrent(specID) end,
                }
            end
        end

        page:Finish()
    end,
}
