-- SuspicionsPack — shared rounded-surface primitives
--
-- WoW's SetBackdrop can only draw a rectangle: bgFile fills the box, edgeFile is
-- a straight strip, and there is no radius anywhere. A real corner needs a
-- nine-slice -- a texture whose four corners render at their native pixel size
-- while the edges and centre stretch -- which WoW exposes as
-- Texture:SetTextureSliceMargins + SetTextureSliceMode.
--
-- This lives in the PARENT addon rather than in the options UI because the
-- changelog popup is shown at login, when the load-on-demand options addon is
-- not loaded. Duplicating the slicing rules in two places is how they drift; a
-- 60-line file in the login path is the cheaper trade.
--
-- THE RULE THAT BITES: an element must be at least 2 * margin in BOTH
-- dimensions. Below that WoW has no centre strip left to stretch and renders the
-- texture OUTSIDE the frame. A 3px rule cannot be sliced at all -- draw it flat,
-- the radius would be invisible anyway.

local SP = SuspicionsPack

local Skin = {}
SP.Skin = Skin

local TEXDIR = "Interface\\AddOns\\SuspicionsPack\\Media\\GUITextures\\"

-- margin >= the corner radius, 2 * margin < the texture size.
Skin.ROUND = {
    square = { tex = "sq",   margin = 4  },   -- minimum element  8x8
    rr4    = { tex = "rr4",  margin = 8  },   -- controls        16x16
    rr6    = { tex = "rr6",  margin = 12 },   -- cards, panels   24x24
    rr10   = { tex = "rr10", margin = 20 },   -- windows         40x40
}

-- Every sliced texture can be recorded with the frame it covers so the rule
-- above is VERIFIED rather than merely documented. Breaking it is silent in Lua
-- and spectacular on screen.
--
-- OFF by default. The audit is developer bookkeeping and its only consumer is
-- Skin.AuditSlices; recording is not free -- building all 32 options pages
-- records 1415 entries, one table per skinned surface, held for the session.
-- That is
-- bounded rather than a runaway leak (WoW cannot free the frames either way),
-- but this file is deliberately on the login path for every user and they should
-- not pay for it. The test suite turns it on, so the rule stays enforced where
-- enforcement actually happens.
Skin.audit = false
local sliced = {}

function Skin.Slice(tex, name, margin, owner)
    if Skin.audit then
        sliced[#sliced + 1] = { name = name, margin = margin, owner = owner }
    end
    tex:SetTexture(TEXDIR .. name .. ".png")
    -- Guarded: the slice API arrived in 10.0. Without it the texture still
    -- draws, just with stretched corners, rather than erroring on an old client.
    if tex.SetTextureSliceMargins then
        tex:SetTextureSliceMargins(margin, margin, margin, margin)
        if tex.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
            tex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
        end
    end
end

-- Returns a list of surfaces that break the 2 * margin rule -- empty means
-- clean -- plus the number that could NOT be judged. If recording was off there
-- is nothing to report on, and saying so beats returning an empty list that
-- reads exactly like a pass.
--
-- The second return value matters. A surface reporting 0 in either dimension has
-- simply not been anchored yet, so it is unmeasurable rather than valid -- and
-- an empty `bad` list drawn mostly from unmeasurable surfaces is indistinguish-
-- able from a real pass. 632 of 1409 recorded surfaces used to be skipped in
-- silence, which made this audit far weaker than it read.
function Skin.AuditSlices()
    if not Skin.audit then
        return { "slice audit was not recording: set SuspicionsPack.Skin.audit = true before any surface is built" }, 0
    end
    local bad, unchecked = {}, 0
    for i = 1, #sliced do
        local e = sliced[i]
        local f = e.owner
        local w, h = 0, 0
        if f and f.GetWidth then w, h = f:GetWidth() or 0, f:GetHeight() or 0 end
        local need = e.margin * 2
        if w <= 0 or h <= 0 then
            unchecked = unchecked + 1
        elseif w < need or h < need then
            bad[#bad + 1] = string.format("%s needs %dx%d, got %.0fx%.0f",
                e.name, need, need, w, h)
        end
    end
    return bad, unchecked
end

-- A rounded fill plus a matching 1px outline, both plain white so the caller
-- tints them. Returns the two textures.
function Skin.Round(frame, style)
    local st = Skin.ROUND[style or "rr4"]
    if frame._spBG then return frame._spBG, frame._spBorder end

    -- Sub-layer -8 / 7 keeps the fill under and the outline over anything the
    -- frame draws in the same layer.
    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(frame)
    local br = frame:CreateTexture(nil, "BORDER", nil, 7)
    br:SetAllPoints(frame)
    Skin.Slice(bg, st.tex, st.margin, frame)
    Skin.Slice(br, st.tex .. "-border", st.margin, frame)

    frame._spBG, frame._spBorder = bg, br
    return bg, br
end

-- A standalone rounded texture, for callers that want the shape without the
-- frame plumbing.
function Skin.RoundTex(parent, layer, style, border, sublevel)
    local st  = Skin.ROUND[style or "rr4"]
    local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    -- Audit the TEXTURE, not the parent. These carry their own anchors and are
    -- routinely much smaller than the frame holding them (an inset swatch fill,
    -- a selection strip, a toggle track), so measuring the parent asked the rule
    -- of the wrong object and always passed.
    Skin.Slice(tex, st.tex .. (border and "-border" or ""), st.margin, tex)
    return tex
end

-- The toggle's capsule, drawn as ONE stretched texture rather than nine-sliced.
--
-- A capsule cannot be nine-sliced. Its corner radius is half its height by
-- definition, so 2*margin always equals the full height and there is no centre
-- strip left to stretch. The old track used the `pill` style, whose texture is a
-- rounded RECTANGLE with a ~5px radius, sliced at margin 8 -- a margin larger
-- than the radius, so every corner carried a piece of the straight edge and the
-- ends read flat.
--
-- The source is 64x32 and the track is 36x18: both 2:1, so the stretch is
-- uniform and the caps stay circular. Drawing a square capsule across a 2:1
-- track would squash them into ellipses.
function Skin.Capsule(parent, layer, border, sublevel)
    local tex = parent:CreateTexture(nil, layer or "ARTWORK", nil, sublevel)
    tex:SetTexture(TEXDIR .. "toggle-pill" .. (border and "-border" or "") .. ".png")
    return tex
end

function Skin.Circle(parent, layer, sublevel)
    local tex = parent:CreateTexture(nil, layer or "OVERLAY", nil, sublevel)
    tex:SetTexture(TEXDIR .. "circle.png")
    return tex
end

-- ============================================================
-- WoW: Forever -- Plumber's panel
--
-- On Forever the options window and the changelog popup wear Plumber's settings
-- panel (by Raenore and Peterodox), copied into Media\Plumber. Here for the
-- same reason as the rounded textures above: the popup comes up at login,
-- before the options addon is loaded, and two copies drift.
-- ============================================================

Skin.FOREVER = (WOW_PROJECT_CAMELOT ~= nil) and (WOW_PROJECT_ID == WOW_PROJECT_CAMELOT)

-- Its sheet of panel parts, its leather background, the bronze frame, close
-- button and dropdown of its landing page, and that dropdown's sheet of list
-- parts. Rects are pixels in those files, as Plumber's own code has them
-- (Modules\ControlCenter\SettingsPanelNew.lua, ExpansionLandingPage\Basic.lua);
-- it draws them at half size.
local PLUMBER_DIR = "Interface\\AddOns\\SuspicionsPack\\Media\\Plumber\\"
Skin.PLUMBER = {
    SHEET = PLUMBER_DIR .. "SettingsPanel.png",          -- 1024 square
    BG    = PLUMBER_DIR .. "SettingsPanelBackground.jpg",
    FRAME = PLUMBER_DIR .. "ExpansionBorder_TWW.tga",    -- 1024 square
    MENU  = PLUMBER_DIR .. "DropdownMenu.tga",           -- 512 square
}

-- Plumber's text colours, with the game's gold for headings.
Skin.FOREVER_TEXT = {
    gold     = { 1,     0.82,  0,     1 },
    cream    = { 0.843, 0.753, 0.639, 1 },  -- 215,192,163: labels, list entries
    readable = { 0.639, 0.616, 0.576, 1 },  -- 163,157,147: notes, paragraphs
    heading  = { 0.580, 0.486, 0.400, 1 },  -- 148,124,102: section headers
}

-- The guild's demon eye, one of the game's own tabard emblems. The large
-- emblem sheet is 1024 square, 16 x 16 cells of 64; the eye is column 7, row 6,
-- and fills x 10-53, y 23-40 of its cell. Cut to that with 2 to spare, 48 x 22,
-- so it sits at its own shape. Worn in light grey, as on the tabard.
Skin.DEMON_EYE = {
    file  = "Interface\\GuildFrame\\GuildEmblemsLG_01",
    uv    = { (7 * 64 + 8) / 1024, (7 * 64 + 56) / 1024, (6 * 64 + 21) / 1024, (6 * 64 + 43) / 1024 },
    w     = 48,
    h     = 22,
    shade = 0.82,
}

-- Sets `tex` to a pixel rect of one of those files (`size` square, 1024 unless
-- given), smoothed rather than snapped, since the art is drawn scaled.
function Skin.PlumberRect(tex, file, x1, x2, y1, y2, size)
    size = size or 1024
    tex:SetTexture(file)
    tex:SetTexCoord(x1 / size, x2 / size, y1 / size, y2 / size)
    tex:SetTexelSnappingBias(0)
    tex:SetSnapToPixelGrid(false)
    return tex
end

-- Plumber's leather background and bronze frame round `frame`, and the copper
-- close button in the frame's top right corner, which calls `onClose`. The
-- background is stretched once over the frame from `bgLeft` in. Returns the
-- frame's border, 20 levels above `frame`.
function Skin.PlumberFrame(frame, bgLeft, onClose)
    local P = Skin.PLUMBER

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(P.BG)
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", bgLeft or 0, 0)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    -- Eight pieces round a box 24 inside the frame, its 64 corners centred on
    -- that box's corners. The bronze lands just outside the frame's edge and
    -- its shadow falls inward. Above everything else in the frame.
    local border = CreateFrame("Frame", nil, frame)
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -24)
    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 24)
    border:SetFrameLevel(frame:GetFrameLevel() + 20)
    local function Corner(x1, x2, y1, y2, point)
        local tex = Skin.PlumberRect(border:CreateTexture(nil, "BORDER"), P.FRAME, x1, x2, y1, y2)
        tex:SetSize(64, 64)
        tex:SetPoint("CENTER", border, point)
        return tex
    end
    local function Span(x1, x2, y1, y2, from, fromPoint, to, toPoint)
        local tex = Skin.PlumberRect(border:CreateTexture(nil, "BORDER"), P.FRAME, x1, x2, y1, y2)
        tex:SetPoint("TOPLEFT", from, fromPoint)
        tex:SetPoint("BOTTOMRIGHT", to, toPoint)
        return tex
    end
    local tl = Corner(0, 128, 0, 128, "TOPLEFT")
    -- The top right corner's variant with a socket for the close button.
    local tr = Corner(518, 646, 48, 176, "TOPRIGHT")
    local bl = Corner(0, 128, 384, 512, "BOTTOMLEFT")
    local br = Corner(384, 512, 384, 512, "BOTTOMRIGHT")
    Span(128, 384, 0, 128,   tl, "TOPRIGHT",   tr, "BOTTOMLEFT")   -- top
    Span(128, 384, 384, 512, bl, "TOPRIGHT",   br, "BOTTOMLEFT")   -- bottom
    Span(0, 128, 128, 384,   tl, "BOTTOMLEFT", bl, "TOPRIGHT")     -- left
    Span(384, 512, 128, 384, tr, "BOTTOMLEFT", br, "TOPRIGHT")     -- right

    -- In that socket: the copper square with its X, lit by the same square
    -- added over itself.
    local close = CreateFrame("Button", nil, border)
    close:SetSize(32, 32)
    close:SetPoint("CENTER", frame, "TOPRIGHT", -12.5, -12.5)
    local glyph = Skin.PlumberRect(close:CreateTexture(nil, "OVERLAY"), P.FRAME, 646, 694, 48, 96)
    glyph:SetSize(24, 24)
    glyph:SetPoint("CENTER")
    local lit = Skin.PlumberRect(close:CreateTexture(nil, "HIGHLIGHT"), P.FRAME, 646, 694, 48, 96)
    lit:SetSize(24, 24)
    lit:SetPoint("CENTER")
    lit:SetBlendMode("ADD")
    lit:SetAlpha(0.5)
    close:SetScript("OnClick", function() onClose() end)

    return border
end

-- Plumber's section header line under `label`'s row: a small diamond at the
-- left, 20 square, then a bronze line out to `right` that fades before its
-- end. The diamond's LEFT goes at `x, y` of `parent`'s top left; the label sits
-- 16 in from it with its baseline 7 above the line. Returns the diamond.
function Skin.PlumberHeader(parent, label, x, y, right, rightX)
    local P = Skin.PLUMBER
    local diamond = Skin.PlumberRect(parent:CreateTexture(nil, "ARTWORK"), P.SHEET, 416, 456, 80, 120)
    diamond:SetSize(20, 20)
    diamond:SetPoint("LEFT", parent, "TOPLEFT", x, y)
    local line = Skin.PlumberRect(parent:CreateTexture(nil, "ARTWORK"), P.SHEET, 456, 736, 80, 120)
    line:SetPoint("TOPLEFT", diamond, "TOPRIGHT")
    line:SetPoint("BOTTOMLEFT", diamond, "BOTTOMRIGHT")
    line:SetPoint("RIGHT", right, "RIGHT", rightX or 0, 0)
    label:ClearAllPoints()
    label:SetPoint("BOTTOMLEFT", diamond, "LEFT", 16, 7)
    return diamond
end

-- Plumber's divider: 24 high, its line in rows 12-16 of those, faded at both
-- ends. The caller places and sizes it.
function Skin.PlumberDivider(parent, layer)
    return Skin.PlumberRect(parent:CreateTexture(nil, layer or "ARTWORK"), Skin.PLUMBER.SHEET, 416, 672, 16, 64)
end
