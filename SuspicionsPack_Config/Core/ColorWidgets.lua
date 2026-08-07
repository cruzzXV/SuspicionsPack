-- SuspicionsPack Options — colour widgets
--
-- Same contract as everything in Widgets.lua: row.h, a SetEnabled that blocks
-- input, Refresh that re-reads the DB, IsModified, ResetDefault.
--
-- The old colour widgets were the worst offenders on the refresh front: the
-- displayed swatch colour was captured into locals at build time and never
-- re-derived, so "Reset all colours" on the ReapPredict page repainted the bars
-- in game while every swatch in the options window kept showing the old colour.

local ADDON, ns = ...

local SP  = SuspicionsPack
local GUI = ns.GUI
local W   = GUI.W
local T   = GUI.T

local Paint, Text, ApplyFont = GUI.Paint, GUI.Text, GUI.ApplyFont

local G     = nil   -- resolved lazily: Widgets.lua publishes it at load
local function geo() G = G or GUI.ROWGEO; return G end

-- Same rule as the standard rows: the control starts just past the label text,
-- clamped so it neither hugs a one-word label nor runs off a long one.
local function ColumnFor(labelFS)
    local g = geo()
    local col = g.PAD + math.ceil((labelFS:GetStringWidth() or 0)) + 26
    if col < 150 then col = 150 elseif col > 280 then col = 280 end
    return col
end

local function Hex(r, g, b)
    return string.format("#%02X%02X%02X",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- WoW's ColorPickerFrame uses INVERTED opacity: 0 = opaque, 1 = transparent.
-- Preserved verbatim from the previous implementation -- this is the shape the
-- live client actually accepts, and getting it backwards is silent.
local function PickerInfo(r, g, b, onUpdate, onCancel, a)
    local info = { r = r, g = g, b = b }
    if a ~= nil then
        info.hasOpacity = true
        info.opacity    = 1 - a
    end
    info.swatchFunc = function()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = a
        if info.hasOpacity then
            local op = ColorPickerFrame:GetColorAlpha()
            na = op ~= nil and (1 - op) or a
        end
        onUpdate(nr or r, ng or g, nb or b, na)
    end
    info.cancelFunc  = function() onCancel() end
    info.opacityFunc = info.swatchFunc
    return info
end

-- ============================================================
-- Swatch button — checkerboard so alpha is visible
-- ============================================================

local CHK_D, CHK_L = 0.28, 0.50

function W.Swatch(parent, w, h)
    local sw = CreateFrame("Button", nil, parent)
    sw:SetSize(w or 62, h or 20)

    -- A mid-grey rounded plate behind the colour, so a translucent swatch still
    -- reads as translucent. The old version used a 2x2 checkerboard of square
    -- quads, which cannot follow a corner radius.
    local plate = GUI.RoundTex(sw, "BACKGROUND", "rr4")
    plate:SetAllPoints(sw)
    plate:SetVertexColor(CHK_L, CHK_L, CHK_L, 1)

    local fillTex = GUI.RoundTex(sw, "ARTWORK", "rr4")
    fillTex:SetPoint("TOPLEFT", sw, "TOPLEFT", 1, -1)
    fillTex:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", -1, 1)
    sw.fill = fillTex

    local brd = GUI.RoundTex(sw, "OVERLAY", "rr4", true)
    brd:SetAllPoints(sw)
    GUI.Paint(brd, function(f, t)
        f:SetVertexColor(t.border[1], t.border[2], t.border[3], 1)
    end)
    sw.brd = brd

    sw:SetScript("OnEnter", function()
        brd:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end)
    sw:SetScript("OnLeave", function()
        brd:SetVertexColor(T.border[1], T.border[2], T.border[3], 1)
    end)

    function sw:SetColor(r, g, b, a)
        -- SetVertexColor, not SetColorTexture: the latter would replace the
        -- rounded texture with a flat rectangle.
        fillTex:SetVertexColor(r, g, b, a ~= nil and a or 1)
    end
    return sw
end

-- ============================================================
-- Colour — a single bound swatch
--
-- spec.key holds a {r,g,b} or {r,g,b,a} array in the DB. spec.alpha = true
-- enables the opacity slider and stores the 4th component.
-- ============================================================

local function ColorCell(row, spec, host, getFn, setFn, labelText)
    local lbl = Text(host, 10, "textMuted")
    lbl:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    lbl:SetText(labelText or "")

    local sw = W.Swatch(host, 62, 20)
    if labelText then
        sw:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -13)
    else
        sw:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        sw:SetSize(62, 20)
    end

    -- The hex readout is gone: it sat to the RIGHT of the swatch, so on a
    -- right-aligned control it ran off the edge of the card and was clipped.
    -- The swatch shows the colour; the picker shows the number.
    -- A Show/Hide button beside the swatch, for colours a user turns off wholesale
    -- rather than dials. It writes alpha 0 or 1; the picker's opacity slider still
    -- covers everything in between.
    local hideBtn
    if spec.hideToggle then
        hideBtn = W.Button(host, {
            text = "Hide", width = 46, height = 20,
            onClick = function()
                if row._disabled then return end
                local c = getFn() or { 1, 1, 1, 1 }
                local hidden = (c[4] or 1) == 0
                setFn({ c[1], c[2], c[3], hidden and 1 or 0 })
                if host._syncCell then host._syncCell() end
            end,
        })
        hideBtn:SetPoint("LEFT", sw, "RIGHT", 6, 0)
    end

    local function Sync()
        local c = getFn() or { 1, 1, 1 }
        local a = spec.alpha and (c[4] ~= nil and c[4] or 1) or nil
        sw:SetColor(c[1] or 1, c[2] or 1, c[3] or 1, a)
        if hideBtn then
            local hidden = (c[4] or 1) == 0
            hideBtn:SetText(hidden and "Show" or "Hide")
            hideBtn:SetActive(hidden)
        end
    end
    host._syncCell = Sync

    sw:SetScript("OnMouseUp", function()
        if row._disabled then return end
        local c    = getFn() or { 1, 1, 1 }
        local r, g, b = c[1] or 1, c[2] or 1, c[3] or 1
        local a    = spec.alpha and (c[4] ~= nil and c[4] or 1) or nil
        -- Restore the STORED alpha on cancel, not the picker's (which is nil
        -- whenever this swatch has no opacity slider).
        local prev = { r, g, b, c[4] }
        ColorPickerFrame:SetupColorPickerAndShow(PickerInfo(r, g, b,
            function(nr, ng, nb, na)
                -- Keep the fourth component when the picker has no opacity
                -- slider. Replacing the table with a three-element one silently
                -- dropped it, so a {1,1,1,1} default became {1,1,1} on the first
                -- edit and SameValue then reported the row modified forever --
                -- inflating the footer's count with a change nobody made.
                if na == nil then
                    local cur = getFn()
                    na = cur and cur[4]
                end
                setFn({ nr, ng, nb, na })
                Sync()
                row:Sync()
            end,
            function()
                setFn(prev)
                Sync()
                row:Sync()
            end, a))
    end)

    return { sw = sw, lbl = lbl, hideBtn = hideBtn, Sync = Sync }
end

function W.Color(parent, spec)
    local g   = geo()
    local row = CreateFrame("Frame", nil, parent)
    row.binding = GUI.NewBinding(spec)
    row.spec    = spec

    local h = g.ROW_H

    local label = Text(row, 12, "textPrimary")
    -- LEFT, not TOPLEFT: a FontString's LEFT point is its vertical middle, so
    -- this lands the text on the same centre line as the swatch beside it.
    label:SetPoint("LEFT", row, "TOPLEFT", g.PAD, -(g.ROW_H / 2))
    label:SetText(spec.label or "")
    label:SetJustifyH("LEFT"); label:SetWordWrap(false)
    row.label = label

    local host = CreateFrame("Frame", nil, row)
    host:SetSize(spec.hideToggle and 114 or 62, 20)
    host:SetPoint("TOPLEFT", row, "TOPLEFT", ColumnFor(label), -math.floor((g.ROW_H - 20) / 2))

    if spec.desc then
        -- Below the control band, not hung off the label -- see Widgets.lua.
        local d = Text(row, 10, "textMuted")
        d:SetPoint("TOPLEFT", row, "TOPLEFT", g.PAD, -(g.ROW_H - 3))
        d:SetPoint("RIGHT", row, "RIGHT", -g.PAD_R, 0)
        d:SetText(spec.desc); d:SetJustifyH("LEFT"); d:SetWordWrap(false)
        h = h + g.DESC_GAP
    end

    local cell = ColorCell(row, spec, host, function() return row.binding:Get() end,
                                          function(v) row.binding:Set(v) end, nil)

    row:SetHeight(h)
    row.h = h
    row.searchText = string.lower((spec.label or "") .. " " .. (spec.desc or "") .. " colour color")

    function row:Sync() end
    function row:Refresh() cell.Sync(); self:Sync() end
    function row:IsModified() return not self.binding:IsDefault() end
    function row:ResetDefault() self.binding:Reset(); self:Refresh() end
    function row:SetEnabled(en)
        self._disabled = not en
        local c = en and T.textPrimary or T.textMuted
        self.label:SetTextColor(c[1], c[2], c[3], 1)
        cell.sw:EnableMouse(en)
        if cell.hideBtn then cell.hideBtn:SetEnabled(en) end
    end

    GUI.RegisterRefresh(row)
    cell.Sync(); row:Sync()
    return row
end

-- ============================================================
-- DualColor — two bound swatches on one row
-- ============================================================

function W.DualColor(parent, spec)
    local PAD = geo().PAD
    local row = CreateFrame("Frame", nil, parent)
    row.spec = spec

    local h = 36
    local bindA = GUI.NewBinding(spec.a)
    local bindB = GUI.NewBinding(spec.b)
    row.binding = bindA

    local hostA = CreateFrame("Frame", nil, row)
    hostA:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -1)
    hostA:SetSize(140, 34)
    local hostB = CreateFrame("Frame", nil, row)
    hostB:SetPoint("TOPLEFT", row, "TOP", 4, -1)
    hostB:SetSize(140, 34)

    local proxyA = { _disabled = false, Sync = function() end }
    local proxyB = { _disabled = false, Sync = function() end }

    local cellA = ColorCell(proxyA, spec.a, hostA,
        function() return bindA:Get() end, function(v) bindA:Set(v) end, spec.a.label)
    local cellB = ColorCell(proxyB, spec.b, hostB,
        function() return bindB:Get() end, function(v) bindB:Set(v) end, spec.b.label)

    row:SetHeight(h)
    row.h = h
    row.searchText = string.lower((spec.a.label or "") .. " " .. (spec.b.label or "") .. " colour color")

    function row:Sync() end
    function row:Refresh() cellA.Sync(); cellB.Sync() end
    function row:IsModified() return not (bindA:IsDefault() and bindB:IsDefault()) end
    function row:ResetDefault() bindA:Reset(); bindB:Reset(); self:Refresh() end
    function row:SetEnabled(en)
        self._disabled = not en
        proxyA._disabled = not en
        proxyB._disabled = not en
        local c = en and T.textSecondary or T.textMuted
        if cellA.lbl then cellA.lbl:SetTextColor(c[1], c[2], c[3], 1) end
        if cellB.lbl then cellB.lbl:SetTextColor(c[1], c[2], c[3], 1) end
        cellA.sw:EnableMouse(en)
        cellB.sw:EnableMouse(en)
        if cellA.hideBtn then cellA.hideBtn:SetEnabled(en) end
        if cellB.hideBtn then cellB.hideBtn:SetEnabled(en) end
    end

    GUI.RegisterRefresh(row)
    cellA.Sync(); cellB.Sync()
    return row
end

-- ============================================================
-- ColorSource — source dropdown plus the custom swatch, on one row
--
-- The old version returned two separate rows and two heights, and had two
-- different owners writing the swatch's enabled state: the source dropdown set
-- it from the source, and card:GrayContent set it from the master toggle. The
-- second clobbered the first, so picking "Theme accent" left the custom swatch
-- clickable. Here the swatch's state is derived in one place from both inputs.
-- ============================================================

local SOURCE_OPTS = {
    { key = "theme",  label = "Theme accent" },
    { key = "class",  label = "Class colour" },
    { key = "custom", label = "Custom" },
}

function W.ColorSource(parent, spec)
    local row = CreateFrame("Frame", nil, parent)
    row.spec = spec

    local db, srcKey, colKey = spec.db, spec.srcKey, spec.colorKey
    local defColor = spec.default or { 1, 1, 1 }
    local defSrc   = spec.defaultSource or "custom"

    local g = geo()
    local h = g.ROW_H

    -- A bare dropdown: no label line of its own, because the row already has one.
    local dd = W.Dropdown(row, {
        bare     = true,
        options  = SOURCE_OPTS,
        db       = db,
        key      = srcKey,
        default  = defSrc,
        onChange = function() if spec.onChange then spec.onChange() end end,
        onSelect = function() row:UpdateSwatchState(); row:Sync() end,
    })
    local label = Text(row, 12, "textPrimary")
    -- LEFT, not TOPLEFT: a FontString's LEFT point is its vertical middle, so
    -- this lands the text on the same centre line as the swatch beside it.
    label:SetPoint("LEFT", row, "TOPLEFT", g.PAD, -(g.ROW_H / 2))
    label:SetText(spec.label or "")
    label:SetJustifyH("LEFT"); label:SetWordWrap(false)
    row.label = label

    dd:SetWidth(118)
    dd:SetPoint("TOPLEFT", row, "TOPLEFT", ColumnFor(label), -math.floor((g.ROW_H - 20) / 2))

    local swHost = CreateFrame("Frame", nil, row)
    swHost:SetSize(62, 20)
    swHost:SetPoint("LEFT", dd, "RIGHT", 8, 0)

    if spec.desc then
        -- Below the control band, not hung off the label -- see Widgets.lua.
        local d = Text(row, 10, "textMuted")
        d:SetPoint("TOPLEFT", row, "TOPLEFT", g.PAD, -(g.ROW_H - 3))
        d:SetPoint("RIGHT", row, "RIGHT", -g.PAD_R, 0)
        d:SetText(spec.desc); d:SetJustifyH("LEFT"); d:SetWordWrap(false)
        h = h + g.DESC_GAP
    end

    local proxy = { _disabled = false, Sync = function() row:Sync() end }
    local cell = ColorCell(proxy, { alpha = spec.alpha }, swHost,
        function() return db[colKey] or defColor end,
        function(v) db[colKey] = v; if spec.onChange then spec.onChange() end end, nil)

    local function CurrentSource() return db[srcKey] or defSrc end

    row.dd   = dd
    row.cell = cell

    row:SetHeight(h)
    row.h = h
    row.searchText = string.lower((spec.label or "") .. " " .. (spec.desc or "") .. " colour color source")

    -- One place decides whether the swatch is live: it needs BOTH the row to be
    -- enabled AND the source to be "custom".
    function row:UpdateSwatchState()
        local live = (not self._disabled) and CurrentSource() == "custom"
        proxy._disabled = not live
        cell.sw:EnableMouse(live)
    end

    function row:Sync() end
    function row:Refresh()
        dd:Refresh()
        cell.Sync()
        self:UpdateSwatchState()
        self:Sync()
    end
    function row:IsModified()
        return CurrentSource() ~= defSrc
            or not GUI.SameValue(db[colKey] or defColor, defColor)
    end
    function row:ResetDefault()
        db[srcKey] = defSrc
        db[colKey] = GUI.CopyValue(defColor)
        if spec.onChange then spec.onChange() end
        self:Refresh()
    end
    function row:SetEnabled(en)
        self._disabled = not en
        local c = en and T.textPrimary or T.textMuted
        self.label:SetTextColor(c[1], c[2], c[3], 1)
        dd:SetEnabled(en)
        self:UpdateSwatchState()
    end

    GUI.RegisterRefresh(row)
    cell.Sync()
    row:UpdateSwatchState()
    row:Sync()
    return row
end
