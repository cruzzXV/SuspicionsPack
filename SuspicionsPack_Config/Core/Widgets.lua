-- SuspicionsPack Options — the widget layer
--
-- THE CONTRACT. Every widget in this file and its siblings returns a `row` frame
-- satisfying all of:
--
--   row.h                natural height. The layout reads this. Callers never
--                        pass a height, which is what killed the old bug where
--                        CreateToggle declared 24 and all 60 call sites passed 28.
--   row:SetEnabled(en)   BLOCKS INPUT. Not merely SetAlpha. The old GrayContent
--                        fell back to alpha for any row without SetEnabled, so
--                        greyed buttons, anchor grids and item rows all still fired.
--   row:Refresh()        re-reads the bound value out of the DB.
--   row:IsModified()     bound value differs from its default.
--   row:ResetDefault()
--   row.searchText       lowercased label + description, for the search index.
--
-- BINDING. Widgets take a binding, not a value plus a callback:
--
--   c:Slider{ key = "threshold", label = "Warning threshold",
--             min = 1, max = 100, default = 30 }
--
-- From `db`+`key`+`default` we get Refresh, the modified count and
-- the search index for free. None of those are expressible in the old
-- value+callback form, which is why none of them existed.
--
-- Set `db`/`key`, or `get`/`set` for anything not backed by a plain table field.

local ADDON, ns = ...

local SP  = SuspicionsPack
local GUI = ns.GUI
local W   = GUI.W
local T   = GUI.T

local Paint, Backdrop, Text, Tex = GUI.Paint, GUI.Backdrop, GUI.Text, GUI.Tex
local ApplyFont, FocusBorder     = GUI.ApplyFont, GUI.FocusBorder

-- Row geometry. One place, so a density change is one edit.
--
-- Every row is ONE LINE: label (and its description) on the left, control on the
-- right. The first pass stacked the control underneath its label across the full
-- width, which made a six-setting card as tall as a page and looked nothing like
-- the approved design.
local PAD        = 14   -- left gutter
local PAD_R      = 14   -- right gutter
-- The control is placed just after its label's text, not at a fixed column and
-- not flush right. Flush right stranded a dropdown at the far side of a 600px
-- card; a fixed column left short labels with a gulf in front of their control.
-- Measuring the label and clamping the result keeps the pair together while
-- stopping the column from wandering between rows.
local COL_MIN    = 150  -- a one-word label still gets a sane control position
local COL_MAX    = 280  -- a long label does not push its control off the card
local COL_GAP    = 26   -- between the end of the label text and the control
local LABEL_COL  = 210  -- fallback for widgets that build their own rows
local DESC_GAP   = 15   -- extra height a description adds
local ROW_H      = 32   -- label and control share one line
local CTRL_H     = 22   -- default control height
local CTRL_W     = 150  -- default control column width
local LABEL_GAP  = 16   -- minimum gap between the label and its control

-- Published so the colour widgets, which build their own rows, land on exactly
-- the same grid instead of drifting a few pixels off it.
GUI.ROWGEO = { PAD = PAD, PAD_R = PAD_R, ROW_H = ROW_H, LABEL_COL = LABEL_COL,
               DESC_GAP = DESC_GAP, CTRL_H = CTRL_H, LABEL_GAP = LABEL_GAP }

-- ============================================================
-- Binding
-- ============================================================

local Binding = {}
Binding.__index = Binding

function GUI.NewBinding(spec)
    return setmetatable({
        get      = spec.get,
        set      = spec.set,
        db       = spec.db,
        key      = spec.key,
        default  = spec.default,
        onChange = spec.onChange,
    }, Binding)
end

function Binding:Get()
    if self.get then return self.get() end
    if self.db and self.key then
        local v = self.db[self.key]
        -- Explicit nil test, not `v or default`: false and 0 are legitimate
        -- stored values and both would fall through an `or`.
        if v == nil then return self.default end
        return v
    end
    return self.default
end

function Binding:Set(v)
    if self.set then
        self.set(v)
    elseif self.db and self.key then
        self.db[self.key] = v
    end
    if self.onChange then self.onChange(v) end
end

function Binding:IsDefault()
    if self.default == nil then return true end
    return GUI.SameValue(self:Get(), self.default)
end

function Binding:Reset()
    if self.default == nil then return end
    -- Copy: handing the shared default table straight to the profile would let
    -- a later colour edit mutate the default itself.
    self:Set(GUI.CopyValue(self.default))
end

-- ============================================================
-- Row scaffold
--
-- Builds the parts every widget shares: the modified dot, the label, the
-- optional description. Widgets add their control and
-- declare their own height on top of this.
-- ============================================================

-- Nothing per-row marks a modified setting any more: no coloured pip, no revert
-- arrow. A pip on every touched row read as a rash, and a 16px glyph wedged
-- between a label and its control looked like a rendering fault next to anything
-- that was not a slider. The footer counts the changes and offers "Reset page",
-- which is where a page-wide action belongs.
local function UpdateModified(row) end

-- `spec` fields consumed here: label, desc, db/key/get/set, default, onChange.
-- ctrlW / ctrlH size the control column on the right; widgets anchor their own
-- control to `row.ctrl` rather than to the row, so the label never has to know
-- how wide the control is.
local function NewRow(parent, spec, ctrlW, ctrlH)
    local row = CreateFrame("Frame", nil, parent)
    row.binding = GUI.NewBinding(spec)
    row.spec    = spec

    ctrlW = ctrlW or CTRL_W
    ctrlH = ctrlH or CTRL_H
    local h = ROW_H

    -- The control column, right-aligned and centred on the first line so a row
    -- with a description keeps its control level with the label above it.
    -- The label first: its measured width decides where the control goes.
    row.label = Text(row, 12, "textPrimary")
    row.label:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -6)
    row.label:SetText(spec.label or "")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)

    -- No label means no label column. The page header's master switch is exactly
    -- this case: an unlabelled toggle in a 50px row. Clamping it to COL_MIN put
    -- the track 100px past the row's own right edge, so the only way to enable a
    -- module vanished off the side of the header.
    local col = 0
    if (spec.label or "") ~= "" then
        col = PAD + math.ceil(row.label:GetStringWidth() or 0) + COL_GAP
        if col < COL_MIN then col = COL_MIN elseif col > COL_MAX then col = COL_MAX end
    end
    row.labelCol = col

    row.ctrl = CreateFrame("Frame", nil, row)
    row.ctrl:SetSize(ctrlW, ctrlH)
    row.ctrl:SetPoint("TOPLEFT", row, "TOPLEFT", col, -math.floor((ROW_H - ctrlH) / 2))
    -- A stretchy control (the slider) also pins its right edge; a fixed-width
    -- one keeps the width it was given.
    if spec.stretch then
        row.ctrl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -PAD_R, -math.floor((ROW_H - ctrlH) / 2))
    end

    if spec.desc then
        -- Anchored to the ROW's top, not to the label's bottom.
        --
        -- The control is vertically centred on the first ROW_H band, so it
        -- occupies roughly y -5 to -27. A description hung off the label's
        -- bottom starts around -23 and, now that it runs full width, ran
        -- straight underneath the control. Starting it below the whole band
        -- keeps the two apart whatever the label's height turns out to be.
        row.descFS = Text(row, 10, "textMuted")
        row.descFS:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -(ROW_H - 3))
        row.descFS:SetPoint("RIGHT", row, "RIGHT", -PAD_R, 0)
        row.descFS:SetText(spec.desc)
        row.descFS:SetJustifyH("LEFT")
        row.descFS:SetWordWrap(false)
        h = h + DESC_GAP
    end

    row:SetHeight(h)
    row.h = h

    row.searchText = string.lower((spec.label or "") .. " " .. (spec.desc or ""))

    function row:IsModified()  return self.binding and not self.binding:IsDefault() end
    function row:ResetDefault()
        self.binding:Reset()
        self:Refresh()
        UpdateModified(self)
    end
    function row:Sync() UpdateModified(self) end

    GUI.RegisterRefresh(row)
    return row
end

-- Standard disable.
--
-- NOT SetAlpha. Fading the frame let the card show through the control, so a
-- disabled slider looked like a rendering fault rather than a disabled slider.
-- The row stays fully opaque; its colours go muted, and each widget dims its own
-- control through the `_dim` hook it registers.
local function StdSetEnabled(row, en)
    row._disabled = not en
    if row.label then
        local c = en and T.textPrimary or T.textMuted
        row.label:SetTextColor(c[1], c[2], c[3], 1)
    end
    if row._dim then row._dim(en) end
end

-- ============================================================
-- Label — static explanatory text, no binding
-- ============================================================

function W.Label(parent, spec)
    local row = CreateFrame("Frame", nil, parent)
    local fs  = Text(row, spec.size or 11, spec.color or "textMuted")
    fs:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, 0)
    fs:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetText(spec.text or "")
    row.fs = fs

    -- Wrapped text only reports a real height once it has a width, and the row
    -- has none until the card anchors it. Measure on the first size change and
    -- tell the card to re-stack.
    local h = spec.height or math.max(14, math.ceil(fs:GetStringHeight()))
    row:SetHeight(h)
    row.h = h
    row.searchText = string.lower(spec.text or "")

    row:SetScript("OnSizeChanged", function(self, w)
        if not w or w <= 0 then return end
        local want = math.max(14, math.ceil(fs:GetStringHeight()))
        if math.abs(want - self.h) > 1 then
            self.h = want
            self:SetHeight(want)
            if self._card then self._card:Restack() end
        end
    end)

    function row:SetEnabled(en)
        self._disabled = not en
        local c = en and (T[spec.color or "textMuted"]) or T.border
        fs:SetTextColor(c[1], c[2], c[3], 1)
    end
    function row:Refresh() end
    function row:IsModified() return false end
    function row:ResetDefault() end
    function row:Sync() end
    return row
end

-- ============================================================
-- Toggle
-- ============================================================

-- A capsule track with a round knob, not a 1px rectangle with a square pip.
local TR_W, TR_H, KNOB = 38, 16, 12

function W.Toggle(parent, spec)
    local row = NewRow(parent, spec, TR_W, TR_H)

    local track = CreateFrame("Frame", nil, row.ctrl)
    track:SetAllPoints(row.ctrl)

    local trackBG = GUI.RoundTex(track, "BACKGROUND", "pill", false, -8)
    trackBG:SetAllPoints(track)
    local trackBR = GUI.RoundTex(track, "BORDER", "pill", true, 7)
    trackBR:SetAllPoints(track)

    local knob = GUI.CircleTex(track, "OVERLAY")
    knob:SetSize(KNOB, KNOB)

    local OFF_X, ON_X = 2, TR_W - KNOB - 2
    local state = row.binding:Get() and true or false
    local pos   = state and ON_X or OFF_X

    local function Place()
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", track, "LEFT", pos, 0)
    end

    -- The track colour lerps with the knob so the two never disagree mid-slide.
    local function PaintTrack()
        local p  = (pos - OFF_X) / (ON_X - OFF_X)
        local a  = T.accent
        local bg = T.bgMedium
        trackBG:SetVertexColor(
            bg[1] + (a[1] - bg[1]) * p,
            bg[2] + (a[2] - bg[2]) * p,
            bg[3] + (a[3] - bg[3]) * p, 1)
        local br = row._hover and T.accent or T.border
        trackBR:SetVertexColor(br[1], br[2], br[3], 1)
        knob:SetVertexColor(1, 1, 1, 1)
    end
    GUI.PaintLater(track, PaintTrack)
    Place(); PaintTrack()

    local function Slide(target, instant)
        if instant or not SP.Tick then
            pos = target; Place(); PaintTrack(); return
        end
        SP.Tick.Animate(pos, target, 0.18, function(v)
            pos = v; Place(); PaintTrack()
        end)
    end

    local hit = CreateFrame("Button", nil, row)
    hit:SetAllPoints(row)
    hit:SetScript("OnEnter", function()
        if row._disabled then return end
        row._hover = true; PaintTrack()
    end)
    hit:SetScript("OnLeave", function()
        row._hover = false; PaintTrack()
    end)
    hit:SetScript("OnClick", function()
        if row._disabled then return end
        state = not state
        Slide(state and ON_X or OFF_X)
        -- Written immediately. The old toggle deferred the DB write by the 0.18s
        -- animation length, so a fast click-and-close lost the change.
        row.binding:Set(state)
        UpdateModified(row)
        if spec.onToggle then spec.onToggle(state) end
    end)

    GUI.Tooltip(hit, spec.tipTitle, spec.tipBody)

    function row:GetValue() return state end
    function row:SetValue(v, instant)
        state = v and true or false
        Slide(state and ON_X or OFF_X, instant)
    end
    function row:Refresh()
        self:SetValue(self.binding:Get(), true)
        UpdateModified(self)
    end
    function row:SetEnabled(en)
        StdSetEnabled(self, en)
        hit:EnableMouse(en)
    end

    UpdateModified(row)
    return row
end

-- ============================================================
-- Slider
-- ============================================================

-- Label left, rail and value on the right, all on one line.
local SLIDER_W, VALUE_W = 210, 44

function W.Slider(parent, spec)
    spec.stretch = true
    local row = NewRow(parent, spec, SLIDER_W, CTRL_H)

    local minV, maxV = spec.min or 0, spec.max or 100
    local step       = spec.step or 1
    local suffix     = spec.suffix or ""

    local box = CreateFrame("EditBox", nil, row.ctrl)
    box:SetSize(VALUE_W, 20)
    box:SetPoint("RIGHT", row.ctrl, "RIGHT", 0, 0)
    box:SetAutoFocus(false)
    box:EnableMouse(true)
    -- 6 letters, not SetNumeric: numeric mode strips the minus sign, which broke
    -- every negative-range slider (offsets go to -2000).
    box:SetMaxLetters(7)
    box:SetJustifyH("CENTER")
    box:SetTextInsets(3, 3, 0, 0)
    ApplyFont(box, 11)
    Backdrop(box, "bgMedium", 1, "border", 1, "rr4")
    Paint(box, function(f, t) f:SetTextColor(t.textPrimary[1], t.textPrimary[2], t.textPrimary[3], 1) end)

    local slider = CreateFrame("Slider", nil, row.ctrl)
    slider:SetHeight(20)
    slider:SetPoint("LEFT",  row.ctrl, "LEFT", 0, 0)
    slider:SetPoint("RIGHT", box, "LEFT", -10, 0)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local track = Tex(slider, "BACKGROUND", "bgDark")
    track:SetHeight(5)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)

    local fill = Tex(slider, "ARTWORK", "accent", 0.85)
    fill:SetHeight(5)
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)

    -- A round grab handle. The rail stays square: at 5px tall a radius is
    -- imperceptible, and a nine-slice whose margins exceed the frame height
    -- squashes its own corners.
    -- White, matching the toggle knob. A red handle on a red rail disappeared
    -- into it.
    local thumb = GUI.CircleTex(slider, "OVERLAY")
    Paint(thumb, function(f) f:SetVertexColor(1, 1, 1, 1) end)
    thumb:SetSize(13, 13)
    slider:SetThumbTexture(thumb)

    local function Fill(v)
        local span = maxV - minV
        local p = span > 0 and (v - minV) / span or 0
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        local w = track:GetWidth()
        if w and w > 0 then
            local fw = w * p
            -- Below a pixel there is nothing to draw, and clamping to 1 left a
            -- red speck welded to the left end of every slider at minimum.
            if fw < 1 then fill:Hide() else fill:Show(); fill:SetWidth(fw) end
        end
    end

    local function Clamp(v)
        v = tonumber(v)
        if not v then return nil end
        if v < minV then v = minV elseif v > maxV then v = maxV end
        if step and step > 0 then
            v = math.floor((v - minV) / step + 0.5) * step + minV
        end
        return v
    end

    local applying = false
    local function Commit(v)
        if applying then return end
        applying = true
        box:SetText(tostring(v) .. suffix)
        Fill(v)
        row.binding:Set(v)
        UpdateModified(row)
        applying = false
    end

    slider:SetScript("OnValueChanged", function(self, v)
        if applying then return end
        v = Clamp(v)
        if v then Commit(v) end
    end)
    slider:SetScript("OnSizeChanged", function() Fill(slider:GetValue()) end)

    box:SetScript("OnEnterPressed", function(self)
        -- Strip everything that is not part of a number, rather than building a
        -- pattern out of the suffix: "%" .. "s" is %s, the WHITESPACE class, so
        -- the two sliders with suffix "s" left the "s" in place, tonumber failed
        -- and the entry silently reverted. This also swallows a stray space or a
        -- pasted unit, which the old pattern never did.
        local v = Clamp((self:GetText() or ""):gsub("[^%-%d%.]", ""))
        self:ClearFocus()
        if v then applying = true; slider:SetValue(v); applying = false; Commit(v)
        else self:SetText(tostring(slider:GetValue()) .. suffix) end
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText(tostring(slider:GetValue()) .. suffix)
    end)
    box:SetScript("OnEnter", function(self)
        if not row._disabled then FocusBorder(self, true) end
    end)
    box:SetScript("OnLeave", function(self)
        if not self:HasFocus() then FocusBorder(self, false) end
    end)
    box:SetScript("OnEditFocusGained", function(self)
        -- Strip the suffix while editing so the user is not typing around a "%".
        if suffix ~= "" then self:SetText(tostring(slider:GetValue())) end
        FocusBorder(self, true)
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:SetText(tostring(slider:GetValue()) .. suffix)
        FocusBorder(self, false)
    end)
    box:SetScript("OnHide", function(self) GUI.FocusCancel(self) end)

    function row:GetValue() return slider:GetValue() end
    function row:SetValue(v)
        v = Clamp(v) or minV
        applying = true
        slider:SetValue(v)
        box:SetText(tostring(v) .. suffix)
        Fill(v)
        applying = false
    end
    function row:Refresh()
        self:SetValue(self.binding:Get())
        UpdateModified(self)
    end
    row._dim = function(en)
        local f = en and T.accent or T.border
        fill:SetVertexColor(f[1], f[2], f[3], en and 0.85 or 1)
        local th = en and 1 or 0.55
        thumb:SetVertexColor(th, th, th, 1)
        local tc = en and T.textPrimary or T.textMuted
        box:SetTextColor(tc[1], tc[2], tc[3], 1)
    end
    function row:SetEnabled(en)
        StdSetEnabled(self, en)
        slider:EnableMouse(en)
        box:SetEnabled(en)
        if not en then box:ClearFocus() end
    end
    -- Lets the caller narrow the label so two sliders fit side by side.

    row:SetValue(row.binding:Get())
    UpdateModified(row)
    return row
end

-- ============================================================
-- Dropdown
--
-- The popup is LAZY and REBUILDABLE. The old GUI:CreateDropdown built every
-- item frame at construction time -- 25 to 45 frames for a font list, whether or
-- not the user ever opened it -- and because it was built once, a list that was
-- empty on first visit (the TTS voice list, which arrives asynchronously) stayed
-- empty forever. The file worked around that in one place by using a second,
-- private dropdown implementation.
-- ============================================================

local ITEM_H, MAX_VIS = 22, 10

local BAR_W = 3

-- THE LIST MUST SCROLL, AND IT MUST LOOK LIKE IT SCROLLS.
--
-- A font list is 20 to 100 entries on any install carrying ElvUI, WeakAuras or
-- SharedMedia, and the popup shows MAX_VIS of them. The first attempt clipped
-- the frame and moved the items by hand under EnableMouseWheel on the popup --
-- which never received the wheel in game, because the item buttons sit above it
-- and take the input first. WoW's own ScrollFrame handles that, and it is the
-- same primitive the sidebar and the page canvas already use here.
--
-- The thumb on the right is not decoration: a list that silently continues past
-- its own bottom edge reads as a list that ends there.
local function BuildPopup(dd)
    local pop = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    pop:SetFrameStrata("FULLSCREEN_DIALOG")
    pop:SetFrameLevel(220)
    pop:Hide()
    Backdrop(pop, "bgDark", 1, "accent", 0.8)

    local sf = CreateFrame("ScrollFrame", nil, pop)
    sf:SetPoint("TOPLEFT",     pop, "TOPLEFT",      1, -1)
    sf:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -1,  1)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    GUI.SmoothScroll(sf, ITEM_H * 2)

    -- Flat, not nine-sliced: 3px is far below any slice minimum, and WoW would
    -- draw the rounded texture outside the frame.
    local track = Tex(pop, "ARTWORK", "border", 0.55)
    track:SetWidth(BAR_W)
    track:SetPoint("TOPRIGHT",    pop, "TOPRIGHT",    -2, -3)
    track:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -2,  3)
    local thumb = Tex(pop, "OVERLAY", "accent", 0.95)
    thumb:SetWidth(BAR_W)

    pop.sf, pop.content, pop.track, pop.thumb = sf, content, track, thumb
    pop.items = {}

    function pop:UpdateBar()
        local range = self.sf:GetVerticalScrollRange() or 0
        if range <= 0 then
            self.track:Hide(); self.thumb:Hide()
            return
        end
        self.track:Show(); self.thumb:Show()
        local visH = self.sf:GetHeight() or 1
        local h    = visH * visH / (visH + range)
        if h < 16 then h = 16 end
        if h > visH then h = visH end
        local cur = self.sf:GetVerticalScroll() or 0
        self.thumb:SetHeight(h)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOP", self.track, "TOP", 0, -((visH - h) * (cur / range)))
    end

    sf:HookScript("OnVerticalScroll", function(s) pop:UpdateBar() end)
    sf:HookScript("OnScrollRangeChanged", function(s) pop:UpdateBar() end)

    dd.popup = pop
    return pop
end

local function LayoutPopup(dd)
    local pop  = dd.popup or BuildPopup(dd)
    local opts = dd.options
    local n    = #opts

    for i = 1, math.max(n, #pop.items) do
        local it = pop.items[i]
        if i > n then
            if it then it:Hide() end
        else
            if not it then
                it = CreateFrame("Button", nil, pop.content)
                it:SetHeight(ITEM_H)
                it:SetPoint("TOPLEFT",  pop.content, "TOPLEFT",  0, -((i - 1) * ITEM_H))
                it:SetPoint("RIGHT",    pop.content, "RIGHT",    0, 0)
                it.fill = Tex(it, "BACKGROUND", "accent", 0.15)
                it.fill:SetAllPoints()
                it.fill:Hide()
                it.bar = Tex(it, "ARTWORK", "accent")
                it.bar:SetWidth(2)
                it.bar:SetPoint("TOPLEFT", it, "TOPLEFT", 0, 0)
                it.bar:SetPoint("BOTTOMLEFT", it, "BOTTOMLEFT", 0, 0)
                it.bar:Hide()
                it.lbl = it:CreateFontString(nil, "OVERLAY")
                it.lbl:SetPoint("LEFT", it, "LEFT", 8, 0)
                it.lbl:SetPoint("RIGHT", it, "RIGHT", -6, 0)
                it.lbl:SetJustifyH("LEFT")
                it:SetScript("OnEnter", function(s)
                    s.lbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
                    s.fill:Show()
                end)
                it:SetScript("OnLeave", function(s)
                    local sel = s.key == dd.value
                    s.lbl:SetTextColor(
                        sel and T.accent[1] or T.textSecondary[1],
                        sel and T.accent[2] or T.textSecondary[2],
                        sel and T.accent[3] or T.textSecondary[3], 1)
                    if not sel then s.fill:Hide() end
                end)
                it:SetScript("OnClick", function(s)
                    dd:Close()
                    dd:Select(s.key)
                end)
                pop.items[i] = it
            end
            local o = opts[i]
            it.key = o.key
            -- Placement is pop:Reposition's job, called from pop:Scroll below.
            -- The font dropdown renders each entry in its own typeface, which is
            -- the entire point of picking a font from a list.
            local face = dd.fontResolver and dd.fontResolver(o.key)
            if face then
                local ok = pcall(it.lbl.SetFont, it.lbl, face, 12, "")
                if not ok then ApplyFont(it.lbl, 11) end
            else
                ApplyFont(it.lbl, 11)
            end
            it.lbl:SetText(o.label or o.key)
            it:Show()
        end
    end

    local full = n * ITEM_H
    pop._full  = full
    pop._visH  = math.min(full, MAX_VIS * ITEM_H)
    pop.content:SetHeight(math.max(1, full))
    pop:SetHeight(pop._visH + 2)
    -- A shorter list can leave the previous offset past the new end.
    local range = pop.sf:GetVerticalScrollRange() or 0
    if (pop.sf:GetVerticalScroll() or 0) > range then pop.sf:SetVerticalScroll(range) end
    pop:UpdateBar()
end

local function PaintPopup(dd)
    local pop = dd.popup
    if not pop then return end
    for i = 1, #dd.options do
        local it = pop.items[i]
        if it then
            local sel = it.key == dd.value
            it.lbl:SetTextColor(
                sel and T.accent[1] or T.textSecondary[1],
                sel and T.accent[2] or T.textSecondary[2],
                sel and T.accent[3] or T.textSecondary[3], 1)
            if sel then it.fill:Show(); it.bar:Show()
            else it.fill:Hide(); it.bar:Hide() end
        end
    end
end

-- spec.bare = true drops the label and description and shrinks the row to just
-- the 20px trigger. Composites (ColorSource, the
-- anchor row) embed one of these next to their own label instead of nesting a
-- full labelled row inside another labelled row.
function W.Dropdown(parent, spec)
    local row
    if spec.bare then
        row = CreateFrame("Frame", nil, parent)
        row:SetHeight(20)
        row.h = 20
        row.binding    = GUI.NewBinding(spec)
        row.spec       = spec
        row.searchText = string.lower(spec.label or "")
        function row:IsModified() return self.binding and not self.binding:IsDefault() end
        function row:ResetDefault() self.binding:Reset(); self:Refresh() end
        function row:Sync() end
        GUI.RegisterRefresh(row)
    else
        row = NewRow(parent, spec, spec.ctrlW or CTRL_W, CTRL_H)
    end

    local btn = CreateFrame("Button", nil, spec.bare and row or row.ctrl)
    if spec.bare then
        btn:SetHeight(20)
        btn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    else
        btn:SetAllPoints(row.ctrl)
    end
    Backdrop(btn, "bgMedium", 1, "border", 1, "rr4")

    local val = btn:CreateFontString(nil, "OVERLAY")
    val:SetPoint("LEFT", btn, "LEFT", 7, 0)
    val:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
    val:SetJustifyH("LEFT")
    ApplyFont(val, 11)
    Paint(val, function(f, t) f:SetTextColor(t.textPrimary[1], t.textPrimary[2], t.textPrimary[3], 1) end)

    -- A '<' chevron: pointing left when closed, rotated down when open.
    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(11, 11)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -7, 0)
    arrow:SetTexture("Interface\\AddOns\\SuspicionsPack\\Media\\GUITextures\\chevron.png")
    Paint(arrow, function(f, t) f:SetVertexColor(t.textMuted[1], t.textMuted[2], t.textMuted[3], 1) end)
    arrow:SetRotation(0)

    -- 0 = pointing left (closed), +pi/2 = pointing down (open). Negative
    -- rotation turned it UP, which reads as "this collapses upward".
    local function SpinArrow(open)
        local from = arrow:GetRotation() or 0
        local to   = open and (math.pi / 2) or 0
        if SP.Tick then
            SP.Tick.Animate(from, to, 0.16, function(v) arrow:SetRotation(v) end)
        else
            arrow:SetRotation(to)
        end
    end

    row.btn        = btn
    row.options    = {}
    row.value      = nil
    row.fontResolver = spec.fontResolver

    local function LabelFor(key)
        for _, o in ipairs(row.options) do
            if o.key == key then return o.label or o.key end
        end
        return tostring(key)
    end

    function row:Close()
        -- The closer comes down FIRST and unconditionally. It is a fullscreen
        -- AnyUp button over the whole game, and the early return below used to
        -- skip past it whenever the popup had been hidden by some other means --
        -- while CloseActivePopup had already cleared the handle, so nothing
        -- would ever retry. That strands a click-eater until /reload.
        GUI.GetCloser():Hide()
        if GUI._activePopupClose == self._closeFn then GUI._activePopupClose = nil end
        if not self.popup or not self.popup:IsShown() then return end
        self.popup:Hide()
        SpinArrow(false)
        arrow:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
        if btn._spBorder then
            btn._spBorder:SetVertexColor(T.border[1], T.border[2], T.border[3], 1)
        end
    end
    row._closeFn = function() row:Close() end

    function row:Open()
        if self._disabled or #self.options == 0 then return end
        GUI.CloseActivePopup()
        LayoutPopup(self)
        PaintPopup(self)
        local pop = self.popup
        pop:SetWidth(btn:GetWidth())
        -- Derived from the button rather than read back off the ScrollFrame:
        -- an anchor-driven size does not settle until the next frame.
        pop.content:SetWidth(math.max(1, (btn:GetWidth() or 2) - 2 - BAR_W - 3))
        -- Land the list on the current value. With 60 fonts and yours at #45,
        -- opening on entries 1 to 10 is barely better than not opening at all.
        local sel = 0
        for i, o in ipairs(self.options) do
            if o.key == self.value then sel = i; break end
        end
        local range = pop.sf:GetVerticalScrollRange() or 0
        local to    = sel > MAX_VIS and (sel - MAX_VIS) * ITEM_H or 0
        if to > range then to = range end
        pop.sf._target = to
        pop.sf:SetVerticalScroll(to)
        pop:UpdateBar()
        pop:ClearAllPoints()
        -- Flip upward when the list would run off the bottom of the screen.
        local below = btn:GetBottom() or 0
        if below - pop:GetHeight() < 20 then
            pop:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 2)
        else
            pop:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        end
        pop:Show()
        -- Slide down from nothing. It used to appear at full height in one
        -- frame, which loses the connection between the trigger and the list.
        local full = pop:GetHeight()
        -- Start at the nine-slice minimum, not 1. Below 2 * margin WoW has no
        -- centre strip left to stretch and draws the rounded fill and its
        -- outline OUTSIDE the frame, so opening from 1px flashed a halo for the
        -- first frames of every single open. AuditSlices cannot see this one --
        -- it samples sizes at call time, and by then the popup is full height.
        local minH = ((GUI.ROUND and GUI.ROUND.rr4 and GUI.ROUND.rr4.margin) or 8) * 2
        if SP.Tick and full and full > minH then
            pop:SetHeight(minH)
            SP.Tick.Animate(minH, full, 0.16, function(v) pop:SetHeight(v) end)
        end
        local closer = GUI.GetCloser()
        closer:SetFrameStrata("FULLSCREEN_DIALOG")
        closer:SetFrameLevel(210)
        closer:Show()
        GUI._activePopupClose = self._closeFn
        SpinArrow(true)
        arrow:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
        if btn._spBorder then
            btn._spBorder:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
        end
    end

    function row:Select(key)
        self.value = key
        val:SetText(LabelFor(key))
        local face = self.fontResolver and self.fontResolver(key)
        if face then
            if not pcall(val.SetFont, val, face, 12, "") then ApplyFont(val, 11) end
        end
        self.binding:Set(key)
        UpdateModified(self)
        if spec.onSelect then spec.onSelect(key) end
    end

    -- Replaces the option list at runtime. This is what the old implementation
    -- could not do, and why the TTS voice list needed a second dropdown type.
    function row:SetOptions(list, keepValue)
        self.options = list or {}
        if self.popup then LayoutPopup(self) end
        local v = keepValue ~= false and self.binding:Get() or nil
        local found = false
        for _, o in ipairs(self.options) do
            if o.key == v then found = true; break end
        end
        if not found then v = self.options[1] and self.options[1].key end
        self.value = v
        val:SetText(v and LabelFor(v) or (spec.emptyText or "—"))
    end

    btn:SetScript("OnClick", function()
        if row.popup and row.popup:IsShown() then row:Close() else row:Open() end
    end)
    GUI.HoverBorder(btn, function() return row.popup and row.popup:IsShown() end)
    -- The popup is UIParent-parented, so hiding the page does not hide it.
    row:SetScript("OnHide", function() row:Close() end)

    function row:GetValue() return self.value end
    function row:SetValue(v)
        self.value = v
        -- Explicit nil test. LabelFor falls back to tostring(key) for a value
        -- that is not in the list, so a nil value used to render the literal
        -- string "nil" -- and it overwrote the emptyText that SetOptions had
        -- just put there, making emptyText impossible to ever see.
        if v == nil then
            val:SetText(spec.emptyText or "—")
        else
            val:SetText(LabelFor(v))
        end
        if self.popup and self.popup:IsShown() then PaintPopup(self) end
    end
    function row:Refresh()
        -- Re-run a dynamic option provider so a list that filled in since the
        -- page was built (sounds, fonts, voices) is current.
        if spec.optionsFn then self:SetOptions(spec.optionsFn()) end
        self:SetValue(self.binding:Get())
        UpdateModified(self)
    end
    row._dim = function(en)
        local c = en and T.textPrimary or T.textMuted
        val:SetTextColor(c[1], c[2], c[3], 1)
    end
    function row:SetEnabled(en)
        StdSetEnabled(self, en)
        btn:EnableMouse(en)
        if not en then self:Close() end
    end

    local initial = spec.options
    if spec.optionsFn then initial = spec.optionsFn() end
    if initial and type(initial[1]) == "string" then initial = GUI.StrOptions(initial) end
    row:SetOptions(initial or {})
    row:SetValue(row.binding:Get())
    UpdateModified(row)
    return row
end

function W.FontDropdown(parent, spec)
    spec.optionsFn = function() return GUI.StrOptions(SP.GetFontList()) end
    spec.fontResolver = function(name) return SP.GetFontPath(name) end
    return W.Dropdown(parent, spec)
end

-- ============================================================
-- EditBox
--
-- Replaces nine hand-rolled copies of the same 25-36 line block scattered
-- through the page builders, each with its own subtly different commit and
-- revert behaviour.
-- ============================================================

function W.EditBox(parent, spec)
    local row = NewRow(parent, spec, spec.ctrlW or 180, CTRL_H)

    local box = CreateFrame("EditBox", nil, row.ctrl)
    box:SetAllPoints(row.ctrl)
    box:SetAutoFocus(false)
    box:EnableMouse(true)
    box:SetMaxLetters(spec.maxLen or 128)
    box:SetTextInsets(6, 6, 0, 0)
    ApplyFont(box, 11)
    Backdrop(box, "bgMedium", 1, "border", 1, "rr4")
    Paint(box, function(f, t) f:SetTextColor(t.textPrimary[1], t.textPrimary[2], t.textPrimary[3], 1) end)

    local function Current() return row.binding:Get() or "" end

    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        row.binding:Set(self:GetText())
        UpdateModified(row)
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText(Current())
    end)
    -- Hover lights the border exactly like focus does; without it a text field
    -- was the only control in the window that gave no feedback under the cursor.
    box:SetScript("OnEnter", function(self)
        if not row._disabled then FocusBorder(self, true) end
    end)
    box:SetScript("OnLeave", function(self)
        if not self:HasFocus() then FocusBorder(self, false) end
    end)
    box:SetScript("OnEditFocusGained", function(self) FocusBorder(self, true) end)
    box:SetScript("OnEditFocusLost", function(self)
        FocusBorder(self, false)
        -- Commit on blur too. The old boxes only committed on Enter, so clicking
        -- away silently discarded what the user typed.
        if self:GetText() ~= Current() then
            row.binding:Set(self:GetText())
            UpdateModified(row)
        end
    end)
    box:SetScript("OnHide", function(self) GUI.FocusCancel(self) end)

    row.box = box
    function row:GetValue() return box:GetText() end
    function row:SetValue(v) box:SetText(v or "") end
    function row:Refresh()
        if box:HasFocus() then return end   -- never yank text out from under a typist
        self:SetValue(self.binding:Get())
        UpdateModified(self)
    end
    row._dim = function(en)
        local c = en and T.textPrimary or T.textMuted
        box:SetTextColor(c[1], c[2], c[3], 1)
    end
    function row:SetEnabled(en)
        StdSetEnabled(self, en)
        box:SetEnabled(en)
        if not en then box:ClearFocus() end
    end

    box:SetText(Current())
    UpdateModified(row)
    return row
end

-- ============================================================
-- Button
--
-- Gets a real SetEnabled, which GUI:CreateButton never had -- every wrapper
-- around it dimmed the button and left it firing.
-- ============================================================

function W.Button(parent, spec)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(spec.width or 110, spec.height or 22)
    Backdrop(btn, "bgMedium", 1, "border", 1, "rr4")

    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetAllPoints()
    ApplyFont(lbl, 11)
    lbl:SetText(spec.text or "")
    Paint(lbl, function(f, t)
        local c = btn._active and t.accent or t.textPrimary
        f:SetTextColor(c[1], c[2], c[3], 1)
    end)
    btn.lbl = lbl

    GUI.HoverBorder(btn, function(f) return f._active end)
    btn:SetScript("OnClick", function(self)
        if self._disabled then return end
        if spec.onClick then spec.onClick(self) end
    end)
    GUI.Tooltip(btn, spec.tipTitle, spec.tipBody)

    function btn:SetText(t) lbl:SetText(t) end
    function btn:SetActive(on)
        self._active = on and true or false
        local c = self._active and T.accent or T.textPrimary
        lbl:SetTextColor(c[1], c[2], c[3], 1)
        GUI.FocusBorder(self, self._active)
    end
    function btn:SetEnabled(en)
        self._disabled = not en
        local c = en and (self._active and T.accent or T.textPrimary) or T.textMuted
        lbl:SetTextColor(c[1], c[2], c[3], 1)
        self:EnableMouse(en)
    end
    return btn
end

-- A button wrapped in a row so a card can stack it like any other setting.
function W.ButtonRow(parent, spec)
    local row = CreateFrame("Frame", nil, parent)
    local h   = spec.desc and (24 + DESC_GAP + 4) or 26
    row:SetHeight(h)
    row.h = h

    local btn = W.Button(row, spec)
    btn:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -1)

    if spec.desc then
        local d = Text(row, 10, "textMuted")
        d:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -4)
        d:SetPoint("RIGHT", row, "RIGHT", -20, 0)
        d:SetText(spec.desc)
        d:SetJustifyH("LEFT")
        d:SetWordWrap(true)
    end

    row.btn = btn
    row.searchText = string.lower((spec.text or "") .. " " .. (spec.desc or ""))
    function row:SetEnabled(en)
        self._disabled = not en
        btn:SetEnabled(en)
    end
    function row:Refresh() end
    function row:IsModified() return false end
    function row:ResetDefault() end
    function row:Sync() end
    return row
end
