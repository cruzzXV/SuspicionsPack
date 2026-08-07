-- SuspicionsPack Options — Death alert
--
-- The old version was 319 lines and ran two enable-state systems that fought
-- each other: the master toggle's blanket loop re-enabled the TTS rows the audio
-- sub-state had just switched off, so turning Text to Speech off and then
-- touching the master toggle left its rows live. One GateBelow per sub-toggle
-- composes correctly and the bug is gone.
--
-- The per-role blocks were emitted from a ROLES loop that faked indentation with
-- two literal spaces in front of each label. They are one card per role here,
-- which also lets each card point its defaults at its own byRole sub-table.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

local DEF = SP.DEFAULTS and SP.DEFAULTS.profile and SP.DEFAULTS.profile.deathAlert or {}

local ROLES = {
    { key = "TANK",    title = "Tank"          },
    { key = "HEALER",  title = "Healer"        },
    { key = "DAMAGER", title = "Damage dealer" },
}

local ROLE_NOTE = "Per-role override, applied inside raids only. " ..
                  "In a party every death uses the settings above."

-- Re-read on every Refresh: the module builds the list from SOUNDKIT, and a list
-- captured once could not pick up a rebuild.
local function SoundOptions()
    local out = {}
    local mod = SP.DeathAlert
    for _, s in ipairs(mod and mod.Sounds or {}) do
        out[#out + 1] = { key = s.key, label = s.label }
    end
    return out
end

local function SoundKit(key)
    local mod = SP.DeathAlert
    for _, s in ipairs(mod and mod.Sounds or {}) do
        if s.key == key then return s.kit end
    end
end

GUI.RegisterPage{
    id       = "deathalert",
    name     = "Death alert",
    category = "combat",
    dbKey    = "deathAlert",
    keywords = "death died dead alert announce raid party sound tts speech role",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "deathAlert", "DeathAlert",
            "Death alert",
            "Shows a large on-screen message when a party or raid member dies, " ..
            "with the player's name in their class colour.",
            "Enable death alert")

        c1:Toggle{ key = "showForSelf", label = "Show when you die",
                   desc = "Announces your own death as well as your group's." }

        -- ── Display ──────────────────────────────────────────
        local c2 = page:Card("Display", "The message and how it is drawn.")
        c2:EditBox{ key = "displayText", label = "Message text", maxLen = 32,
                    desc = "Follows the player's name, so \"died\" reads as \"Cruzz died\"." }
        c2:FontDropdown{ key = "fontName", label = "Font face" }
        c2:Pair(
            { kind = "slider", key = "fontSize", label = "Font size",
              min = 12, max = 60, step = 1 },
            { kind = "slider", key = "messageDuration", label = "Duration", suffix = "s",
              min = 1, max = 10, step = 1 })

        -- ── Audio ────────────────────────────────────────────
        local c3 = page:Card("Audio",
            "A sound and a spoken line, both on the same two-second cooldown. " ..
            "With both switched on the sound takes priority.")

        local soundOn = c3:Toggle{ key = "playSound", label = "Play sound" }
        c3:GateBelow(soundOn)
        c3:Dropdown{ key = "sound", label = "Sound", optionsFn = SoundOptions }

        local previewHandle
        c3:ButtonRow{
            text  = "Preview sound",
            width = 110,
            onClick = function()
                local kit = SoundKit(db.sound or DEF.sound)
                if not kit then return end
                local ok, handle = PlaySound(kit, "Master")
                if ok then previewHandle = handle end
            end,
        }
        c3:EndGate()

        local ttsOn = c3:Toggle{ key = "playTTS", label = "Text to speech",
                                 desc = "Reads the death out through the game's TTS voice." }
        c3:GateBelow(ttsOn)
        c3:EditBox{ key = "ttsText", label = "Spoken text", maxLen = 80,
                    desc = "Use {name} where the player's name should go." }
        c3:Slider{ key = "ttsVolume", label = "Speech volume", min = 0, max = 100, step = 5 }
        c3:EndGate()

        -- ── Role overrides ───────────────────────────────────
        -- One card per role rather than one card with three faked sub-headings:
        -- each card can then point its default lookup at its own byRole entry,
        -- so showText / playSound resolve their real defaults.
        -- The same line on all three cards, not just the first: a reader who
        -- scrolls straight to Healer or Damage dealer otherwise gets no
        -- indication at all that these are raid-only.
        db.byRole = db.byRole or {}
        for _, role in ipairs(ROLES) do
            db.byRole[role.key] = db.byRole[role.key] or {}
            local rdb  = db.byRole[role.key]
            local card = page:Card(role.title, ROLE_NOTE,
                DEF.byRole and DEF.byRole[role.key])
            card:Toggle{ db = rdb, key = "showText",  label = "Show text" }
            card:Toggle{ db = rdb, key = "playSound", label = "Play sound" }
        end

        -- ── Position ─────────────────────────────────────────
        local c4 = page:Card("Position", "Where the message appears.")
        c4:AnchorRow{}
        c4:Pair(
            { kind = "slider", key = "x", label = "X offset", min = -2000, max = 2000, step = 1 },
            { kind = "slider", key = "y", label = "Y offset", min = -2000, max = 2000, step = 1 })

        -- A previewed sound outlives the page otherwise.
        parent:HookScript("OnHide", function()
            if previewHandle then
                StopSound(previewHandle, 200)
                previewHandle = nil
            end
        end)

        page:Finish()
    end,
}
