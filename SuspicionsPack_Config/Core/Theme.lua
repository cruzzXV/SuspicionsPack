-- SuspicionsPack Options — theme primitives and the paint registry
--
-- THE PAINT REGISTRY
--
-- Until this file existed, changing theme preset ran GUI:Rebuild(): SetParent(nil)
-- on the window, wipe the sidebar pools, drop the page cache. WoW cannot free a
-- frame, so every preset click abandoned the entire tree -- 120 frames if you had
-- only opened Home, closer to 1800 if you had browsed all 33 pages. Clicking
-- through all 13 presets in one session cost thousands. It also grew a duplicate
-- "SP_GUIMainFrame" in UISpecialFrames each time, and left the anchor picker and
-- the profile dialog painted in the OLD theme forever, because those two are
-- UIParent-parented and the rebuild never reached them.
--
-- Instead, a frame registers HOW it paints itself and keeps its registration for
-- the session:
--
--     GUI.Paint(frame, function(f, T)
--         f:SetBackdropColor(T.bgLight[1], T.bgLight[2], T.bgLight[3], 0.9)
--     end)
--
-- The closure runs immediately, so this is a drop-in replacement for painting at
-- construction time. GUI.Repaint() then re-runs every closure with the mutated
-- SP.Theme. Nothing is destroyed, nothing leaks, the window does not blink shut
-- and reopen, and the two UIParent singletons repaint with everything else.
--
-- RULES
--   1. A painter must be idempotent and must read colours from its `T` argument,
--      never from an upvalue captured at creation time. Capturing `T.accent[1]`
--      into a local defeats the whole mechanism.
--   2. Painters run inside pcall. One bad closure cannot stop the rest of the
--      window from repainting.
--   3. Register the painter even when the frame is hidden. Repaint does not care
--      about visibility, and a lazily-built page that was painted while hidden is
--      exactly the case the old rebuild got wrong.

local ADDON, ns = ...

local SP  = SuspicionsPack
local GUI = SP.GUI or {}
SP.GUI = GUI
ns.GUI  = GUI

-- T is a reference to the live table. SP.RefreshTheme mutates T[key][1..4] in
-- place, so the identity never changes and this stays valid for the session.
local T = SP.Theme
GUI.T = T

-- Widget factories live under GUI.W, not on GUI itself.
-- GUI carries the window API (Show/Hide/Toggle) and the shell's methods;
-- putting a widget called Toggle next to a window function called Toggle is
-- how the first build of this rewrite silently replaced the toggle widget
-- with the window's show/hide, and every page died on its enable switch.
GUI.W = GUI.W or {}
local W = GUI.W

local BLANK = SP.BLANK

-- ============================================================
-- Paint registry
-- ============================================================

local painters   = {}
local painterN   = 0
local repainting = false

-- Registers `fn` as frame's painter and runs it once.
-- Returns the frame so calls can be chained onto a constructor.
--
-- The first run is protected for the same reason the repaint loop is: a preset
-- missing a colour key would otherwise throw inside a page builder and take the
-- whole page down with it. A page that renders in the wrong colour is a far
-- better outcome than a blank one.
function GUI.Paint(frame, fn)
    painterN = painterN + 1
    local ok, err = pcall(fn, frame, T)
    if ok then
        painters[painterN] = { frame, fn }
    else
        painters[painterN] = false
        if SP.Debug then SP:Debug("GUI", "painter failed at build:", tostring(err)) end
    end
    return frame
end

-- Registers a painter WITHOUT running it. For the rare case where the frame is
-- not ready to be painted yet (a texture created after the closure is written).
function GUI.PaintLater(frame, fn)
    painterN = painterN + 1
    painters[painterN] = { frame, fn }
    return frame
end

function GUI.Repaint()
    -- Re-entrancy guard: a painter that triggers a repaint (a colour swatch that
    -- resolves "theme" through SP.GetColorFromSource, say) would otherwise
    -- recurse until the stack gives out.
    if repainting then return end
    repainting = true
    for i = 1, painterN do
        local p = painters[i]
        if p then
            local ok, err = pcall(p[2], p[1], T)
            if not ok then
                -- Drop the offender rather than error every single repaint for
                -- the rest of the session.
                painters[i] = false
                if SP.Debug then SP:Debug("GUI", "painter failed:", tostring(err)) end
            end
        end
    end
    repainting = false
end

function GUI.PainterCount()
    return painterN
end

-- ============================================================
-- Value registry — the refresh contract
--
-- Every bound widget registers itself here so that anything which rewrites the
-- profile behind the UI's back (profile import, "Reset all colours", a module
-- resetting its own settings) can call GUI.RefreshAll() and have every visible
-- control re-read its value. Before this the controls kept showing the old
-- numbers until the window was closed and reopened.
-- ============================================================

local refreshers = {}
local refreshN   = 0

function GUI.RegisterRefresh(widget)
    refreshN = refreshN + 1
    refreshers[refreshN] = widget
    return widget
end

function GUI.RefreshAll()
    for i = 1, refreshN do
        local w = refreshers[i]
        if w and w.Refresh then
            local ok, err = pcall(w.Refresh, w)
            if not ok then
                refreshers[i] = false
                if SP.Debug then SP:Debug("GUI", "refresh failed:", tostring(err)) end
            end
        end
    end
end

-- ============================================================
-- Fonts
-- ============================================================

local UI_FONT = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"

-- The WoW default face. Expressway has no arrows or block glyphs, so anything
-- drawing a symbol has to fall back to this.
local ICON_FONT = "Fonts\\FRIZQT__.TTF"

function GUI.ApplyFont(fs, size, outline)
    if not fs then return end
    fs:SetFont(UI_FONT, size or 12, outline or "")
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
end

function GUI.ApplyIconFont(fs, size)
    if not fs then return end
    fs:SetFont(ICON_FONT, size or 12, "")
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
end

-- A FontString that follows a theme colour key by name. The painter re-reads
-- T[key] on every repaint, which is what makes text follow the preset.
function GUI.Text(parent, size, colorKey, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    GUI.ApplyFont(fs, size)
    local key = colorKey or "textSecondary"
    GUI.Paint(fs, function(f, t)
        local c = t[key]
        f:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    end)
    return fs
end

function GUI.AccentHex()
    return string.format("|cff%02x%02x%02x",
        math.floor(T.accent[1] * 255 + 0.5),
        math.floor(T.accent[2] * 255 + 0.5),
        math.floor(T.accent[3] * 255 + 0.5))
end

-- ============================================================
-- Backdrops
-- ============================================================

-- ROUNDED CORNERS
--
-- WoW's SetBackdrop can only draw a rectangle: bgFile fills the box, edgeFile is
-- a straight strip. There is no radius. The first pass of this rewrite used it
-- and the result was the same hard-cornered box the old UI had.
--
-- The way to get a real radius is a nine-slice: a texture whose four corners are
-- drawn at their native pixel size while the edges and centre stretch. WoW
-- exposes this as Texture:SetTextureSliceMargins + SetTextureSliceMode, so a
-- single 48px rounded square renders a crisp 6px radius on a card of any size.
--
-- Each style is a fill texture plus a matching 1px outline, both plain white so
-- SetVertexColor can tint them from the theme. Generated into
-- Media/GUITextures at 8x and downsampled, so the arcs are antialiased.
-- The slicing rules and the texture table live in the PARENT addon
-- (SuspicionsPack/Core/Skin.lua), because the changelog popup needs them at
-- login when this load-on-demand addon is not loaded. Two copies of a rule with
-- a numeric constraint in it is how the constraint drifts.
local Skin  = SP.Skin
local ROUND = Skin.ROUND
GUI.ROUND   = ROUND
GUI.AuditSlices = Skin.AuditSlices

-- Gives `frame` a rounded fill and outline, and registers a painter for both.
-- bgKey / borderKey are THEME KEY NAMES, not colour values, so the frame follows
-- the preset without a rebuild.
function GUI.Backdrop(frame, bgKey, bgAlpha, borderKey, borderAlpha, style)
    Skin.Round(frame, style or "rr4")
    GUI.Paint(frame, function(f, t)
        local bg = t[bgKey or "bgMedium"]
        f._spBG:SetVertexColor(bg[1], bg[2], bg[3], bgAlpha or 1)
        if f._spBorder then
            local br = t[borderKey or "border"]
            f._spBorder:SetVertexColor(br[1], br[2], br[3], borderAlpha or 1)
        end
    end)
    return frame
end

-- A plain filled circle: toggle knobs, sidebar state dots, modified dots.
function GUI.CircleTex(parent, layer, sublevel)
    return Skin.Circle(parent, layer, sublevel)
end

-- A standalone rounded texture, for callers that want the shape without the
-- frame plumbing (the toggle track, a swatch outline).
function GUI.RoundTex(parent, layer, style, border, sublevel)
    return Skin.RoundTex(parent, layer, style, border, sublevel)
end

-- A horizontal gradient across a texture, darker on the left.
--
-- The alpha is BAKED INTO THE COLOURS, never applied with SetAlpha afterwards.
-- A gradient's own vertex alpha wins over SetAlpha, so fading a gradient texture
-- the obvious way does nothing at all and the caller is left wondering why the
-- cross-fade never appears. That is the whole reason this helper takes an alpha
-- per stop instead of returning a texture for the caller to fade.
--
-- The darker stop is the same hue at 60%: a flat accent reads as a coloured
-- rectangle, while the same colour with a fall across it reads as a surface.
function GUI.TintGradientH(tex, r, g, b, a, factor)
    if not tex or not tex.SetGradient then return end
    factor = factor or 0.6
    if CreateColor then
        tex:SetGradient("HORIZONTAL",
            CreateColor(r * factor, g * factor, b * factor, a),
            CreateColor(r, g, b, a))
    else
        tex:SetVertexColor(r, g, b, a)
    end
end

-- A flat colour texture that follows a theme key.
function GUI.Tex(parent, layer, colorKey, alpha)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK")
    GUI.Paint(tex, function(tx, t)
        local c = t[colorKey]
        tx:SetColorTexture(c[1], c[2], c[3], alpha or c[4] or 1)
    end)
    return tex
end

-- ============================================================
-- Border focus animation
--
-- Driven off SP.Tick (the shared self-disarming per-frame driver in the parent
-- addon) rather than a fresh C_Timer.NewTicker per hover. The old version
-- allocated a ticker object every time the mouse crossed any control, and the
-- ticker held a strong reference to the frame, so it kept running even after the
-- frame was hidden.
-- ============================================================

local DUR = 0.18

-- SP.Tick calls its subscribers as fn(elapsed) -- the delta only, with no
-- reference to the key. So each frame needs a closure that captures it. It is
-- built once on first hover and cached on the frame, which is still far cheaper
-- than the old code's fresh C_Timer.NewTicker on every single mouse-over.
local function FocusStep(frame, dt)
    frame._focusT = (frame._focusT or 0) + (dt or 0.016)
    local p = frame._focusT / DUR
    if p >= 1 then p = 1 end
    p = 1 - (1 - p) * (1 - p)   -- ease-out quadratic

    local s, e = frame._focusFrom, frame._focusTo
    frame._spBorder:SetVertexColor(
        s[1] + (e[1] - s[1]) * p,
        s[2] + (e[2] - s[2]) * p,
        s[3] + (e[3] - s[3]) * p, 1)

    if p >= 1 then
        frame._focusT = nil
        if SP.Tick then SP.Tick.Remove(frame) end
    end
end

-- Tints the frame's rounded outline texture. Was SetBackdropBorderColor, which
-- no longer applies: the border is a nine-sliced texture now, not a backdrop.
function GUI.FocusBorder(frame, focused)
    local tex = frame._spBorder
    if not tex then return end

    local target = focused and T.accent or T.border
    local sr, sg, sb = tex:GetVertexColor()
    if not sr then
        tex:SetVertexColor(target[1], target[2], target[3], 1)
        return
    end

    frame._focusFrom = frame._focusFrom or {}
    frame._focusFrom[1], frame._focusFrom[2], frame._focusFrom[3] = sr, sg, sb
    frame._focusTo    = frame._focusTo or {}
    frame._focusTo[1], frame._focusTo[2], frame._focusTo[3] = target[1], target[2], target[3]
    frame._focusT     = 0
    frame._focused    = focused and true or false

    if SP.Tick then
        if not frame._focusStep then
            frame._focusStep = function(dt) FocusStep(frame, dt) end
        end
        SP.Tick.Add(frame, frame._focusStep)
    else
        tex:SetVertexColor(target[1], target[2], target[3], 1)
    end
end

-- Stops an in-flight animation and snaps to the resting colour. Called when a
-- frame is hidden mid-hover so it does not come back half-lit.
function GUI.FocusCancel(frame)
    if SP.Tick then SP.Tick.Remove(frame) end
    frame._focusT = nil
    if frame._spBorder then
        local c = frame._focused and T.accent or T.border
        frame._spBorder:SetVertexColor(c[1], c[2], c[3], 1)
    end
end

-- Wires the standard hover behaviour onto anything with a backdrop. `stateFn`,
-- if given, is consulted on leave so a toggled-on control keeps its lit border.
function GUI.HoverBorder(frame, stateFn)
    frame:HookScript("OnEnter", function(f)
        if f._disabled then return end
        GUI.FocusBorder(f, true)
    end)
    frame:HookScript("OnLeave", function(f)
        GUI.FocusBorder(f, stateFn and stateFn(f) or false)
    end)
    frame:HookScript("OnHide", function(f) GUI.FocusCancel(f) end)
    return frame
end

-- ============================================================
-- Tooltips
-- ============================================================

function GUI.Tooltip(frame, title, body)
    if not title and not body then return frame end
    frame:HookScript("OnEnter", function(f)
        GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
        if title then GameTooltip:AddLine(title, 1, 1, 1) end
        if body then GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return frame
end

-- ============================================================
-- Small shared helpers
-- ============================================================

-- Turns a plain list of strings into the {key=, label=} form the dropdowns use.
function GUI.StrOptions(list)
    local out = {}
    for i = 1, #list do out[i] = { key = list[i], label = list[i] } end
    return out
end

-- Deep-compares a stored value against its default so IsModified() works for
-- colour arrays as well as scalars.
function GUI.SameValue(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not GUI.SameValue(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

function GUI.CopyValue(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, sub in pairs(v) do out[k] = GUI.CopyValue(sub) end
    return out
end

-- The one place that closes whatever popup is currently open. mainFrame's OnHide
-- calls this: a dropdown left open when the window closes leaves its fullscreen
-- closer frame behind, which swallows every right-click in the game.
function GUI.CloseActivePopup()
    if GUI._activePopupClose then
        local fn = GUI._activePopupClose
        GUI._activePopupClose = nil
        pcall(fn)
    end
end

-- THE ONE SCROLLING MECHANISM.
--
-- Lives here rather than in Shell.lua because the dropdown popup needs it too,
-- and Widgets.lua loads before Shell. A hand-rolled offset with
-- EnableMouseWheel on the container did NOT receive the wheel in game -- the
-- item buttons sit above it and take the input first. WoW's own ScrollFrame is
-- what handles that case, and this addon already proves it works in the sidebar
-- and the page canvas, so everything that scrolls goes through here.
function GUI.SmoothScroll(sf, step)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(s, delta)
        local range  = s:GetVerticalScrollRange() or 0
        local target = (s._target or s:GetVerticalScroll()) - delta * step
        if target < 0 then target = 0 elseif target > range then target = range end
        s._target = target
        if SP.Tick then
            if not s._scrollFn then
                s._scrollFn = function()
                    local cur = s:GetVerticalScroll()
                    local d   = (s._target - cur) * 0.25
                    if math.abs(d) < 0.5 then
                        s:SetVerticalScroll(s._target)
                        SP.Tick.Remove(s)
                    else
                        s:SetVerticalScroll(cur + d)
                    end
                end
            end
            SP.Tick.Add(s, s._scrollFn)
        else
            s:SetVerticalScroll(target)
        end
    end)
end

-- A single fullscreen click-catcher shared by every popup, rather than one per
-- dropdown.
local closer
function GUI.GetCloser()
    if not closer then
        closer = CreateFrame("Button", "SP_GUICloser", UIParent)
        closer:SetAllPoints(UIParent)
        closer:SetFrameStrata("FULLSCREEN_DIALOG")
        closer:RegisterForClicks("AnyUp")
        closer:Hide()
        closer:SetScript("OnClick", function() GUI.CloseActivePopup() end)
    end
    return closer
end
