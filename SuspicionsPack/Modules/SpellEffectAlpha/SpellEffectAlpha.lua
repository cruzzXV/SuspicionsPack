-- SuspicionsPack — SpellEffectAlpha Module
-- Forked from ExwindTools "ExClass.SpellEffectAlpha".
-- Sets spellActivationOverlayOpacity CVar per specialization.
-- Per-spec overrides: 0 = hidden, 100 = full opacity.
local SP = SuspicionsPack

local SEA = SP:NewModule("SpellEffectAlpha", "AceEvent-3.0")
SP.SpellEffectAlpha = SEA

-- ============================================================
-- Spec data — display name for each specID (for GUI labels)
-- ============================================================
SEA.SpecNames = {
    -- Death Knight
    [250] = "Blood DK",       [251] = "Frost DK",       [252] = "Unholy DK",
    -- Demon Hunter
    [577] = "Havoc DH",       [581] = "Vengeance DH",   [1480] = "Devourer DH",
    -- Druid
    [102] = "Balance Druid",  [103] = "Feral Druid",    [104] = "Guardian Druid", [105] = "Resto Druid",
    -- Evoker
    [1467] = "Devastation Evoker", [1468] = "Preservation Evoker", [1473] = "Augmentation Evoker",
    -- Hunter
    [253] = "Beast Mastery Hunter", [254] = "Marksmanship Hunter", [255] = "Survival Hunter",
    -- Mage
    [62] = "Arcane Mage",     [63] = "Fire Mage",       [64] = "Frost Mage",
    -- Monk
    [268] = "Brewmaster Monk",[269] = "Windwalker Monk",[270] = "Mistweaver Monk",
    -- Paladin
    [65] = "Holy Paladin",    [66] = "Protection Paladin",[70] = "Retribution Paladin",
    -- Priest
    [256] = "Discipline Priest",[257] = "Holy Priest",  [258] = "Shadow Priest",
    -- Rogue
    [259] = "Assassination Rogue",[260] = "Outlaw Rogue",[261] = "Subtlety Rogue",
    -- Shaman
    [262] = "Elemental Shaman",[263] = "Enhancement Shaman",[264] = "Restoration Shaman",
    -- Warlock
    [265] = "Affliction Warlock",[266] = "Demonology Warlock",[267] = "Destruction Warlock",
    -- Warrior
    [71] = "Arms Warrior",    [72] = "Fury Warrior",    [73] = "Protection Warrior",
}

-- Spec icon texture file IDs (same source as ExwindTools, hardcoded for reliability)
SEA.SpecIcons = {
    -- Death Knight
    [250] = 135770,  [251] = 135773,  [252] = 135775,
    -- Demon Hunter
    [577] = 1247264, [581] = 1247265, [1480] = 7455385,
    -- Druid
    [102] = 136096,  [103] = 132115,  [104] = 132276,  [105] = 136041,
    -- Evoker
    [1467] = 4511811,[1468] = 4511812,[1473] = 5198700,
    -- Hunter
    [253] = 461112,  [254] = 236179,  [255] = 461113,
    -- Mage
    [62] = 135932,   [63] = 135810,   [64] = 135846,
    -- Monk
    [268] = 608951,  [269] = 608953,  [270] = 608952,
    -- Paladin
    [65] = 135920,   [66] = 236264,   [70] = 135873,
    -- Priest
    [256] = 135940,  [257] = 237542,  [258] = 136207,
    -- Rogue
    [259] = 236270,  [260] = 236286,  [261] = 132320,
    -- Shaman
    [262] = 136048,  [263] = 237581,  [264] = 136052,
    -- Warlock
    [265] = 136145,  [266] = 136172,  [267] = 136186,
    -- Warrior
    [71] = 132355,   [72] = 132347,   [73] = 132341,
}

-- ============================================================
-- Helpers
-- ============================================================
local function GetDB()
    return SP.GetDB().spellEffectAlpha
end

local function ApplyAlpha()
    local db = GetDB()
    if not db or not db.enabled then
        -- When disabled, restore to full opacity
        SetCVar("spellActivationOverlayOpacity", "1")
        SetCVar("displaySpellActivationOverlays", "1")
        return
    end

    -- ExwindTools pattern: safe spec ID resolution
    local specIndex = GetSpecialization and GetSpecialization() or 0
    local specID = (specIndex and specIndex > 0 and GetSpecializationInfo)
        and GetSpecializationInfo(specIndex) or 0

    if not specID or specID == 0 then return end

    local val = (db.specs and db.specs[specID]) or db.globalDefault or 100
    val = math.max(0, math.min(100, val))
    local finalVal = val / 100
    -- SetCVar expects strings (WoW Midnight compatibility)
    SetCVar("spellActivationOverlayOpacity", tostring(finalVal))
    SetCVar("displaySpellActivationOverlays", finalVal > 0 and "1" or "0")
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function SEA:OnEnable()
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_LOGIN", "OnSpecChanged")
    ApplyAlpha()
end

function SEA:OnDisable()
    self:UnregisterAllEvents()
    -- Restore defaults
    SetCVar("spellActivationOverlayOpacity", 1)
    SetCVar("displaySpellActivationOverlays", 1)
end

function SEA:OnSpecChanged()
    ApplyAlpha()
end

-- ============================================================
-- Public API
-- ============================================================
function SEA.Refresh()
    local db = GetDB()
    local mod = SP.SpellEffectAlpha
    if db and db.enabled then
        if not mod:IsEnabled() then mod:Enable() end
    else
        if mod:IsEnabled() then mod:Disable() end
    end
    ApplyAlpha()
end

-- Called from GUI when a per-spec value changes
function SEA.ApplyNow()
    ApplyAlpha()
end
