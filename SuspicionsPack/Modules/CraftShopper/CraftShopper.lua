-- SuspicionsPack — CraftShopper Module
-- Tracks crafting recipe quantities and builds a shopping list of missing
-- reagents. When the Auction House is open the list pops up beside it
-- with per-item Search-AH and Quick-Buy buttons.
--
-- Ported and fully rewritten from Enhanced QoL's CraftShopper by R41z0r.
-- No AceGUI dependency; no localisation dependency; UI rebuilt natively.
local SP = SuspicionsPack

local CS = SP:NewModule("CraftShopper", "AceEvent-3.0")
SP.CraftShopper = CS

-- ============================================================
-- Constants
-- ============================================================
local SP_FONT      = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"
local BLANK        = "Interface\\Buttons\\WHITE8X8"
local SCAN_DELAY   = 0.3
local ROW_H        = 24
local SHOP_W       = 340
local SCROLL_W     = 6          -- thin custom scrollbar width
local BOTH_RECRAFT = { false, true }

local mapQuality = {
    [0] = Enum.AuctionHouseFilter.PoorQuality,
    [1] = Enum.AuctionHouseFilter.CommonQuality,
    [2] = Enum.AuctionHouseFilter.UncommonQuality,
    [3] = Enum.AuctionHouseFilter.RareQuality,
    [4] = Enum.AuctionHouseFilter.EpicQuality,
    [5] = Enum.AuctionHouseFilter.LegendaryQuality,
    [6] = Enum.AuctionHouseFilter.ArtifactQuality,
    [7] = Enum.AuctionHouseFilter.LegendaryCraftedItemOnly,
}

local purchaseErrorCodes = {
    [Enum.AuctionHouseError.NotEnoughMoney] = true,
    [Enum.AuctionHouseError.ItemNotFound]   = true,
}

-- ============================================================
-- State
-- ============================================================
local items       = {}   -- [{ itemID, qtyNeeded, owned, missing, ahBuyable, hidden, name, qualityRank, hasAlternatives }]
local ahCache     = {}   -- [itemID] = bool — AH-buyable cache
local schemCache  = {}   -- [recipeID] = schematic (normal)
local schemRecraft = {}  -- [recipeID] = schematic (recraft)
local purchased   = {}   -- [itemID] = true — hidden after successful quick-buy
local pendingScan = nil
local scanRunning = false
local pendingBuy       = nil  -- active commodity purchase state
local lastBuyID        = nil  -- itemID being purchased
local lastPurchaseInfo = nil  -- { name, need, total } stored at confirm time for the toast

-- Forward declarations (assigned below, after helpers)
local BuildList
local ShowIfNeeded
local RefreshList
local ShowBuyPopup

-- ============================================================
-- DB
-- ============================================================
local function GetDB()
    return SP.GetDB().craftShopper
end

local function IsEnabled()
    local db = GetDB()
    return db and db.enabled
end

-- ============================================================
-- Helpers
-- ============================================================
local function HasTracked()
    for _, r in ipairs(BOTH_RECRAFT) do
        local t = C_TradeSkillUI.GetRecipesTracked(r)
        if t and #t > 0 then return true end
    end
    return false
end

local function IsAHBuyable(id)
    if ahCache[id] ~= nil then return ahCache[id] end
    local buyable = true
    if C_TooltipInfo then
        local data = C_TooltipInfo.GetItemByID(id)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                -- line.type 20 = item property (BoE), line.type 0 = plain text (Conjured)
                -- Both checks required to avoid false positives from other tooltip lines
                if (line.type == 20 and line.leftText == ITEM_BIND_ON_EQUIP)
                or (line.type == 0  and line.leftText == ITEM_CONJURED) then
                    buyable = false; break
                end
            end
        end
    end
    ahCache[id] = buyable
    return buyable
end

local function GetSchematic(id, recraft)
    local cache = recraft and schemRecraft or schemCache
    if not cache[id] then
        cache[id] = C_TradeSkillUI.GetRecipeSchematic(id, recraft)
    end
    return cache[id]
end

-- ============================================================
-- Shopping-list builder
-- ============================================================
BuildList = function()
    -- need[id] = { qty, ahBuy, qualityRank, hasAlternatives }
    -- When a reagent slot offers multiple quality tiers (different itemIDs per rank),
    -- we collect EACH distinct itemID as a separate entry so the player can choose
    -- which quality to buy.  The full quantity is listed for every alternative —
    -- satisfying the slot with ANY one quality clears that need.
    local need     = {}
    local siblings = {}  -- [id] -> { [sibId] = true, ... } — all quality alts for the same slot

    for _, recraft in ipairs(BOTH_RECRAFT) do
        local recipes = C_TradeSkillUI.GetRecipesTracked(recraft) or {}
        for _, rid in ipairs(recipes) do
            local schem = GetSchematic(rid, recraft)
            if schem and schem.reagentSlotSchematics then
                for _, slot in ipairs(schem.reagentSlotSchematics) do
                    if slot.reagentType == Enum.CraftingReagentType.Basic then
                        local req = slot.quantityRequired

                        -- Collect all distinct non-zero itemIDs from this slot's quality tiers.
                        local slotIds = {}   -- { { id, rank } } in rank order
                        local seen    = {}
                        for rank, reagent in ipairs(slot.reagents) do
                            local id = reagent and reagent.itemID
                            if id and id ~= 0 and not seen[id] then
                                seen[id] = true
                                table.insert(slotIds, { id = id, rank = rank })
                            end
                        end
                        -- Only process slots where at least one quality tier has a valid itemID
                        if #slotIds > 0 then
                            local hasAlts = #slotIds > 1

                            for _, entry in ipairs(slotIds) do
                                local id, rank = entry.id, entry.rank
                                if not need[id] then
                                    need[id] = {
                                        qty             = 0,
                                        ahBuy           = IsAHBuyable(id),
                                        qualityRank     = rank,
                                        hasAlternatives = hasAlts,
                                    }
                                end
                                need[id].qty = need[id].qty + req
                                -- A later recipe may reference the same id in a multi-quality slot
                                if hasAlts then need[id].hasAlternatives = true end
                            end

                            -- Register quality siblings so result-building can suppress the whole
                            -- slot when any one tier already satisfies the need.
                            if hasAlts then
                                for _, a in ipairs(slotIds) do
                                    if not siblings[a.id] then siblings[a.id] = {} end
                                    for _, b in ipairs(slotIds) do
                                        siblings[a.id][b.id] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    local result = {}
    for id, want in pairs(need) do
        local owned    = C_Item.GetItemCount(id, true)   -- includes bank (for missing calc)
        local bagCount = C_Item.GetItemCount(id, false)  -- bags only (for display)
        if purchased[id] and owned >= want.qty then purchased[id] = nil end
        local missing = math.max(want.qty - owned, 0)

        -- For quality alternatives: suppress this entry if any sibling already owns enough.
        -- This prevents quality 2 from reappearing after quality 1 was bought to fill the slot.
        local sibSatisfied = false
        if want.hasAlternatives and siblings[id] then
            for sibId in pairs(siblings[id]) do
                if C_Item.GetItemCount(sibId, true) >= want.qty then
                    sibSatisfied = true; break
                end
            end
        end

        if missing > 0 and not purchased[id] and not sibSatisfied then
            table.insert(result, {
                itemID          = id,
                qtyNeeded       = want.qty,
                owned           = owned,
                bagCount        = bagCount,
                missing         = missing,
                ahBuyable       = want.ahBuy,
                hidden          = false,
                qualityRank     = want.qualityRank,
                hasAlternatives = want.hasAlternatives,
            })
        end
    end
    return result
end

-- ============================================================
-- Scan scheduling
-- ============================================================
local function DoScan()
    if scanRunning then return end
    scanRunning = true
    pendingScan = nil
    -- Only scan while resting (capitals/inns) — same restriction as the original.
    -- Crafting always happens in capitals where rested XP is active, so this
    -- avoids pointless rescans in dungeons or the open world.
    if not IsResting() then
        scanRunning = false
        return
    end
    items       = BuildList()
    if CS._shopFrame then RefreshList() end
    scanRunning = false
    ShowIfNeeded()
end

local function ScheduleScan()
    if pendingScan or scanRunning then return end
    pendingScan = C_Timer.NewTimer(SCAN_DELAY, DoScan)
end

-- ============================================================
-- Aux plain frame — for events that must be dynamically
-- registered / unregistered during an AH purchase flow.
-- ============================================================
local function GetAux()
    if CS._aux then return CS._aux end
    local a = CreateFrame("Frame")
    a:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "COMMODITY_PRICE_UPDATED" then
            if pendingBuy and pendingBuy.OnPrice then
                pendingBuy.OnPrice(arg1, arg2)
            end
        elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
            a:UnregisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
            a:UnregisterEvent("AUCTION_HOUSE_SHOW_ERROR")
            a:UnregisterEvent("COMMODITY_PURCHASE_FAILED")
            local id = lastBuyID
            lastBuyID = nil
            if id then
                local purchasedItem = nil
                for _, it in ipairs(items) do
                    if it.itemID == id then purchasedItem = it; break end
                end
                -- Collect quality sisters: same name, hasAlternatives, not already hidden
                local sisterItems = {}
                if purchasedItem and purchasedItem.hasAlternatives then
                    for _, it in ipairs(items) do
                        if it ~= purchasedItem and it.hasAlternatives
                           and it.name == purchasedItem.name and not it.hidden then
                            table.insert(sisterItems, it)
                        end
                    end
                end
                purchased[id] = true
                -- Toast notification (accent colour)
                if lastPurchaseInfo then
                    local info = lastPurchaseInfo
                    local priceStr = info.total and GetMoneyString(info.total) or "?"
                    UIErrorsFrame:AddMessage(
                        info.name .. " purchased ×" .. info.need .. " for " .. priceStr,
                        SP.Theme.accent[1], SP.Theme.accent[2], SP.Theme.accent[3], 1)
                    lastPurchaseInfo = nil
                end
                -- Briefly show checkmark on bought item + all quality sisters, then hide all.
                -- ScheduleScan is deferred into the timer so BuildList doesn't replace
                -- the items table before C_Timer.After fires (which would orphan our refs).
                if purchasedItem then
                    purchasedItem.purchased = true
                    for _, it in ipairs(sisterItems) do it.purchased = true end
                    if CS._shopFrame then RefreshList() end
                    C_Timer.After(2, function()
                        purchasedItem.hidden    = true
                        purchasedItem.purchased = nil
                        for _, it in ipairs(sisterItems) do
                            it.hidden    = true
                            it.purchased = nil
                        end
                        if CS._shopFrame then RefreshList() end
                        ScheduleScan()  -- rebuild list AFTER hide so refs are still valid
                    end)
                else
                    if CS._shopFrame then RefreshList() end
                    ScheduleScan()
                end
            end
        elseif event == "COMMODITY_PURCHASE_FAILED"
            or (event == "AUCTION_HOUSE_SHOW_ERROR" and purchaseErrorCodes[arg1]) then
            lastBuyID = nil
            a:UnregisterEvent("COMMODITY_PRICE_UPDATED")
            a:UnregisterEvent("COMMODITY_PURCHASE_FAILED")
            a:UnregisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
            a:UnregisterEvent("AUCTION_HOUSE_SHOW_ERROR")
            if pendingBuy and pendingBuy.OnFail then pendingBuy.OnFail() end
        end
    end)
    CS._aux = a
    return a
end

local function UnregisterAllAux()
    if not CS._aux then return end
    CS._aux:UnregisterEvent("COMMODITY_PRICE_UPDATED")
    CS._aux:UnregisterEvent("COMMODITY_PURCHASE_FAILED")
    CS._aux:UnregisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
    CS._aux:UnregisterEvent("AUCTION_HOUSE_SHOW_ERROR")
end

-- ============================================================
-- Purchase-confirmation popup (SP-themed)
-- ============================================================
ShowBuyPopup = function(item, buyBtn)
    if pendingBuy then return end
    buyBtn:Disable()

    local T = SP.Theme

    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetSize(300, 160)
    popup:SetPoint("TOP", UIParent, "TOP", 0, -200)
    popup:SetFrameStrata("TOOLTIP")
    popup:EnableMouse(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup:SetScript("OnDragStart", popup.StartMoving)
    popup:SetScript("OnDragStop",  popup.StopMovingOrSizing)
    popup:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    popup:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.97)
    popup:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT",  popup, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, 0)
    titleBar:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    titleBar:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    titleBar:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

    local accentLine = titleBar:CreateTexture(nil, "OVERLAY")
    accentLine:SetHeight(2)
    accentLine:SetPoint("BOTTOMLEFT",  titleBar, "BOTTOMLEFT",  0, 0)
    accentLine:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    accentLine:SetTexture(BLANK)
    accentLine:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.85)

    local titleFS = titleBar:CreateFontString(nil, "OVERLAY")
    titleFS:SetFont(SP_FONT, 12, "")
    titleFS:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleFS:SetTextColor(1, 1, 1, 1)
    titleFS:SetText("|cffe51039Craft|r|cffffffffShopper|r — Confirm")

    local closeFS_str_dim  = "|cff666666×|r"
    local closeFS_str_high = "|cffffffff×|r"
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -5, 0)
    local closeFS = closeBtn:CreateFontString(nil, "OVERLAY")
    closeFS:SetFont(SP_FONT, 15, "")
    closeFS:SetText(closeFS_str_dim)
    closeFS:SetAllPoints()

    -- Body text
    local text = popup:CreateFontString(nil, "OVERLAY")
    text:SetFont(SP_FONT, 11, "")
    text:SetPoint("TOP", popup, "TOP", 0, -44)
    text:SetJustifyH("CENTER")
    text:SetTextColor(0.9, 0.9, 0.9, 1)
    text:SetText("Fetching price from server…")

    local timerFS = popup:CreateFontString(nil, "OVERLAY")
    timerFS:SetFont(SP_FONT, 10, "")
    timerFS:SetPoint("TOP", text, "BOTTOM", 0, -8)
    timerFS:SetJustifyH("CENTER")
    timerFS:SetTextColor(0.45, 0.45, 0.45, 1)

    local spinner = CreateFrame("Frame", nil, popup, "LoadingSpinnerTemplate")
    spinner:SetPoint("TOP", popup, "TOP", 0, -30)
    spinner:SetSize(20, 20)
    spinner:Show()

    -- Buy button (success green)
    local confirmBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
    confirmBtn:SetSize(130, 26)
    confirmBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 10, 12)
    confirmBtn:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    confirmBtn:SetBackdropColor(T.success[1] * 0.18, T.success[2] * 0.18, T.success[3] * 0.18, 0.9)
    confirmBtn:SetBackdropBorderColor(T.success[1], T.success[2], T.success[3], 0.55)
    local confirmFS = confirmBtn:CreateFontString(nil, "OVERLAY")
    confirmFS:SetFont(SP_FONT, 11, "")
    confirmFS:SetTextColor(T.success[1], T.success[2], T.success[3], 1)
    confirmFS:SetText("Buy Now")
    confirmFS:SetAllPoints()
    confirmFS:SetJustifyH("CENTER")
    confirmBtn:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        self:SetBackdropBorderColor(T.success[1], T.success[2], T.success[3], 1)
        self:SetBackdropColor(T.success[1] * 0.28, T.success[2] * 0.28, T.success[3] * 0.28, 0.9)
        confirmFS:SetTextColor(1, 1, 1, 1)
    end)
    confirmBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(T.success[1], T.success[2], T.success[3], 0.55)
        self:SetBackdropColor(T.success[1] * 0.18, T.success[2] * 0.18, T.success[3] * 0.18, 0.9)
        confirmFS:SetTextColor(T.success[1], T.success[2], T.success[3], 1)
    end)
    confirmBtn:Disable()
    confirmFS:SetTextColor(T.success[1], T.success[2], T.success[3], 0.35)

    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
    cancelBtn:SetSize(130, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -10, 12)
    cancelBtn:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    cancelBtn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 0.9)
    cancelBtn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.7)
    local cancelFS = cancelBtn:CreateFontString(nil, "OVERLAY")
    cancelFS:SetFont(SP_FONT, 11, "")
    cancelFS:SetTextColor(0.75, 0.75, 0.75, 1)
    cancelFS:SetText(CANCEL)
    cancelFS:SetAllPoints()
    cancelFS:SetJustifyH("CENTER")
    cancelBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(
            T.border[1] + 0.1, T.border[2] + 0.1, T.border[3] + 0.1, 1)
        cancelFS:SetTextColor(1, 1, 1, 1)
    end)
    cancelBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.7)
        cancelFS:SetTextColor(0.75, 0.75, 0.75, 1)
    end)

    closeBtn:SetScript("OnClick",  function() cancelBtn:Click() end)
    closeBtn:SetScript("OnEnter",  function() closeFS:SetText(closeFS_str_high) end)
    closeBtn:SetScript("OnLeave",  function() closeFS:SetText(closeFS_str_dim) end)

    -- 15-second countdown
    local remaining = 15
    timerFS:SetText(("Timeout: %ds"):format(remaining))
    local ticker = C_Timer.NewTicker(1, function()
        remaining = remaining - 1
        if remaining <= 0 then
            cancelBtn:Click()
        else
            timerFS:SetText(("Timeout: %ds"):format(remaining))
        end
    end)

    local confirmedTotal = nil  -- set when price arrives, read at confirm time

    -- keepPurchaseEvents=true → confirm path; keep SUCCEEDED/FAILED alive
    -- keepPurchaseEvents=nil  → cancel/timeout; unregister everything
    local function Cleanup(keepPurchaseEvents)
        ticker:Cancel()
        popup:Hide()
        pendingBuy = nil
        buyBtn:Enable()
        buyBtn._enabled = true
        if keepPurchaseEvents then
            if CS._aux then CS._aux:UnregisterEvent("COMMODITY_PRICE_UPDATED") end
        else
            UnregisterAllAux()
        end
    end

    confirmBtn:SetScript("OnClick", function()
        local aux = GetAux()
        aux:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
        aux:RegisterEvent("COMMODITY_PURCHASE_FAILED")
        aux:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
        lastBuyID = item.itemID
        lastPurchaseInfo = {
            name  = item.name or ("Item " .. item.itemID),
            need  = item.missing,
            total = confirmedTotal,
        }
        C_AuctionHouse.ConfirmCommoditiesPurchase(item.itemID, item.missing)
        Cleanup(true)  -- close popup but keep purchase result events alive
    end)

    cancelBtn:SetScript("OnClick", function()
        C_AuctionHouse.CancelCommoditiesPurchase(item.itemID)
        Cleanup()
    end)

    pendingBuy = {
        OnPrice = function(_, total)
            GetAux():UnregisterEvent("COMMODITY_PRICE_UPDATED")
            spinner:Hide()
            local money = GetMoney()
            if money < total then
                local short = GetMoneyString(total - money)
                text:SetText("|cffff4444Not enough gold!\nShort by: " .. short .. "|r")
                confirmBtn:Hide()
                cancelFS:SetText(CLOSE)
                cancelBtn:ClearAllPoints()
                cancelBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 12)
            else
                local name = item.name or ("Item " .. item.itemID)
                text:SetText(("%s |cffffffff×%d|r\n%s"):format(
                    name, item.missing, GetMoneyString(total)))
                confirmedTotal = total  -- store for toast at confirm time
                confirmBtn:Show()
                confirmBtn:Enable()
                confirmFS:SetTextColor(T.success[1], T.success[2], T.success[3], 1)
            end
        end,
        OnFail = function()
            spinner:Hide()
            text:SetText("|cffff4444Purchase failed.|r")
            timerFS:SetText("")
            confirmBtn:Hide()
            cancelFS:SetText(OKAY)
            cancelBtn:ClearAllPoints()
            cancelBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 12)
            pendingBuy = nil
            buyBtn:Enable()
        end,
    }
end

-- ============================================================
-- Compact text-button helper (action buttons in rows)
--   r, g, b  — button accent colour
--   tooltip  — optional GameTooltip text
-- ============================================================
local function MakeTextBtn(parent, label, r, g, b, tooltip)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    btn:SetBackdropColor(r * 0.12, g * 0.12, b * 0.12, 0.85)
    btn:SetBackdropBorderColor(r, g, b, 0.45)

    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetFont(SP_FONT, 9, "")
    fs:SetText(label)
    fs:SetTextColor(r, g, b, 1)
    fs:SetAllPoints()
    fs:SetJustifyH("CENTER")
    btn._fs = fs
    btn._r, btn._g, btn._b = r, g, b

    btn:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        self:SetBackdropBorderColor(r, g, b, 0.95)
        self:SetBackdropColor(r * 0.24, g * 0.24, b * 0.24, 0.95)
        fs:SetTextColor(1, 1, 1, 1)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function(self)
        local enabled = self:IsEnabled()
        self:SetBackdropBorderColor(r, g, b, enabled and 0.45 or 0.18)
        self:SetBackdropColor(r * 0.12, g * 0.12, b * 0.12, enabled and 0.85 or 0.35)
        fs:SetTextColor(r, g, b, enabled and 1 or 0.35)
        if tooltip then GameTooltip:Hide() end
    end)

    return btn
end

-- Visual helper: apply enabled/disabled look to a MakeTextBtn button
local function SetBtnEnabled(btn, enabled)
    local r, g, b = btn._r, btn._g, btn._b
    if enabled then
        btn:Enable()
        btn:SetBackdropBorderColor(r, g, b, 0.45)
        btn:SetBackdropColor(r * 0.12, g * 0.12, b * 0.12, 0.85)
        btn._fs:SetTextColor(r, g, b, 1)
    else
        btn:Disable()
        btn:SetBackdropBorderColor(r, g, b, 0.18)
        btn:SetBackdropColor(r * 0.12, g * 0.12, b * 0.12, 0.35)
        btn._fs:SetTextColor(r, g, b, 0.35)
    end
end

-- ============================================================
-- Row pool (frames are never GC'd — reuse with Hide/Show)
-- ============================================================
local rowPool = {}

local function GetRow(idx, content)
    local row = rowPool[idx]
    if row then
        row:ClearAllPoints()
        row:SetParent(content)
        return row
    end

    local T = SP.Theme

    row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_H)

    -- Tiny item icon (left edge)
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ROW_H - 4, ROW_H - 4)
    icon:SetPoint("LEFT", row, "LEFT", 3, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim default icon border
    row.icon = icon

    -- Item name
    local nameFS = row:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(SP_FONT, 10, "OUTLINE")
    nameFS:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    nameFS:SetWidth(128)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    row.nameFS = nameFS

    -- Quantity needed (accent colour, slightly bold via OUTLINE)
    local qtyFS = row:CreateFontString(nil, "OVERLAY")
    qtyFS:SetFont(SP_FONT, 10, "OUTLINE")
    qtyFS:SetPoint("LEFT", row, "LEFT", 163, 0)
    qtyFS:SetWidth(78)
    qtyFS:SetJustifyH("LEFT")
    qtyFS:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    row.qtyFS = qtyFS

    -- [Buy] — quick buy from AH  (success / green)
    --   right edge = row.RIGHT - 2 (matches left padding)
    local bBtn = MakeTextBtn(row, "Buy",
        T.success[1], T.success[2], T.success[3], "Quick-buy from Auction House")
    bBtn:SetSize(28, ROW_H - 6)
    bBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.buyBtn = bBtn

    -- [Search] — search on Auction House  (accent)
    --   left of Buy: -2 - 28 - 4 = -34
    local sBtn = MakeTextBtn(row, "Search",
        T.accent[1], T.accent[2], T.accent[3], "Search on Auction House")
    sBtn:SetSize(44, ROW_H - 6)
    sBtn:SetPoint("RIGHT", row, "RIGHT", -34, 0)
    row.sBtn = sBtn

    -- Alternate-row tint background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(BLANK)
    bg:SetVertexColor(1, 1, 1, 0)
    row.altBg = bg

    -- Subtle separator at the row bottom
    local sep = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetTexture(BLANK)
    sep:SetVertexColor(T.border[1], T.border[2], T.border[3], 0.4)

    -- Hover tooltip (full item tooltip on name/icon area)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    rowPool[idx] = row
    return row
end

-- ============================================================
-- Shopping-list frame (SP-themed, custom scrollbar)
-- ============================================================
local function MakeShopFrame()
    if CS._shopFrame then return CS._shopFrame end

    local T = SP.Theme
    -- Content width: panel minus left pad, scrollbar, gap, right pad
    local CONTENT_W = SHOP_W - 6 - SCROLL_W - 4 - 6

    local f = CreateFrame("Frame", "SP_CraftShopperFrame", UIParent, "BackdropTemplate")
    f:SetWidth(SHOP_W)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:Hide()
    f:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    f:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.90)
    f:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

    -- Draggable via title bar
    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)

    -- ── Title bar ─────────────────────────────────────────────────────────────
    local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    titleBar:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    titleBar:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

    -- Thin accent line under title bar
    local accentLine = titleBar:CreateTexture(nil, "OVERLAY")
    accentLine:SetHeight(2)
    accentLine:SetPoint("BOTTOMLEFT",  titleBar, "BOTTOMLEFT",  0, 0)
    accentLine:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    accentLine:SetTexture(BLANK)
    accentLine:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.85)

    -- SP Logo — overflows the top-left corner (same style as GUI)
    local logo = CreateFrame("Frame", nil, f)
    logo:SetSize(44, 44)
    logo:SetPoint("TOPLEFT", f, "TOPLEFT", -11, 11)
    logo:SetFrameLevel(f:GetFrameLevel() + 2)
    local logoTex = logo:CreateTexture(nil, "ARTWORK")
    logoTex:SetAllPoints()
    logoTex:SetTexture("Interface\\AddOns\\SuspicionsPack\\Media\\Icons\\icon128x128.png")
    logoTex:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.9)

    local titleFS = titleBar:CreateFontString(nil, "OVERLAY")
    titleFS:SetFont(SP_FONT, 13, "OUTLINE")
    titleFS:SetPoint("LEFT", titleBar, "LEFT", 35, 0)
    local _accentHex = string.format("%02x%02x%02x",
        math.floor(T.accent[1] * 255),
        math.floor(T.accent[2] * 255),
        math.floor(T.accent[3] * 255))
    titleFS:SetText("|cff".._accentHex.."Craft|r|cffffffffShopper|r")

    -- ── Search / filter bar ───────────────────────────────────────────────────
    local searchBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    searchBg:SetHeight(24)
    searchBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  6, -32)
    searchBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -32)
    searchBg:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    searchBg:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 0.7)
    searchBg:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.7)

    local searchLabel = searchBg:CreateFontString(nil, "OVERLAY")
    searchLabel:SetFont(SP_FONT, 9, "")
    searchLabel:SetTextColor(0.45, 0.45, 0.45, 1)
    searchLabel:SetPoint("LEFT", searchBg, "LEFT", 6, 0)
    searchLabel:SetText("Filter:")

    local searchBox = CreateFrame("EditBox", "SP_CraftShopperSearch", searchBg)
    searchBox:SetFont(SP_FONT, 10, "")
    searchBox:SetTextColor(0.9, 0.9, 0.9, 1)
    searchBox:SetHeight(20)
    searchBox:SetPoint("LEFT",  searchBg, "LEFT",  44, 0)
    searchBox:SetPoint("RIGHT", searchBg, "RIGHT", -4, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function()
        if CS._shopFrame then RefreshList() end
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- ── Scroll area ───────────────────────────────────────────────────────────
    -- ScrollFrame clips to visible area; the custom scrollbar is separate.
    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     6, -60)
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(6 + SCROLL_W + 4), 24)
    sf:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, sf)
    content:SetWidth(CONTENT_W)
    content:SetHeight(1)
    sf:SetScrollChild(content)

    f.searchBox = searchBox
    f.content   = content
    f.sf        = sf

    -- ── Custom thin scrollbar ─────────────────────────────────────────────────
    local sbTrack = CreateFrame("Frame", nil, f, "BackdropTemplate")
    sbTrack:SetWidth(SCROLL_W)
    sbTrack:SetPoint("TOPRIGHT",    f, "TOPRIGHT",    -6, -60)
    sbTrack:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6,  24)
    sbTrack:SetBackdrop({ bgFile = BLANK })
    sbTrack:SetBackdropColor(T.bgLight[1], T.bgLight[2], T.bgLight[3], 0.12)
    f.sbTrack = sbTrack

    local sbThumb = CreateFrame("Frame", nil, sbTrack, "BackdropTemplate")
    sbThumb:SetWidth(SCROLL_W)
    sbThumb:SetBackdrop({ bgFile = BLANK })
    sbThumb:SetBackdropColor(T.accent[1], T.accent[2], T.accent[3], 0.45)
    sbThumb:SetPoint("TOPLEFT", sbTrack, "TOPLEFT", 0, 0)
    sbThumb:SetHeight(30)
    sbThumb:Hide()
    f.sbThumb = sbThumb

    -- ── Footer ────────────────────────────────────────────────────────────────
    local footer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    footer:SetHeight(18)
    footer:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    footer:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    footer:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    footer:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

    local footerLbl = footer:CreateFontString(nil, "OVERLAY")
    footerLbl:SetFont(SP_FONT, 9, "")
    footerLbl:SetPoint("LEFT", footer, "LEFT", 8, 0)
    footerLbl:SetText("Suspicion's Pack  ·  CraftShopper")
    footerLbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.6)

    local function UpdateScrollbar()
        local contentH = content:GetHeight()
        local areaH    = sf:GetHeight()
        if contentH <= areaH then
            sbThumb:Hide()
            return
        end
        sbThumb:Show()
        local trackH    = sbTrack:GetHeight()
        local ratio     = areaH / contentH
        local thumbH    = math.max(ratio * trackH, 20)
        local scrollMax = sf:GetVerticalScrollRange()
        local scrollCur = sf:GetVerticalScroll()
        local frac      = scrollMax > 0 and scrollCur / scrollMax or 0
        sbThumb:SetHeight(thumbH)
        sbThumb:ClearAllPoints()
        sbThumb:SetPoint("TOPLEFT", sbTrack, "TOPLEFT", 0,
            -(frac * (trackH - thumbH)))
    end
    f.UpdateScrollbar = UpdateScrollbar

    local function OnWheel(_, delta)
        local cur = sf:GetVerticalScroll()
        local max = sf:GetVerticalScrollRange()
        sf:SetVerticalScroll(math.max(0, math.min(max, cur - delta * (ROW_H * 3))))
        UpdateScrollbar()
    end
    f:SetScript("OnMouseWheel", OnWheel)
    sf:SetScript("OnMouseWheel", OnWheel)

    CS._shopFrame = f
    return f
end

-- ============================================================
-- Refresh the list of rows inside the shop panel
-- ============================================================
-- Quality icon markup is resolved dynamically via C_TradeSkillUI.GetItemReagentQualityInfo(itemID)
-- so it works correctly regardless of how many tiers the current expansion uses.
local function GetReagentQualityIconMarkup(itemID)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetItemReagentQualityInfo then return "" end
    local qualityInfo = C_TradeSkillUI.GetItemReagentQualityInfo(itemID)
    if not qualityInfo or not qualityInfo.iconSmall then return "" end
    return CreateAtlasMarkup(qualityInfo.iconSmall, 20, 20)
end

RefreshList = function()
    local f = CS._shopFrame
    if not f or not f:IsShown() then return end

    local T          = SP.Theme
    local content    = f.content
    local searchText = (f.searchBox:GetText() or ""):lower()

    -- Resolve names for all items first (needed for sort)
    for _, item in ipairs(items) do
        if not item.name then
            item.name = C_Item.GetItemInfo(item.itemID) or ("item:" .. item.itemID)
        end
    end

    -- Sort: group by base name so quality alternatives appear adjacent,
    -- then by quality rank ascending within the same name.
    table.sort(items, function(a, b)
        local na = a.name or ""
        local nb = b.name or ""
        if na ~= nb then return na < nb end
        return (a.qualityRank or 0) < (b.qualityRank or 0)
    end)

    -- Hide all pooled rows
    for _, r in ipairs(rowPool) do r:Hide() end

    local idx = 0
    local y   = 0
    local ahOpen = AuctionHouseFrame and AuctionHouseFrame:IsShown()

    for _, item in ipairs(items) do
        if not item.hidden then
            local name = item.name

            if searchText == "" or name:lower():find(searchText, 1, true) then
                idx = idx + 1
                local row = GetRow(idx, content)
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                row:SetWidth(content:GetWidth())
                row:Show()
                row.itemID = item.itemID

                -- Alternate row shading
                row.altBg:SetVertexColor(1, 1, 1, idx % 2 == 0 and 0.04 or 0)

                -- Item icon
                local _, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(item.itemID)
                if texture then
                    row.icon:SetTexture(texture)
                    row.icon:Show()
                else
                    row.icon:Hide()
                end

                -- Name with quality colour
                local color = quality and select(4, C_Item.GetItemQualityColor(quality)) or "ffffffff"
                row.nameFS:SetText(("|c%s%s|r"):format(color, name))

                -- Quantity: "qty : bag/total" with optional quality rank badge
                -- when this reagent has quality alternatives for its slot.
                local qtyText = "|cff888888qty :|r " .. tostring(item.bagCount) .. "|cff888888/|r" .. tostring(item.qtyNeeded)
                if item.hasAlternatives then
                    local iconMarkup = GetReagentQualityIconMarkup(item.itemID)
                    if iconMarkup ~= "" then
                        qtyText = iconMarkup .. " " .. qtyText
                    end
                end
                -- Checkmark after purchase (WoW texture — Expressway has no unicode glyphs)
                if item.purchased then
                    row.qtyFS:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t")
                    row.qtyFS:SetTextColor(1, 1, 1, 1)
                else
                    row.qtyFS:SetText(qtyText)
                    row.qtyFS:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
                end

                -- Wire Search-AH button
                local capturedItem = item
                SetBtnEnabled(row.sBtn, true)
                row.sBtn:SetScript("OnClick", function()
                    local n, _, q, _, _, _, _, _, equip, _, _, cid, scid =
                        C_Item.GetItemInfo(capturedItem.itemID)
                    if not n then return end
                    local filters = { Enum.AuctionHouseFilter.ExactMatch }
                    if mapQuality[q] then table.insert(filters, 1, mapQuality[q]) end
                    C_AuctionHouse.SendBrowseQuery({
                        searchString = n,
                        sorts = {
                            { sortOrder = Enum.AuctionHouseSortOrder.Name,  reverseSort = false },
                            { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
                        },
                        filters = filters,
                        itemClassFilters = { classID = cid, subClassID = scid, inventoryType = equip },
                    })
                    if AuctionHouseFrame then
                        AuctionHouseFrame:Show()
                        AuctionHouseFrame:Raise()
                    end
                end)

                -- Wire Quick-Buy button
                SetBtnEnabled(row.buyBtn, item.ahBuyable and ahOpen and not pendingBuy)
                row.buyBtn:SetScript("OnClick", function()
                    if pendingBuy then return end
                    local aux = GetAux()
                    aux:RegisterEvent("COMMODITY_PRICE_UPDATED")
                    aux:RegisterEvent("COMMODITY_PURCHASE_FAILED")
                    aux:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
                    ShowBuyPopup(capturedItem, row.buyBtn)
                    C_AuctionHouse.StartCommoditiesPurchase(capturedItem.itemID, capturedItem.missing)
                end)

                y = y + ROW_H
            end
        end
    end

    -- "Nothing needed" placeholder when list is empty
    if idx == 0 then
        local row = GetRow(1, content)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        row:SetWidth(content:GetWidth())
        row:Show()
        row.itemID = nil
        row.icon:Hide()
        row.nameFS:SetText("|cff444444No items needed|r")
        row.qtyFS:SetText("")
        row.sBtn:SetScript("OnClick",   nil)
        row.buyBtn:SetScript("OnClick", nil)
        SetBtnEnabled(row.sBtn,   false)
        SetBtnEnabled(row.buyBtn, false)
        y = ROW_H
    end

    content:SetHeight(math.max(y, 1))
    if f.UpdateScrollbar then f.UpdateScrollbar() end
end

-- ============================================================
-- Show (or hide) the panel anchored next to the AH frame
-- ============================================================
ShowIfNeeded = function()
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return end

    local hasItems = false
    for _, item in ipairs(items) do
        if item.ahBuyable and item.missing > 0 and not item.hidden then
            hasItems = true; break
        end
    end

    if hasItems then
        local f = MakeShopFrame()
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT",    AuctionHouseFrame, "TOPRIGHT",    5, 0)
        f:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", 5, 0)
        f:SetWidth(math.max(SHOP_W, AuctionHouseFrame:GetWidth() * 0.4))
        f:Show()
        RefreshList()
    else
        if CS._shopFrame then CS._shopFrame:Hide() end
        UnregisterAllAux()
    end
end

-- ============================================================
-- Heavy-event set (registered only while recipes are tracked)
-- ============================================================
local HEAVY = {
    "BAG_UPDATE_DELAYED",
    "CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
}
local heavyOn = false

local function RegisterHeavy()
    if heavyOn then return end
    heavyOn = true
    for _, ev in ipairs(HEAVY) do CS:RegisterEvent(ev) end
end

local function UnregisterHeavy()
    if not heavyOn then return end
    heavyOn = false
    for _, ev in ipairs(HEAVY) do CS:UnregisterEvent(ev) end
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function CS:OnEnable()
    if IsLoggedIn() then
        self:OnLogin()
    else
        self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
    end
    self:RegisterEvent("TRACKED_RECIPE_UPDATE", "OnTrackedRecipeUpdate")
    -- Clear per-item caches on logout so stale tooltip/schematic data
    -- doesn't persist across sessions (e.g. after a patch changes item flags).
    self:RegisterEvent("PLAYER_LOGOUT", "OnLogout")
end

function CS:OnLogout()
    wipe(ahCache)
    wipe(schemCache)
    wipe(schemRecraft)
end

function CS:OnDisable()
    self:UnregisterAllEvents()
    UnregisterHeavy()
    UnregisterAllAux()
    if pendingScan then pendingScan:Cancel(); pendingScan = nil end
    if CS._shopFrame then CS._shopFrame:Hide() end
end

function CS:OnLogin()
    self:UnregisterEvent("PLAYER_LOGIN")
    if not IsEnabled() then return end
    if HasTracked() then
        RegisterHeavy()
        DoScan()
    end
end

-- ============================================================
-- AceEvent handlers
-- ============================================================
function CS:OnTrackedRecipeUpdate()
    if not IsEnabled() then return end
    if HasTracked() then
        RegisterHeavy()
        ScheduleScan()
    else
        UnregisterHeavy()
        if pendingScan then pendingScan:Cancel(); pendingScan = nil end
        if CS._shopFrame then CS._shopFrame:Hide() end
    end
end

function CS:BAG_UPDATE_DELAYED()
    ScheduleScan()
end

function CS:CRAFTINGORDERS_ORDER_PLACEMENT_RESPONSE(_, result)
    if result == 0 and not scanRunning then DoScan() end
end

function CS:AUCTION_HOUSE_SHOW()
    if not IsEnabled() then return end
    DoScan()
    ShowIfNeeded()
end

function CS:AUCTION_HOUSE_CLOSED()
    if CS._shopFrame then CS._shopFrame:Hide() end
    UnregisterAllAux()
end

-- ============================================================
-- Called by GUI enable toggle
-- ============================================================
function CS.Refresh()
    local db  = GetDB()
    local mod = SP.CraftShopper
    if db and db.enabled then
        if not mod:IsEnabled() then mod:Enable() end
    else
        if mod:IsEnabled() then mod:Disable() end
    end
end

-- Called by SP.RefreshTheme() so accent-colored elements rebuild with new colors.
function CS.RebuildShopFrame()
    if CS._shopFrame then
        CS._shopFrame:Hide()
        CS._shopFrame:SetParent(nil)
        CS._shopFrame = nil
        rowPool = {}  -- row frames reference old parent; must be recreated too
    end
    -- If the AH is already open, recreate and show immediately —
    -- AUCTION_HOUSE_SHOW won't fire again for an already-open AH.
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
        ShowIfNeeded()
    end
end
