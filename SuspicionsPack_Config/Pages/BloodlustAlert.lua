-- SuspicionsPack Options — Bloodlust alert
--
-- The old version of this page was 415 lines. Ninety-four of them were a second
-- copy of CreateAnchorRow, hand-written purely because the module names its keys
-- timerAnchorFrom / timerAnchorTo / timerAnchorFrame instead of the four the
-- shared widget hardcoded. c:AnchorRow takes those names as fields, so the copy
-- collapses to one line.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

local DEF = SP.DEFAULTS and SP.DEFAULTS.profile and SP.DEFAULTS.profile.bloodlustAlert or {}

-- Read on every Refresh instead of captured once. The module builds its sound
-- list at load, and a list captured at page-build time could only go stale.
local function SoundOptions()
    local out = {}
    local mod = SP.BloodlustAlert
    for _, s in ipairs(mod and mod.Sounds or {}) do
        out[#out + 1] = { key = s.key, label = s.label }
    end
    return out
end

-- The file the Listen button should play, including the random case.
local function SoundFile(key)
    local mod  = SP.BloodlustAlert
    local list = mod and mod.Sounds
    if not list then return nil end
    if key == "random" then
        local choices = {}
        for _, s in ipairs(list) do
            if s.file then choices[#choices + 1] = s.file end
        end
        if #choices == 0 then return nil end
        return choices[math.random(#choices)]
    end
    for _, s in ipairs(list) do
        if s.key == key then return s.file end
    end
end

GUI.RegisterPage{
    id       = "bloodlustalert",
    name     = "Bloodlust alert",
    category = "combat",
    dbKey    = "bloodlustAlert",
    keywords = "bloodlust heroism time warp lust haste sated exhaustion sound countdown timer",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "bloodlustAlert", "BloodlustAlert",
            "Bloodlust alert",
            "Plays a sound when Bloodlust, Heroism or Time Warp goes out. Detection " ..
            "watches for the Sated / Exhaustion / Temporal Displacement debuff the " ..
            "buff leaves on you, so it is event driven and never polls.",
            "Enable bloodlust alert")

        -- The module's Refresh only starts and stops detection; the countdown
        -- frame re-reads its own settings in ApplyTimerSettings. The page's apply
        -- runs both, so a change lands on screen whichever card it came from.
        page.apply = function()
            local mod = SP.BloodlustAlert
            if not mod then return end
            if mod.Refresh            then mod:Refresh()            end
            if mod.ApplyTimerSettings then mod:ApplyTimerSettings() end
        end

        -- ── Audio ────────────────────────────────────────────
        local c2 = page:Card("Audio", "What is played, and which volume slider it obeys.")
        local playSound = c2:Toggle{ key = "playSound", label = "Play sound" }
        c2:GateBelow(playSound)

        -- "Random" shares the key with the pick: db.sound is either a sound key
        -- or the string "random". The dropdown therefore binds to the last real
        -- choice and only writes through while random is off, so switching random
        -- back off restores what was selected before.
        local lastSound = (db.sound and db.sound ~= "random") and db.sound or DEF.sound

        local soundRow = c2:Dropdown{
            label     = "Sound",
            optionsFn = SoundOptions,
            default   = DEF.sound,
            get       = function() return lastSound end,
            set       = function(v)
                lastSound = v
                if db.sound ~= "random" then db.sound = v end
            end,
        }

        local previewHandle
        local listenRow
        local function StopPreview()
            if previewHandle then
                StopSound(previewHandle, 200)
                previewHandle = nil
            end
            if listenRow then listenRow.btn:SetText("Listen") end
        end

        listenRow = c2:ButtonRow{
            text  = "Listen",
            width = 80,
            desc  = "Plays the current sound so you can judge the volume.",
            onClick = function()
                if previewHandle then StopPreview(); return end
                local file = SoundFile(db.sound or DEF.sound)
                if not file then return end
                local ok, handle = PlaySoundFile(file, "Master")
                if ok then
                    previewHandle = handle
                    listenRow.btn:SetText("Stop")
                end
            end,
        }

        local randomRow = c2:Toggle{
            label    = "Random sound",
            desc     = "Picks a different sound each time bloodlust is detected.",
            default  = false,
            get      = function() return db.sound == "random" end,
            set      = function(v) db.sound = v and "random" or lastSound end,
            onToggle = function()
                StopPreview()
                -- Not soundRow:SetEnabled(...) directly: the gates decide when
                -- the picker MAY be on, and the wrapper below decides whether
                -- random is currently taking that away. Re-running them asks
                -- both questions in the right order.
                page:ApplyGates()
            end,
        }

        -- The one condition the gate system cannot express: the sound picker is
        -- meaningless while Random is on. Applying it once after Finish() was not
        -- enough -- Page:ApplyGates re-enables every ungated row, and
        -- GUI:RefreshContent runs page:Refresh() (gates included) on EVERY show
        -- of a cached page, so navigating away and back left the picker live and
        -- a pick then wrote only a local. Folding it into the row's own
        -- SetEnabled makes it survive every gate pass, and it only ever takes
        -- away. `randomRow` is a local declared above, so the closure sees it.
        local soundSetEnabled = soundRow.SetEnabled
        function soundRow:SetEnabled(en)
            soundSetEnabled(self, (en and not randomRow:GetValue()) and true or false)
        end

        c2:Dropdown{ key = "channel", label = "Audio channel",
                     desc = "Volume slider the sound obeys.", options = GUI.CHANNELS }

        -- ── Timer display ────────────────────────────────────
        local c3 = page:Card("Timer display",
            "An optional countdown showing how much of the lust is left.")
        local timerOn = c3:Toggle{ key = "timerEnabled", label = "Enable timer" }
        c3:GateBelow(timerOn)

        -- The four keys the module actually uses. The old page reimplemented the
        -- whole widget rather than pass these three names.
        c3:AnchorRow{
            fromKey  = "timerAnchorFrom",
            toKey    = "timerAnchorTo",
            frameKey = "timerAnchorFrame",
            defaultStrata = "HIGH",
        }
        c3:Pair(
            { kind = "slider", key = "timerX", label = "X offset", min = -2000, max = 2000, step = 1 },
            { kind = "slider", key = "timerY", label = "Y offset", min = -2000, max = 2000, step = 1 })

        c3:FontDropdown{ key = "timerFontFace", label = "Font face", default = "Expressway" }
        c3:Pair(
            { kind = "slider",   key = "timerFontSize", label = "Font size", min = 10, max = 60, step = 1 },
            { kind = "dropdown", key = "timerOutline",  label = "Outline",
              options = GUI.OUTLINES, default = "OUTLINE" })
        c3:Pair(
            { kind = "toggle", key = "timerShowLabel", label = "Show label" },
            { kind = "toggle", key = "timerShowBar",   label = "Show bar" })
        c3:Slider{ key = "timerBgOpacity", label = "Backdrop opacity",
                   desc = "Opacity of the panel behind the countdown.",
                   min = 0, max = 1, step = 0.05 }
        c3:ColorSource{ label = "Number colour",
                        srcKey = "timerNumColorSource", colorKey = "timerNumColor" }
        c3:ColorSource{ label = "Bar colour",
                        srcKey = "timerBarColorSource", colorKey = "timerBarColor" }

        -- The Listen preview keeps playing over the game otherwise.
        parent:HookScript("OnHide", StopPreview)

        -- Finish applies the gates, which now go through the wrapper above, so
        -- the Random lock is in place from the first frame.
        page:Finish()
    end,
}
