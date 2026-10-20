-- SuspicionsPack Options — Animated portraits
--
-- Every setting is applied live: the GUI calls the module's Refresh on each
-- change, and Activate re-lays out and re-colours every portrait on screen.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

local BACKGROUND_STYLES = {
    { key = "dark",      label = "Dark" },
    { key = "unitclass", label = "Unit class colour" },
    { key = "theme",     label = "Theme accent" },
    { key = "custom",    label = "Custom" },
}

-- AnimationData IDs. A model that lacks the one picked plays Stand instead.
local ANIMATIONS = {
    { key = 0,  label = "Stand (idle)" },
    { key = 60, label = "Talk" },
    { key = 69, label = "Dance" },
    { key = 4,  label = "Walk" },
    { key = 5,  label = "Run" },
}

GUI.RegisterPage{
    id       = "animatedportraits",
    name     = "Animated portraits",
    category = "interface",
    dbKey    = "animatedPortraits",
    keywords = "portrait 3d model animated living face unit frame target party npc " ..
               "quest gossip camera zoom rotation background class",
    build = function(parent)
        local page, db, c1, master = GUI.ModulePage(parent, "animatedPortraits", "AnimatedPortraits",
            "Animated portraits",
            "Replaces the flat portrait pictures with living 3D models: your unit frames, " ..
            "your party, the NPCs you talk to and the windows that show a character. The " ..
            "flat picture comes back by itself whenever a model cannot be shown. " ..
            "/spack debug portraits lists what is on screen.",
            nil, "Unit frames")

        -- Turning the module on only takes on the portraits once the UI is
        -- reloaded, so ask right away. Wrapped the same way Page:Gate wraps the
        -- master's onToggle: the toast and the gate refresh still run first.
        if master and master.spec then
            local prev = master.spec.onToggle
            master.spec.onToggle = function(v)
                if prev then prev(v) end
                if v and SP.CreateReloadPrompt then
                    SP.CreateReloadPrompt("Animated portraits needs a UI reload to take effect.")
                end
            end
        end

        c1:Pair({ key = "showPlayer", kind = "toggle", label = "Player" },
                { key = "showTarget", kind = "toggle", label = "Target" })
        c1:Pair({ key = "showFocus",  kind = "toggle", label = "Focus" },
                { key = "showPet",    kind = "toggle", label = "Pet" })
        c1:Pair({ key = "showTargetTarget", kind = "toggle", label = "Target of target" },
                { key = "showParty",        kind = "toggle", label = "Party" })
        c1:Pair({ key = "showBoss",  kind = "toggle", label = "Boss and arena" },
                { key = "showOther", kind = "toggle", label = "Other unit frames" })

        local c2 = page:Card("Windows")
        c2:Toggle{ key = "showNPC", label = "NPC windows",
                   desc = "Quest givers, gossip, merchants, trainers, bank, stable and the like." }
        c2:Toggle{ key = "npcTalk", label = "NPCs talk",
                   desc = "The NPC you are speaking with plays its talk animation." }
        c2:Toggle{ key = "showWindows", label = "Character windows",
                   desc = "Character, inspect, dressing room, PvP and your trade partner." }

        local c3 = page:Card("Framing",
            "A 3D model is a square that cannot be cut round. Reach sets how far it goes " ..
            "toward the gold ring; face size only moves the camera inside it.")
        c3:Slider{ key = "frameFill", label = "Reach the frame",
                   desc = "Closes the dark ring between the model and the gold frame. Above " ..
                          "about 90% the model's corners can show past the ring at the diagonals.",
                   min = 70, max = 100, step = 1, suffix = "%" }
        c3:Slider{ key = "size", label = "Face size",
                   desc = "How big the face is in the round portrait.",
                   min = 60, max = 130, step = 1, suffix = "%" }
        c3:Slider{ key = "zoom", label = "Portrait zoom",
                   desc = "100 frames the face; lower shows more of the body.",
                   min = 0, max = 100, step = 5, suffix = "%" }
        c3:Slider{ key = "rotation", label = "Rotation",
                   desc = "Turns the model. 0 faces the camera.",
                   min = -90, max = 90, step = 5, suffix = "°" }
        local facing = c3:Toggle{ key = "mirrorTargetSide", label = "Faces look at each other",
                   desc = "Player, pet and party turn right; target, focus and boss turn left." }
        c3:GateBelow(facing)
        c3:Slider{ key = "faceTurn", label = "Turn toward each other",
                   desc = "How far each side turns. Negative turns them apart.",
                   min = -90, max = 90, step = 5, suffix = "°" }
        c3:EndGate()
        c3:Pair({ key = "offsetX", label = "Horizontal offset", min = -50, max = 50, step = 1 },
                { key = "offsetY", label = "Vertical offset",   min = -50, max = 50, step = 1 })
        c3:Slider{ key = "modelAlpha", label = "Model opacity",
                   min = 10, max = 100, step = 5, suffix = "%" }

        local c4 = page:Card("Background")
        local bgOn = c4:Toggle{ key = "background", label = "Background disc",
                                desc = "A disc behind the model, so it stands out from the frame." }
        c4:GateBelow(bgOn)
        c4:Toggle{ key = "edgeFade", label = "Soft edge",
                   desc = "Fades the model's square corners into the disc on round portraits." }
        c4:Dropdown{ key = "backgroundStyle", label = "Colour", options = BACKGROUND_STYLES }
        c4:Color{ key = "backgroundColor", label = "Custom colour",
                  desc = "Used when the colour is set to Custom." }
        c4:Slider{ key = "backgroundAlpha", label = "Opacity",
                   min = 0, max = 100, step = 5, suffix = "%" }
        c4:EndGate()

        local c5 = page:Card("Animation")
        local anim = c5:Toggle{ key = "animate", label = "Animate",
                                desc = "Off: models hold still on their first frame." }
        c5:GateBelow(anim)
        c5:Dropdown{ key = "animation", label = "Animation", options = ANIMATIONS,
                     desc = "What unit frame models play. NPC windows use Talk when that is on." }
        c5:Toggle{ key = "pauseInCombat", label = "Hold still in combat",
                   desc = "Freezes the models while you are in combat." }
        c5:EndGate()

        local c6 = page:Card("Behaviour")
        c6:Toggle{ key = "keepFlatWhenTinted", label = "Flat picture for dead, offline or tapped",
                   desc = "Keeps the game's grey, blue or faded picture, which a model would hide." }
        c6:Toggle{ key = "flatInCombat", label = "Flat pictures in combat",
                   desc = "Every portrait goes back to its picture while you are in combat." }
        c6:Slider{ key = "minSize", label = "Smallest portrait",
                   desc = "Portraits smaller than this, in pixels, stay flat.",
                   min = 16, max = 80, step = 1 }

        page:Finish()
    end,
}
