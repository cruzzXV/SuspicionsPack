-- SuspicionsPack — FilterExpansionOnly Module
-- Automatically applies "Current Expansion Only" filter when:
--   • The Auction House opens           (AH SearchBar.FilterButton)
--   • The Crafting Orders browser opens (ProfessionsCustomerOrdersFrame FilterDropdown)
-- Crafting Orders logic ported from NorskenUI/AuctionHouseFilter.lua.
local SP = SuspicionsPack

local FEO = SP:NewModule("FilterExpansionOnly", "AceEvent-3.0")
SP.FilterExpansionOnly = FEO

-- ============================================================
-- Helpers
-- ============================================================
local function GetDB()
    return SP.GetDB().filterExpansionOnly
end

-- ============================================================
-- Filter application
-- ============================================================
local function ApplyAHFilter()
    C_Timer.After(0, function()
        if AuctionHouseFrame and AuctionHouseFrame.SearchBar then
            local filterBtn = AuctionHouseFrame.SearchBar.FilterButton
            if filterBtn and filterBtn.filters then
                filterBtn.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
                if AuctionHouseFrame.SearchBar.UpdateClearFiltersButton then
                    AuctionHouseFrame.SearchBar:UpdateClearFiltersButton()
                end
            end
        end
    end)
end

local function ApplyCraftOrdersFilter()
    C_Timer.After(0, function()
        local frame = ProfessionsCustomerOrdersFrame
        if frame and frame.BrowseOrders and frame.BrowseOrders.SearchBar then
            local filterDropdown = frame.BrowseOrders.SearchBar.FilterDropdown
            if filterDropdown and filterDropdown.filters then
                filterDropdown.filters[Enum.AuctionHouseFilter.CurrentExpansionOnly] = true
            end
        end
    end)
end

-- ============================================================
-- Event handlers
-- ============================================================
function FEO:AUCTION_HOUSE_SHOW()
    local db = GetDB()
    if not db or not db.enabled then return end
    ApplyAHFilter()
end

function FEO:CRAFTINGORDERS_SHOW_CUSTOMER()
    local db = GetDB()
    if not db or not db.enabled then return end
    ApplyCraftOrdersFilter()
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function FEO:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterEvent("CRAFTINGORDERS_SHOW_CUSTOMER")
end

function FEO:OnDisable()
    self:UnregisterAllEvents()
end

-- Called by GUI toggle
function FEO.Refresh()
    local db  = GetDB()
    local mod = SP.FilterExpansionOnly
    if db and db.enabled then
        if not mod:IsEnabled() then mod:Enable() end
    else
        if mod:IsEnabled() then mod:Disable() end
    end
end
