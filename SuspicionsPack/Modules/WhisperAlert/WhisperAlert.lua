-- SuspicionsPack - WhisperAlert.lua
-- Plays a custom sound when a whisper or Battle.net whisper is received.

local SP = SuspicionsPack

local WA = SP:NewSPModule("WhisperAlert", "whisperAlert")
SP.WhisperAlert = WA

-- ============================================================
-- Locals
-- ============================================================
local PlaySoundFile = PlaySoundFile
local GetTime       = GetTime
local UnitAffectingCombat = UnitAffectingCombat

local SP_LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Register our bundled whisper sound into LSM so it appears in every sound dropdown
local WA_SOUND_KEY  = "SuspicionsPack Whisper"
local WA_SOUND_FILE = "Interface\\AddOns\\SuspicionsPack\\Media\\Sounds\\Whisper.ogg"
if SP_LSM then
    SP_LSM:Register("sound", WA_SOUND_KEY, WA_SOUND_FILE)
end

-- ============================================================
-- DB helper
-- Kept as a file local: PlayAlert() is a file-scope function with no `self`.
-- ============================================================
local function GetDB()
    return SP.GetDB().whisperAlert
end

-- ============================================================
-- Sound playback
-- ============================================================
local DEBOUNCE     = 0.5   -- seconds — prevents double-trigger from split events
local lastPlayedAt = 0

local function PlayAlert(soundName, channel)
    if not soundName or soundName == "None" then return end

    -- Debounce: ignore bursts of events
    local now = GetTime()
    if (now - lastPlayedAt) < DEBOUNCE then return end
    lastPlayedAt = now

    local db = GetDB()

    -- Optional: silence while in combat
    if db and db.muteInCombat and UnitAffectingCombat("player") then return end

    local file = SP_LSM and SP_LSM:Fetch("sound", soundName)
    if not file then return end

    PlaySoundFile(file, channel or "Master")
end

-- ============================================================
-- Event handlers
-- ============================================================
function WA:OnWhisper()
    local db = GetDB()
    PlayAlert(db and db.sound, db and db.channel or "Master")
end

function WA:OnBNetWhisper()
    local db = GetDB()
    PlayAlert(db and db.bnetSound, db and db.channel or "Master")
end

-- ============================================================
-- Activate / Deactivate
-- Everything else (Refresh / OnEnable / OnDisable) comes from SP.ModuleMixin.
-- ============================================================
function WA:Activate()
    if not self:IsOn() then return end
    self:RegisterEvent("CHAT_MSG_WHISPER",    "OnWhisper")
    self:RegisterEvent("CHAT_MSG_BN_WHISPER", "OnBNetWhisper")
end

function WA:Deactivate()
    self:UnregisterAllEvents()
end
