-- SuspicionsPack Options — anchor widgets
--
-- Two things the old version got wrong, both fixed here:
--
-- 1. Disabling did nothing. `CreateAnchorRow:SetEnabled` called
--    `fromSel:EnableMouse(en)` on the CONTAINER frame. EnableMouse is per-frame
--    in WoW and does not cascade, so all nine child buttons stayed live: a
--    greyed-out anchor grid was fully clickable and still wrote to the DB.
--
-- 2. The key names were hardcoded to anchorFrom / anchorTo / anchorFrame /
--    frameStrata. Two pages needed different names, and solved it two different
--    ways -- BloodlustAlert copied the entire 170-line widget, MovementAlert
--    wrapped its DB in a setmetatable proxy that remapped the keys. Here the
--    names are just fields on the spec.

local ADDON, ns = ...

local SP  = SuspicionsPack
local GUI = ns.GUI
local W   = GUI.W
local T   = GUI.T

local Paint, Text, ApplyFont = GUI.Paint, GUI.Text, GUI.ApplyFont
local Backdrop, FocusBorder  = GUI.Backdrop, GUI.FocusBorder

local PAD = 10

local ANCHOR_GRID = {
    { "TOPLEFT",    "TOP",    "TOPRIGHT"    },
    { "LEFT",       "CENTER", "RIGHT"       },
    { "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
}
local CELL, CELL_PAD = 26, 3
local GRID_SIZE = CELL * 3 + CELL_PAD * 2

-- ============================================================
-- 3x3 anchor selector
-- ============================================================

function W.AnchorGrid(parent, initial, onChange)
    local grid = CreateFrame("Frame", nil, parent)
    grid:SetSize(GRID_SIZE, GRID_SIZE)
    grid.buttons = {}

    local selected = initial or "CENTER"

    local function Repaint()
        for _, b in ipairs(grid.buttons) do
            local sel = b.anchor == selected
            if grid._disabled then
                -- Disabled state is a colour, not an alpha: fading the grid let
                -- the card show through the cells and read as a render fault.
                local bg = sel and T.bgHover or T.bgDark
                b._spBG:SetVertexColor(bg[1], bg[2], bg[3], 1)
                b._spBorder:SetVertexColor(T.border[1], T.border[2], T.border[3], 1)
            elseif sel then
                b._spBG:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.75)
                b._spBorder:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
            else
                b._spBG:SetVertexColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
                b._spBorder:SetVertexColor(T.border[1], T.border[2], T.border[3], 1)
            end
        end
    end

    for r = 1, 3 do
        for c = 1, 3 do
            local b = CreateFrame("Button", nil, grid)
            b:SetSize(CELL, CELL)
            b:SetPoint("TOPLEFT", grid, "TOPLEFT",
                (c - 1) * (CELL + CELL_PAD), -((r - 1) * (CELL + CELL_PAD)))
            Backdrop(b, "bgMedium", 1, "border", 1, "rr4")
            b.anchor = ANCHOR_GRID[r][c]
            b:SetScript("OnEnter", function(s)
                if grid._disabled then return end
                if s.anchor ~= selected then
                    s._spBorder:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
                end
            end)
            b:SetScript("OnLeave", function() Repaint() end)
            b:SetScript("OnClick", function(s)
                if grid._disabled then return end
                selected = s.anchor
                Repaint()
                if onChange then onChange(selected) end
            end)
            grid.buttons[#grid.buttons + 1] = b
        end
    end

    -- Registered as a painter so the grid follows a preset change without the
    -- window being torn down.
    GUI.PaintLater(grid, Repaint)
    Repaint()

    function grid:GetValue() return selected end
    function grid:SetValue(v) selected = v or "CENTER"; Repaint() end
    function grid:SetEnabled(en)
        -- Every button individually. EnableMouse on `grid` alone was the bug.
        self._disabled = not en
        for _, b in ipairs(self.buttons) do b:EnableMouse(en) end
        Repaint()
    end
    return grid
end

-- ============================================================
-- Frame picker overlay
--
-- A screen-wide, mouse-transparent overlay that highlights whatever frame is
-- under the cursor and reports its name. Logic ported as-is -- it works and the
-- comments explain why each piece is the way it is -- with the colours moved
-- onto the paint registry. Previously this singleton survived GUI:Rebuild, so
-- after a theme switch it kept the OLD accent colour for the rest of the session.
-- ============================================================

local _picker

local BLACKLIST = { "SP_", "NRSKNUIFrameChooser" }
local function IsBlacklisted(name)
    if not name then return false end
    for _, pat in ipairs(BLACKLIST) do
        if name:sub(1, #pat) == pat then return true end
    end
    return false
end

-- Walks up from the raw mouse focus to the nearest named, non-blacklisted
-- ancestor. Anchoring to that instead of the raw focus stops the highlight
-- twitching as the cursor crosses unnamed child regions of one logical frame.
local function ResolveFrame(f)
    if not f then return UIParent, "UIParent" end
    local cur = f
    while cur do
        local name = cur.GetName and cur:GetName() or nil
        if name and name ~= "" and name ~= "WorldFrame" and not IsBlacklisted(name) then
            return cur, name
        end
        cur = cur.GetParent and cur:GetParent() or nil
    end
    return UIParent, "UIParent"
end

local function GetPicker()
    if _picker then return _picker end

    local picker = CreateFrame("Frame", "SP_AnchorPickerOverlay", UIParent)
    picker:SetFrameStrata("TOOLTIP")
    picker:SetAllPoints(UIParent)
    -- Pass-through: with EnableMouse(false) the real frames keep receiving the
    -- mouse, so GetMouseFocus reports what the user is actually pointing at.
    -- Clicks are detected by polling IsMouseButtonDown instead.
    picker:EnableMouse(false)
    picker:Hide()

    local hl = CreateFrame("Frame", nil, picker, "BackdropTemplate")
    hl:SetFrameStrata("TOOLTIP")
    hl:SetBackdrop({ edgeFile = SP.BLANK, edgeSize = 2 })
    Paint(hl, function(f, t) f:SetBackdropBorderColor(t.accent[1], t.accent[2], t.accent[3], 1) end)
    hl:Hide()

    local bar = CreateFrame("Frame", nil, picker)
    bar:SetSize(500, 40)
    bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 60)
    Backdrop(bar, "bgDark", 0.95, "accent", 1, "rr6")

    local lbl = Text(bar, 11, "textPrimary")
    lbl:SetPoint("CENTER", bar, "CENTER", 0, 0)
    lbl:SetText("|cffFFFFFF Left-click|r any frame to anchor to it   " ..
                "|cffFFFFFF Right-click|r to cancel")

    local cb, curName, waitRelease

    local function Stop()
        -- Deliberately NOT clearing OnUpdate: a hidden frame does not fire it,
        -- so Hide() pauses the poll on its own, and clearing would break
        -- re-activation.
        picker:Hide(); hl:Hide()
        curName = nil; waitRelease = false
    end

    picker:SetScript("OnUpdate", function()
        if not cb then picker:Hide(); return end

        -- Swallow the click that opened the picker, or we confirm instantly on
        -- the "select frame" button itself.
        if waitRelease then
            if IsMouseButtonDown("LeftButton") then return end
            waitRelease = false
        end

        if IsMouseButtonDown("RightButton") then cb = nil; Stop(); return end

        local raw = GetMouseFocus and GetMouseFocus() or nil
        if not raw and GetMouseFoci then
            local foci = GetMouseFoci()
            raw = foci and foci[1] or nil
        end
        local f, name = ResolveFrame(raw)
        curName = name

        -- Absolute screen coordinates against UIParent's static origin. A
        -- cross-frame SetPoint to the hovered frame makes WoW's layout engine
        -- re-solve every tick, which shows up as visible jitter.
        local l, b, w, h = f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight()
        if l and b and w and h then
            hl:ClearAllPoints()
            hl:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l - 2, b - 2)
            hl:SetSize(w + 4, h + 4)
            hl:Show()
        else
            hl:Hide()
        end

        if IsMouseButtonDown("LeftButton") and curName then
            local fn, n = cb, curName
            cb = nil
            Stop()
            if fn then fn(n) end
        end
    end)

    function picker:Activate(callback)
        cb          = callback
        curName     = nil
        waitRelease = true
        self:Show()
    end

    function picker:Cancel()
        cb = nil
        Stop()
    end

    _picker = picker
    return picker
end

-- Cancels any in-flight pick. Called from the options window's OnHide, so the
-- overlay can never be left running over the game with no way back to it.
function GUI.CancelFramePick()
    if _picker and _picker:IsShown() then _picker:Cancel() end
end

-- ============================================================
-- AnchorRow — the composite
--
--   [Anchor from]  [To frame's]      Frame strata [ ▾ ]
--   [ 3x3 grid  ]  [ 3x3 grid ]      Anchored to  [____] [+]
--
-- spec:
--   db          the table holding the four keys
--   fromKey     default "anchorFrom"
--   toKey       default "anchorTo"
--   frameKey    default "anchorFrame"
--   strataKey   default "frameStrata"   (omit strata = false to hide that control)
--   defaultFrom / defaultTo / defaultFrame / defaultStrata
--   onChange    called after any of the four is written
-- ============================================================

local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "TOOLTIP" }

function W.AnchorRow(parent, spec)
    local db        = spec.db
    local fromKey   = spec.fromKey   or "anchorFrom"
    local toKey     = spec.toKey     or "anchorTo"
    local frameKey  = spec.frameKey  or "anchorFrame"
    local strataKey = spec.strataKey or "frameStrata"
    local defFrom   = spec.defaultFrom   or "CENTER"
    local defTo     = spec.defaultTo     or "CENTER"
    local defFrame  = spec.defaultFrame  or "UIParent"
    local defStrata = spec.defaultStrata or "MEDIUM"
    local useStrata = spec.strata ~= false

    local function Changed() if spec.onChange then spec.onChange() end end

    local row = CreateFrame("Frame", nil, parent)
    local h   = 22 + GRID_SIZE + 10
    row:SetHeight(h)
    row.h = h
    row.searchText = "position anchor anchored to frame strata offset"
    row._captions = {}

    -- Left: the two grids, each under its own caption.
    local capFrom = Text(row, 10, "textMuted")
    capFrom:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -2)
    row._captions[#row._captions + 1] = capFrom
    capFrom:SetText("Anchor from")

    local gridFrom = W.AnchorGrid(row, db[fromKey] or defFrom, function(v)
        db[fromKey] = v; Changed(); row:Sync()
    end)
    gridFrom:SetPoint("TOPLEFT", capFrom, "BOTTOMLEFT", 0, -4)

    local capTo = Text(row, 10, "textMuted")
    capTo:SetPoint("TOPLEFT", capFrom, "TOPLEFT", GRID_SIZE + 14, 0)
    row._captions[#row._captions + 1] = capTo
    capTo:SetText("To frame's")

    local gridTo = W.AnchorGrid(row, db[toKey] or defTo, function(v)
        db[toKey] = v; Changed(); row:Sync()
    end)
    gridTo:SetPoint("TOPLEFT", capTo, "BOTTOMLEFT", 0, -4)

    -- Right: strata dropdown over the frame name box.
    local right = CreateFrame("Frame", nil, row)
    right:SetPoint("TOPLEFT", capTo, "TOPRIGHT", GRID_SIZE - 40, 0)
    right:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    right:SetHeight(h - 8)

    local strataDD
    if useStrata then
        local sCap = Text(right, 10, "textMuted")
        sCap:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -2)
        row._captions[#row._captions + 1] = sCap
    sCap:SetText("Frame strata")

        strataDD = W.Dropdown(right, {
            bare     = true,
            options  = STRATA,
            db       = db,
            key      = strataKey,
            default  = defStrata,
            onChange = Changed,
            onSelect = function() row:Sync() end,
        })
        strataDD:SetPoint("TOPLEFT", sCap, "BOTTOMLEFT", 0, -3)
        strataDD:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    end

    local fCap = Text(right, 10, "textMuted")
    fCap:SetPoint("TOPLEFT", right, "TOPLEFT", 0, useStrata and -42 or -2)
    row._captions[#row._captions + 1] = fCap
    fCap:SetText("Anchored to")

    local pick = CreateFrame("Button", nil, right, "BackdropTemplate")
    pick:SetSize(22, 20)
    pick:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, useStrata and -55 or -15)
    Backdrop(pick, "bgMedium", 1, "border", 1)
    local pIcon = pick:CreateFontString(nil, "OVERLAY")
    pIcon:SetAllPoints()
    GUI.ApplyIconFont(pIcon, 13)
    pIcon:SetText("+")
    Paint(pIcon, function(f, t) f:SetTextColor(t.accent[1], t.accent[2], t.accent[3], 1) end)
    GUI.HoverBorder(pick)
    GUI.Tooltip(pick, "Pick a frame",
        "Click, then click any frame on screen to anchor to it.")

    local fBox = CreateFrame("EditBox", nil, right, "BackdropTemplate")
    fBox:SetHeight(20)
    fBox:SetPoint("TOPLEFT", fCap, "BOTTOMLEFT", 0, -3)
    fBox:SetPoint("RIGHT", pick, "LEFT", -4, 0)
    fBox:SetAutoFocus(false)
    fBox:SetMaxLetters(80)
    fBox:SetTextInsets(6, 6, 0, 0)
    ApplyFont(fBox, 11)
    Backdrop(fBox, "bgMedium", 1, "border", 1)
    Paint(fBox, function(f, t) f:SetTextColor(t.textPrimary[1], t.textPrimary[2], t.textPrimary[3], 1) end)
    fBox:SetText(db[frameKey] or defFrame)

    local function CommitFrame(text)
        db[frameKey] = (text and text ~= "") and text or defFrame
        fBox:SetText(db[frameKey])
        Changed()
        row:Sync()
    end
    fBox:SetScript("OnEnterPressed", function(s) s:ClearFocus(); CommitFrame(s:GetText()) end)
    fBox:SetScript("OnEscapePressed", function(s) s:ClearFocus(); s:SetText(db[frameKey] or defFrame) end)
    fBox:SetScript("OnEditFocusGained", function(s) FocusBorder(s, true) end)
    fBox:SetScript("OnEditFocusLost", function(s) FocusBorder(s, false); CommitFrame(s:GetText()) end)
    fBox:SetScript("OnHide", function(s) GUI.FocusCancel(s) end)

    pick:SetScript("OnClick", function()
        if row._disabled then return end
        GetPicker():Activate(function(name) CommitFrame(name) end)
    end)

    row.dot = GUI.Tex(row, "OVERLAY", "accent")
    row.dot:SetSize(4, 4)
    row.dot:SetPoint("LEFT", row, "TOPLEFT", 2, -8)
    row.dot:Hide()

    function row:IsModified()
        return (db[fromKey]  or defFrom)   ~= defFrom
            or (db[toKey]    or defTo)     ~= defTo
            or (db[frameKey] or defFrame)  ~= defFrame
            or (useStrata and (db[strataKey] or defStrata) ~= defStrata)
    end
    function row:Sync()
        if self:IsModified() then self.dot:Show() else self.dot:Hide() end
    end
    function row:Refresh()
        gridFrom:SetValue(db[fromKey] or defFrom)
        gridTo:SetValue(db[toKey] or defTo)
        if not fBox:HasFocus() then fBox:SetText(db[frameKey] or defFrame) end
        if strataDD then strataDD:Refresh() end
        self:Sync()
    end
    function row:ResetDefault()
        db[fromKey]  = defFrom
        db[toKey]    = defTo
        db[frameKey] = defFrame
        if useStrata then db[strataKey] = defStrata end
        Changed()
        self:Refresh()
    end
    function row:SetEnabled(en)
        self._disabled = not en
        for _, fs in ipairs(row._captions or {}) do
            local c = en and T.textMuted or T.border
            fs:SetTextColor(c[1], c[2], c[3], 1)
        end
        gridFrom:SetEnabled(en)
        gridTo:SetEnabled(en)
        fBox:SetEnabled(en)
        if not en then fBox:ClearFocus() end
        pick:EnableMouse(en)
        if strataDD then strataDD:SetEnabled(en) end
    end

    -- Exposed so a test (and the shell's disabled-state audit) can assert the
    -- nine buttons are really mouse-disabled, which is the bug this widget was
    -- rewritten for.
    row._gridButtons = {}
    for _, b in ipairs(gridFrom.buttons) do row._gridButtons[#row._gridButtons + 1] = b end
    for _, b in ipairs(gridTo.buttons)   do row._gridButtons[#row._gridButtons + 1] = b end

    GUI.RegisterRefresh(row)
    row:Sync()
    return row
end
