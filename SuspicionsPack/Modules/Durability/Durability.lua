-- SuspicionsPack - Durability.lua
-- Displays a "REPAIR NOW" warning text on-screen when gear durability
-- drops below a configurable threshold. Never shown during combat.

local SP = SuspicionsPack

local DUR = SP:NewSPModule("Durability", "durability")
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



-- Font names now resolve through Core: SP.FONT_FACES is the single
-- source of truth and SP.ResolveFont falls back to the pack default.
-- The private table this used to carry SHADOWED LibSharedMedia, so any
-- font the user added via another addon silently became Expressway here.
local function GetFontPath(name)
    return SP.ResolveFont(name)
end

-- Inventory slots: Head, Shoulder, Chest, Waist, Legs, Feet, Wrists, Gloves, MH, OH, Ranged
local SLOTS = { 1, 3, 5, 6, 7, 8, 9, 10, 16, 17, 18 }

-- ============================================================
-- Module state
-- ============================================================
DUR.frame      = nil
DUR.text       = nil
DUR.isPreview  = false

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
    local db = self:GetDB()
    if not db then return end

    -- Built by the shared factory: this was ~30 lines duplicated almost
    -- verbatim across eight alert modules, and the copies had already drifted
    -- from each other on the outline default and mouse handling.
    local f, txt = SP.CreateAlertFrame("SP_DurabilityWarning", db, {
        defaultY       = -200,
        defaultSize    = 20,
        defaultColor   = { 1, 0.537, 0.2, 1 },
        text           = db.warningText or "REPAIR NOW",
        pulse          = { from = 1, to = 0.25, duration = 0.6 },
    })

    self.frame   = f
    self.text    = txt
    self.pulseAG = f.pulseAG
end

-- ============================================================
-- Apply settings from DB
-- ============================================================
function DUR:ApplySettings()
    if not self.frame then return end
    local db = self:GetDB()
    if not db then return end

    local fontPath    = GetFontPath(db.fontFace or "Expressway")
    local outlineFlag = (db.fontOutline ~= "NONE" and db.fontOutline) or ""
    SP.SetFontSafe(self.text, fontPath, db.fontSize or 20, outlineFlag)
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
    if self.isPreview then return end
    if not self.frame then return end

    if InCombatLockdown() then
        self.frame:Hide()
        return
    end

    local db = self:GetDB()
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

    self.frame:EnableMouse(false)
    self:ApplySettings()
    self.frame:Show()
end

function DUR:HidePreview()
    self.isPreview = false
    if not self.frame then return end
    self.frame:EnableMouse(false)

    local db = self:GetDB()
    if not db or not db.enabled then
        self.frame:Hide()
        return
    end
    self:OnDurabilityCheck()
end

-- ============================================================
-- Activate / Deactivate
-- Everything else (Refresh / OnEnable / OnDisable) comes from SP.ModuleMixin.
-- ============================================================
function DUR:Activate()
    if not self:IsOn() then return end

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
        -- C_Timer.After cannot be cancelled, so re-read the setting instead:
        -- the user may have switched the module off inside this half-second
        -- window, and OnDurabilityCheck would otherwise re-show the frame.
        if not self:IsOn() then return end
        self:ApplySettings()
        self:OnDurabilityCheck()
    end)
end

function DUR:Deactivate()
    self:UnregisterAllEvents()
    if self.frame then self.frame:Hide() end
    self.isPreview  = false
end
