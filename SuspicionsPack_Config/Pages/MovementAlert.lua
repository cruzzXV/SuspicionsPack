-- SuspicionsPack Options — Movement alert
--
-- The old version was 468 lines. The Time Spiral icon reused the shared anchor
-- widget by wrapping the DB in a setmetatable proxy that remapped anchorFrame /
-- anchorFrom / anchorTo / frameStrata onto the timeSpiralIcon* keys, because the
-- widget's key names were hardcoded. c:AnchorRow takes the names as fields, so
-- the proxy is gone.
--
-- Two things here outlive the page -- the LSM sound preview and the Time Spiral
-- preview, which installs a callback on the module object -- and both are torn
-- down in the OnHide hook at the bottom.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

local DEF = SP.DEFAULTS and SP.DEFAULTS.profile and SP.DEFAULTS.profile.movementAlert or {}

local function LSM() return LibStub and LibStub("LibSharedMedia-3.0", true) end

-- Sorted list of LibSharedMedia sounds with "None" pinned to the top. Read on
-- every Refresh so a sound pack loaded after this page was built shows up.
local function SoundOptions()
    local names = {}
    local lsm = LSM()
    if lsm then
        for name in pairs(lsm:HashTable("sound")) do
            if name ~= "None" then names[#names + 1] = name end
        end
        table.sort(names)
    end
    table.insert(names, 1, "None")
    return GUI.StrOptions(names)
end

GUI.RegisterPage{
    id       = "movementalert",
    name     = "Movement alert",
    category = "combat",
    dbKey    = "movementAlert",
    keywords = "movement mobility cooldown dash charge blink time spiral free movement",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "movementAlert", "MovementAlert",
            "Movement alert",
            "Shows a countdown while your movement ability is on cooldown.",
            "Enable movement alert")

        c1:Pair(
            { kind = "slider", key = "precision", label = "Decimal precision",
              desc = "Digits shown after the decimal point.",
              min = 0, max = 1, step = 1 },
            -- Stored in seconds, edited in milliseconds.
            { kind = "slider", label = "Update interval", suffix = " ms",
              min = 50, max = 500, step = 10,
              default = (DEF.updateInterval or 0.1) * 1000,
              get = function() return math.floor((db.updateInterval or 0.1) * 1000 + 0.5) end,
              set = function(v) db.updateInterval = v / 1000 end })

        -- ── Tracked spells ───────────────────────────────────
        -- Only classes with movement abilities get this card.
        local ma      = SP.MovementAlert
        local _, cls  = UnitClass("player")
        local byClass = ma and ma.MovementAbilities and ma.MovementAbilities[cls]
        if byClass then
            local seen, unique = {}, {}
            for _, spells in pairs(byClass) do
                for _, sid in ipairs(spells) do
                    if not seen[sid] then
                        seen[sid] = true
                        unique[#unique + 1] = sid
                    end
                end
            end
            table.sort(unique)

            if #unique > 0 then
                db.disabledSpells = db.disabledSpells or {}
                local cs = page:Card("Tracked spells",
                    "Which of your class's movement abilities this module watches.")
                for _, sid in ipairs(unique) do
                    local info = C_Spell.GetSpellInfo(sid)
                    local name = info and info.name or ("Spell " .. sid)
                    local icon = info and info.iconID
                    cs:Toggle{
                        label   = icon and ("|T" .. icon .. ":16:16|t  " .. name) or name,
                        default = true,
                        get = function() return not db.disabledSpells[sid] end,
                        set = function(v)
                            if v then db.disabledSpells[sid] = nil
                            else      db.disabledSpells[sid] = true end
                        end,
                    }
                end
            end
        end

        -- ── Position ─────────────────────────────────────────
        local c2 = page:Card("Position",
            "Where the countdown sits. It is previewed on screen while this window is open.")
        c2:AnchorRow{}
        c2:Pair(
            { kind = "slider", key = "x", label = "X offset", min = -2000, max = 2000, step = 1 },
            { kind = "slider", key = "y", label = "Y offset", min = -2000, max = 2000, step = 1 })

        -- ── Font ─────────────────────────────────────────────
        local c3 = page:Card("Font", "Typeface, size and colour of the countdown text.")
        c3:FontDropdown{ key = "fontFace", label = "Font face" }
        c3:Pair(
            { kind = "slider",   key = "fontSize", label = "Font size", min = 8, max = 60, step = 1 },
            { kind = "dropdown", key = "outline",  label = "Outline", options = GUI.OUTLINES })
        c3:ColorSource{ label = "Text colour", srcKey = "colorSource", colorKey = "color",
                        alpha = true }

        -- ── Time spiral ──────────────────────────────────────
        local c4 = page:Card("Time spiral",
            "A free-movement countdown, triggered by the spell's glow overlay.")
        local tsOn = c4:Toggle{ key = "showTimeSpiral", label = "Enable time spiral" }
        c4:GateBelow(tsOn)

        c4:EditBox{ key = "timeSpiralText", label = "Display text", maxLen = 64,
                    desc = "Shown for as long as the proc lasts." }
        -- The module reads timeSpiralColor directly, with no source key, so this
        -- is a plain colour rather than a colour-with-source row.
        c4:Color{ key = "timeSpiralColor", label = "Text colour", alpha = true }
        c4:Pair(
            { kind = "slider", key = "timeSpiralTextX", label = "Text X", min = -500, max = 500, step = 1 },
            { kind = "slider", key = "timeSpiralTextY", label = "Text Y", min = -500, max = 500, step = 1 })

        local tsSoundOn = c4:Toggle{ key = "timeSpiralPlaySound", label = "Play a sound on trigger" }
        c4:GateBelow(tsSoundOn)
        c4:Dropdown{
            label     = "Sound",
            optionsFn = SoundOptions,
            default   = "None",
            get       = function() return db.timeSpiralSound or "None" end,
            set       = function(v) db.timeSpiralSound = (v ~= "None") and v or nil end,
        }

        local soundHandle
        local listenRow
        local function StopSpiralSound()
            if soundHandle then
                StopSound(soundHandle, 200)
                soundHandle = nil
            end
            if listenRow then listenRow.btn:SetText("Listen") end
        end

        listenRow = c4:ButtonRow{
            text  = "Listen",
            width = 80,
            onClick = function()
                if soundHandle then StopSpiralSound(); return end
                local name = db.timeSpiralSound
                if not name or name == "None" then return end
                local lsm  = LSM()
                local file = lsm and lsm:Fetch("sound", name)
                if not file then return end
                local ok, handle = PlaySoundFile(file, "Master")
                if ok then
                    soundHandle = handle
                    listenRow.btn:SetText("Stop")
                end
            end,
        }

        -- Back to the time-spiral gate for the icon block.
        c4:GateBelow(tsOn)
        local showIcon = c4:Toggle{ key = "timeSpiralShowIcon", label = "Show spell icon" }
        c4:GateBelow(showIcon)
        c4:Slider{ key = "timeSpiralIconSize", label = "Icon size", min = 20, max = 100, step = 1 }
        -- The four real key names, in place of the setmetatable proxy the old
        -- page used to make them look like the widget's hardcoded ones.
        c4:AnchorRow{
            fromKey   = "timeSpiralIconAnchorFrom",
            toKey     = "timeSpiralIconAnchorTo",
            frameKey  = "timeSpiralIconAnchorFrame",
            strataKey = "timeSpiralIconFrameStrata",
        }
        c4:Pair(
            { kind = "slider", key = "timeSpiralIconX", label = "Icon X", min = -500, max = 500, step = 1 },
            { kind = "slider", key = "timeSpiralIconY", label = "Icon Y", min = -500, max = 500, step = 1 })

        c4:GateBelow(tsOn)
        local previewOn = false
        local previewRow
        local function ResetPreviewButton()
            previewOn = false
            if previewRow then
                previewRow.btn:SetText("Preview")
                previewRow.btn:SetActive(false)
            end
        end
        local function StopSpiralPreview()
            local mod = SP.MovementAlert
            if mod then
                if previewOn and mod.HideTimeSpiralPreview then mod:HideTimeSpiralPreview() end
                mod._tsPreviewEndCallback = nil
            end
            ResetPreviewButton()
        end

        previewRow = c4:ButtonRow{
            text  = "Preview",
            width = 110,
            desc  = "Runs the countdown on screen so you can place it.",
            onClick = function()
                local mod = SP.MovementAlert
                if not mod then return end
                if previewOn then StopSpiralPreview(); return end
                previewOn = true
                previewRow.btn:SetText("Stop preview")
                previewRow.btn:SetActive(true)
                -- The module calls this when its own auto-cancel fires. Installed
                -- per preview and cleared in StopSpiralPreview, so the page never
                -- leaves a closure hanging off the module -- and, unlike the old
                -- page, it is still installed on the second and later visits.
                mod._tsPreviewEndCallback = ResetPreviewButton
                mod:ShowTimeSpiralPreview()
            end,
        }

        -- Everything that outlives the page: a playing sound, a running preview,
        -- and the callback the preview installed on the module.
        parent:HookScript("OnHide", function()
            StopSpiralSound()
            StopSpiralPreview()
        end)

        page:Finish()
    end,
}
