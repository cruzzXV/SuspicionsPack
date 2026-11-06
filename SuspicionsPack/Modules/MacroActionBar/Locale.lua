local smb = SuspicionsPack.MAB

-- The pack's addition: Macro Action Bar on a client that isn't English.
--
-- The original names spells in English everywhere: its class files (sections, Mouseover and Focus spells,
-- cursor spells, stances, pet abilities, forms, racials, the ready-made macros) and a few words in Macros.lua.
-- The spellbook, macro conditionals and /cast all use the client's own names, so on a French client none of
-- those lists matched: no Cast On for Vague de soins, every spell in Unsorted, and so on. Each English name
-- goes through its spell ID (Spells.lua, generated from the game's data) to this client's name instead.
--
-- The class files are translated once, at login, before the page first reads them. On an English client
-- nothing is touched, so the module builds exactly what the original does.

local LANGUAGE = GetLocale and GetLocale() or "enUS"
local ENGLISH = LANGUAGE == "enUS" or LANGUAGE == "enGB"

local names, english = {}, {}   -- English -> this client's, and back

-- This client's name for a spell the module names in English, or the English name when it has no ID or the
-- client has no name for it yet (not kept, so a later call can still find it).
function smb.L(name)
    local known = names[name]
    if known then return known end
    local id = smb.spellIDs[name]
    local here = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if type(here) ~= "string" or here == "" then return name end
    names[name], english[here] = here, name
    return here
end

-- The English name for one of this client's spell names, when the module knows it, else the name itself.
function smb.englishName(name)
    if english[name] then return english[name] end
    for en in pairs(smb.spellIDs) do
        if smb.L(en) == name then return en end
    end
    return name
end

-- "Rank 1" as this client writes it, for "/cast Frostbolt(Rank 1)": a ranked spell's subtext ("Rang 1"),
-- with its number made 1 whatever rank it was.
local RANK_ONE_SPELL = 133 -- Fireball (Rank 1): every client has it
function smb.rankOne()
    local subtext = C_Spell and C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(RANK_ONE_SPELL)
    if type(subtext) == "string" and subtext:find("%d") then return (subtext:gsub("%d+", "1", 1)) end
    return "Rank 1"
end

-- The start of a tooltip's "Requires Battle Stance" line in this client's language.
function smb.requiresText()
    local text = type(SPELL_REQUIRED_FORM) == "string" and SPELL_REQUIRED_FORM:match("^(.-)%s*%%s") or nil
    return (text and text ~= "") and text or "Requires"
end

-- The creature family a summon spell brings, as [pet:<family>] wants it in this client's language.
function smb.petFamilyName(summon)
    local en = smb.englishName(summon)
    local id = smb.petFamilies[en]
    local info = id and C_CreatureInfo and C_CreatureInfo.GetCreatureFamilyInfo
        and C_CreatureInfo.GetCreatureFamilyInfo(id)
    if info and type(info.name) == "string" and info.name ~= "" then return info.name end
    return en:match("^Summon (.+)$") or summon
end

-- ---- the class files ---------------------------------------------------------------------------------------

-- The longest start several names share, or nil when it is too short to mean anything.
local function sharedStart(list)
    local first = list[1]
    if not first then return nil end
    local n = #first
    for i = 2, #list do
        local other = list[i]
        local j = 0
        while j < n and j < #other and first:byte(j + 1) == other:byte(j + 1) do j = j + 1 end
        n = j
    end
    if n < 4 then return nil end
    return first:sub(1, n)
end

-- A config list in this client's names. A wildcard ("Conjure *") keeps its place and is followed by the
-- same wildcard in this client's words ("Invocation d*"): the start the class's matching spells share here,
-- so they still share one position in the section, as they do in English. When they share no start, they
-- follow it one by one.
local function list(entries, class)
    if type(entries) ~= "table" then return entries end
    local out = {}
    for _, entry in ipairs(entries) do
        out[#out + 1] = type(entry) == "string" and smb.L(entry) or entry
        local prefix = type(entry) == "string" and entry:match("^(.-)%*$")
        if prefix then
            local matched = {}
            for _, en in ipairs(smb.spellPrefixes[class .. " " .. prefix] or {}) do matched[#matched + 1] = smb.L(en) end
            local start = sharedStart(matched)
            if start and start ~= prefix then
                out[#out + 1] = start .. "*"
            elseif not start then
                for _, name in ipairs(matched) do out[#out + 1] = name end
            end
        end
    end
    return out
end

local function escape(text) return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

-- A ready-made macro's body in this client's names: each spell the module knows, longest first, and the
-- families in [pet:imp] conditions.
local function body(text)
    if type(text) ~= "string" then return text end
    local known = {}
    for en in pairs(smb.spellIDs) do
        if text:find(en, 1, true) then known[#known + 1] = en end
    end
    table.sort(known, function(a, b) return #a > #b end)
    for _, en in ipairs(known) do
        local here = smb.L(en)
        if here ~= en then
            text = text:gsub("%f[%w]" .. escape(en) .. "%f[%W]", (here:gsub("%%", "%%%%")))
        end
    end
    return (text:gsub("([%[,;]%s*pet:)(%a+)", function(lead, family)
        local id = smb.petFamilies[family:sub(1, 1):upper() .. family:sub(2):lower()]
        local info = id and C_CreatureInfo and C_CreatureInfo.GetCreatureFamilyInfo
            and C_CreatureInfo.GetCreatureFamilyInfo(id)
        return lead .. (info and info.name or family)
    end))
end

local LISTS = { "mouseoverEnemy", "mouseoverFriend", "dispels", "buffs", "cursor", "raidRank1", "combatRank1",
                "channeled", "stealth", "toggle", "cooldowns", "offGcd" }

-- The player's class file, translated in place.
local function translateClass(class)
    local c = smb.classConfigs[class]
    if not c then return end
    for _, category in ipairs(c.categories or {}) do category.spells = list(category.spells, class) end
    for _, key in ipairs(LISTS) do c[key] = list(c[key], class) end
    if c.stances then
        local stances = {}
        for spell, those in pairs(c.stances) do stances[smb.L(spell)] = list(those, class) end
        c.stances = stances
    end
    if c.petAbilities then
        local abilities = {}
        for summon, ability in pairs(c.petAbilities) do abilities[smb.L(summon)] = smb.L(ability) end
        c.petAbilities = abilities
    end
    for _, form in ipairs(c.forms or {}) do form.spells = list(form.spells, class) end
    for _, entry in ipairs(c.custom or {}) do entry.body = body(entry.body) end
end

smb.localize = { list = list, body = body, translateClass = translateClass, sharedStart = sharedStart }

-- Before Macros.lua's setup, which comes next in the .toc: nothing has read the class file yet.
smb.onInstall(function()
    if ENGLISH then return end
    local class = select(2, UnitClass("player"))
    translateClass(class)
    local race = select(2, UnitRace("player"))
    if smb.racials[race] then smb.racials[race] = list(smb.racials[race], class) end
    if C_Spell and C_Spell.RequestLoadSpellData then C_Spell.RequestLoadSpellData(RANK_ONE_SPELL) end
end)
