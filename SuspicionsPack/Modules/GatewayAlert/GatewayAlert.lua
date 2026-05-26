-- SuspicionsPack — GatewayAlert Module
-- Affiche une alerte clignotante quand le Portail démoniaque est utilisable.

local SP = SuspicionsPack

local GA = SP:NewModule("GatewayAlert", "AceEvent-3.0")
SP.GatewayAlert = GA

-- ============================================================
-- Constants
-- ============================================================
local GATEWAY_ITEM_ID = 188152

local SP_FONT = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"

-- ============================================================
-- DB helper
-- ============================================================
local function GetDB()
    return SP.GetDB().gatewayAlert
end

-- ============================================================
-- Module state
-- ============================================================
GA.frame      = nil
GA.isPreview  = false

local wasUsable    = false
local hasItem      = false
local fullUpdateTimer = nil

-- ============================================================
-- Frame creation
-- ============================================================
function GA:CreateAlertFrame()
    if self.frame then return end
    local db = GetDB()

    local f = CreateFrame("Frame", "SP_GatewayAlertFrame", UIParent)
    f:SetSize(200, 30)
    f:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or -100)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(200)
    f:EnableMouse(false)
    f:SetMouseClickEnabled(false)
    f:Hide()

    local lbl = f:CreateFontString(nil, "OVERLAY")
    local fontPath    = SP_FONT
    local outlineFlag = (db.fontOutline ~= "NONE" and db.fontOutline) or "OUTLINE"
    lbl:SetFont(fontPath, db.fontSize or 16, outlineFlag)
    lbl:SetPoint("CENTER", f, "CENTER", 0, 0)
    lbl:SetText("GATE USABLE")
    local c = db.color or { 0.3, 1.0, 0.4, 1 }
    lbl:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    f.label = lbl

    -- Pulse animation
    local ag    = f:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local alpha = ag:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0.25)
    alpha:SetDuration(0.5)
    alpha:SetSmoothing("IN_OUT")
    ag:Play()
    f.pulseGroup = ag

    self.frame = f
end

-- ============================================================
-- Apply position & style from DB
-- ============================================================
function GA:ApplySettings()
    if not self.frame then return end
    local db = GetDB()
    self.frame:ClearAllPoints()
    local anchorFrom  = db.anchorFrom  or "CENTER"
    local anchorTo    = db.anchorTo    or "CENTER"
    local anchorFrame = _G[db.anchorFrame or "UIParent"] or UIParent
    self.frame:SetPoint(anchorFrom, anchorFrame, anchorTo, db.x or 0, db.y or -100)
    self.frame:SetFrameStrata(db.frameStrata or "HIGH")
    if self.frame.label then
        local fontPath = (db.fontFace and SP.GetFontPath and SP.GetFontPath(db.fontFace)) or SP_FONT
        local outlineFlag = (db.fontOutline ~= "NONE" and db.fontOutline) or "OUTLINE"
        self.frame.label:SetFont(fontPath, db.fontSize or 16, outlineFlag)
        local cr, cg2, cb = SP.GetColorFromSource(db.colorSource or "custom",
            db.color or { 0.3, 1.0, 0.4 })
        self.frame.label:SetTextColor(cr, cg2, cb, 1)
    end
end

-- ============================================================
-- State logic
-- ============================================================
function GA:UpdateState(isUsable)
    if self.isPreview then return end
    if isUsable == wasUsable then return end
    wasUsable = isUsable

    if not self.frame then return end
    if isUsable then
        self.frame:Show()
    else
        self.frame:Hide()
    end
end

function GA:CheckUsable()
    if not hasItem then self:UpdateState(false); return end
    self:UpdateState(C_Item.IsUsableItem(GATEWAY_ITEM_ID) and true or false)
end

function GA:FullUpdate()
    if fullUpdateTimer then fullUpdateTimer:Cancel() end
    fullUpdateTimer = C_Timer.NewTimer(0.5, function()
        fullUpdateTimer = nil
        local count = C_Item.GetItemCount(GATEWAY_ITEM_ID)
        hasItem = count and count > 0
        if hasItem then
            self:CheckUsable()
        else
            self:UpdateState(false)
        end
    end)
end

-- ============================================================
-- Preview
-- ============================================================
function GA:ShowPreview()
    if not self.frame then self:CreateAlertFrame() end
    self.isPreview = true
    self.frame:EnableMouse(true)
    self.frame:SetMouseClickEnabled(true)
    self.frame:Show()
    self:ApplySettings()
end

function GA:HidePreview()
    self.isPreview = false
    wasUsable = nil
    if not self.frame then return end
    self.frame:EnableMouse(false)
    self.frame:SetMouseClickEnabled(false)
    local db = GetDB()
    if not db or not db.enabled then
        self.frame:Hide()
        return
    end
    self:CheckUsable()
end

-- ============================================================
-- Activate / Deactivate
-- ============================================================
function GA:Activate()
    local db = GetDB()
    if not db or not db.enabled then return end

    self:CreateAlertFrame()
    self:ApplySettings()

    self:RegisterEvent("PLAYER_ENTERING_WORLD", "FullUpdate")
    self:RegisterEvent("BAG_UPDATE",            "FullUpdate")
    self:RegisterEvent("SPELL_UPDATE_USABLE",   "CheckUsable")

    C_Timer.After(0.5, function()
        if self.frame then
            self:ApplySettings()
            self:FullUpdate()
        end
    end)
end

function GA:Deactivate()
    self:UnregisterAllEvents()
    if fullUpdateTimer then fullUpdateTimer:Cancel(); fullUpdateTimer = nil end
    if self.frame then self.frame:Hide() end
    wasUsable     = false
    hasItem       = false
    self.isPreview  = false
end

function GA:Refresh()
    local db = GetDB()
    if db and db.enabled then
        self:Activate()
    else
        self:Deactivate()
    end
end

-- ============================================================
-- AceAddon lifecycle
-- ============================================================
function GA:OnEnable()
    if IsLoggedIn() then
        local db = GetDB()
        if db and db.enabled then self:Activate() end
    else
        self:RegisterEvent("PLAYER_LOGIN", function()
            local db = GetDB()
            if db and db.enabled then self:Activate() end
        end)
    end
end

function GA:OnDisable()
    self:Deactivate()
end
