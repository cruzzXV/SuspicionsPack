-- SuspicionsPack Options — Buff thanks

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

-- The same keys as BuffThanks.EMOTES, which maps them to PerformEmote tokens.
local EMOTES = {
    { key = "emoteThank",        label = "Thank",        desc = "/thank" },
    { key = "emoteCheer",        label = "Cheer",        desc = "/cheer" },
    { key = "emoteApplaud",      label = "Applaud",      desc = "/applaud" },
    { key = "emoteCongratulate", label = "Congratulate", desc = "/congratulate" },
    { key = "emoteNod",          label = "Nod",          desc = "/nod" },
    { key = "emoteKiss",         label = "Kiss",         desc = "/kiss" },
}

GUI.RegisterPage{
    id       = "buffthanks",
    name     = "Buff thanks",
    category = "social",
    dbKey    = "buffThanks",
    keywords = "buff thanks thank emote whisper cheer applaud congratulate stranger reaction delay group party dungeon",
    tip      = "Thanks the players who buff you, with an emote aimed at them or a whisper, a moment later. Never in combat, and never twice in a row for the same player.",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "buffThanks", "BuffThanks",
            "Buff thanks",
            "When another player buffs you, thanks them with an emote aimed at them or a whisper.",
            "Enable buff thanks")

        -- The emote card and the whisper card each follow the reaction picked
        -- here, on top of the master switch: a gate only needs GetValue.
        local function Mode(mode)
            return { GetValue = function() return db.reaction == mode end }
        end
        local emoteMode, whisperMode = Mode("emote"), Mode("whisper")

        c1:Dropdown{
            key = "reaction", label = "Reaction",
            options = {
                { key = "emote",   label = "Emote" },
                { key = "whisper", label = "Whisper" },
            },
            onSelect = function() page:ApplyGates() end,
        }
        c1:Slider{
            key = "delay", label = "Delay", suffix = " s", min = 0, max = 10, step = 0.5,
            desc = "Time between the buff and the thanks.",
        }
        c1:Slider{
            key = "cooldown", label = "Same player again after", suffix = " s", min = 10, max = 600, step = 10,
            desc = "A player who buffs you several times is thanked once in this window.",
        }
        c1:ButtonRow{
            text  = "Test",
            width = 100,
            desc  = "Emote: aimed at your target. Whisper: sent to yourself.",
            onClick = function() if SP.BuffThanks then SP.BuffThanks:Test() end end,
        }

        local c2 = page:Card("Where", "Where buffs are thanked.")
        c2:Toggle{ key = "inWorld",      label = "Open world", desc = "Alone, outside instances." }
        c2:Toggle{ key = "inWorldGroup", label = "Open world in a group", desc = "In a party, outside instances." }
        c2:Toggle{ key = "inGroup",      label = "Dungeons" }
        c2:Toggle{ key = "inRaid",       label = "Raids", desc = "In a raid group, open world included." }
        c2:Toggle{ key = "inPvP",   label = "Battlegrounds and arenas" }

        local c3 = page:Card("Emotes", "One of the ticked emotes, picked at random, never the same twice in a row.")
        c3:GateBelow(emoteMode)
        for _, e in ipairs(EMOTES) do
            c3:Toggle{ key = e.key, label = e.label, desc = e.desc }
        end
        c3:EndGate()

        local c4 = page:Card("Whisper")
        c4:GateBelow(whisperMode)
        c4:EditBox{
            key = "message", label = "Message", ctrlW = 240, maxLen = 200,
            desc = "{buff} becomes a link to the buff.",
        }
        c4:EndGate()

        page:Finish()
    end,
}
