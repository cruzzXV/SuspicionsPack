-- SuspicionsPack Options — Campfire wheel (WoW: Forever only)
--
-- Listed only where the module is: the .toc line carries the same
-- [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic] gate.
--
-- Everything goes through the page's standard onChange, which reaches
-- CampWheel:Refresh -> Activate -> redraw.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

GUI.RegisterPage{
    id       = "campwheel",
    name     = "Campfire wheel",
    category = "interface",
    dbKey    = "campWheel",
    keywords = "camp campfire camping fire wheel chair tent toy dust pouch adventurer profession object objects",
    tip      = "Near a campfire, opens a ring of the camp items you can use right now. Click an icon to use it. The ring stays hidden in combat, on a mount and while you are dead.",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "campWheel", "CampWheel",
            "Campfire wheel",
            "Near a campfire, opens a wheel of the camp items you can place, with the Pouch of " ..
            "Violet Dust and the Adventurer's Tent if you own them.",
            nil, "Size and position")

        c1:Slider{ key = "scale", label = "Wheel size", suffix = "%", min = 50, max = 200, step = 5 }
        c1:Pair(
            { kind = "slider", key = "x", label = "X offset", min = -800, max = 800, step = 1 },
            { kind = "slider", key = "y", label = "Y offset", min = -800, max = 800, step = 1 })

        local previewRow
        local function StopPreview()
            if SP.CampWheel then SP.CampWheel:SetPreview(false) end
            if previewRow then previewRow.btn:SetText("Preview") end
        end
        previewRow = c1:ButtonRow{
            text  = "Preview",
            width = 100,
            desc  = "Shows a sample wheel so you can place it. Not in combat.",
            onClick = function()
                local wheel = SP.CampWheel
                if not wheel then return end
                if wheel:IsPreviewing() then
                    StopPreview()
                else
                    wheel:SetPreview(true)
                    if wheel:IsPreviewing() then previewRow.btn:SetText("Stop") end
                end
            end,
        }
        -- The wheel is parented to UIParent, so hiding the page does not hide it.
        parent:HookScript("OnHide", StopPreview)

        local c2 = page:Card("Good to know")
        c2:Note("The game only says a campfire is within 100 yards, so you may have to walk closer before an item can be placed.")
        c2:Note("Items on cooldown leave the wheel. It closes when nothing is left, and in combat, on a mount or when dead.")
        c2:Note("Click the middle of the wheel to sit down. Right-click it to close the wheel until the next campfire.")

        page:Finish()
    end,
}
