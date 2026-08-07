-- SuspicionsPack — BloodlustAlert Module
-- Détecte le Bloodlust via les debuffs Epuisement/Satié sur UNIT_AURA.
-- Les spellId de addedAuras sont protégés par issecretvalue().

local SP = SuspicionsPack

local BLAlert = SP:NewSPModule("BloodlustAlert", "bloodlustAlert")
SP.BloodlustAlert = BLAlert

-- ============================================================
-- Constants
-- ============================================================
local BL_MEDIA = "Interface\\AddOns\\SuspicionsPack\\Media\\Bloodlust\\"

BLAlert.Sounds = {
    { key = "hotnigga",   label = "Hot Nigga",           file = BL_MEDIA .. "hotnigga.mp3"            },
    { key = "oggy",       label = "OGGY PHONK",          file = BL_MEDIA .. "OGGY PHONK.mp3"          },
    { key = "taii",       label = "Taii Hardtek",        file = BL_MEDIA .. "Taii Hardtek.mp3"        },
    { key = "ratirl",     label = "RatIRL",              file = BL_MEDIA .. "RatIRL.mp3"              },
    { key = "doigby",     label = "Doigby Guerrier",     file = BL_MEDIA .. "Doigby Guerrier.mp3"     },
    { key = "charlie",    label = "We Are Charlie Kirk", file = BL_MEDIA .. "We are charlie kirk.mp3" },
    { key = "oiia",       label = "OIIA Psytrance",      file = BL_MEDIA .. "oiia-psytrance.mp3"      },
}

local SOUND_FILES = {}
for _, s in ipairs(BLAlert.Sounds) do SOUND_FILES[s.key] = s.file end

local DEFAULT_SOUND        = "hotnigga"
local BL_DURATION          = 40    -- seconds (matches Bloodlust / Heroism / Time Warp)

-- Debuffs appliqués au joueur quand un effet BL se déclenche.
local EXHAUSTION_IDS = {
    57723,   -- Sated                   (Bloodlust)
    57724,   -- Exhaustion              (Heroism)
    80354,   -- Temporal Displacement   (Time Warp)
    95809,   -- Insanity                (Ancient Hysteria)
    160455,  -- Fatigued                (Netherwinds / Primal Rage)
    264689,  -- Fatigued                (Primal Rage / Drums of the Maelstrom)
    390435,  -- Exhaustion              (Fury of the Aspects)
}

-- Fast lookup set
local EXHAUSTION_SET = {}
for _, id in ipairs(EXHAUSTION_IDS) do EXHAUSTION_SET[id] = true end

-- ============================================================
-- State
-- ============================================================
local active        = false
local armed         = true
local rearmTimer    = nil
local soundHandle   = nil
local stopTimer     = nil
local fadeTimer     = nil
local lastTimerNum  = nil

local timerFrame    = nil
local timerTicker   = nil
local blStartTime   = nil

-- issecretvalue guard — API exists in 12.x; fall back to always-false on older builds
local _issecretvalue = issecretvalue or function() return false end

-- Frame dédié pour UNIT_AURA — AceEvent-3.0 ne supporte pas RegisterUnitEvent.
local unitAuraFrame = CreateFrame("Frame")
unitAuraFrame:SetScript("OnEvent", function(_, event, unit, updateInfo)
    BLAlert:OnUnitAura(event, unit, updateInfo)
end)

local BL_FONT = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"


-- Font names now resolve through Core: SP.FONT_FACES is the single
-- source of truth and SP.ResolveFont falls back to the pack default.
-- The private table this used to carry SHADOWED LibSharedMedia, so any
-- font the user added via another addon silently became Expressway here.
local function GetFontPath(name)
    return SP.ResolveFont(name)
end

-- ============================================================
-- Timer frame
-- ============================================================
local function BuildTimerFrame()
    if timerFrame then return end

    local f = CreateFrame("Frame", "SPBLTimerFrame", UIParent, "BackdropTemplate")
    f:SetSize(100, 52)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(100)
    f:SetBackdrop({ bgFile   = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    f:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    f:Hide()

    local num = f:CreateFontString(nil, "OVERLAY")
    num:SetPoint("TOP", f, "TOP", 0, -6)
    num:SetFont(BL_FONT, 22, "OUTLINE")
    num:SetTextColor(1, 1, 1, 1)
    num:SetText("40")
    f.num = num

    local lbl = f:CreateFontString(nil, "OVERLAY")
    lbl:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
    lbl:SetFont(BL_FONT, 9, "")
    lbl:SetTextColor(0.85, 0.85, 0.85, 0.7)
    lbl:SetText("BLOODLUST")
    f.lbl = lbl

    local barBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    barBg:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  1, 1)
    barBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    barBg:SetHeight(3)
    barBg:SetColorTexture(0.2, 0.2, 0.2, 1)
    f.barBg = barBg

    local barFill = f:CreateTexture(nil, "ARTWORK", nil, 2)
    barFill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
    barFill:SetHeight(3)
    barFill:SetColorTexture(0.93, 0.27, 0.27, 1)
    f.barFill = barFill
    f.barMaxW = 98

    f:EnableMouse(false)

    timerFrame = f
end

local function UpdateTimerDisplay()
    if not timerFrame or not blStartTime then return end
    local remaining = math.max(0, BL_DURATION - (GetTime() - blStartTime))
    local ceiled = math.ceil(remaining)
    if ceiled ~= lastTimerNum then
        lastTimerNum = ceiled
        timerFrame.num:SetText(ceiled)
    end
    if timerFrame.barFill:IsShown() then
        local pct = remaining / BL_DURATION
        timerFrame.barFill:SetWidth(math.max(1, timerFrame.barMaxW * pct))
    end
end

-- ============================================================
-- Helpers
--
-- No file-local GetDB: every reader here is a colon method, so they all go
-- through ModuleMixin:GetDB() -- see Core/Module.lua.
-- ============================================================
local function ResolveSound(key)
    if key == "random" then
        local choices = {}
        for _, s in ipairs(BLAlert.Sounds) do
            if s.file then table.insert(choices, s.file) end
        end
        if #choices > 0 then return choices[math.random(#choices)] end
        return SOUND_FILES[DEFAULT_SOUND]
    end
    return SOUND_FILES[key] or SOUND_FILES[DEFAULT_SOUND]
end

-- ============================================================
-- Detection: UNIT_AURA on player
-- ============================================================

function BLAlert:OnUnitAura(event, unit, updateInfo)
    local db = self:GetDB()
    if not (db and db.enabled) then return end
    if active or not armed then return end

    -- Fast path : ignore si aucun debuff d'épuisement dans addedAuras.
    if updateInfo and not updateInfo.isFullUpdate then
        local added = updateInfo.addedAuras
        if not added then return end
        local found = false
        for _, aura in ipairs(added) do
            local sid = aura.spellId
            if type(sid) == "number" and not _issecretvalue(sid) and EXHAUSTION_SET[sid] then
                found = true
                break
            end
        end
        if not found then return end
    end

    -- Slow path : confirmation via GetPlayerAuraBySpellID + vérification de fraîcheur.
    for _, spellId in ipairs(EXHAUSTION_IDS) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
        if aura then
            -- Read the fields, then guard, THEN test. `if aura.expirationTime`
            -- is itself a truthiness branch on a possibly-secret value, so the
            -- guard has to come before it -- not after, as a first pass had it.
            local expiration = aura.expirationTime
            local dur        = aura.duration
            if not _issecretvalue(expiration) and not _issecretvalue(dur) and expiration then
                if not dur or dur <= 0 then dur = 600 end
                local appliedTime = expiration - dur
                if (GetTime() - appliedTime) < BL_DURATION then
                    self:StartBL()
                    return
                end
            end
        end
    end
end

-- ============================================================
-- Timer display settings
-- ============================================================
function BLAlert:ApplyTimerSettings()
    BuildTimerFrame()
    if not timerFrame then return end
    local db = self:GetDB()
    if not db then return end

    local anchorFrame = _G[db.timerAnchorFrame or "UIParent"] or UIParent
    timerFrame:ClearAllPoints()
    timerFrame:SetPoint(
        db.timerAnchorFrom or "CENTER",
        anchorFrame,
        db.timerAnchorTo   or "CENTER",
        db.timerX or 0,
        db.timerY or -220)
    timerFrame:SetFrameStrata(db.frameStrata or "HIGH")

    local fs = db.timerFontSize or 22
    local fontPath = GetFontPath(db.timerFontFace or "Expressway")
    timerFrame.num:SetFont(fontPath, fs, db.timerOutline or "OUTLINE")
    local w = math.max(80, math.floor(fs * 3.2))
    local h = fs + 30
    timerFrame:SetSize(w, h)
    timerFrame.barMaxW = w - 2

    local nr, ng, nb = SP.GetColorFromSource(db.timerNumColorSource or "custom",
        db.timerNumColor or { 1, 1, 1 })
    timerFrame.num:SetTextColor(nr, ng, nb, 1)

    local br, bg2, bb = SP.GetColorFromSource(db.timerBarColorSource or "custom",
        db.timerBarColor or { 0.93, 0.27, 0.27 })
    timerFrame.barFill:SetColorTexture(br, bg2, bb, 1)
    local showBar = db.timerShowBar ~= false
    timerFrame.barBg:SetShown(showBar)
    timerFrame.barFill:SetShown(showBar)

    if timerFrame.lbl then
        timerFrame.lbl:SetShown(db.timerShowLabel ~= false)
    end

    local op = db.timerBgOpacity
    if op == nil then op = 0.85 end
    timerFrame:SetBackdropColor(0.05, 0.05, 0.05, op)
    timerFrame:SetBackdropBorderColor(0.15, 0.15, 0.15, op)
end

function BLAlert:ShowTimerPreview()
    self.isTimerPreview = true
    BuildTimerFrame()
    self:ApplyTimerSettings()
    if timerFrame then
        timerFrame.num:SetText("40")
        if timerFrame.barFill:IsShown() then
            timerFrame.barFill:SetWidth(timerFrame.barMaxW or 98)
        end
        timerFrame:Show()
    end
end

function BLAlert:HideTimerPreview()
    self.isTimerPreview = false
    if timerFrame then timerFrame:Hide() end
    -- blStartTime est nil pendant la fenêtre de re-arm, donc pas de faux positif.
    if active and blStartTime and timerFrame then
        timerFrame:Show()
    end
end

-- ============================================================
-- Start / Stop
-- ============================================================
function BLAlert:StartBL()
    if active then return end
    active = true
    armed  = false

    if soundHandle then StopSound(soundHandle, 500); soundHandle = nil end
    local db  = self:GetDB()
    local ch  = db and db.channel or "Master"
    local key = db and db.sound or DEFAULT_SOUND
    if db and db.playSound ~= false then
        local file = ResolveSound(key)
        local willPlay, handle = PlaySoundFile(file, ch)
        if willPlay then soundHandle = handle end
    end

    if fadeTimer then fadeTimer:Cancel() end
    fadeTimer = C_Timer.NewTimer(BL_DURATION - 3, function()
        fadeTimer = nil
        if soundHandle then StopSound(soundHandle, 3000); soundHandle = nil end
    end)

    if stopTimer then stopTimer:Cancel() end
    stopTimer = C_Timer.NewTimer(BL_DURATION, function()
        stopTimer = nil
        if active then self:StopBL() end
    end)

    if db and db.timerEnabled ~= false then
        self:ApplyTimerSettings()
        blStartTime = GetTime()
        if timerFrame then
            UpdateTimerDisplay()
            timerFrame:Show()
        end
        if timerTicker then timerTicker:Cancel() end
        timerTicker = C_Timer.NewTicker(0.1, UpdateTimerDisplay)
    end
end

function BLAlert:StopBL()
    active = false

    if stopTimer   then stopTimer:Cancel();   stopTimer   = nil end
    if fadeTimer   then fadeTimer:Cancel();   fadeTimer   = nil end
    if timerTicker then timerTicker:Cancel(); timerTicker = nil end

    blStartTime = nil
    if timerFrame then timerFrame:Hide() end
    if soundHandle then StopSound(soundHandle, 500); soundHandle = nil end

    -- Re-arm after a short delay to avoid double-triggering
    if rearmTimer then rearmTimer:Cancel() end
    rearmTimer = C_Timer.NewTimer(8, function()
        rearmTimer = nil
        armed = true
    end)
end

function BLAlert:OnPlayerDead()
    if active then self:StopBL() end
end

function BLAlert:OnEnteringWorld()
    if active then self:StopBL() end
end

-- ============================================================
-- Activate / Deactivate
--
-- Called by the GUI enable toggle and by ModuleMixin:Refresh(). Refresh,
-- OnEnable and OnDisable all come from ModuleMixin -- see Core/Module.lua.
--
-- UNIT_AURA lives on our own unitAuraFrame, not on AceEvent, because
-- AceEvent-3.0 has no RegisterUnitEvent. That frame therefore has to be
-- registered and unregistered here by hand; self:UnregisterAllEvents() knows
-- nothing about it.
-- ============================================================
function BLAlert:Activate()
    if not self:IsOn() then return end

    unitAuraFrame:RegisterUnitEvent("UNIT_AURA", "player")
    self:RegisterEvent("PLAYER_DEAD",           "OnPlayerDead")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
end

function BLAlert:Deactivate()
    unitAuraFrame:UnregisterEvent("UNIT_AURA")
    self:UnregisterEvent("PLAYER_DEAD")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    if active then self:StopBL() end
    armed = true

    -- StopBL only runs when a lust was actually in progress, so every timer is
    -- cancelled again here: a Deactivate mid-countdown must leave nothing armed.
    if rearmTimer  then rearmTimer:Cancel();  rearmTimer  = nil end
    if stopTimer   then stopTimer:Cancel();   stopTimer   = nil end
    if fadeTimer   then fadeTimer:Cancel();   fadeTimer   = nil end
    if timerTicker then timerTicker:Cancel(); timerTicker = nil end
    if soundHandle then StopSound(soundHandle, 500); soundHandle = nil end

    blStartTime  = nil
    lastTimerNum = nil

    -- The GUI preview owns the frame while it is open; only the module's own
    -- countdown display is torn down here.
    if timerFrame and not self.isTimerPreview then timerFrame:Hide() end
end
