-- SuspicionsPack - MinimapButton.lua
-- Registers a LibDBIcon minimap button; left-click toggles the settings panel.

local SP      = SuspicionsPack
local LDB     = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

if not LDB or not LDBIcon then return end

-- Register as an AceAddon module with AceEvent-3.0 mixin
local MinimapBtn = SP:NewModule("MinimapButton", "AceEvent-3.0")

local T = SP.Theme

local DataObj = LDB:NewDataObject("SuspicionsPack", {
    type   = "launcher",
    text   = "Suspicion's Pack",
    icon   = "Interface\\AddOns\\SuspicionsPack\\Media\\Icons\\icon.png",
    iconR  = T.accent[1],
    iconG  = T.accent[2],
    iconB  = T.accent[3],
    OnClick = function(_, btn)
        if btn == "LeftButton" then
            if SP.GUI then SP.GUI.Toggle() end
        end
    end,
    OnTooltipShow = function(tt)
        local ac = SP.Theme.accent
        tt:AddLine(string.format("|cff%02x%02x%02xSuspicion's|r|cffffffffPack|r",
            ac[1]*255, ac[2]*255, ac[3]*255))
        tt:AddLine(" ")
        tt:AddLine("|cffaaaaaaLeft-Click|r to open settings", 1, 1, 1)
    end,
})

-- Expose DataObj so RefreshTheme can update iconR/G/B for live theme color changes
SP.MinimapDataObj = DataObj

function MinimapBtn:OnEnable()
    if IsLoggedIn() then
        self:RegisterButton()
    else
        self:RegisterEvent("PLAYER_LOGIN", "RegisterButton")
    end
end

function MinimapBtn:RegisterButton()
    self:UnregisterEvent("PLAYER_LOGIN")
    local db = SP.GetDB()
    if not db.minimapButton then db.minimapButton = {} end

    -- The minimap button is always visible — not user-hideable.
    db.minimapButton.hide = false

    -- Re-sync accent color to live theme (snapshotted at file-load before OnInitialize).
    local ac = SP.Theme.accent
    DataObj.iconR = ac[1]
    DataObj.iconG = ac[2]
    DataObj.iconB = ac[3]

    LDBIcon:Register("SuspicionsPack", DataObj, db.minimapButton)
    LDBIcon:Show("SuspicionsPack")

    -- ── ElvUI-style 1px pixel-perfect border ─────────────────────
    -- Defer one frame so LibDBIcon finishes building the button before we touch it.
    C_Timer.After(0, function()
        local btn = LDBIcon:GetMinimapButton("SuspicionsPack")
        if not btn then return end

        -- Square texcoords: fill icon area cleanly (removes Blizzard circular inset)
        if btn.icon then
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end

        -- Hide the default circular border/overlay textures from LibDBIcon
        for _, region in ipairs({ btn:GetRegions() }) do
            if region:IsObjectType("Texture") and region ~= btn.icon then
                region:SetAlpha(0)
            end
        end

        -- 4 individual 1px textures at OVERLAY subLevel 7.
        -- Textures on a frame are NOT clipped by the frame bounds, so the
        -- border extends 1px outside the button edges reliably.
        local bdr = SP.Theme.border
        local r, g, b = bdr[1], bdr[2], bdr[3]

        local top = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        top:SetColorTexture(r, g, b, 1)
        top:SetPoint("TOPLEFT",  btn, "TOPLEFT",  -1,  1)
        top:SetPoint("TOPRIGHT", btn, "TOPRIGHT",  1,  1)
        top:SetHeight(1)

        local bot = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        bot:SetColorTexture(r, g, b, 1)
        bot:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  -1, -1)
        bot:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  1, -1)
        bot:SetHeight(1)

        local lft = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        lft:SetColorTexture(r, g, b, 1)
        lft:SetPoint("TOPLEFT",    btn, "TOPLEFT",    -1,  1)
        lft:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -1, -1)
        lft:SetWidth(1)

        local rgt = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        rgt:SetColorTexture(r, g, b, 1)
        rgt:SetPoint("TOPRIGHT",    btn, "TOPRIGHT",    1,  1)
        rgt:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, -1)
        rgt:SetWidth(1)
    end)
end
