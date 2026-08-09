-- SuspicionsPack - MovementAlert.lua
-- Affiche un texte + cooldown quand la capacité de déplacement est en CD.
-- Suit aussi le Time Spiral (affiche le countdown de mouvement libre).

local SP = SuspicionsPack

local MA = SP:NewSPModule("MovementAlert", "movementAlert")
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

-- Localised with a fallback (matching BloodlustAlert/ReapPredict). This module
-- reads spell/cooldown APIs on a 10 Hz loop, so a missing global would be a
-- hard error several times a second.
local _issecretvalue = issecretvalue or function() return false end

-- Font names now resolve through Core: SP.FONT_FACES is the single
-- source of truth and SP.ResolveFont falls back to the pack default.
-- The private table this used to carry SHADOWED LibSharedMedia, so any
-- font the user added via another addon silently became Expressway here.
local function GetFontPath(name)
    return SP.ResolveFont(name)
end

-- ============================================================
-- DB helper
-- ============================================================
local function GetDB()
    return SP.GetDB().movementAlert
end

-- ============================================================
-- Movement abilities per class/spec
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
-- Glow-ignore
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
-- Spells whose GCD reports isOnGCD=false
-- ============================================================
local SPELLS_WITH_OWN_GCD = {
    [1234796] = 0.8,   -- DH Shift (Devourer) — isOnGCD returns false during its GCD
}

-- ============================================================
-- Cast filter
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
                        -- pcall does NOT stop taint propagation: comparing a
                        -- secret value taints execution regardless. Same class
                        -- as the isOnGCD bug that broke Blizzard_CooldownViewer.
                        -- Guard FIRST: Lua evaluates left to right, so putting
                        -- `oid ~= nil` before the check would already have
                        -- compared a secret value.
                        if ok and not _issecretvalue(oid) and oid ~= nil then
                            if oid > 0 and oid ~= spellId and C_Spell.GetSpellInfo(oid) then
                                displayId = oid
                            end
                        end
                    end

                    if not seen[displayId] then
                        seen[spellId]   = true
                        seen[displayId] = true
                        local info = C_Spell.GetSpellInfo(displayId)
                        if not info and displayId ~= spellId then
                            displayId = spellId
                            info = C_Spell.GetSpellInfo(displayId)
                        end
                        if info then
                            local baseId = (displayId ~= spellId) and spellId or nil

                            if BUFF_ACTIVE_SPELLS[displayId] then
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

-- State
f.cachedSpells        = {}   -- list of entry tables from BuildMovementSpellList
f.ignoreGlow          = false
f.ignoreMovementCd    = false  -- true for SPELLS_WITH_OWN_GCD window (suppress GCD false positives)
f.spellsToIgnoreGlow  = {}
f.timeSpiralOn       = false
f.timeSinceLastUpdate= 0

local TIME_SPIRAL_DURATION = 10   -- seconds (also used by OnUpdate)

local fsText

-- ============================================================
-- Time Spiral icon frame
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

    f_tsIconTex = f_tsIcon:CreateTexture(nil, "BACKGROUND")
    f_tsIconTex:SetAllPoints()
    f_tsIconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f_tsIconCd = CreateFrame("Cooldown", nil, f_tsIcon, "CooldownFrameTemplate")
    f_tsIconCd:SetAllPoints()
    f_tsIconCd:SetDrawEdge(false)
    f_tsIconCd:SetDrawSwipe(true)
    f_tsIconCd:SetReverse(true)
    f_tsIconCd:SetHideCountdownNumbers(true)
    f_tsIconCd:SetDrawBling(false)

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
    fsText:SetPoint("CENTER")
    f_tsTextPositioned = false
end

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

MA.frame     = f
MA.fsText    = fsText
MA.isPreview = false

-- ============================================================
-- Helpers
-- ============================================================
local function ApplyStyles()
    local db = GetDB()
    local fontPath = GetFontPath(db.fontFace or "Expressway")
    -- Not fsText:SetFont directly: at login the .ttf is sometimes not loadable
    -- yet, SetFont then returns false and changes NOTHING -- leaving the size at
    -- the 14 this FontString was created with. SP.SetFontSafe keeps the size
    -- right and restores the face when it becomes available.
    SP.SetFontSafe(fsText, fontPath, db.fontSize or 14, db.outline or "OUTLINE")
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
-- Tick arming
--
-- The per-frame driver exists only to refresh a COUNTDOWN. Everything else is
-- already event-driven (SPELL_UPDATE_COOLDOWN, UNIT_AURA, UNIT_SPELLCAST_SENT).
-- It used to be armed in Refresh() and never disarmed, so enabling this module
-- cost ten C_Spell.GetSpellCooldown scans a second for the rest of the session,
-- standing in a city, with nothing on screen.
--
-- Now: armed whenever something countdown-shaped becomes visible, and it
-- unsubscribes itself as soon as nothing is displayed.
-- ============================================================
local TICK_KEY = "movementAlert"
local MATick   -- forward-declared: ArmTick is used above its definition

local function ArmTick()
    if MATick then SP.Tick.Add(TICK_KEY, MATick) end
end

-- ============================================================
-- CheckMovementCooldown
-- ============================================================
local function CheckMovementCooldown()
    if MA.isPreview then return end

    -- Nothing to draw while the module is off. Without this, the Time Spiral
    -- preview (which arms deliberately even when disabled) fell through here
    -- after its auto-cancel and rendered the real alert.
    local _db = GetDB()
    if not (_db and _db.enabled) then
        fsText:Hide()
        SP.Tick.Remove(TICK_KEY)
        return
    end

    -- Armed BEFORE the timeSpiralOn guard: the 10 s expiry lives inside the
    -- tick, so a spiral left running with nothing subscribed could never end.
    ArmTick()
    if f.timeSpiralOn then return end
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
-- Assigns the forward-declared local. `self` is the module frame `f`, which is
-- a file-scope local, so the ticker callback reaches it directly.
MATick = function(elapsed)
    local self = f
    if MA.isPreview then
        SP.Tick.Remove(TICK_KEY)
        return
    end

    self.timeSinceLastUpdate = (self.timeSinceLastUpdate or 0) + elapsed
    local db = GetDB()
    if self.timeSinceLastUpdate < (db.updateInterval or 0.1) then return end
    self.timeSinceLastUpdate = 0

    if self.timeSpiralOn then
        local remaining = TIME_SPIRAL_DURATION - (GetTime() - self.timeSpiralOn)
        if remaining <= 0 then
            self.timeSpiralOn = false
            ResetTSTextPosition()
            fsText:Hide()
            HideTSIcon()
            SP.Tick.Remove(TICK_KEY)
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

    -- Nothing on screen and no Time Spiral running: there is no countdown left
    -- to refresh, so stop costing a frame. The events re-arm via ArmTick.
    if not fsText:IsShown() and not self.timeSpiralOn then
        SP.Tick.Remove(TICK_KEY)
    end
end

-- ============================================================
-- OnEvent
-- ============================================================
local function OnEvent(self, event, ...)
    local db = GetDB()

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

    if event == "SPELL_UPDATE_COOLDOWN"
        or event == "UNIT_AURA"
    then
        CheckMovementCooldown()
        return
    end

    if event == "UNIT_SPELLCAST_SENT" then
        local castSpellId = select(4, ...)
        if SPELLS_WITH_OWN_GCD[castSpellId] then
            self.ignoreMovementCd = true
            C_Timer.After(SPELLS_WITH_OWN_GCD[castSpellId], function()
                self.ignoreMovementCd = false
                CheckMovementCooldown()
            end)
        end
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

    if db.showTimeSpiral then
        local spellId = ...

        if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" and not self.ignoreGlow then
            if TIME_SPIRAL_ABILITIES[spellId] then
                if GetTime() > castFilterExpiry then
                    self.timeSpiralOn = GetTime()
                    ArmTick()
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
    fsText:SetText("No Blink\n3.2")
    fsText:Show()
    f:Show()
    ApplyStyles()
end

function MA:HidePreview()
    self.isPreview = false
    -- Re-evaluate immediately: MATick unsubscribed itself when preview began,
    -- so without this a live countdown stays frozen until the next event.
    CheckMovementCooldown()
    if fsText then fsText:Hide() end
end

function MA:ShowTimeSpiralPreview()
    if self.isPreview then return end  -- don't conflict with drag preview
    local db = GetDB()
    f.timeSpiralOn = GetTime()
    ArmTick()
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
    ShowTSIcon(nil)
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
--
-- OnEnable (deferred to PLAYER_LOGIN, then Refresh) and OnDisable
-- (UnregisterAllEvents + Deactivate) come from SP.ModuleMixin -- see
-- Core/Module.lua. Refresh is kept because it does more than the mixin's: it
-- restyles and rebuilds the spell caches before dispatching, and the GUI calls
-- it after every settings change, not just on enable/disable.
-- ============================================================
function MA:Refresh()
    ApplyStyles()
    ApplyTSIconPosition()
    if not f.timeSpiralOn then
        ResetTSTextPosition()
    end
    f.cachedSpells = BuildMovementSpellList()
    f.spellsToIgnoreGlow = GetGlowIgnoreList()
    RefreshCastFilters()

    -- Delegate the dispatch so AceAddon's flag tracks db.enabled the same
    -- way it does for every other module.
    SP.ModuleMixin.Refresh(self)
end

function MA:Activate()
    -- All nine registrations live on the raw frame `f`, so AceEvent's
    -- UnregisterAllEvents does not reach them -- Deactivate below has to.
    f:SetScript("OnEvent", OnEvent)
    -- No OnUpdate: the ticker is armed on demand by ArmTick and
    -- unsubscribes itself when nothing is being counted down.
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    f:RegisterEvent("PLAYER_TALENT_UPDATE")
    f:RegisterEvent("TRAIT_CONFIG_UPDATED")
    f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    f:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    f:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    f:RegisterUnitEvent("UNIT_AURA", "player")
    -- Evaluate current state now: enabling mid-cooldown used to show
    -- nothing until an unrelated event arrived.
    CheckMovementCooldown()
end

function MA:Deactivate()
    f:SetScript("OnEvent", nil)
    f:UnregisterAllEvents()
    SP.Tick.Remove(TICK_KEY)
    if fsText then fsText:Hide() end
    HideTSIcon()
    -- Cleared, not just hidden: timeSpiralOn holds a GetTime() stamp and its
    -- 10 s expiry lives inside the tick. Leaving it set means a later
    -- re-activate inherits a stale countdown that has no subscriber to end it.
    f.timeSpiralOn = false
    ResetTSTextPosition()
end
