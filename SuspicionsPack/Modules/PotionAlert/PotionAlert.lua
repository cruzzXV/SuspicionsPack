-- SuspicionsPack — PotionAlert Module
-- Shows a text alert when your combat potion comes off cooldown.

local SP = SuspicionsPack

local PotionAlert = SP:NewModule("PotionAlert", "AceEvent-3.0")
SP.PotionAlert = PotionAlert

-- ============================================================
-- Constants
-- ============================================================
local POTION_IDS = {
    -- The War Within
    212263, 212264, 212265,   -- Tempered Potion (ranks 1-3)
    -- Midnight
    241292, 241293,           -- Draught of Rampant Abandon
    241308, 241309,           -- Light's Potential
    241288,                   -- Potion of Recklessness
    245902,                   -- Fleeting Potion of Recklessness
}

local DEFAULT_FONT = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"

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

local function GetFontPath(name)
    return FONT_FACES[name]
        or (SP.GetFontPath and SP.GetFontPath(name))
        or DEFAULT_FONT
end

-- ============================================================
-- State
-- ============================================================
local onCD          = false   -- true while potion is on CD
local frame         = nil
local isPreview     = false
local displayTimer  = nil     -- C_Timer handle for auto-hide
local cdTimer       = nil     -- fallback timer for CD expiry

-- ============================================================
-- Helpers
-- ============================================================
local function GetDB()
    return SP.GetDB().potionAlert
end

local function InDungeon()
    local _, instanceType = GetInstanceInfo()
    return instanceType == "party"
end

local function InRaid()
    local _, instanceType = GetInstanceInfo()
    return instanceType == "raid"
end

local function CancelDisplayTimer()
    if displayTimer then
        displayTimer:Cancel()
        displayTimer = nil
    end
end

local function CancelCDTimer()
    if cdTimer then
        cdTimer:Cancel()
        cdTimer = nil
    end
end

local function FindTrackedPotion()
    for _, id in ipairs(POTION_IDS) do
        local _, _, enabled = C_Container.GetItemCooldown(id)
        if enabled then return id end
    end
    return nil
end

-- ============================================================
-- Frame construction
-- ============================================================
local function BuildFrame()
    if frame then return end

    local f = CreateFrame("Frame", "SPPotionAlertFrame", UIParent)
    f:SetSize(180, 36)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(100)
    f:EnableMouse(false)

    local lbl = f:CreateFontString(nil, "OVERLAY")
    lbl:SetAllPoints()
    lbl:SetFont(DEFAULT_FONT, 20, "OUTLINE")
    lbl:SetJustifyH("CENTER")
    lbl:SetJustifyV("MIDDLE")
    f.lbl = lbl

    f:Hide()
    frame = f
end

-- ============================================================
-- Apply settings from DB
-- ============================================================
function PotionAlert:ApplySettings()
    BuildFrame()
    if not frame then return end
    local db = GetDB()
    if not db then return end

    local fontPath  = GetFontPath(db.fontFace or "Expressway")
    local fontSize  = db.fontSize or 20
    local outline   = db.fontOutline ~= "NONE" and (db.fontOutline or "OUTLINE") or ""
    frame.lbl:SetFont(fontPath, fontSize, outline)
    frame.lbl:SetText(db.displayText or "Potion ready")

    local cr, cg, cb = SP.GetColorFromSource(db.colorSource or "custom",
        db.color or { 0.4, 1, 0.4 })
    frame.lbl:SetTextColor(cr, cg, cb, 1)

    frame:ClearAllPoints()
    local anchorFrom  = db.anchorFrom  or "CENTER"
    local anchorTo    = db.anchorTo    or "CENTER"
    local anchorFrame = _G[db.anchorFrame or "UIParent"] or UIParent
    frame:SetPoint(anchorFrom, anchorFrame, anchorTo, db.x or 0, db.y or 200)
    frame:SetFrameStrata(db.frameStrata or "HIGH")

    C_Timer.After(0, function()
        if not frame then return end
        local w = math.max(frame.lbl:GetStringWidth()  + 20, 80)
        local h = math.max(frame.lbl:GetStringHeight() + 10, 26)
        frame:SetSize(w, h)
    end)
end

-- ============================================================
-- Preview
-- ============================================================
function PotionAlert:ShowPreview()
    BuildFrame()
    isPreview = true
    self:ApplySettings()
    if frame then
        frame:EnableMouse(false)
        frame:Show()
    end
end

function PotionAlert:HidePreview()
    isPreview = false
    if not frame then return end
    frame:EnableMouse(false)
    frame:Hide()
    local db = GetDB()
    if db and db.enabled then
        C_Timer.After(0, function() PotionAlert:OnCooldownEvent() end)
    end
end

-- ============================================================
-- Detection
-- ============================================================
local function CheckCooldown()
    local db = GetDB()
    if not (db and db.enabled) then return end
    if isPreview then return end

    local inM = InDungeon()
    local inR = InRaid() and UnitAffectingCombat("player")
    if not ((db.enabledInDungeons and inM) or (db.enabledInRaids and inR)) then
        if frame then frame:Hide() end
        return
    end

    local potion = FindTrackedPotion()
    if not potion then
        if frame then frame:Hide() end
        return
    end

    local start = C_Container.GetItemCooldown(potion)
    if start == 0 then
        if onCD then
            if db.playTTS and db.ttsText and db.ttsText ~= "" then
                C_VoiceChat.SpeakText(db.ttsVoiceId or 0, db.ttsText, 1, db.ttsVolume or 75, true)
            end
        end
        onCD = false
        CancelDisplayTimer()
        BuildFrame()
        PotionAlert:ApplySettings()
        if frame then
            frame:Show()
            local dur = db.displayDuration or 0
            if dur > 0 then
                displayTimer = C_Timer.NewTimer(dur, function()
                    displayTimer = nil
                    if frame and not isPreview then
                        frame:Hide()
                    end
                end)
            end
        end
    else
        onCD = true
        CancelDisplayTimer()
        CancelCDTimer()
        if frame then frame:Hide() end
        -- BAG_UPDATE_COOLDOWN ne fire pas toujours à l'expiration, timer de secours.
        local _, duration = C_Container.GetItemCooldown(potion)
        if duration and duration > 0 then
            local remaining = (start + duration) - GetTime()
            if remaining > 0 then
                cdTimer = C_Timer.NewTimer(remaining + 0.5, function()
                    cdTimer = nil
                    CheckCooldown()
                end)
            end
        end
    end
end

-- ============================================================
-- AceAddon lifecycle
-- ============================================================
function PotionAlert:OnEnable()
    local db = GetDB()
    if not (db and db.enabled) then return end
    self:_RegisterEvents()
    self:ApplySettings()
end

function PotionAlert:OnDisable()
    self:UnregisterAllEvents()
    CancelDisplayTimer()
    CancelCDTimer()
    onCD      = false
    isPreview = false
    if frame then frame:Hide() end
end

function PotionAlert:_RegisterEvents()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCooldownEvent")
    self:RegisterEvent("BAG_UPDATE_COOLDOWN",   "OnCooldownEvent")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnCooldownEvent")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",  "OnCooldownEvent")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCooldownEvent")
    self:RegisterEvent("ENCOUNTER_START",        "OnEncounterStart")
end

function PotionAlert:OnCooldownEvent()
    CheckCooldown()
end

function PotionAlert:OnEncounterStart()
    -- reset au pull pour éviter un faux positif au début du combat
    CancelDisplayTimer()
    CancelCDTimer()
    onCD = false
    if frame and not isPreview then frame:Hide() end
end

-- ============================================================
-- Refresh
-- ============================================================
function PotionAlert:Refresh()
    local db = GetDB()
    if not db then return end

    if db.enabled then
        if not self:IsEnabled() then self:Enable(); return end
        self:UnregisterAllEvents()
        self:_RegisterEvents()
        self:ApplySettings()
    else
        self:UnregisterAllEvents()
        onCD = false
        if frame and not isPreview then frame:Hide() end
    end
end
