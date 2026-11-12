-- SuspicionsPack — ConsumableMacros (WoW: Forever only, see the .toc gate)
--
-- Three account macros kept pointed at the best thing in your bags:
--   SPFoodDrink  eat and drink out of combat, optionally a mana potion in combat
--   SPBuffFood   the buff food with the highest required level
--   SPBandage    the strongest bandage your First Aid allows
--   SPHealth     a /castsequence of healthstone, potion and your own spell, never food
--
-- Buff food is eaten for its buff: only SPBuffFood picks it, never as plain regen.
--
-- Macros can only be written out of combat, so everything frequent is listened
-- to out of combat only, and the macros catch up the moment combat ends. In
-- combat this module costs nothing at all.

local SP = SuspicionsPack

local CM = SP:NewSPModule("ConsumableMacros", "consumableMacros")
SP.ConsumableMacros = CM

local FOOD_DRINK_MACRO = "SPFoodDrink"
local BUFF_FOOD_MACRO  = "SPBuffFood"
local BANDAGE_MACRO    = "SPBandage"
local HEALTH_MACRO     = "SPHealth"

-- The icon #showtooltip replaces with the item's own.
local MACRO_ICON = "INV_Misc_QuestionMark"

-- For the setup tour's example bar: the macros' names, in their order.
CM.MACROS = { FOOD_DRINK_MACRO, BUFF_FOOD_MACRO, BANDAGE_MACRO, HEALTH_MACRO }

-- The skill line every bandage asks for in the game data (its parent line is 129).
local FIRST_AID_LINE = 2942

local _issecretvalue = issecretvalue or function() return false end

-- What a pick looks for. `what` names the restore that ranks them; `buff` picks
-- buff food instead of leaving it alone, and `byLevel` ranks by required level
-- first, since a buff grows with it and buffs of different stats do not compare.
local FOOD          = { kinds = { food = true, both = true },   what = "health" }
local BUFF_FOOD     = { kinds = { food = true },                what = "health", buff = true, byLevel = true }
local DRINK         = { kinds = { drink = true, both = true },  what = "mana" }
local MANA_ITEM     = { kinds = { potion = true, gem = true },  what = "mana" }
local STONE         = { kinds = { stone = true },               what = "health" }
local HEALTH_POTION = { kinds = { potion = true },              what = "health" }
-- Bandages share one cooldown, and the debuff that blocks them is not a cooldown.
local BANDAGE       = { kinds = { bandage = true },             what = "health", ignoreCooldown = true }

-- A number, or nil for one that cannot be inspected.
local function Plain(v)
    if _issecretvalue(v) or type(v) ~= "number" then return nil end
    return v
end

-- ============================================================
-- What the player has
-- ============================================================

-- Slots, not GetItemCount per table row: that call searches the bags each time,
-- and it was PotionAlert's whole cost in the 2026-10-26 capture.
local function CarriedItems()
    local ids, seen = {}, {}
    local data = SP.ConsumableData
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            -- Guard before the truthiness test: `id and` already branches on the value.
            if not _issecretvalue(id) and id and data[id] and not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    return ids
end

-- One read per rebuild, so every comparison in it sees the same moment.
local function ReadPlayer()
    local skill = C_SkillInfo.GetSkillLineInfoByID(FIRST_AID_LINE)
    local readable = not _issecretvalue(skill) and skill
    return {
        items     = CarriedItems(),
        now       = GetTime(),
        level     = Plain(UnitLevel("player")) or 0,
        firstAid  = readable and Plain(readable.rank) or 0,
        maxHealth = Plain(UnitHealthMax("player")) or 0,
        maxMana   = Plain(UnitPowerMax("player", 0)) or 0,
    }
end

-- Seconds left, or nil when the item cannot be counted on. Keeps the soonest end,
-- so the macros can look again when a better item comes back.
local function SecondsLeft(player, start, duration)
    if start <= 0 or duration <= 0 then return 0 end
    local left = start + duration - player.now
    if left <= 0 then return 0 end
    if not player.soonest or left < player.soonest then player.soonest = left end
    return left
end

local function ItemCooldownLeft(player, id)
    local start, duration, running = C_Item.GetItemCooldown(id)
    if _issecretvalue(start) or _issecretvalue(duration) or _issecretvalue(running) then return nil end
    if running == false then return nil end
    return SecondsLeft(player, start or 0, duration or 0)
end

-- ============================================================
-- Picking
-- ============================================================

local function Restore(player, entry, what)
    if what == "health" then
        return (entry.health or 0) + player.maxHealth * (entry.healthPct or 0) / 100
    end
    return (entry.mana or 0) + player.maxMana * (entry.manaPct or 0) / 100
end

local function CanUse(player, entry)
    return entry.level <= player.level
        and (entry.firstAid == nil or entry.firstAid <= player.firstAid)
end

local function Beats(a, b, spec, preferConjured)
    if a.left ~= b.left then return a.left < b.left end
    if preferConjured and (a.entry.conjured or false) ~= (b.entry.conjured or false) then
        return a.entry.conjured == true
    end
    if spec.byLevel and a.entry.level ~= b.entry.level then return a.entry.level > b.entry.level end
    if a.amount ~= b.amount then return a.amount > b.amount end
    if a.entry.level ~= b.entry.level then return a.entry.level > b.entry.level end
    return a.id < b.id
end

local function Best(player, spec, preferConjured, minimum)
    local best
    for _, id in ipairs(player.items) do
        local entry = SP.ConsumableData[id]
        if spec.kinds[entry.kind] and (entry.buff == true) == (spec.buff == true) and CanUse(player, entry) then
            local amount = Restore(player, entry, spec.what)
            local left = 0
            if not spec.ignoreCooldown then left = ItemCooldownLeft(player, id) end
            if left and amount > 0 and amount >= (minimum or 0) then
                local candidate = { id = id, entry = entry, amount = amount, left = left }
                if not best or Beats(candidate, best, spec, preferConjured) then best = candidate end
            end
        end
    end
    return best
end

-- IsPlayerSpell, not the spellbook: every rank has its own ID here, and the
-- book can hide the lower ones (ShowAllSpellRanks).
local function BestSpell(player, list)
    local best, bestLeft
    for text in tostring(list or ""):gmatch("%d+") do
        local id = tonumber(text)
        if IsPlayerSpell(id) then
            local cd = C_Spell.GetSpellCooldown(id)
            local start, duration = cd and cd.startTime, cd and cd.duration
            if not (_issecretvalue(start) or _issecretvalue(duration)) then
                local left = SecondsLeft(player, start or 0, duration or 0)
                if not best or left < bestLeft then best, bestLeft = id, left end
            end
        end
    end
    return best and C_Spell.GetSpellName(best)
end

-- ============================================================
-- Macro bodies
-- ============================================================

-- Without its item data the macro's icon can stay a question mark.
local function ItemToken(candidate)
    C_Item.RequestLoadItemDataByID(candidate.id)
    return "item:" .. candidate.id
end

local function FoodDrinkBody(db, player)
    local hasMana = player.maxMana > 0
    local food  = db.includeFood and Best(player, FOOD, db.preferConjured) or nil
    local drink = hasMana and Best(player, DRINK, db.preferConjured,
                                   player.maxMana * (db.minManaPercent or 0) / 100) or nil
    -- One item for both is one action, and a second item would fight it for the
    -- same seat.
    if drink and drink.entry.kind == "both" then
        food = drink
    elseif food and food.entry.kind == "both" then
        drink = food
    end
    local mana = hasMana and db.manaPotionInCombat and Best(player, MANA_ITEM) or nil

    local lines = { "#showtooltip" }
    if mana then lines[#lines + 1] = "/use [combat] " .. ItemToken(mana) end
    if food then lines[#lines + 1] = "/use [nocombat] " .. ItemToken(food) end
    if drink and drink ~= food then lines[#lines + 1] = "/use [nocombat] " .. ItemToken(drink) end
    return table.concat(lines, "\n")
end

local function BuffFoodBody(player)
    local food = Best(player, BUFF_FOOD)
    if not food then return "#showtooltip" end
    return "#showtooltip\n/use [nocombat] " .. ItemToken(food)
end

local function BandageBody(player)
    local bandage = Best(player, BANDAGE)
    if not bandage then return "#showtooltip" end
    local token = ItemToken(bandage)
    return "#showtooltip " .. token .. "\n/use [nochanneling] " .. token
end

local function HealthSequence(db, player)
    local tokens, used = {}, {}
    for _, category in ipairs({ db.priority1, db.priority2, db.priority3 }) do
        if not used[category] then
            used[category] = true
            local token
            if category == "stone" then
                local stone = Best(player, STONE)
                token = stone and ItemToken(stone)
            elseif category == "potion" then
                local potion = Best(player, HEALTH_POTION)
                token = potion and ItemToken(potion)
            elseif category == "spell" then
                token = BestSpell(player, db.customSpells)
            end
            if token then tokens[#tokens + 1] = token end
        end
    end
    return table.concat(tokens, ", ")
end

local function HealthBody(db, player)
    local lines = { "#showtooltip" }
    if db.stopCasting then lines[#lines + 1] = "/stopcasting" end
    local sequence = HealthSequence(db, player)
    if sequence ~= "" then
        lines[#lines + 1] = "/castsequence reset=" .. tostring(db.reset) .. " " .. sequence
    end
    return table.concat(lines, "\n")
end

-- ============================================================
-- Writing
-- ============================================================

local warnedFull = {}

local function WriteMacro(name, body)
    local index = GetMacroIndexByName(name)
    if index and index > 0 then
        local _, _, current = GetMacroInfo(index)
        if current ~= body then EditMacro(index, nil, nil, body) end
        return
    end
    if GetNumMacros() >= Constants.MacroConsts.MAX_ACCOUNT_MACROS then
        if not warnedFull[name] then
            warnedFull[name] = true
            print("|cffe51039SuspicionsPack|r : no room for the " .. name .. " macro, your account macros are full.")
        end
        return
    end
    CreateMacro(name, MACRO_ICON, body)
end

local rebuildQueued = false
local cooldownTimer

local function CancelCooldownTimer()
    if cooldownTimer then
        cooldownTimer:Cancel()
        cooldownTimer = nil
    end
end

local RequestRebuild

local function Rebuild()
    rebuildQueued = false
    if not CM:IsOn() or InCombatLockdown() then return end
    local db = CM:GetDB()
    local player = ReadPlayer()
    if db.foodDrink then WriteMacro(FOOD_DRINK_MACRO, FoodDrinkBody(db, player)) end
    if db.buffFood then WriteMacro(BUFF_FOOD_MACRO, BuffFoodBody(player)) end
    if db.bandage then WriteMacro(BANDAGE_MACRO, BandageBody(player)) end
    if db.health then WriteMacro(HEALTH_MACRO, HealthBody(db, player)) end

    -- No event is promised when a cooldown ends, and until then the pick may be
    -- a lesser item.
    CancelCooldownTimer()
    if player.soonest then
        cooldownTimer = C_Timer.NewTimer(player.soonest + 0.05, function()
            cooldownTimer = nil
            RequestRebuild()
        end)
    end
end

-- A loot or a stack change is a burst of events: one rebuild for all of them.
RequestRebuild = function()
    if rebuildQueued then return end
    rebuildQueued = true
    C_Timer.After(0.1, Rebuild)
end

-- ============================================================
-- Events
-- ============================================================

local OUT_OF_COMBAT_EVENTS = {
    "BAG_UPDATE_DELAYED",
    "BAG_UPDATE_COOLDOWN",
    "PLAYER_LEVEL_UP",
    "SKILL_LINES_CHANGED",
    "SPELLS_CHANGED",
}

local function WatchesSpells(db)
    return db.health and tostring(db.customSpells or ""):find("%d") ~= nil
end

function CM:OnChange()
    RequestRebuild()
end

function CM:OnUnitMaximum(_, unit)
    if _issecretvalue(unit) or unit ~= "player" then return end
    RequestRebuild()
end

function CM:ListenOutOfCombat()
    for _, event in ipairs(OUT_OF_COMBAT_EVENTS) do
        self:RegisterEvent(event, "OnChange")
    end
    self:RegisterEvent("UNIT_MAXHEALTH", "OnUnitMaximum")
    self:RegisterEvent("UNIT_MAXPOWER", "OnUnitMaximum")
    if WatchesSpells(self:GetDB()) then
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnChange")
    else
        self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    end
end

function CM:OnCombatStart()
    for _, event in ipairs(OUT_OF_COMBAT_EVENTS) do
        self:UnregisterEvent(event)
    end
    self:UnregisterEvent("UNIT_MAXHEALTH")
    self:UnregisterEvent("UNIT_MAXPOWER")
    self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
end

function CM:OnCombatEnd()
    self:ListenOutOfCombat()
    RequestRebuild()
end

-- ============================================================
-- Activate / Deactivate
-- Everything else (Refresh / OnEnable / OnDisable) comes from SP.ModuleMixin.
-- ============================================================

-- Also how a settings change reaches the macros: GUI.Applier -> Refresh -> here.
function CM:Activate()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnChange")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
    if not InCombatLockdown() then self:ListenOutOfCombat() end
    RequestRebuild()
end

-- The macros stay: they may be on someone's action bars.
function CM:Deactivate()
    self:UnregisterAllEvents()
    CancelCooldownTimer()
end
