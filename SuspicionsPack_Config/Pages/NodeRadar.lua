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
    tip      = "Shows the nearest herbs and veins as icons around the middle of your screen, each turned toward its node. It needs Find Herbs or Find Minerals on and the minimap shown, and skips nodes above your skill.",
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

        local cs = page:Card("Scanning")
        cs:Slider{ key = "scanYards", label = "Scan every",
                   desc = "Yards walked between two scans. Standing still, it does not scan.",
                   suffix = " yd", min = 10, max = 100, step = 5 }
        cs:Slider{ key = "scanSeconds", label = "At most every",
                   desc = "Seconds between two scans, at the least.",
                   suffix = " s", min = 3, max = 60, step = 1 }
        cs:Toggle{ key = "scanCombat", label = "Scan in combat",
                   desc = "Off: no scan in a fight, the icons keep following the nodes already found." }

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
        c3:Note("To read them, a scan moves the minimap under your mouse for a few tenths of a second, unseen: a copy of it stays in its place, its buttons, frame and texts included, without its other dots. A scan reads a little of the minimap at a time, and gives the mouse back as soon as you press a button or bring it onto the minimap or its buttons.")
        c3:Note("A scan waits while your mouse is over a window. None while you aim a spell, cast, loot or have a mob under the mouse, nor in cities and inns, indoors, in instances, flying, or with a rotating minimap. One after each fight.")
        c3:Note("With NodeSight on, the radar takes NodeSight's nodes and does not scan itself.")
        c3:Note("Up is the way your character faces. If you turn the camera alone, the icons follow your character.")
        c3:Note("Right-click an icon to take its node off the radar, as with WaypointUI. A left-click goes on to the world.")

        page:Finish()
    end,
}
