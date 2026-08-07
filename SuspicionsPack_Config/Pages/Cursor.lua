-- SuspicionsPack Options — Cursor circle
--
-- The two bespoke pieces here -- the live preview canvas and the six-swatch
-- texture grid -- go in through c:Custom(). Everything the old 391-line builder
-- wrote by hand around them (three enable cascades, two colour-source dropdowns
-- with their own swatch plumbing, eleven separators) is now declarative.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

local CURSOR_MEDIA = "Interface\\AddOns\\SuspicionsPack\\Media\\CursorCircles\\"

local BTN_SZ  = 70    -- one texture swatch
local MIN_GAP = 8     -- never let two swatches touch
local PREVIEW = 100   -- the preview canvas is square

-- ============================================================
-- Texture picker
--
-- Six swatches showing the real ring art, spread across whatever width the card
-- gives them. Used twice -- the main ring and the click ring -- so it takes its
-- colour source and a binding as arguments. Going through a binding rather than
-- a get/set pair is what lets it answer IsModified and ResetDefault, so the
-- picker joins the page's reset instead of being the one row it skips.
-- ============================================================

local function MakeTexturePicker(parent, getColor, binding)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(BTN_SZ)
    container.searchText = "texture ring thin medium thick aura circle"

    local buttons = {}
    local current = nil

    for i, name in ipairs(SP.Cursor.TextureOrder) do
        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetSize(BTN_SZ, BTN_SZ)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT",     btn, "TOPLEFT",      8, -8)
        tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -8,  8)
        tex:SetTexture(SP.Cursor.Textures[name])

        GUI.Backdrop(btn, "bgDark", 1, "border", 1)

        -- Registered as a painter, so the selection border and the tinted art
        -- follow a preset change instead of freezing at build-time colours.
        local function Repaint(_, t)
            t = t or GUI.T
            local r, g, b = 1, 1, 1
            if getColor then r, g, b = getColor() end
            if btn._off then
                btn:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 0.6)
                tex:SetVertexColor(r * 0.3, g * 0.3, b * 0.3)
                tex:SetAlpha(0.5)
            elseif current == name then
                btn:SetBackdropBorderColor(t.accent[1], t.accent[2], t.accent[3], 1)
                tex:SetVertexColor(r, g, b)
                tex:SetAlpha(0.9)
            elseif btn._hover then
                btn:SetBackdropBorderColor(t.accent[1], t.accent[2], t.accent[3], 0.7)
                tex:SetVertexColor(r * 0.85, g * 0.85, b * 0.85)
                tex:SetAlpha(0.85)
            else
                btn:SetBackdropBorderColor(t.border[1], t.border[2], t.border[3], 1)
                tex:SetVertexColor(r * 0.6, g * 0.6, b * 0.6)
                tex:SetAlpha(0.75)
            end
        end
        btn.Repaint = Repaint
        GUI.Paint(btn, Repaint)

        btn:SetScript("OnEnter", function(self)
            self._hover = true
            Repaint()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(name, 1, 0.82, 0)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self._hover = false
            Repaint()
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function(self)
            if self._off then return end
            current = name
            for _, b in ipairs(buttons) do b.Repaint() end
            binding:Set(name)
        end)

        buttons[i] = btn
    end

    container:SetScript("OnSizeChanged", function(self, w)
        if not w or w <= 0 then return end
        local fw = math.floor(w)
        -- 2px of hysteresis. Re-anchoring the swatches feeds a slightly different
        -- width straight back into this handler, and without the guard the two
        -- keep correcting each other forever.
        if math.abs(fw - (self._lastW or 0)) < 2 then return end
        self._lastW = fw
        local n = #buttons
        if n < 2 then return end
        local spacing = math.max(MIN_GAP,
            math.floor((fw - n * BTN_SZ - (GUI.T.paddingSmall or 4)) / (n - 1)))
        for i, b in ipairs(buttons) do
            b:ClearAllPoints()
            if i == 1 then
                b:SetPoint("LEFT", self, "LEFT", 0, 0)
            else
                b:SetPoint("LEFT", buttons[i - 1], "RIGHT", spacing, 0)
            end
        end
    end)

    function container:SetValue(v)
        current = v
        for _, b in ipairs(buttons) do b.Repaint() end
    end
    function container:Refresh()      self:SetValue(binding:Get()) end
    function container:IsModified()   return not binding:IsDefault() end
    function container:ResetDefault() binding:Reset(); self:Refresh() end
    function container:RefreshColors()
        for _, b in ipairs(buttons) do b.Repaint() end
    end
    function container:SetEnabled(en)
        -- `_disabled` as well as the per-button state: it is the flag the row
        -- contract expects, and the page's gate audit checks it.
        self._disabled = not en
        self:SetAlpha(en and 1 or 0.72)
        for _, b in ipairs(buttons) do
            b._off = not en
            b:EnableMouse(en)
            b.Repaint()
        end
    end

    container:SetValue(binding:Get())
    return container
end

GUI.RegisterPage{
    id       = "cursor",
    name     = "Cursor circle",
    category = "combat",
    dbKey    = "cursor",
    keywords = "cursor mouse pointer circle ring click highlight centre dot texture update rate fps",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "cursor", "Cursor",
            "Cursor circle",
            "A ring that follows your mouse pointer on screen.",
            "Enable cursor circle")

        -- Same resolution the module itself uses, mirrored here so the preview and
        -- the swatches show what the ring will actually look like.
        local function SourceColor(srcKey, colorKey)
            local src = db[srcKey] or "theme"
            if src == "theme" then
                local a = GUI.T.accent
                return a[1], a[2], a[3]
            end
            if src == "class" then
                local _, cls = UnitClass("player")
                local c = RAID_CLASS_COLORS and cls and RAID_CLASS_COLORS[cls]
                if c then return c.r, c.g, c.b end
            end
            local cc = db[colorKey] or { 1, 1, 1 }
            return cc[1], cc[2], cc[3]
        end
        local function RingColor()  return SourceColor("colorSource", "cursorColor") end
        local function ClickColor() return SourceColor("clickColorSource", "clickColor") end

        -- ── Preview canvas ───────────────────────────────────────
        local preview = CreateFrame("Frame", nil, parent)
        preview:EnableMouse(false)

        local box = CreateFrame("Frame", nil, preview, "BackdropTemplate")
        box:SetSize(PREVIEW, PREVIEW)
        box:SetPoint("CENTER", preview, "CENTER", 0, 0)
        box:EnableMouse(false)
        GUI.Backdrop(box, "bgDark", 1, "border", 1)

        local hLine = GUI.Tex(box, "ARTWORK", "border")
        hLine:SetSize(PREVIEW - 4, 1)
        hLine:SetPoint("CENTER", box, "CENTER", 0, 0)
        local vLine = GUI.Tex(box, "ARTWORK", "border")
        vLine:SetSize(1, PREVIEW - 4)
        vLine:SetPoint("CENTER", box, "CENTER", 0, 0)

        local ring = box:CreateTexture(nil, "ARTWORK")
        ring:SetPoint("CENTER", box, "CENTER", 0, 0)
        ring:SetSize(50, 50)   -- non-zero, so it renders before the first update
        ring:SetTexelSnappingBias(0)
        ring:SetSnapToPixelGrid(false)

        local dot = box:CreateTexture(nil, "OVERLAY")
        dot:SetTexture(CURSOR_MEDIA .. "Click.tga")
        dot:SetPoint("CENTER", box, "CENTER", 0, 0)
        dot:SetVertexColor(1, 1, 1, 1)
        dot:SetTexelSnappingBias(0)
        dot:SetSnapToPixelGrid(false)

        local function UpdatePreview()
            local path = SP.Cursor and SP.Cursor.Textures
                and SP.Cursor.Textures[db.texture or "Thick"]
            if path then
                -- SetTexture never raises a Lua error in WoW -- a failed load just
                -- renders blank, so pcall buys nothing. Clearing to nil first
                -- forces a full reload, which is what makes the PNG rings appear
                -- the first time the page is opened.
                ring:SetTexture(nil)
                ring:SetTexture(path)
                ring:SetBlendMode("BLEND")
            end
            local r, g, b = RingColor()
            ring:SetVertexColor(r, g, b, 0.9)

            -- 20..120 px of real ring maps onto 24..72 px of canvas.
            local size = math.floor(24 + ((db.size or 50) - 20) * (72 - 24) / (120 - 20) + 0.5)
            if size < 24 then size = 24 elseif size > 72 then size = 72 end
            ring:SetSize(size, size)

            if db.showDot then dot:Show() else dot:Hide() end
            local ds = math.max(2, math.floor((db.dotSize or 6) * 1.3 + 0.5))
            dot:SetSize(ds, ds)
        end
        function preview:Refresh() UpdatePreview() end

        c1:Custom(preview, PREVIEW + (GUI.T.paddingSmall or 4) * 2)

        local function Apply()
            page.apply()
            UpdatePreview()
        end

        c1:Slider{
            key = "size", label = "Size",
            desc = "Diameter of the ring in pixels.",
            min = 20, max = 120, step = 2, onChange = Apply,
        }

        c1:Note("Ring texture")
        local picker = MakeTexturePicker(parent, RingColor, GUI.NewBinding{
            db = db, key = "texture", onChange = Apply,
            default = page.defaults and page.defaults.texture,
        })
        c1:Custom(picker, BTN_SZ)

        local dotOn = c1:Toggle{
            key = "showDot", label = "Centre dot",
            desc = "Marks the exact pointer position inside the ring.",
            onChange = Apply,
        }
        c1:GateBelow(dotOn)
        c1:Slider{ key = "dotSize", label = "Dot size", min = 2, max = 16, step = 1,
                   onChange = Apply }
        c1:EndGate()

        c1:ColorSource{
            label    = "Ring colour",
            srcKey   = "colorSource",
            colorKey = "cursorColor",
            onChange = function()
                Apply()
                picker:RefreshColors()
            end,
        }

        -- ── Click circle ─────────────────────────────────────────
        local c2 = page:Card("Click circle",
            "A ring shown while a mouse button is held down.")
        local clickOn = c2:Toggle{ key = "showClickCircle", label = "Enable click circle" }
        c2:GateBelow(clickOn)

        c2:Dropdown{
            key   = "clickMode",
            label = "Mode",
            desc  = "Overlay draws a second ring on top of the first; Replace swaps " ..
                    "the main ring out for as long as the button is down.",
            -- No `default` here: clickMode is in SP.DEFAULTS.profile.cursor
            -- ("overlay"), so Card:Fill looks it up like every other key on the
            -- page. Restating it would be a second copy to keep in step.
            options = { { key = "overlay", label = "Overlay" },
                        { key = "replace", label = "Replace" } },
        }
        c2:Slider{
            key = "clickSize", label = "Size", min = 20, max = 150, step = 2,
            desc = "Diameter of the click ring in pixels.",
            onChange = function()
                page.apply()
                -- Flashes the ring at the pointer so the size is visible while
                -- dragging. It is on a 1.2s timer parented to UIParent -- the
                -- OnHide hook at the bottom of this builder is what clears it.
                if SP.Cursor then SP.Cursor.PreviewClickCircle() end
            end,
        }

        c2:Note("Ring texture")
        local clickPicker = MakeTexturePicker(parent, ClickColor, GUI.NewBinding{
            db = db, key = "clickTexture", onChange = page.apply,
            default = page.defaults and page.defaults.clickTexture,
        })
        c2:Custom(clickPicker, BTN_SZ)

        c2:ColorSource{
            label    = "Ring colour",
            srcKey   = "clickColorSource",
            colorKey = "clickColor",
            onChange = function()
                page.apply()
                clickPicker:RefreshColors()
            end,
        }

        -- ── Performance ──────────────────────────────────────────
        local c3 = page:Card("Performance",
            "The ring is repositioned on every frame unless you throttle it.")
        local limit = c3:Toggle{
            key   = "limitUpdateRate",
            label = "Limit update rate",
            desc  = "Moves the ring on a fixed interval instead of every frame.",
        }
        c3:GateBelow(limit)

        -- The profile stores seconds and the slider works in whole milliseconds,
        -- so the default cannot come straight out of SP.DEFAULTS; it is converted
        -- from it rather than restated.
        local defSeconds = SP.DEFAULTS and SP.DEFAULTS.profile and SP.DEFAULTS.profile.cursor
                           and SP.DEFAULTS.profile.cursor.updateInterval
        c3:Slider{
            label = "Update interval", suffix = " ms",
            min = 8, max = 200, step = 1,
            get = function() return math.floor((db.updateInterval or 0.02) * 1000 + 0.5) end,
            set = function(v) db.updateInterval = v / 1000 end,
            default = defSeconds and math.floor(defSeconds * 1000 + 0.5) or nil,
        }

        -- SP_CursorCircle and SP_CursorClickCircle are parented to UIParent, so
        -- hiding the page container does NOT hide them: without this the ring, and
        -- any click-circle preview left over from the size slider, float on top of
        -- every other page. Regression recorded in lessons.md, 2026-03-29.
        parent:HookScript("OnHide", function()
            if SP.Cursor then SP.Cursor.Refresh() end
        end)

        UpdatePreview()
        page:Finish()
    end,
}
