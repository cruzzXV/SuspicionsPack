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
local LSM                = LibStub and LibStub("LibSharedMedia-3.0", true)

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

-- ============================================================
-- Spells whose GCD reports isOnGCD=false (anti-cheat quirk).
-- We suppress the movement CD display for a short window after
-- UNIT_SPELLCAST_SENT to avoid false positives during the GCD.
-- ============================================================
local SPELLS_WITH_OWN_GCD = {
    [1234796] = 0.8,   -- DH Shift (Devourer) — isOnGCD returns false during its GCD
}

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
-- Spell list builder
-- Returns a list of entry tables for the player's spec.
-- Each entry: { spellId, baseSpellId, spellName, customText, checkType }
-- checkType == "buffActive" for BUFF_ACTIVE_SPELLS entries.
-- Detection uses GetSpellCooldown directly (Itrulia approach — no charge tracking).
-- ============================================================
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
                                table.insert(result, {
                                    spellId     = displayId,
                                    baseSpellId = baseId,
                                    spellName   = info.name,
                                    customText  = override and override.customText ~= ""
                                                  and override.customText or nil,
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
                    table.insert(result, {
                        spellId    = spellId,
                        spellName  = info.name,
                        customText = override.customText ~= "" and override.customText or nil,
                    })
                end
            end
        end
    end

    return result
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
f.cachedSpells        = {}   -- list of entry tables from BuildMovementSpellList
f.ignoreGlow          = false
f.ignoreMovementCd    = false  -- true for SPELLS_WITH_OWN_GCD window (suppress GCD false positives)
f.spellsToIgnoreGlow  = {}
f.timeSpiralOn       = false
f.timeSinceLastUpdate= 0

local TIME_SPIRAL_DURATION = 10   -- seconds (also used by OnUpdate)

-- Forward declaration: icon helper closures reference fsText which is
-- created after this block (same file-scope level, but later in the file).
local fsText

-- ============================================================
-- Time Spiral icon frame (NorskenUI-inspired)
-- Shows the movement spell icon + cooldown spiral + glow
-- when Time Spiral procs. Created lazily on first use.
-- ============================================================
local f_tsIcon    = nil  -- icon frame, lazy-created
local f_tsIconTex = nil  -- spell icon texture
local f_tsIconCd  = nil  -- CooldownFrameTemplate overlay

local function CreateTSIconFrame()
    if f_tsIcon then return end
    local db   = GetDB()
    local size = db.timeSpiralIconSize or 50

    f_tsIcon = CreateFrame("Frame", "SP_MovementAlert_TSIcon", UIParent)
    f_tsIcon:SetSize(size, size)
    f_tsIcon:EnableMouse(false)
    f_tsIcon:Hide()

    -- Spell icon texture (crop inner 84 % to cut the default icon border)
    f_tsIconTex = f_tsIcon:CreateTexture(nil, "BACKGROUND")
    f_tsIconTex:SetAllPoints()
    f_tsIconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Cooldown spiral (same template as NorskenUI)
    f_tsIconCd = CreateFrame("Cooldown", nil, f_tsIcon, "CooldownFrameTemplate")
    f_tsIconCd:SetAllPoints()
    f_tsIconCd:SetDrawEdge(false)
    f_tsIconCd:SetDrawSwipe(true)
    f_tsIconCd:SetReverse(true)
    f_tsIconCd:SetHideCountdownNumbers(true)
    f_tsIconCd:SetDrawBling(false)

    -- Initial position
    f_tsIcon:SetFrameStrata(db.timeSpiralIconFrameStrata or "MEDIUM")
    f_tsIcon:ClearAllPoints()
    local anchorFrame = _G[db.timeSpiralIconAnchorFrame or "UIParent"] or UIParent
    f_tsIcon:SetPoint(
        db.timeSpiralIconAnchorFrom or "CENTER", anchorFrame,
        db.timeSpiralIconAnchorTo   or "CENTER",
        db.timeSpiralIconX or 0, db.timeSpiralIconY or 250)
end

local function ApplyTSIconPosition()
    if not f_tsIcon then return end
    local db = GetDB()
    f_tsIcon:SetFrameStrata(db.timeSpiralIconFrameStrata or "MEDIUM")
    f_tsIcon:ClearAllPoints()
    local anchorFrame = _G[db.timeSpiralIconAnchorFrame or "UIParent"] or UIParent
    f_tsIcon:SetPoint(
        db.timeSpiralIconAnchorFrom or "CENTER", anchorFrame,
        db.timeSpiralIconAnchorTo   or "CENTER",
        db.timeSpiralIconX or 0, db.timeSpiralIconY or 250)
end

-- TS text positioning — separates TS countdown from normal CD text position
local f_tsTextPositioned = false

local function ApplyTSTextPosition()
    local db = GetDB()
    fsText:ClearAllPoints()
    fsText:SetPoint("CENTER", UIParent, "CENTER",
        db.timeSpiralTextX or 0, db.timeSpiralTextY or 200)
    f_tsTextPositioned = true
end

local function ResetTSTextPosition()
    if not f_tsTextPositioned then return end
    fsText:ClearAllPoints()
    fsText:SetPoint("CENTER")   -- back to center of frame f
    f_tsTextPositioned = false
end

-- Show the icon for a given spellId. No-op if timeSpiralShowIcon is off.
local function ShowTSIcon(spellId)
    local db = GetDB()
    if not db.timeSpiralShowIcon or not db.showTimeSpiral then return end
    CreateTSIconFrame()
    local size = db.timeSpiralIconSize or 50
    f_tsIcon:SetSize(size, size)
    ApplyTSIconPosition()
    local tex = spellId and C_Spell.GetSpellTexture(spellId)
    f_tsIconTex:SetTexture(tex or 4622479)
    f_tsIconCd:SetCooldown(GetTime(), TIME_SPIRAL_DURATION)
    if ActionButton_ShowOverlayGlow then ActionButton_ShowOverlayGlow(f_tsIcon) end
    f_tsIcon:Show()
end

local function HideTSIcon()
    if not f_tsIcon or not f_tsIcon:IsShown() then return end
    if ActionButton_HideOverlayGlow then ActionButton_HideOverlayGlow(f_tsIcon) end
    f_tsIcon:Hide()
end

fsText = f:CreateFontString(nil, "OVERLAY")
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
    local cr, cg, cb = SP.GetColorFromSource(db.colorSource or "custom", db.color or {1,1,1})
    fsText:SetTextColor(cr, cg, cb, (db.colorSource == "custom" and db.color and db.color[4]) or 1)
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
-- CheckMovementCooldown — core detection (Itrulia approach)
-- ============================================================
-- Detection strategy:
--   Gate: cdInfo.timeUntilEndOfStartRecovery is truthy (secret-value safe — no compare).
--   Show: isOnGCD == false  (real CD — guard with issecretvalue before comparing;
--         isOnGCD CAN be a secret value in TWW, direct comparison causes taint)
--         AND isOnGCD ~= nil  (rejects the nil quirk seen on DH/Evoker during double-jump)
--   WARLOCK exception: isOnGCD == nil is allowed (Demonic Circle returns nil while on GCD).
--   Spells in SPELLS_WITH_OWN_GCD (e.g. DH Shift) are gated by f.ignoreMovementCd
--   set in UNIT_SPELLCAST_SENT — see there for details.
local function CheckMovementCooldown()
    if MA.isPreview then return end
    if f.timeSpiralOn then return end  -- Time Spiral owns fsText during its countdown
    if f.ignoreMovementCd then fsText:Hide(); return end
    local db   = GetDB()
    local prec = db.precision or 0
    local _, class = UnitClass("player")
    local isWarlock = (class == "WARLOCK")
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
            local cdInfo  = C_Spell.GetSpellCooldown(spellId)
            -- Read isOnGCD once; guard before comparing (secret value comparison causes taint).
            local isOnGCD    = cdInfo and cdInfo.isOnGCD
            local isOnGCDSafe = not (issecretvalue and issecretvalue(isOnGCD))
            if cdInfo
                and cdInfo.timeUntilEndOfStartRecovery
                and isOnGCDSafe
                and not isOnGCD
                and (isOnGCD ~= nil or isWarlock)
            then
                local label = entry.customText or ("No " .. entry.spellName)
                fsText:SetText(label .. "\n"
                    .. string.format("%." .. prec .. "f", cdInfo.timeUntilEndOfStartRecovery))
                fsText:Show()
                return
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
            ResetTSTextPosition()
            fsText:Hide()
            HideTSIcon()
            return
        end
        ApplyTSTextPosition()
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
            self.spellsToIgnoreGlow = GetGlowIgnoreList()
            RefreshCastFilters()
        end
        CheckMovementCooldown()
        return
    end

    -- ── Immediate CD reactions ────────────────────────────────────────────────
    if event == "SPELL_UPDATE_COOLDOWN"
        or event == "UNIT_AURA"
    then
        CheckMovementCooldown()
        return
    end

    -- ── UNIT_SPELLCAST_SENT — always active (not gated by showTimeSpiral) ────
    -- Handles both glow suppression (TS feature) and ignoreMovementCd (detection).
    if event == "UNIT_SPELLCAST_SENT" then
        local castSpellId = select(4, ...)
        -- ignoreMovementCd: for spells whose GCD reports isOnGCD=false (e.g. DH Shift).
        -- Suppress movement CD display for the GCD window to avoid false positives.
        if SPELLS_WITH_OWN_GCD[castSpellId] then
            self.ignoreMovementCd = true
            C_Timer.After(SPELLS_WITH_OWN_GCD[castSpellId], function()
                self.ignoreMovementCd = false
                CheckMovementCooldown()
            end)
        end
        -- Time Spiral glow-related (only matters when TS feature is on)
        if db.showTimeSpiral then
            if self.spellsToIgnoreGlow and self.spellsToIgnoreGlow[castSpellId] then
                self.ignoreGlow = true
                C_Timer.After(self.spellsToIgnoreGlow[castSpellId], function()
                    self.ignoreGlow = false
                end)
            end
            if castFilters[castSpellId] then
                castFilterExpiry = GetTime() + 1.5
            end
        end
        return
    end

    -- ── Time Spiral glow events ──────────────────────────────────────────────
    if db.showTimeSpiral then
        local spellId = ...

        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" and not self.ignoreGlow then
            if TIME_SPIRAL_ABILITIES[spellId] then
                if GetTime() > castFilterExpiry then
                    self.timeSpiralOn = GetTime()
                    f_tsTextPositioned = false   -- force reposition on next OnUpdate tick
                    if db.timeSpiralPlaySound and db.timeSpiralSound then
                        local soundPath = LSM and LSM:Fetch("sound", db.timeSpiralSound) or db.timeSpiralSound
                        if soundPath then PlaySoundFile(soundPath, "Master") end
                    end
                    ShowTSIcon(spellId)
                end
            end

        elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
            if TIME_SPIRAL_ABILITIES[spellId] then
                self.timeSpiralOn = nil
                ResetTSTextPosition()
                fsText:Hide()
                HideTSIcon()
            end

        else
            self.timeSpiralOn = nil
            ResetTSTextPosition()
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
    -- Auto-cancel after 5 s (same pattern as ShowTimeSpiralPreview)
    if self._maPrevTimer then self._maPrevTimer:Cancel() end
    self._maPrevTimer = C_Timer.NewTimer(5, function()
        self._maPrevTimer = nil
        self:HidePreview()
        if self._maPreviewEndCallback then self._maPreviewEndCallback() end
    end)
end

function MA:HidePreview()
    if self._maPrevTimer then
        self._maPrevTimer:Cancel()
        self._maPrevTimer = nil
    end
    self.isPreview = false
    f:EnableMouse(false)
    f:SetMouseClickEnabled(false)
    if f.movableLbl then f.movableLbl:Hide() end
    if not GetDB().enabled then
        fsText:Hide()
    end
end

-- ── Time Spiral display preview ──────────────────────────────────────────
-- Independent of the main text preview — doesn't set isPreview, so it
-- never conflicts with the drag-to-move mode.
-- Sets timeSpiralOn so OnUpdate renders a live countdown (if the module
-- is enabled and OnUpdate is ticking).  Also renders immediately so it
-- works even when the module is disabled.
-- Auto-cancels after 5 s and fires _tsPreviewEndCallback (set by the GUI)
-- so the preview button can reset its label automatically.
function MA:ShowTimeSpiralPreview()
    if self.isPreview then return end  -- don't conflict with drag preview
    local db = GetDB()
    f.timeSpiralOn = GetTime()
    f_tsTextPositioned = false  -- force reposition on next tick / immediate render
    -- Immediate render so there's no 1-tick delay and it works when disabled
    local c     = db.timeSpiralColor or { 0.451, 0.741, 0.522, 1 }
    local hex   = string.format("|cff%02x%02x%02x",
        math.floor(c[1]*255), math.floor(c[2]*255), math.floor(c[3]*255))
    local label = db.timeSpiralText or "Free Movement"
    local prec  = db.precision or 0
    ApplyTSTextPosition()
    fsText:SetText(hex .. label .. "\n" .. string.format("%." .. prec .. "f", 10.0) .. "|r")
    fsText:Show()
    -- Show icon (uses fallback TS icon texture since no real spellId in preview)
    ShowTSIcon(nil)
    -- Auto-cancel timer
    if self._tsPrevTimer then self._tsPrevTimer:Cancel() end
    self._tsPrevTimer = C_Timer.NewTimer(5, function()
        self._tsPrevTimer = nil
        f.timeSpiralOn = false
        ResetTSTextPosition()
        fsText:Hide()
        HideTSIcon()
        if self._tsPreviewEndCallback then self._tsPreviewEndCallback() end
    end)
end

function MA:HideTimeSpiralPreview()
    if self._tsPrevTimer then
        self._tsPrevTimer:Cancel()
        self._tsPrevTimer = nil
    end
    f.timeSpiralOn = false
    ResetTSTextPosition()
    fsText:Hide()
    HideTSIcon()
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
    ApplyTSIconPosition()
    -- If TS is not currently active, make sure fsText is anchored back to frame f
    if not f.timeSpiralOn then
        ResetTSTextPosition()
    end
    f.cachedSpells = BuildMovementSpellList()
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
        -- Immediate CD reaction
        f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        f:RegisterUnitEvent("UNIT_AURA", "player")
    else
        f:SetScript("OnEvent", nil)
        f:SetScript("OnUpdate", nil)
        f:UnregisterAllEvents()
        fsText:Hide()
    end
end
