-- SuspicionsPack Options — Nudge tool
--
-- Documentation only: the Nudge Tool is a separate addon with no settings of its
-- own, so there is no module toggle and no DB section. The page is built by hand
-- with GUI.NewPage rather than GUI.ModulePage, and registers without a dbKey so
-- the sidebar gives it no on/off dot.
--
-- Three of the four cards only exist when the plugin is actually loaded.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

GUI.RegisterPage{
    id       = "editmode",
    name     = "Nudge tool",
    category = "interface",
    keywords = "nudge edit mode move frame position anchor pixel offset plugin",
    build = function(parent)
        local page   = GUI.NewPage(parent, nil, nil)
        local loaded = SP.nudgeFrame ~= nil

        local c1 = page:Card("Nudge tool")
        if loaded then
            c1:Note("|cff4DCC66Plugin active|r  —  the Nudge Tool is loaded and operational.",
                    { color = "textPrimary" })
        else
            c1:Note("|cffFF4444Plugin inactive|r  —  the Nudge Tool is a separate addon.",
                    { color = "textPrimary" })
            c1:Note(
                "To activate: open the WoW addon list (Esc > AddOns), tick " ..
                "SuspicionsPackNudgeTool, then reload the interface.\n" ..
                "To deactivate: untick it in the same list and reload.")
        end

        if loaded then
            local c2 = page:Card("Usage")
            c2:Note(
                "Open Blizzard's Edit Mode (Game Menu > Edit Mode) and click any element to " ..
                "select it. The Nudge panel appears automatically below the settings window.")

            local c3 = page:Card("Controls")
            c3:Note(
                "D-pad arrows  —  move the selected frame by one pixel.\n" ..
                "X / Y fields  —  enter a value and press Enter to set it directly.\n" ..
                "Self point  —  anchor point on the frame itself.\n" ..
                "Anchor to  —  name of the frame to anchor to (default: UIParent).\n" ..
                "Anchor point  —  point on the anchor frame.")

            local c4 = page:Card("Compatible elements")
            c4:Note(
                "Works with any frame exposed in Blizzard's Edit Mode: player frame, minimap, " ..
                "action bars, cast bars, buffs and so on.")
            c4:Note(
                "Changes are saved by Blizzard's layout system — click Save in the Edit Mode " ..
                "window to keep them.")
        end

        page:Finish()
    end,
}
