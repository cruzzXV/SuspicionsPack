-- SuspicionsPack Options — ReapPredict (Devourer Demon Hunter)
--
-- The biggest page in the pack: two resource bars, ~20 colours and four
-- independent gate levels (module / soul bar / fury bar / fading).
--
-- Three things the old version did by hand and no longer needs:
--
--   * A Hide/Show button welded onto every colour row, which wrote alpha 0 or 1
--     into db.colors[key][4]. `alpha = true` gives the colour picker a real
--     opacity slider, which does the same thing and everything in between.
--   * Two bookkeeping tables and three GrayContent closures for the cascade.
--   * A private copy of every layout default, restated per row.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

-- SP.DEFAULTS.profile.reapMeter carries the whole `layout` and `colors` tables,
-- not just `enabled` -- and its layout values are the module's own, kept in step
-- with LoadSizesFromDB in Modules/ReapPredict/ReapPredict.lua. The page reads
-- them from there rather than keeping a second copy of thirty numbers: this
-- table used to restate every one of them, which is exactly how an options UI
-- drifts out of step with the module it configures.
--
-- `layout.barTexture` is deliberately absent from both: it has no default, and
-- nil legitimately means "Solid".
local LAYOUT_DEFAULTS = SP.DEFAULTS and SP.DEFAULTS.profile
                        and SP.DEFAULTS.profile.reapMeter
                        and SP.DEFAULTS.profile.reapMeter.layout or {}

local MATCH_LABEL = "Match Ellesmere width"

GUI.RegisterPage{
    id       = "reapmeter",
    name     = "ReapPredict (DH)",
    category = "combat",
    dbKey    = "reapMeter",
    keywords = "reap predict demon hunter devourer soul fragment fury meter " ..
               "void metamorphosis collapsing star ellesmere snap fading",
    build = function(parent)
        local page, db = GUI.ModulePage(parent, "reapMeter", "ReapPredict",
            "ReapPredict",
            "Fury and Soul Fragment meter for Devourer Demon Hunter. Tracks Reap " ..
            "stacks to predict when Void Metamorphosis or Collapsing Star will trigger.",
            "Enable ReapPredict")

        -- The module builds these on enable, but the page can be opened before
        -- the module has ever been switched on.
        db.layout = db.layout or {}
        db.colors = db.colors or {}
        local L  = db.layout
        local DC = (SP.ReapPredict and SP.ReapPredict.DEFAULT_COLORS) or {}

        -- The module is a dot-function API and may not have loaded its bars yet.
        local function Call(name)
            local mod = SP.ReapPredict
            if mod and mod[name] then mod[name]() end
        end
        local SoulSize = function() Call("ApplySize") end
        local SoulPos  = function() Call("ApplySavedPosition") end
        local FurySize = function() Call("ApplyFurySize") end
        local FuryPos  = function() Call("ApplyFuryPosition") end
        local MoCRail  = function() Call("ApplyMoCRailPosition") end
        local Colors   = function() Call("ApplyColors") end
        local Fade     = function() Call("FadeRefresh") end

        -- ── the Ellesmere width picker ──────────────────────────────────
        -- The module arms a fullscreen click-catcher. Nothing else can be
        -- clicked while it is up, so it has to be disarmed if the page goes
        -- away: the old page did not, and closing the window mid-pick left the
        -- catcher swallowing the whole screen until the next pick.
        local function CancelWidthPick()
            local picker = _G.SP_ERBWidthPicker
            if not (picker and picker:IsShown()) then return end
            -- The module keeps its exit path private. Firing the Escape handler
            -- it already installed unwinds it exactly as the user would, and
            -- runs the callback that puts the button caption back.
            local onKey = picker:GetScript("OnKeyDown")
            if onKey then onKey(picker, "ESCAPE") else picker:Hide() end
        end
        parent:HookScript("OnHide", CancelWidthPick)

        local function MatchWidth(btn)
            local mod = SP.ReapPredict
            if not (mod and mod.StartERBWidthPick) then return end
            -- W.Button has a real SetText. The old page had to poke btn.lbl
            -- directly, because GUI:CreateButton never called SetFontString and
            -- Button:SetText was a silent no-op.
            btn:SetText("Click the bar\226\128\166  (Esc / right-click = cancel)")
            btn:SetEnabled(false)
            mod.StartERBWidthPick(function(w)
                btn:SetEnabled(true)
                btn:SetText(w and ("Width matched: %d px"):format(w) or MATCH_LABEL)
                -- The picker writes width AND furyWidth straight into the DB,
                -- so both width sliders are stale until they re-read it.
                if w then page:Refresh() end
            end)
        end

        -- ── Soul bar ────────────────────────────────────────────────────
        local c2 = page:Card("Soul bar",
            "Tracks how many souls Reap will get on its next use, so you can see when " ..
            "it will trigger Void Metamorphosis or Collapsing Star. The MoC preview " ..
            "extends the cap while Moment of Craving is active.",
            LAYOUT_DEFAULTS)

        local soulShow = c2:Toggle{ db = L, key = "showSoulBar", label = "Show soul bar",
                                    onChange = function() Call("UpdateSoulBarVisibility") end }
        c2:GateBelow(soulShow)

        c2:Pair(
            { kind = "slider", db = L, key = "width",  label = "Width",  min = 100, max = 1200, step = 1, onChange = SoulSize },
            { kind = "slider", db = L, key = "height", label = "Height", min = 1,   max = 100,  step = 1, onChange = SoulSize })

        local soulMatch
        soulMatch = c2:ButtonRow{
            text  = MATCH_LABEL,
            width = 200,
            desc  = "Click any bar on screen to copy its width to both bars.",
            onClick = function() MatchWidth(soulMatch.btn) end,
        }

        c2:Slider{ db = L, key = "font", label = "Font size", min = 6, max = 32, step = 1,
                   onChange = SoulSize }

        c2:Toggle{
            db = L, key = "syncToCDM", label = "Sync width to CDM",
            desc = "Both bars follow the Cooldown Manager's width instead of their own.",
            onChange = function(v)
                if v then
                    Call("SyncToCDMNow")
                else
                    SoulPos(); FuryPos()
                end
            end,
        }
        c2:Pair(
            { kind = "slider", db = L, key = "cdmOffsetX", label = "X offset", min = -800, max = 800, step = 1,
              onChange = SoulPos },
            { kind = "slider", db = L, key = "cdmOffsetY", label = "Y offset", min = -800, max = 800, step = 1,
              onChange = function() SoulPos(); FuryPos() end })

        c2:Toggle{ db = L, key = "locked", label = "Lock position",
                   onChange = function() Call("ApplyLock") end }
        c2:Toggle{ db = L, key = "showMocPreview", label = "Show MoC capacity preview",
                   onChange = function() Call("ApplyMoCPreview") end }
        c2:Toggle{ db = L, key = "showCsCounter", label = "Show CS cast counter",
                   onChange = function() Call("ApplyCsCounter") end }
        c2:Toggle{ db = L, key = "cellMode", label = "Cell mode",
                   desc = "Draws one separated cell per stack instead of a continuous bar.",
                   onChange = function() Call("RebuildCellSeparators") end }

        c2:Pair(
            { kind = "slider", db = L, key = "mocRailOffsetX", label = "MoC rail X", min = -200, max = 200, step = 1,
              onChange = MoCRail },
            { kind = "slider", db = L, key = "mocRailOffsetY", label = "MoC rail Y", min = -200, max = 200, step = 1,
              onChange = MoCRail })

        c2:ButtonRow{
            text = "Reset position", width = 160,
            desc = "Drops the dragged position and goes back to the anchor.",
            onClick = function() db.framePos = nil; SoulPos() end,
        }

        -- ── Fury bar ────────────────────────────────────────────────────
        local c3 = page:Card("Fury bar",
            "Shows current Fury with a projection of the next Reap's gain. Hidden during " ..
            "the Meta phase. The MoC preview shows the extra soul fury gain while Moment " ..
            "of Craving is available.",
            LAYOUT_DEFAULTS)

        local furyShow = c3:Toggle{ db = L, key = "showFuryBar", label = "Show fury bar",
                                    onChange = function() Call("UpdateFuryVisibility") end }
        c3:GateBelow(furyShow)

        c3:Pair(
            { kind = "slider", db = L, key = "furyWidth",  label = "Width",  min = 100, max = 1200, step = 1, onChange = FurySize },
            { kind = "slider", db = L, key = "furyHeight", label = "Height", min = 1,   max = 60,   step = 1, onChange = FurySize })

        local furyMatch
        furyMatch = c3:ButtonRow{
            text  = MATCH_LABEL,
            width = 200,
            desc  = "Click any bar on screen to copy its width to both bars.",
            onClick = function() MatchWidth(furyMatch.btn) end,
        }

        c3:Note("Snapping sticks the prediction to another bar's fill edge instead of " ..
                "this bar's own. No gap is possible, not even mid-animation, and the " ..
                "prediction is clipped at the right edge instead of overflowing.")

        -- Declared before the closures that call it; assigned once the note row
        -- below exists.
        local snapNote
        local function RefreshSnapStatus()
            if not snapNote then return end
            local mod = SP.ReapPredict
            local choices = (mod and mod.GetSnapBarChoices and mod.GetSnapBarChoices()) or {}
            if #choices == 0 then
                snapNote.fs:SetText("|cffff5555No EllesmereUI bar detected.|r " ..
                                    "Check that EllesmereUI Resource Bars is enabled.")
                return
            end
            if not (mod and mod.GetSnapStatus) then snapNote.fs:SetText(""); return end
            local on, name, found = mod.GetSnapStatus()
            if not on then
                snapNote.fs:SetText("")
            elseif found then
                snapNote.fs:SetText("|cff55ff55Following|r " .. (name or "?"))
            else
                snapNote.fs:SetText("|cffff5555Not found:|r " .. (name or "?"))
            end
        end

        c3:Toggle{
            db = L, key = "snapToBar", label = "Snap to Ellesmere bar",
            onChange = function() FurySize(); RefreshSnapStatus() end,
        }
        -- A dropdown, not a click-picker: EllesmereUI calls EnableMouse(false)
        -- on its resource bars deliberately, and GetMouseFoci only returns
        -- mouse-enabled regions, so a picker could never select one and would
        -- silently land on WorldFrame instead.
        c3:Dropdown{
            db = L, key = "snapBarName", label = "Bar to follow",
            emptyText = "No EllesmereUI bar detected",
            -- optionsFn, not options: EllesmereUI may load after this page is
            -- built, and the list is then re-read on every page show.
            optionsFn = function()
                local mod = SP.ReapPredict
                return (mod and mod.GetSnapBarChoices and mod.GetSnapBarChoices()) or {}
            end,
            onChange = function(v)
                local mod = SP.ReapPredict
                if mod and mod.SetSnapBar then mod.SetSnapBar(v) end
                RefreshSnapStatus()
            end,
        }
        snapNote = c3:Note("")
        -- The status is live: re-evaluated whenever the page is shown, not just
        -- when it was built.
        snapNote.Refresh = RefreshSnapStatus
        RefreshSnapStatus()

        c3:Slider{ db = L, key = "furyFont", label = "Font size", min = 6, max = 32, step = 1,
                   onChange = FurySize }
        c3:Pair(
            { kind = "slider", db = L, key = "furyOffsetX", label = "X offset", min = -800, max = 800, step = 1,
              onChange = FuryPos },
            { kind = "slider", db = L, key = "furyOffsetY", label = "Y offset", min = -800, max = 800, step = 1,
              onChange = FuryPos })

        c3:Toggle{ db = L, key = "furyLocked", label = "Lock position",
                   onChange = function() Call("ApplyFuryLock") end }
        c3:Toggle{ db = L, key = "showFuryMocPreview", label = "Show MoC capacity preview",
                   onChange = function() Call("ApplyFuryMoCPreview") end }
        c3:Slider{
            label = "Preview opacity", suffix = "%",
            min = 0, max = 100, step = 1,
            -- Stored as a 0-1 alpha, shown as a percentage, so this row carries
            -- its own default rather than reading LAYOUT_DEFAULTS.
            default = 18,
            get = function() return math.floor(((L.furyPreviewAlpha or 0.18) * 100) + 0.5) end,
            set = function(v) L.furyPreviewAlpha = v / 100 end,
            onChange = function() Call("ApplyFuryMoCPreview") end,
        }
        c3:ButtonRow{
            text = "Reset position", width = 160,
            desc = "Drops the dragged position and goes back to the anchor.",
            onClick = function() db.furyPos = nil; FuryPos() end,
        }

        -- ── Shared ──────────────────────────────────────────────────────
        local c4 = page:Card("Shared", "Applies to both bars.", LAYOUT_DEFAULTS)
        c4:FontDropdown{ db = L, key = "fontKey", label = "Font face",
                         onChange = function() SoulSize(); FurySize() end }
        c4:Dropdown{
            label = "Bar texture",
            default = "Solid",
            optionsFn = function()
                local list = { { key = "Solid", label = "Solid" } }
                for _, n in ipairs(SP.GetStatusBarList and SP.GetStatusBarList() or {}) do
                    list[#list + 1] = { key = n, label = n }
                end
                return list
            end,
            get = function() return L.barTexture or "Solid" end,
            -- "Solid" is the absence of a texture: stored as nil so the module
            -- falls back to its own flat fill.
            set = function(v) L.barTexture = (v ~= "Solid") and v or nil end,
            onChange = function() Call("ApplyBarTexture") end,
        }
        c4:DualColor{
            a = { db = db.colors, key = "bg",   label = "Background", alpha = true, hideToggle = true,
                  default = DC.bg,   onChange = Colors },
            b = { db = db.colors, key = "edge", label = "Outer edge", alpha = true, hideToggle = true,
                  default = DC.edge, onChange = Colors },
        }
        c4:ButtonRow{
            text = "Reset all colours", width = 160,
            desc = "Puts every colour on this page back to the module default.",
            onClick = function()
                local mod = SP.ReapPredict
                if mod and mod.ResetColors then mod.ResetColors() end
                -- ResetColors rewrites db.colors behind the UI's back. Without
                -- this every swatch in the window keeps showing the old colour,
                -- which is exactly what the old page did.
                GUI.RefreshAll()
            end,
        }

        -- ── Colours ─────────────────────────────────────────────────────
        -- These two cards point their default lookup at the module's
        -- DEFAULT_COLORS, so no row restates a colour.
        local function Swatch(key, label)
            -- hideToggle: this page has 20 colours and turning one off entirely is a
        -- routine thing to want. The picker's opacity slider still handles
        -- everything between 0 and 1.
        return { db = db.colors, key = key, label = label, alpha = true,
                 hideToggle = true, onChange = Colors }
        end

        local c5 = page:Card("Colours \226\128\148 soul bar", nil, DC)
        c5:DualColor{ a = Swatch("growthBuild",    "Growth bar, build phase"),
                      b = Swatch("growthVM",       "Growth bar, VM phase") }
        c5:DualColor{ a = Swatch("thresholdBuild", "Threshold tick, build phase"),
                      b = Swatch("thresholdVM",    "Threshold tick, VM phase") }
        c5:DualColor{ a = Swatch("beyondBuild",    "Beyond threshold, build phase"),
                      b = Swatch("beyondVM",       "Beyond threshold, VM phase") }
        c5:DualColor{ a = Swatch("sfBase",         "SF, MoC inactive"),
                      b = Swatch("sfMoc",          "SF, MoC active") }
        c5:DualColor{ a = Swatch("mocRailFill",    "MoC rail fill"),
                      b = Swatch("mocRailTrack",   "MoC rail track") }
        c5:DualColor{ a = Swatch("numberLabel",    "Growth number text"),
                      b = Swatch("sfNumberLabel",  "SF number text") }

        local c6 = page:Card("Colours \226\128\148 fury bar", nil, DC)
        c6:DualColor{ a = Swatch("furyFill",    "Fury fill"),
                      b = Swatch("furyFlat",    "Scythes Embrace flat") }
        c6:DualColor{ a = Swatch("furyConsume", "Consume predict"),
                      b = Swatch("furyLabel",   "Fury value text") }
        c6:DualColor{ a = Swatch("furySoul",    "Soul projection"),
                      b = Swatch("furyTick",    "100-fury tick") }

        -- ── Fading ──────────────────────────────────────────────────────
        local c7 = page:Card("Fading",
            "Fades both bars to a chosen opacity based on your current state. " ..
            "Mirrors Ayije CDM's fading behaviour.",
            LAYOUT_DEFAULTS)
        local fadeOn = c7:Toggle{ db = L, key = "fadingEnabled", label = "Enable fading",
                                  onChange = Fade }
        c7:GateBelow(fadeOn)
        c7:Slider{ db = L, key = "fadingOpacity", label = "Faded opacity", suffix = "%",
                   min = 0, max = 99, step = 1, onChange = Fade }
        c7:Toggle{ db = L, key = "fadingTriggerNoTarget", label = "Fade when no target",
                   onChange = Fade }
        c7:Toggle{ db = L, key = "fadingTriggerOOC", label = "Fade when out of combat",
                   onChange = Fade }
        c7:Toggle{ db = L, key = "fadingTriggerMounted", label = "Fade when mounted",
                   onChange = Fade }

        page:Finish()
    end,
}
