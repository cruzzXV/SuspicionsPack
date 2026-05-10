-- SuspicionsPack - PetStatus.lua
-- Displays a text alert for pet status: Missing, Dead, or Passive.
-- Forked from NorskenUI's PetTexts module, adapted to SP patterns.

local SP = SuspicionsPack

local PS = SP:NewModule("PetStatus", "AceEvent-3.0")
SP.PetStatus = PS

-- ============================================================
-- Locals
-- ============================================================
local CreateFrame           = CreateFrame
local UnitClass             = UnitClass
local UnitExists            = UnitExists
local UnitIsDeadOrGhost     = UnitIsDeadOrGhost
local IsMounted             = IsMounted
local UnitOnTaxi            = UnitOnTaxi
local UnitInVehicle         = UnitInVehicle
local UnitHasVehicleUI      = UnitHasVehicleUI
local GetSpecialization     = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local IsPlayerSpell         = IsPlayerSpell
local GetPetActionInfo      = GetPetActionInfo
local PetHasActionBar       = PetHasActionBar
local C_SpellBook           = C_SpellBook
local C_Timer               = C_Timer
local UIParent              = UIParent

local SP_FONT = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"

-- ============================================================
-- Pet classes with summonable pets
-- specId: restrict to a specific spec (nil = all specs)
-- ============================================================
local PET_CLASSES = {
    HUNTER      = { summonSpellId = 883,   specId = nil },
    WARLOCK     = { summonSpellId = 688,   specId = nil },
    DEATHKNIGHT = { summonSpellId = 46584, specId = 252 }, -- Unholy only
    MAGE        = { summonSpellId = 31687, specId = 64  }, -- Arcane only
}

-- ============================================================
-- DB helper
-- ============================================================
local function GetDB()
    return SP.GetDB().petStatus
end

-- ============================================================
-- Module state
-- ============================================================
local petInfo         = nil   -- set in OnInitialize from player class
local petDeathTracked = false -- persists death state across unit disappear events

-- ============================================================
-- Pet detection helpers
-- ============================================================
local function IsPlayerMounted()
    return IsMounted() or UnitOnTaxi("player") or UnitInVehicle("player") or UnitHasVehicleUI("player")
end

-- Returns true if the pet action bar has the Passive stance active.
local function IsPetOnPassive()
    if not UnitExists("pet") or not PetHasActionBar() then return false end
    for slot = 1, 10 do
        local name, _, isToken, isActive = GetPetActionInfo(slot)
        if isToken and name == "PET_MODE_PASSIVE" and isActive then return true end
    end
    return false
end

-- Tracks pet death across unit-removed events.
local function CheckAndUpdatePetDeathState()
    if UnitExists("pet") and not UnitIsDeadOrGhost("pet") then
        petDeathTracked = false
        return false
    end
    if UnitExists("pet") and UnitIsDeadOrGhost("pet") then
        petDeathTracked = true
        return true
    end
    -- Pet doesn't exist — was it dead before it disappeared?
    return petDeathTracked
end

local function ResetPetDeathTracking()
    petDeathTracked = false
end

-- Returns "dead" | "passive" | "missing" | nil (nil = nothing to show)
local function CheckPetStatus()
    if not petInfo then return nil end
    if IsPlayerMounted() then return nil end

    local specIndex = GetSpecialization()
    local specID    = specIndex and GetSpecializationInfo(specIndex)

    -- MM Hunter with Unbreakable Bond (466867): no pet needed, suppress
    if specID == 254 and IsPlayerSpell(466867) then return nil end

    -- Spec restriction (DK Unholy, Mage Arcane)
    if petInfo.specId then
        if not specID or specID ~= petInfo.specId then return nil end
    end

    if not C_SpellBook.IsSpellKnown(petInfo.summonSpellId) then return nil end

    -- Priority: Dead > Passive > Missing
    if CheckAndUpdatePetDeathState() then return "dead" end
    if UnitExists("pet") then
        if IsPetOnPassive() then return "passive" end
        return nil  -- alive and active
    end
    return "missing"
end

-- ============================================================
-- Font path helper
-- ============================================================
local function GetFontPath(name)
    return SP.GetFontPath(name) or SP_FONT
end

-- Convert "NONE" → "" (SetFont does not accept "NONE")
local function ResolveOutline(outline)
    if not outline or outline == "NONE" then return "" end
    return outline
end

-- ============================================================
-- Frame (lazy-built)
-- ============================================================
local frame  = nil
local fsText = nil

local function BuildFrame()
    if frame then return end

    frame = CreateFrame("Frame", "SP_PetStatus", UIParent)
    frame:SetSize(200, 50)
    frame:EnableMouse(false)

    fsText = frame:CreateFontString(nil, "OVERLAY")
    fsText:SetPoint("CENTER")
    fsText:SetFont(SP_FONT, 20, "OUTLINE")
    fsText:SetTextColor(1, 0.843, 0, 1)
    fsText:SetJustifyH("CENTER")
    fsText:Hide()

    PS.frame  = frame
    PS.fsText = fsText
end

-- ============================================================
-- ApplySettings — font + position
-- ============================================================
function PS:ApplySettings()
    if not frame then return end
    local db = GetDB()
    fsText:SetFont(
        GetFontPath(db.fontFace or "Expressway"),
        db.fontSize  or 25,
        ResolveOutline(db.fontOutline or "SOFTOUTLINE"))
    frame:SetFrameStrata(db.frameStrata or "HIGH")
    frame:ClearAllPoints()
    local anchorFrame = _G[db.anchorFrame or "UIParent"] or UIParent
    frame:SetPoint(
        db.anchorFrom or "CENTER", anchorFrame, db.anchorTo or "CENTER",
        db.x or 0, db.y or 105)
end

-- ============================================================
-- UpdateDisplay — reads live pet state and refreshes the text
-- ============================================================
function PS:UpdateDisplay()
    if PS.isPreview then return end
    if not frame or not fsText then return end

    local status = CheckPetStatus()
    local db = GetDB()

    if status == "dead" then
        local c = db.deadColor or { 1, 0.2, 0.2, 1 }
        fsText:SetText(db.deadText or "PET DEAD")
        fsText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        fsText:Show()
        frame:Show()
    elseif status == "passive" then
        local c = db.passiveColor or { 0.302, 0.702, 1, 1 }
        fsText:SetText(db.passiveText or "PET PASSIVE")
        fsText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        fsText:Show()
        frame:Show()
    elseif status == "missing" then
        local c = db.missingColor or { 1, 0.843, 0, 1 }
        fsText:SetText(db.missingText or "PET MISSING")
        fsText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        fsText:Show()
        frame:Show()
    else
        fsText:Hide()
        frame:Hide()
    end
end

-- ============================================================
-- Preview (called by PreviewManager on GUI open/close)
-- Shows the "missing" text so position is always visible.
-- ============================================================
function PS:ShowPreview()
    if not petInfo then return end  -- non-pet class: nothing to preview
    BuildFrame()
    self:ApplySettings()
    PS.isPreview = true
    local db = GetDB()
    local c  = db.missingColor or { 1, 0.843, 0, 1 }
    fsText:SetText(db.missingText or "PET MISSING")
    fsText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fsText:Show()
    frame:Show()
end

function PS:HidePreview()
    PS.isPreview = false
    if fsText then fsText:Hide() end
    if frame  then frame:Hide()  end
    local db = GetDB()
    if db and db.enabled then
        C_Timer.After(0, function() PS:UpdateDisplay() end)
    end
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function PS:OnInitialize()
    local _, class = UnitClass("player")
    petInfo = PET_CLASSES[class]
    -- Module starts disabled; AceAddon will call OnEnable when db.enabled becomes true
    self:SetEnabledState(false)
end

function PS:OnEnable()
    self:Refresh()
end

function PS:OnDisable()
    self:UnregisterAllEvents()
    if frame then frame:Hide() end
end

function PS:Refresh()
    local db = GetDB()
    if not db then return end

    if not db.enabled then
        self:UnregisterAllEvents()
        if frame then frame:Hide() end
        return
    end

    if not petInfo then return end  -- player class has no pet

    BuildFrame()
    self:ApplySettings()

    -- Pet summon/dismiss (unit appears or disappears)
    self:RegisterEvent("UNIT_PET", function(_, unit)
        if unit ~= "player" then return end
        C_Timer.After(0.2, function()
            if UnitExists("pet") and not UnitIsDeadOrGhost("pet") then
                ResetPetDeathTracking()
            end
            PS:UpdateDisplay()
        end)
    end)

    -- Pet death event
    self:RegisterEvent("UNIT_DIED", "UpdateDisplay")

    -- Pet stance change (passive/aggressive/defensive)
    self:RegisterEvent("PET_BAR_UPDATE", function()
        C_Timer.After(0.1, function() PS:UpdateDisplay() end)
    end)

    -- Combat state transitions
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "UpdateDisplay")

    -- Login / zone change
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(1, function() PS:UpdateDisplay() end)
    end)

    -- Spell book changes (summon spell learned)
    self:RegisterEvent("SPELLS_CHANGED", "UpdateDisplay")

    -- Spec change may change whether pet is relevant
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "UpdateDisplay")

    frame:Show()
    self:UpdateDisplay()
end
