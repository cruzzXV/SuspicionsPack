-- SuspicionsPack — AutoBuy Module
-- Vendor flow : silent, instant, on MERCHANT_SHOW.
-- AH flow     : scan bags → show list panel with per-item Buy buttons,
--               mirroring CraftShopper's UI exactly.
local SP = SuspicionsPack

local AutoBuy = SP:NewModule("AutoBuy", "AceEvent-3.0")
SP.AutoBuy = AutoBuy

-- ============================================================
-- Preset items
-- ============================================================
AutoBuy.PresetItems = {
    -- ── Flasks ──────────────────────────────────────────────────────────
    { id = 241322, q2 = 241323, buy = 10, cat = "flask",        name = "Flask of the Magisters" },
    { id = 241324, q2 = 241325, buy = 10, cat = "flask",        name = "Flask of the Blood Knights" },
    { id = 241326, q2 = 241327, buy = 10, cat = "flask",        name = "Flask of the Shattered Sun" },
    { id = 241320, q2 = 241321, buy = 10, cat = "flask",        name = "Flask of Thalassian Resistance" },

    -- ── Health/Mana Potions ──────────────────────────────────────────────
    { id = 241304, q2 = 241305, buy = 20, cat = "healthpotion", name = "Silvermoon Health Potion" },
    { id = 241300, q2 = 241301, buy = 20, cat = "healthpotion", name = "Lightfused Mana Potion" },
    { id = 241298, q2 = 241299, buy = 10, cat = "healthpotion", name = "Amani Extract" },
    { id = 241286, q2 = 241287, buy = 10, cat = "healthpotion", name = "Light's Preservation" },

    -- ── Combat Potions ───────────────────────────────────────────────────
    { id = 241308, q2 = 241309, buy = 10, cat = "combatpotion", name = "Light's Potential" },
    { id = 241302, q2 = 241303, buy = 10, cat = "combatpotion", name = "Void-Shrouded Tincture" },
    { id = 241288, q2 = 241289, buy = 10, cat = "combatpotion", name = "Potion of Recklessness" },
    { id = 241292, q2 = 241293, buy = 10, cat = "combatpotion", name = "Draught of Rampant Abandon" },
    { id = 241294, q2 = 241295, buy = 10, cat = "combatpotion", name = "Potion of Devoured Dreams" },
    { id = 241296, q2 = 241297, buy = 10, cat = "combatpotion", name = "Potion of Zealotry" },
    { id = 241338, q2 = 241339, buy = 10, cat = "combatpotion", name = "Enlightenment Tonic" },

    -- ── Augment Runes ────────────────────────────────────────────────────
    { id = 259085,              buy = 20, cat = "rune",         name = "Void-Touched Augment Rune" },

    -- ── Weapon Oils ──────────────────────────────────────────────────────
    { id = 243733, q2 = 243734, buy = 10, cat = "oil",         name = "Thalassian Phoenix Oil" },
    { id = 243735, q2 = 243736, buy = 10, cat = "oil",         name = "Oil of Dawn" },
    { id = 243737, q2 = 243738, buy = 10, cat = "oil",         name = "Smuggler's Enchanted Edge" },

    -- ── Individual Food ──────────────────────────────────────────────────
    { id = 242274,              buy = 20, cat = "food",        name = "Champion's Bento" },
    { id = 242275,              buy = 20, cat = "food",        name = "Royal Roast" },

    -- ── Raid Feasts ──────────────────────────────────────────────────────
    { id = 255845,              buy = 5,  cat = "food",        name = "Silvermoon Parade" },
    { id = 255846,              buy = 5,  cat = "food",        name = "Harandar Celebration" },
    { id = 242272,              buy = 5,  cat = "food",        name = "Quel'dorei Medley" },
    { id = 242273,              buy = 5,  cat = "food",        name = "Blooming Feast" },
}

-- ============================================================
-- Constants  (mirror CraftShopper)
-- ============================================================
local BLANK    = "Interface\\Buttons\\WHITE8X8"
local FONT     = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"
local ROW_H  = 24
local SHOP_W = 340

-- ============================================================
-- Helpers
-- ============================================================
local function GetDB()
    return SP.GetCharDB().autoBuy
end

local function GetReagentQualityIconMarkup(itemID)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetItemReagentQualityInfo then return "" end
    local qualityInfo = C_TradeSkillUI.GetItemReagentQualityInfo(itemID)
    if not qualityInfo or not qualityInfo.iconSmall then return "" end
    return CreateAtlasMarkup(qualityInfo.iconSmall, 28, 28)
end

local function GetBagCount(id)
    local count = 0
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == id then
                count = count + (info.stackCount or 1)
            end
        end
    end
    return count
end

local function ResolveItemID(preset, entry)
    -- Fully explicit: use Q2 id only when quality is exactly 2
    if preset.q2 and entry and entry.quality == 2 then
        return preset.q2
    end
    return preset.id
end

-- minQty: trigger threshold — only buy if bags are below this.
-- buyQty: purchase amount — how many to actually buy when triggered.
local function DoBuy(id, minQty, buyQty)
    local have = GetBagCount(id)
    if have >= minQty then return end
    local need = buyQty
    if need <= 0 then return end
    local numItems = GetMerchantNumItems()
    for i = 1, numItems do
        if GetMerchantItemID(i) == id then
            local _, _, _, _, _, _, maxStack = GetMerchantItemInfo(i)
            maxStack = maxStack or 1
            while need > 0 do
                local toBuy = math.min(maxStack, need)
                BuyMerchantItem(i, toBuy)
                need = need - toBuy
            end
            return
        end
    end
end

-- Returns [{ itemID, need, have, target, name }]
-- need   = buyQty (how many to purchase)
-- target = minQty (trigger threshold shown in the UI)
local function BuildBuyList()
    local db  = GetDB()
    local out = {}
    for _, item in ipairs(AutoBuy.PresetItems) do
        local entry = db.items and db.items[item.id]
        if entry and entry.enabled then
            local buyID  = ResolveItemID(item, entry)
            local minQty = entry.quantity or item.buy   -- trigger threshold
            local buyQty = entry.buyQty   or item.buy   -- purchase amount
            local have   = GetBagCount(buyID)
            -- buyQty=0 means "fill to threshold" — buy exactly the deficit
            if buyQty == 0 then buyQty = minQty - have end
            if have < minQty then
                -- Prefer the live game name (reflects actual quality tier) over preset fallback
                local name = GetItemInfo(buyID) or item.name or ("Item " .. buyID)
                -- qualityTier: 1 = base, 2 = higher tier (nil when no q2 variant exists)
                local qualityTier = item.q2 and (entry.quality or 2) or nil
                table.insert(out, { itemID = buyID, need = buyQty, have = have, target = minQty, name = name, qualityTier = qualityTier })
            end
        end
    end
    return out
end

-- ============================================================
-- State
-- ============================================================
local items            = {}    -- current buy list (same shape as BuildBuyList output + .hidden)
local pendingBuy       = nil   -- active commodity purchase (pricing or confirm waiting)
local lastBuyID        = nil   -- itemID being purchased right now
local lastPurchaseInfo = nil   -- { name, need, total } stored at confirm time for the toast

local purchaseErrorCodes = {
    [Enum.AuctionHouseError.NotEnoughMoney] = true,
    [Enum.AuctionHouseError.ItemNotFound]   = true,
}

-- Forward declarations
local RefreshList
local ShowIfNeeded

-- ============================================================
-- Aux raw event frame  (identical pattern to CraftShopper)
-- ============================================================
local function GetAux()
    if AutoBuy._aux then return AutoBuy._aux end
    local a = CreateFrame("Frame")
    a:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "COMMODITY_PRICE_UPDATED" then
            if pendingBuy and pendingBuy.OnPrice then
                -- Wrap in pcall: a nil-total Lua error here would leave the popup frozen
                local ok, err = pcall(pendingBuy.OnPrice, arg1, arg2)
                if not ok then
                    -- Error in OnPrice → treat as failure so the popup recovers
                    if pendingBuy and pendingBuy.OnFail then pendingBuy.OnFail() end
                end
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
                    if it.itemID == id then
                        purchasedItem = it
                        it.have      = it.have + it.need  -- optimistic update for display
                        it.purchased = true
                        break
                    end
                end
                -- Toast notification
                if lastPurchaseInfo then
                    local info = lastPurchaseInfo
                    local priceStr = info.total and GetMoneyString(info.total) or "?"
                    UIErrorsFrame:AddMessage(
                        info.name .. " purchased ×" .. info.need .. " for " .. priceStr,
                        SP.Theme.accent[1], SP.Theme.accent[2], SP.Theme.accent[3], 1)
                    lastPurchaseInfo = nil
                end
                -- Show green qty briefly, then hide the row
                if AutoBuy._listFrame then RefreshList() end
                if purchasedItem then
                    C_Timer.After(2, function()
                        purchasedItem.hidden    = true
                        purchasedItem.purchased = nil
                        if AutoBuy._listFrame then RefreshList() end
                    end)
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
    AutoBuy._aux = a
    return a
end

local function UnregisterAllAux()
    if not AutoBuy._aux then return end
    AutoBuy._aux:UnregisterEvent("COMMODITY_PRICE_UPDATED")
    AutoBuy._aux:UnregisterEvent("COMMODITY_PURCHASE_FAILED")
    AutoBuy._aux:UnregisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
    AutoBuy._aux:UnregisterEvent("AUCTION_HOUSE_SHOW_ERROR")
end

-- ============================================================
-- Per-item confirm popup  (mirrors CraftShopper's ShowBuyPopup)
-- ============================================================
local function ShowBuyPopup(item, buyBtn)
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

    local _accentHex = string.format("%02x%02x%02x",
        math.floor(T.accent[1] * 255),
        math.floor(T.accent[2] * 255),
        math.floor(T.accent[3] * 255))

    local titleFS = titleBar:CreateFontString(nil, "OVERLAY")
    titleFS:SetFont(FONT, 12, "")
    titleFS:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleFS:SetTextColor(1, 1, 1, 1)
    titleFS:SetText("|cff".._accentHex.."Auto|r|cffffffffBuy|r — Confirm")

    local closeFS_dim  = "|cff666666×|r"
    local closeFS_high = "|cffffffff×|r"
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -5, 0)
    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY")
    closeTxt:SetFont(FONT, 15, "")
    closeTxt:SetText(closeFS_dim)
    closeTxt:SetAllPoints()

    -- Body
    local bodyText = popup:CreateFontString(nil, "OVERLAY")
    bodyText:SetFont(FONT, 11, "")
    bodyText:SetPoint("TOP", popup, "TOP", 0, -44)
    bodyText:SetJustifyH("CENTER")
    bodyText:SetTextColor(0.9, 0.9, 0.9, 1)
    bodyText:SetText("Fetching price from server…")

    local timerFS = popup:CreateFontString(nil, "OVERLAY")
    timerFS:SetFont(FONT, 10, "")
    timerFS:SetPoint("TOP", bodyText, "BOTTOM", 0, -8)
    timerFS:SetJustifyH("CENTER")
    timerFS:SetTextColor(0.45, 0.45, 0.45, 1)

    local spinner = CreateFrame("Frame", nil, popup, "LoadingSpinnerTemplate")
    spinner:SetPoint("TOP", popup, "TOP", 0, -30)
    spinner:SetSize(20, 20)
    spinner:Show()

    -- Buy Now (success green)
    local confirmBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
    confirmBtn:SetSize(130, 26)
    confirmBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 10, 12)
    confirmBtn:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    confirmBtn:SetBackdropColor(T.success[1] * 0.18, T.success[2] * 0.18, T.success[3] * 0.18, 0.9)
    confirmBtn:SetBackdropBorderColor(T.success[1], T.success[2], T.success[3], 0.55)
    local confirmFS = confirmBtn:CreateFontString(nil, "OVERLAY")
    confirmFS:SetFont(FONT, 11, "")
    confirmFS:SetTextColor(T.success[1], T.success[2], T.success[3], 0.35)
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

    -- Cancel
    local cancelBtn = CreateFrame("Button", nil, popup, "BackdropTemplate")
    cancelBtn:SetSize(130, 26)
    cancelBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -10, 12)
    cancelBtn:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    cancelBtn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 0.9)
    cancelBtn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.7)
    local cancelFS = cancelBtn:CreateFontString(nil, "OVERLAY")
    cancelFS:SetFont(FONT, 11, "")
    cancelFS:SetTextColor(0.75, 0.75, 0.75, 1)
    cancelFS:SetText(CANCEL)
    cancelFS:SetAllPoints()
    cancelFS:SetJustifyH("CENTER")
    cancelBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(T.border[1]+0.1, T.border[2]+0.1, T.border[3]+0.1, 1)
        cancelFS:SetTextColor(1, 1, 1, 1)
    end)
    cancelBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.7)
        cancelFS:SetTextColor(0.75, 0.75, 0.75, 1)
    end)

    closeBtn:SetScript("OnClick",  function() cancelBtn:Click() end)
    closeBtn:SetScript("OnEnter",  function() closeTxt:SetText(closeFS_high) end)
    closeBtn:SetScript("OnLeave",  function() closeTxt:SetText(closeFS_dim) end)

    -- 15-second countdown (same as CraftShopper)
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

    -- keepPurchaseEvents=true → called from confirm path; keep SUCCEEDED/FAILED registered
    -- keepPurchaseEvents=nil  → called from cancel/timeout; unregister everything
    local function Cleanup(keepPurchaseEvents)
        ticker:Cancel()
        popup:Hide()
        pendingBuy = nil
        buyBtn:Enable()
        if keepPurchaseEvents then
            -- Only drop the pricing event; result events must stay alive
            if AutoBuy._aux then
                AutoBuy._aux:UnregisterEvent("COMMODITY_PRICE_UPDATED")
            end
        else
            UnregisterAllAux()
        end
        -- refresh so other buy buttons re-enable
        if AutoBuy._listFrame then RefreshList() end
    end

    confirmBtn:SetScript("OnClick", function()
        local aux = GetAux()
        aux:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
        aux:RegisterEvent("COMMODITY_PURCHASE_FAILED")
        aux:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
        lastBuyID = item.itemID
        lastPurchaseInfo = {
            name  = item.name or ("Item " .. item.itemID),
            need  = item.need,
            total = confirmedTotal,
        }
        C_AuctionHouse.ConfirmCommoditiesPurchase(item.itemID, item.need)
        Cleanup(true)  -- close popup but keep purchase result events alive
    end)

    cancelBtn:SetScript("OnClick", function()
        -- Guard: CancelCommoditiesPurchase errors if the AH is already closed
        if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
            C_AuctionHouse.CancelCommoditiesPurchase()
        end
        Cleanup()
    end)

    pendingBuy = {
        Cleanup = Cleanup,   -- exposed so OnAuctionHouseClosed can cancel gracefully
        OnPrice = function(_, total)
            -- COMMODITY_PRICE_UPDATED fires as (unitPrice, totalPrice).
            -- arg1 = unit price (ignored), arg2 = total price → captured as 'total'.
            GetAux():UnregisterEvent("COMMODITY_PRICE_UPDATED")
            spinner:Hide()
            if not total or total == 0 then
                -- No price = item not listed on AH
                bodyText:SetText("|cffff8800Not listed on AH|r")
                timerFS:SetText("No current listings found")
                ticker:Cancel()
                confirmBtn:Hide()
                cancelFS:SetText(CLOSE)
                cancelBtn:ClearAllPoints()
                cancelBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 12)
                pendingBuy = nil
                buyBtn:Enable()
                return
            end
            local money = GetMoney()
            if money < total then
                local short = GetMoneyString(total - money)
                bodyText:SetText("|cffff4444Not enough gold!\nShort by: " .. short .. "|r")
                confirmBtn:Hide()
                cancelFS:SetText(CLOSE)
                cancelBtn:ClearAllPoints()
                cancelBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 12)
            else
                local name        = item.name or ("Item " .. item.itemID)
                local qualityIcon = GetReagentQualityIconMarkup(item.itemID)
                if qualityIcon ~= "" then name = name .. " " .. qualityIcon end
                bodyText:SetText(("%s |cffffffff×%d|r\n%s"):format(
                    name, item.need, GetMoneyString(total)))
                confirmedTotal = total
                confirmBtn:Show()
                confirmBtn:Enable()
                confirmFS:SetTextColor(T.success[1], T.success[2], T.success[3], 1)
            end
        end,
        OnFail = function()
            spinner:Hide()
            bodyText:SetText("|cffff4444Purchase failed.|r")
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
-- MakeTextBtn  (identical to CraftShopper)
-- ============================================================
local function MakeTextBtn(parent, label, r, g, b, tooltip)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    btn:SetBackdropColor(r * 0.12, g * 0.12, b * 0.12, 0.85)
    btn:SetBackdropBorderColor(r, g, b, 0.45)

    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, 9, "")
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
-- Row pool  (same approach as CraftShopper, Buy button only)
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

    -- [Buy] button — declared first so everything else anchors to it
    local bBtn = MakeTextBtn(row, "Buy",
        T.success[1], T.success[2], T.success[3], "Buy from the Auction House")
    bBtn:SetSize(38, ROW_H - 6)
    bBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.buyBtn = bBtn

    -- Quality icon — fixed frame just left of Buy, independent of name length
    local qualIconFrame = CreateFrame("Frame", nil, row)
    qualIconFrame:SetSize(28, 28)
    qualIconFrame:SetPoint("RIGHT", bBtn, "LEFT", -6, 0)
    qualIconFrame:Hide()
    local qualIconTex = qualIconFrame:CreateTexture(nil, "ARTWORK")
    qualIconTex:SetAllPoints()
    row.qualIconFrame = qualIconFrame
    row.qualIconTex   = qualIconTex

    -- Quantity: N/M — right-aligned, just left of quality icon
    local qtyFS = row:CreateFontString(nil, "OVERLAY")
    qtyFS:SetFont(FONT, 10, "OUTLINE")
    qtyFS:SetPoint("RIGHT", qualIconFrame, "LEFT", -4, 0)
    qtyFS:SetWidth(52)
    qtyFS:SetJustifyH("RIGHT")
    qtyFS:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    row.qtyFS = qtyFS

    -- Item icon — 20×20 on the LEFT
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ROW_H - 4, ROW_H - 4)   -- 20×20
    icon:SetPoint("LEFT", row, "LEFT", 3, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    -- Item name — stretches from item icon to just before qty, truncates naturally
    local nameFS = row:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(FONT, 10, "OUTLINE")
    nameFS:SetPoint("LEFT",  icon,  "RIGHT", 4,  0)
    nameFS:SetPoint("RIGHT", qtyFS, "LEFT",  -4, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    row.nameFS = nameFS

    -- Alternating row background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(BLANK)
    bg:SetVertexColor(1, 1, 1, 0)
    row.altBg = bg

    -- Separator line at row bottom
    local sep = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT",  row, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    sep:SetTexture(BLANK)
    sep:SetVertexColor(T.border[1], T.border[2], T.border[3], 0.4)

    -- Full item tooltip on hover
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
-- Main popup frame  (CraftShopper style, centered on AH)
-- ============================================================
local function MakeListFrame()
    if AutoBuy._listFrame then return AutoBuy._listFrame end

    local T = SP.Theme
    local CONTENT_W = SHOP_W - 12

    local f = CreateFrame("Frame", "SP_AutoBuyFrame", UIParent, "BackdropTemplate")
    f:SetWidth(SHOP_W)
    f:SetFrameStrata("DIALOG")   -- floats above the AH
    f:SetFrameLevel(100)
    f:SetClampedToScreen(true)
    f:Hide()
    -- Body: slightly transparent (like CraftShopper's dark bg), header/footer are solid
    f:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    f:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.80)
    f:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

    f:EnableMouse(true)
    f:EnableMouseWheel(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)

    -- ── Title bar ─────────────────────────────────────────────
    local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    titleBar:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    titleBar:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

    local accentLine = titleBar:CreateTexture(nil, "OVERLAY")
    accentLine:SetHeight(2)
    accentLine:SetPoint("BOTTOMLEFT",  titleBar, "BOTTOMLEFT",  0, 0)
    accentLine:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    accentLine:SetTexture(BLANK)
    accentLine:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.85)

    -- SP Logo overflowing top-left (identical to CraftShopper)
    local logo = CreateFrame("Frame", nil, f)
    logo:SetSize(44, 44)
    logo:SetPoint("TOPLEFT", f, "TOPLEFT", -11, 11)
    logo:SetFrameLevel(f:GetFrameLevel() + 2)
    local logoTex = logo:CreateTexture(nil, "ARTWORK")
    logoTex:SetAllPoints()
    logoTex:SetTexture("Interface\\AddOns\\SuspicionsPack\\Media\\Icons\\icon128x128.png")
    logoTex:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.9)

    local _accentHex = string.format("%02x%02x%02x",
        math.floor(T.accent[1] * 255),
        math.floor(T.accent[2] * 255),
        math.floor(T.accent[3] * 255))

    local titleFS = titleBar:CreateFontString(nil, "OVERLAY")
    titleFS:SetFont(FONT, 13, "OUTLINE")
    titleFS:SetPoint("LEFT", titleBar, "LEFT", 35, 0)
    titleFS:SetText("|cff".._accentHex.."Auto|r|cffffffffBuy|r")

    -- Close ×
    local closeFS_dim  = "|cff666666×|r"
    local closeFS_high = "|cffffffff×|r"
    local closeBtnMain = CreateFrame("Button", nil, titleBar)
    closeBtnMain:SetSize(22, 22)
    closeBtnMain:SetPoint("RIGHT", titleBar, "RIGHT", -5, 0)
    local closeTxtMain = closeBtnMain:CreateFontString(nil, "OVERLAY")
    closeTxtMain:SetFont(FONT, 15, "")
    closeTxtMain:SetText(closeFS_dim)
    closeTxtMain:SetAllPoints()
    closeBtnMain:SetScript("OnClick",  function() f:Hide() end)
    closeBtnMain:SetScript("OnEnter",  function() closeTxtMain:SetText(closeFS_high) end)
    closeBtnMain:SetScript("OnLeave",  function() closeTxtMain:SetText(closeFS_dim) end)

    -- ── Content area (no scroll — all rows visible) ───────────
    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",  f, "TOPLEFT",  6, -32)
    content:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -32)
    content:SetWidth(CONTENT_W)
    content:SetHeight(1)

    f.content = content

    -- ── Footer ────────────────────────────────────────────────
    local footer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    footer:SetHeight(18)
    footer:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    footer:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    footer:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    footer:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

    local footerLbl = footer:CreateFontString(nil, "OVERLAY")
    footerLbl:SetFont(FONT, 9, "")
    footerLbl:SetPoint("LEFT", footer, "LEFT", 8, 0)
    footerLbl:SetText("Suspicion's Pack  ·  AutoBuy")
    footerLbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.6)

    AutoBuy._listFrame = f
    return f
end

-- ============================================================
-- Refresh rows inside the list frame
-- ============================================================
RefreshList = function()
    local f = AutoBuy._listFrame
    if not f or not f:IsShown() then return end

    local T      = SP.Theme
    local content = f.content
    local ahOpen  = AuctionHouseFrame and AuctionHouseFrame:IsShown()

    -- Resolve names
    for _, item in ipairs(items) do
        if not item.name then
            item.name = C_Item.GetItemInfo(item.itemID) or ("item:" .. item.itemID)
        end
    end

    -- Hide all pooled rows
    for _, r in ipairs(rowPool) do r:Hide() end

    local idx = 0
    local y   = 0

    for _, item in ipairs(items) do
        if not item.hidden then
            idx = idx + 1
            local row = GetRow(idx, content)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            row:SetWidth(content:GetWidth())
            row:Show()
            row.itemID = item.itemID

            -- Alternating row shading
            row.altBg:SetVertexColor(1, 1, 1, idx % 2 == 0 and 0.05 or 0)

            -- Icon (async load if not yet cached)
            local capturedID = item.itemID
            local _, _, quality, _, _, _, _, _, _, texture = C_Item.GetItemInfo(capturedID)
            if texture then
                row.icon:SetTexture(texture)
                row.icon:Show()
            else
                -- Show question-mark placeholder while we wait for data
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.icon:Show()
                C_Item.RequestLoadItemDataByID(capturedID)
                local capturedIcon = row.icon
                local listener = CreateFrame("Frame")
                listener:RegisterEvent("GET_ITEM_INFO_RECEIVED")
                listener:SetScript("OnEvent", function(self, _, id)
                    if id ~= capturedID then return end
                    local _, _, _, _, _, _, _, _, _, tex = GetItemInfo(capturedID)
                    if tex then
                        capturedIcon:SetTexture(tex)
                        capturedIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    end
                    self:UnregisterAllEvents()
                    self:SetScript("OnEvent", nil)
                end)
            end

            -- Name with quality colour (icon lives in a separate fixed frame, not inline)
            local color   = quality and select(4, C_Item.GetItemQualityColor(quality)) or "ffffffff"
            local nameStr = ("|c%s%s|r"):format(color, item.name)
            row.nameFS:SetText(nameStr)

            -- Quality icon — drawn in dedicated frame to the left of Buy button
            local qualInfo = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityInfo
                and C_TradeSkillUI.GetItemReagentQualityInfo(capturedID)
            if qualInfo and qualInfo.iconSmall then
                row.qualIconTex:SetAtlas(qualInfo.iconSmall, false)
                row.qualIconFrame:Show()
            else
                row.qualIconFrame:Hide()
            end

            -- Qty: ready-check green checkmark after purchase, "N/M" otherwise
            -- NOTE: Expressway font has no unicode symbols — use |T texture notation instead
            if item.purchased then
                row.qtyFS:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t")
                row.qtyFS:SetTextColor(1, 1, 1, 1)
            else
                row.qtyFS:SetText(("%d|cff888888/|r%d"):format(item.have, item.target))
                row.qtyFS:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
            end

            -- Buy button
            local capturedItem = item
            SetBtnEnabled(row.buyBtn, ahOpen and not pendingBuy)
            row.buyBtn:SetScript("OnClick", function()
                if pendingBuy then return end
                local aux = GetAux()
                aux:RegisterEvent("COMMODITY_PRICE_UPDATED")
                aux:RegisterEvent("COMMODITY_PURCHASE_FAILED")
                aux:RegisterEvent("AUCTION_HOUSE_SHOW_ERROR")
                ShowBuyPopup(capturedItem, row.buyBtn)
                C_AuctionHouse.StartCommoditiesPurchase(capturedItem.itemID, capturedItem.need)
            end)

            y = y + ROW_H
        end
    end

    -- Empty-state placeholder
    if idx == 0 then
        local row = GetRow(1, content)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        row:SetWidth(content:GetWidth())
        row:Show()
        row.itemID = nil
        row.icon:Hide()
        row.qualIconFrame:Hide()
        row.altBg:SetVertexColor(1, 1, 1, 0)
        row.nameFS:SetText("|cff444444All items stocked — nothing to buy|r")
        row.qtyFS:SetText("")
        row.buyBtn:SetScript("OnClick", nil)
        SetBtnEnabled(row.buyBtn, false)
        y = ROW_H
    end

    content:SetHeight(math.max(y, 1))
end

-- ============================================================
-- Show or hide the popup, centered on the AH frame
-- ============================================================
ShowIfNeeded = function()
    if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return end

    local visibleCount = 0
    for _, item in ipairs(items) do
        if not item.hidden then visibleCount = visibleCount + 1 end
    end

    if visibleCount > 0 then
        local f = MakeListFrame()
        f:ClearAllPoints()

        -- Dynamic height: header(28) + all rows + footer(18), no cap
        local HEADER_H = 28
        local FOOTER_H = 18
        local PAD_V    = 4
        local totalH   = HEADER_H + PAD_V + (visibleCount * ROW_H) + PAD_V + FOOTER_H
        f:SetHeight(totalH)

        -- Center on the AH frame
        f:SetPoint("CENTER", AuctionHouseFrame, "CENTER", 0, 0)
        f:Show()
        RefreshList()
    else
        if AutoBuy._listFrame then AutoBuy._listFrame:Hide() end
        UnregisterAllAux()
    end
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function AutoBuy:OnEnable()
    self:RegisterEvent("MERCHANT_SHOW",       "OnMerchantShow")
    self:RegisterEvent("AUCTION_HOUSE_SHOW",   "OnAuctionHouseShow")
    self:RegisterEvent("AUCTION_HOUSE_CLOSED", "OnAuctionHouseClosed")
end

function AutoBuy:OnDisable()
    UnregisterAllAux()
    if AutoBuy._listFrame then AutoBuy._listFrame:Hide() end
    items      = {}
    pendingBuy = nil
    lastBuyID  = nil
    self:UnregisterAllEvents()
end

-- ============================================================
-- Vendor (silent, instant)
-- ============================================================
function AutoBuy:OnMerchantShow()
    local db = GetDB()
    if not db or not db.enabled then return end
    for _, item in ipairs(AutoBuy.PresetItems) do
        local entry = db.items and db.items[item.id]
        if entry and entry.enabled then
            DoBuy(ResolveItemID(item, entry), entry.quantity or item.buy, entry.buyQty or item.buy)
        end
    end
end

-- ============================================================
-- AH entry point
-- ============================================================
function AutoBuy:OnAuctionHouseShow()
    local db = GetDB()
    if not db or not db.enabled then return end
    -- Small delay to let the AH initialise
    C_Timer.After(0.5, function()
        if AutoBuy._listFrame and AutoBuy._listFrame:IsShown() then return end
        items = BuildBuyList()
        ShowIfNeeded()
    end)
end

function AutoBuy:OnAuctionHouseClosed()
    -- If a confirm popup is open, cancel it cleanly so its ticker doesn't fire
    -- CancelCommoditiesPurchase after the AH is already closed (which causes a Lua error).
    if pendingBuy and pendingBuy.Cleanup then
        pendingBuy.Cleanup()   -- cancels ticker, hides popup, clears pendingBuy
    end
    UnregisterAllAux()
    pendingBuy = nil
    lastBuyID  = nil
    if AutoBuy._listFrame then AutoBuy._listFrame:Hide() end
    items = {}
end

-- ============================================================
-- Public API
-- ============================================================
function AutoBuy.Refresh()
    local db  = GetDB()
    local mod = SP.AutoBuy
    if db and db.enabled then
        if not mod:IsEnabled() then mod:Enable() end
    else
        if mod:IsEnabled() then mod:Disable() end
    end
end

