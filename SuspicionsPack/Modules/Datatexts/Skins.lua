-- SuspicionsPack — Datatexts: the three bar skins
--
-- Each skin draws on a holder frame of its own at the bar's level (the slots
-- sit two above, so text stays on top). A holder is built once per bar and
-- skin; switching skins only shows one holder and hides the others, so the
-- options page can flip between them without creating frames.
--
-- All three come from Plumber's art (Media\Plumber, Core\Skin.lua), already
-- shipped by the pack for the options window: measured colours, the leather
-- and the copper corners.

local SP   = SuspicionsPack
local DT   = SP.Datatexts
local Skin = SP.Skin
local P    = Skin.PLUMBER

local Skins = {
    order = { "box", "frame", "text" },
    -- The keys stay as first saved; only the names changed (2026-10-23).
    names = { box = "Forever", frame = "Ornated", text = "Text only" },
    -- What a bordered skin can leave off (Text only has no border).
    edges = {
        { key = "none",        label = "None" },
        { key = "top",         label = "Top" },
        { key = "bottom",      label = "Bottom" },
        { key = "topsides",    label = "Top and sides" },
        { key = "bottomsides", label = "Bottom and sides" },
    },
}
DT.Skins = Skins

local Build, Fit = {}, {}

-- ---- the two bordered skins: lines of one physical pixel --------------------
-- Plumber draws its frames for windows. On a bar 24 high its art either
-- shrinks to a blur (the ornate frame: its sides aliased unlike its bottom,
-- Cruzz's capture of 2026-10-23) or keeps chamfered corners that meet and
-- point both ends of the bar (the dropdown box). Both bordered skins are
-- therefore drawn as lines, in colours measured from Plumber's files:
--   * `lines`, outside in from the bar's edge, one physical pixel each. Line k
--     is inset k - 1 pixels at both ends, so the sides meet in square mitres;
--   * `halo`, alphas of black lines outside the bar, mitred the same way;
--   * a fill under them, and corner pieces over them for Ornated.
-- An open edge drops that edge's lines, halo and corners; the sides run on to
-- the bar's edge. "Top and sides" keeps only the bottom rim, running the full
-- width, with both bottom corners whole (and "Bottom and sides" the top).

-- One physical pixel, in the units of `frame` (its bar has its own scale).
local function OnePixel(frame)
    local factor
    if PixelUtil and PixelUtil.GetPixelToUIUnitFactor then
        factor = PixelUtil.GetPixelToUIUnitFactor()
    elseif GetPhysicalScreenSize then
        local _, physH = GetPhysicalScreenSize()
        if physH and physH > 0 then factor = 768 / physH end
    end
    local scale = frame:GetEffectiveScale()
    if not (factor and scale and scale > 0) then return 1 end
    return factor / scale
end

local SIDES = { "top", "bottom", "left", "right" }

local function C(r, g, b, a) return { r / 255, g / 255, b / 255, a or 1 } end

-- Forever: the options window's dropdown box (ExpansionBorder_TWW.tga, x
-- 512-768, y 320-576) at full scale, squared: its 2 px bronze rim on the bar's
-- edge, the 1 px dark line inside it, its near-black fill and its soft shadow
-- outside. The box art's fill is 90 % opaque; here it is drawn whole, and
-- the bar's Background opacity is its alpha (100 % opaque, as it reads).
local FOREVER = {
    lines = { C(182, 153, 129), C(85, 71, 60), C(5, 5, 3) },
    halo  = { 0.73, 0.39, 0.1 },
    fill  = C(14, 13, 9),
}

-- Ornated: Plumber's thin bronze frame (bottom right of SettingsPanel.png, x
-- 515-1021, y 835-1021) at its own half scale: its 12 px rim as six lines,
-- the colours of its profile (outside in) averaged in pairs, then four lines
-- of its inward shadow, over the leather. Its copper corner blocks are cut 26
-- px from the rim's outer line and drawn 13 physical pixels, smaller only on a
-- bar too short for two of them.
local ORNATED = {
    lines = {
        C(114, 92, 71), C(46, 37, 29), C(41, 26, 14), C(44, 28, 15), C(113, 91, 70), C(46, 37, 28),
        C(0, 0, 0, 0.5), C(0, 0, 0, 0.32), C(0, 0, 0, 0.18), C(0, 0, 0, 0.08),
    },
    halo    = {},
    leather = true,
    corners = {   -- SettingsPanel.png, 26 px from the rim's outer line
        TOPLEFT     = { 518, 544, 838, 864 },
        TOPRIGHT    = { 992, 1018, 838, 864 },
        BOTTOMLEFT  = { 518, 544, 992, 1018 },
        BOTTOMRIGHT = { 992, 1018, 992, 1018 },
    },
    cornerPx = 13,
}

local function BuildLines(h, spec)
    local fill = h:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(h)
    if spec.leather then
        fill:SetTexture(P.BG)
    else
        local c = spec.fill
        fill:SetColorTexture(c[1], c[2], c[3], c[4])
    end
    h.fill = fill

    h.lines, h.halo = {}, {}
    for _, side in ipairs(SIDES) do
        local list = {}
        for k, c in ipairs(spec.lines) do
            local t = h:CreateTexture(nil, "BORDER")
            t:SetColorTexture(c[1], c[2], c[3], c[4])
            list[k] = t
        end
        h.lines[side] = list
        local out = {}
        for j, a in ipairs(spec.halo) do
            local t = h:CreateTexture(nil, "BORDER")
            t:SetColorTexture(0, 0, 0, a)
            out[j] = t
        end
        h.halo[side] = out
    end

    if spec.corners then
        h.corners = {}
        for point, r in pairs(spec.corners) do
            h.corners[point] = Skin.PlumberRect(h:CreateTexture(nil, "ARTWORK"), P.SHEET, r[1], r[2], r[3], r[4])
        end
    end
end

-- Which sides each Open edge choice leaves off ("none" and unknown: none).
local OPEN = {
    top         = { top = true },
    bottom      = { bottom = true },
    topsides    = { top = true, left = true, right = true },
    bottomsides = { bottom = true, left = true, right = true },
}

local function FitLines(h, spec, w, hgt, open)
    local px  = OnePixel(h)
    local off = OPEN[open] or {}
    local show = { top = not off.top, bottom = not off.bottom, left = not off.left, right = not off.right }

    for _, side in ipairs(SIDES) do
        -- Inside: line k, k - 1 pixels in from the edge. A top or bottom line
        -- is inset at an end only where a side meets it; without one it runs
        -- to the bar's end.
        for k, t in ipairs(h.lines[side]) do
            local d = (k - 1) * px
            t:ClearAllPoints()
            t:SetShown(show[side])
            if side == "top" or side == "bottom" then
                local a = side == "top" and "TOP" or "BOTTOM"
                local y = side == "top" and -d or d
                t:SetPoint(a .. "LEFT", h, a .. "LEFT", show.left and d or 0, y)
                t:SetPoint(a .. "RIGHT", h, a .. "RIGHT", show.right and -d or 0, y)
                t:SetHeight(px)
            else
                local x = side == "left" and d or -d
                local a = side == "left" and "LEFT" or "RIGHT"
                t:SetPoint("TOP" .. a, h, "TOP" .. a, x, show.top and -d or 0)
                t:SetPoint("BOTTOM" .. a, h, "BOTTOM" .. a, x, show.bottom and d or 0)
                t:SetWidth(px)
            end
        end
        -- Outside: halo line j, j pixels out. Top and bottom ones reach j out
        -- past a side that is there; the side ones stop j - 1 short, so each
        -- corner pixel is drawn once.
        for j, t in ipairs(h.halo[side]) do
            local o, e = j * px, (j - 1) * px
            t:ClearAllPoints()
            t:SetShown(show[side])
            if side == "top" or side == "bottom" then
                local l, r = show.left and o or 0, show.right and o or 0
                if side == "top" then
                    t:SetPoint("BOTTOMLEFT", h, "TOPLEFT", -l, e)
                    t:SetPoint("BOTTOMRIGHT", h, "TOPRIGHT", r, e)
                else
                    t:SetPoint("TOPLEFT", h, "BOTTOMLEFT", -l, -e)
                    t:SetPoint("TOPRIGHT", h, "BOTTOMRIGHT", r, -e)
                end
                t:SetHeight(px)
            else
                local left = side == "left"
                local x = left and -e or e
                local a, b = left and "RIGHT" or "LEFT", left and "LEFT" or "RIGHT"
                t:SetPoint("TOP" .. a, h, "TOP" .. b, x, show.top and e or 0)
                t:SetPoint("BOTTOM" .. a, h, "BOTTOM" .. b, x, show.bottom and -e or 0)
                t:SetWidth(px)
            end
        end
    end

    if h.corners then
        -- Two corners must fit the bar's height, in whole pixels.
        local c = math.min(spec.cornerPx, math.floor(hgt / px / 2)) * px
        for point, t in pairs(h.corners) do
            t:ClearAllPoints()
            t:SetSize(c, c)
            t:SetPoint(point, h, point)
            -- A corner goes with its top or bottom edge, and stays whole when
            -- the sides are left off.
            local onTop = point:find("^TOP") ~= nil
            t:SetShown((onTop and show.top) or (not onTop and show.bottom))
        end
    end

    if spec.leather then
        -- The leather file is square: show a band of it as tall, relative to
        -- its width, as the bar is.
        local half = math.min(0.5, hgt / math.max(1, w) / 2)
        h.fill:SetTexCoord(0, 1, 0.5 - half, 0.5 + half)
    end
end

function Build.box(h)   BuildLines(h, FOREVER) end
function Build.frame(h) BuildLines(h, ORNATED) end
function Fit.box(h, w, hgt, n, slotW, open)   FitLines(h, FOREVER, w, hgt, open) end
function Fit.frame(h, w, hgt, n, slotW, open) FitLines(h, ORNATED, w, hgt, open) end

-- ---- Text only --------------------------------------------------------------
-- Forever's fill and nothing else: no rim, no shadow, no dividers between the
-- slots. Nothing to fit, so an open edge changes nothing.
function Build.text(h)
    local fill = h:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(h)
    local c = FOREVER.fill
    fill:SetColorTexture(c[1], c[2], c[3], c[4])
    h.fill = fill
end

-- ---- applying -----------------------------------------------------------
local function Holder(bar, id)
    bar.skins = bar.skins or {}
    local h = bar.skins[id]
    if h then return h end
    h = CreateFrame("Frame", nil, bar)
    h:SetAllPoints(bar)
    h:SetFrameLevel(bar:GetFrameLevel())
    Build[id](h)
    bar.skins[id] = h
    return h
end

-- `open`: an Open edge key (Skins.edges), what a bordered skin leaves off.
-- `opacity`: 0 to 1, the alpha of the skin's fill (every fill is drawn
-- opaque, so 1 hides what is behind the bar); its border stays whole.
function Skins.Apply(bar, id, n, slotW, w, hgt, open, opacity)
    if not Build[id] then id = "box" end
    if bar.skins then
        for other, h in pairs(bar.skins) do
            if other ~= id then h:Hide() end
        end
    end
    local h = Holder(bar, id)
    if Fit[id] then Fit[id](h, w, hgt, n, slotW, open) end
    if h.fill then h.fill:SetAlpha(opacity or 1) end
    h:Show()
end

-- { key, label } for the options page.
function Skins.List()
    local out = {}
    for _, id in ipairs(Skins.order) do out[#out + 1] = { key = id, label = Skins.names[id] } end
    return out
end
