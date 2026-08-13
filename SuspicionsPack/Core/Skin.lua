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
