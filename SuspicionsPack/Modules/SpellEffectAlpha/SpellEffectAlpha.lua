-- SuspicionsPack — SpellEffectAlpha Module
-- Sets spellActivationOverlayOpacity CVar per specialization.
-- Per-spec overrides: 0 = hidden, 100 = full opacity.
local SP = SuspicionsPack

local SEA = SP:NewSPModule("SpellEffectAlpha", "spellEffectAlpha")
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

-- Spec icon texture file IDs
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
-- Kept as a file-scope local: ApplyNow is a dot function with no `self`, so it
-- cannot reach the mixin's self:GetDB().
-- ============================================================
local function GetDB()
    return SP.GetDB().spellEffectAlpha
end

-- True while our values are the ones in the CVars. Without it, Deactivate would
-- write "1"/"1" at every login for players who have the module switched off --
-- exactly the bug the db.enabled gate below was added to fix.
local _applied = false

-- Reported: the opacity is wrong after login and only takes hold once the
-- options window is opened and a slider nudged. Moving a slider calls the SAME
-- ApplyAlpha as login does, so nothing about the writing is broken -- what
-- differs is only WHEN it runs. Two things can make the login call a no-op, and
-- both are handled below because the symptom does not distinguish them:
--
--   1. THE SPEC IS NOT KNOWN YET. Activate runs at PLAYER_LOGIN, and the spec
--      APIs answer nil that early. The old code turned that into `specID == 0`
--      and returned in silence, with nothing left to try again -- so the value
--      stayed unapplied for the whole session. Handled by RETRYING rather than
--      giving up (see RETRY_DELAYS).
--
--   2. THE ENGINE OVERWRITES US. The client runs its own CVar restore during
--      login; a value written just before it lands is discarded without a word.
--      Core.lua already carries this knowledge for preloadWorldNonCriticalObjects
--      ("Re-apply CVars that WoW resets on every login"), and this module never
--      got the same treatment. Handled by READING THE CVAR BACK and writing once
--      more if it did not stick.
--
-- Resolved defensively, the way FocusTargetMarker does it: C_SpecializationInfo
-- first, the globals as a fallback. Note the explicit range test -- 0 is TRUTHY
-- in Lua and is exactly what these return when no spec is chosen, so `index and`
-- would sail straight past it.
local function ResolveSpecID()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
                    or _G.GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo)
                    or _G.GetSpecializationInfo
    if not (getSpec and getInfo) then return nil end

    local index = getSpec()
    if type(index) ~= "number" or index < 1 then return nil end

    local specID = getInfo(index)
    if type(specID) ~= "number" or specID < 1 then return nil end
    return specID
end

local function GetCVarValue(name)
    local get = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
    return get and get(name) or nil
end

-- Bounded, and deliberately not a ticker: if the spec has not resolved fifteen
-- seconds into a session it is not going to, and a poll that never stops is a
-- worse bug than the one it was covering.
local RETRY_DELAYS = { 1, 2, 4, 8 }

local ApplyAlpha

-- Confirm the write actually took, once. `verified` stops this from recursing:
-- the follow-up write is a last word, not a loop, because a CVar the client
-- keeps refusing must not turn into an argument that runs all session.
local function VerifyApplied(wanted)
    C_Timer.After(2, function()
        if not _applied then return end            -- switched off in the meantime
        local got = tonumber(GetCVarValue("spellActivationOverlayOpacity"))
        if got and math.abs(got - wanted) <= 0.005 then return end
        ApplyAlpha(nil, true)
    end)
end

-- attempt:  how many times the spec lookup has already come back empty.
-- verified: true when this call IS the second-chance write, so it does not
--           schedule another readback.
function ApplyAlpha(attempt, verified)
    local db = GetDB()
    -- Never write a CVar while switched off. AceAddon enables every module at
    -- login regardless of the user's setting, so an ungated write here silently
    -- overwrote the player's own Blizzard CVars every session.
    if not db or not db.enabled then return end

    local specID = ResolveSpecID()
    if not specID then
        attempt = (attempt or 0) + 1
        local delay = RETRY_DELAYS[attempt]
        if delay then
            C_Timer.After(delay, function() ApplyAlpha(attempt, verified) end)
        end
        return
    end

    local val = (db.specs and db.specs[specID]) or db.globalDefault or 100
    val = math.max(0, math.min(100, val))
    local finalVal = val / 100
    -- SetCVar expects strings (WoW Midnight compatibility)
    SetCVar("spellActivationOverlayOpacity", tostring(finalVal))
    SetCVar("displaySpellActivationOverlays", finalVal > 0 and "1" or "0")
    _applied = true

    if not verified then VerifyApplied(finalVal) end
end

local function RestoreAlpha()
    if not _applied then return end
    _applied = false
    -- Restore defaults. Strings, not numbers: SetCVar expects strings on
    -- Midnight, and the rest of this file already passes them that way.
    SetCVar("spellActivationOverlayOpacity", "1")
    SetCVar("displaySpellActivationOverlays", "1")
end

-- ============================================================
-- Module lifecycle
-- OnEnable / OnDisable / Refresh come from SP.ModuleMixin. PLAYER_LOGIN is
-- deliberately NOT registered here: the mixin already owns that event for its
-- own deferral, and AceEvent keeps only one handler per event per object.
-- ============================================================
function SEA:Activate()
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
    -- PLAYER_ENTERING_WORLD arrives AFTER the engine's own login CVar restore,
    -- which is the whole point: the write from Activate can be thrown away, the
    -- one from here cannot be. Two SetCVar calls per loading screen.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnSpecChanged")
    ApplyAlpha()
end

function SEA:Deactivate()
    self:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    RestoreAlpha()
end

function SEA:OnSpecChanged()
    -- No arguments forwarded on purpose: ApplyAlpha's first parameter is the
    -- retry counter, and handing it an event name would index RETRY_DELAYS with
    -- a string and quietly disable every retry.
    ApplyAlpha()
end

-- ============================================================
-- Public API
-- ============================================================
-- Called from GUI when a per-spec value changes
function SEA.ApplyNow()
    ApplyAlpha()
end
