-- SuspicionsPack Options — Auto buy
--
-- The only CHARACTER-scoped page in the pack: the item list differs from alt to
-- alt, so everything here lives in SP.GetCharDB().autoBuy. GUI.ModulePage reads
-- SP.GetDB()[dbKey] -- the shared profile -- so this page builds its own head,
-- and RegisterPage carries `charDB = true` so the sidebar dot reads the same
-- table the module does.
--
-- WHAT THE OLD PAGE (562 lines) GOT WRONG
--
--   * MakeItemRow:SetEnabled was `self:SetAlpha(en and 1 or 0.4)` and nothing
--     else. Every checkbox, both number boxes and the quality toggle stayed
--     fully clickable behind the grey, so a switched-off AutoBuy could still be
--     reconfigured -- and the greyed-out state was a lie. SetEnabled now
--     forwards to every child.
--   * Opening the page WROTE TO SAVEDVARIABLES. Old 8129-8134 back-filled
--     `entry.quality` and `entry.buyQty` and stored the entry for all 25
--     presets, so merely looking at the page created 25 per-character records.
--     Everything is read through with a fallback now; nothing is written until
--     the user changes something.
--   * A complete remove-button path (old 7889-7918) that nothing could ever
--     reach: buildCol passed nil for onRemove at every call site. There are no
--     user-added items, only presets, and a preset row cannot be removed. Gone.
--   * Every colour was baked at build time. Pages are cached for the session
--     now, so a baked colour is permanently stale the moment the user picks a
--     different preset. Everything colour-bearing here has a painter.
--   * It resolved its own Expressway path instead of using the shared helper.
--
-- WHY THE GRID IS ONE Custom() ROW
--
-- The old page bypassed AddRow and drew a two-column category grid straight
-- into card2.content, computing the column heights itself and then poking
-- card2.currentY and card2:_UpdateHeight(). Those internals are gone. A card
-- stacks its rows full-width, one per line, so a two-column layout cannot be
-- expressed as a sequence of rows: the whole grid is a single Custom() frame
-- that lays its own columns out and reports its own height. The item rows
-- inside it still satisfy the full row contract (h = ITEM_ROW_H, SetEnabled,
-- Refresh, IsModified, ResetDefault, Sync) and the grid forwards all of it.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

-- ============================================================
-- Geometry
-- ============================================================

local ITEM_ROW_H = 42   -- the height every item row reports
local ICON_SIZE  = 34
local CTRL       = 22   -- checkbox / number box / quality button edge
local BOX_W      = 32
local CAP_GAP    = 2    -- caption baseline to the control below it
local CTRL_DROP  = -6   -- controls sit below centre to leave room for captions
local COL_GAP    = 12   -- between the two category columns
local ROW_GAP    = 4    -- between item rows inside a column
local PAIR_GAP   = 8    -- between one pair of categories and the next
local CAT_LBL_H  = 20

-- Item-quality gold. Deliberately NOT a theme colour and deliberately not a
-- painter: it advertises the crafted quality tier of the item, exactly like the
-- preset swatches on the Themes page advertise their own palette. Repainting it
-- in the active accent would make the two tier buttons indistinguishable.
local GOLD    = { 0.95, 0.80, 0.25 }
local GOLD_BG = { 0.14, 0.11, 0.03 }

local CAT_ORDER = { "flask", "healthpotion", "combatpotion", "food", "oil", "rune" }
local CAT_LABELS = {
    flask        = "Flasks",
    healthpotion = "Health and mana potions",
    combatpotion = "Combat potions",
    food         = "Food and feasts",
    oil          = "Weapon oils",
    rune         = "Augment runes",
}

local ATLASES = {
    [1] = "Professions-Chaticon-Quality-Tier1",
    [2] = "Professions-Chaticon-Quality-Tier5",
}

-- ============================================================
-- Per-item settings
--
-- SP.DEFAULTS.char.autoBuy.items describes all 25 presets, keyed by the preset's
-- own (Q1) item ID -- the same key the module and this page index by. AceDB
-- materialises it into the character profile, so it is what `db.items[id]`
-- actually holds on a fresh character and therefore the ONLY answer that leaves
-- IsModified false on an untouched profile. Deriving the default from the preset
-- instead made all 25 rows report a phantom change and made "Reset page" write
-- 25 records that disagreed with the shipped values.
--
-- The fallback below is only reached for a preset SP.DEFAULTS does not list. It
-- restates the module's own: Modules/AutoBuy/AutoBuy.lua reads
-- `entry.quantity or item.buy` and `entry.buyQty or item.buy`, and ResolveItemID
-- treats the Q2 variant as the one to buy whenever a preset has one.
--
-- SHIPPING quantity = 0 IS DELIBERATE. [confirmed 2026-08-07]
-- The module treats a threshold of 0 as "never buy", so no preset buys anything
-- until the user sets one. That is the intent: the 25 presets are a menu, not a
-- shopping list, and an addon that starts spending your gold on login because
-- you enabled it once is not a feature. Do not "fix" this by copying preset.buy
-- into SP.DEFAULTS -- it would arm all 25 rows for every existing user on their
-- next login.
-- ============================================================

local ITEM_FIELDS = { "enabled", "quantity", "buyQty", "quality" }

local DEFAULT_ITEMS = SP.DEFAULTS and SP.DEFAULTS.char and SP.DEFAULTS.char.autoBuy
                      and SP.DEFAULTS.char.autoBuy.items or {}

local function DefaultFor(preset, field)
    local shipped = DEFAULT_ITEMS[preset.id]
    -- Explicit nil test: `enabled = false` and `quantity = 0` are both shipped
    -- values and both fall straight through an `or`.
    if shipped and shipped[field] ~= nil then return shipped[field] end
    if field == "enabled" then return false end
    if field == "quality" then return preset.q2 and 2 or 1 end
    return preset.buy or 0          -- quantity and buyQty
end

-- Read-through. Never materialises an entry, so opening the page leaves
-- SavedVariables exactly as it found them.
local function ReadItem(db, preset, field)
    local entry = db.items and db.items[preset.id]
    local v = entry and entry[field]
    -- Explicit nil test: 0 and false are both legitimate stored values and
    -- would fall straight through an `or`.
    if v == nil then return DefaultFor(preset, field) end
    return v
end

-- The only writer. Materialises the entry -- fully populated, so the module
-- never sees a half-built record -- on the first user edit and not before.
local function WriteItem(db, preset, field, value)
    db.items = db.items or {}
    local entry = db.items[preset.id]
    if not entry then
        entry = {}
        for _, f in ipairs(ITEM_FIELDS) do entry[f] = DefaultFor(preset, f) end
        db.items[preset.id] = entry
    end
    entry[field] = value
end

-- ============================================================
-- Checkbox — 22x22, accent-filled when ticked
-- ============================================================

local function MakeCheckbox(parentFrame, Get, Set)
    local btn = CreateFrame("Button", nil, parentFrame)
    btn:SetSize(CTRL, CTRL)
    -- Rounded: SetBackdrop cannot draw a corner radius.
    GUI.Backdrop(btn, "bgMedium", 1, "border", 1, "rr4")

    -- Blizzard's own tick art: the bundled UI font carries no check glyph.
    local check = btn:CreateTexture(nil, "OVERLAY")
    check:SetPoint("TOPLEFT",     btn, "TOPLEFT",      2, -2)
    check:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2,  2)
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")

    -- Both the painter and the state handler. Colours come from `t`, never from
    -- a captured upvalue, so a preset change repaints it in place.
    local function Redraw(f, t)
        local on  = Get() and true or false
        local hot = f._hover and not f._disabled
        if on then
            local k = hot and 0.6 or 0.4
            f._spBG:SetVertexColor(t.accent[1] * k, t.accent[2] * k, t.accent[3] * k, 1)
            f._spBorder:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], 1)
            check:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], 1)
            check:Show()
        else
            local bg = hot and t.bgHover or t.bgDark
            local br = hot and t.accent  or t.border
            f._spBG:SetVertexColor(bg[1], bg[2], bg[3], 1)
            f._spBorder:SetVertexColor(br[1], br[2], br[3], 1)
            check:Hide()
        end
    end
    GUI.Paint(btn, Redraw)

    btn:SetScript("OnEnter", function(f) f._hover = true;  Redraw(f, GUI.T) end)
    btn:SetScript("OnLeave", function(f) f._hover = false; Redraw(f, GUI.T) end)
    btn:SetScript("OnClick", function(f)
        if f._disabled then return end
        Set(not Get())
        Redraw(f, GUI.T)
    end)

    -- Overrides Button:SetEnabled the same way W.Button does: a _disabled flag
    -- the scripts respect plus EnableMouse, so the row really is dead to input.
    function btn:SetEnabled(en)
        self._disabled = not en
        self:EnableMouse(en)
        if not en then self._hover = false end
        Redraw(self, GUI.T)
    end
    function btn:Refresh() Redraw(self, GUI.T) end
    return btn
end

-- ============================================================
-- Item icon — 34x34, resolved asynchronously
-- ============================================================

-- `watch` is the page's set of icons that still have no texture. The old page
-- registered GET_ITEM_INFO_RECEIVED per unresolved icon and only unregistered
-- on success, so an ID the client cannot resolve -- a removed item, an ID from
-- a future build -- left a live listener behind for the rest of the session,
-- 25 of them per page visit in the worst case. Arm/Sleep let the page disarm
-- the whole set on hide and try again on the next show, by which time the
-- earlier RequestLoadItemDataByID has usually landed.
local function MakeItemIcon(parentFrame, itemID, watch, onResolved)
    local border = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
    border:SetSize(ICON_SIZE, ICON_SIZE)
    GUI.Backdrop(border, "bgDark", 1, "border", 0.8)

    local tex = border:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT",     border, "TOPLEFT",      2, -2)
    tex:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -2,  2)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local function TrySet()
        local icon = select(10, GetItemInfo(itemID))
        if not icon then return false end
        tex:SetTexture(icon)
        return true
    end

    -- Drops the event registration but stays in `watch`, so the next show can
    -- pick the icon back up.
    function border:Sleep()
        self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        self:SetScript("OnEvent", nil)
    end

    function border:Arm()
        if TrySet() then
            self:Sleep()
            watch[self] = nil
            if onResolved then onResolved() end
            return
        end
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        if C_Item and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
        watch[self] = true
        self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        self:SetScript("OnEvent", function(f, _, id)
            if id ~= itemID then return end
            if TrySet() then
                f:Sleep()
                watch[f] = nil
                if onResolved then onResolved() end
            end
        end)
    end
    border:Arm()

    border:EnableMouse(true)
    border:SetScript("OnEnter", function(f)
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(itemID)
        GameTooltip:Show()
    end)
    border:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return border
end

-- ============================================================
-- Numeric box
-- ============================================================

local function MakeNumBox(parentFrame, width, minV, maxV, Get, Set)
    local box = CreateFrame("EditBox", nil, parentFrame, "BackdropTemplate")
    box:SetSize(width, CTRL)
    box:SetAutoFocus(false)
    box:SetNumeric(true)
    box:SetMaxLetters(4)
    box:SetTextInsets(4, 4, 0, 0)
    box:SetJustifyH("CENTER")
    GUI.ApplyFont(box, 11)
    GUI.Backdrop(box, "bgDark", 1, "border", 1)
    GUI.Paint(box, function(f, t)
        f:SetTextColor(t.textPrimary[1], t.textPrimary[2], t.textPrimary[3], 1)
    end)

    local function Display() box:SetText(tostring(Get())) end

    local function Commit()
        local v = tonumber(box:GetText())
        if v == nil then v = Get() end
        v = math.floor(v)
        if v < minV then v = minV elseif v > maxV then v = maxV end
        Set(v)
        box:SetText(tostring(v))
    end

    box:SetScript("OnEnterPressed",    function(f) Commit(); f:ClearFocus() end)
    box:SetScript("OnEscapePressed",   function(f) Display(); f:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(f) GUI.FocusBorder(f, true) end)
    box:SetScript("OnEditFocusLost",   function(f) GUI.FocusBorder(f, false); Commit() end)
    -- The border animation is driven off SP.Tick and would keep running against
    -- a hidden frame otherwise.
    box:SetScript("OnHide",            function(f) GUI.FocusCancel(f) end)

    function box:Refresh()
        if self:HasFocus() then return end   -- never yank text out from under a typist
        Display()
    end
    Display()
    return box
end

-- ============================================================
-- Quality toggle — two tier buttons, the active one raised
-- ============================================================

local function MakeQualityToggle(parentFrame, preset, Get, Set)
    if not preset.q2 then return nil end
    local ids = { [1] = preset.id, [2] = preset.q2 }

    local container = CreateFrame("Frame", nil, parentFrame)
    container:SetSize(CTRL * 2 + 2, CTRL)

    local function Redraw(f, t)
        local active = Get()
        for q = 1, 2 do
            local btn = f["btn" .. q]
            local hot = (not f._disabled) and f._hover == q
            if q == active then
                btn:SetFrameLevel(f:GetFrameLevel() + 3)
                btn:SetSize(CTRL, CTRL)
                btn._spBG:SetVertexColor(GOLD_BG[1], GOLD_BG[2], GOLD_BG[3], 1)
                btn._spBorder:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
                btn.icon:SetVertexColor(1, 1, 1, 1)
                btn.icon:SetAlpha(1)
                btn.icon:SetSize(18, 18)
            elseif hot then
                btn:SetFrameLevel(f:GetFrameLevel() + 2)
                btn:SetSize(CTRL, CTRL)
                btn._spBG:SetVertexColor(GOLD_BG[1], GOLD_BG[2], GOLD_BG[3], 1)
                btn._spBorder:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 0.55)
                btn.icon:SetVertexColor(1, 1, 1, 1)
                btn.icon:SetAlpha(0.8)
                btn.icon:SetSize(16, 16)
            else
                btn:SetFrameLevel(f:GetFrameLevel() + 1)
                btn:SetSize(CTRL - 2, CTRL - 2)
                btn._spBG:SetVertexColor(t.bgDark[1], t.bgDark[2], t.bgDark[3], 1)
                btn._spBorder:SetVertexColor(t.border[1], t.border[2], t.border[3], 0.35)
                btn.icon:SetVertexColor(0.5, 0.5, 0.5, 1)
                btn.icon:SetAlpha(0.45)
                btn.icon:SetSize(13, 13)
            end
        end
    end

    for q = 1, 2 do
        local btn = CreateFrame("Button", nil, container)
        btn:SetSize(CTRL, CTRL)
        -- Rounded: SetBackdrop cannot draw a corner radius.
        GUI.Backdrop(btn, "bgMedium", 1, "border", 1, "rr4")
        btn:SetPoint(q == 1 and "LEFT" or "RIGHT", container,
                     q == 1 and "LEFT" or "RIGHT", 0, 0)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        icon:SetAtlas(ATLASES[q], false)
        btn.icon = icon

        btn:SetScript("OnEnter", function(f)
            if container._disabled then return end
            container._hover = q
            Redraw(container, GUI.T)
            GameTooltip:SetOwner(f, "ANCHOR_TOP")
            GameTooltip:SetItemByID(ids[q])
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            container._hover = nil
            Redraw(container, GUI.T)
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function()
            if container._disabled then return end
            Set(q)
            Redraw(container, GUI.T)
        end)
        container["btn" .. q] = btn
    end

    -- Registered after the buttons exist: GUI.Paint runs the closure at once.
    GUI.Paint(container, Redraw)

    function container:SetEnabled(en)
        self._disabled = not en
        self.btn1:EnableMouse(en)
        self.btn2:EnableMouse(en)
        if not en then self._hover = nil end
        Redraw(self, GUI.T)
    end
    function container:Refresh() Redraw(self, GUI.T) end
    return container
end

-- ============================================================
-- Item row — [icon] [name / id] ... [quality] [buy qty] [min qty] [tick]
-- ============================================================

local function MakeItemRow(parentFrame, db, preset, watch)
    local row = CreateFrame("Frame", nil, parentFrame)
    row:SetHeight(ITEM_ROW_H)
    row.h = ITEM_ROW_H
    row._itemOn = ReadItem(db, preset, "enabled") and true or false

    -- Assigned once every child exists. The callbacks that read them only run
    -- on a click or an event, long after this function has returned.
    local RefreshName, RefreshVisual

    local iconF = MakeItemIcon(row, preset.id, watch, function()
        if RefreshName then RefreshName() end
    end)
    iconF:SetPoint("LEFT", row, "LEFT", 0, 0)

    local function Caption(anchor, text)
        local fs = GUI.Text(row, 9, "textMuted")
        fs:SetPoint("BOTTOM", anchor, "TOP", 0, CAP_GAP)
        fs:SetJustifyH("CENTER")
        fs:SetText(text)
        return fs
    end

    -- Right to left, each control anchored to the one before it.
    local cb = MakeCheckbox(row,
        function() return ReadItem(db, preset, "enabled") end,
        function(v)
            WriteItem(db, preset, "enabled", v)
            row._itemOn = v and true or false
            RefreshVisual()
        end)
    cb:SetPoint("RIGHT", row, "RIGHT", 0, CTRL_DROP)
    GUI.Tooltip(cb, "Keep stocked",
        "Buy this item automatically at a vendor, and list it in the auction house panel.")

    -- Trigger threshold. 0 disables the item as surely as unticking it: the
    -- module only buys when `have < minQty`.
    local minBox = MakeNumBox(row, BOX_W, 0, 9999,
        function() return ReadItem(db, preset, "quantity") end,
        function(v) WriteItem(db, preset, "quantity", v) end)
    minBox:SetPoint("RIGHT", cb, "LEFT", -6, 0)
    GUI.Tooltip(minBox, "Minimum quantity", "Buy only when your bags hold fewer than this.")

    -- Purchase amount. The old box clamped this to a minimum of 1, which made
    -- the module's documented `buyQty == 0` ("buy exactly the shortfall") mode
    -- unreachable and silently rewrote the shipped 0 to 1 on any focus change.
    local buyBox = MakeNumBox(row, BOX_W, 0, 9999,
        function() return ReadItem(db, preset, "buyQty") end,
        function(v) WriteItem(db, preset, "buyQty", v) end)
    buyBox:SetPoint("RIGHT", minBox, "LEFT", -6, 0)
    GUI.Tooltip(buyBox, "Buy quantity",
        "How many to buy each time. 0 buys exactly the shortfall.")

    local qual = MakeQualityToggle(row, preset,
        function() return ReadItem(db, preset, "quality") end,
        function(q)
            WriteItem(db, preset, "quality", q)
            RefreshName()
        end)
    if qual then qual:SetPoint("RIGHT", buyBox, "LEFT", -8, 0) end

    Caption(minBox, "Min qty")
    Caption(buyBox, "Buy qty")
    if qual then Caption(qual, "Quality") end

    -- Name and ID stop at whichever control is leftmost.
    local rightAnchor = qual or buyBox
    local rightOff    = qual and -8 or -10

    local nameFS = row:CreateFontString(nil, "OVERLAY")
    GUI.ApplyFont(nameFS, 12)
    nameFS:SetPoint("LEFT",  iconF,       "RIGHT", 8, 5)
    nameFS:SetPoint("RIGHT", rightAnchor, "LEFT",  rightOff, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    -- State-aware painter rather than GUI.Text: the colour depends on whether
    -- this particular item is ticked, and still has to follow the preset.
    local function PaintName(f, t)
        local c = row._itemOn and t.textPrimary or t.textMuted
        f:SetTextColor(c[1], c[2], c[3], row._itemOn and 1 or 0.55)
    end
    GUI.Paint(nameFS, PaintName)

    local idFS = GUI.Text(row, 9, "textMuted")
    idFS:SetPoint("LEFT",  iconF,       "RIGHT", 8, -8)
    idFS:SetPoint("RIGHT", rightAnchor, "LEFT",  rightOff, 0)
    idFS:SetJustifyH("LEFT")
    idFS:SetWordWrap(false)

    -- A fixed hover zone over the two text lines. Both font strings carry LEFT
    -- and RIGHT anchors, so their rect spans the whole row; anchoring a button
    -- to their edges would inherit that and swallow the controls.
    local nameHover = CreateFrame("Button", nil, row)
    nameHover:SetPoint("TOPLEFT", nameFS, "TOPLEFT", -2, 4)
    nameHover:SetSize(170, 26)
    nameHover:SetScript("OnEnter", function(f)
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(preset.id)
        GameTooltip:Show()
    end)
    nameHover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    RefreshName = function()
        -- Prefer the live, localised name; the preset's own is an English
        -- fallback for an item the client has not cached yet.
        nameFS:SetText(GetItemInfo(preset.id) or preset.name or ("Item " .. preset.id))
        local q = ReadItem(db, preset, "quality")
        if preset.q2 then
            idFS:SetText(("ID %d  (Q%d)"):format(q == 2 and preset.q2 or preset.id, q))
        else
            idFS:SetText("ID " .. preset.id)
        end
    end

    RefreshVisual = function()
        local on = row._itemOn
        iconF:SetAlpha(on and 1 or 0.3)
        idFS:SetAlpha(on and 0.85 or 0.3)
        if qual then qual:SetAlpha(on and 1 or 0.35) end
        PaintName(nameFS, GUI.T)
    end

    -- ── the row contract ────────────────────────────────────────────
    -- The old SetEnabled was alpha-only. Every control below stayed live.
    function row:SetEnabled(en)
        self._disabled = not en
        self:SetAlpha(en and 1 or 0.72)
        cb:SetEnabled(en)
        minBox:SetEnabled(en)
        buyBox:SetEnabled(en)
        if not en then
            minBox:ClearFocus()
            buyBox:ClearFocus()
        end
        if qual then qual:SetEnabled(en) end
        iconF:EnableMouse(en)
        nameHover:EnableMouse(en)
    end

    function row:Refresh()
        self._itemOn = ReadItem(db, preset, "enabled") and true or false
        cb:Refresh()
        minBox:Refresh()
        buyBox:Refresh()
        if qual then qual:Refresh() end
        RefreshName()
        RefreshVisual()
    end

    function row:IsModified()
        for _, field in ipairs(ITEM_FIELDS) do
            if ReadItem(db, preset, field) ~= DefaultFor(preset, field) then return true end
        end
        return false
    end

    function row:ResetDefault()
        -- Guarded so a page-wide reset does not materialise 25 records for
        -- items the user never touched.
        if not self:IsModified() then return end
        for _, field in ipairs(ITEM_FIELDS) do
            WriteItem(db, preset, field, DefaultFor(preset, field))
        end
        self:Refresh()
    end

    function row:Sync() end

    -- Exposed like Pair's a/b and SpecRow's cells, so a test can assert that
    -- these are the things being disabled rather than just the row dimming.
    row.icon, row.check, row.minBox, row.buyBox, row.quality =
        iconF, cb, minBox, buyBox, qual

    row.searchText = string.lower((preset.name or "") .. " " .. preset.id)

    RefreshName()
    RefreshVisual()
    return row
end

-- ============================================================
-- The category grid — one Custom() row for the whole thing
-- ============================================================

local function BuildGrid(parent, db, presets, watch)
    local byCat = {}
    for _, cat in ipairs(CAT_ORDER) do byCat[cat] = {} end
    for _, p in ipairs(presets) do
        local bucket = byCat[p.cat]
        if bucket then bucket[#bucket + 1] = p end
    end

    local active = {}
    for _, cat in ipairs(CAT_ORDER) do
        if #byCat[cat] > 0 then active[#active + 1] = cat end
    end
    if #active == 0 then return nil, 0 end

    local grid   = CreateFrame("Frame", nil, parent)
    local rows   = {}
    local titles = {}
    local words  = {}

    local function ColHeight(cat)
        return CAT_LBL_H + ROW_GAP + #byCat[cat] * (ITEM_ROW_H + ROW_GAP)
    end

    local function FillColumn(col, cat)
        local label = CAT_LABELS[cat] or cat
        local title = GUI.Text(col, 11, "accent")
        GUI.ApplyFont(title, 11, "OUTLINE")
        title:SetPoint("TOPLEFT", col, "TOPLEFT", 4, -3)
        title:SetText(label)
        titles[#titles + 1] = title
        words[#words + 1]   = string.lower(label)

        local y = CAT_LBL_H + ROW_GAP
        for _, p in ipairs(byCat[cat]) do
            local r = MakeItemRow(col, db, p, watch)
            r:SetPoint("TOPLEFT",  col, "TOPLEFT",  0, -y)
            r:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, -y)
            y = y + ITEM_ROW_H + ROW_GAP
            rows[#rows + 1]  = r
            words[#words + 1] = r.searchText
        end
    end

    -- Categories in pairs, left column | right column, stacked as bands. Each
    -- band is its own frame of the pair's height so the columns can anchor a
    -- side to the band's CENTER without needing a width of their own -- the
    -- same trick the Themes grid uses. Anchoring to the grid's CENTER instead
    -- would over-constrain every column but the first.
    local total = 0
    local i = 1
    while i <= #active do
        local catL  = active[i]
        local catR  = active[i + 1]         -- nil when the count is odd
        local pairH = math.max(ColHeight(catL), catR and ColHeight(catR) or 0)

        local band = CreateFrame("Frame", nil, grid)
        band:SetHeight(pairH)
        band:SetPoint("TOPLEFT",  grid, "TOPLEFT",  0, -total)
        band:SetPoint("TOPRIGHT", grid, "TOPRIGHT", 0, -total)

        local colL = CreateFrame("Frame", nil, band)
        colL:SetHeight(pairH)
        colL:SetPoint("TOPLEFT", band, "TOPLEFT", 0, 0)
        colL:SetPoint("RIGHT",   band, "CENTER",  -COL_GAP / 2, 0)
        FillColumn(colL, catL)

        if catR then
            local colR = CreateFrame("Frame", nil, band)
            colR:SetHeight(pairH)
            colR:SetPoint("TOPRIGHT", band, "TOPRIGHT", 0, 0)
            colR:SetPoint("LEFT",     band, "CENTER",   COL_GAP / 2, 0)
            FillColumn(colR, catR)
        end

        total = total + pairH
        i = i + 2
        if i <= #active then total = total + PAIR_GAP end
    end

    grid:SetHeight(total)
    grid.rows       = rows
    grid.searchText = table.concat(words, " ")

    -- The full row contract, forwarded to every item row. The category titles
    -- are the grid's own regions rather than any row's, so they have to be
    -- dimmed here or a gated-off grid greys 25 rows and leaves six headings
    -- burning at full brightness above them.
    function grid:SetEnabled(en)
        for _, r in ipairs(rows)   do r:SetEnabled(en) end
        for _, t in ipairs(titles) do t:SetAlpha(en and 1 or 0.72) end
    end
    function grid:Refresh()      for _, r in ipairs(rows) do r:Refresh() end end
    function grid:ResetDefault() for _, r in ipairs(rows) do r:ResetDefault() end end
    function grid:Sync()         for _, r in ipairs(rows) do r:Sync() end end
    function grid:IsModified()
        for _, r in ipairs(rows) do
            if r:IsModified() then return true end
        end
        return false
    end

    return grid, total
end

-- ============================================================

GUI.RegisterPage{
    id       = "autobuy",
    name     = "Auto buy",
    category = "items",
    dbKey    = "autoBuy",
    charDB   = true,   -- settings live in SP.GetCharDB(), not the shared profile
    keywords = "auto buy vendor merchant auction house consumable restock stock " ..
               "flask potion food feast rune oil augment quality reagent quantity " ..
               "shopping list per character",
    build = function(parent)
        -- `or {}` rather than creating the section: a page that has to write to
        -- SavedVariables before it can draw itself is the bug this migration is
        -- removing. AceDB supplies the section from SP.DEFAULTS.char in
        -- practice; the fallback only keeps the page from throwing if it does not.
        local db = SP.GetCharDB().autoBuy or {}

        local apply = GUI.Applier("AutoBuy")
        local page  = GUI.NewPage(parent, db, apply)

        -- GUI.NewPage's dbKey lookup reads SP.DEFAULTS.profile, which has no
        -- autoBuy section, so the default source is named explicitly here.
        local charDefaults = SP.DEFAULTS and SP.DEFAULTS.char and SP.DEFAULTS.char.autoBuy

        -- The header is built by hand, the way GroupInvitations does it, because
        -- GUI.ModulePage reads SP.GetDB()[dbKey] -- the shared profile -- and
        -- this module lives in SP.GetCharDB(). It is still the page header that
        -- carries the master switch, like every other module page: leaving it in
        -- the first card made this the only page where the switch was somewhere
        -- else.
        local _, master = page:Header("Auto buy",
            "Keeps your consumables topped up. At a vendor the purchase is silent " ..
            "and instant. At the auction house a panel lists what is missing, with " ..
            "a buy button and a price confirmation for each item. Everything on " ..
            "this page is stored per character.", {
                key      = "enabled",
                db       = db,
                default  = charDefaults and charDefaults.enabled,
                onChange = apply,
                onToggle = function(v) GUI.UpdateDots(); GUI.Toast("Auto buy", v) end,
            })
        page:GateAll(master)

        local c2 = page:Card("Preset items",
            "Tick an item to keep it stocked, then set how low your bags may run " ..
            "before a purchase and how many to buy when they do. Items that come " ..
            "in two crafted qualities carry a tier picker.")

        -- Icons still waiting on GET_ITEM_INFO_RECEIVED. Owned by the page so
        -- they can all be disarmed when it goes away.
        local watch = {}

        local grid, height = BuildGrid(parent, db,
            (SP.AutoBuy and SP.AutoBuy.PresetItems) or {}, watch)

        if grid then
            c2:Custom(grid, height)
        else
            c2:Note("The AutoBuy module has not published a preset item list.")
        end

        -- The event listeners are the only thing here that outlives the page.
        parent:HookScript("OnHide", function()
            for f in pairs(watch) do f:Sleep() end
        end)
        parent:HookScript("OnShow", function()
            -- Arm() clears its own entry from `watch` the moment the item data
            -- has arrived, which removing a key during traversal permits.
            for f in pairs(watch) do f:Arm() end
        end)

        page:Finish()
    end,
}
