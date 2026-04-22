-- SuspicionsPack — BloodlustAlert Module
-- Detects Bloodlust / Heroism / Time Warp via UNIT_AURA debuff tracking.
--
-- Detection approach (TWW 12.0.5+):
--   UnitSpellHaste() now returns a secret number value — arithmetic on it
--   crashes. Instead we watch for the Sated/Exhaustion/Temporal Displacement
--   debuffs that Blizzard applies to the player when BL fires.
--
--   On UNIT_AURA (player):
--     • Fast path: updateInfo.addedAuras contains one of the exhaustion debuff IDs
--     • Slow path (isFullUpdate): scan with C_UnitAuras.GetPlayerAuraBySpellID,
--       confirm freshness (applied < EXHAUST_FRESH_WINDOW seconds ago)
--
--   All spellId reads from addedAuras are guarded with issecretvalue().
--
-- Inspired by Ayije_CDM's CustomBuffs.lua bloodlust detection.

local SP = SuspicionsPack

local BLAlert = SP:NewModule("BloodlustAlert", "AceEvent-3.0")
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
}

local SOUND_FILES = {}
for _, s in ipairs(BLAlert.Sounds) do SOUND_FILES[s.key] = s.file end

local DEFAULT_SOUND        = "hotnigga"
local BL_DURATION          = 40    -- seconds (matches Bloodlust / Heroism / Time Warp)
local EXHAUST_FRESH_WINDOW = 5     -- aura must have been applied within last N seconds

-- Sated/Exhaustion debuff IDs applied to the player when any BL-type effect fires.
-- We detect BL by watching for these debuffs appearing, not by reading haste.
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

-- Raw frame for UNIT_AURA — AceEvent-3.0 doesn't support RegisterUnitEvent,
-- so we mirror Ayije_CDM's approach: dedicated frame registered only for "player".
local unitAuraFrame = CreateFrame("Frame")
unitAuraFrame:SetScript("OnEvent", function(_, event, unit, updateInfo)
    BLAlert:OnUnitAura(event, unit, updateInfo)
end)

local BL_FONT = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"

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
BLAlert.FontFaceOrder = {
    "Expressway", "Friz Quadrata", "Arial Narrow", "Morpheus",
    "Skurri", "Damage", "Ambiguity", "Nimrod MT",
}

local function GetFontPath(name)
    return FONT_FACES[name]
        or (SP.GetFontPath and SP.GetFontPath(name))
        or BL_FONT
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

    local movableLbl = f:CreateFontString(nil, "OVERLAY")
    movableLbl:SetPoint("TOP", f, "TOP", 0, 14)
    movableLbl:SetFont(BL_FONT, 8, "OUTLINE")
    movableLbl:SetTextColor(1, 0.82, 0, 1)
    movableLbl:SetText("MOVABLE")
    movableLbl:Hide()
    f.movableLbl = movableLbl

    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing()
        local db = SP.GetDB().bloodlustAlert
        if db then
            local cx,  cy  = self:GetCenter()
            local ucx, ucy = UIParent:GetCenter()
            db.timerAnchorFrom  = "CENTER"
            db.timerAnchorTo    = "CENTER"
            db.timerAnchorFrame = "UIParent"
            db.timerX           = math.floor(cx - ucx + 0.5)
            db.timerY           = math.floor(cy - ucy + 0.5)
        end
    end)

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
-- ============================================================
local function GetDB()
    return SP.GetDB().bloodlustAlert
end

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
-- Returns true if a fresh exhaustion debuff was just applied.
-- ============================================================

function BLAlert:OnUnitAura(event, unit, updateInfo)
    local db = GetDB()
    if not (db and db.enabled) then return end
    if active or not armed then return end

    -- Fast path (non-full updates only): bail early if none of the exhaustion
    -- debuffs appear in addedAuras — avoids the more expensive API scan below.
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

    -- Confirmation (mirrors Ayije_CDM exactly): always verify via
    -- GetPlayerAuraBySpellID + freshness < 40 s (covers mid-BL zone changes too).
    for _, spellId in ipairs(EXHAUSTION_IDS) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
        if aura and aura.expirationTime then
            local dur = aura.duration
            if not dur or dur <= 0 then dur = 600 end
            local appliedTime = aura.expirationTime - dur
            if (GetTime() - appliedTime) < 40 then
                self:StartBL()
                return
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
    local db = GetDB()
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
    BuildTimerFrame()
    self:ApplyTimerSettings()
    if timerFrame then
        timerFrame.num:SetText("40")
        if timerFrame.barFill:IsShown() then
            timerFrame.barFill:SetWidth(timerFrame.barMaxW or 98)
        end
        if timerFrame.movableLbl then timerFrame.movableLbl:Show() end
        timerFrame:Show()
    end
end

function BLAlert:HideTimerPreview()
    if timerFrame then
        if timerFrame.movableLbl then timerFrame.movableLbl:Hide() end
        if not active then timerFrame:Hide() end
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
    local db  = GetDB()
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
            if timerFrame.movableLbl then timerFrame.movableLbl:Hide() end
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

-- ============================================================
-- AceAddon lifecycle
-- ============================================================
function BLAlert:OnEnable()
    if IsLoggedIn() then
        self:OnLogin()
    else
        self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
    end
end

function BLAlert:OnDisable()
    self:UnregisterAllEvents()
    unitAuraFrame:UnregisterEvent("UNIT_AURA")
    if active then self:StopBL() end
    active = false
    armed  = true
    if rearmTimer  then rearmTimer:Cancel();  rearmTimer  = nil end
    if fadeTimer   then fadeTimer:Cancel();   fadeTimer   = nil end
    if timerTicker then timerTicker:Cancel(); timerTicker = nil end
    blStartTime = nil
    if timerFrame then timerFrame:Hide() end
end

function BLAlert:OnLogin()
    local db = GetDB()
    if not (db and db.enabled) then return end
    unitAuraFrame:RegisterUnitEvent("UNIT_AURA", "player")
    self:RegisterEvent("PLAYER_DEAD",           "OnPlayerDead")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
end

function BLAlert:OnPlayerDead()
    if active then self:StopBL() end
end

function BLAlert:OnEnteringWorld()
    if active then self:StopBL() end
end

-- ============================================================
-- Refresh (called by GUI toggle)
-- ============================================================
function BLAlert:Refresh()
    local db = GetDB()
    if not db then return end

    if db.enabled then
        if not self:IsEnabled() then self:Enable() end
        unitAuraFrame:RegisterUnitEvent("UNIT_AURA", "player")
        self:RegisterEvent("PLAYER_DEAD",           "OnPlayerDead")
        self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
    else
        unitAuraFrame:UnregisterEvent("UNIT_AURA")
        self:UnregisterEvent("PLAYER_DEAD")
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if active then self:StopBL() end
    end
end
