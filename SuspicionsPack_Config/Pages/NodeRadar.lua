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
            "Shows the nearest herbs and veins as icons around your character. Like compass " ..
            "needles, they turn to point where each node is. The nearest is larger.",
            nil, "What it shows")

        c1:Toggle{ key = "herbs", label = "Herbs",
                   desc = "Needs Find Herbs on." }
        c1:Toggle{ key = "ore", label = "Veins and deposits",
                   desc = "Needs Find Minerals on." }
        c1:Slider{ key = "range", label = "Range",
                   desc = "It never reaches further than your minimap shows, so zooming out helps.",
                   min = 30, max = 500, step = 10 }
        c1:Slider{ key = "maxNodes", label = "Nodes shown", min = 1, max = 8, step = 1 }
        c1:Toggle{ key = "showDistance", label = "Show the distance",
                   desc = "On the nearest node." }
        local arrowRow
        c1:Toggle{ key = "showArrows", label = "Arrows",
                   desc = "A small arrow between your character and each icon.",
                   onChange = function()
                       page.apply()
                       arrowRow._hidden = not db.showArrows
                       page:Restack()
                   end }

        local c2 = page:Card("Size and position")
        c2:Slider{ key = "orbit", label = "Circle size",
                   desc = "How far from your character the icons sit as they turn.",
                   suffix = " px", min = 20, max = 300, step = 5 }
        c2:Slider{ key = "scale", label = "Icon size", suffix = "%", min = 50, max = 200, step = 5 }
        c2:Slider{ key = "otherScale", label = "Other nodes' size",
                   desc = "Every node but the nearest, and its arrow.",
                   suffix = "%", min = 40, max = 100, step = 5 }
        arrowRow = c2:Slider{ key = "arrowScale", label = "Arrow size", suffix = "%", min = 50, max = 200, step = 5 }
        arrowRow._hidden = not db.showArrows
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
            desc  = "Shows sample icons so you can place them. Your character is about in the middle of the screen.",
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
        -- The icons are parented to UIParent, so hiding the page does not hide them.
        parent:HookScript("OnHide", StopPreview)

        local c3 = page:Card("Good to know")
        c3:Note("It reads your minimap's tracking dots, so the minimap has to be on screen.")
        c3:Note("Up is the way your character faces. If you turn the camera alone, the icons follow your character.")

        page:Finish()
    end,
}
