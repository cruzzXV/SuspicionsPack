-- SuspicionsPack - WhisperAlert.lua
-- Plays a custom sound when a whisper or Battle.net whisper is received.
-- Forked from NorskenUI's QoL/Misc.lua (WhisperSounds) with improvements:
--   • Separate sounds for in-game whispers vs Battle.net whispers
--   • Configurable audio channel (Master / SFX / Music / Ambience / Dialog)
--   • "Mute in combat" option so arena noise doesn't double up with whisper pings
--   • Short debounce to prevent double-trigger when chat addons fire multiple events

local SP = SuspicionsPack

local WA = SP:NewModule("WhisperAlert", "AceEvent-3.0")
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
-- Activate / Deactivate — called by GUI toggle and lifecycle
-- ============================================================
function WA:Activate()
    local db = GetDB()
    if not db or not db.enabled then return end
    self:RegisterEvent("CHAT_MSG_WHISPER",    "OnWhisper")
    self:RegisterEvent("CHAT_MSG_BN_WHISPER", "OnBNetWhisper")
end

function WA:Deactivate()
    self:UnregisterAllEvents()
end

-- Called from GUI toggle (mirrors other modules' .Refresh pattern)
function WA.Refresh()
    local db = GetDB()
    if db and db.enabled then
        WA:Activate()
    else
        WA:Deactivate()
    end
end

-- ============================================================
-- AceAddon lifecycle
-- ============================================================
function WA:OnEnable()
    if IsLoggedIn() then
        local db = GetDB()
        if db and db.enabled then self:Activate() end
    else
        self:RegisterEvent("PLAYER_LOGIN", function()
            local db = GetDB()
            if db and db.enabled then self:Activate() end
        end)
    end
end

function WA:OnDisable()
    self:Deactivate()
end
