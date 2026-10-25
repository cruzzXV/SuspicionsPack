-- SuspicionsPack — Datatexts: Hearthstone, Durability, Gold

local SP = SuspicionsPack
local DT = SP.Datatexts

local floor = math.floor

local function Icon(file, size)
    if not file then return "" end
    size = size or 14
    return "|T" .. file .. ":" .. size .. ":" .. size .. ":0:0:64:64:5:59:5:59|t "
end

-- 1:23:45, 12:34 or 0:05.
local function Clock(seconds)
    seconds = floor(seconds + 0.5)
    local h, m, s = floor(seconds / 3600), floor(seconds % 3600 / 60), seconds % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
    return string.format("%d:%02d", m, s)
end
DT.Clock = Clock

-- ============================================================
-- Hearthstone
--
-- The secure button over the slot does the casting (Datatexts.lua). Right
-- click picks what it uses: the Hearthstone, one of the hearthstone toys this
-- account owns, or a random one of them, drawn again before every use.
-- ============================================================
local HEARTHSTONE = 6948

-- Hearthstone toys, by item id. PlayerHasToy answers false for any the
-- account lacks or the client does not have, so the list can be generous;
-- names come from the game.
local HEARTH_TOYS = {
    54452, 64488, 93672, 142542, 162973, 163045, 165669, 165670, 165802, 166746,
    166747, 168907, 172179, 188952, 190196, 190237, 193588, 200630, 206195,
    208704, 209035, 210455, 212337, 228940,
}

local function OwnedToys()
    local out = {}
    if not PlayerHasToy then return out end
    for _, id in ipairs(HEARTH_TOYS) do
        if PlayerHasToy(id) then out[#out + 1] = id end
    end
    return out
end

local function ItemName(id)
    local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    return name or ("Item " .. id)
end

-- What a click uses now: "item", 6948 or "toy", <id>.
local randomPick
local function Chosen(o)
    local use = o.use
    if use == "random" then
        local owned = OwnedToys()
        if #owned > 0 then
            if not (randomPick and PlayerHasToy(randomPick)) then
                randomPick = owned[math.random(#owned)]
            end
            return "toy", randomPick
        end
    elseif use and use ~= "hearthstone" then
        local id = tonumber(use)
        if id and PlayerHasToy and PlayerHasToy(id) then return "toy", id end
    end
    return "item", HEARTHSTONE
end

local function Remaining(id)
    if not (C_Container and C_Container.GetItemCooldown) then return 0 end
    local start, duration = C_Container.GetItemCooldown(id)
    if not (start and duration) or duration <= 1.5 then return 0 end
    local left = start + duration - GetTime()
    return left > 0 and left or 0
end

local function SetUse(key)
    DT.SetOption("hearthstone", "use", key)
    randomPick = nil
    DT.RefreshSecure("hearthstone")
    DT.Update("hearthstone")
end

DT.Register("hearthstone", {
    name     = "Hearthstone",
    group    = "Character",
    events   = { "BAG_UPDATE_COOLDOWN", "HEARTHSTONE_BOUND", "PLAYER_ENTERING_WORLD", "TOYS_UPDATED" },
    interval = 1,
    options  = {
        { kind = "toggle", key = "showLocation", label = "Show where it is bound", default = true },
        { kind = "dropdown", key = "use", label = "Use", default = "hearthstone",
          optionsFn = function()
              local list = { { key = "hearthstone", label = ItemName(HEARTHSTONE) },
                             { key = "random", label = "A random hearthstone toy" } }
              for _, id in ipairs(OwnedToys()) do
                  list[#list + 1] = { key = tostring(id), label = ItemName(id) }
              end
              return list
          end },
    },
    Text = function(o)
        local _, id = Chosen(o)
        local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
        local left = Remaining(id)
        if left > 0 then return Icon(icon) .. Clock(left) end
        if o.showLocation then return Icon(icon) .. (GetBindLocation() or "") end
        return Icon(icon) .. ItemName(id)
    end,
    Tooltip = function(o, tt)
        local _, id = Chosen(o)
        DT.TipHeader(tt, ItemName(id))
        DT.TipLine(tt, "Bound to", GetBindLocation() or "?")
        local left = Remaining(id)
        DT.TipLine(tt, "Cooldown", left > 0 and Clock(left) or "Ready")
        DT.TipSpace(tt)
        DT.TipNote(tt, "Click: use    Right-click: choose")
    end,
    -- "*type1": any modifier held, a left click still uses it (a bare
    -- "type1" matches an unmodified click only).
    Secure = function(o, b)
        local kind, id = Chosen(o)
        b:SetAttribute("*type1", kind)
        b:SetAttribute("*item1", kind == "item" and ("item:" .. id) or nil)
        b:SetAttribute("*toy1", kind == "toy" and id or nil)
    end,
    -- A random toy is drawn again before each use (out of combat only, where
    -- attributes may change).
    PreClick = function(o, b, button)
        if button == "LeftButton" and o.use == "random" then
            randomPick = nil
            local kind, id = Chosen(o)
            b:SetAttribute("*type1", kind)
            b:SetAttribute("*toy1", kind == "toy" and id or nil)
            b:SetAttribute("*item1", kind == "item" and ("item:" .. id) or nil)
        end
    end,
    Click = function(o, slot, button)
        if button ~= "RightButton" or not MenuUtil then return end
        MenuUtil.CreateContextMenu(slot, function(_, root)
            root:CreateTitle("Hearthstone")
            local function Is(key) return (o.use or "hearthstone") == key end
            root:CreateRadio(ItemName(HEARTHSTONE), Is, SetUse, "hearthstone")
            local owned = OwnedToys()
            if #owned > 0 then
                root:CreateRadio("A random hearthstone toy", Is, SetUse, "random")
                for _, id in ipairs(owned) do
                    root:CreateRadio(ItemName(id), Is, SetUse, tostring(id))
                end
            end
        end)
    end,
})

-- ============================================================
-- Durability
-- ============================================================
local function ScanDurability()
    local lowest, items = nil, {}
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local f = cur / max
            items[#items + 1] = { slot = slot, f = f }
            if not lowest or f < lowest then lowest = f end
        end
    end
    return lowest, items
end

DT.Register("durability", {
    name   = "Durability",
    group  = "Character",
    label  = "Durability",
    events = { "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "MERCHANT_CLOSED", "PLAYER_ENTERING_WORLD" },
    Text = function()
        local lowest = ScanDurability()
        if not lowest then return "100%" end
        return DT.Gradient(lowest) .. floor(lowest * 100 + 0.5) .. "%|r"
    end,
    Tooltip = function(o, tt)
        DT.TipHeader(tt, "Durability")
        local _, items = ScanDurability()
        local cost = 0
        for _, it in ipairs(items) do
            local link = GetInventoryItemLink("player", it.slot)
            DT.TipLine(tt, link or ("Slot " .. it.slot), DT.Gradient(it.f) .. floor(it.f * 100 + 0.5) .. "%|r")
            local data = C_TooltipInfo and C_TooltipInfo.GetInventoryItem
                and C_TooltipInfo.GetInventoryItem("player", it.slot)
            if data and type(data.repairCost) == "number" then cost = cost + data.repairCost end
        end
        if #items == 0 then DT.TipNote(tt, "Nothing equipped that wears.") end
        if cost > 0 then
            DT.TipSpace(tt)
            -- Not the bare GetCoinTextureString: the engine only has
            -- C_CurrencyInfo's.
            DT.TipLine(tt, "Repair cost", DT.FormatMoney(cost, true, true))
        end
        DT.TipSpace(tt)
        DT.TipNote(tt, "Click: character")
    end,
    Click = function(o, slot, button)
        if button == "LeftButton" and not InCombatLockdown() then ToggleCharacter("PaperDollFrame") end
    end,
})

-- ============================================================
-- Gold
--
-- Every character's gold is kept account-wide (SP.GetGlobalDB), so the
-- tooltip can list the alts on this realm and the total.
-- ============================================================
local GOLD_ICON   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"

local function Thousands(n)
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function Money(copper, silver, copperToo)
    copper = floor(copper or 0)
    local g, s, c = floor(copper / 10000), floor(copper % 10000 / 100), copper % 100
    local out = Thousands(g) .. GOLD_ICON
    if silver then out = out .. " " .. s .. SILVER_ICON end
    if copperToo then out = out .. " " .. c .. COPPER_ICON end
    return out
end

DT.FormatMoney = Money

local session  -- money when this session's count started
local redrawing = false

local function Store()
    local g = SP.GetGlobalDB().datatexts
    if not g then return nil end
    g.gold = g.gold or {}
    local realm = GetRealmName() or "?"
    g.gold[realm] = g.gold[realm] or {}
    return g.gold[realm]
end

local function Record()
    local realmList = Store()
    if not realmList then return end
    local _, class = UnitClass("player")
    realmList[UnitName("player")] = { money = GetMoney(), class = class }
end

local function DeleteCharacter(name)
    local realmList = Store()
    if realmList then realmList[name] = nil end
    DT.Update("gold")
end

DT.Register("gold", {
    name   = "Gold",
    group  = "Character",
    events = { "PLAYER_MONEY", "PLAYER_ENTERING_WORLD", "TOKEN_MARKET_PRICE_UPDATED" },
    options = {
        { kind = "toggle", key = "showSilver", label = "Show silver", default = true },
        { kind = "toggle", key = "showCopper", label = "Show copper", default = true },
    },
    OnStart = function()
        if not session then session = GetMoney() end
        Record()
    end,
    OnEvent = function(o, event)
        if event ~= "TOKEN_MARKET_PRICE_UPDATED" then Record() return end
        -- The price asked for on hover: redraw without asking again, the
        -- request itself fires this event.
        local owner = DT.TooltipOwner and DT.TooltipOwner()
        if owner and owner.id == "gold" then
            redrawing = true
            DT.SlotEnter(owner)
            redrawing = false
        end
    end,
    Text = function(o)
        return Money(GetMoney(), o.showSilver, o.showCopper)
    end,
    Tooltip = function(o, tt)
        local money = GetMoney()
        DT.TipHeader(tt, "Gold")
        local diff = money - (session or money)
        if diff >= 0 then
            DT.TipLine(tt, "Earned this session", Money(diff, true, true))
        else
            DT.TipLine(tt, "Spent this session", Money(-diff, true, true), 1, 0.4, 0.4)
        end

        local realmList = Store() or {}
        local chars, total = {}, 0
        for name, rec in pairs(realmList) do
            if type(rec) == "table" and rec.money then
                chars[#chars + 1] = { name = name, money = rec.money, class = rec.class }
                total = total + rec.money
            end
        end
        table.sort(chars, function(a, b) return a.money > b.money end)
        DT.TipSpace(tt)
        DT.TipHeader(tt, GetRealmName() or "Realm")
        for _, c in ipairs(chars) do
            local cc = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]
            local hex = cc and DT.Hex(cc.r, cc.g, cc.b) or "|cffffffff"
            DT.TipLine(tt, hex .. c.name .. "|r", Money(c.money, o.showSilver, o.showCopper))
        end
        DT.TipLine(tt, "Total", Money(total, o.showSilver, o.showCopper))

        -- Only when the realm has a token market: the price stays nil or 0
        -- otherwise.
        local api = C_WowTokenPublic
        if api and api.GetCurrentMarketPrice then
            if api.UpdateMarketPrice and not redrawing then api.UpdateMarketPrice() end
            local price = api.GetCurrentMarketPrice()
            if type(price) == "number" and price > 0 then
                DT.TipSpace(tt)
                DT.TipLine(tt, "WoW Token", Money(price, false, false))
            end
        end

        DT.TipSpace(tt)
        DT.TipNote(tt, "Click: bags    Shift+right-click: reset session    Alt+right-click: forget a character")
    end,
    Click = function(o, slot, button)
        if button == "LeftButton" then
            if not InCombatLockdown() and ToggleAllBags then ToggleAllBags() end
        elseif button == "RightButton" and IsShiftKeyDown() then
            session = GetMoney()
        elseif button == "RightButton" and IsAltKeyDown() and MenuUtil then
            local me = UnitName("player")
            MenuUtil.CreateContextMenu(slot, function(_, root)
                root:CreateTitle("Forget a character")
                for name in pairs(Store() or {}) do
                    if name ~= me then root:CreateButton(name, function() DeleteCharacter(name) end) end
                end
            end)
        end
    end,
})
