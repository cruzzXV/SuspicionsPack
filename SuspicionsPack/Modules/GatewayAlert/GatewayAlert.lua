-- SuspicionsPack — GatewayAlert Module
-- Affiche une alerte clignotante quand le Portail démoniaque est utilisable.

local SP = SuspicionsPack

local GA = SP:NewSPModule("GatewayAlert", "gatewayAlert")
SP.GatewayAlert = GA

-- ============================================================
-- Constants
-- ============================================================
local GATEWAY_ITEM_ID = 188152

local SP_FONT = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"

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
    local db = self:GetDB()

    local f, lbl = SP.CreateAlertFrame("SP_GatewayAlertFrame", db, {
        defaultY       = -100,
        defaultSize    = 16,
        defaultOutline = "OUTLINE",
        defaultColor   = { 0.3, 1.0, 0.4, 1 },
        text           = "GATE USABLE",
        pulse          = { from = 1, to = 0.25, duration = 0.5 },
    })

    f.label      = lbl          -- kept: ApplySettings and the preview read it
    f.pulseGroup = f.pulseAG    -- kept under the old name for the same reason
    self.frame   = f
end

-- ============================================================
-- Apply position & style from DB
-- ============================================================
function GA:ApplySettings()
    if not self.frame then return end
    local db = self:GetDB()
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
    local db = self:GetDB()
    if not db or not db.enabled then
        self.frame:Hide()
        return
    end
    self:CheckUsable()
end

-- ============================================================
-- Activate / Deactivate
--
-- Called by the GUI enable toggle and by ModuleMixin:Refresh(). Refresh,
-- OnEnable and OnDisable all come from ModuleMixin -- see Core/Module.lua.
-- ============================================================
function GA:Activate()
    local db = self:GetDB()
    if not db or not db.enabled then return end

    self:CreateAlertFrame()
    self:ApplySettings()

    self:RegisterEvent("PLAYER_ENTERING_WORLD", "FullUpdate")
    self:RegisterEvent("BAG_UPDATE",            "FullUpdate")
    self:RegisterEvent("SPELL_UPDATE_USABLE",   "CheckUsable")

    C_Timer.After(0.5, function()
        -- Re-read the setting: C_Timer.After cannot be cancelled, so this can
        -- land after a Deactivate and would otherwise re-arm FullUpdate (and
        -- with it the frame) for a module the user just switched off.
        local d = self:GetDB()
        if not (d and d.enabled) then return end
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
