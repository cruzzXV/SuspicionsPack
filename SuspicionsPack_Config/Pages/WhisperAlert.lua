-- SuspicionsPack Options — Whisper alert

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

local function Media()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- Rebuilt on every refresh rather than frozen at build time: LibSharedMedia's
-- sound table is a hash, and another addon registering a sound after login used
-- to leave this list permanently stale.
local function SoundOptions()
    local names = {}
    local lsm = Media()
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
    id       = "whisperalert",
    name     = "Whisper alert",
    category = "social",
    dbKey    = "whisperAlert",
    keywords = "whisper alert sound battle.net bnet message ping audio channel mute combat preview",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "whisperAlert", "WhisperAlert",
            "Whisper alert",
            "Plays a sound when you receive a whisper or a Battle.net message.",
            "Enable whisper alert")

        c1:Toggle{
            key   = "muteInCombat",
            label = "Mute while in combat",
            desc  = "Suppresses the alert for as long as you are in combat.",
        }

        -- PlaySoundFile outlives the frame that started it, so the handles are
        -- kept and stopped when the page goes away. Nothing did this before and a
        -- preview could keep playing over the rest of the interface.
        local playing = {}
        local function Preview(soundKey)
            local name = db[soundKey]
            if not name or name == "None" then return end
            local lsm  = Media()
            local file = lsm and lsm:Fetch("sound", name)
            if not file then return end
            local ok, handle = PlaySoundFile(file, db.channel or "Master")
            if ok and handle then playing[#playing + 1] = handle end
        end
        parent:HookScript("OnHide", function()
            for i = #playing, 1, -1 do
                if StopSound then StopSound(playing[i]) end
                playing[i] = nil
            end
        end)

        local c2 = page:Card("Sounds", "Which sound plays for each kind of message.")

        -- The old page glued the Preview button inside the dropdown's own row and
        -- monkey-patched that row's SetEnabled so the button followed it. The real
        -- condition it was hiding is "there is a sound to play" -- checked inside
        -- the click handler, where the button still looked live. Here the preview
        -- is a row of its own: the page gate hands it the master's state, and
        -- SyncPreview ANDs in the sound check whenever the choice changes.
        local wPreview, bPreview

        local function SyncPreview(row, soundKey)
            if not row then return end
            row:SetEnabled(db.enabled and db[soundKey] ~= "None" and db[soundKey] ~= nil)
        end

        c2:Dropdown{
            key = "sound", label = "Whisper sound", optionsFn = SoundOptions,
            onSelect = function() SyncPreview(wPreview, "sound") end,
        }
        wPreview = c2:ButtonRow{
            text    = "Preview whisper sound",
            desc    = "Plays it through the channel selected below.",
            width   = 150,
            onClick = function() Preview("sound") end,
        }

        c2:Dropdown{
            key = "bnetSound", label = "Battle.net sound", optionsFn = SoundOptions,
            onSelect = function() SyncPreview(bPreview, "bnetSound") end,
        }
        bPreview = c2:ButtonRow{
            text    = "Preview Battle.net sound",
            desc    = "Plays it through the channel selected below.",
            width   = 150,
            onClick = function() Preview("bnetSound") end,
        }

        c2:Dropdown{
            key     = "channel",
            label   = "Audio channel",
            desc    = "Both sounds play through this channel.",
            options = GUI.CHANNELS,
        }

        page:Finish()

        -- After Finish, so the gate pass does not immediately overwrite it.
        SyncPreview(wPreview, "sound")
        SyncPreview(bPreview, "bnetSound")
    end,
}
