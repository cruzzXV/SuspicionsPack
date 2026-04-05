------------------------------------------------------------------------
-- SuspicionsPack — AutoPI Module
-- Power Infusion callout & request coordination between DPS and Priests
-- Ported from AutoPI (original by Shauna)
------------------------------------------------------------------------

local SP = SuspicionsPack

local AutoPI = SP:NewModule("AutoPI", "AceEvent-3.0")
SP.AutoPI = AutoPI

-- ============================================================
-- Constants
-- ============================================================
local ADDON_PREFIX   = "AutoPI"   -- matches standalone AutoPI for cross-addon interoperability
local PI_SPELL_ID    = 10060
C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)  -- register at load time, like standalone
local POPUP_DURATION = 15
local PI_BASE_CD     = 120

local MEDIA_PATH    = "Interface\\AddOns\\SuspicionsPack\\Media\\AutoPI\\"
local ALERT_SOUND   = MEDIA_PATH .. "Empowered.ogg"
local PI_RECV_SOUND = MEDIA_PATH .. "Pi.ogg"

-- ============================================================
-- State
-- ============================================================
local piSpellName    = "Power Infusion"
local piIconID       = 135939
local popupShowing   = false
local popupTimer     = 0
local popupRequester = nil
local frameIconGen   = 0
local piWasOnCD      = false
local piCastTime     = 0
local alertsUnlocked = false
local framesCreated  = false

-- Frame refs (created lazily in CreateFrames)
local popup, miniToast, frameIcon
local nameText, pIcon, mtText, mtIcon, mtFadeGroup, mtFadeAnim

-- ============================================================
-- DB helper
-- ============================================================
local function GetDB()
    return SP.db and SP.db.profile and SP.db.profile.autoPi
end

-- ============================================================
-- Helpers
-- ============================================================
local function Short(name)
    return name and Ambiguate(name, "short") or "?"
end

local function IsSelf(sender)
    return Short(sender) == UnitName("player")
end

local function BaseName(name)
    return name and name:match("^([^-]+)") or name
end

local function IsMyName(targetName)
    local myName = UnitName("player")
    return myName and BaseName(targetName):lower() == myName:lower()
end

local function IsAccepted(sender)
    local db = GetDB()
    if not db or not db.acceptFrom then return false end
    local senderBase = BaseName(sender):lower()
    for name in pairs(db.acceptFrom) do
        if BaseName(name):lower() == senderBase then return true end
    end
    return false
end

local function IsInMyGroup(playerName)
    if not playerName then return false end
    local search = BaseName(playerName):lower()
    for i = 1, GetNumGroupMembers() do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        local name = UnitName(unit)
        if name and name:lower() == search then return true end
    end
    return false
end

local function GetGroupChannel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

local function Send(msg)
    local ch = GetGroupChannel()
    if not ch then return false end
    C_ChatInfo.SendAddonMessage(ADDON_PREFIX, msg, ch)
    return true
end

local function FindUnit(playerName)
    local search = BaseName(playerName):lower()
    for i = 1, GetNumGroupMembers() do
        local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
        local name = UnitName(unit)
        if name and name:lower() == search then return unit end
    end
    return nil
end

local function FindUnitFrame(unit)
    if not unit then return nil end
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if f and f:IsShown() and f.unit == unit then return f end
    end
    for i = 1, 5 do
        local f = _G["CompactPartyFrameMember" .. i]
        if f and f:IsShown() and f.unit == unit then return f end
    end
    return nil
end

local function GetPICooldownRemaining()
    if piCastTime == 0 then return 0 end
    local remaining = (piCastTime + PI_BASE_CD) - GetTime()
    return remaining > 0 and remaining or 0
end

-- ============================================================
-- Alert actions — declared before use in frame scripts
-- ============================================================
local HideFrameIcon, ShowFrameIcon
local HidePopup, ShowPopup, ShowMiniToast
local SaveAlertPositions, ApplyPopupPosition, ApplyToastPosition, DismissAlerts

HideFrameIcon = function()
    if frameIcon then
        frameIcon:Hide()
        frameIconGen = frameIconGen + 1
    end
end

ShowFrameIcon = function(sender)
    if not frameIcon then return end
    local uf = FindUnitFrame(FindUnit(sender))
    if not uf then return end
    frameIcon:SetParent(uf)
    frameIcon:ClearAllPoints()
    frameIcon:SetPoint("CENTER", uf, "CENTER")
    frameIcon._fiTex:SetTexture(piIconID)
    frameIcon:Show()
    frameIconGen = frameIconGen + 1
    local myGen = frameIconGen
    C_Timer.After(POPUP_DURATION, function()
        if frameIconGen == myGen and frameIcon then frameIcon:Hide() end
    end)
end

HidePopup = function()
    if alertsUnlocked then return end
    popupShowing   = false
    popupRequester = nil
    if popup then popup:Hide() end
end

ShowPopup = function(sender)
    if alertsUnlocked or not framesCreated then return end
    nameText:SetText(Short(sender))
    pIcon:SetTexture(piIconID)
    popup:Show()
    popupTimer     = POPUP_DURATION
    popupShowing   = true
    popupRequester = sender
    PlaySoundFile(ALERT_SOUND, "Master")
    ShowFrameIcon(sender)
end

ShowMiniToast = function(text, holdTime)
    if alertsUnlocked or not framesCreated then return end
    mtText:SetText(text)
    mtIcon:SetTexture(piIconID)
    miniToast:SetAlpha(1)
    miniToast:Show()
    mtFadeGroup:Stop()
    mtFadeAnim:SetStartDelay(holdTime or 0.8)
    mtFadeGroup:Play()
end

-- Position helpers — always anchor to UIParent CENTER with stored X/Y offsets
ApplyPopupPosition = function()
    local db = GetDB()
    if not popup or not db then return end
    popup:ClearAllPoints()
    popup:SetPoint("CENTER", UIParent, "CENTER", db.popupX or 0, db.popupY or 200)
end

ApplyToastPosition = function()
    local db = GetDB()
    if not miniToast or not db then return end
    miniToast:ClearAllPoints()
    miniToast:SetPoint("CENTER", UIParent, "CENTER", db.toastX or 0, db.toastY or 240)
end

-- After dragging: compute CENTER-relative offset from current frame screen position
SaveAlertPositions = function()
    local db = GetDB()
    if not db then return end
    if popup and popup:IsShown() then
        local cx, cy = UIParent:GetCenter()
        local fx, fy = popup:GetCenter()
        if cx and fx then
            db.popupX = math.floor(fx - cx + 0.5)
            db.popupY = math.floor(fy - cy + 0.5)
        end
    end
    if miniToast and miniToast:IsShown() then
        local cx, cy = UIParent:GetCenter()
        local fx, fy = miniToast:GetCenter()
        if cx and fx then
            db.toastX = math.floor(fx - cx + 0.5)
            db.toastY = math.floor(fy - cy + 0.5)
        end
    end
end

DismissAlerts = function()
    if popupRequester then
        Send("ACK:" .. BaseName(popupRequester))
    end
    HidePopup()
    HideFrameIcon()
end

-- ============================================================
-- Frame creation (lazy — called on first OnEnable)
-- ============================================================
local BLANK = "Interface\\Buttons\\WHITE8X8"

local function GetAccent()
    local ac = SP.Theme and SP.Theme.accent
    return ac and ac[1] or 0.58, ac and ac[2] or 0.51, ac and ac[3] or 0.79
end

local function CreateFrames()
    if framesCreated then return end
    framesCreated = true

    local ar, ag, ab = GetAccent()

    -- ── Unit-frame icon overlay ──────────────────────────────
    frameIcon = CreateFrame("Frame", "SPAutoPI_FrameIcon", UIParent)
    frameIcon:SetSize(22, 22)
    frameIcon:SetFrameStrata("HIGH")
    frameIcon:SetFrameLevel(50)
    frameIcon:Hide()

    local fiBorder = frameIcon:CreateTexture(nil, "BORDER")
    fiBorder:SetAllPoints()
    fiBorder:SetColorTexture(0, 0, 0, 1)

    local fiTex = frameIcon:CreateTexture(nil, "ARTWORK")
    fiTex:SetPoint("TOPLEFT",     1, -1)
    fiTex:SetPoint("BOTTOMRIGHT", -1, 1)
    fiTex:SetTexture(piIconID)
    fiTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frameIcon._fiTex = fiTex

    -- ── Popup toast ──────────────────────────────────────────
    popup = CreateFrame("Frame", "SPAutoPI_Popup", UIParent, "BackdropTemplate")
    popup:SetSize(220, 56)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(100)
    popup:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    popup:SetBackdropColor(0.06, 0.02, 0.12, 0.92)
    popup:SetBackdropBorderColor(ar, ag, ab, 1)
    popup:Hide()

    local iconBdr = popup:CreateTexture(nil, "BORDER")
    iconBdr:SetSize(38, 38)
    iconBdr:SetPoint("LEFT", popup, "LEFT", 8, 0)
    iconBdr:SetColorTexture(0, 0, 0, 1)

    pIcon = popup:CreateTexture(nil, "ARTWORK")
    pIcon:SetSize(36, 36)
    pIcon:SetPoint("CENTER", iconBdr)
    pIcon:SetTexture(piIconID)
    pIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    nameText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOPLEFT", iconBdr, "TOPRIGHT", 8, -4)
    nameText:SetTextColor(1, 0.84, 0)

    local hintText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
    hintText:SetTextColor(0.6, 0.6, 0.6)
    hintText:SetText("wants Power Infusion")

    local popCloseBtn = CreateFrame("Button", nil, popup)
    popCloseBtn:SetSize(16, 16)
    popCloseBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -4, -4)
    popCloseBtn:SetFrameLevel(popup:GetFrameLevel() + 10)

    local popCloseLbl = popCloseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    popCloseLbl:SetText("X")
    popCloseLbl:SetTextColor(0.5, 0.5, 0.6)
    popCloseLbl:SetAllPoints()
    popCloseBtn:SetScript("OnEnter", function() popCloseLbl:SetTextColor(1, 0.3, 0.3) end)
    popCloseBtn:SetScript("OnLeave", function() popCloseLbl:SetTextColor(0.5, 0.5, 0.6) end)
    popCloseBtn:SetScript("OnClick", function() HidePopup(); HideFrameIcon() end)

    popup:SetScript("OnUpdate", function(_, elapsed)
        if not popupShowing then return end
        popupTimer = popupTimer - elapsed
        if popupTimer <= 0 then HidePopup(); HideFrameIcon() end
    end)

    -- ── Mini toast (CD / ready) ──────────────────────────────
    miniToast = CreateFrame("Frame", "SPAutoPI_MiniToast", UIParent, "BackdropTemplate")
    miniToast:SetSize(200, 34)
    miniToast:SetFrameStrata("DIALOG")
    miniToast:SetFrameLevel(99)
    miniToast:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    miniToast:SetBackdropColor(0.06, 0.02, 0.12, 0.92)
    miniToast:SetBackdropBorderColor(ar, ag, ab, 0.8)
    miniToast:Hide()

    local mtIconBdr = miniToast:CreateTexture(nil, "BORDER")
    mtIconBdr:SetSize(26, 26)
    mtIconBdr:SetPoint("LEFT", miniToast, "LEFT", 6, 0)
    mtIconBdr:SetColorTexture(0, 0, 0, 1)

    mtIcon = miniToast:CreateTexture(nil, "ARTWORK")
    mtIcon:SetSize(24, 24)
    mtIcon:SetPoint("CENTER", mtIconBdr)
    mtIcon:SetTexture(piIconID)
    mtIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    mtText = miniToast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mtText:SetPoint("LEFT",  mtIconBdr, "RIGHT", 6,  0)
    mtText:SetPoint("RIGHT", miniToast, "RIGHT", -8, 0)
    mtText:SetJustifyH("LEFT")
    mtText:SetTextColor(0.9, 0.9, 0.95)

    mtFadeGroup = miniToast:CreateAnimationGroup()
    mtFadeAnim  = mtFadeGroup:CreateAnimation("Alpha")
    mtFadeAnim:SetFromAlpha(1)
    mtFadeAnim:SetToAlpha(0)
    mtFadeAnim:SetDuration(0.4)
    mtFadeAnim:SetStartDelay(0.8)
    mtFadeGroup:SetScript("OnFinished", function()
        miniToast:Hide()
        miniToast:SetAlpha(1)
    end)

    -- ── Make frames movable when unlocked ────────────────────
    for _, f in ipairs({ popup, miniToast }) do
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self)
            if alertsUnlocked then self:StartMoving() end
        end)
        f:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            if alertsUnlocked then SaveAlertPositions() end
        end)
    end

    -- Apply saved positions
    ApplyPopupPosition()
    ApplyToastPosition()
end

-- ============================================================
-- GUI helper: unlock/lock alert frames for repositioning
-- ============================================================
function AutoPI:SetAlertLock(locked)
    alertsUnlocked = not locked
    if not framesCreated then return end
    local ar, ag, ab = GetAccent()
    if alertsUnlocked then
        -- Show preview mode so user can drag
        nameText:SetText("Preview")
        popup:SetBackdropBorderColor(ar, ag, ab, 1)
        popup:Show()
        mtText:SetText("Preview — PI ready!")
        miniToast:SetAlpha(1)
        miniToast:SetBackdropBorderColor(ar, ag, ab, 0.9)
        miniToast:Show()
        mtFadeGroup:Stop()
    else
        SaveAlertPositions()
        popup:SetBackdropBorderColor(ar, ag, ab, 1)
        popup:Hide()
        miniToast:SetBackdropBorderColor(ar, ag, ab, 0.8)
        miniToast:Hide()
        miniToast:SetAlpha(1)
    end
end

-- Preview: show alerts so the user can see / position them
function AutoPI:SetPreview(on)
    CreateFrames()
    local ar, ag, ab = GetAccent()
    if on then
        nameText:SetText("Preview — PI")
        popup:SetBackdropBorderColor(ar, ag, ab, 1)
        ApplyPopupPosition()
        popup:Show()
        mtText:SetText("Preview — PI ready!")
        miniToast:SetAlpha(1)
        miniToast:SetBackdropBorderColor(ar, ag, ab, 0.9)
        ApplyToastPosition()
        miniToast:Show()
        mtFadeGroup:Stop()
    else
        popup:Hide()
        miniToast:Hide()
        miniToast:SetAlpha(1)
    end
end

-- Called from GUI sliders to immediately reposition
function AutoPI:ApplyPopupPosition()  ApplyPopupPosition()  end
function AutoPI:ApplyToastPosition()  ApplyToastPosition()  end

-- ============================================================
-- Module lifecycle
-- ============================================================
function AutoPI:OnInitialize()
    local db = GetDB()
    if not db then return end
    if db.acceptFrom == nil then db.acceptFrom = {} end
    if db.notifyReady == nil then db.notifyReady = true end
end

function AutoPI:OnEnable()
    CreateFrames()
    if IsLoggedIn() then
        self:OnLogin()
    else
        self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
    end
    self:RegisterEvent("CHAT_MSG_ADDON",           "OnAddonMsg")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellCast")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN",    "OnCooldownUpdate")
end

function AutoPI:OnDisable()
    self:UnregisterAllEvents()
    if alertsUnlocked then self:SetAlertLock(true) end
    popupShowing   = false
    popupRequester = nil
    piWasOnCD      = false
    piCastTime     = 0
    if popup     then popup:Hide()     end
    if miniToast then miniToast:Hide() end
    if frameIcon then frameIcon:Hide() end
end

function AutoPI:OnLogin()
    local info = C_Spell.GetSpellInfo(PI_SPELL_ID)
    if info then
        piSpellName = info.name
        piIconID    = info.iconID
        if pIcon     then pIcon:SetTexture(piIconID)            end
        if frameIcon then frameIcon._fiTex:SetTexture(piIconID) end
        if mtIcon    then mtIcon:SetTexture(piIconID)           end
    end
end

function AutoPI:OnSpellCast(event, unit, _, spellID)
    if unit ~= "player" then return end
    if spellID ~= PI_SPELL_ID then return end
    piCastTime = GetTime()
    piWasOnCD  = true
    if popupShowing then DismissAlerts() end
end

function AutoPI:OnCooldownUpdate()
    if not piWasOnCD then return end
    if GetPICooldownRemaining() < 2 then
        piWasOnCD  = false
        piCastTime = 0
        Send("RDY")
    end
end

function AutoPI:OnAddonMsg(event, prefix, msg, dist, sender)
    if prefix ~= ADDON_PREFIX then return end
    if IsSelf(sender) then return end

    local db = GetDB()
    if not db then return end

    -- REQ:<priestName> — DPS requesting PI from their priest
    local targetPriest = msg:match("^REQ:(.+)$")
    if targetPriest then
        local _, myClass = UnitClass("player")
        if myClass ~= "PRIEST" then return end
        if not IsMyName(targetPriest) then return end
        if not IsAccepted(sender) then return end
        local cdLeft = GetPICooldownRemaining()
        if cdLeft > 10 then
            Send("CD:" .. math.ceil(cdLeft))
            return
        end
        ShowPopup(sender)
        return
    end

    -- CD:<seconds> — priest responding with cooldown remaining
    local cdSecs = msg:match("^CD:(%d+)$")
    if cdSecs then
        local targetBase = db.piTarget and BaseName(db.piTarget):lower()
        local senderBase = BaseName(sender):lower()
        if targetBase and senderBase == targetBase then
            ShowMiniToast(Short(sender) .. " - PI in |cffFFD100" .. cdSecs .. "s|r", 1.0)
        end
        return
    end

    -- RDY — priest broadcasting PI off cooldown
    if msg == "RDY" then
        if not db.notifyReady then return end
        local targetBase = db.piTarget and BaseName(db.piTarget):lower()
        local senderBase = BaseName(sender):lower()
        if targetBase and senderBase == targetBase then
            ShowMiniToast(Short(sender) .. " - |cff00ff00PI ready!|r", 1.5)
        end
        return
    end

    -- ACK:<dpsName> — priest confirming they are casting
    local targetDPS = msg:match("^ACK:(.+)$")
    if targetDPS then
        if not IsMyName(targetDPS) then return end
        print("|cff9482C9AutoPI:|r |cffFFD100" .. Short(sender) .. "|r is casting PI on you!")
        PlaySoundFile(PI_RECV_SOUND, "Master")
        return
    end
end

-- ============================================================
-- Slash commands
-- ============================================================
-- /pi  — DPS sends PI request to their priest
SLASH_SPPI1 = "/pi"
SlashCmdList["SPPI"] = function()
    local db = GetDB()
    if not db or not db.piTarget then return end
    if not IsInGroup() then return end
    if not IsInMyGroup(db.piTarget) then return end
    Send("REQ:" .. db.piTarget)
end

-- /picast  — Priest: dismiss the alert (they are casting)
SLASH_SPPICAST1 = "/picast"
SlashCmdList["SPPICAST"] = function()
    if popupShowing then DismissAlerts() end
end
