-- SuspicionsPack — PotionAlert Module
-- Shows a text alert when your combat potion comes off cooldown.

local SP = SuspicionsPack

local PotionAlert = SP:NewSPModule("PotionAlert", "potionAlert")
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

-- Localised with a fallback, matching BloodlustAlert/ReapPredict.
local _issecretvalue = issecretvalue or function() return false end


-- Font names now resolve through Core: SP.FONT_FACES is the single
-- source of truth and SP.ResolveFont falls back to the pack default.
-- The private table this used to carry SHADOWED LibSharedMedia, so any
-- font the user added via another addon silently became Expressway here.
local function GetFontPath(name)
    return SP.ResolveFont(name)
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
--
-- GetDB stays a file-local rather than folding into ModuleMixin:GetDB():
-- CheckCooldown is a plain local function with no `self` to reach the module
-- through, and it is also the body of a C_Timer callback.
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

-- Picks the potion the player actually carries.
--
-- This used to test GetItemCooldown's `enable` return, which is truthy for
-- every item id (and 0 would be truthy in Lua anyway), so it always returned
-- POTION_IDS[1]. For an item the player doesn't own GetItemCooldown reports
-- start=0, i.e. "ready", so the alert showed permanently in any dungeon.
local function FindTrackedPotion()
    local firstOwned
    for _, id in ipairs(POTION_IDS) do
        if (C_Item.GetItemCount(id) or 0) > 0 then
            firstOwned = firstOwned or id
            -- Prefer one that is currently on cooldown: that's the potion the
            -- player is actually using this fight.
            -- Guard before the truthiness test, not after: `start and ...`
            -- already branches on the value.
            local start = C_Item.GetItemCooldown(id)
            if not _issecretvalue(start) and start and start > 0 then
                return id
            end
        end
    end
    return firstOwned
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
        -- Player carries none. Clear the tracked state too, otherwise drinking
        -- your last potion leaves onCD stuck true and restocking later fires a
        -- spurious "potion ready" announcement.
        onCD = false
        CancelDisplayTimer()
        if frame then frame:Hide() end
        return
    end

    local start, duration = C_Item.GetItemCooldown(potion)
    -- Item cooldown fields can be secret values; comparing one taints execution.
    if _issecretvalue(start) or _issecretvalue(duration) then return end
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
-- Activate / Deactivate
--
-- Refresh, OnEnable and OnDisable all come from ModuleMixin -- see
-- Core/Module.lua. Every event registration lives in Activate, so a module the
-- user has switched off subscribes to nothing at all.
-- ============================================================
function PotionAlert:Activate()
    local db = GetDB()
    if not (db and db.enabled) then return end

    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnCooldownEvent")
    self:RegisterEvent("BAG_UPDATE_COOLDOWN",   "OnBagCooldown")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",  "OnCooldownEvent")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCooldownEvent")
    self:RegisterEvent("CHALLENGE_MODE_START",  "OnCooldownEvent")
    self:RegisterEvent("ENCOUNTER_START",        "OnEncounterStart")
    self:RegisterEvent("ENCOUNTER_END",          "OnEncounterEnd")

    self:ApplySettings()
end

function PotionAlert:Deactivate()
    self:UnregisterAllEvents()
    CancelDisplayTimer()
    CancelCDTimer()
    onCD = false
    -- Left alone while the GUI preview owns the frame: the old Refresh()
    -- deliberately kept the preview on screen when the module was switched off,
    -- and PreviewManager:Stop() -> HidePreview() is what clears it.
    if frame and not isPreview then frame:Hide() end
end

function PotionAlert:OnCooldownEvent()
    CheckCooldown()
end

-- Skip BAG_UPDATE_COOLDOWN if potion is already known to be on CD.
-- The fallback cdTimer handles expiry; no need to scan on every bag event.
function PotionAlert:OnBagCooldown()
    if not onCD then CheckCooldown() end
end

function PotionAlert:OnEncounterStart()
    -- Reset at pull to avoid a false positive at combat start.
    CancelDisplayTimer()
    CancelCDTimer()
    onCD = false
    if frame and not isPreview then frame:Hide() end
end

function PotionAlert:OnEncounterEnd()
    -- Re-check after boss kill or wipe — potion may now be ready.
    CheckCooldown()
end
