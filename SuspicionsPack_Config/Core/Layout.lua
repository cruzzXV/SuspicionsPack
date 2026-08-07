-- SuspicionsPack Options — page and card layout
--
-- Replaces three things that were written out by hand on every page:
--
--   1. Vertical stacking. 97 copies of `y = y + card:GetTotalHeight() +
--      T.paddingSmall`, and 265 `AddRow(widget, <magic number>)` calls whose
--      numbers disagreed with the widgets' own heights. Rows now report `row.h`
--      and the card stacks them.
--   2. Separators. 202 explicit AddSeparator() calls. A hairline is drawn
--      between consecutive rows automatically; nobody has to remember.
--   3. Enable cascades. 28 hand-written GrayContent blocks plus childRows /
--      childCards bookkeeping tables, which disagreed with each other often
--      enough to produce real bugs -- DeathAlert's master toggle re-enabled the
--      TTS rows its own sub-state had just disabled, and MicroMenuSkin had a
--      master toggle with 13 sub-settings and no cascade at all.
--
-- Usage:
--
--   local page = GUI.NewPage(parent, db, Apply)
--   local c    = page:Card("Repair warning", "Shown when durability drops.")
--   local m    = c:Toggle{ key = "enabled", label = "Enable repair warning" }
--   page:GateAll(m)
--   c:Slider{ key = "threshold", label = "Warning threshold", min = 1, max = 100 }
--   page:Finish()

local ADDON, ns = ...

local SP  = SuspicionsPack
local GUI = ns.GUI
local W   = GUI.W
local T   = GUI.T

local Paint, Text, Tex = GUI.Paint, GUI.Text, GUI.Tex

-- Density. The first pass shipped these at 6/6/3/26/8 and the result was
-- suffocating: text ran into the card edges and the cards ran into each other.
-- Settings panes are read, not scanned, so they can afford whitespace.
local CARD_GAP   = 10   -- between cards
local CARD_PAD   = 10   -- inside a card, above the first row and below the last
local ROW_GAP    = 5    -- between a separator and the rows either side
local HEADER_H   = 32
local SIDE       = 12   -- card content inset from the card's own edges

-- ============================================================
-- Card
-- ============================================================

local Card = {}
Card.__index = Card

local function NewCard(page, title, desc)
    local card = setmetatable({}, Card)
    card.page  = page
    card.rows  = {}
    card.seps  = {}

    local f = CreateFrame("Frame", nil, page.parent, "BackdropTemplate")
    f:SetPoint("LEFT",  page.parent, "LEFT",  0, 0)
    f:SetPoint("RIGHT", page.parent, "RIGHT", 0, 0)
    GUI.Backdrop(f, "bgLight", 1, "border", 1, "rr6")
    card.frame = f

    local top = 0
    if title and title ~= "" then
        -- A quiet uppercase group label, not a large accent heading with a
        -- stripe. The card title names a GROUP of settings; the page's own name
        -- lives in the page header above. Shouting both competed for attention
        -- and made every card look like the start of a new page.
        local ts = Text(f, 10, "textMuted")
        ts:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -11)
        ts:SetText(string.upper(title))
        card.title = ts

        -- A hairline under the header, or the label and the first setting read
        -- as one undifferentiated block.
        local rule = Tex(f, "ARTWORK", "border", 1)
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -HEADER_H)
        rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEADER_H)

        top = HEADER_H
    end

    if desc and desc ~= "" then
        local d = Text(f, 10, "textMuted")
        d:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE, -(top + 8))
        d:SetPoint("RIGHT", f, "RIGHT", -SIDE, 0)
        d:SetJustifyH("LEFT")
        d:SetWordWrap(true)
        d:SetText(desc)
        card.desc = d
        card.descH = 0   -- measured on first layout, once the card has a width
    end

    card.top = top

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",  f, "TOPLEFT",  SIDE, -top)
    content:SetPoint("TOPRIGHT", f, "TOPRIGHT", -SIDE, -top)
    content:SetHeight(1)
    card.content = content

    -- The mouse blocker. Widgets all disable properly now, but a page can drop a
    -- raw frame in through Custom(), and there is no way to make that obey a
    -- cascade. An invisible pane over the content means a gated-off card cannot
    -- be interacted with no matter what is inside it.
    local glass = CreateFrame("Frame", nil, f)
    glass:SetAllPoints(content)
    glass:SetFrameLevel(f:GetFrameLevel() + 20)
    glass:EnableMouse(true)
    glass:Hide()
    card.glass = glass

    page.cards[#page.cards + 1] = card
    return card
end

-- Attaches a row the card owns: stacked, separated, gated, searched.
function Card:Add(row)
    row:SetParent(self.content)
    row:ClearAllPoints()
    row._card = self
    self.rows[#self.rows + 1] = row
    self.page.allRows[#self.page.allRows + 1] = row

    if self._gateBelow then
        self.page:Gate(self._gateBelow, row)
    end
    self.page._dirty = true
    return row
end

-- Positions every row and returns the card's total height.
function Card:Layout()
    local y = CARD_PAD

    -- A description only knows its wrapped height once it has a width, which it
    -- does not have until the card is anchored. Re-measure on every layout.
    -- DESC_TOP is the gap above the description, DESC_BOT the gap below it.
    -- They must agree with where NewCard anchored the FontString, or the first
    -- row lands on top of the text.
    local DESC_TOP, DESC_BOT = 8, 10
    if self.desc then
        local w = self.frame:GetWidth()
        if w and w > 0 then
            local dh = math.ceil(self.desc:GetStringHeight())
            if dh ~= self.descH then
                self.descH = dh
                local off = self.top + DESC_TOP + dh + DESC_BOT
                self.content:ClearAllPoints()
                self.content:SetPoint("TOPLEFT",  self.frame, "TOPLEFT",  SIDE, -off)
                self.content:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -SIDE, -off)
            end
        end
    end

    local sepN = 0
    for i, row in ipairs(self.rows) do
        if row._hidden then
            row:Hide()
        else
            row:Show()
            if i > 1 and not self._noSeps then
                sepN = sepN + 1
                local s = self.seps[sepN]
                if not s then
                    s = Tex(self.content, "ARTWORK", "border", 0.5)
                    s:SetHeight(1)
                    self.seps[sepN] = s
                end
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT",  self.content, "TOPLEFT",  0, -(y + ROW_GAP - 1))
                s:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -(y + ROW_GAP - 1))
                s:Show()
                y = y + ROW_GAP * 2
            end
            row:SetPoint("TOPLEFT",  self.content, "TOPLEFT",  0, -y)
            row:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -y)
            -- Set the height, do not merely read it. The standard widgets size
            -- themselves, but a frame handed to Card:Custom only ever had `h`
            -- written as a field -- so the card reserved the right space while
            -- the frame itself stayed 0 px tall and its contents collapsed
            -- against the top edge. That hit every custom row in the addon: the
            -- Home banner, the cursor preview, both texture pickers, the Auto
            -- buy grid, the theme swatches and the spec matrix.
            local h = row.h or 24
            if row:GetHeight() ~= h then row:SetHeight(h) end
            y = y + h
        end
    end
    for i = sepN + 1, #self.seps do self.seps[i]:Hide() end

    y = y + CARD_PAD
    self.content:SetHeight(math.max(1, y))

    -- Must mirror the content offset computed above, or the card's box stops
    -- short of its own last row.
    local descBlock = self.desc and (DESC_TOP + (self.descH or 0) + DESC_BOT) or 0
    local total = self.top + descBlock + y
    self.frame:SetHeight(total)
    return total
end

function Card:SetGlass(on)
    if on then self.glass:Show() else self.glass:Hide() end
end

-- A row that re-measured itself (a wrapped label that finally has a width) asks
-- its card to re-stack. Every card below this one has to move too, so it is the
-- page that does the work -- but the row only knows its card, and W.Label calls
-- `self._card:Restack()`. Without this method that call is a nil index, and any
-- page carrying a Note whose wrapped height differs from its first guess throws
-- inside an OnSizeChanged handler.
function Card:Restack()
    return self.page:Restack()
end

-- Rows added after this call follow `row`'s state, within this card only.
function Card:GateBelow(row)
    self._gateBelow = row
    return row
end

function Card:EndGate()
    self._gateBelow = nil
end

-- ------------------------------------------------------------
-- Widget shorthands
--
-- `db` defaults to the page's db and `onChange` to the page's apply function, so
-- a typical row is one line with no plumbing.
-- ------------------------------------------------------------

-- Fills in the three things almost every spec would otherwise repeat: the DB
-- table, the apply callback, and the default value.
--
-- The default is looked up in SP.DEFAULTS rather than written out at the call
-- site. Restating 400 defaults in the options UI would guarantee they drift out
-- of step with the ones the modules actually use, and a wrong default here is
-- not cosmetic -- it drives the modified dot and what "reset" writes back.
local function Fill(card, spec)
    spec.db       = spec.db or card.page.db
    spec.onChange = spec.onChange or card.page.apply
    if spec.default == nil and spec.key then
        local src = card.defaults or card.page.defaults
        if src then spec.default = src[spec.key] end
    end
    return spec
end

function Card:Toggle(spec)       return self:Add(W.Toggle(self.content, Fill(self, spec)))       end
function Card:Slider(spec)       return self:Add(W.Slider(self.content, Fill(self, spec)))       end
function Card:Dropdown(spec)     return self:Add(W.Dropdown(self.content, Fill(self, spec)))     end
function Card:FontDropdown(spec) return self:Add(W.FontDropdown(self.content, Fill(self, spec))) end
function Card:EditBox(spec)      return self:Add(W.EditBox(self.content, Fill(self, spec)))      end
function Card:Color(spec)        return self:Add(W.Color(self.content, Fill(self, spec)))        end
function Card:ButtonRow(spec)    return self:Add(W.ButtonRow(self.content, spec))                end
function Card:Note(text, spec)
    spec = spec or {}
    spec.text = text
    return self:Add(W.Label(self.content, spec))
end

function Card:DualColor(spec)
    Fill(self, spec.a)
    Fill(self, spec.b)
    return self:Add(W.DualColor(self.content, spec))
end

-- ColorSource straddles two keys, so it cannot go through Fill directly.
function Card:ColorSource(spec)
    spec.db       = spec.db or self.page.db
    spec.onChange = spec.onChange or self.page.apply
    local src = self.defaults or self.page.defaults
    if src then
        if spec.default       == nil then spec.default       = src[spec.colorKey] end
        if spec.defaultSource == nil then spec.defaultSource = src[spec.srcKey]   end
    end
    return self:Add(W.ColorSource(self.content, spec))
end

-- Same for the anchor row's four keys.
function Card:AnchorRow(spec)
    spec = spec or {}
    spec.db       = spec.db or self.page.db
    spec.onChange = spec.onChange or self.page.apply
    local src = self.defaults or self.page.defaults
    if src then
        if spec.defaultFrom   == nil then spec.defaultFrom   = src[spec.fromKey   or "anchorFrom"]  end
        if spec.defaultTo     == nil then spec.defaultTo     = src[spec.toKey     or "anchorTo"]    end
        if spec.defaultFrame  == nil then spec.defaultFrame  = src[spec.frameKey  or "anchorFrame"] end
        if spec.defaultStrata == nil then spec.defaultStrata = src[spec.strataKey or "frameStrata"] end
    end
    return self:Add(W.AnchorRow(self.content, spec))
end

-- Escape hatch for anything bespoke: a preview canvas, a generated grid, a
-- click-to-copy macro row. The frame is stacked and gated like any other row;
-- it just has to declare its own height.
function Card:Custom(frame, height)
    -- GetHeight() returns 0 for a frame nobody has sized, and 0 is TRUTHY, so
    -- the `or 24` this replaces could never fire: a Custom row with no explicit
    -- height became a zero-pixel strip inside correctly-reserved space.
    local h = height or frame:GetHeight()
    if not h or h <= 0 then h = 24 end
    frame.h = h

    -- Its own mouse blocker, because EnableMouse does not cascade to children.
    --
    -- The card's glass only appears once EVERY row in the card is off, and a
    -- card holding the sub-master that gated this row always has that toggle
    -- enabled -- so the glass never covered the case it was written for. A
    -- Custom row is precisely where child buttons live (the AutoBuy grid, the
    -- cursor texture pickers, the macro rows), so it carries its own.
    local block = CreateFrame("Frame", nil, frame)
    block:SetAllPoints(frame)
    block:SetFrameLevel(frame:GetFrameLevel() + 10)
    block:EnableMouse(true)
    block:Hide()

    -- rawget, not a plain truth test.
    --
    -- `frame.SetEnabled` is truthy for any Button, EditBox or Slider, because WoW
    -- puts it on the widget metatable. A plain `if not frame.SetEnabled` therefore
    -- skipped the wrapper for exactly those frames, so a custom Button row was
    -- never dimmed and never got `_disabled` -- it just kept working while the
    -- rest of the page was greyed out. rawget sees only what the page itself
    -- assigned, which is the question we actually mean to ask.
    local ownEnable = rawget(frame, "SetEnabled")
    local nativeEnable = (not ownEnable) and frame.SetEnabled or nil
    -- Alpha is the last resort: a raw frame exposes nothing to recolour. But
    -- 0.4 let the card show straight through and read as a rendering fault, so
    -- this is a dim, not a fade. Widgets that CAN recolour do that instead.
    function frame:SetEnabled(en)
        self._disabled = not en
        self:SetAlpha(en and 1 or 0.72)
        if en then block:Hide() else block:Show() end
        if ownEnable then ownEnable(self, en)
        elseif nativeEnable then nativeEnable(self, en) end
    end

    if not rawget(frame, "Refresh")      then function frame:Refresh() end end
    if not rawget(frame, "IsModified")   then function frame:IsModified() return false end end
    if not rawget(frame, "ResetDefault") then function frame:ResetDefault() end end
    if not rawget(frame, "Sync")         then function frame:Sync() end end
    frame.searchText = frame.searchText or ""
    return self:Add(frame)
end

-- Two controls sharing one line. Replaces CreateHRow, whose width maths
-- subtracted the gap from every cell including the last, leaving a strip of
-- dead space on the right of every pair.
--
--   c:Pair({ kind = "slider",   key = "fontSize", label = "Font size", min = 8, max = 60 },
--          { kind = "dropdown", key = "outline",  label = "Outline", options = OUTLINES },
--          0.55)
local KINDS = {
    toggle       = "Toggle",
    slider       = "Slider",
    dropdown     = "Dropdown",
    fontdropdown = "FontDropdown",
    editbox      = "EditBox",
    color        = "Color",
}

-- Two settings on one line. Kept only as a compatibility shim: with one-line
-- rows there is no vertical space to save, and splitting the row meant each half
-- measured its own label column, so the right-hand control ended up floating in
-- the middle of the card with nothing beside it. Both specs become normal rows.
function Card:Pair(specA, specB)
    self:Add(W[KINDS[specA.kind or "slider"] or "Slider"](self.content, Fill(self, specA)))
    return self:Add(W[KINDS[specB.kind or "slider"] or "Slider"](self.content, Fill(self, specB)))
end


-- ============================================================
-- Page
-- ============================================================

local Page = {}
Page.__index = Page

-- `dbKey` names the module's section in the profile. It is used to find the
-- matching defaults in SP.DEFAULTS, so no page has to restate them.
-- The block above the cards: the page's own name, a one-line explanation, and
-- (for a module page) its master switch on the right. Keeping the master switch
-- out of the first card is what lets the cards be plain groups of settings.
function Page:Header(title, desc, toggleSpec)
    local f = CreateFrame("Frame", nil, self.parent)
    f:SetPoint("LEFT",  self.parent, "LEFT",  0, 0)
    f:SetPoint("RIGHT", self.parent, "RIGHT", 0, 0)

    local ts = Text(f, 15, "textPrimary")
    ts:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    ts:SetText(title or "")
    -- A FontString anchored on both sides centres by default, which is why the
    -- page title floated in the middle of its own header.
    ts:SetJustifyH("LEFT")
    ts:SetWordWrap(false)

    local h = 26
    local master
    if toggleSpec then
        -- No "Enabled" caption: the switch is self-explanatory, and the page
        -- title sitting beside it already says what is being enabled.
        toggleSpec.label = ""
        master = W.Toggle(f, toggleSpec)
        master:ClearAllPoints()
        master:SetWidth(50)
        self.allRows[#self.allRows + 1] = master
        f._master = master
        ts:SetPoint("RIGHT", f, "RIGHT", -66, 0)
    end

    if desc and desc ~= "" then
        local d = Text(f, 11, "textMuted")
        d:SetPoint("TOPLEFT", ts, "BOTTOMLEFT", 0, -3)
        d:SetPoint("RIGHT", f, "RIGHT", toggleSpec and -70 or -4, 0)
        d:SetJustifyH("LEFT")
        d:SetWordWrap(true)
        d:SetText(desc)
        f.desc = d
        h = h + 16
    end

    f:SetHeight(h)
    f.h = h
    self.header = f
    return f, master
end

function GUI.NewPage(parent, db, apply, dbKey)
    local page = setmetatable({
        parent  = parent,
        db      = db,
        apply   = apply,
        cards   = {},
        allRows = {},
        gates   = {},
    }, Page)
    if dbKey and SP.DEFAULTS and SP.DEFAULTS.profile then
        page.defaults = SP.DEFAULTS.profile[dbKey]
    end
    parent._page = page
    return page
end

-- `defaults` overrides the page's default source for this card, for settings
-- that live in a nested table (combatTimer.backdrop and friends).
function Page:Card(title, desc, defaults)
    local card = NewCard(self, title, desc)
    card.defaults = defaults
    return card
end

-- Registers `target` as following `master`. Both are rows; `master` must have
-- GetValue (a toggle).
function Page:Gate(master, target)
    local g = self.gates[master]
    if not g then
        g = {}
        self.gates[master] = g
        self.gateOrder = self.gateOrder or {}
        self.gateOrder[#self.gateOrder + 1] = master
        -- Re-evaluate the whole page whenever this master flips, so a row under
        -- two gates gets the AND of both rather than whichever fired last.
        local prev = master.spec and master.spec.onToggle
        if master.spec then
            master.spec.onToggle = function(v)
                if prev then prev(v) end
                self:ApplyGates()
            end
        end
    end
    -- A master is never its own child. GateAll still has to come through here to
    -- get the hook installed, though: the early `if master == target then return`
    -- this replaces skipped the registration entirely, so the page master greyed
    -- everything out at build time and no click ever un-greyed it again.
    if master ~= target then g[#g + 1] = target end
end

-- Everything on the page follows `master`, including rows added later.
function Page:GateAll(master)
    self._gateAll = master
    self:Gate(master, master)   -- registers the master and its onToggle hook
    return master
end

function Page:ApplyGates()
    local state = {}
    for _, row in ipairs(self.allRows) do state[row] = true end

    if self._gateAll then
        local on = self._gateAll:GetValue() and true or false
        for _, row in ipairs(self.allRows) do
            if row ~= self._gateAll then state[row] = on end
        end
    end

    -- A FIXED POINT, not a single pass.
    --
    -- A sub-master reads state[master], which is only right if that master's own
    -- gate has already been resolved -- and gateOrder is REGISTRATION order, not
    -- dependency order. One pass therefore made a nested gate's outcome depend
    -- on which toggle the page happened to declare first. Bounded by the number
    -- of gates, since each sweep settles at least one more level, and it stops
    -- the moment nothing moves.
    local order = self.gateOrder or {}
    for _ = 1, #order do
        local changed = false
        for _, master in ipairs(order) do
            if master ~= self._gateAll then
                -- A sub-master that is itself gated off gates its children off.
                local on = (master:GetValue() and true or false) and (state[master] ~= false)
                for _, target in ipairs(self.gates[master] or {}) do
                    if target ~= master and state[target] ~= false and state[target] ~= on then
                        state[target] = on
                        changed = true
                    end
                end
            end
        end
        if not changed then break end
    end

    for _, row in ipairs(self.allRows) do
        if row.SetEnabled then
            -- A row can opt out. One-shot actions that were usable with the
            -- module switched off -- TankMD's copy-a-macro rows, Performance's
            -- two cleanup buttons -- must not be swept up by GateAll, and
            -- without this flag ApplyGates re-enabled every hand-disabled row on
            -- each Page:Refresh, which fires on every return to a cached page.
            row:SetEnabled(row._manualEnable and true or state[row])
        end
    end

    -- A card whose every row is off gets the mouse blocker.
    for _, card in ipairs(self.cards) do
        local anyOn = false
        for _, row in ipairs(card.rows) do
            if state[row] or row._manualEnable then anyOn = true; break end
        end
        card:SetGlass(#card.rows > 0 and not anyOn)
    end
end

-- Re-stacks every card and resizes the page container. Cheap enough to call
-- whenever content changes shape (a wrapped label re-measured, a card grew a row).
function Page:Restack()
    local y = 0

    if self.header then
        self.header:ClearAllPoints()
        self.header:SetPoint("TOPLEFT",  self.parent, "TOPLEFT",  2, 0)
        self.header:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", -2, 0)
        -- Re-measure the blurb: a long one wraps to two lines and would
        -- otherwise run underneath the first card.
        if self.header.desc and (self.parent:GetWidth() or 0) > 0 then
            local dh = math.ceil(self.header.desc:GetStringHeight())
            local want = 26 + dh + 3
            if math.abs(want - self.header.h) > 1 then
                self.header.h = want
                self.header:SetHeight(want)
            end
        end
        if self.header._master then
            self.header._master:ClearAllPoints()
            self.header._master:SetPoint("RIGHT", self.header, "RIGHT", 8, 0)
        end
        y = self.header.h + CARD_GAP + 4
    end

    for _, card in ipairs(self.cards) do
        -- A card with no rows, no description and no title has nothing to show.
        -- Moving the master switch into the page header left several pages with
        -- exactly that.
        local empty = #card.rows == 0 and not card.desc
        if card._hidden or empty then
            card.frame:Hide()
        else
            card.frame:Show()
            card.frame:ClearAllPoints()
            card.frame:SetPoint("TOPLEFT",  self.parent, "TOPLEFT",  0, -y)
            card.frame:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", 0, -y)
            y = y + card:Layout() + CARD_GAP
        end
    end
    self.parent:SetHeight(math.max(1, y))
    self._dirty = false
    return y
end

function Page:Finish()
    self:Restack()
    self:ApplyGates()
    -- A card's description and any wrapped label only know their height once the
    -- page has a real width, which happens one frame after the builder returns.
    -- One deferred re-stack settles it without a permanent OnUpdate.
    local page = self
    C_Timer.After(0, function()
        if page.parent and page.parent.GetWidth then page:Restack() end
    end)
    return self
end

function Page:Refresh()
    for _, row in ipairs(self.allRows) do
        if row.Refresh then row:Refresh() end
    end
    self:ApplyGates()
end

function Page:ModifiedCount()
    local n = 0
    for _, row in ipairs(self.allRows) do
        if row.IsModified and row:IsModified() then n = n + 1 end
    end
    return n
end

function Page:ResetAll()
    for _, row in ipairs(self.allRows) do
        if row.ResetDefault then row:ResetDefault() end
    end
    if self.apply then self.apply() end
    self:Refresh()
end

-- Every searchable string on the page, for the sidebar's global search.
function Page:SearchText()
    local parts = {}
    for _, row in ipairs(self.allRows) do
        if row.searchText and row.searchText ~= "" then
            parts[#parts + 1] = row.searchText
        end
    end
    return table.concat(parts, " ")
end
