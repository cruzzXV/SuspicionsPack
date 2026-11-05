-- SuspicionsPack — NodeRadar's node list (WoW: Forever only, see the .toc gate)
--
-- A minimap dot only gives its name, so the name has to say what the node is.
-- Names and skills come from Wowhead's Forever objects of type Herb and Mining Node,
-- in English and French, read on 2026-11-05 (build 1.60.1.70790). The game's data
-- files do not hold these objects.
--
-- Left out: quest objects Wowhead also files as herbs (Serpentbloom, Violet Tragan,
-- Beached Sea Creature, Skeletal Sea Turtle, Incendia Agave, Tomb Weed, Hyjal
-- Silphium). Also left out: Death Lotus, Demonsage, Frilled Lichen, Hive Thistle,
-- Marefoil, Rosecap and Stranglevine, which Wowhead has no object for so far. A name
-- missing here shows up in `/spack radar names`.

local SP = SuspicionsPack

-- { English name, French name, skill needed, colour of its icon }
-- No French name: Wowhead has no translation yet. The colours are chosen by hand so that
-- a resource can be told at a glance: one per metal, ooze-covered and poor veins with theirs.
local HERBS = {
    { "Silverleaf",          "Feuillargent",               1,   "d0f0c8" },
    { "Stunted Silverleaf",  "Feuillargent rabougri",      1,   "d0f0c8" },
    { "Peacebloom",          "Pacifique",                  1,   "fff0a0" },
    { "Wilted Peacebloom",   "Pacifique fanée",            1,   "fff0a0" },
    { "Gloom Weed",          "Herbe des ténèbres",         1,   "90a080" },
    { "Doom Weed",           "Herbe maléfique",            1,   "a868c0" },
    { "Earthroot",           "Terrestrine",                15,  "d09a60" },
    { "Mageroyal",           "Mage royal",                 50,  "ff7a48" },
    { "Briarthorn",          "Eglantine",                  70,  "ff8ab8" },
    { "Stranglekelp",        "Etouffante",                 85,  "48e0a8" },
    { "Bruiseweed",          "Doulourante",                100, "a878f0" },
    { "Wild Steelbloom",     "Aciérite sauvage",           115, "90c0e8" },
    { "Grave Moss",          "Tombeline",                  120, "88b860" },
    { "Kingsblood",          "Sang-royal",                 125, "f04848" },
    { "Nightmare Moss",      "Mousse des cauchemars",      125, "8058d0" },
    { "Liferoot",            "Vietérule",                  150, "58e058" },
    { "Fadeleaf",            "Pâlerette",                  160, "d0c0f0" },
    { "Goldthorn",           "Dorépine",                   170, "ffc838" },
    { "Khadgar's Whisker",   "Moustache de Khadgar",       185, "f0e878" },
    { "Wintersbite",         "Hivernale",                  195, "a8e8ff" },
    { "Firebloom",           "Fleur de feu",               205, "ff7020" },
    { "Dreamroot",           "Oniracine",                  205, "88f058" },
    { "Purple Lotus",        "Lotus pourpre",              210, "b860ff" },
    { "Arthas' Tears",       "Larmes d'Arthas",            220, "e04890" },
    { "Sungrass",            "Soleillette",                230, "fff040" },
    { "Blindweed",           "Aveuglette",                 235, "70a8e0" },
    { "Ghost Mushroom",      "Champignon fantôme",         245, "e0e0ff" },
    { "Gromsblood",          "Gromsang",                   250, "d02848" },
    { "Star Lotus",          "Lotus stellaire",            250, "a8d8ff" },
    { "Moonroot",            "Racine lunaire",             250, "b8d0ff" },
    { "Golden Sansam",       "Sansam doré",                260, "ffaa20" },
    { "Dreamfoil",           "Feuillerêve",                270, "58d0e8" },
    { "Mountain Silversage", "Sauge-argent des montagnes", 280, "c0f0d8" },
    { "Plaguebloom",         "Fleur de peste",             285, "a8e040" },
    { "Icecap",              "Calot de glace",             290, "80d0ff" },
    { "Black Lotus",         "Lotus noir",                 300, "9070e8" },
}

local ORE = {
    { "Copper Vein",                     "Filon de cuivre",                         1,   "ff8a3c" },
    { "Poor Copper Vein",                "Filon de cuivre appauvri",                1,   "ff8a3c" },
    { "Chunk of Amber",                  "Morceau d’ambre",                         1,   "ffa820" },
    { "Large Chunk of Amber",            "Gros morceau d’ambre",                    1,   "ffa820" },
    { "Incendicite Mineral Vein",        "Filon d'incendicite",                     65,  "ff5a30" },
    { "Tin Vein",                        "Filon d'étain",                           65,  "6fe0c8" },
    { "Silver Vein",                     "Filon d'argent",                          75,  "f2f6ff" },
    { "Ooze Covered Silver Vein",        "Filon d'argent couvert de limon",         75,  "f2f6ff" },
    { "Lesser Bloodstone Deposit",       "Gisement de pierre de sang inférieure",   75,  "e0244e" },
    { "Iron Deposit",                    "Gisement de fer",                         125, "8fa8d0" },
    { "Cold Iron Deposit",               "Gisement de fer froid",                   125, "8fd8f0" },
    { "Indurium Mineral Vein",           "Filon d'indurium",                        150, "b890ff" },
    { "Gold Vein",                       "Filon d'or",                              155, "ffd21f" },
    { "Ooze Covered Gold Vein",          "Filon d'or couvert de limon",             155, "ffd21f" },
    { "Mithril Deposit",                 "Gisement de mithril",                     175, "5f9cff" },
    { "Ooze Covered Mithril Deposit",    "Gisement de mithril couvert de vase",     175, "5f9cff" },
    { "Fool's Gold Vein",                "Filon de pyrite",                         175, "d8d070" },
    { "Truesilver Deposit",              "Gisement de vrai-argent",                 230, "7fe8ff" },
    { "Ooze Covered Truesilver Deposit", "Gisement de vrai-argent couvert de vase", 230, "7fe8ff" },
    { "Dark Iron Deposit",               "Gisement de sombrefer",                   230, "c04a3a" },
    { "Small Thorium Vein",              "Petit filon de thorium",                  245, "58f08a" },
    { "Ooze Covered Thorium Vein",       "Filon de thorium couvert de limon",       245, "58f08a" },
    { "Starsilver Vein",                 "Veine d’astrargent",                      245, "cfe0ff" },
    { "Greater Moonstone Formation",     "Formation de pierre de lune supérieure",  245, "e0d8ff" },
    { "Rich Thorium Vein",               "Riche filon de thorium",                  275, "58f08a" },
    { "Ooze Covered Rich Thorium Vein",  "Riche filon de thorium couvert de limon", 275, "58f08a" },
    { "Hakkari Thorium Vein",            "Filon de thorium Hakkari",                275, "58f08a" },
    { "Heavy Thorium Vein",              false,                                     300, "58f08a" },
    { "Small Obsidian Chunk",            "Petit morceau d'obsidienne",              305, "9060e0" },
    { "Large Obsidian Chunk",            "Grand morceau d'obsidienne",              305, "9060e0" },
}

-- The form names are compared in: lowercase, straight apostrophes, and E for É and é,
-- because the same herb can be written Églantine or Eglantine.
local function Key(name)
    local key = name:lower():gsub("\226\128\153", "'"):gsub("\195\137", "e"):gsub("\195\169", "e")
    return key
end

local nodes = {}
local function Add(list, kind)
    for _, row in ipairs(list) do
        local hex = row[4]
        local node = {
            kind = kind, skill = row[3],
            r = tonumber(hex:sub(1, 2), 16) / 255,
            g = tonumber(hex:sub(3, 4), 16) / 255,
            b = tonumber(hex:sub(5, 6), 16) / 255,
        }
        nodes[Key(row[1])] = node
        if row[2] then nodes[Key(row[2])] = node end
    end
end
Add(HERBS, "herb")
Add(ORE, "ore")

SP.NodeRadarData = {
    Key    = Key,
    nodes  = nodes,
    -- Herbalism and Mining.
    skillLine = { herb = 182, ore = 186 },
    -- The minimap's sparkling symbols. Not square, so each gives its height per width.
    symbol = {
        herb = { atlas = "professions_tracking_herb_special", ratio = 42 / 44 },
        ore  = { atlas = "professions_tracking_ore_special",  ratio = 42 / 48 },
    },
    -- The tracking spells: Find Herbs, Find Minerals.
    finders = { [2383] = "herb", [2580] = "ore" },
}
