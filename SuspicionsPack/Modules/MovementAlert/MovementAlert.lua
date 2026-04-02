-- SuspicionsPack - MovementAlert.lua
-- Displays a text + cooldown when your movement ability is on CD.
-- Also tracks "Time Spiral" (shows free-movement countdown).
-- Forked from ItruliaQoL's MovementAlert module.
-- Enhanced with charge tracking, buff-active detection, alias system,
-- issecretvalue handling, GetOverrideSpell, and spellOverrides.

local SP = SuspicionsPack

local MA = SP:NewModule("MovementAlert", "AceEvent-3.0")
SP.MovementAlert = MA

-- ============================================================
-- Locals
-- ============================================================
local CreateFrame        = CreateFrame
local GetTime            = GetTime
local GetSpecialization  = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local UnitClass          = UnitClass
local InCombatLockdown   = InCombatLockdown
local C_Spell            = C_Spell
local C_Timer            = C_Timer
local C_UnitAuras        = C_UnitAuras
local PlaySoundFile      = PlaySoundFile
local UIParent           = UIParent

local SP_FONT = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"

local FONT_FACES = {
    ["Expressway"]    = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf",
    ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"]  = "Fonts\\ARIALN.TTF",
    ["Morpheus"]      = "Fonts\\MORPHEUS.TTF",
    ["Skurri"]        = "Fonts\\SKURRI.TTF",
    ["Damage"]        = "Fonts\\DAMAGE.TTF",
    ["Ambiguity"]     = "Fonts\\2002.TTF",
    ["Nimrod MT"]     = "Fonts\\NIMROD.TTF",
}
MA.FontFaceOrder = {
    "Expressway", "Friz Quadrata", "Arial Narrow", "Morpheus",
    "Skurri", "Damage", "Ambiguity", "Nimrod MT",
}

local function GetFontPath(name)
    return FONT_FACES[name] or SP_FONT
end

-- ============================================================
-- DB helper
-- ============================================================
local function GetDB()
    return SP.GetDB().movementAlert
end

-- ============================================================
-- issecretvalue — Blizzard anti-cheat obfuscation check
-- ============================================================
local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

-- ============================================================
-- Movement abilities per class/spec
-- Exposed so the GUI can iterate it to build spell toggles.
-- ============================================================
MA.MovementAbilities = nil  -- assigned after table definition

local MOVEMENT_ABILITIES = {
    DEATHKNIGHT = {
        [250] = {48265},
        [251] = {48265},
        [252] = {48265, 444010, 444347},  -- TWW: Ghoul's Leap, Bone Shield
    },
    DEMONHUNTER = {
        [577]  = {195072},
        [581]  = {189110},
        [1480] = {1234796},
        -- Talent gating: if talent active, suppress those spells from the time-spiral glow
        filter = {
            [427640] = {198793, 370965, 195072},
            [427794] = {195072},
        },
    },
    DRUID = {
        [102] = {102401, 252216, 1850, 102417},
        [103] = {102401, 252216, 1850, 102417},
        [104] = {102401, 252216, 106898, 1850, 102417},
        [105] = {102401, 252216, 1850, 102417},
    },
    EVOKER  = { [1467] = {358267}, [1468] = {358267}, [1473] = {358267} },
    HUNTER  = { [253] = {186257, 781}, [254] = {186257, 781}, [255] = {186257, 781} },
    MAGE    = { [62] = {212653, 1953}, [63] = {212653, 1953}, [64] = {212653, 1953} },
    MONK    = {
        [268] = {115008, 109132, 119085, 361138},
        [269] = {109132, 119085, 361138},
        [270] = {109132, 119085, 361138},
    },
    PALADIN = { [65] = {190784}, [66] = {190784}, [70] = {190784} },
    PRIEST  = { [256] = {121536, 73325}, [257] = {121536, 73325}, [258] = {121536, 73325} },
    ROGUE   = { [259] = {36554, 2983}, [260] = {195457, 2983}, [261] = {36554, 2983} },
    SHAMAN  = {
        [262] = {79206, 90328, 192063, 58875},
        [263] = {90328, 192063, 58875},
        [264] = {79206, 90328, 192063, 58875},
    },
    WARLOCK = {
        [265] = {48020, 111400},
        [266] = {48020, 111400},
        [267] = {48020, 111400},
        filter = { [385899] = {385899} },
    },
    WARRIOR = { [71] = {6544}, [72] = {6544}, [73] = {6544} },
}
MA.MovementAbilities = MOVEMENT_ABILITIES

-- ============================================================
-- Buff-triggered display
-- Show when the BUFF is active, not when the spell is on CD.
-- ============================================================
local BUFF_ACTIVE_SPELLS = {
    [111400] = "Burning Rush Active!",   -- Warlock: Burning Rush
}

-- ============================================================
-- Spell alias groups
-- Different spell IDs that share the same category cooldown.
-- e.g. Druid Wild Charge differs per form.
-- ============================================================
local SPELL_ALIAS_GROUPS = {
    { 102401, 16979, 102417, 252216 },   -- Wild Charge (all forms) + Tiger Dash
    { 106898, 77761 },                    -- Wild Charge (Aquatic) + Aquatic form
}

-- Fallback cooldown durations for category-cooldown spells (seconds)
local SPELL_CATEGORY_DURATION = {
    [102401] = 15, [16979] = 15, [102417] = 15, [252216] = 15,
    [1850]   = 18,
    [106898] = 120, [77761] = 120,
}

-- Build reverse alias lookup table at load time
local SPELL_ALIAS_MAP = {}
do
    for _, group in ipairs(SPELL_ALIAS_GROUPS) do
        for _, id in ipairs(group) do
            SPELL_ALIAS_MAP[id] = group
        end
        -- Propagate known durations to all aliases in the group
        for _, id in ipairs(group) do
            if not SPELL_CATEGORY_DURATION[id] then
                for _, other in ipairs(group) do
                    if SPELL_CATEGORY_DURATION[other] then
                        SPELL_CATEGORY_DURATION[id] = SPELL_CATEGORY_DURATION[other]
                        break
                    end
                end
            end
        end
    end
end

local function GetKnownCategoryDuration(spellId)
    if SPELL_CATEGORY_DURATION[spellId] then return SPELL_CATEGORY_DURATION[spellId] end
    local group = SPELL_ALIAS_MAP[spellId]
    if group then
        for _, id in ipairs(group) do
            if SPELL_CATEGORY_DURATION[id] then return SPELL_CATEGORY_DURATION[id] end
        end
    end
    return 0
end

-- ============================================================
-- Spells that trigger the Time Spiral countdown display
-- ============================================================
local TIME_SPIRAL_ABILITIES = {
    [48265]   = true,  -- Death's Advance (DK)
    [195072]  = true,  -- Fel Rush (DH)
    [189110]  = true,  -- Infernal Strike (DH)
    [1234796] = true,  -- Shift (DH Havoc new)
    [1850]    = true,  -- Dash (Druid)
    [252216]  = true,  -- Tiger Dash (Druid)
    [358267]  = true,  -- Hover (Evoker)
    [186257]  = true,  -- Aspect of the Cheetah (Hunter)
    [212653]  = true,  -- Shimmer (Mage)
    [1953]    = true,  -- Blink (Mage)
    [119085]  = true,  -- Chi Torpedo (Monk)
    [361138]  = true,  -- Roll (Monk)
    [190784]  = true,  -- Divine Steed (Paladin)
    [2983]    = true,  -- Sprint (Rogue)
    [192063]  = true,  -- Gust of Wind (Shaman)
    [58875]   = true,  -- Spirit Walk (Shaman)
    [79206]   = true,  -- Spiritwalker's Grace (Shaman)
    [48020]   = true,  -- Demonic Circle: Teleport (Warlock)
    [6544]    = true,  -- Heroic Leap (Warrior)
}

-- ============================================================
-- Glow-ignore: spells that fire a glow before the actual cast
-- ============================================================
local GLOW_IGNORE_SPECS = {
    DEMONHUNTER = {
        [577] = {
            { talent = 427640, spellId = 370965, delay = 1 }, -- Inertia / The Hunt
            { talent = 427640, spellId = 198793 },             -- Inertia / Vengeful Retreat
            { talent = 427794, spellId = 195072 },             -- Dash of Chaos / Fel Rush
        },
    },
    WARLOCK = {
        [265] = { { talent = 385899, spellId = 385899 } }, -- Soulburn
        [266] = { { talent = 385899, spellId = 385899 } },
        [267] = { { talent = 385899, spellId = 385899 } },
    },
}

-- (OWN_GCD_SPELLS removed — the ignoreMovementCd mechanism caused the 0.5s display
--  lag for charge spells like DH Transfer.  The hasCharges + isOnGCD condition below
--  handles the animation window cleanly without an artificial timer suppression.)

-- ============================================================
-- Safe API wrappers (handle issecretvalue / anti-cheat)
-- ============================================================
local knownChargeSpells = {}  -- cache when API returns secret values

local function SafeGetChargeInfo(spellId)
    local chargeInfo = C_Spell.GetSpellCharges(spellId)
    if not chargeInfo then
        local cached = knownChargeSpells[spellId]
        if cached then return true, cached.maxCh, cached.rechDur end
        return false, 1, 0
    end
    local m = chargeInfo.maxCharges or 1
    local r = chargeInfo.cooldownDuration or 0
    if IsSecret(m) or IsSecret(r) then
        local cached = knownChargeSpells[spellId]
        if cached then return true, cached.maxCh, cached.rechDur end
        return false, 1, 0
    end
    if m > 1 then
        knownChargeSpells[spellId] = { maxCh = m, rechDur = r }
        return true, m, r
    end
    local cached = knownChargeSpells[spellId]
    if cached then return true, cached.maxCh, cached.rechDur end
    return false, m, r
end

local function SafeGetBaseDuration(spellId)
    local cdInfo = C_Spell.GetSpellCooldown(spellId)
    if cdInfo and cdInfo.duration then
        local d = cdInfo.duration
        if not IsSecret(d) and d > 1.5 then return d end
    end
    return 0
end

-- ============================================================
-- Cast filter (DH talent gating for Time Spiral glow suppression)
-- ============================================================
local castFilters = {}
local castFilterExpiry = 0

local function RefreshCastFilters()
    for k in pairs(castFilters) do castFilters[k] = nil end
    local _, class = UnitClass("player")
    local classData = MOVEMENT_ABILITIES[class]
    if not classData or not classData.filter then return end
    for talentId, spells in pairs(classData.filter) do
        if IsPlayerSpell(talentId) then
            for _, id in ipairs(spells) do
                castFilters[id] = true
            end
        end
    end
end

-- ============================================================
-- Spell list builder (replaces GetMovementSpell)
-- Returns a list of entry tables for the player's spec.
-- Each entry: { spellId, baseSpellId, spellName, customText,
--              isChargeSpell, maxCharges, rechargeDuration,
--              baseDuration, checkType }
-- checkType == "buffActive" for BUFF_ACTIVE_SPELLS entries.
-- ============================================================
local trackedSpellSet = {}  -- [castId] = canonicalId, alias-aware

local function BuildMovementSpellList()
    local _, class = UnitClass("player")
    local spec = GetSpecialization()
    if not spec then return {} end
    local specId = select(1, GetSpecializationInfo(spec))
    local classData = MOVEMENT_ABILITIES[class]
    if not classData then return {} end
    local specSpells = classData[specId]
    if not specSpells then return {} end

    local db = GetDB()
    local disabled  = db.disabledSpells  or {}
    local overrides = db.spellOverrides  or {}

    local result = {}
    local seen   = {}

    for _, spellId in ipairs(specSpells) do
        if not seen[spellId] and not disabled[spellId] then
            local override = overrides[spellId]
            if not override or override.enabled ~= false then
                if IsPlayerSpell(spellId) then
                    -- Attempt to resolve talent-swapped ID, but only if the override
                    -- spell actually has accessible spell info.  If GetOverrideSpell
                    -- returns an ID we can't resolve (e.g. a different-race or
                    -- different-form variant), fall back to the original spellId so
                    -- the spell is never silently dropped from the list.
                    local displayId = spellId
                    if C_Spell.GetOverrideSpell then
                        local ok, oid = pcall(C_Spell.GetOverrideSpell, spellId)
                        if ok and oid and oid > 0 and oid ~= spellId then
                            local overrideInfo = C_Spell.GetSpellInfo(oid)
                            if overrideInfo then
                                displayId = oid
                            end
                        end
                    end

                    if not seen[displayId] then
                        seen[spellId]   = true
                        seen[displayId] = true
                        local info = C_Spell.GetSpellInfo(displayId)
                        -- If displayId somehow still has no info, use original
                        if not info and displayId ~= spellId then
                            displayId = spellId
                            info = C_Spell.GetSpellInfo(displayId)
                        end
                        if info then
                            local baseId = (displayId ~= spellId) and spellId or nil

                            if BUFF_ACTIVE_SPELLS[displayId] then
                                -- Buff-active entry: show when buff is present, not on CD
                                table.insert(result, {
                                    spellId    = displayId,
                                    spellName  = info.name,
                                    customText = override and override.customText ~= "" and override.customText
                                                 or BUFF_ACTIVE_SPELLS[displayId],
                                    checkType  = "buffActive",
                                })
                            else
                                local isCharge, maxCh, rechDur = SafeGetChargeInfo(displayId)
                                if not isCharge and baseId then
                                    isCharge, maxCh, rechDur = SafeGetChargeInfo(baseId)
                                end
                                local baseDur = SafeGetBaseDuration(displayId)
                                if baseDur <= 0 and baseId then baseDur = SafeGetBaseDuration(baseId) end
                                if baseDur <= 0 then baseDur = GetKnownCategoryDuration(displayId) end
                                if baseDur <= 0 and baseId then baseDur = GetKnownCategoryDuration(baseId) end

                                table.insert(result, {
                                    spellId          = displayId,
                                    baseSpellId      = baseId,
                                    spellName        = info.name,
                                    customText       = override and override.customText ~= ""
                                                       and override.customText or nil,
                                    isChargeSpell    = isCharge,
                                    maxCharges       = maxCh,
                                    rechargeDuration = rechDur,
                                    baseDuration     = isCharge and rechDur or baseDur,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    -- spellOverrides: user-defined custom spells (not in the built-in table)
    for spellId, override in pairs(overrides) do
        if not seen[spellId] and not disabled[spellId] and override.enabled ~= false then
            if IsPlayerSpell(spellId) then
                seen[spellId] = true
                local info = C_Spell.GetSpellInfo(spellId)
                if info then
                    local isCharge, maxCh, rechDur = SafeGetChargeInfo(spellId)
                    local baseDur = SafeGetBaseDuration(spellId)
                    if baseDur <= 0 then baseDur = GetKnownCategoryDuration(spellId) end
                    table.insert(result, {
                        spellId          = spellId,
                        spellName        = info.name,
                        customText       = override.customText ~= "" and override.customText or nil,
                        isChargeSpell    = isCharge,
                        maxCharges       = maxCh,
                        rechargeDuration = rechDur,
                        baseDuration     = isCharge and rechDur or baseDur,
                    })
                end
            end
        end
    end

    return result
end

local function RebuildTrackedSpellSet(spellList)
    for k in pairs(trackedSpellSet) do trackedSpellSet[k] = nil end
    for _, entry in ipairs(spellList) do
        trackedSpellSet[entry.spellId] = entry.spellId
        if entry.baseSpellId then
            trackedSpellSet[entry.baseSpellId] = entry.spellId
        end
        -- Register all aliases so UNIT_SPELLCAST_SENT can find them
        local group = SPELL_ALIAS_MAP[entry.spellId]
        if group then
            for _, aliasId in ipairs(group) do
                if not trackedSpellSet[aliasId] then
                    trackedSpellSet[aliasId] = entry.spellId
                end
            end
        end
    end
end

local function GetGlowIgnoreList()
    local _, class = UnitClass("player")
    local specId   = GetSpecialization() and select(1, GetSpecializationInfo(GetSpecialization()))
    local byClass  = GLOW_IGNORE_SPECS[class]
    if not byClass or not specId then return {} end
    local specs = byClass[specId]
    if not specs then return {} end
    local result = {}
    for _, entry in ipairs(specs) do
        if IsPlayerSpell(entry.talent) then
            result[entry.spellId] = 0.05 + (entry.delay or 0)
        end
    end
    return result
end

-- ============================================================
-- Frame
-- ============================================================
local f = CreateFrame("Frame", "SP_MovementAlert", UIParent)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 300)
f:SetSize(28, 28)
f:EnableMouse(false)
f:SetMovable(true)

-- State
f.cachedSpells       = {}   -- list of entry tables from BuildMovementSpellList
f.ignoreGlow         = false
f.spellsToIgnoreGlow = {}
f.timeSpiralOn       = false
f.timeSinceLastUpdate= 0

local fsText = f:CreateFontString(nil, "OVERLAY")
fsText:SetPoint("CENTER")
fsText:SetFont(SP_FONT, 14, "OUTLINE")
fsText:SetTextColor(1, 1, 1, 1)
fsText:SetJustifyH("CENTER")
fsText:Hide()
f.fsText = fsText

-- "MOVABLE" label — shown only during preview/drag
local movableLbl = f:CreateFontString(nil, "OVERLAY")
movableLbl:SetPoint("TOP", f, "TOP", 0, 14)
movableLbl:SetFont(FONT_FACES["Expressway"] or SP_FONT, 8, "OUTLINE")
movableLbl:SetTextColor(1, 0.82, 0, 1)
movableLbl:SetText("MOVABLE")
movableLbl:Hide()
f.movableLbl = movableLbl

-- Drag — saves position back to DB on release
f:SetScript("OnDragStart", function(self) self:StartMoving() end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local db = GetDB()
    if db then
        local cx,  cy  = self:GetCenter()
        local ucx, ucy = UIParent:GetCenter()
        db.anchorFrom  = "CENTER"
        db.anchorTo    = "CENTER"
        db.anchorFrame = "UIParent"
        db.x = math.floor(cx - ucx + 0.5)
        db.y = math.floor(cy - ucy + 0.5)
        if MA._syncSliders then MA._syncSliders(db.x, db.y) end
    end
end)

MA.frame     = f
MA.fsText    = fsText
MA.isPreview = false

-- ============================================================
-- Helpers
-- ============================================================
local function ApplyStyles()
    local db = GetDB()
    local fontPath = GetFontPath(db.fontFace or "Expressway")
    fsText:SetFont(fontPath, db.fontSize or 14, db.outline or "OUTLINE")
    fsText:SetTextColor(db.color[1], db.color[2], db.color[3], db.color[4] or 1)
    fsText:SetJustifyH(db.justify or "CENTER")
    fsText:SetShadowOffset(db.shadowX or 1, db.shadowY or -1)
    fsText:SetShadowColor(0, 0, 0, db.shadowAlpha or 1)
    f:SetFrameStrata(db.frameStrata or "MEDIUM")
    f:SetFrameLevel(db.frameLevel or 50)
    f:ClearAllPoints()
    local anchorFrom  = db.anchorFrom  or "CENTER"
    local anchorTo    = db.anchorTo    or "CENTER"
    local anchorFrame = _G[db.anchorFrame or "UIParent"] or UIParent
    f:SetPoint(anchorFrom, anchorFrame, anchorTo, db.x or 0, db.y or 300)
end

-- ============================================================
-- CheckMovementCooldown — core detection, callable from OnUpdate AND events
-- ============================================================
-- Detection strategy (learned from NaowhQOL):
--
-- Multi-charge spells (maxCharges > 1, e.g. DH Transfer/Fel Rush, Mage Shimmer):
--   Check currentCharges DIRECTLY.  isOnGCD is unreliable for these — DH spells
--   can return isOnGCD=false even during the GCD, which would trigger a false
--   positive for the full ~1.5s GCD duration.  currentCharges==0 is unambiguous.
--
-- Regular / single-charge spells (e.g. Blink, Sprint, Demonic Circle):
--   isOnGCD semantics:
--     false → real CD active                                         → show
--     true  → GCD only                                              → hide
--     nil   → special (Demonic Circle teleport quirk, etc.)         → show ONLY if
--             GetSpellCharges returns nil (no charge system on spell)
--
-- timeUntilEndOfStartRecovery guard > 0:
--   WoW returns 0 when the spell is already usable; 0 is truthy in Lua.
--   Requiring > 0 prevents showing "0.0" when the spell is ready.
local function CheckMovementCooldown()
    if MA.isPreview then return end
    if f.timeSpiralOn then return end  -- Time Spiral owns fsText during its countdown
    local db = GetDB()
    local prec = db.precision or 0
    for _, entry in ipairs(f.cachedSpells) do
        if entry.checkType == "buffActive" then
            -- Buff-active spells (e.g. Burning Rush): show when the buff is present.
            if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                local aura = C_UnitAuras.GetPlayerAuraBySpellID(entry.spellId)
                if aura then
                    fsText:SetText(entry.customText or entry.spellName)
                    fsText:Show()
                    return
                end
            end
        else
            local spellId = entry.baseSpellId or entry.spellId
            local cdInfo = C_Spell.GetSpellCooldown(spellId)
            if cdInfo
                and cdInfo.timeUntilEndOfStartRecovery
                and cdInfo.timeUntilEndOfStartRecovery > 0
            then
                local chargeInfo = C_Spell.GetSpellCharges(spellId)
                local shouldShow = false

                if chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1
                    and not IsSecret(chargeInfo.currentCharges)
                then
                    -- Multi-charge spell: show if and only if ALL charges are spent.
                    -- This bypasses the unreliable isOnGCD value that DH spells report.
                    shouldShow = (chargeInfo.currentCharges == 0)
                else
                    -- Regular/single-charge spell: rely on isOnGCD.
                    shouldShow = (cdInfo.isOnGCD == false)
                        or (cdInfo.isOnGCD == nil and not chargeInfo)
                end

                if shouldShow then
                    local label = entry.customText or ("No " .. entry.spellName)
                    fsText:SetText(label .. "\n"
                        .. string.format("%." .. prec .. "f", cdInfo.timeUntilEndOfStartRecovery))
                    fsText:Show()
                    return
                end
            end
        end
    end
    fsText:Hide()
end

-- ============================================================
-- OnUpdate
-- ============================================================
local function OnUpdate(self, elapsed)
    -- Don't touch the display while the preview is active — ShowPreview owns it.
    if MA.isPreview then return end

    self.timeSinceLastUpdate = self.timeSinceLastUpdate + elapsed
    local db = GetDB()
    if self.timeSinceLastUpdate < (db.updateInterval or 0.1) then return end
    self.timeSinceLastUpdate = 0

    -- Time Spiral has highest priority — handled directly here (not in CheckMovementCooldown)
    if self.timeSpiralOn then
        local remaining = 10 - (GetTime() - self.timeSpiralOn)
        if remaining <= 0 then
            self.timeSpiralOn = false
            fsText:Hide()
            return
        end
        local timeSpiralColor = db.timeSpiralColor or {0.451, 0.741, 0.522, 1}
        local hex = string.format("|cff%02x%02x%02x",
            math.floor(timeSpiralColor[1] * 255),
            math.floor(timeSpiralColor[2] * 255),
            math.floor(timeSpiralColor[3] * 255))
        local label = db.timeSpiralText or "Free Movement"
        local prec  = db.precision or 0
        fsText:SetText(hex .. label .. "\n" .. string.format("%." .. prec .. "f", remaining) .. "|r")
        fsText:Show()
        return
    end

    CheckMovementCooldown()
end

-- ============================================================
-- OnEvent
-- ============================================================
local function OnEvent(self, event, ...)
    local db = GetDB()

    -- ── Spec / talent changes → rebuild spell list ──────────────────────────
    if event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED"
    then
        if not InCombatLockdown() then
            self.cachedSpells = BuildMovementSpellList()
            RebuildTrackedSpellSet(self.cachedSpells)
            self.spellsToIgnoreGlow = GetGlowIgnoreList()
            RefreshCastFilters()
        end
        CheckMovementCooldown()
        return
    end

    -- ── Immediate CD reactions (NaowhQOL approach) ───────────────────────────
    -- Fire as soon as the server updates so we don't wait for the next OnUpdate tick.
    if event == "SPELL_UPDATE_COOLDOWN"
        or event == "SPELL_UPDATE_CHARGES"
        or event == "UNIT_AURA"
    then
        CheckMovementCooldown()
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, _, spellId = ...
        -- Only react when it's one of our tracked spells to avoid noise
        if trackedSpellSet[spellId] then
            -- Reset the OnUpdate throttle so the very next frame also polls
            -- (belt-and-suspenders alongside the immediate call below)
            self.timeSinceLastUpdate = 99
            CheckMovementCooldown()
        end
        return
    end

    -- ── Time Spiral + glow suppression ──────────────────────────────────────
    if db.showTimeSpiral then
        local spellId = ...

        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" and not self.ignoreGlow then
            if TIME_SPIRAL_ABILITIES[spellId] then
                -- Suppress if a DH cast-filter spell was just used
                if GetTime() > castFilterExpiry then
                    self.timeSpiralOn = GetTime()
                    if db.timeSpiralPlaySound and db.timeSpiralSound then
                        PlaySoundFile(db.timeSpiralSound, "Master")
                    end
                end
            end

        elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
            if TIME_SPIRAL_ABILITIES[spellId] then
                self.timeSpiralOn = nil
            end

        elseif event == "UNIT_SPELLCAST_SENT" then
            local castSpellId = select(4, ...)
            -- Glow suppression for pre-fire glows
            if self.spellsToIgnoreGlow and self.spellsToIgnoreGlow[castSpellId] then
                self.ignoreGlow = true
                C_Timer.After(self.spellsToIgnoreGlow[castSpellId], function()
                    self.ignoreGlow = false
                end)
            end
            -- Cast filter: suppress Time Spiral glow for DH talent-gated spells
            if castFilters[castSpellId] then
                castFilterExpiry = GetTime() + 1.5
            end
        else
            self.timeSpiralOn = nil
        end
    end
end

-- ============================================================
-- Preview / drag
-- ============================================================
function MA:ShowPreview()
    self.isPreview = true
    f:EnableMouse(true)
    f:SetMouseClickEnabled(true)
    f:RegisterForDrag("LeftButton")
    if f.movableLbl then f.movableLbl:Show() end
    fsText:SetText("No Blink\n3.2")
    fsText:Show()
    f:Show()
    ApplyStyles()
end

function MA:HidePreview()
    self.isPreview = false
    f:EnableMouse(false)
    f:SetMouseClickEnabled(false)
    if f.movableLbl then f.movableLbl:Hide() end
    if not GetDB().enabled then
        fsText:Hide()
    end
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function MA:OnEnable()
    self:Refresh()
end

function MA:Refresh()
    local db = GetDB()
    ApplyStyles()
    f.cachedSpells = BuildMovementSpellList()
    RebuildTrackedSpellSet(f.cachedSpells)
    f.spellsToIgnoreGlow = GetGlowIgnoreList()
    RefreshCastFilters()

    if db.enabled then
        f:SetScript("OnEvent", OnEvent)
        f:SetScript("OnUpdate", OnUpdate)
        -- Spec / talent changes
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        f:RegisterEvent("PLAYER_TALENT_UPDATE")
        f:RegisterEvent("TRAIT_CONFIG_UPDATED")
        -- Time Spiral glow detection
        f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
        f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
        -- Immediate CD reaction (NaowhQOL approach — eliminates server-tick lag)
        f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        f:RegisterEvent("SPELL_UPDATE_CHARGES")
        f:RegisterUnitEvent("UNIT_AURA", "player")
        f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        f:SetScript("OnEvent", nil)
        f:SetScript("OnUpdate", nil)
        f:UnregisterAllEvents()
        fsText:Hide()
    end
end
