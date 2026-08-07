-- SuspicionsPack — FilterExpansionOnly Module
-- Automatically applies "Current Expansion Only" filter when:
--   • The Auction House opens           (AH SearchBar.FilterButton)
--   • The Crafting Orders browser opens (ProfessionsCustomerOrdersFrame FilterDropdown)
local SP = SuspicionsPack

local FEO = SP:NewSPModule("FilterExpansionOnly", "filterExpansionOnly")
SP.FilterExpansionOnly = FEO

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
    if not self:IsOn() then return end
    ApplyAHFilter()
end

function FEO:CRAFTINGORDERS_SHOW_CUSTOMER()
    if not self:IsOn() then return end
    ApplyCraftOrdersFilter()
end

-- ============================================================
-- Module lifecycle
-- OnEnable / OnDisable / Refresh come from SP.ModuleMixin.
-- ============================================================
function FEO:Activate()
    self:RegisterEvent("AUCTION_HOUSE_SHOW")
    self:RegisterEvent("CRAFTINGORDERS_SHOW_CUSTOMER")
end

function FEO:Deactivate()
    self:UnregisterEvent("AUCTION_HOUSE_SHOW")
    self:UnregisterEvent("CRAFTINGORDERS_SHOW_CUSTOMER")
end
