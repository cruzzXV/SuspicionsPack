-- SuspicionsPack — GatewayAlert Module
-- Displays a flashing alert when the Warlock Demonic Gateway item is usable.
-- Checks: item 188152 is in bags AND C_Item.IsUsableItem returns true.
-- Forked & simplified from NorskenUI's QoL/GateUsable.lua.

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
GA.isDragMode = false
GA._syncSliders = nil   -- set by GUI to sync X/Y sliders on drag

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

    -- "Drag to reposition" hint
    local movLbl = f:CreateFontString(nil, "OVERLAY")
    movLbl:SetPoint("TOP", f, "BOTTOM", 0, -4)
    movLbl:SetFont(SP_FONT, 10, "")
    movLbl:SetText("Drag to reposition")
    movLbl:SetTextColor(1, 0.82, 0.0, 1)
    movLbl:Hide()
    f.movableLbl = movLbl

    f:SetMovable(true)
    f:SetScript("OnDragStart", function(self2) self2:StartMoving() end)
    f:SetScript("OnDragStop",  function(self2)
        self2:StopMovingOrSizing()
        local db2 = GetDB()
        if db2 then
            local cx, cy   = self2:GetCenter()
            local ucx, ucy = UIParent:GetCenter()
            db2.x = math.floor(cx - ucx + 0.5)
            db2.y = math.floor(cy - ucy + 0.5)
            if GA._syncSliders then GA._syncSliders(db2.x, db2.y) end
        end
    end)
    f:EnableMouse(false)
    f:SetMouseClickEnabled(false)

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
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local fontPath = (LSM and db.fontFace and LSM:Fetch("font", db.fontFace)) or SP_FONT
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
    -- Small delay to avoid race conditions with BAG_UPDATE firing before item data is ready
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
    -- Reset cached state so UpdateState doesn't skip the hide due to
    -- "isUsable == wasUsable" when nothing changed while preview was open.
    wasUsable = nil
    if not self.frame then return end
    if not self.isDragMode then
        self.frame:EnableMouse(false)
        self.frame:SetMouseClickEnabled(false)
    end
    local db = GetDB()
    if not db or not db.enabled then
        if not self.isDragMode then self.frame:Hide() end
        return
    end
    self:CheckUsable()
end

-- ============================================================
-- Drag mode
-- ============================================================
function GA:StartDragMode()
    if not self.frame then self:CreateAlertFrame() end
    self.isDragMode = true
    self.frame:EnableMouse(true)
    self.frame:SetMouseClickEnabled(true)
    self.frame:RegisterForDrag("LeftButton")
    if self.frame.movableLbl then self.frame.movableLbl:Show() end
    self.frame:Show()
    self:ApplySettings()
end

function GA:EndDragMode()
    self.isDragMode = false
    -- Reset cached state so UpdateState doesn't skip the hide (same fix as HidePreview).
    wasUsable = nil
    if not self.frame then return end
    if not self.isPreview then
        self.frame:EnableMouse(false)
        self.frame:SetMouseClickEnabled(false)
        if self.frame.movableLbl then self.frame.movableLbl:Hide() end
    end
    local db = GetDB()
    if not db or not db.enabled then
        if not self.isPreview then self.frame:Hide() end
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
    self.isDragMode = false
end

function GA.Refresh()
    local db = GetDB()
    if db and db.enabled then
        GA:Activate()
    else
        GA:Deactivate()
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
