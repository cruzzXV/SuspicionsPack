-- SuspicionsPack — SimpleStats (WoW: Forever only, see the .toc gate)
--
-- An item's long bonus lines, in short: "Equip: Increases damage and healing done by magical
-- spells and effects by up to 12." becomes "+12 Spell Power", in the line's own green.
--
-- Forever turned Vanilla's equip spells into item stats, and the client writes each one from a
-- TOOLTIP_ITEM_STAT_* format. Every pattern here is built from those formats and every label is
-- the client's own, so any client language works. The French formats start with "Équipé :" or
-- "Équiper :", never with ITEM_SPELL_TRIGGER_ONEQUIP ("Equipé :"): no line is picked by its
-- prefix, a line matches a whole format or is left as it is.
--
-- Written after EllesmereUI Forever Essentials' Simplified Stats (All Rights Reserved: read for
-- its behaviour, nothing copied). Ours swaps a line before the game adds it, in a line pre-call,
-- instead of rewriting the tooltip's text afterwards.
--
-- Set bonuses: in English their text is a stat format without its "Equip: ", and they shorten
-- too. In French it is a spell's description, worded otherwise, and they stay as they are.

local SP = SuspicionsPack

local SS = SP:NewSPModule("SimpleStats", "simpleStats")
SP.SimpleStats = SS

local _issecretvalue = issecretvalue or function() return false end

local active = false

-- ============================================================
-- What gets shortened
-- ============================================================
-- [TOOLTIP_ITEM_STAT_<key>_INCREASE / _DECREASE] = its short label: client globals, the first
-- one that exists. A key the client lacks is skipped.
local SINGLE = {
    SPELL_DAMAGE        = { "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" },
    SPELL_HEALING       = { "ITEM_MOD_SPELL_HEALING_DONE_SHORT" },
    SPELL_PENETRATION   = { "ITEM_MOD_SPELL_PENETRATION_SHORT" },
    ARMOR_PENETRATION   = { "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT" },
    ATTACK_POWER        = { "ITEM_MOD_ATTACK_POWER_SHORT" },
    RANGED_ATTACK_POWER = { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT" },
    HIT_PERCENT         = { "ITEM_MOD_HIT_RATING_SHORT" },
    -- The rating's label reads "Score de crit." in French, wrong for a percentage.
    CRIT_PERCENT        = { "STAT_CRITICAL_STRIKE", "ITEM_MOD_CRIT_RATING_SHORT" },
    HASTE_PCT           = { "ITEM_MOD_HASTE_RATING_SHORT" },
    EXPERTISE_PCT       = { "ITEM_MOD_EXPERTISE_RATING_SHORT" },
    DODGE_PCT           = { "ITEM_MOD_DODGE_RATING_SHORT" },
    PARRY_PCT           = { "ITEM_MOD_PARRY_RATING_SHORT" },
    BLOCK_CHANCE        = { "ITEM_MOD_BLOCK_RATING_SHORT" },
    BLOCK_VALUE         = { "ITEM_MOD_BLOCK_VALUE_SHORT" },
    DEFENSE             = { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT" },
    MANA_REGEN          = { "ITEM_MOD_POWER_REGEN0_SHORT" },
    HEALTH_REGEN        = { "ITEM_MOD_HEALTH_REGEN_SHORT" },
}
for _, school in ipairs({ "HOLY", "FIRE", "NATURE", "FROST", "SHADOW", "ARCANE" }) do
    SINGLE[school .. "_DAMAGE"]      = { "ITEM_MOD_" .. school .. "_DAMAGE_DONE_SHORT" }
    SINGLE[school .. "_PENETRATION"] = { "ITEM_MOD_" .. school .. "_PENETRATION_SHORT" }
end
-- Weapon and profession skills: TOOLTIP_ITEM_STAT_SKILL_<key> -> ITEM_MOD_<key>_SHORT,
-- five of them under another name (the two-handed formats have a dash, their labels none).
local SKILL_LABEL = { THROWN_WEAPONS = "THROWN", DUAL_WIELDING = "DUAL_WIELD",
                      ["TWO-HANDED_SWORDS"] = "TWOHANDED_SWORDS", ["TWO-HANDED_MACES"] = "TWOHANDED_MACES",
                      ["TWO-HANDED_AXES"] = "TWOHANDED_AXES" }
for _, key in ipairs({ "SWORDS", "MACES", "AXES", "TWO-HANDED_SWORDS", "TWO-HANDED_MACES",
                       "TWO-HANDED_AXES", "FIST_WEAPONS", "DAGGERS", "STAVES", "POLEARMS",
                       "BOWS", "CROSSBOWS", "GUNS", "WANDS", "THROWN_WEAPONS", "DUAL_WIELDING",
                       "ALCHEMY", "JEWELCRAFTING", "BLACKSMITHING", "ENCHANTING", "ENGINEERING",
                       "LEATHERWORKING", "HERBALISM", "MINING", "SKINNING", "COOKING", "FIRST_AID",
                       "FISHING", "TAILORING" }) do
    SINGLE["SKILL_" .. key] = { "ITEM_MOD_" .. (SKILL_LABEL[key] or key) .. "_SHORT" }
end

local DAMAGE_LABEL  = { "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT" }
local HEALING_LABEL = { "ITEM_MOD_SPELL_HEALING_DONE_SHORT" }
local POWER_LABEL   = { "ITEM_MOD_SPELL_POWER_SHORT" }

local DIRECTIONS = { INCREASE = "+", DECREASE = "-" }

-- ============================================================
-- Formats into patterns
-- ============================================================
local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"

local function Label(globals)
    for _, name in ipairs(globals) do
        local text = _G[name]
        if type(text) == "string" and text ~= "" then return text end
    end
end

-- A format as a Lua pattern: each figure captured, the plural token ("$lpoint:points;") either
-- word, the rest literal. Also returns, per argument number, its capture's place: a language
-- may put the figures in another order. Every stat format numbers its arguments ("%1$d").
local function Compile(fmt)
    local slot, n = {}, 0
    local f = fmt:gsub("%%%%", "\002")
    for arg in f:gmatch("%%(%d)%$") do
        n = n + 1
        slot[tonumber(arg)] = n
    end
    local figures
    f, figures = f:gsub("%%%d%$[%d%.]*[dfis]", "\001")
    if figures == 0 then return end
    f = f:gsub("%$l[^:;]*:[^;]*;", "\003")
    f = f:gsub(MAGIC, "%%%0")
    f = f:gsub("\001", "([%%d%%.,]+)"):gsub("\002", "%%%%"):gsub("\003", "%%S+")
    return "^" .. f .. "$", slot
end

-- "(%d) Set: %s" -> "^(%(%d+%) Set: )(.+)$"; nil unless the format ends in its text.
local function PrefixPattern(fmt)
    local pre = type(fmt) == "string" and fmt:match("^(.+)%%s$")
    if not pre then return end
    pre = pre:gsub("%%d", "\001"):gsub(MAGIC, "%%%0"):gsub("\001", "%%d+")
    return "^(" .. pre .. ")(.+)$"
end

local rules, prefixes

-- outs: { argument number, sign, label } per line it gives.
-- merge: one figure for spell damage and healing, which can read as one Spell Power line.
local function AddRule(fmtName, outs, merge)
    local fmt = _G["TOOLTIP_ITEM_STAT_" .. fmtName]
    if type(fmt) ~= "string" then return end
    for _, out in ipairs(outs) do
        if not out[3] then return end
    end
    local pat, slot = Compile(fmt)
    if not pat then return end
    -- The same text without its trigger ("Equip: "), as a set bonus carries it.
    local rest = fmt:match("^[^%%:]*:%s*(.+)$")
    rules[#rules + 1] = {
        pat   = pat,
        bare  = rest and Compile(rest),
        slot  = slot,
        outs  = outs,
        pct   = fmt:find("%%%%") and "%" or "",
        merge = merge,
    }
end

local function BuildRules()
    rules, prefixes = {}, {}
    local damage, healing = Label(DAMAGE_LABEL), Label(HEALING_LABEL)
    for dir, sign in pairs(DIRECTIONS) do
        for key, globals in pairs(SINGLE) do
            AddRule(key .. "_" .. dir, { { 1, sign, Label(globals) } })
        end
        AddRule("SPELL_POWER_" .. dir, { { 1, sign, damage }, { 1, sign, healing } }, true)
        -- "healing done by up to %1$d and damage done by up to %2$d"
        for dmgDir, dmgSign in pairs(DIRECTIONS) do
            AddRule("SPELL_HEALING_" .. dir .. "_DAMAGE_" .. dmgDir,
                { { 2, dmgSign, damage }, { 1, sign, healing } }, true)
        end
    end
    for _, name in ipairs({ "ITEM_SET_BONUS", "ITEM_SET_BONUS_GRAY" }) do
        local pat = PrefixPattern(_G[name])
        if pat then prefixes[#prefixes + 1] = pat end
    end
    SP:Debug("SimpleStats", #rules, "rules,", #prefixes, "set bonus prefixes")
end

-- ============================================================
-- One line
-- ============================================================
-- "1.0" -> "1": the client writes percentages with one decimal.
local function Figure(s)
    return (s:gsub("^(%d+)[%.,]0$", "%1"))
end

local function Lines(rule, c1, c2)
    local caps = { c1, c2 }
    local out = {}
    for i, o in ipairs(rule.outs) do
        out[i] = o[2] .. Figure(caps[rule.slot[o[1]]] or "?") .. rule.pct
    end
    local db = SS:GetDB()
    local merge = not db or db.merge ~= false
    if merge and rule.merge and out[1] == out[2] then
        local label = Label(POWER_LABEL)
        if label then return { out[1] .. " " .. label } end
    end
    for i, o in ipairs(rule.outs) do
        out[i] = out[i] .. " " .. o[3]
    end
    return out
end

-- The short lines for one tooltip text, or false to leave it.
local function Shorten(text)
    if not rules then BuildRules() end
    for _, rule in ipairs(rules) do
        local c1, c2 = text:match(rule.pat)
        if c1 then return Lines(rule, c1, c2) end
    end
    for _, prefix in ipairs(prefixes) do
        local pre, inner = text:match(prefix)
        if pre then
            for _, rule in ipairs(rules) do
                local c1, c2
                if rule.bare then c1, c2 = inner:match(rule.bare) end
                if c1 then
                    local out = Lines(rule, c1, c2)
                    for i = 1, #out do out[i] = pre .. out[i] end
                    return out
                end
            end
            return false
        end
    end
    return false
end

-- ============================================================
-- The tooltips
-- ============================================================
-- Only the tooltips the player reads. Other addons read items through hidden tooltips of
-- their own and parse the game's lines: those keep the original text.
local TIP_NAMES = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2",
                    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }
local shown = {}

-- A shown tooltip is rebuilt on every data update: each text's answer is kept, until a
-- setting changes.
local memo, memoSize, MEMO_MAX = {}, 0, 500

local function OnLine(tooltip, lineData)
    if not active or not shown[tooltip] or type(lineData) ~= "table" then return end
    -- A line with a right text is never a bonus line; a secret one returns here too.
    local text = lineData.leftText
    if not text or _issecretvalue(text) or lineData.rightText then return end
    local out = memo[text]
    if out == nil then
        out = text:find("%d") and Shorten(text) or false
        if memoSize >= MEMO_MAX then
            wipe(memo)
            memoSize = 0
        end
        memo[text] = out
        memoSize = memoSize + 1
    end
    if not out then return end
    -- What the game would have done with the line (TooltipDataHandlerMixin:AddLineDataText).
    local color = lineData.leftColor or NORMAL_FONT_COLOR
    local r, g, b = color:GetRGB()
    for i = 1, #out do
        tooltip:AddLine(out[i], r, g, b, lineData.wrapText, lineData.leftOffset)
    end
    -- Consumed: the game does not add its own line.
    return true
end

local hooked = false

-- Once: the processor has no way to take a call back, so OnLine checks `active`.
local function Hook()
    if hooked then return end
    hooked = true
    for _, name in ipairs(TIP_NAMES) do
        local tip = _G[name]
        if tip then shown[tip] = true end
    end
    TooltipDataProcessor.AddLinePreCall(TooltipDataProcessor.AllTypes,
        SP.Perf.Wrap("SimpleStats", "tooltip line", OnLine))
end

-- For the options page and the setup tour: the client's own line for a stat, and what
-- it becomes. The spell power line (damage and healing) unless `key` names another
-- TOOLTIP_ITEM_STAT_<key>, as "SPELL_HEALING_INCREASE" for healing only.
function SS.Example(value, key)
    local fmt = _G["TOOLTIP_ITEM_STAT_" .. (key or "SPELL_POWER_INCREASE")]
    if type(fmt) ~= "string" then return end
    local ok, before = pcall(string.format, fmt:gsub("%%(%d)%$", "%%"), value or 12)
    if not ok then return end
    local out = Shorten(before)
    return before, out and table.concat(out, "\n") or nil
end

-- ============================================================
-- Lifecycle
-- ============================================================
function SS:Activate()
    active = true
    -- The answers depend on the merge setting.
    wipe(memo)
    memoSize = 0
    Hook()
end

function SS:Deactivate()
    active = false
end
