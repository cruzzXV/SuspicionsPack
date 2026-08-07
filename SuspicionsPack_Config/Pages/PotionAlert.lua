-- SuspicionsPack Options — Potion alert
--
-- The old version was 338 lines. The TTS voice list arrives asynchronously and
-- the old public dropdown built its popup eagerly, so a list that was empty on
-- the first visit stayed empty for ever. The page worked around that three ways:
-- it reached past GUI:CreateDropdown for the private lazy CreateDropdown, it
-- monkey-patched parent._onPageShow to rebuild the control on every page show,
-- and it parented a bare CreateFrame("Frame") to nothing so it could listen to
-- VOICE_CHAT_TTS_VOICES_UPDATE. That event frame was created once and never
-- unregistered; what leaked per rebuild was a dropdown button, since WoW cannot
-- destroy a frame and the old one was only hidden.
--
-- The dropdown here takes optionsFn, which W.Dropdown re-evaluates on every
-- Refresh, and GUI:RefreshContent refreshes a cached page every time it is
-- shown. All three workarounds are gone; this page creates no event frame and
-- rebuilds nothing.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

-- Enum.VoiceTtsDestination.LocalPlayback. Spelt out because the enum is not
-- guaranteed to exist on every client build this addon supports.
local TTS_LOCAL_PLAYBACK = 1

local function VoiceOptions()
    local out = {}
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
        if ok and voices then
            for _, v in ipairs(voices) do
                out[#out + 1] = {
                    key   = v.voiceID,
                    label = (v.name and v.name ~= "") and v.name
                            or ("Voice " .. tostring(v.voiceID)),
                }
            end
        end
    end
    -- The list is empty until Blizzard has enumerated the system voices. One
    -- placeholder keeps the control readable; the next Refresh replaces it.
    if #out == 0 then out[1] = { key = 0, label = "Default" } end
    return out
end

GUI.RegisterPage{
    id       = "potionalert",
    name     = "Potion alert",
    category = "combat",
    dbKey    = "potionAlert",
    keywords = "potion cooldown ready alert dungeon raid tts speech voice",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "potionAlert", "PotionAlert",
            "Potion alert",
            "Shows a text alert when your combat potion comes off cooldown. " ..
            "Works in any dungeon and in raids.",
            "Enable potion alert")

        c1:Pair(
            { kind = "toggle", key = "enabledInDungeons", label = "In dungeons" },
            { kind = "toggle", key = "enabledInRaids",    label = "In raids" })

        -- ── Display ──────────────────────────────────────────
        local c2 = page:Card("Display", "The alert text and how it is drawn.")
        c2:EditBox{ key = "displayText", label = "Alert text", maxLen = 64 }
        c2:FontDropdown{ key = "fontFace", label = "Font face" }
        c2:Pair(
            { kind = "slider",   key = "fontSize",    label = "Font size", min = 8, max = 60, step = 1 },
            { kind = "dropdown", key = "fontOutline", label = "Outline",
              options = { "NONE", "OUTLINE", "THICKOUTLINE" } })
        c2:ColorSource{ label = "Text colour", srcKey = "colorSource", colorKey = "color" }
        c2:Slider{ key = "displayDuration", label = "Display duration", suffix = "s",
                   desc = "How long the alert stays up. Zero leaves it on screen until it is cleared.",
                   min = 0, max = 30, step = 1 }

        -- ── Position ─────────────────────────────────────────
        local c3 = page:Card("Position",
            "Where the alert sits. It is previewed on screen while this window is open.")
        c3:AnchorRow{}
        c3:Pair(
            { kind = "slider", key = "x", label = "X offset", min = -2000, max = 2000, step = 1 },
            { kind = "slider", key = "y", label = "Y offset", min = -2000, max = 2000, step = 1 })

        -- ── Text to speech ───────────────────────────────────
        local c4 = page:Card("Text to speech",
            "Reads a line aloud through the game's own speech engine when the " ..
            "potion comes off cooldown.")
        local ttsOn = c4:Toggle{ key = "playTTS", label = "Speak the alert" }
        c4:GateBelow(ttsOn)
        local ttsTextRow = c4:EditBox{ key = "ttsText", label = "Spoken text", maxLen = 128 }
        c4:Slider{ key = "ttsVolume", label = "Speech volume", min = 0, max = 100, step = 1 }
        -- optionsFn, not a fixed list: the voices are enumerated asynchronously
        -- and the page may well be built before they arrive.
        c4:Dropdown{ key = "ttsVoiceId", label = "Voice", optionsFn = VoiceOptions }
        c4:ButtonRow{
            text  = "Test voice",
            width = 100,
            desc  = "Speaks the text above with the selected voice and volume.",
            onClick = function()
                -- The box only commits on focus loss, and WoW does NOT blur an
                -- EditBox when another frame is clicked -- so db.ttsText still
                -- held the previous line and the test spoke the wrong thing.
                -- ClearFocus runs the commit; reading the box is what is spoken
                -- either way.
                ttsTextRow.box:ClearFocus()
                local text = ttsTextRow:GetValue()
                if not text or text == "" then return end
                C_VoiceChat.SpeakText(db.ttsVoiceId or 0, text,
                    TTS_LOCAL_PLAYBACK, db.ttsVolume or 75, true)
            end,
        }

        -- A test line keeps talking over the game otherwise.
        parent:HookScript("OnHide", function()
            if C_VoiceChat and C_VoiceChat.StopSpeakingText then
                C_VoiceChat.StopSpeakingText()
            end
        end)

        page:Finish()
    end,
}
