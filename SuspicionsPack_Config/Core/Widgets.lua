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

    -- BOTH ANCHORED TO THE SAME CENTRE LINE.
    --
    -- The label used to hang from the row's top at a fixed -6 while the control
    -- was centred in the ROW_H band. A FontString's height depends on its font,
    -- so the two centres landed a few pixels apart and every switch sat visibly
    -- low against its own text. Deriving one number and anchoring both to it
    -- makes the misalignment unrepresentable rather than merely corrected.
    --
    -- The label takes its LEFT point, which IS its vertical middle.
    local ctrlTop = math.floor((ROW_H - ctrlH) / 2)
    local midY    = -(ctrlTop + ctrlH / 2)
    row.midY      = midY

    -- The label first: its measured width decides where the control goes.
    row.label = Text(row, 12, "textPrimary")
    row.label:SetPoint("LEFT", row, "TOPLEFT", PAD, midY)
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
    row.ctrl:SetPoint("TOPLEFT", row, "TOPLEFT", col, -ctrlTop)
    -- A stretchy control (the slider) also pins its right edge; a fixed-width
    -- one keeps the width it was given.
    if spec.stretch then
        row.ctrl:SetPoint("TOPRIGHT", row, "TOPRIGHT", -PAD_R, -ctrlTop)
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

    local function Measure(self)
        local want = math.max(14, math.ceil(fs:GetStringHeight()))
        if math.abs(want - self.h) > 1 then
            self.h = want
            self:SetHeight(want)
            if self._card then self._card:Restack() end
        end
    end
    -- Measured again a frame later. The wrap a new width brings is not always
    -- counted yet when the size changes: on Forever, Home's last Profiles note
    -- wrapped to two lines, measured one, and ran into the card's bottom edge.
    row:SetScript("OnSizeChanged", function(self, w)
        if not w or w <= 0 then return end
        Measure(self)
        if not self._remeasure then
            self._remeasure = true
            C_Timer.After(0, function()
                self._remeasure = nil
                Measure(self)
            end)
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
-- Track 36x18 with a 14px knob, not 38x16 with a 12. The ratio is what reads:
-- a knob at 78% of the track height leaves a thin even margin all round and the
-- switch looks like a switch, where 75% of a shorter track reads flat and thin.
local TR_W, TR_H, KNOB = 36, 18, 14

-- Forever: the game's check box (UICheckButtonTemplate), the control NeedRoll
-- and Keep or Toss use for every on/off. 24 square, between their 22 and 26.
local CHECK = 24

-- Gap between the switch and the text it belongs to. The check box art has
-- its own transparent margin, so it needs less.
local TOGGLE_LABEL_GAP = GUI.FOREVER and 2 or 6

-- The two looks of an on/off. Each draws into row.ctrl at state `on` and
-- returns Show(on, instant), which moves it to a state, and Repaint(), which
-- redraws it for row._hover and row._disabled. W.Toggle owns the state, the
-- clicks and the binding; these only draw.

local function BuildSwitch(row, on)
    local track = CreateFrame("Frame", nil, row.ctrl)
    track:SetAllPoints(row.ctrl)

    -- A true capsule, not the `pill` nine-slice. That texture is a rounded
    -- RECTANGLE with a ~5px radius and was sliced at margin 8 -- a margin wider
    -- than the radius, so each corner carried a piece of the straight edge and
    -- the ends read flat. A capsule cannot be nine-sliced at all: its radius is
    -- half its height, so the margins always meet and leave no centre strip.
    local trackBG = GUI.CapsuleTex(track, "BACKGROUND", false, -8)
    trackBG:SetAllPoints(track)
    local trackBR = GUI.CapsuleTex(track, "BORDER", true, 7)
    trackBR:SetAllPoints(track)

    -- The ON state is its OWN layer over the dark track, not a recolour of it.
    --
    -- Lerping one texture between the background and the accent was the obvious
    -- way and it looks flat: at rest the switch is a grey rectangle, and every
    -- intermediate frame is a muddy blend of two unrelated colours. Two layers
    -- keep the dark track underneath at all times and cross-fade the accent in
    -- above it, so the colour sits ON the surface rather than replacing it, and
    -- the hover tint of the track still reads through.
    local fill = GUI.CapsuleTex(track, "BACKGROUND", false, -7)
    fill:SetAllPoints(track)

    local knob = GUI.CircleTex(track, "OVERLAY")
    knob:SetSize(KNOB, KNOB)

    local OFF_X, ON_X = 2, TR_W - KNOB - 2
    local pos = on and ON_X or OFF_X

    local function Place()
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", track, "LEFT", pos, 0)
    end

    -- Everything visual is driven by ONE number: how far along the knob is.
    -- Track, fill and knob can never disagree mid-slide because none of them
    -- carries its own idea of the state.
    local function PaintTrack()
        local p = (pos - OFF_X) / (ON_X - OFF_X)

        local bg = T.bgMedium
        trackBG:SetVertexColor(bg[1], bg[2], bg[3], 1)

        -- Disabled drops the accent ENTIRELY rather than dimming it. A greyed
        -- switch that is still red reads as "on and working"; the whole point of
        -- the disabled state is that it cannot be mistaken for a live one.
        local c = row._disabled and T.textMuted or T.accent
        GUI.TintGradientH(fill, c[1], c[2], c[3], p)

        local br = (row._hover and not row._disabled) and T.accent or T.border
        trackBR:SetVertexColor(br[1], br[2], br[3], 1)
        knob:SetVertexColor(1, 1, 1, 1)
    end
    GUI.PaintLater(track, PaintTrack)
    Place(); PaintTrack()

    local function Show(state, instant)
        local target = state and ON_X or OFF_X
        if instant or not SP.Tick then
            pos = target; Place(); PaintTrack(); return
        end
        SP.Tick.Animate(pos, target, 0.15, function(v)
            pos = v; Place(); PaintTrack()
        end)
    end
    return Show, PaintTrack
end

local function BuildCheck(row, on)
    local box = CreateFrame("CheckButton", nil, row.ctrl, "UICheckButtonTemplate")
    box:SetAllPoints(row.ctrl)
    -- The row's hit button takes every click, label and gap included, as it
    -- does for the switch. The box only shows the state, so its hover light is
    -- driven by hand.
    box:EnableMouse(false)

    local state = on
    local function Repaint()
        box:SetChecked(state)
        box:SetEnabled(not row._disabled)
        -- The template greys a disabled tick but has no art for a disabled
        -- empty box.
        local v = row._disabled and 0.5 or 1
        box:GetNormalTexture():SetVertexColor(v, v, v)
        if row._hover and not row._disabled then box:LockHighlight() else box:UnlockHighlight() end
    end
    Repaint()

    local function Show(newState)
        state = newState
        Repaint()
    end
    return Show, Repaint
end

function W.Toggle(parent, spec)
    local ctrlW, ctrlH = TR_W, TR_H
    if GUI.FOREVER then ctrlW, ctrlH = CHECK, CHECK end
    local row = NewRow(parent, spec, ctrlW, ctrlH)

    -- THE SWITCH COMES FIRST, then its label.
    --
    -- Every other row in this file is label-left / control-after, and NewRow
    -- builds that. A switch is the one control that reads better inverted: it is
    -- small, its state IS the information, and putting it first means the eye
    -- scans a column of on/off states instead of hunting for them at the end of
    -- labels of differing length.
    --
    -- Re-anchored here rather than parameterised in NewRow, because NewRow
    -- measures the label to place the control and that whole calculation is
    -- meaningless once the order flips. Only the two points move; the shared
    -- centre line (midY) and the description's own anchor are untouched.
    -- TOPLEFT, like NewRow's own anchor. Anchoring by LEFT instead puts the
    -- control's vertical MIDDLE on the centre line, which drops its bottom edge
    -- half a control lower and straight through the description underneath.
    -- Caught by the "no control overlaps its own description" assertion.
    -- midY == -(ctrlTop + ctrlH/2), so this recovers ctrlTop exactly.
    row.ctrl:ClearAllPoints()
    row.ctrl:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, row.midY + ctrlH / 2)

    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", row.ctrl, "RIGHT", TOGGLE_LABEL_GAP, 0)
    -- The label no longer has a column to be clamped into, so it may run to the
    -- card's edge instead of being truncated at COL_MAX.
    row.label:SetPoint("RIGHT", row, "RIGHT", -PAD_R, 0)
    row.labelCol = PAD

    local state = row.binding:Get() and true or false
    local Show, Repaint = (GUI.FOREVER and BuildCheck or BuildSwitch)(row, state)

    local hit = CreateFrame("Button", nil, row)
    hit:SetAllPoints(row)
    hit:SetScript("OnEnter", function()
        if row._disabled then return end
        row._hover = true; Repaint()
    end)
    hit:SetScript("OnLeave", function()
        row._hover = false; Repaint()
    end)
    hit:SetScript("OnClick", function()
        if row._disabled then return end

        -- Write the flipped value, then READ BACK what the binding actually
        -- holds. Flipping a local and trusting it means a setter that clamps,
        -- refuses, or rewrites the value leaves the switch showing one thing
        -- while the profile holds another -- and the switch is the more
        -- convincing of the two. Going back to the source keeps the setter
        -- authoritative.
        row.binding:Set(not state)
        state = row.binding:Get() and true or false

        -- Written before the slide, not after. The old toggle deferred the DB
        -- write by the 0.18s animation, so a fast click-and-close lost it.
        Show(state)
        UpdateModified(row)
        if PlaySound and SOUNDKIT then
            PlaySound(state and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                            or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end
        if spec.onToggle then spec.onToggle(state) end
    end)

    GUI.Tooltip(hit, spec.tipTitle, spec.tipBody)

    function row:GetValue() return state end
    function row:SetValue(v, instant)
        state = v and true or false
        Show(state, instant)
    end
    function row:Refresh()
        self:SetValue(self.binding:Get(), true)
        UpdateModified(self)
    end
    function row:SetEnabled(en)
        StdSetEnabled(self, en)
        hit:EnableMouse(en)
        -- StdSetEnabled only greys the LABEL. Without this the track kept its
        -- full accent while switched off, so a locked-on switch looked exactly
        -- like a live one.
        Repaint()
    end

    UpdateModified(row)
    return row
end

-- ============================================================
-- Text field
-- ============================================================

-- The field the slider's value and W.EditBox type into.
--
-- Forever: the game's InputBoxTemplate (NeedRoll's native input). Its edge art
-- sits 5 outside the box on the left, and it has no outline of ours, so
-- FocusBorder passes over it. Its own Escape and focus scripts are replaced by
-- the caller's.
local function NewInputBox(parent)
    local box
    if GUI.FOREVER then
        box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    else
        box = CreateFrame("EditBox", nil, parent)
        Backdrop(box, "bgMedium", 1, "border", 1, "rr4")
    end
    box:SetAutoFocus(false)
    box:EnableMouse(true)
    ApplyFont(box, 11)
    Paint(box, function(f, t) f:SetTextColor(t.textPrimary[1], t.textPrimary[2], t.textPrimary[3], 1) end)
    return box
end

-- ============================================================
-- Slider
-- ============================================================

-- Label left, rail and value on the right, all on one line.
local SLIDER_W, VALUE_W = 210, 44

-- Forever: the game's field at its own art's size (20 high, edge caps 8 wide)
-- read too big round a value of two or three digits. 38 x 16 still holds
-- "-2000" in the 10 point font; the caps shrink with the height, and the left
-- one is pulled in level with the box (the template hangs it 5 outside), so
-- the art is centred on the text it frames.
local VALUE_W_SMALL, VALUE_H_SMALL, VALUE_CAP_SMALL = 38, 16, 6

function W.Slider(parent, spec)
    spec.stretch = true
    local row = NewRow(parent, spec, SLIDER_W, CTRL_H)

    local minV, maxV = spec.min or 0, spec.max or 100
    local step       = spec.step or 1
    local suffix     = spec.suffix or ""

    local box = NewInputBox(row.ctrl)
    if GUI.FOREVER then
        box:SetSize(VALUE_W_SMALL, VALUE_H_SMALL)
        for _, part in ipairs({ box.Left, box.Middle, box.Right }) do
            part:SetHeight(VALUE_H_SMALL)
        end
        box.Left:SetWidth(VALUE_CAP_SMALL)
        box.Right:SetWidth(VALUE_CAP_SMALL)
        box.Left:ClearAllPoints()
        box.Left:SetPoint("LEFT", box, "LEFT", 0, 0)
        ApplyFont(box, 10)
    else
        box:SetSize(VALUE_W, 20)
    end
    box:SetPoint("RIGHT", row.ctrl, "RIGHT", 0, 0)
    -- 6 letters, not SetNumeric: numeric mode strips the minus sign, which broke
    -- every negative-range slider (offsets go to -2000).
    box:SetMaxLetters(7)
    box:SetJustifyH("CENTER")
    box:SetTextInsets(3, 3, 0, 0)

    -- Forever: the game's own slider, the one its options panel uses. Its rail
    -- and thumb are Forever art, and it has no fill.
    local slider
    if GUI.FOREVER then
        slider = CreateFrame("Slider", nil, row.ctrl, "MinimalSliderTemplate")
    else
        slider = CreateFrame("Slider", nil, row.ctrl)
    end
    slider:SetHeight(20)
    slider:SetPoint("LEFT",  row.ctrl, "LEFT", 0, 0)
    slider:SetPoint("RIGHT", box, "LEFT", -10, 0)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local track, fill, thumb
    if not GUI.FOREVER then
        track = Tex(slider, "BACKGROUND", "bgDark")
        track:SetHeight(5)
        track:SetPoint("LEFT", slider, "LEFT", 0, 0)
        track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)

        fill = Tex(slider, "ARTWORK", "accent", 0.85)
        fill:SetHeight(5)
        fill:SetPoint("LEFT", track, "LEFT", 0, 0)

        -- A round grab handle. The rail stays square: at 5px tall a radius is
        -- imperceptible, and a nine-slice whose margins exceed the frame height
        -- squashes its own corners.
        -- White, matching the toggle knob. A red handle on a red rail
        -- disappeared into it.
        thumb = GUI.CircleTex(slider, "OVERLAY")
        Paint(thumb, function(f) f:SetVertexColor(1, 1, 1, 1) end)
        thumb:SetSize(13, 13)
        slider:SetThumbTexture(thumb)
    end

    local function Fill(v)
        if not fill then return end
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
        if fill then
            local f = en and T.accent or T.border
            fill:SetVertexColor(f[1], f[2], f[3], en and 0.85 or 1)
            local th = en and 1 or 0.55
            thumb:SetVertexColor(th, th, th, 1)
        else
            -- The game's slider has no disabled art: grey its rail and thumb.
            local v = en and 1 or 0.5
            for _, part in ipairs({ slider.Left, slider.Middle, slider.Right, slider.Thumb }) do
                part:SetDesaturated(not en)
                part:SetVertexColor(v, v, v)
            end
        end
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

-- Forever: Plumber's dropdown (its landing page's, Basic.lua). The list is a
-- black box with a thin bronze rim, rows 6 in from its top and bottom, a radio
-- dot 8 in on each row and the text 4 after it. Plumber's rows are 24; 20
-- here, with the button cut down to match (DD_ART): at its own sizes the
-- dropdown stood half again as tall as everything round it.
local ITEM_H, MAX_VIS = GUI.FOREVER and 20 or 22, 10
local POP_PAD_V = GUI.FOREVER and 6 or 1
local POP_PAD_H = GUI.FOREVER and 4 or 1
local RADIO, RADIO_X = 16, 8

-- Plumber's button art at three quarters: 24 high round our 22 high button
-- instead of 32.
local DD_ART = 0.75

local BAR_W = 3

-- Forever: the list scrolls with the game's MinimalScrollBar, as the page
-- does: 8 wide, 6 in from the box's right, 6 clear of the rows.
local POP_BAR_W   = 8
local POP_BAR_ROOM = GUI.FOREVER and (POP_BAR_W + 6) or (BAR_W + 3)

local PLUMBER = GUI.PLUMBER

-- Plumber's dropdown button: a dark box with a bronze rim in three slices
-- (ends 20 and 32 wide, 32 high, standing 2.5 out past the button's ends) and
-- the same slices added over it at 25% under the mouse; its copper arrow
-- square, 32, centred 13.5 in from the right, and the arrow's glow, 48. All
-- drawn at DD_ART of those sizes. Returns the slices and the arrow, which the
-- caller greys and presses.
local function PlumberDropdownArt(btn)
    local s = DD_ART
    local slices = {}
    for _, layer in ipairs({ "BACKGROUND", "HIGHLIGHT" }) do
        local left = GUI.PlumberRect(btn:CreateTexture(nil, layer), PLUMBER.FRAME, 518, 558, 256, 320)
        left:SetSize(20 * s, 32 * s)
        left:SetPoint("LEFT", btn, "LEFT", -2.5 * s, 0)
        local right = GUI.PlumberRect(btn:CreateTexture(nil, layer), PLUMBER.FRAME, 690, 754, 256, 320)
        right:SetSize(32 * s, 32 * s)
        right:SetPoint("RIGHT", btn, "RIGHT", 2.5 * s, 0)
        local middle = GUI.PlumberRect(btn:CreateTexture(nil, layer), PLUMBER.FRAME, 558, 690, 256, 320)
        middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
        middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
        for _, tex in ipairs({ left, middle, right }) do
            if layer == "HIGHLIGHT" then
                tex:SetBlendMode("ADD")
                tex:SetAlpha(0.25)
            else
                slices[#slices + 1] = tex
            end
        end
    end

    local arrow = GUI.PlumberRect(btn:CreateTexture(nil, "OVERLAY"), PLUMBER.FRAME, 764, 828, 256, 320)
    arrow:SetSize(32 * s, 32 * s)
    arrow:SetPoint("CENTER", btn, "RIGHT", -13.5 * s, 0)
    local glow = GUI.PlumberRect(btn:CreateTexture(nil, "HIGHLIGHT"), PLUMBER.FRAME, 892, 956, 256, 320)
    glow:SetSize(48 * s, 48 * s)
    glow:SetPoint("CENTER", btn, "RIGHT", -13.5 * s, 0)
    glow:SetBlendMode("ADD")
    return slices, arrow
end

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
    if GUI.FOREVER then
        SP.Skin.PlumberBox(pop)
    else
        Backdrop(pop, "bgDark", 1, "accent", 0.8)
    end

    local sf = CreateFrame("ScrollFrame", nil, pop)
    sf:SetPoint("TOPLEFT",     pop, "TOPLEFT",      POP_PAD_H, -POP_PAD_V)
    sf:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -POP_PAD_H,  POP_PAD_V)

    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)

    pop.sf, pop.content = sf, content
    pop.items = {}

    -- Whether the rows run past the box at its full height. Not the scroll
    -- range: while the box slides open it is shorter than its rows, so a list
    -- of four flashed a scroll bar for the length of the slide.
    function pop:Overflows()
        return (self._full or 0) > (self._visH or 0)
    end

    if GUI.FOREVER then
        -- The page's scroll bar, wired the same way (ScrollUtil drives the
        -- frame, the wheel included), shown only when the list overflows.
        local bar = CreateFrame("EventFrame", nil, pop, "MinimalScrollBar")
        bar:SetPoint("TOPRIGHT",    pop, "TOPRIGHT",    -6, -POP_PAD_V)
        bar:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -6,  POP_PAD_V)
        ScrollUtil.InitScrollFrameWithScrollBar(sf, bar)
        sf:EnableMouseWheel(true)
        sf:SetPanExtent(ITEM_H * 2)
        bar:Hide()
        pop.bar = bar

        function pop:UpdateBar()
            self.bar:SetShown(self:Overflows())
        end
        sf:HookScript("OnScrollRangeChanged", function() pop:UpdateBar() end)
    else
        GUI.SmoothScroll(sf, ITEM_H * 2)

        -- Flat, not nine-sliced: 3px is far below any slice minimum, and WoW
        -- would draw the rounded texture outside the frame.
        local track = Tex(pop, "ARTWORK", "border", 0.55)
        track:SetWidth(BAR_W)
        track:SetPoint("TOPRIGHT",    pop, "TOPRIGHT",    -2, -3)
        track:SetPoint("BOTTOMRIGHT", pop, "BOTTOMRIGHT", -2,  3)
        local thumb = Tex(pop, "OVERLAY", "accent", 0.95)
        thumb:SetWidth(BAR_W)
        pop.track, pop.thumb = track, thumb

        function pop:UpdateBar()
            local range = self.sf:GetVerticalScrollRange() or 0
            if range <= 0 or not self:Overflows() then
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
    end

    dd.popup = pop
    return pop
end

-- Forever's row: the radio dot marks the current value, the text is cream and
-- turns white over the brown bar under the mouse (Plumber's MenuButton).
local function PaintPlumberItem(it, sel, hover)
    local c = hover and T.textHover or T.textPrimary
    it.lbl:SetTextColor(c[1], c[2], c[3], 1)
    it.fill:SetShown(hover)
    GUI.PlumberRect(it.radio, PLUMBER.MENU, sel and 32 or 0, sel and 64 or 32, 0, 32, 512)
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
                it.lbl = it:CreateFontString(nil, "OVERLAY")
                it.lbl:SetPoint("RIGHT", it, "RIGHT", -6, 0)
                it.lbl:SetJustifyH("LEFT")
                -- One line, cut short if it must: a long font name drawn in its
                -- own face wrapped to two and spilled over the next row.
                it.lbl:SetWordWrap(false)
                if GUI.FOREVER then
                    -- Plumber's bar: a dark pill tinted brown and added over the
                    -- row.
                    it.fill = GUI.PlumberRect(it:CreateTexture(nil, "BACKGROUND"), PLUMBER.MENU, 368, 512, 0, 48, 512)
                    it.fill:SetAllPoints()
                    it.fill:SetVertexColor(119 / 255, 96 / 255, 74 / 255)
                    it.fill:SetBlendMode("ADD")
                    it.fill:Hide()
                    it.radio = it:CreateTexture(nil, "ARTWORK")
                    it.radio:SetSize(RADIO, RADIO)
                    it.radio:SetPoint("LEFT", it, "LEFT", RADIO_X, 0)
                    it.lbl:SetPoint("LEFT", it.radio, "RIGHT", 4, 0)
                    it:SetScript("OnEnter", function(s) PaintPlumberItem(s, s.key == dd.value, true) end)
                    it:SetScript("OnLeave", function(s) PaintPlumberItem(s, s.key == dd.value, false) end)
                else
                    it.fill = Tex(it, "BACKGROUND", "accent", 0.15)
                    it.fill:SetAllPoints()
                    it.fill:Hide()
                    it.bar = Tex(it, "ARTWORK", "accent")
                    it.bar:SetWidth(2)
                    it.bar:SetPoint("TOPLEFT", it, "TOPLEFT", 0, 0)
                    it.bar:SetPoint("BOTTOMLEFT", it, "BOTTOMLEFT", 0, 0)
                    it.bar:Hide()
                    it.lbl:SetPoint("LEFT", it, "LEFT", 8, 0)
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
                end
                it:SetScript("OnClick", function(s)
                    GUI.Sound(GUI.SOUND_ON)
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
            -- Forever: 12, the game's normal font size, as Plumber's rows.
            local size = GUI.FOREVER and 12 or 11
            local face = dd.fontResolver and dd.fontResolver(o.key)
            if face then
                local ok = pcall(it.lbl.SetFont, it.lbl, face, 12, "")
                if not ok then ApplyFont(it.lbl, size) end
            else
                ApplyFont(it.lbl, size)
            end
            it.lbl:SetText(o.label or o.key)
            it:Show()
        end
    end

    local full = n * ITEM_H
    pop._full  = full
    pop._visH  = math.min(full, MAX_VIS * ITEM_H)
    pop.content:SetHeight(math.max(1, full))
    pop:SetHeight(pop._visH + 2 * POP_PAD_V)
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
        if it and GUI.FOREVER then
            PaintPlumberItem(it, it.key == dd.value, false)
        elseif it then
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

    -- Forever: Plumber's button; its text starts 8 in and stops clear of the
    -- arrow square (32 short of the right end at Plumber's size).
    local slices, arrow
    if GUI.FOREVER then
        slices, arrow = PlumberDropdownArt(btn)
    else
        Backdrop(btn, "bgMedium", 1, "border", 1, "rr4")
    end

    local val = btn:CreateFontString(nil, "OVERLAY")
    val:SetPoint("LEFT", btn, "LEFT", GUI.FOREVER and 8 or 7, 0)
    val:SetPoint("RIGHT", btn, "RIGHT", GUI.FOREVER and -32 * DD_ART or -20, 0)
    val:SetJustifyH("LEFT")
    ApplyFont(val, GUI.FOREVER and 12 or 11)
    Paint(val, function(f, t) f:SetTextColor(t.textPrimary[1], t.textPrimary[2], t.textPrimary[3], 1) end)

    if not GUI.FOREVER then
        -- A '<' chevron: pointing left when closed, rotated down when open.
        arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(11, 11)
        arrow:SetPoint("RIGHT", btn, "RIGHT", -7, 0)
        arrow:SetTexture("Interface\\AddOns\\SuspicionsPack\\Media\\GUITextures\\chevron.png")
        Paint(arrow, function(f, t) f:SetVertexColor(t.textMuted[1], t.textMuted[2], t.textMuted[3], 1) end)
        arrow:SetRotation(0)
    end

    -- Retail: 0 = pointing left (closed), +pi/2 = pointing down (open), tinted
    -- with the accent while open. Negative rotation turned it UP, which reads
    -- as "this collapses upward". Forever: Plumber's arrow square stays
    -- pressed while its list is open.
    local function ShowArrow(open)
        if GUI.FOREVER then
            GUI.PlumberRect(arrow, PLUMBER.FRAME, open and 828 or 764, open and 892 or 828, 256, 320)
            return
        end
        local from = arrow:GetRotation() or 0
        local to   = open and (math.pi / 2) or 0
        if SP.Tick then
            SP.Tick.Animate(from, to, 0.16, function(v) arrow:SetRotation(v) end)
        else
            arrow:SetRotation(to)
        end
        local c = open and T.accent or T.textMuted
        arrow:SetVertexColor(c[1], c[2], c[3], 1)
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
        ShowArrow(false)
        if btn._spBorder then
            btn._spBorder:SetVertexColor(T.border[1], T.border[2], T.border[3], 1)
        end
    end
    row._closeFn = function() row:Close() end

    function row:Open()
        if self._disabled or #self.options == 0 then return end
        GUI.Sound(GUI.SOUND_ON)
        GUI.CloseActivePopup()
        LayoutPopup(self)
        PaintPopup(self)
        local pop = self.popup
        pop:SetWidth(btn:GetWidth())
        -- Derived from the button rather than read back off the ScrollFrame:
        -- an anchor-driven size does not settle until the next frame.
        pop.content:SetWidth(math.max(1, (btn:GetWidth() or 2) - 2 * POP_PAD_H - POP_BAR_ROOM))
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
        -- Forever: 6 off the button, as Plumber's, clear of both pieces' art.
        local gap = GUI.FOREVER and 6 or 2
        local below = btn:GetBottom() or 0
        if below - pop:GetHeight() < 20 then
            pop:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, gap)
        else
            pop:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -gap)
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
        ShowArrow(true)
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
        if row.popup and row.popup:IsShown() then
            GUI.Sound(GUI.SOUND_OFF)
            row:Close()
        else
            row:Open()
        end
    end)
    GUI.HoverBorder(btn, function() return row.popup and row.popup:IsShown() end)
    if GUI.FOREVER then
        -- Plumber's text turns white under the mouse. A disabled button takes
        -- no mouse, so this never repaints a greyed one.
        local function Tint(key)
            local c = T[key]
            val:SetTextColor(c[1], c[2], c[3], 1)
        end
        btn:HookScript("OnEnter", function() Tint("textHover") end)
        btn:HookScript("OnLeave", function() Tint("textPrimary") end)
    end
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
        -- Forever: greyed as Plumber greys its own (desaturated, half).
        if slices then
            local v = en and 1 or 0.5
            for _, tex in ipairs(slices) do
                tex:SetDesaturated(not en)
                tex:SetVertexColor(v, v, v)
            end
            arrow:SetDesaturated(not en)
            local a = en and 1 or 0.6
            arrow:SetVertexColor(a, a, a)
        end
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

    local box = NewInputBox(row.ctrl)
    box:SetAllPoints(row.ctrl)
    box:SetMaxLetters(spec.maxLen or 128)
    -- The game's field starts its text at the box's edge; its art already
    -- frames it.
    box:SetTextInsets(GUI.FOREVER and 0 or 6, 6, 0, 0)

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

-- Forever: the game's UIPanelButtonTemplate, Keep or Toss's buttons. It greys
-- its own art and text when disabled, and LockHighlight is its lit state, so
-- that is what "active" means here. It widens to fit its text, now and on
-- every SetText: the game's font runs wider than Expressway, and a Blizzard
-- button does not clip its label, it spills it over the art.
local function ForeverButton(parent, spec)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetHeight(spec.height or 22)
    local minW = spec.width or 110

    local nativeSetText = btn.SetText
    function btn:SetText(t)
        nativeSetText(self, t)
        self:SetWidth(math.max(minW, math.ceil(self:GetTextWidth() or 0) + 24))
    end
    btn:SetText(spec.text or "")

    btn:SetScript("OnClick", function(self)
        if self._disabled then return end
        GUI.Sound(GUI.SOUND_ON)
        if spec.onClick then spec.onClick(self) end
    end)
    GUI.Tooltip(btn, spec.tipTitle, spec.tipBody)

    function btn:SetActive(on)
        self._active = on and true or false
        if self._active then self:LockHighlight() else self:UnlockHighlight() end
    end
    local nativeSetEnabled = btn.SetEnabled
    function btn:SetEnabled(en)
        self._disabled = not en
        nativeSetEnabled(self, en)
    end
    return btn
end

function W.Button(parent, spec)
    if GUI.FOREVER then return ForeverButton(parent, spec) end

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
