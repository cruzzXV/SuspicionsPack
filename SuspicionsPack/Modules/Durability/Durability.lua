-- SuspicionsPack - Durability.lua
-- Displays a "REPAIR NOW" warning text on-screen when gear durability
-- drops below a configurable threshold. Never shown during combat.
-- Forked & simplified from NorskenUI's QoL/DurabilityUtil.lua.

local SP = SuspicionsPack

local DUR = SP:NewModule("Durability", "AceEvent-3.0")
SP.Durability = DUR

-- ============================================================
-- Locals
-- ============================================================
local CreateFrame                = CreateFrame
local GetInventoryItemDurability = GetInventoryItemDurability
local InCombatLockdown           = InCombatLockdown
local math_floor                 = math.floor
local ipairs                     = ipairs
local UIParent                   = UIParent

local FONT_FACES = {
    ["Expressway"]    = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf",
    ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
    ["Arial"]         = "Fonts\\ARIALN.TTF",
    ["Morpheus"]      = "Fonts\\MORPHEUS.TTF",
}
DUR.FontFaceOrder = { "Expressway", "Friz Quadrata", "Arial", "Morpheus" }

local SP_FONT = FONT_FACES["Expressway"]

local function GetFontPath(name)
    return FONT_FACES[name]
        or (SP.GetFontPath and SP.GetFontPath(name))
        or SP_FONT
end

-- Inventory slots: Head, Shoulder, Chest, Waist, Legs, Feet, Wrists, Gloves, MH, OH, Ranged
local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

-- ============================================================
-- DB helpers
-- ============================================================
local function GetDB()
    return SP.GetDB().durability
end

-- ============================================================
-- Module state
-- ============================================================
DUR.frame      = nil
DUR.text       = nil
DUR.isPreview  = false
DUR.isDragMode = false
DUR._syncSliders = nil  -- set by GUI to sync X/Y sliders on drag

-- ============================================================
-- Durability check — returns lowest durability % across all slots
-- ============================================================
local function GetLowestDurability()
    local lowest = 100
    for _, slot in ipairs(SLOTS) do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = math_floor((cur / max) * 100)
            if pct < lowest then lowest = pct end
        end
    end
    return lowest
end

-- ============================================================
-- Frame creation
-- ============================================================
function DUR:CreateWarningFrame()
    if self.frame then return end
    local db = GetDB()

    local f = CreateFrame("Frame", "SP_DurabilityWarning", UIParent)
    f:SetSize(200, 30)
    f:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or -200)
    f:SetFrameStrata(db.frameStrata or "HIGH")
    f:SetFrameLevel(200)
    f:EnableMouse(false)
    f:Hide()

    local fontPath    = GetFontPath(db.fontFace or "Expressway")
    local outlineFlag = (db.fontOutline ~= "NONE" and db.fontOutline) or ""
    local txt = f:CreateFontString(nil, "OVERLAY")
    txt:SetPoint("CENTER")
    txt:SetFont(fontPath, db.fontSize or 20, outlineFlag)
    txt:SetText(db.warningText or "REPAIR NOW")
    txt:SetJustifyH("CENTER")

    local c = db.color or { 1, 0.537, 0.2, 1 }
    txt:SetTextColor(c[1], c[2], c[3], c[4] or 1)

    -- "Drag to reposition" hint shown during preview/drag mode
    local movLbl = f:CreateFontString(nil, "OVERLAY")
    movLbl:SetPoint("TOP", f, "BOTTOM", 0, -4)
    movLbl:SetFont(SP_FONT, 10, "")
    movLbl:SetText("Drag to reposition")
    movLbl:SetTextColor(1, 0.82, 0.0, 1)
    movLbl:Hide()
    f.movableLbl = movLbl

    -- Pulse animation
    local ag    = f:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local alpha = ag:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0.25)
    alpha:SetDuration(0.6)
    alpha:SetSmoothing("IN_OUT")
    ag:Play()

    -- Drag support (preview/drag mode only)
    f:SetMovable(true)
    f:SetScript("OnDragStart", function(self2) self2:StartMoving() end)
    f:SetScript("OnDragStop",  function(self2)
        self2:StopMovingOrSizing()
        local db2 = GetDB()
        if db2 then
            local cx, cy   = self2:GetCenter()
            local ucx, ucy = UIParent:GetCenter()
            db2.x = math_floor(cx - ucx + 0.5)
            db2.y = math_floor(cy - ucy + 0.5)
            if DUR._syncSliders then DUR._syncSliders(db2.x, db2.y) end
        end
    end)

    self.frame   = f
    self.text    = txt
    self.pulseAG = ag
end

-- ============================================================
-- Apply settings from DB
-- ============================================================
function DUR:ApplySettings()
    if not self.frame then return end
    local db = GetDB()

    local fontPath    = GetFontPath(db.fontFace or "Expressway")
    local outlineFlag = (db.fontOutline ~= "NONE" and db.fontOutline) or ""
    self.text:SetFont(fontPath, db.fontSize or 20, outlineFlag)
    self.text:SetText(db.warningText or "REPAIR NOW")

    local cr, cg, cb = SP.GetColorFromSource(db.colorSource or "custom",
        db.color or { 1, 0.537, 0.2 })
    self.text:SetTextColor(cr, cg, cb, 1)

    self.frame:ClearAllPoints()
    local anchorFrom  = db.anchorFrom  or "CENTER"
    local anchorTo    = db.anchorTo    or "CENTER"
    local anchorFrame = _G[db.anchorFrame or "UIParent"] or UIParent
    self.frame:SetPoint(anchorFrom, anchorFrame, anchorTo, db.x or 0, db.y or -200)
    self.frame:SetFrameStrata(db.frameStrata or "HIGH")

    local w = math.max(self.text:GetStringWidth() + 20, 120)
    local h = math.max(self.text:GetStringHeight() + 10, 26)
    self.frame:SetSize(w, h)
end

-- ============================================================
-- Core update — show/hide based on durability threshold
-- Never shows during combat.
-- ============================================================
function DUR:OnDurabilityCheck()
    if self.isPreview or self.isDragMode then return end
    if not self.frame then return end

    if InCombatLockdown() then
        self.frame:Hide()
        return
    end

    local db = GetDB()
    if not db then return end

    local lowest = GetLowestDurability()
    if lowest <= (db.threshold or 30) then
        self.frame:Show()
    else
        self.frame:Hide()
    end
end

-- ============================================================
-- Preview
-- ============================================================
function DUR:ShowPreview()
    if not self.frame then self:CreateWarningFrame() end
    self.isPreview = true

    self.frame:EnableMouse(false)   -- preview is display-only, not draggable
    self:ApplySettings()
    self.frame:Show()
end

function DUR:HidePreview()
    self.isPreview = false
    if not self.frame then return end
    if not self.isDragMode then
        self.frame:EnableMouse(false)
        if self.frame.movableLbl then self.frame.movableLbl:Hide() end
    end

    local db = GetDB()
    if not db or not db.enabled then
        self.frame:Hide()
        return
    end
    self:OnDurabilityCheck()
end

-- ============================================================
-- Drag mode (separate from preview — repositions live frame)
-- ============================================================
function DUR:StartDragMode()
    if not self.frame then self:CreateWarningFrame() end
    self.isDragMode = true

    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    if self.frame.movableLbl then self.frame.movableLbl:Show() end
    self:ApplySettings()
    self.frame:Show()
end

function DUR:EndDragMode()
    self.isDragMode = false
    if not self.frame then return end
    if not self.isPreview then
        self.frame:EnableMouse(false)
        if self.frame.movableLbl then self.frame.movableLbl:Hide() end
    end

    local db = GetDB()
    if not db or not db.enabled then
        if not self.isPreview then self.frame:Hide() end
        return
    end
    self:OnDurabilityCheck()
end

-- ============================================================
-- Activate / Deactivate
-- ============================================================
function DUR:Activate()
    local db = GetDB()
    if not db or not db.enabled then return end

    self:CreateWarningFrame()
    self:ApplySettings()

    self:RegisterEvent("UPDATE_INVENTORY_DURABILITY", "OnDurabilityCheck")
    self:RegisterEvent("MERCHANT_SHOW",               "OnDurabilityCheck")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",       "OnDurabilityCheck")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        if self.frame then self.frame:Hide() end
    end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnDurabilityCheck")

    C_Timer.After(0.5, function()
        self:ApplySettings()
        self:OnDurabilityCheck()
    end)
end

function DUR:Deactivate()
    self:UnregisterAllEvents()
    if self.frame then self.frame:Hide() end
    self.isPreview  = false
    self.isDragMode = false
end

function DUR.Refresh()
    local db = GetDB()
    if db and db.enabled then
        DUR:Activate()
    else
        DUR:Deactivate()
    end
end

-- ============================================================
-- AceAddon lifecycle
-- ============================================================
function DUR:OnEnable()
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

function DUR:OnDisable()
    self:Deactivate()
end
