-- SuspicionsPack Options — Performance
--
-- Two action buttons flash a confirmation for three seconds after they are
-- clicked. The old page hung a bare C_Timer.NewTimer(3, ...) off each of them
-- with nothing tracking it, so navigating away inside those three seconds left
-- the closure firing into a FontString whose page had already been torn down.
-- The timers are tracked and cancelled in parent's OnHide instead.
--
-- The quest-watch sweep itself is deliberate: SP.Performance.ClearQuestWatches()
-- walks the whole 200,000-wide questID space, chunked across frames, because
-- phantom watches are invisible to an index walk. It is called unchanged.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

GUI.RegisterPage{
    id       = "performance",
    name     = "Performance",
    category = "interface",
    dbKey    = "performance",
    keywords = "performance fps quest watch combat log sound channels stutter lag",
    build = function(parent)
        local page, db, c0 = GUI.ModulePage(parent, "performance", "Performance",
            "Performance",
            "Quest watch cleaner, automatic combat-log clearing and audio channel control. " ..
            "Enable the module to activate its sub-features.",
            "Enable performance module")

        -- row -> pending revert timer, so OnHide can cancel every one of them.
        local flashing = {}

        local function FlashButton(card, spec)
            local idle, done = spec.text, spec.doneText
            local row
            row = card:ButtonRow{
                text  = idle,
                desc  = spec.desc,
                width = 200,
                onClick = function()
                    spec.run()
                    if flashing[row] then flashing[row]:Cancel() end
                    row.btn:SetText(done)
                    flashing[row] = C_Timer.NewTimer(3, function()
                        flashing[row] = nil
                        row.btn:SetText(idle)
                    end)
                end,
            }
            row._idleText = idle
            -- Out of the page's enable cascade. These are one-shot cleanup
            -- actions, not settings: clearing a phantom quest watch or the
            -- combat log is worth doing whether or not the module is switched
            -- on, and both worked with it off before the cascade covered every
            -- row. Only the buttons are exempt; the settings around them are not.
            row._manualEnable = true
            return row
        end

        parent:HookScript("OnHide", function()
            for row, timer in pairs(flashing) do
                timer:Cancel()
                row.btn:SetText(row._idleText)
                flashing[row] = nil
            end
        end)

        local c1 = page:Card("Quest watch cleaner",
            "WoW can silently keep tracking quests as phantom watches in the background even " ..
            "once they are hidden from your quest log. Those ghost entries cost time every " ..
            "frame and can noticeably hurt FPS.")
        FlashButton(c1, {
            text     = "Print and clear quest watches",
            doneText = "Quest log cleaned",
            desc     = "Prints every tracked entry to chat, then removes all watches.",
            run      = function()
                if SP.Performance then SP.Performance.ClearQuestWatches() end
            end,
        })

        local c2 = page:Card("Auto clear combat log",
            "The combat log grows all session and weighs on FPS over time. This calls " ..
            "CombatLogClearEntries() on every login so you always start with a clean log.")
        c2:Toggle{ key = "autoClearCombatLog", label = "Clear combat log on login" }
        FlashButton(c2, {
            text     = "Clear combat log",
            doneText = "Combat log cleared",
            desc     = "Clears it once, right now.",
            run      = function() CombatLogClearEntries() end,
        })

        local c3 = page:Card("Sound channels",
            "Sets the audio channel count on login, which also stops BigWigs from resetting " ..
            "it. Lower values improve FPS and reduce stuttering in raids, but some sounds may " ..
            "not play in busy environments.")
        local soundOn = c3:Toggle{ key = "setSoundChannels",
                                   label = "Set audio channel count on login" }
        c3:GateBelow(soundOn)
        c3:Dropdown{
            key     = "soundChannelCount",
            label   = "Audio channels",
            options = {
                { key = 32,  label = "32 (recommended)" },
                { key = 64,  label = "64 (WoW default)" },
                { key = 128, label = "128 (maximum)" },
            },
        }
        c3:Toggle{ key = "soundChannelNotify",
                   label = "Announce the change in chat",
                   desc  = "Posts a line when the channel count is actually changed." }

        page:Finish()
    end,
}
