-- SuspicionsPack Options — Automation
--
-- The old page was one long card whose groups were marked out with separators
-- and whose eleven descriptions were free-floating labels tracked in a parallel
-- `childLabels` table purely so the enable cascade could dim them. Groups are
-- cards now, and each description belongs to the toggle it describes.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

GUI.RegisterPage{
    id       = "automation",
    name     = "Automation",
    category = "general",
    dbKey    = "automation",
    keywords = "automation auto accept delete cinematic cutscene talking head bags bar " ..
               "screenshot junk sell vendor repair guild funds decor flight form druid travel",
    build = function(parent)
        local page = GUI.ModulePage(parent, "automation", "Automation",
            "Automation",
            "Answers dialogs and popups for you, and handles selling and repairing " ..
            "when you open a merchant.",
            "Enable automation")

        local c2 = page:Card("Dialogs and popups")

        c2:Toggle{
            key   = "autoFillDelete",
            label = "Auto fill delete",
            desc  = "Types DELETE for you when destroying a good item.",
            onChange = function(v)
                page.apply()
                -- hooksecurefunc cannot be undone, so switching this back off only
                -- takes full effect after a reload.
                if not v then
                    SP.CreateReloadPrompt("Disabling Auto Fill Delete requires a reload to take full effect.")
                end
            end,
        }
        c2:Toggle{
            key   = "skipCinematics",
            label = "Skip cinematics",
            desc  = "Cancels in-game cutscenes and movies as they start.",
        }
        c2:Toggle{
            key   = "hideTalkingHead",
            label = "Hide talking head",
            desc  = "Hides the talking head popup that appears during quests.",
        }
        c2:Toggle{
            key   = "hideBagsBar",
            label = "Hide bags bar",
            desc  = "Hides the backpack buttons from the main action bar.",
        }


        -- This one lives in the Performance section, not Automation, so it carries
        -- its own DB table, its own default source and its own apply callback.
        local dbPerf   = SP.GetDB().performance
        local perfDef  = SP.DEFAULTS and SP.DEFAULTS.profile and SP.DEFAULTS.profile.performance
        c2:Toggle{
            db       = dbPerf,
            key      = "hideScreenshotMsg",
            default  = perfDef and perfDef.hideScreenshotMsg,
            onChange = GUI.Applier("Performance"),
            label    = "Hide screenshot notification",
            desc     = "Suppresses the \"Screenshot saved\" message.",
        }

        local c3 = page:Card("Merchant")

        c3:Toggle{
            key   = "autoSellJunk",
            label = "Auto sell junk",
            desc  = "Sells every grey item in your bags when you open a merchant.",
        }
        local repairOn = c3:Toggle{
            key   = "autoRepair",
            label = "Auto repair",
            desc  = "Repairs all your gear at any merchant that offers repairs.",
        }
        c3:GateBelow(repairOn)
        c3:Toggle{
            key   = "useGuildFunds",
            label = "Use guild funds",
            desc  = "Pays for repairs from the guild bank instead of your own gold. " ..
                    "Needs guild repair permission.",
        }
        c3:EndGate()
        c3:Toggle{
            key   = "autoDecorVendor",
            label = "Auto accept decor prompt",
            desc  = "Confirms the purchase prompt when buying decoration items.",
        }

        local c4 = page:Card("Druid")

        c4:Toggle{
            key   = "autoSwitchFlight",
            label = "Auto switch to flight form",
            desc  = "Cancels ground Travel Form once flying is allowed, so you can " ..
                    "take off straight away.",
        }

        page:Finish()
    end,
}
