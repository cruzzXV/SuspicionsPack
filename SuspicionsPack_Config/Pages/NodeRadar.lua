-- SuspicionsPack Options — Node radar (WoW: Forever only)
--
-- Listed only where the module is: the .toc line carries the same
-- [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic] gate.
--
-- Everything goes through the page's standard onChange, which reaches
-- NodeRadar:Refresh -> Activate -> redraw.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

GUI.RegisterPage{
    id       = "noderadar",
    name     = "Node radar",
    category = "interface",
    dbKey    = "nodeRadar",
    keywords = "node nodes herb herbs herbalism ore mining vein radar compass arrow gather gathering " ..
               "minimap tracking find",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "nodeRadar", "NodeRadar",
            "Node radar",
            "Shows the nearest herb or vein as an icon around your character. Like a compass " ..
            "needle, it turns to point where the node is.",
            nil, "What it shows")

        c1:Toggle{ key = "herbs", label = "Herbs",
                   desc = "Needs Find Herbs on." }
        c1:Toggle{ key = "ore", label = "Veins and deposits",
                   desc = "Needs Find Minerals on." }
        c1:Slider{ key = "range", label = "Range",
                   desc = "It never reaches further than your minimap shows, so zooming out helps.",
                   min = 30, max = 500, step = 10 }
        c1:Toggle{ key = "showDistance", label = "Show the distance" }

        local c2 = page:Card("Size and position")
        c2:Slider{ key = "orbit", label = "Circle size",
                   desc = "How far from your character the icon sits as it turns.",
                   suffix = " px", min = 20, max = 300, step = 5 }
        c2:Slider{ key = "scale", label = "Icon size", suffix = "%", min = 50, max = 200, step = 5 }
        c2:Pair(
            { kind = "slider", key = "x", label = "X offset", min = -800, max = 800, step = 1 },
            { kind = "slider", key = "y", label = "Y offset", min = -800, max = 800, step = 1 })

        local previewRow
        local function StopPreview()
            if SP.NodeRadar then SP.NodeRadar:SetPreview(false) end
            if previewRow then previewRow.btn:SetText("Preview") end
        end
        previewRow = c2:ButtonRow{
            text  = "Preview",
            width = 100,
            desc  = "Shows a sample icon so you can place it. Your character is about in the middle of the screen.",
            onClick = function()
                local radar = SP.NodeRadar
                if not radar then return end
                if radar:IsPreviewing() then
                    StopPreview()
                else
                    radar:SetPreview(true)
                    if radar:IsPreviewing() then previewRow.btn:SetText("Stop") end
                end
            end,
        }
        -- The icon is parented to UIParent, so hiding the page does not hide it.
        parent:HookScript("OnHide", StopPreview)

        local c3 = page:Card("Good to know")
        c3:Note("It reads your minimap's tracking dots, so the minimap has to be on screen.")
        c3:Note("Up is the way your character faces. If you turn the camera alone, the icon follows your character.")

        page:Finish()
    end,
}
