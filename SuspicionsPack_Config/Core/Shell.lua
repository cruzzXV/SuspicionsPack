-- SuspicionsPack Options — the window shell
--
-- Window, header, sidebar, search, content area, footer, and the page registry.
--
-- WHAT CHANGED FROM THE OLD SHELL
--
--   * No Rebuild(). A theme change repaints in place. The window no longer
--     blinks shut and reopens, and nothing leaks.
--   * The sidebar's on/off dot comes from a `dbKey` field on the page
--     registration instead of a 33-branch if/elseif that had to be edited by
--     hand for every new module.
--   * Search covers every setting on every page, not just page names.
--   * UISpecialFrames is inserted into exactly once. The old code did it inside
--     BuildMainFrame, which re-ran on every theme switch, so the table grew a
--     duplicate "SP_GUIMainFrame" string forever.
--   * Window position and size persist in the profile instead of a field on the
--     GUI table that was lost on every reload.
--
-- THE LOGO IS LOAD-BEARING. It is 72x72 anchored at (-17, +18) from the
-- window's TOPLEFT, so it deliberately hangs outside the frame on two sides.
-- That works only because mainFrame never calls SetClipsChildren(true) and the
-- logo sits at header level + 50. Do not reparent it to the header, do not clip
-- the window. (Retail only: on Forever it sits inside the top band.)

local ADDON, ns = ...

local SP  = SuspicionsPack
local GUI = ns.GUI
local W   = GUI.W
local T   = GUI.T

local Paint, Text, Tex   = GUI.Paint, GUI.Text, GUI.Tex
local Backdrop, ApplyFont = GUI.Backdrop, GUI.ApplyFont

local LOGO_TEX   = "Interface\\AddOns\\SuspicionsPack\\Media\\Icons\\icon128x128.png"

-- Forever's logo (the guild's demon eye) and window chrome (Plumber's settings
-- panel) are the parent's, shared with the changelog popup: Core\Skin.lua.
local Skin        = SP.Skin
local DEMON_EYE   = Skin.DEMON_EYE
local PLUMBER     = GUI.PLUMBER
local PlumberRect = GUI.PlumberRect
local ARROW_TEX  = "Interface\\AddOns\\SuspicionsPack\\Media\\Icons\\collapse.tga"
local CLOSE_X_TEX = "Interface\\AddOns\\SuspicionsPack\\Media\\GUITextures\\close.png"
local RESIZE_TEX = "Interface\\AddOns\\SuspicionsPack\\Media\\Icons\\resize.png"

-- Forever's list art, from the game: the quest log's highlights (NeedRoll's
-- native rows) and the +/- buttons of Keep or Toss's group headers.
local QUEST_HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local QUEST_SELECTED  = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
local PLUS_TEX        = "Interface\\Buttons\\UI-PlusButton-Up"
local MINUS_TEX       = "Interface\\Buttons\\UI-MinusButton-Up"

-- Forever's on/off marker: WaypointUI's minimap pin, a bevelled white diamond
-- on a black centre, cut out of its MapPinFrame sheet (cell 1,1), and our own
-- solid diamond that fits that centre. Both white, tinted here.
local DIAMOND_TEX      = "Interface\\AddOns\\SuspicionsPack\\Media\\GUITextures\\diamond.png"
local DIAMOND_FILL_TEX = "Interface\\AddOns\\SuspicionsPack\\Media\\GUITextures\\diamond-fill.png"
-- The copper gold of Forever's frame metal, darker and warmer than the FFD100
-- of its text.
local MARKER_GOLD      = { 0.90, 0.72, 0.36 }

-- A module that is on: the dot's green on retail, the gem's on Forever.
local ON_GREEN         = { 0.29, 0.87, 0.50 }

local SECTION_H, ITEM_H = 28, 25
local SB_W = 4

-- ============================================================
-- Page registry
-- ============================================================

GUI.Categories = {}
GUI.Pages      = {}
GUI.PageOrder  = {}

function GUI.RegisterCategory(id, name)
    GUI.Categories[#GUI.Categories + 1] = { id = id, name = name, items = {} }
end

local function FindCategory(id)
    for _, c in ipairs(GUI.Categories) do
        if c.id == id then return c end
    end
end

-- spec: id, name, category, dbKey (optional), charDB (optional), keywords, build
function GUI.RegisterPage(spec)
    GUI.Pages[spec.id] = spec
    GUI.PageOrder[#GUI.PageOrder + 1] = spec.id

    local cat = FindCategory(spec.category)
    if not cat then return end

    -- Inserted in name order, not load order. The sidebar reads this list
    -- straight through, and load order is whatever the TOC happens to say --
    -- which is a build detail, not a menu. Sorted on the way in rather than on
    -- every refresh, since it only changes when a page is registered.
    --
    -- Compared lowercased: byte order puts every capital ahead of every
    -- lowercase letter, which would scatter the list on any name that is not
    -- capitalised the same way as its neighbours.
    local key = string.lower(spec.name or "")
    local at  = #cat.items + 1
    for i, other in ipairs(cat.items) do
        if key < string.lower(other.name or "") then at = i; break end
    end
    table.insert(cat.items, at, spec)
end

-- The on/off dot. Reads the module's own `enabled` flag through the dbKey the
-- page declared; `alwaysOn` pages (documentation, themes) get no dot.
local function PageIsOn(spec)
    if not spec.dbKey then return nil end
    local db = spec.charDB and SP.GetCharDB() or SP.GetDB()
    local sub = db and db[spec.dbKey]
    if type(sub) ~= "table" then return nil end
    return sub.enabled and true or false
end

-- ============================================================
-- Search
-- ============================================================

-- Matches a page against a lowercased query. A page that has been built also
-- offers every setting label and description it contains, so typing "threshold"
-- finds Repair Warning even though the word is not in the page's name.
local function PageMatches(spec, q)
    if q == "" then return true end
    if string.find(string.lower(spec.name), q, 1, true) then return true end
    if spec.keywords and string.find(string.lower(spec.keywords), q, 1, true) then return true end
    local container = GUI.PageCache and GUI.PageCache[spec.id]
    local page = container and container._page
    if page then
        if not page._searchCache then page._searchCache = page:SearchText() end
        if string.find(page._searchCache, q, 1, true) then return true end
    end
    return false
end

-- ============================================================
-- Sidebar
-- ============================================================

local sidebarPool, headerPool = {}, {}
local expanded, selectedItem = {}, nil

-- Opens a page the user picked (list, logo, search), with Forever's tab
-- sound when it is not the one already open.
local function OpenPage(id)
    if id ~= selectedItem then GUI.Sound(GUI.SOUND_PAGE) end
    GUI:SelectItem(id)
end

local function GetSectionRow(parent)
    for _, h in ipairs(headerPool) do
        if not h._inUse then h._inUse = true; h:SetParent(parent); h:Show(); return h end
    end
    local h = CreateFrame("Button", nil, parent)
    h:SetHeight(SECTION_H)

    if GUI.FOREVER then
        h.hover = h:CreateTexture(nil, "BACKGROUND")
        h.hover:SetTexture(QUEST_HIGHLIGHT)
        h.hover:SetBlendMode("ADD")
        h.hover:SetAllPoints()
        h.hover:Hide()

        h.arrow = h:CreateTexture(nil, "ARTWORK")
        h.arrow:SetSize(14, 14)
        h.arrow:SetPoint("LEFT", h, "LEFT", 8, 0)

        h.label = Text(h, 12, "accent")
        h.label:SetPoint("LEFT", h.arrow, "RIGHT", 5, 0)

        function h:SetOpen(open) self.arrow:SetTexture(open and MINUS_TEX or PLUS_TEX) end
    else
        h.hover = Tex(h, "BACKGROUND", "bgHover", 0.5)
        h.hover:SetAllPoints()
        h.hover:Hide()

        h.label = Text(h, 10, "textMuted")
        h.label:SetPoint("LEFT", h, "LEFT", 10, 0)

        h.arrow = h:CreateTexture(nil, "OVERLAY")
        h.arrow:SetSize(9, 9)
        h.arrow:SetPoint("RIGHT", h, "RIGHT", -10, 0)
        h.arrow:SetTexture(ARROW_TEX)
        Paint(h.arrow, function(f, t) f:SetVertexColor(t.textMuted[1], t.textMuted[2], t.textMuted[3], 1) end)

        function h:SetOpen(open) self.arrow:SetRotation(open and 0 or -math.pi / 2) end
    end

    h:SetScript("OnEnter", function(s) s.hover:Show() end)
    h:SetScript("OnLeave", function(s) s.hover:Hide() end)
    h:SetScript("OnClick", function(s)
        expanded[s.catId] = not expanded[s.catId]
        GUI.Sound(expanded[s.catId] and GUI.SOUND_ON or GUI.SOUND_OFF)
        GUI:RefreshSidebar()
    end)

    h._inUse = true
    headerPool[#headerPool + 1] = h
    return h
end

local function GetItemRow(parent)
    for _, i in ipairs(sidebarPool) do
        if not i._inUse then i._inUse = true; i:SetParent(parent); i:Show(); return i end
    end
    local it = CreateFrame("Button", nil, parent)
    it:SetHeight(ITEM_H)

    if GUI.FOREVER then
        -- NeedRoll's native rows: the quest log's highlight under the mouse, its
        -- selected bar tinted blue on the open page, and no accent bar.
        it.sel = it:CreateTexture(nil, "BACKGROUND")
        it.sel:SetTexture(QUEST_SELECTED)
        it.sel:SetBlendMode("ADD")
        it.sel:SetVertexColor(0.35, 0.55, 1, 1)
        it.sel:SetPoint("TOPLEFT",     it, "TOPLEFT",      2, 0)
        it.sel:SetPoint("BOTTOMRIGHT", it, "BOTTOMRIGHT", -2, 0)
        it.sel:Hide()

        it.hover = it:CreateTexture(nil, "BACKGROUND")
        it.hover:SetTexture(QUEST_HIGHLIGHT)
        it.hover:SetBlendMode("ADD")
        it.hover:SetVertexColor(1, 1, 1, 0.5)
        it.hover:SetPoint("TOPLEFT",     it, "TOPLEFT",      2, 0)
        it.hover:SetPoint("BOTTOMRIGHT", it, "BOTTOMRIGHT", -2, 0)
        it.hover:Hide()
    else
        -- The selection is a rounded pill inset from the sidebar edges, not a
        -- strip running the full width with a bar welded to the left edge.
        it.sel = GUI.RoundTex(it, "BACKGROUND", "rr4")
        it.sel:SetPoint("TOPLEFT",     it, "TOPLEFT",      6, -1)
        it.sel:SetPoint("BOTTOMRIGHT", it, "BOTTOMRIGHT", -8,  1)
        Paint(it.sel, function(f, t) f:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], 0.16) end)
        it.sel:Hide()

        it.hover = GUI.RoundTex(it, "BACKGROUND", "rr4")
        it.hover:SetPoint("TOPLEFT",     it, "TOPLEFT",      6, -1)
        it.hover:SetPoint("BOTTOMRIGHT", it, "BOTTOMRIGHT", -8,  1)
        Paint(it.hover, function(f, t) f:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], 0.08) end)
        it.hover:Hide()

        -- Flat: 3px is below the nine-slice minimum in both dimensions.
        it.bar = Tex(it, "OVERLAY", "accent")
        it.bar:SetWidth(3)
        it.bar:SetPoint("TOPLEFT",    it, "TOPLEFT",     6, -4)
        it.bar:SetPoint("BOTTOMLEFT", it, "BOTTOMLEFT",  6,  4)
        it.bar:Hide()
    end

    -- The open page's look: the fill, plus the accent bar where the skin has one.
    function it:SetSelected(on)
        self.sel:SetShown(on)
        if self.bar then self.bar:SetShown(on) end
    end

    -- The state dot. Green means the module is on, a dim grey means it is off,
    -- and hidden means the page has no on/off at all. `on` is PageIsOn's
    -- answer: true, false or nil.
    --
    -- Forever: the diamond in the copper gold of the game's frames, a green
    -- gem inside it when the module is on; off, the frame dims and the centre
    -- stays empty.
    if GUI.FOREVER then
        it.dot = CreateFrame("Frame", nil, it)
        it.dot:SetSize(16, 16)
        it.dot:SetPoint("LEFT", it, "LEFT", 10, 0)

        local frame = it.dot:CreateTexture(nil, "OVERLAY")
        frame:SetAllPoints()
        frame:SetTexture(DIAMOND_TEX)
        frame:SetVertexColor(MARKER_GOLD[1], MARKER_GOLD[2], MARKER_GOLD[3])

        local gem = it.dot:CreateTexture(nil, "OVERLAY", nil, 1)
        gem:SetAllPoints()
        gem:SetTexture(DIAMOND_FILL_TEX)
        gem:SetVertexColor(ON_GREEN[1], ON_GREEN[2], ON_GREEN[3])

        function it:SetState(on)
            self.dot:SetShown(on ~= nil)
            frame:SetAlpha(on and 1 or 0.6)
            gem:SetShown(on == true)
        end
    else
        it.dot = GUI.CircleTex(it, "OVERLAY")
        it.dot:SetSize(6, 6)
        it.dot:SetPoint("LEFT", it, "LEFT", 15, 0)

        function it:SetState(on)
            if on == nil then self.dot:Hide(); return end
            self.dot:Show()
            if on then self.dot:SetVertexColor(ON_GREEN[1], ON_GREEN[2], ON_GREEN[3], 1)
            else self.dot:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.55) end
        end
    end

    it.label = Text(it, GUI.FOREVER and 12 or 11, "textSecondary")
    it.label:SetPoint("LEFT", it, "LEFT", 28, 0)
    it.label:SetPoint("RIGHT", it, "RIGHT", -8, 0)
    it.label:SetJustifyH("LEFT")
    it.label:SetWordWrap(false)

    -- Lit under the mouse and on the open page: white on Forever (Plumber's
    -- list), the primary text colour on retail.
    it:SetScript("OnEnter", function(s)
        if s.id ~= selectedItem then
            s.hover:Show()
            local c = T.textHover or T.textPrimary
            s.label:SetTextColor(c[1], c[2], c[3], 1)
        end
    end)
    it:SetScript("OnLeave", function(s)
        s.hover:Hide()
        if s.id ~= selectedItem then
            s.label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        end
    end)
    it:SetScript("OnClick", function(s) OpenPage(s.id) end)

    it._inUse = true
    sidebarPool[#sidebarPool + 1] = it
    return it
end

function GUI:RefreshSidebar()
    local sc = self.sidebarScrollChild
    if not sc then return end

    for _, h in ipairs(headerPool) do h._inUse = false; h:Hide() end
    for _, i in ipairs(sidebarPool) do i._inUse = false; i:Hide() end

    local q = string.lower(self.searchQuery or "")
    local y, firstMatch = 4, nil

    for _, cat in ipairs(GUI.Categories) do
        local matches = {}
        for _, spec in ipairs(cat.items) do
            if PageMatches(spec, q) then matches[#matches + 1] = spec end
        end

        if #matches > 0 then
            local h = GetSectionRow(sc)
            h.catId = cat.id
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, -y)
            h:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -y)
            -- Capitals are the flat skin's group labels; Forever writes names
            -- as they are, like the game's own headers.
            h.label:SetText(GUI.FOREVER and cat.name or string.upper(cat.name))
            -- A live query force-expands everything: hiding matches behind a
            -- collapsed section makes search useless.
            local open = (q ~= "") or expanded[cat.id]
            h:SetOpen(open)
            y = y + SECTION_H

            if open then
                for _, spec in ipairs(matches) do
                    firstMatch = firstMatch or spec.id
                    local it = GetItemRow(sc)
                    it.id = spec.id
                    it:ClearAllPoints()
                    it:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, -y)
                    it:SetPoint("TOPRIGHT", sc, "TOPRIGHT", 0, -y)
                    it.label:SetText(spec.name)
                    it:SetState(PageIsOn(spec))

                    if spec.id == selectedItem then
                        it:SetSelected(true)
                        local c = T.textHover or T.textPrimary
                        it.label:SetTextColor(c[1], c[2], c[3], 1)
                    else
                        it:SetSelected(false)
                        it.label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
                    end
                    y = y + ITEM_H
                end
            end
            y = y + 2
        end
    end

    self._searchFirstMatch = firstMatch
    sc:SetHeight(y + 4)

    if self.emptyMsg then
        self.emptyMsg:SetShown(firstMatch == nil and q ~= "")
    end
end

-- Repaints only the dots, without relaying out the sidebar. A full refresh
-- while the cursor is over an item re-fires its OnEnter and leaves it stuck in
-- the hover colour.
function GUI.UpdateDots()
    for _, it in ipairs(sidebarPool) do
        if it._inUse and it.id then
            local spec = GUI.Pages[it.id]
            it:SetState(spec and PageIsOn(spec))
        end
    end
end

-- ============================================================
-- Content
-- ============================================================

function GUI:SelectItem(id)
    selectedItem = id
    if self.contentScroll then self.contentScroll:SetVerticalScroll(0) end
    self:RefreshSidebar()
    self:RefreshContent()
end

function GUI:GetSelected() return selectedItem end

function GUI:RefreshContent()
    local sc = self.contentScrollChild
    if not sc then return end
    self.PageCache = self.PageCache or {}

    -- Hide EVERY cached container, not just the previously active one:
    -- mainFrame:Show() re-shows all children of the scroll child, so a
    -- hide-only-the-last scheme breaks the moment the window is reopened.
    for _, container in pairs(self.PageCache) do container:Hide() end
    self._activePage = nil

    local spec = GUI.Pages[selectedItem]
    if self.crumb then
        self.crumb:SetText(spec and spec.name or "")
        local catName = ""
        if spec then
            for _, c in ipairs(GUI.Categories) do
                if c.id == spec.category then catName = c.name; break end
            end
        end
        self.crumbCat:SetText(catName)
        self.crumbArrow:SetText(catName ~= "" and "-" or "")
    end

    local cached = self.PageCache[selectedItem]
    if cached then
        if cached._onPageShow then cached._onPageShow() end
        -- Re-read the DB every time the page is shown. A module that changed its
        -- own settings while the page sat in the cache used to leave the
        -- controls showing stale values.
        if cached._page then cached._page:Refresh() end
        cached:Show()
        sc:SetHeight(cached:GetHeight())
        self._activePage = cached
    elseif spec and spec.build then
        local container = CreateFrame("Frame", nil, sc)
        container:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, 0)
        container:SetPoint("RIGHT",   sc, "RIGHT",   0, 0)
        container:SetHeight(1)

        -- THE SCROLL RANGE HAS TO FOLLOW THE PAGE.
        --
        -- Page:Restack resizes the container; the scrollable range comes from
        -- the scroll CHILD, which was only ever set here, before any deferred
        -- relayout. So both re-stacks that happen after this point -- the one
        -- Page:Finish queues a frame later, and the one a wrapped label fires
        -- when it finally measures itself -- grew the page without growing the
        -- range, and the bottom rows could not be scrolled to. It corrected
        -- itself if you left the page and came back, which is exactly why it
        -- survived testing.
        container:SetScript("OnSizeChanged", function(f)
            if GUI._activePage == f then
                sc:SetHeight(math.max(1, f:GetHeight() or 1))
            end
        end)

        -- CACHE BEFORE BUILDING, and build under pcall.
        --
        -- The container is created shown. If a builder throws, every line after
        -- the call is skipped -- including the one that registers the container
        -- -- so the hide-all loop above can never find it and it stays visible
        -- over every page opened afterwards, with a fresh copy piling up on each
        -- revisit. That is the "pages superposees" bug in lessons.md
        -- [2026-03-29]. Registering first makes the symptom impossible whatever
        -- the cause: a broken page is merely blank instead of poisoning the
        -- whole window.
        self.PageCache[selectedItem] = container
        self._activePage = container

        local ok, err = pcall(spec.build, container)
        if not ok then geterrorhandler()(err) end

        sc:SetHeight(container:GetHeight())
    end

    self:UpdateFooter()
end

-- Throws a page's cached container away and builds it again.
--
-- THE HIDE IS THE WHOLE POINT, and it is why this is an API instead of three
-- lines a page writes itself. RefreshContent hides every container it can find
-- in PageCache; one removed from the cache while still on screen is one nothing
-- will ever hide again, and it stays painted over every page opened afterwards.
-- That is the "pages superposees" regression in lessons.md [2026-03-29], and it
-- came straight back the first time a page did this by hand.
--
-- For pages whose SHAPE depends on data -- a list you can add rows to -- where
-- Refresh only re-reads values into rows that already exist.
function GUI:RebuildPage(id)
    self.PageCache = self.PageCache or {}
    local old = self.PageCache[id]
    if old then
        old:Hide()
        self.PageCache[id] = nil
        if self._activePage == old then self._activePage = nil end
    end
    self:SelectItem(id)
end

function GUI:UpdateFooter()
    if not self.modLabel then return end
    local container = self.PageCache and self.PageCache[selectedItem]
    local page = container and container._page
    local n = page and page:ModifiedCount() or 0
    if n == 0 then
        self.modLabel:SetText("")
        self.resetBtn:Hide()
    else
        self.modLabel:SetText(n == 1 and "1 setting changed" or (n .. " settings changed"))
        self.resetBtn:Show()
    end
end

-- ============================================================
-- Window
-- ============================================================

local mainFrame

local function SavedWindow()
    local db = SP.GetDB()
    db.settings = db.settings or {}
    db.settings.window = db.settings.window or {}
    return db.settings.window
end

-- Hoisted to Theme.lua so the dropdown popup can use the same one: Widgets.lua
-- loads before this file, and two scrolling implementations is how they drift.
local SmoothScroll = GUI.SmoothScroll

-- What typing in either search box does. Escape and the clear button empty the
-- box; Enter opens the first page that matched.
local function OnSearchText(txt)
    GUI.searchQuery = txt
    GUI:RefreshSidebar()
end

local function OpenFirstMatch()
    if GUI._searchFirstMatch then OpenPage(GUI._searchFirstMatch) end
end

-- The flat skin's search box: a rounded field with its own magnifier, hint
-- and clear cross.
local function BuildFlatSearch(sidebar)
    local searchWrap = CreateFrame("Frame", nil, sidebar, "BackdropTemplate")
    searchWrap:SetHeight(22)
    searchWrap:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 8, -8)
    searchWrap:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -9, -8)
    Backdrop(searchWrap, "bgDark", 1, "border", 1)

    local mag = searchWrap:CreateTexture(nil, "ARTWORK")
    mag:SetSize(11, 11)
    mag:SetPoint("LEFT", searchWrap, "LEFT", 6, 0)
    mag:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    Paint(mag, function(f, t) f:SetVertexColor(t.textMuted[1], t.textMuted[2], t.textMuted[3], 1) end)

    local search = CreateFrame("EditBox", nil, searchWrap)
    search:EnableMouse(true)
    search:SetPoint("LEFT", searchWrap, "LEFT", 21, 0)
    search:SetPoint("RIGHT", searchWrap, "RIGHT", -18, 0)
    search:SetHeight(20)
    search:SetAutoFocus(false)
    ApplyFont(search, 11)
    Paint(search, function(f, t) f:SetTextColor(t.textPrimary[1], t.textPrimary[2], t.textPrimary[3], 1) end)

    local placeholder = Text(searchWrap, 11, "textMuted")
    placeholder:SetPoint("LEFT", searchWrap, "LEFT", 21, 0)
    placeholder:SetText("Search settings")

    local clear = CreateFrame("Button", nil, searchWrap)
    clear:SetSize(14, 14)
    clear:SetPoint("RIGHT", searchWrap, "RIGHT", -4, 0)
    local clearTex = clear:CreateTexture(nil, "ARTWORK")
    clearTex:SetAllPoints()
    clearTex:SetTexture(CLOSE_X_TEX)
    Paint(clearTex, function(f, t) f:SetVertexColor(t.textMuted[1], t.textMuted[2], t.textMuted[3], 1) end)
    clear:Hide()
    clear:SetScript("OnClick", function() search:SetText(""); search:ClearFocus() end)

    -- The hint goes as soon as the box has the caret, not only once something
    -- is typed, and comes back when it is left empty.
    local function ShowHint(s)
        placeholder:SetShown((s:GetText() or "") == "" and not s:HasFocus())
    end
    search:SetScript("OnTextChanged", function(s)
        local txt = s:GetText() or ""
        ShowHint(s)
        clear:SetShown(txt ~= "")
        OnSearchText(txt)
    end)
    search:SetScript("OnEnterPressed", function(s)
        OpenFirstMatch()
        s:ClearFocus()
    end)
    search:SetScript("OnEscapePressed", function(s) s:SetText(""); s:ClearFocus() end)
    -- The border lives on the WRAPPER, but the EditBox and the clear button sit
    -- on top of it and swallow the mouse, so the wrapper's own OnEnter only fires
    -- over the few pixels of padding around them. Every child that covers it has
    -- to report hover as well.
    --
    -- `focused` keeps leaving the box from dimming the border while the caret is
    -- still in it -- otherwise moving the mouse away mid-typing turns the
    -- highlight off.
    local focused = false
    local function Light(on)
        GUI.FocusBorder(searchWrap, on or focused)
    end
    for _, f in ipairs({ searchWrap, search, clear }) do
        f:HookScript("OnEnter", function() Light(true)  end)
        f:HookScript("OnLeave", function() Light(false) end)
    end

    search:SetScript("OnEditFocusGained", function(s) focused = true;  Light(true);  ShowHint(s) end)
    search:SetScript("OnEditFocusLost",   function(s) focused = false; Light(false); ShowHint(s) end)
    return search, searchWrap
end

-- Forever: the game's SearchBoxTemplate, magnifier, grey hint and clear button
-- included (NeedRoll's native search). Its own scripts keep the hint and the
-- clear button right, so ours are hooked on after them, never set over them.
-- Under it, Plumber's divider, as under its own search row; the list hangs
-- from that.
local function BuildForeverSearch(sidebar)
    local search = CreateFrame("EditBox", nil, sidebar, "SearchBoxTemplate")
    search:SetHeight(20)
    -- The template's left edge art sits 5 outside the box.
    search:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 5, -2)
    search:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, -2)
    search.Instructions:SetText("Search settings")

    -- The template shows its hint whenever the box is empty, caret or not.
    -- Hooked after it: the hint goes as soon as the box has the caret, and
    -- comes back when it is left empty.
    local function ShowHint(s)
        s.Instructions:SetShown((s:GetText() or "") == "" and not s:HasFocus())
    end
    search:HookScript("OnTextChanged", function(s)
        ShowHint(s)
        OnSearchText(s:GetText() or "")
    end)
    search:HookScript("OnEditFocusGained", ShowHint)
    search:HookScript("OnEditFocusLost", ShowHint)
    -- The template's Enter and Escape only drop the focus.
    search:HookScript("OnEnterPressed", OpenFirstMatch)
    search:HookScript("OnEscapePressed", function(s) s:SetText("") end)

    -- As wide as the column, edge art included.
    local divider = Skin.PlumberDivider(sidebar)
    divider:SetHeight(24)
    divider:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -9, -2)
    divider:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", 4, -2)
    return search, divider
end

-- ============================================================
-- Forever chrome: Plumber's settings panel
-- ============================================================

-- The leather background, the leather side panel, the bronze frame and its
-- close button, all on `frame`. `sideW` is where the side panel's bronze edge
-- is centred.
local function BuildPlumberChrome(frame, sideW)
    -- Background, frame and close button, as round the changelog popup. The
    -- background starts under the side panel's last 8. The window's OnHide
    -- plays the close sound.
    Skin.PlumberFrame(frame, sideW - 8, function() GUI.Hide() end)

    -- The side panel, Plumber's six pieces: a dark column and a 40 wide bronze
    -- edge centred on its right border, each in three rows, the middle row
    -- stretching. The edge's shadow falls on the background.
    local function Piece(x1, x2, y1, y2)
        return PlumberRect(frame:CreateTexture(nil, "BORDER"), PLUMBER.SHEET, x1, x2, y1, y2)
    end
    local edgeTop = Piece(280, 360, 176, 240)
    edgeTop:SetSize(40, 32)
    edgeTop:SetPoint("TOP", frame, "TOPLEFT", sideW, 0)
    local edgeBottom = Piece(280, 360, 832, 896)
    edgeBottom:SetSize(40, 32)
    edgeBottom:SetPoint("BOTTOM", frame, "BOTTOMLEFT", sideW, 0)
    local edgeMid = Piece(280, 360, 240, 832)
    edgeMid:SetPoint("TOPLEFT", edgeTop, "BOTTOMLEFT")
    edgeMid:SetPoint("BOTTOMRIGHT", edgeBottom, "TOPRIGHT")
    local colTop = Piece(0, 280, 176, 240)
    colTop:SetPoint("TOPLEFT", frame, "TOPLEFT")
    colTop:SetPoint("BOTTOMRIGHT", edgeTop, "BOTTOMLEFT")
    local colBottom = Piece(0, 280, 832, 896)
    colBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT")
    colBottom:SetPoint("TOPRIGHT", edgeBottom, "TOPLEFT")
    local colMid = Piece(0, 280, 240, 832)
    colMid:SetPoint("TOPLEFT", colTop, "BOTTOMLEFT")
    colMid:SetPoint("BOTTOMRIGHT", colBottom, "TOPRIGHT")
end

-- Plumber's Modules / Release notes tabs: a leather box hanging under the
-- window, its text cream, white under the mouse, nudged while pressed. 40
-- high, 7 apart; at least 100 wide, else the text and 18 each side.
local TAB_H, TAB_GAP = 40, 7

local function BuildPlumberTab(frame, text, onClick)
    local tab = CreateFrame("Button", nil, frame)
    tab:SetHeight(TAB_H)

    -- Three slices, the end caps 24 x 48 centred on the tab's edges.
    local function Slice(x1, x2)
        return PlumberRect(tab:CreateTexture(nil, "BACKGROUND"), PLUMBER.SHEET, x1, x2, 176, 272)
    end
    local left = Slice(392, 440)
    left:SetSize(24, 48)
    left:SetPoint("CENTER", tab, "LEFT", 0, -1)
    local right = Slice(552, 600)
    right:SetSize(24, 48)
    right:SetPoint("CENTER", tab, "RIGHT", 0, -1)
    local middle = Slice(440, 552)
    middle:SetPoint("TOPLEFT", left, "TOPRIGHT")
    middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")

    local label = Text(tab, 12, "textSecondary")
    label:SetPoint("CENTER", tab, "CENTER", 0, 0)
    label:SetText(text)
    tab:SetWidth(math.max(18 * 2 + math.ceil(label:GetStringWidth() or 0), 2.5 * TAB_H))

    local function Tint(key)
        local c = T[key]
        label:SetTextColor(c[1], c[2], c[3], 1)
    end
    tab:SetScript("OnEnter", function() Tint("textHover") end)
    tab:SetScript("OnLeave", function() Tint("textSecondary") end)
    tab:SetScript("OnMouseDown", function() label:SetPoint("CENTER", tab, "CENTER", 1, -1) end)
    tab:SetScript("OnMouseUp", function() label:SetPoint("CENTER", tab, "CENTER", 0, 0) end)
    tab:SetScript("OnClick", function()
        GUI.Sound(GUI.SOUND_PAGE)
        onClick()
    end)
    return tab
end

function GUI:BuildMainFrame()
    if mainFrame then return end

    local saved = SavedWindow()

    -- Forever: a bare frame dressed in Plumber's settings panel below.
    if GUI.FOREVER then
        mainFrame = CreateFrame("Frame", "SP_GUIMainFrame", UIParent)
    else
        mainFrame = CreateFrame("Frame", "SP_GUIMainFrame", UIParent, "BackdropTemplate")
    end
    self.mainFrame = mainFrame
    mainFrame:SetSize(saved.w or T.winW, saved.h or T.winH)
    if saved.point then
        mainFrame:SetPoint(saved.point, UIParent, saved.rel or saved.point, saved.x or 0, saved.y or 0)
    else
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    mainFrame:SetResizable(true)
    mainFrame:SetResizeBounds(T.winMinW, T.winMinH)
    -- FULLSCREEN_DIALOG, not DIALOG. At DIALOG the window shared a strata with
    -- resource bars, cooldown displays and WeakAuras, which then drew across the
    -- settings you were trying to read -- faded, so it looked like the window
    -- itself was see-through. Dropdown popups sit above this at level 220 and
    -- the frame picker overlay is at TOOLTIP, so both still clear it.
    mainFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    mainFrame:SetFrameLevel(10)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    -- Fully opaque. A settings pane is read, not glanced at over the game.
    -- The window carries the CHROME tone and the outer radius; the content
    -- area is an inset darker panel below. Doing it the other way round means
    -- the header, sidebar and footer each need their own fill, and every one of
    -- them lands on a rounded window corner it cannot follow.
    if GUI.FOREVER then
        BuildPlumberChrome(mainFrame, T.sidebarWidth)
    else
        Backdrop(mainFrame, "bgMedium", 1, "border", 1, "rr10")
    end

    local function Remember()
        local p, _, rp, x, y = mainFrame:GetPoint()
        local s = SavedWindow()
        if p then s.point, s.rel, s.x, s.y = p, rp, x, y end
        local w, h = mainFrame:GetSize()
        if w and w > 0 then s.w, s.h = w, h end
    end

    -- Forever: NeedRoll's sounds, the professions book opening and the
    -- profession window closing. Hiding the whole interface (Alt+Z) hides the
    -- window without un-showing it: IsShown stays true on the way out and
    -- `soundOpen` on the way back, so that makes no sound either way.
    local soundOpen = false
    if GUI.FOREVER then
        mainFrame:HookScript("OnShow", function()
            if soundOpen then return end
            soundOpen = true
            PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN)
        end)
    end

    mainFrame:SetScript("OnMouseUp", function() mainFrame:StopMovingOrSizing(); Remember() end)
    mainFrame:SetScript("OnHide", function()
        if soundOpen and not mainFrame:IsShown() then
            soundOpen = false
            PlaySound(SOUNDKIT.UI_PROFESSIONS_WINDOW_CLOSE)
        end
        mainFrame:StopMovingOrSizing()
        Remember()
        -- A dropdown left open when the window closes leaves its fullscreen
        -- click-catcher behind, which then swallows every right-click in the
        -- game until reload.
        GUI.CloseActivePopup()
        GUI.CancelFramePick()
        if SP.PreviewManager then SP.PreviewManager:Stop() end
    end)
    mainFrame:Hide()

    -- ---- header ----
    -- The backdrop goes on the header ITSELF, not on a child frame filling it.
    -- A child frame sits one level above its parent, so an opaque child backdrop
    -- draws over every region the parent owns -- which is exactly what happened:
    -- the title, the version line, the breadcrumb and the close button were all
    -- painted and then buried under the header's own background.
    local header = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    header:SetHeight(T.headerHeight)
    if GUI.FOREVER then
        -- The whole top band, clear of the close button: logo and title over
        -- the side panel, breadcrumb and version over the page.
        header:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -40, 0)
    else
        header:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, 0)
        header:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 0, 0)
    end
    -- No fill: the window's own chrome tone shows through. A header with its
    -- own background would need to round its top corners and square its bottom
    -- ones, which a single nine-slice cannot do.
    header:SetScript("OnMouseDown", function() mainFrame:StartMoving() end)
    header:SetScript("OnMouseUp", function() mainFrame:StopMovingOrSizing(); Remember() end)
    header:EnableMouse(true)

    -- Inset past the window's corner radius, and rounded itself, so it reads as
    -- a deliberate rule rather than a bar clipped by the corners. Forever's
    -- frame draws its own edge under the strip.
    if not GUI.FOREVER then
        local headRule = Tex(header, "OVERLAY", "border", 0.8)
        headRule:SetHeight(1)
        headRule:SetPoint("BOTTOMLEFT",  header, "BOTTOMLEFT",  0, 0)
        headRule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    end

    -- ---- THE LOGO ----
    -- Retail: 72x72 at (-17, +18) from the window corner, so it hangs 17px past
    -- the left edge and 18px above the top. This survives only because
    -- mainFrame has no SetClipsChildren and the logo sits 50 levels above the
    -- header. Reparenting it to the header, or clipping the window, destroys the
    -- overflow.
    --
    -- Forever: the guild's demon eye at its own shape, at the start of the top
    -- band, the window's name beside it.
    local logo = CreateFrame("Button", nil, mainFrame)
    local logoIcon = logo:CreateTexture(nil, "ARTWORK")
    if GUI.FOREVER then
        logo:SetSize(DEMON_EYE.w, DEMON_EYE.h)
        logo:SetPoint("LEFT", header, "LEFT", 18, 0)
        logo:SetFrameLevel(header:GetFrameLevel() + 5)
        logoIcon:SetAllPoints(logo)
        logoIcon:SetTexture(DEMON_EYE.file)
        logoIcon:SetTexCoord(unpack(DEMON_EYE.uv))

        local title = Text(header, 14, "accent")
        title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
        title:SetText("Suspicion's Pack")
    else
        logo:SetSize(72, 72)
        logo:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", -17, 18)
        logo:SetFrameLevel(header:GetFrameLevel() + 50)
        logoIcon:SetAllPoints(logo)
        logoIcon:SetTexture(LOGO_TEX)
    end
    logoIcon:SetTexelSnappingBias(0)
    logoIcon:SetSnapToPixelGrid(false)

    -- Retail: SP.Theme's accent, the brand red. Forever: the light grey the
    -- guild wears the eye in. Hover brightens either.
    local function LogoColor()
        if GUI.FOREVER then return DEMON_EYE.shade, DEMON_EYE.shade, DEMON_EYE.shade end
        local a = SP.Theme.accent
        return a[1], a[2], a[3]
    end
    Paint(logoIcon, function(f)
        local r, g, b = LogoColor()
        f:SetVertexColor(r, g, b, 0.9)
    end)
    logo:SetScript("OnEnter", function()
        local r, g, b = LogoColor()
        logoIcon:SetVertexColor(
            math.min(r * 1.35 + 0.15, 1),
            math.min(g * 1.35 + 0.15, 1),
            math.min(b * 1.35 + 0.15, 1), 1)
    end)
    logo:SetScript("OnLeave", function()
        local r, g, b = LogoColor()
        logoIcon:SetVertexColor(r, g, b, 0.9)
    end)
    logo:SetScript("OnClick", function() OpenPage("home") end)

    local crumbCat = Text(header, 12, "textMuted")
    if GUI.FOREVER then
        -- Over the page, lined up with it.
        crumbCat:SetPoint("LEFT", header, "LEFT", T.sidebarWidth + 28, 0)
    else
        -- One baseline across the whole bar: name, breadcrumb, version, close.
        -- The version used to sit under the title on the left, which pushed the
        -- breadcrumb off its line and left the right-hand side empty.
        -- Just "Pack": the logo immediately to its left already says whose.
        local title = Text(header, 14, "textPrimary")
        title:SetPoint("LEFT", header, "LEFT", 58, 0)
        title:SetText("Pack")

        local crumbSep = Text(header, 12, "textMuted")
        crumbSep:SetPoint("LEFT", title, "RIGHT", 14, 0)
        crumbSep:SetText("|")

        crumbCat:SetPoint("LEFT", crumbSep, "RIGHT", 12, 0)
    end
    self.crumbCat = crumbCat

    local crumbArrow = Text(header, 11, "textMuted")
    crumbArrow:SetPoint("LEFT", crumbCat, "RIGHT", 8, 0)
    self.crumbArrow = crumbArrow

    local crumb = Text(header, 12, "textPrimary")
    crumb:SetPoint("LEFT", crumbArrow, "RIGHT", 8, 0)
    self.crumb = crumb

    local ver = Text(header, 11, "textMuted")
    ver:SetText("v" .. (SP.VERSION or "?"))

    if GUI.FOREVER then
        -- The chrome brings the close button; the version ends the band.
        ver:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    else
        local close = CreateFrame("Button", nil, header)
        close:SetSize(24, 24)
        close:SetPoint("RIGHT", header, "RIGHT", -8, 0)

        -- A rounded plate that lights up on hover. A bare 20px glyph with no
        -- backing reads as decoration rather than as a button.
        local closeBG = GUI.RoundTex(close, "BACKGROUND", "rr4")
        closeBG:SetAllPoints(close)
        Paint(closeBG, function(f, t) f:SetVertexColor(t.bgHover[1], t.bgHover[2], t.bgHover[3], 0) end)

        local closeTex = close:CreateTexture(nil, "ARTWORK")
        closeTex:SetPoint("CENTER", close, "CENTER", 0, 0)
        closeTex:SetSize(13, 13)
        -- A drawn X. The old asset is a plus sign that had to be rotated 45
        -- degrees, which read as a smudge at this size.
        closeTex:SetTexture(CLOSE_X_TEX)
        Paint(closeTex, function(f, t) f:SetVertexColor(t.textMuted[1], t.textMuted[2], t.textMuted[3], 1) end)

        -- Hover tints the glyph, not the whole plate. A solid red block reads as
        -- an error state rather than as "close".
        close:SetScript("OnEnter", function()
            closeTex:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
            closeBG:SetVertexColor(T.bgHover[1], T.bgHover[2], T.bgHover[3], 1)
        end)
        close:SetScript("OnLeave", function()
            closeTex:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
            closeBG:SetVertexColor(T.bgHover[1], T.bgHover[2], T.bgHover[3], 0)
        end)
        close:SetScript("OnClick", function() GUI.Hide() end)

        ver:SetPoint("RIGHT", close, "LEFT", -12, 0)
    end

    -- ---- sidebar ----
    -- Forever: on the side panel, 14 in from the window's left (Plumber's own
    -- inset) and 22 short of where its bronze edge is centred.
    local listW = GUI.FOREVER and (T.sidebarWidth - 36) or T.sidebarWidth
    local sidebar
    if GUI.FOREVER then
        sidebar = CreateFrame("Frame", nil, mainFrame)
        sidebar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 14, -T.headerHeight)
        sidebar:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 14, T.footerHeight)
    else
        sidebar = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
        sidebar:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 0, -T.headerHeight)
        sidebar:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 0, T.footerHeight)
        -- No fill, same reason as the header: it sits on two window corners.

        local div = Tex(sidebar, "OVERLAY", "border")
        div:SetWidth(1)
        div:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
        div:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    end
    sidebar:SetWidth(listW)

    -- Search, at the top of the list it filters. Both builders return the box
    -- and the frame the list hangs under.
    local search, searchAbove
    if GUI.FOREVER then
        search, searchAbove = BuildForeverSearch(sidebar)
    else
        search, searchAbove = BuildFlatSearch(sidebar)
    end
    self.searchBox = search

    local sScroll = CreateFrame("ScrollFrame", nil, sidebar)
    if GUI.FOREVER then
        -- Under the divider, back out to the column's own left edge: the
        -- divider starts 4 before it.
        sScroll:SetPoint("TOPLEFT", searchAbove, "BOTTOMLEFT", 4, 0)
        sScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    else
        sScroll:SetPoint("TOPLEFT", searchAbove, "BOTTOMLEFT", -8, -6)
        sScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -1, 4)
    end
    local sChild = CreateFrame("Frame", nil, sScroll)
    sChild:SetWidth(GUI.FOREVER and listW or (T.sidebarWidth - 1))
    sChild:SetHeight(1)
    sScroll:SetScrollChild(sChild)
    self.sidebarScrollChild = sChild
    SmoothScroll(sScroll, 60)

    local empty = Text(sidebar, 11, "textMuted")
    empty:SetPoint("TOP", sScroll, "TOP", 0, -20)
    empty:SetText("No match")
    empty:Hide()
    self.emptyMsg = empty

    -- ---- content ----
    local content
    if GUI.FOREVER then
        -- On the background, right of the side panel's bronze edge and 16
        -- clear of the frame's shadow on the right.
        content = CreateFrame("Frame", nil, mainFrame)
        content:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", T.sidebarWidth + 20, -T.headerHeight)
        content:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -16, T.footerHeight)
    else
        content = CreateFrame("Frame", nil, mainFrame)
        content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0)
        content:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, T.footerHeight)

        -- The page canvas: a darker panel inset from the chrome, rounded on all
        -- four corners because it never reaches a window corner. This is what
        -- gives the window its depth now that the chrome bands carry no fill of
        -- their own.
        local canvas = CreateFrame("Frame", nil, content)
        canvas:SetPoint("TOPLEFT",     content, "TOPLEFT",      4, -4)
        canvas:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -4,  4)
        Backdrop(canvas, "bgDark", 1, "border", 0.6, "rr6")
    end

    -- Forever: the game's MinimalScrollBar (8 wide, its arrows above and below)
    -- 6 in from the content area's right, with 6 between it and the page.
    local barRoom = GUI.FOREVER and (6 + 8 + 6) or (SB_W + 8)
    local cScroll = CreateFrame("ScrollFrame", nil, content)
    cScroll:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -8)
    cScroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -barRoom, 8)
    local cChild = CreateFrame("Frame", nil, cScroll)
    cChild:SetWidth(1)
    cChild:SetHeight(1)
    cScroll:SetScrollChild(cChild)
    self.contentScroll      = cScroll
    self.contentScrollChild = cChild

    -- The page's width: the content area less the 8 on the left, the bar's
    -- room and 4 of air.
    local function FitPage(w)
        cChild:SetWidth(math.max(1, (w or 0) - 8 - barRoom - 4))
    end

    if GUI.FOREVER then
        -- The scroll bar Forever's own panes use (the statistics pane): track,
        -- thumb and arrows in the client's art. ScrollUtil wires it to a plain
        -- ScrollFrame the way Blizzard does, wheel included.
        local bar = CreateFrame("EventFrame", nil, content, "MinimalScrollBar")
        bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -8)
        bar:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -6, 8)
        ScrollUtil.InitScrollFrameWithScrollBar(cScroll, bar)
        cScroll:EnableMouseWheel(true)
        -- Blizzard's 30 a notch is a crawl through a long page; the flat
        -- skin's wheel moves 80.
        cScroll:SetPanExtent(80)
        -- Hidden while the page fits, as the flat bar is.
        bar:Hide()
        cScroll:HookScript("OnScrollRangeChanged", function(_, _, range)
            bar:SetShown((range or 0) > 0)
        end)
        content:SetScript("OnSizeChanged", function(_, w) FitPage(w) end)
    else
        SmoothScroll(cScroll, 80)

        local track = Tex(content, "BACKGROUND", "bgDark")
        track:SetWidth(SB_W)
        track:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, -8)
        track:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -4, 8)
        local thumb = Tex(content, "ARTWORK", "accent", 0.75)
        thumb:SetWidth(SB_W)
        thumb:SetPoint("TOP", track, "TOP", 0, 0)

        local function UpdateBar()
            local range = cScroll:GetVerticalScrollRange() or 0
            local vis   = cScroll:GetHeight() or 1
            if range <= 0 then track:Hide(); thumb:Hide(); return end
            track:Show(); thumb:Show()
            local total = vis + range
            local th    = math.max(20, vis * (vis / total))
            thumb:SetHeight(th)
            local p = cScroll:GetVerticalScroll() / range
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -((vis - th) * p))
        end
        cScroll:SetScript("OnVerticalScroll", UpdateBar)
        cScroll:SetScript("OnScrollRangeChanged", UpdateBar)
        content:SetScript("OnSizeChanged", function(s, w)
            FitPage(w)
            UpdateBar()
        end)
    end

    -- ---- footer ----
    -- Forever: the band along the bottom carries the labels only; Changelog and
    -- Reset page hang under the window as Plumber's tabs.
    local footer = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    footer:SetHeight(T.footerHeight)
    footer:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, 0)
    if not GUI.FOREVER then
        local footRule = Tex(footer, "OVERLAY", "border", 0.8)
        footRule:SetHeight(1)
        footRule:SetPoint("TOPLEFT",  footer, "TOPLEFT",  0, 0)
        footRule:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    end

    -- Forever: lined up with the list, clear of the frame's shadow.
    local profLbl = Text(footer, 10, "textMuted")
    profLbl:SetPoint("LEFT", footer, "LEFT", GUI.FOREVER and 18 or 10, 0)
    self.profileLabel = profLbl

    local grip = CreateFrame("Button", nil, footer)
    grip:SetSize(16, 16)
    if GUI.FOREVER then
        -- The chat window's size grabber (NeedRoll's), its tip against the
        -- inside of the frame's bottom right corner, above it. The corner's
        -- bronze starts 1 inside the window's edge (texture px 110 of its 128,
        -- the edge at 112), and the grabber's hatching stops short of its own
        -- corner: at 2 in, the tip stood off the metal, so the texture's corner
        -- goes 1 past the window's.
        grip:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 1, -1)
        grip:SetFrameLevel(mainFrame:GetFrameLevel() + 25)
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        -- In the copper gold of the frame's metal, as the list's diamonds,
        -- rather than the chat window's grey.
        for _, tex in ipairs({ grip:GetNormalTexture(), grip:GetHighlightTexture(), grip:GetPushedTexture() }) do
            tex:SetVertexColor(MARKER_GOLD[1], MARKER_GOLD[2], MARKER_GOLD[3])
        end
    else
        grip:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", -3, 3)
        local gripTex = grip:CreateTexture(nil, "ARTWORK")
        gripTex:SetAllPoints()
        gripTex:SetTexture(RESIZE_TEX)
        Paint(gripTex, function(f, t) f:SetVertexColor(t.textMuted[1], t.textMuted[2], t.textMuted[3], 1) end)
    end
    -- RegisterForDrag, not OnMouseDown/OnMouseUp: with the mouse-script pair the
    -- window could be left permanently in sizing mode if the button-up landed
    -- outside the grip.
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function() mainFrame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnDragStop", function() mainFrame:StopMovingOrSizing(); Remember() end)

    local function ResetPage()
        local container = GUI.PageCache and GUI.PageCache[selectedItem]
        if container and container._page then
            container._page:ResetAll()
            GUI:UpdateFooter()
            GUI.UpdateDots()
        end
    end
    local function OpenChangelog()
        if SP.ShowChangelogPopup then SP.ShowChangelogPopup() end
    end

    local resetBtn
    local modLbl = Text(footer, 10, "textMuted")
    if GUI.FOREVER then
        -- Changelog first, so Reset page coming and going moves nothing.
        local chg = BuildPlumberTab(mainFrame, "Changelog", OpenChangelog)
        chg:SetPoint("TOPLEFT", mainFrame, "BOTTOMLEFT", 14, 0)
        resetBtn = BuildPlumberTab(mainFrame, "Reset page", ResetPage)
        resetBtn:SetPoint("TOPLEFT", chg, "TOPRIGHT", TAB_GAP, 0)
        GUI.Tooltip(resetBtn, "Reset this page", "Puts every setting on this page back to its default.")
        -- Clear of the grip in the corner.
        modLbl:SetPoint("RIGHT", footer, "RIGHT", -40, 0)
    else
        resetBtn = W.Button(footer, {
            text = "Reset page", width = 82, height = T.footerHeight - 8,
            tipTitle = "Reset this page",
            tipBody  = "Puts every setting on this page back to its default.",
            onClick  = ResetPage,
        })
        resetBtn:SetPoint("RIGHT", grip, "LEFT", -6, 0)
        modLbl:SetPoint("RIGHT", resetBtn, "LEFT", -8, 0)

        local chg = W.Button(footer, {
            text = "Changelog", width = 76, height = T.footerHeight - 8,
            onClick = OpenChangelog,
        })
        chg:SetPoint("LEFT", profLbl, "RIGHT", 12, 0)
    end
    resetBtn:Hide()
    self.resetBtn = resetBtn
    self.modLabel = modLbl

    -- ESC closes the window. Guarded so a second BuildMainFrame -- which cannot
    -- happen now, but used to on every theme change -- could never duplicate it.
    if not GUI._escRegistered then
        tinsert(UISpecialFrames, "SP_GUIMainFrame")
        GUI._escRegistered = true
    end

    for _, cat in ipairs(GUI.Categories) do expanded[cat.id] = true end
    if not selectedItem then selectedItem = GUI.PageOrder[1] end
end

function GUI.UpdateProfileLabel()
    if not GUI.profileLabel then return end
    local name = SP.db and SP.db:GetCurrentProfile() or "Default"
    GUI.profileLabel:SetText("Profile: " .. tostring(name))
end

function GUI.Show()
    if not mainFrame then GUI:BuildMainFrame() end
    mainFrame:Show()
    GUI.UpdateProfileLabel()
    GUI:RefreshSidebar()
    GUI:RefreshContent()
    if SP.PreviewManager then SP.PreviewManager:Start() end
end

function GUI.Hide()
    if mainFrame then mainFrame:Hide() end
end

function GUI.Toggle()
    if mainFrame and mainFrame:IsShown() then GUI.Hide() else GUI.Show() end
end

-- Re-runs every cached page's gates.
--
-- Needed after a REPAINT, because a painter unconditionally writes the ENABLED
-- colour to the FontStrings it owns while the disabled look is imperative
-- (StdSetEnabled and each widget's _dim). Without this, a theme repaint left
-- every greyed control on every page already visited reading as enabled while
-- still silently refusing clicks -- the precise confusion this rewrite exists to
-- remove.
--
-- Needed after a PROFILE CHANGE, because RefreshAll walks individual widgets and
-- re-reads their values; nothing in that path re-evaluates a master switch. An
-- import that turned a module off moved its toggle and left all its children
-- live.
local function ReapplyGates()
    for _, container in pairs(GUI.PageCache or {}) do
        if container._page then pcall(container._page.ApplyGates, container._page) end
    end
end

-- Called by SP.RefreshTheme instead of the old Rebuild.
function GUI.OnThemeChanged()
    GUI.Repaint()
    ReapplyGates()
    if mainFrame and mainFrame:IsShown() then
        GUI:RefreshSidebar()
    end
end

-- Called after anything rewrites the profile behind the UI's back.
function GUI.OnProfileChanged()
    GUI.RefreshAll()
    ReapplyGates()
    GUI.UpdateProfileLabel()
    if mainFrame and mainFrame:IsShown() then
        GUI:RefreshSidebar()
        GUI:UpdateFooter()
    end
end
