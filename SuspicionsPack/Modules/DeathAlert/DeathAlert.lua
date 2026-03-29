-- SuspicionsPack — DeathAlert Module
-- Full fork of ItruliaQOL's DeathAlert.
-- Displays a large on-screen text when a party/raid member (or yourself) dies.
-- Features: display text, font name (LSM), font size, message duration, sound, TTS,
--           whitelist/blacklist, per-role overrides in raids (show text / play sound
--           per Tank/Healer/DPS).
--
-- Adaptations vs. ItruliaQOL:
--   • LibSharedMedia-3.0 used for font selection; falls back to Expressway if unavailable
--   • ElvUI/LEM frame movers not available → position via X/Y sliders
local SP = SuspicionsPack

local DeathAlert = SP:NewModule("DeathAlert", "AceEvent-3.0")
SP.DeathAlert = DeathAlert

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local DEFAULT_FONT_PATH = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"

local function GetFontPath(fontName)
    if LSM and fontName then
        local path = LSM:Fetch("font", fontName)
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

    -- Animation sequence: fade IN (0→1, 0.3s) → hold messageDuration → fade OUT (1→0, 1s)
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
-- Audio helper (shared 2-second cooldown to avoid spam)
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
-- Core logic: apply role overrides, then show
-- ============================================================
local function ProcessDeath(unitId, name, classToken)
    local db = GetDB()
    if not db then return end

    EnsureByRole(db)

    -- Start with global settings
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
        displayFrame.fs:SetAlpha(0)   -- start invisible; fadeIn animation brings it to 1
        displayFrame.animGroup:Stop()
        displayFrame.animGroup:Play()
    end

    -- Play sound / TTS
    TryPlayAudio(db, sound, ttsText, playSound, playTTS)
end

-- ============================================================
-- Event handler
-- ============================================================
function DeathAlert:OnUnitDied(_, deadGUID)
    if not deadGUID then return end
    if not canaccessvalue(deadGUID) then return end

    local unitToken = UnitTokenFromGUID(deadGUID)
    if not unitToken or not canaccessvalue(unitToken) then return end

    -- Hunters can feign death — verify truly dead
    if not UnitIsDead(unitToken) then return end

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
-- ============================================================
function DeathAlert:OnEnable()
    if IsLoggedIn() then
        self:OnLogin()
    else
        self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
    end
end

function DeathAlert:OnLogin()
    BuildSoundList()
    if LSM then
        LSM:Register("font", "Expressway", DEFAULT_FONT_PATH)
    end
    local db = GetDB()
    EnsureByRole(db)
    if db and db.enabled then
        EnsureFrame()
        RefreshFramePosition()
        self:RegisterEvent("UNIT_DIED", "OnUnitDied")
    end
end

function DeathAlert:OnDisable()
    self:UnregisterAllEvents()
    if displayFrame then
        displayFrame.animGroup:Stop()
        displayFrame.fs:SetText("")
    end
end

-- ============================================================
-- Preview — called by the GUI "Preview" button
-- ============================================================
function DeathAlert.Preview()
    local db = GetDB()
    if not db then return end
    EnsureFrame()
    RefreshFrameStyle()
    RefreshFramePosition()

    local name       = UnitName("player") or "Player"
    local _, clsTok  = UnitClass("player")
    local classColor = clsTok and C_ClassColor.GetClassColor(clsTok)
    local nameText   = classColor and classColor:WrapTextInColorCode(name) or name
    local msgText    = "|cffffffff" .. (db.displayText or "died") .. "|r"

    displayFrame.fs:SetText(nameText .. " " .. msgText)
    displayFrame.fs:SetAlpha(0)   -- start invisible; fadeIn animation brings it to 1
    displayFrame.animGroup:Stop()
    displayFrame.animGroup:Play()
end

-- ============================================================
-- StopPreview — stops the animation and clears the text immediately
-- ============================================================
function DeathAlert.StopPreview()
    if not displayFrame then return end
    displayFrame.animGroup:Stop()
    displayFrame.fs:SetText("")
    displayFrame.fs:SetAlpha(0)
end

-- ============================================================
-- Drag mode — called by the GUI "Drag to Move" / "Lock Position" button
-- ============================================================
function DeathAlert.StartDragMode()
    local db = GetDB()
    if not db then return end
    EnsureFrame()
    RefreshFrameStyle()
    RefreshFramePosition()

    -- Show placeholder text so the user can see where the frame is
    local name       = UnitName("player") or "Player"
    local _, clsTok  = UnitClass("player")
    local classColor = clsTok and C_ClassColor.GetClassColor(clsTok)
    local nameText   = classColor and classColor:WrapTextInColorCode(name) or name
    local msgText    = "|cffffffff" .. (db.displayText or "died") .. "|r"
    displayFrame.fs:SetText(nameText .. " " .. msgText)
    displayFrame.fs:SetAlpha(0.8)
    displayFrame.animGroup:Stop()

    -- Enable dragging
    displayFrame:EnableMouse(true)
    displayFrame:SetMovable(true)
    displayFrame:RegisterForDrag("LeftButton")
    displayFrame:SetScript("OnDragStart", function(f) f:StartMoving() end)
    displayFrame:SetScript("OnDragStop",  function(f)
        f:StopMovingOrSizing()
        -- Compute new offset from UIParent CENTER and reset anchor to CENTER/UIParent
        local cx,  cy  = f:GetCenter()
        local ucx, ucy = UIParent:GetCenter()
        db.anchorFrom  = "CENTER"
        db.anchorTo    = "CENTER"
        db.anchorFrame = "UIParent"
        db.x = math.floor(cx - ucx + 0.5)
        db.y = math.floor(cy - ucy + 0.5)
        -- Re-anchor cleanly so sliders stay consistent
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        -- Notify GUI to sync sliders
        if SP.DeathAlert._syncSliders then
            SP.DeathAlert._syncSliders(db.x, db.y)
        end
    end)
end

function DeathAlert.EndDragMode()
    if not displayFrame then return end
    displayFrame:StopMovingOrSizing()
    displayFrame:EnableMouse(false)
    displayFrame:SetMovable(false)
    displayFrame:SetScript("OnDragStart", nil)
    displayFrame:SetScript("OnDragStop",  nil)
    displayFrame:RegisterForDrag()
    -- Clear placeholder unless a real animation is running
    if not displayFrame.animGroup:IsPlaying() then
        displayFrame.fs:SetText("")
        displayFrame.fs:SetAlpha(0)
    end
end

-- Called by the GUI on any setting change
function DeathAlert.Refresh()
    local db  = GetDB()
    local mod = SP.DeathAlert
    if db then EnsureByRole(db) end
    if db and db.enabled then
        if not mod:IsEnabled() then mod:Enable() end
        EnsureFrame()
        RefreshFramePosition()
        RefreshFrameStyle()
        mod:RegisterEvent("UNIT_DIED", "OnUnitDied")
    else
        mod:UnregisterEvent("UNIT_DIED")
        if displayFrame then
            displayFrame.animGroup:Stop()
            displayFrame.fs:SetText("")
        end
    end
end
