-- SuspicionsPack - CombatCross.lua
-- Affiche un "+" à l'écran en combat. Passe en rouge hors de portée.

local SP = SuspicionsPack

local CC = SP:NewSPModule("CombatCross", "combatCross")
SP.CombatCross = CC

-- ============================================================
-- Locals
-- ============================================================
local CreateFrame           = CreateFrame
local InCombatLockdown      = InCombatLockdown
local UIFrameFadeIn         = UIFrameFadeIn
local UIParent              = UIParent
local GetSpecialization     = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local C_Spell               = C_Spell
local UnitExists            = UnitExists
local select                = select

-- Localised with a fallback, matching BloodlustAlert/ReapPredict: a missing
-- global here would be a hard error on every range check.
local _issecretvalue = issecretvalue or function() return false end

local SP_FONT              = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"
local FONT_SIZE_MULTIPLIER = 2
local RANGE_UPDATE_THROTTLE = 0.1
local rangeUpdateElapsed   = 0

-- ============================================================
-- DB helper
--
-- Kept as a file-local rather than folded into ModuleMixin:GetDB(): GetColor()
-- below is a plain local function with no `self` to reach the module through.
-- ============================================================
local function GetDB()
    return SP.GetDB().combatCross
end

-- ============================================================
-- Spec → range ability tables
-- ============================================================

-- Melee specs: specID → a short-range spell for IsSpellInRange
local MELEE_RANGE_ABILITIES = {
    -- Melee DPS
    [71]  = 6552,   -- Arms Warrior: Pummel
    [72]  = 6552,   -- Fury Warrior: Pummel
    [251] = 49020,  -- Frost DK: Obliterate
    [252] = 49998,  -- Unholy DK: Death Strike
    [577] = 162794, -- Havoc DH: Chaos Strike
    [103] = 22568,  -- Feral Druid: Ferocious Bite
    [255] = 186270, -- Survival Hunter: Raptor Strike
    [259] = 1329,   -- Assassination Rogue: Mutilate
    [260] = 193315, -- Outlaw Rogue: Sinister Strike
    [261] = 53,     -- Subtlety Rogue: Backstab
    [263] = 17364,  -- Enhancement Shaman: Stormstrike
    [269] = 100780, -- Windwalker Monk: Tiger Palm
    [70]  = 96231,  -- Retribution Paladin: Rebuke
    -- Tanks
    [73]  = 6552,   -- Protection Warrior: Pummel
    [250] = 49998,  -- Blood DK: Death Strike
    [581] = 203782, -- Vengeance DH: Shear (5 yd). 225921 was Fracture, a 20 yd
                    -- talent spell -- wrong range, and nil when untalented.
                    -- FindSpellOverrideByID picks up Fracture automatically.
    [104] = 33917,  -- Guardian Druid: Mangle. Was 22568 = Ferocious Bite, a
                    -- Cat-Form-only finisher -- always nil in Bear Form.
    [268] = 100780, -- Brewmaster Monk: Tiger Palm
    [66]  = 96231,  -- Protection Paladin: Rebuke. Crusader Strike (35395) is
                    -- replaced for Prot, and both replacements (Hammer of the
                    -- Righteous 53595 / Blessed Hammer 204019) are talents on a
                    -- choice node -- either one is nil for half the players.
                    -- Rebuke is baseline melee for every Paladin and is already
                    -- what spec 70 uses.
}

-- Ranged DPS: specID → a long-range spell for IsSpellInRange
local RANGED_RANGE_ABILITIES = {
    [102]  = 5176,   -- Balance Druid: Wrath (40yd)
    [1467] = 361469, -- Devastation Evoker: Living Flame (25yd)
    [1473] = 361469, -- Augmentation Evoker: Living Flame (25yd)
    [253]  = 77767,  -- Beast Mastery Hunter: Cobra Shot (40yd)
    [254]  = 185358, -- Marksmanship Hunter: Arcane Shot (40yd)
    [62]   = 30451,  -- Arcane Mage: Arcane Blast (40yd)
    [63]   = 133,    -- Fire Mage: Fireball (40yd)
    [64]   = 116,    -- Frost Mage: Frostbolt (40yd)
    [258]  = 589,    -- Shadow Priest: Shadow Word: Pain (40yd)
    [262]  = 188196, -- Elemental Shaman: Lightning Bolt (40yd)
    [265]  = 686,    -- Affliction Warlock: Shadow Bolt (40yd)
    [266]  = 686,    -- Demonology Warlock: Shadow Bolt (40yd)
    [267]  = 29722,  -- Destruction Warlock: Incinerate (40yd)
    [1480] = 473662, -- Devourer Demon Hunter: Consume (25yd)
}

-- ============================================================
-- Module state
-- ============================================================
CC.frame          = nil
CC.text           = nil
CC.previewActive  = false
CC.combatActive   = false
CC.rangeAbility   = nil
CC.specType       = nil
CC.lastInRange    = nil
CC.onUpdateActive = false

-- ============================================================
-- Color helper
-- ============================================================
local function GetColor()
    local db = GetDB()
    local r, g, b = SP.GetColorFromSource(db.colorSource or "theme", db.color)
    return r, g, b, 1
end

-- ============================================================
-- Range ability resolution
-- ============================================================
function CC:ResolveRangeAbility()
    local specIndex = GetSpecialization()
    if not specIndex then
        self.rangeAbility = nil
        self.specType     = nil
        return
    end
    local specID = select(1, GetSpecializationInfo(specIndex))
    if not specID then
        self.rangeAbility = nil
        self.specType     = nil
        return
    end
    if MELEE_RANGE_ABILITIES[specID] then
        self.rangeAbility = MELEE_RANGE_ABILITIES[specID]
        self.specType     = "melee"
    elseif RANGED_RANGE_ABILITIES[specID] then
        self.rangeAbility = RANGED_RANGE_ABILITIES[specID]
        self.specType     = "ranged"
    else
        self.rangeAbility = nil
        self.specType     = nil
    end
end

-- ============================================================
-- Range color
-- ============================================================
function CC:UpdateRangeColor()
    if not self.text then return end

    -- No target → reset to default color once if we were out-of-range
    if not UnitExists("target") then
        if self.lastInRange == false then
            self.lastInRange = nil
            local r, g, b, a = GetColor()
            self.text:SetTextColor(r, g, b, a)
        end
        return
    end

    -- Resolve talent/hero-spec overrides: several specs replace their base
    -- ability, and IsSpellInRange answers nil for a spell not in the spellbook,
    -- which silently disabled range colouring for those specs.
    local spellID = self.rangeAbility
    if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
        spellID = C_SpellBook.FindSpellOverrideByID(spellID) or spellID
    end

    local inRange = C_Spell.IsSpellInRange(spellID, "target")

    -- IsSpellInRange returns a SECRET VALUE inside instanced content. Comparing
    -- one taints execution and the taint propagates into Blizzard frames --
    -- the same failure that broke Blizzard_CooldownViewer via isOnGCD. This
    -- runs 10x/second in combat, so it must be checked before any comparison.
    --
    -- Treated exactly like "indeterminate": reset to the default colour once.
    -- Bailing out instead would freeze the cross on whatever colour it happened
    -- to have when you zoned in -- permanently red if you entered out of range.
    if _issecretvalue(inRange) or inRange == nil then
        if self.lastInRange ~= nil then
            self.lastInRange = nil
            local r, g, b, a = GetColor()
            self.text:SetTextColor(r, g, b, a)
        end
        return
    end

    local nowInRange = (inRange == true)
    if nowInRange == self.lastInRange then return end
    self.lastInRange = nowInRange

    if nowInRange then
        local r, g, b, a = GetColor()
        self.text:SetTextColor(r, g, b, a)
    else
        local db = GetDB()
        local c  = db.outOfRangeColor or { 1, 0, 0, 1 }
        self.text:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end
end

function CC:ShouldRunRangeUpdate()
    if not self.combatActive then return false end
    if not self.rangeAbility or not self.specType then return false end
    local db = GetDB()
    if self.specType == "melee"  and not db.rangeColorMeleeEnabled  then return false end
    if self.specType == "ranged" and not db.rangeColorRangedEnabled then return false end
    return true
end

function CC:UpdateOnUpdateState()
    if not self.frame then return end

    if self:ShouldRunRangeUpdate() then
        if not self.onUpdateActive then
            self.onUpdateActive  = true
            rangeUpdateElapsed   = 0
            self.frame:SetScript("OnUpdate", function(_, elapsed) self:OnUpdate(elapsed) end)
        end
    else
        if self.onUpdateActive then
            self.onUpdateActive = false
            self.frame:SetScript("OnUpdate", nil)
            -- Reset to default color when range check is turned off
            if self.text then
                local r, g, b, a = GetColor()
                self.text:SetTextColor(r, g, b, a)
            end
            self.lastInRange = nil
        end
    end
end

function CC:OnUpdate(elapsed)
    rangeUpdateElapsed = rangeUpdateElapsed + elapsed
    if rangeUpdateElapsed < RANGE_UPDATE_THROTTLE then return end
    rangeUpdateElapsed = 0
    self:UpdateRangeColor()
end

-- ============================================================
-- Frame creation
-- ============================================================
function CC:CreateCrossFrame()
    if self.frame then return end
    local db = GetDB()

    local f = CreateFrame("Frame", "SP_CombatCrossFrame", UIParent)
    f:SetSize(60, 60)
    f:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 0)
    f:SetFrameStrata(db.frameStrata or "HIGH")
    f:SetFrameLevel(100)
    f:EnableMouse(false)
    f:Hide()

    local fontSize  = (db.thickness or 14) * FONT_SIZE_MULTIPLIER
    local fontFlags = (db.outline ~= false) and "SOFTOUTLINE" or ""

    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    text:SetFont(SP_FONT, fontSize, fontFlags)
    text:SetText("+")

    local r, g, b, a = GetColor()
    text:SetTextColor(r, g, b, a)

    self.frame = f
    self.text  = text
end

-- ============================================================
-- Position
-- ============================================================
function CC:ApplyPosition()
    if not self.frame then return end
    local db = GetDB()
    self.frame:ClearAllPoints()
    local anchorFrom  = db.anchorFrom  or "CENTER"
    local anchorTo    = db.anchorTo    or "CENTER"
    local anchorFrame = _G[db.anchorFrame or "UIParent"] or UIParent
    self.frame:SetPoint(anchorFrom, anchorFrame, anchorTo, db.x or 0, db.y or 0)
    self.frame:SetFrameStrata(db.frameStrata or "HIGH")
end

-- ============================================================
-- Apply settings (called from GUI on any change)
-- ============================================================
function CC:ApplySettings()
    if not self.frame or not self.text then return end
    local db = GetDB()

    local fontSize  = (db.thickness or 14) * FONT_SIZE_MULTIPLIER
    local fontFlags = (db.outline ~= false) and "SOFTOUTLINE" or ""
    self.text:SetFont(SP_FONT, fontSize, fontFlags)

    local r, g, b, a = GetColor()
    self.text:SetTextColor(r, g, b, a)

    -- Force range re-evaluation on next update cycle
    self.lastInRange = nil

    self:ApplyPosition()
end

-- ============================================================
-- Show / Hide
-- ============================================================
function CC:ShowCross(isPreview)
    if not self.frame then
        self:CreateCrossFrame()
        self:ApplySettings()
    end
    if not self.frame then return end

    if isPreview then
        self.previewActive = true
    else
        self.combatActive = true
    end

    if self.previewActive or self.combatActive then
        if not self.frame:IsShown() then
            self.frame:Show()
            self.frame:SetAlpha(0)
            UIFrameFadeIn(self.frame, 0.3, 0, 1)
        end
    end
end

function CC:HideCross(isPreview)
    if not self.frame then return end

    if isPreview then
        self.previewActive = false
    else
        self.combatActive = false
        -- Restore normal color so the next combat entry starts clean
        if self.text then
            local r, g, b, a = GetColor()
            self.text:SetTextColor(r, g, b, a)
        end
        self.lastInRange = nil
    end

    if not self.previewActive and not self.combatActive then
        self.frame:Hide()
    end
end

-- ============================================================
-- Preview (called from GUI)
-- ============================================================
function CC:ShowPreview()
    if InCombatLockdown() then return end
    self:ShowCross(true)
end

function CC:HidePreview()
    if InCombatLockdown() then return end
    if not self.previewActive then return end
    self:HideCross(true)
end

-- ============================================================
-- Event: spec changed
-- ============================================================
function CC:OnSpecChanged()
    self:ResolveRangeAbility()
    self.lastInRange = nil
    self:UpdateOnUpdateState()
end

-- ============================================================
-- Combat events
-- ============================================================
function CC:OnEnterCombat()
    if not GetDB().enabled then return end
    self:ShowCross(false)
    self:UpdateOnUpdateState()
end

function CC:OnExitCombat()
    if not GetDB().enabled then return end
    self:HideCross(false)
    self:UpdateOnUpdateState()
end

-- ============================================================
-- Activate / Deactivate
--
-- Called by the GUI enable toggle and by ModuleMixin:Refresh(). Refresh,
-- OnEnable and OnDisable all come from ModuleMixin -- see Core/Module.lua.
-- ============================================================
function CC:Activate()
    local db = GetDB()
    if not (db and db.enabled) then return end

    self:CreateCrossFrame()
    self:ApplySettings()
    self:ResolveRangeAbility()

    self:RegisterEvent("PLAYER_REGEN_DISABLED",         "OnEnterCombat")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",          "OnExitCombat")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
end

function CC:Deactivate()
    self:UnregisterAllEvents()
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
    self.rangeAbility   = nil
    self.specType       = nil
    self.lastInRange    = nil
    self.onUpdateActive = false
    self.combatActive   = false
    self.previewActive  = false
end
