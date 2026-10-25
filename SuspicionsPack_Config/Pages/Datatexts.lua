-- SuspicionsPack Options — Datatexts (WoW: Forever only)
--
-- Listed only where the module is: the .toc line carries the same
-- [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic] gate.
--
-- THE BAR EDITOR. Bars are a list in the profile, edited one at a time: a bar
-- dropdown picks which, and every row below it reads and writes that bar
-- through get/set closures. Those rows carry no default on purpose: "Reset
-- page" and the change count are about settings, not about the bars you
-- built, and "Restore default bars" is the way back for those.
--
-- Rows are built once. The 8 datatext rows past the bar's count, and the
-- options of every datatext but the one picked, are hidden with `_hidden` and
-- a restack -- never a page rebuild, which would leak the old page's rows and,
-- from a slider, rebuild on every step of the drag.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

GUI.RegisterPage{
    id       = "datatexts",
    name     = "Datatexts",
    category = "interface",
    dbKey    = "datatexts",
    keywords = "datatext datatexts data text bar bars panel sdt simple gold durability hearthstone " ..
               "time clock fps latency system volume sound guild friends roster",
    build = function(parent)
        local DT = SP.Datatexts
        if DT.EnsureSeeded then DT.EnsureSeeded() end
        local MAX  = DT.MAX_SLOTS or 8
        local NONE = DT.NONE or "none"

        local page, db, c1 = GUI.ModulePage(parent, "datatexts", "Datatexts",
            "Datatexts",
            "Bars of small live texts: gold, durability, the clock, your guild and more. " ..
            "Hover one for details; click it for its action.",
            nil, "General")

        c1:Toggle{ key = "locked", label = "Lock bars",
                   desc = "Unlock to drag the bars. Each one shows its name and a gold outline while unlocked." }
        c1:Toggle{ key = "hideInCombat", label = "Hide every bar in combat" }
        c1:FontDropdown{ key = "fontFace", label = "Font" }
        c1:Slider{ key = "fontSize", label = "Font size", min = 8, max = 24, step = 1 }
        c1:Dropdown{ key = "fontOutline", label = "Outline", options = GUI.OUTLINES }
        c1:ColorSource{ label = "Label colour", srcKey = "labelSource", colorKey = "labelColor" }
        c1:ColorSource{ label = "Value colour", srcKey = "valueSource", colorKey = "valueColor" }

        -- ---- bars ----------------------------------------------------------
        local sel = 1
        local function Bars()
            local d = SP.GetDB().datatexts
            return d and type(d.bars) == "table" and d.bars or {}
        end
        local function Cur()
            local b = Bars()
            if sel > #b then sel = #b end
            if sel < 1 then sel = 1 end
            return b[sel]
        end
        local function Apply() if DT.RequestLayout then DT.RequestLayout() end end

        local c2 = page:Card("Bars",
            "Each bar holds up to 8 datatexts. Unlock the bars to drag them into place. " ..
            "Changes made in combat apply when it ends.")

        local barRows, slotRows = {}, {}
        local barDD

        -- Hides what the selected bar does not use, then re-stacks. `refresh`
        -- re-reads every row too, for a new selection; a slot-count drag only
        -- needs the restack.
        local function Reshape(refresh)
            local b = Cur()
            local n = b and math.floor(tonumber(b.numSlots) or 0) or 0
            for _, row in ipairs(barRows) do row._hidden = (b == nil) end
            for i, row in ipairs(slotRows) do row._hidden = (b == nil) or (i > n) end
            if refresh then page:Refresh() end
            page:Restack()
        end

        barDD = c2:Dropdown{
            label     = "Bar",
            get       = function() return sel end,
            set       = function(v) sel = v end,
            onChange  = function() end,
            emptyText = "No bar",
            optionsFn = function()
                local out = {}
                for i, b in ipairs(Bars()) do out[#out + 1] = { key = i, label = b.name or ("Bar " .. i) } end
                return out
            end,
            onSelect  = function() Reshape(true) end,
        }

        c2:ButtonRow{
            text = "New bar",
            onClick = function()
                local n = DT.NewBar and DT.NewBar()
                if n then sel = n end
                Reshape(true)
            end,
        }

        -- Two clicks, a moment apart: a popup would open under this window.
        local delRow
        delRow = c2:ButtonRow{
            text = "Delete this bar",
            onClick = function(btn)
                if not Cur() then return end
                if not btn._armed then
                    btn._armed = true
                    btn:SetText("Click again to delete")
                    C_Timer.After(3, function()
                        btn._armed = false
                        btn:SetText("Delete this bar")
                    end)
                    return
                end
                btn._armed = false
                btn:SetText("Delete this bar")
                if DT.DeleteBar then DT.DeleteBar(sel) end
                Reshape(true)
            end,
        }
        barRows[#barRows + 1] = delRow

        -- A row bound to a field of the selected bar. `fallback` stands in for a
        -- field the bar lacks; it is not a default (see the top of the file).
        local function BarRow(kind, spec)
            local field, fallback = spec.field, spec.fallback
            spec.field, spec.fallback = nil, nil
            spec.get = function()
                local b = Cur()
                local v = b and b[field]
                if v == nil then v = fallback end
                return v
            end
            spec.set = function(v)
                local b = Cur()
                if b then b[field] = v end
            end
            spec.onChange = spec.onChange or Apply
            local row = c2[kind](c2, spec)
            barRows[#barRows + 1] = row
            return row
        end

        BarRow("EditBox", { field = "name", label = "Name", maxLen = 32, fallback = "",
            onChange = function() barDD:Refresh() ; Apply() end })
        BarRow("Dropdown", { field = "skin", label = "Skin", fallback = "box",
            options = DT.Skins and DT.Skins.List and DT.Skins.List() or {} })
        BarRow("Dropdown", { field = "openEdge", label = "Open edge", fallback = "none",
            desc = "Leaves that side of the border off, for a bar set against a frame above or below it. " ..
                   "Text only has no border.",
            options = DT.Skins and DT.Skins.edges or {} })
        BarRow("Slider", { field = "bgOpacity", label = "Background opacity", suffix = "%",
            min = 0, max = 100, step = 1, fallback = 100,
            desc = "100% hides what is behind the bar. The border stays." })
        BarRow("Slider", { field = "width", label = "Width", min = 40, max = 1600, step = 1, fallback = 300 })
        BarRow("Slider", { field = "height", label = "Height", min = DT.MIN_HEIGHT or 16, max = 60, step = 1,
            fallback = 22 })
        BarRow("Slider", { field = "scale", label = "Scale", suffix = "%", min = 50, max = 200, step = 1, fallback = 100 })
        BarRow("Slider", { field = "numSlots", label = "Number of datatexts", min = 1, max = MAX, step = 1,
            fallback = 3, onChange = function() Apply(); Reshape(false) end })
        BarRow("Toggle", { field = "hideInCombat", label = "Hide in combat", fallback = false })

        -- The bar's offsets from where it is anchored (the Chat bar: the
        -- bottom left of the screen). Dragging the bar writes them too.
        local function OffsetRow(axis, label, desc)
            barRows[#barRows + 1] = c2:Slider{
                label    = label,
                desc     = desc,
                min      = -2000, max = 2000, step = 1,
                get      = function()
                    local b  = Cur()
                    local pt = b and type(b.point) == "table" and b.point
                    local v  = pt and pt[axis]
                    if v == nil then v = 0 end
                    return v
                end,
                set      = function(v)
                    local b = Cur()
                    if not b then return end
                    if type(b.point) ~= "table" then
                        b.point = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
                    end
                    b.point[axis] = v
                end,
                onChange = Apply,
            }
        end
        OffsetRow("x", "X offset", "From where the bar is anchored. Dragging the bar changes it too.")
        OffsetRow("y", "Y offset")
        barRows[#barRows + 1] = c2:ButtonRow{
            text = "Reset position",
            desc = "Back to the middle of the screen.",
            onClick = function() if DT.ResetPosition then DT.ResetPosition(sel) end end,
        }

        for i = 1, MAX do
            slotRows[i] = c2:Dropdown{
                label     = "Datatext " .. i,
                get       = function()
                    local b = Cur()
                    local v = b and type(b.slots) == "table" and b.slots[i]
                    if v == nil or v == false then v = NONE end
                    return v
                end,
                set       = function(v)
                    local b = Cur()
                    if not b then return end
                    if type(b.slots) ~= "table" then b.slots = {} end
                    for k = 1, MAX do
                        if b.slots[k] == nil then b.slots[k] = NONE end
                    end
                    b.slots[i] = v
                end,
                onChange  = Apply,
                optionsFn = function() return DT.List and DT.List() or {} end,
            }
        end

        c2:ButtonRow{
            text  = "Restore default bars",
            desc  = "Replaces every bar with the default one: a single bar in the middle of the screen.",
            width = 180,
            onClick = function()
                if DT.RestoreDefaultBars then DT.RestoreDefaultBars() end
                sel = 1
                Reshape(true)
            end,
        }

        -- ---- per-datatext options -----------------------------------------
        -- One card per datatext with options, all built now; the dropdown
        -- shows one of them.
        local withOptions = {}
        for _, item in ipairs(DT.List and DT.List() or {}) do
            local d = DT.defs and DT.defs[item.key]
            if d and d.options and #d.options > 0 then withOptions[#withOptions + 1] = item end
        end

        local optCards, optSel = {}, withOptions[1] and withOptions[1].key
        local function ShowOptions()
            for id, card in pairs(optCards) do card._hidden = (id ~= optSel) end
            page:Restack()
        end

        if #withOptions > 0 then
            local c3 = page:Card("Datatext options")
            c3:Dropdown{
                label    = "Datatext",
                get      = function() return optSel end,
                set      = function(v) optSel = v end,
                onChange = function() end,
                options  = withOptions,
                onSelect = ShowOptions,
            }
            local KIND = { toggle = "Toggle", slider = "Slider", dropdown = "Dropdown" }
            for _, item in ipairs(withOptions) do
                local id = item.key
                local d  = DT.defs[id]
                local card = page:Card(d.name)
                for _, opt in ipairs(d.options) do
                    local method = KIND[opt.kind]
                    if method then
                        card[method](card, {
                            label     = opt.label,
                            desc      = opt.desc,
                            default   = opt.default,
                            min       = opt.min, max = opt.max, step = opt.step, suffix = opt.suffix,
                            options   = opt.options,
                            optionsFn = opt.optionsFn,
                            get       = function() return DT.O(id)[opt.key] end,
                            set       = function(v) DT.SetOption(id, opt.key, v) end,
                            onChange  = function()
                                DT.Update(id)
                                DT.RefreshSecure(id)
                            end,
                        })
                    end
                end
                optCards[id] = card
            end
        end

        -- A cached page only re-reads its rows when shown again; what is
        -- hidden depends on the bars, which may have changed since (an import,
        -- a profile switch, a bar deleted).
        parent._onPageShow = function() Reshape(false); ShowOptions() end

        page:Finish()
        Reshape(false)
        ShowOptions()
    end,
}
