-- SuspicionsPack — DeathAlert Module
-- Affiche un texte à l'écran quand un membre du groupe meurt.
local SP = SuspicionsPack

local DeathAlert = SP:NewSPModule("DeathAlert", "deathAlert")
SP.DeathAlert = DeathAlert

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local DEFAULT_FONT_PATH = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"

local function GetFontPath(fontName)
    if fontName then
        local path = SP.GetFontPath and SP.GetFontPath(fontName)
        if path then return path end
    end
    return DEFAULT_FONT_PATH
end

-- ============================================================
-- Sound list  (built after PLAYER_LOGIN so SOUNDKIT is guaranteed available)
-- ============================================================
DeathAlert.Sounds = {}

local function BuildSoundList()
    -- Some SOUNDKIT constants were removed in TWW; fall back to READY_CHECK for any that are nil.
    local RC = SOUNDKIT.READY_CHECK
    DeathAlert.Sounds = {
        { key = "readycheck", label = "Ready Check",   kit = RC },
        { key = "decline",    label = "Decline",        kit = SOUNDKIT.IG_PLAYER_INVITE_DECLINE    or RC },
        { key = "close",      label = "Close",          kit = SOUNDKIT.AUCTION_WINDOW_CLOSE        or RC },
        { key = "abandon",    label = "Quest Abandon",  kit = SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST  or RC },
        { key = "error",      label = "Error",          kit = SOUNDKIT.IG_CREATURE_AGGRO_SELECT    or RC },
    }
end

local function GetSoundKit(key)
    for _, s in ipairs(DeathAlert.Sounds) do
        if s.key == key then return s.kit end
    end
    return SOUNDKIT.READY_CHECK
end

-- ============================================================
-- DB helper
--
-- Kept as a file-local rather than folded into ModuleMixin:GetDB(): EnsureFrame,
-- RefreshFrameStyle, RefreshFramePosition and ProcessDeath below are plain local
-- functions with no `self` to reach the module through.
-- ============================================================
local function GetDB()
    return SP.GetDB().deathAlert
end

-- ============================================================
-- Helpers
-- ============================================================

-- Ensure byRole table always has all three roles (migration safety)
local function EnsureByRole(db)
    db.byRole = db.byRole or {}
    for _, role in ipairs({ "DAMAGER", "HEALER", "TANK" }) do
        db.byRole[role] = db.byRole[role] or { showText = true, playSound = true }
    end
end

-- ============================================================
-- Display frame (lazy-created on first use)
-- ============================================================
local displayFrame      = nil
local lastSoundPlayedAt = nil

local function EnsureFrame()
    if displayFrame then return end
    local db = GetDB()

    local f = CreateFrame("Frame", "SP_DeathAlertFrame", UIParent)
    f:SetSize(600, 60)
    f:SetFrameStrata(db.frameStrata or "HIGH")
    f:SetFrameLevel(100)
    f:EnableMouse(false)
    local anchorFrame0 = _G[db.anchorFrame or "UIParent"] or UIParent
    f:SetPoint(db.anchorFrom or "CENTER", anchorFrame0, db.anchorTo or "CENTER", db.x or 0, db.y or 200)

    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    fs:SetFont(GetFontPath(db.fontName), db.fontSize or 28, "OUTLINE")
    fs:SetShadowOffset(0, 0)
    fs:SetShadowColor(0, 0, 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetText("")
    fs:SetAlpha(0)

    local animGroup = fs:CreateAnimationGroup()
    animGroup:SetScript("OnFinished", function() fs:SetText("") ; fs:SetAlpha(0) end)

    local fadeIn = animGroup:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.3)
    fadeIn:SetOrder(1)

    local fadeOut = animGroup:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(1)
    fadeOut:SetStartDelay(db.messageDuration or 4)
    fadeOut:SetOrder(2)

    f.fs        = fs
    f.animGroup = animGroup
    f.fadeIn    = fadeIn
    f.fadeOut   = fadeOut

    displayFrame = f
end

local function RefreshFrameStyle()
    if not displayFrame then return end
    local db = GetDB()
    displayFrame.fs:SetFont(GetFontPath(db.fontName), db.fontSize or 28, "OUTLINE")
    displayFrame.fs:SetShadowOffset(0, 0)
    displayFrame.fs:SetShadowColor(0, 0, 0, 0)
    displayFrame.fadeOut:SetStartDelay(db.messageDuration or 4)
end

local function RefreshFramePosition()
    if not displayFrame then return end
    local db = GetDB()
    local anchorFrame = _G[db.anchorFrame or "UIParent"] or UIParent
    displayFrame:ClearAllPoints()
    displayFrame:SetPoint(db.anchorFrom or "CENTER", anchorFrame, db.anchorTo or "CENTER", db.x or 0, db.y or 200)
    displayFrame:SetFrameStrata(db.frameStrata or "HIGH")
end

-- ============================================================
-- Audio helper
-- ============================================================
local function TryPlayAudio(db, sound, ttsText, playSound, playTTS)
    local now = GetTime()
    if lastSoundPlayedAt and (now - lastSoundPlayedAt) < 2 then return end

    if playSound then
        lastSoundPlayedAt = now
        PlaySound(GetSoundKit(sound or "readycheck"), "Master")
    elseif playTTS and ttsText and ttsText ~= "" then
        lastSoundPlayedAt = now
        C_VoiceChat.SpeakText(0, ttsText, 1, db.ttsVolume or 50, true)
    end
end

-- ============================================================
-- Core logic
-- ============================================================
local function ProcessDeath(unitId, name, classToken)
    local db = GetDB()
    if not db then return end

    EnsureByRole(db)

    local showText  = true
    local playSound = db.playSound
    local sound     = db.sound
    local playTTS   = db.playTTS
    local ttsText   = (db.ttsText or "{name} died"):gsub("{name}", name)

    -- Role-based overrides (raid only)
    if UnitInRaid(unitId) then
        local role = UnitGroupRolesAssigned(unitId)
        if role == "NONE" then role = "DAMAGER" end
        local byRole = db.byRole[role]
        if byRole then
            showText  = byRole.showText  ~= false
            playSound = playSound and (byRole.playSound ~= false)
        end
    end

    -- Show text
    if showText then
        EnsureFrame()
        RefreshFrameStyle()

        local classColor = classToken and C_ClassColor.GetClassColor(classToken)
        local nameText   = classColor and classColor:WrapTextInColorCode(name) or name
        local msgText    = "|cffffffff" .. (db.displayText or "died") .. "|r"

        displayFrame.fs:SetText(nameText .. " " .. msgText)
        displayFrame.fs:SetAlpha(0)
        displayFrame.animGroup:Stop()
        displayFrame.animGroup:Play()
    end

    -- Play sound / TTS
    TryPlayAudio(db, sound, ttsText, playSound, playTTS)
end

-- ============================================================
-- Safe UnitTokenFromGUID wrapper
-- ============================================================
local function SafeUnitTokenFromGUID(guid)
    if not guid or hasanysecretvalues(guid) then return nil end

    local token = UnitTokenFromGUID(guid)
    if token then return token end

    if guid == UnitGUID("player") then return "player" end

    if IsInRaid() then
        for i = 1, 40 do
            local unit = "raid" .. i
            if guid == UnitGUID(unit) then return unit end
        end
    end

    if IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            if guid == UnitGUID(unit) then return unit end
        end
    end

    return nil
end

-- ============================================================
-- Event handler
-- ============================================================
function DeathAlert:OnUnitDied(_, deadGUID)
    if not deadGUID then return end

    local unitToken = SafeUnitTokenFromGUID(deadGUID)

    -- Hunters can feign death — verify truly dead
    if not unitToken or not UnitIsDead(unitToken) then return end

    local db      = GetDB()
    local isSelf  = (unitToken == "player")
    local inGroup = UnitInParty(unitToken) or UnitInRaid(unitToken)

    if not (inGroup or (isSelf and db.showForSelf)) then return end

    local name = UnitName(unitToken)
    if not name or not canaccessvalue(name) then return end

    local _, classToken = UnitClass(unitToken)
    ProcessDeath(unitToken, name, classToken)
end

-- ============================================================
-- Module lifecycle
--
-- OnEnable/OnLogin are kept instead of ModuleMixin's: the sound list and the
-- LibSharedMedia font registration have to happen at login whether or not the
-- feature is switched on, because the GUI dropdown reads DeathAlert.Sounds even
-- while the module is off. Refresh and OnDisable come from ModuleMixin --
-- see Core/Module.lua.
-- ============================================================
-- Media registration must happen whether or not the feature is switched on:
-- the GUI reads DeathAlert.Sounds for its dropdown, and "Expressway" is the
-- pack's default font for EVERY module. Both used to sit in OnEnable, which the
-- login sweep skips for a disabled module.
do
    BuildSoundList()
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    if lsm then lsm:Register("font", "Expressway", DEFAULT_FONT_PATH) end
end

function DeathAlert:OnEnable()
    if IsLoggedIn() then
        self:OnLogin()
    else
        self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
    end
end

function DeathAlert:OnLogin()
    self:UnregisterEvent("PLAYER_LOGIN")
    BuildSoundList()
    if LSM then
        LSM:Register("font", "Expressway", DEFAULT_FONT_PATH)
    end
    local db = GetDB()
    if db then EnsureByRole(db) end
    self:Refresh()
end

-- ============================================================
-- Activate / Deactivate
-- ============================================================
function DeathAlert:Activate()
    local db = GetDB()
    if not (db and db.enabled) then return end

    EnsureByRole(db)
    EnsureFrame()
    RefreshFramePosition()
    RefreshFrameStyle()
    self:RegisterEvent("UNIT_DIED", "OnUnitDied")
end

function DeathAlert:Deactivate()
    if displayFrame then displayFrame:Hide() end
    self:UnregisterEvent("UNIT_DIED")
    if displayFrame then
        displayFrame.animGroup:Stop()
        displayFrame.fs:SetText("")
        displayFrame.fs:SetAlpha(0)
    end
    lastSoundPlayedAt = nil
end
