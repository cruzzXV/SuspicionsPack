-- SuspicionsPack — NodeRadar's copy of the minimap (WoW: Forever only, see the .toc gate)
--
-- A scan moves the real minimap under the mouse (Scan.lua). Meanwhile this draws the same
-- picture in its place: the ground pictures Tiles.lua lists, tinted the way the minimap tints
-- them, your arrow, and the nodes the radar already knows, with the minimap's own dot. The
-- minimap's other dots (group, quest areas, flight masters) are not drawn: they are gone for
-- the length of a scan.
--
-- Measured in game on 2026-11-09 (Thousand Needles, by day): the copy lines up with the
-- minimap to the pixel, and the minimap is the pictures times (0.889, 0.839, 0.780), within
-- 1.5 % per channel. Not measured by night yet. Indoors the minimap draws other maps, so no
-- copy there, and no scan (Copy.CanDraw).

local SP = SuspicionsPack
local Copy = {}
SP.NodeRadarCopy = Copy

local Tiles = SP.NodeRadarTiles
local _issecretvalue = issecretvalue or function() return false end
local floor = math.floor

local TILE = 1600 / 3            -- yards per map tile
local TINT = { 0.889, 0.839, 0.780 }
local ARROW = "Interface\\Minimap\\MinimapArrow"
local ARROW_SIZE = 32            -- minimap units
local DOT = 136435               -- Interface\Minimap\ObjectIcons, 8 x 8 pictures
local DOT_SIZE = 12              -- minimap units
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local frame, mask, back, arrow
local place               -- where the copy stands, in UIParent's units: { x, y, w, h }
local tiles, ids, dots = {}, {}, {}
local masked = false

-- The continent's pictures, the tile you are on, and your place in it (0 to 1, east and south
-- from its top left); nil off the two continents or when the game will not say.
function Copy.Where()
    local north, west, _, map = UnitPosition("player")
    if _issecretvalue(north) or _issecretvalue(west) or _issecretvalue(map) or not north or not west then return nil end
    local set = map and Tiles[map]
    if type(set) ~= "table" then return nil end
    local fx, fy = 32 - west / TILE, 32 - north / TILE
    local tx, ty = floor(fx), floor(fy)
    return set, tx, ty, fx - tx, fy - ty
end

-- The tint the copy gives the ground pictures, for /spack radar compare.
function Copy.Tint() return TINT[1], TINT[2], TINT[3] end

-- Can the copy stand in for the minimap here? A reason when not.
function Copy.CanDraw()
    if IsIndoors() then return false, "indoors" end
    if not Copy.Where() then return false, "no minimap pictures here" end
    return true
end

local function Build()
    frame = CreateFrame("Frame", "SP_NodeRadarCopy", UIParent)
    frame:EnableMouse(false)
    frame:SetClipsChildren(true)
    frame:Hide()
    back = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    back:SetAllPoints(frame)
    back:SetColorTexture(0, 0, 0, 1)
    for i = 1, 9 do
        local t = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
        t:SetVertexColor(TINT[1], TINT[2], TINT[3])
        tiles[i] = t
    end
    arrow = frame:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture(ARROW)
    arrow:SetSize(ARROW_SIZE, ARROW_SIZE)
    arrow:SetPoint("CENTER")
end

-- A round minimap: everything drawn through a round mask; square: the frame clips.
local function SetRound(round)
    if round == masked then return end
    if round and not mask then
        mask = frame:CreateMaskTexture()
        mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(frame)
    end
    local list = { back }
    for i = 1, #tiles do list[#list + 1] = tiles[i] end
    for i = 1, #dots do list[#list + 1] = dots[i] end
    for _, t in ipairs(list) do
        if round then t:AddMaskTexture(mask) else t:RemoveMaskTexture(mask) end
    end
    masked = round
end

local function Dot(i)
    local t = dots[i]
    if t then return t end
    t = frame:CreateTexture(nil, "ARTWORK")
    t:SetTexture(DOT)
    t:SetTexCoord(0.75, 0.875, 0, 0.125) -- row 0, column 6: the tracked herb or vein
    t:SetSize(DOT_SIZE, DOT_SIZE)
    if masked then t:AddMaskTexture(mask) end
    dots[i] = t
    return t
end

-- Draws where you are now: the 3 x 3 tiles around you, your arrow, and the nodes on this map.
-- Your map position comes from the caller (NodeRadar's), as nodes are kept in map
-- coordinates. False when the copy cannot be drawn here.
function Copy.Update(nodes, map, x, y, width, height)
    if not frame then return false end
    local set, tx, ty, u, v = Copy.Where()
    local radius = C_Minimap.GetViewRadius()
    if not set or _issecretvalue(radius) or not radius or radius <= 0 then return false end
    local half = frame:GetWidth() / 2
    local k = half / radius          -- frame units per yard
    local size = TILE * k
    local i = 0
    for dy = -1, 1 do
        for dx = -1, 1 do
            i = i + 1
            local t = tiles[i]
            local id = set[(tx + dx) * 64 + ty + dy]
            if id then
                if ids[i] ~= id then
                    ids[i] = id
                    t:SetTexture(id)
                end
                t:ClearAllPoints()
                t:SetSize(size, size)
                t:SetPoint("TOPLEFT", frame, "CENTER", (dx - u) * size, (v - dy) * size)
                t:Show()
            else
                t:Hide()
            end
        end
    end
    local facing = GetPlayerFacing()
    if not _issecretvalue(facing) and facing then arrow:SetRotation(facing) end
    local shown = 0
    if map and nodes then
        local reach = half + DOT_SIZE
        for n = 1, #nodes do
            local node = nodes[n]
            if node.map == map then
                local east, north = (node.mx - x) * width * k, (y - node.my) * height * k
                if east > -reach and east < reach and north > -reach and north < reach then
                    shown = shown + 1
                    local t = Dot(shown)
                    t:ClearAllPoints()
                    t:SetPoint("CENTER", frame, "CENTER", east, north)
                    t:Show()
                end
            end
        end
    end
    for n = shown + 1, #dots do dots[n]:Hide() end
    return true
end

-- Over the minimap's place, given while it is still there: same spot, size and effective
-- scale, in its strata, at the level given (one over the minimap, so it can fade in over it).
function Copy.Show(left, bottom, width, height, strata, level, round, nodes, map, x, y, mapWidth, mapHeight)
    if not frame then Build() end
    SetRound(round and true or false)
    frame:SetScale(Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale())
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
    frame:SetSize(width, height)
    local k = Minimap:GetEffectiveScale() / UIParent:GetEffectiveScale()
    place = { left * k, bottom * k, width * k, height * k }
    frame:SetFrameStrata(strata)
    frame:SetFrameLevel(level)
    local ok = Copy.Update(nodes, map, x, y, mapWidth, mapHeight)
    Copy.StopFade()
    frame:Show()
    return ok
end

-- ============================================================
-- The minimap's pieces, photocopied
-- ============================================================
-- A scan hides the minimap's buttons, frame and texts where they are: they would ride under
-- the mouse with it. Their look is copied first, in their place: every texture and text as
-- drawn (file, coordinates, colour, alpha, layer, masks), each frame's copy in its strata and
-- one level over the piece itself (so the copy can fade in over it), the minimap's own
-- regions just over the ground's copy. Nothing of theirs is
-- touched, only read. A still picture for a few tenths of a second: nothing on it moves or
-- takes the mouse. What cannot be read (a secret, a texture the game names no file for) is
-- left out, and vanishes for the scan as before; /spack radar status says what.
local MAX_REGIONS = 600   -- a last guard
local DEPTH = 6           -- levels down a piece's tree
local holders, usedHolders = {}, 0
local root                -- every piece's copy is on it: its alpha is the fade's
local clip                -- the minimap's place: the pieces it clips are clipped to it
local made = { drawn = 0, out = 0, why = {} }
local spots = {}          -- where each piece's copy is drawn, in UIParent's units

local function Out(why)
    made.out = made.out + 1
    if not made.why[why] and #made.why < 4 then
        made.why[why] = true
        made.why[#made.why + 1] = why
    end
end

local function Holder(parent, strata, level)
    usedHolders = usedHolders + 1
    local h = holders[usedHolders]
    if not h then
        h = CreateFrame("Frame", nil, UIParent)
        h:EnableMouse(false)
        h.textures, h.texts, h.masks = {}, {}, {}
        holders[usedHolders] = h
    end
    h:SetParent(parent)
    h:ClearAllPoints()
    h:SetAllPoints(UIParent)
    h:SetFrameStrata(strata)
    h:SetFrameLevel(level)
    for _, t in ipairs(h.textures) do t:Hide() end
    for _, fs in ipairs(h.texts) do fs:Hide() end
    h.nt, h.nf, h.nm = 0, 0, 0
    h:Show()
    return h
end

-- Where a region is drawn, in UIParent's units; nil when the game will not say.
local function Place(r, ui)
    local ok, left, bottom, width, height = pcall(r.GetRect, r)
    if not ok or _issecretvalue(left) or _issecretvalue(bottom) or _issecretvalue(width) or _issecretvalue(height)
        or not left or not bottom or not width or not height or width <= 0 or height <= 0 then
        return nil
    end
    local okS, scale = pcall(r.GetEffectiveScale, r)
    if not okS or _issecretvalue(scale) or type(scale) ~= "number" then return nil end
    local k = scale / ui
    return left * k, bottom * k, width * k, height * k, k
end

local function Put(region, x, y, w, h)
    region:ClearAllPoints()
    region:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    region:SetSize(w, h)
end

local function CopyMasks(h, r, t, ui)
    if t.masks then
        for _, m in ipairs(t.masks) do t:RemoveMaskTexture(m) end
    end
    t.masks = nil
    local n = r.GetNumMaskTextures and r:GetNumMaskTextures()
    if _issecretvalue(n) or type(n) ~= "number" then return end
    for i = 1, n do
        local m = r:GetMaskTexture(i)
        local file, x, y, w, hh
        if m and not _issecretvalue(m) then
            file = m:GetTexture()
            x, y, w, hh = Place(m, ui)
        end
        if file and not _issecretvalue(file) and x then
            h.nm = h.nm + 1
            local mm = h.masks[h.nm]
            if not mm then
                mm = h:CreateMaskTexture()
                h.masks[h.nm] = mm
            end
            mm:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            Put(mm, x, y, w, hh)
            t:AddMaskTexture(mm)
            t.masks = t.masks or {}
            t.masks[#t.masks + 1] = mm
        end
    end
end

local function CopyTexture(h, r, alpha, ui)
    local file = r:GetTexture()
    if _issecretvalue(file) then return Out("secret texture") end
    if file == nil then return end   -- an empty texture draws nothing
    -- A plain colour (SetColorTexture): what the game names it is not known yet.
    if type(file) == "string" and file:find("^Color") then return Out(file) end
    local x, y, w, hh = Place(r, ui)
    if not x then return Out("texture not placed") end
    h.nt = h.nt + 1
    local t = h.textures[h.nt]
    if not t then
        t = h:CreateTexture()
        h.textures[h.nt] = t
    end
    t:SetTexture(file)
    t:SetTexCoord(r:GetTexCoord())
    t:SetVertexColor(r:GetVertexColor())
    t:SetBlendMode(r:GetBlendMode())
    t:SetDrawLayer(r:GetDrawLayer())
    if r.GetDesaturation then t:SetDesaturation(r:GetDesaturation()) end
    if r.GetRotation then t:SetRotation(r:GetRotation()) end
    if r.GetHorizTile then t:SetHorizTile(r:GetHorizTile()) end
    if r.GetVertTile then t:SetVertTile(r:GetVertTile()) end
    t:SetAlpha(alpha)
    Put(t, x, y, w, hh)
    spots[#spots + 1] = { x, y, w, hh }
    CopyMasks(h, r, t, ui)
    t:Show()
    made.drawn = made.drawn + 1
end

local function CopyText(h, r, alpha, ui)
    local text = r:GetText()
    if _issecretvalue(text) or type(text) ~= "string" or text == "" then return end
    local font, size, flags = r:GetFont()
    if _issecretvalue(font) or _issecretvalue(size) or not font or not size then return Out("text without a font") end
    local x, y, w, hh, k = Place(r, ui)
    if not x then return Out("text not placed") end
    h.nf = h.nf + 1
    local fs = h.texts[h.nf]
    if not fs then
        fs = h:CreateFontString()
        h.texts[h.nf] = fs
    end
    fs:SetFont(font, size * k, flags)
    fs:SetText(text)
    fs:SetTextColor(r:GetTextColor())
    fs:SetShadowColor(r:GetShadowColor())
    local sx, sy = r:GetShadowOffset()
    fs:SetShadowOffset((sx or 0) * k, (sy or 0) * k)
    fs:SetJustifyH(r:GetJustifyH())
    fs:SetJustifyV(r:GetJustifyV())
    fs:SetDrawLayer(r:GetDrawLayer())
    if r.CanWordWrap then fs:SetWordWrap(r:CanWordWrap()) end
    fs:SetAlpha(alpha)
    Put(fs, x, y, w, hh)
    spots[#spots + 1] = { x, y, w, hh }
    fs:Show()
    made.drawn = made.drawn + 1
end

-- One region, drawn at alpha × its frame's effective alpha. Of the minimap's own, the ones
-- in its background layer are under its ground: left out.
local function CopyRegion(h, r, frameAlpha, ui, own)
    if made.drawn + made.out >= MAX_REGIONS then return end
    -- Textures and texts: a mask texture is a region too, and is not drawn.
    local kind = r.GetObjectType and r:GetObjectType()
    if kind ~= "Texture" and kind ~= "FontString" then return end
    local okV, visible = pcall(r.IsVisible, r)
    if not okV or _issecretvalue(visible) or not visible then return end
    local okA, a = pcall(r.GetAlpha, r)
    if not okA or _issecretvalue(a) or type(a) ~= "number" then return Out("secret alpha") end
    local alpha = a * frameAlpha
    if alpha <= 0 then return end
    if own and kind == "Texture" and r:GetDrawLayer() == "BACKGROUND" then return end
    local ok, err = pcall(kind == "FontString" and CopyText or CopyTexture, h, r, alpha, ui)
    if not ok then Out("error: " .. tostring(err):sub(1, 60)) end
end

local function CopyFrame(f, ui, parent, depth)
    if depth > DEPTH or (f.IsForbidden and f:IsForbidden()) then return end
    local okV, visible = pcall(f.IsVisible, f)
    if not okV or _issecretvalue(visible) or not visible then return end
    local okA, alpha = pcall(f.GetEffectiveAlpha, f)
    if not okA or _issecretvalue(alpha) or type(alpha) ~= "number" or alpha <= 0 then return end
    local okS, strata, level = pcall(function() return f:GetFrameStrata(), f:GetFrameLevel() end)
    if not okS or _issecretvalue(strata) or _issecretvalue(level) then return end
    local regions = { f:GetRegions() }
    if regions[1] then
        local h = Holder(parent, strata, level + 1)
        for _, r in ipairs(regions) do CopyRegion(h, r, alpha, ui, false) end
    end
    for _, kid in ipairs({ f:GetChildren() }) do CopyFrame(kid, ui, parent, depth + 1) end
end

local function IsUnderMinimap(f)
    for _ = 1, 12 do
        if type(f) ~= "table" then return false end
        if f == Minimap then return true end
        local ok, up = pcall(f.GetParent, f)
        if not ok then return false end
        f = up
    end
    return false
end

-- Copies the pieces Scan.lua is about to hide (the minimap's children and regions, the
-- frames that follow it), as they are now.
function Copy.ShowPieces(pieces)
    for i = 1, usedHolders do holders[i]:Hide() end
    usedHolders = 0
    made = { drawn = 0, out = 0, why = {} }
    spots = {}
    local ui = UIParent:GetEffectiveScale()
    if not root then
        root = CreateFrame("Frame", nil, UIParent)
        root:EnableMouse(false)
        root:SetAllPoints(UIParent)
    end
    root:Show()
    -- What the minimap clips, its copy clips too.
    local clipped = Minimap.DoesClipChildren and Minimap:DoesClipChildren()
    if clipped and not _issecretvalue(clipped) then
        if not clip then
            clip = CreateFrame("Frame", nil, root)
            clip:EnableMouse(false)
            clip:SetClipsChildren(true)
        end
        local x, y, w, h = Place(Minimap, ui)
        if x then
            Put(clip, x, y, w, h)
            clip:Show()
        else
            clipped = false
        end
    else
        clipped = false
    end
    local own
    for _, piece in ipairs(pieces) do
        local kind = piece.GetObjectType and piece:GetObjectType()
        if kind == "Texture" or kind == "FontString" then
            if not own then
                own = Holder(root, Minimap:GetFrameStrata(), Minimap:GetFrameLevel() + 2)
            end
            local okA, alpha = pcall(Minimap.GetEffectiveAlpha, Minimap)
            if okA and not _issecretvalue(alpha) and type(alpha) == "number" then CopyRegion(own, piece, alpha, ui, true) end
        else
            -- One piece that cannot be read does not stop the others being copied.
            local ok, err = pcall(CopyFrame, piece, ui, clipped and IsUnderMinimap(piece) and clip or root, 0)
            if not ok then Out("error: " .. tostring(err):sub(1, 60)) end
        end
    end
end

-- Is the cursor (screen units, GetCursorPosition's) over the minimap's place or one of its
-- pieces' copies? You are going for them: the scan gives them back. A copy far bigger than
-- the minimap (a full-screen layer) does not count, or no scan would ever run.
local function Inside(r, x, y) return x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4] end

function Copy.Covers(cx, cy)
    if not (frame and frame:IsShown() and place) or Copy.Fading() then return false end
    local ui = UIParent:GetEffectiveScale()
    local x, y = cx / ui, cy / ui
    if Inside(place, x, y) then return true end
    for _, r in ipairs(spots) do
        if r[3] <= place[3] * 2 and r[4] <= place[4] * 2 and Inside(r, x, y) then return true end
    end
    return false
end

-- What the last copy of the pieces drew and left out, for /spack radar status.
function Copy.Pieces()
    return made.drawn, made.out, made.why[1] and table.concat(made.why, ", ") or "nothing"
end

-- ============================================================
-- Fading
-- ============================================================
-- The ground's copy and the pieces' copies together. The scan fades them in (Copy.SetAlpha
-- each frame) and out (Copy.FadeOut, on its own once the scan is over).
local FADE_KEY = "NodeRadarCopyFade"
local fade                -- fading out: { from, at, seconds }

function Copy.SetAlpha(alpha)
    if frame then frame:SetAlpha(alpha) end
    if root then root:SetAlpha(alpha) end
end

function Copy.StopFade()
    if fade then
        fade = nil
        SP.Tick.Remove(FADE_KEY)
    end
end

local function FadeStep()
    if not fade then return SP.Tick.Remove(FADE_KEY) end
    local t = (GetTime() - fade.at) / fade.seconds
    if t >= 1 then return Copy.Hide() end
    Copy.SetAlpha(fade.from * (1 - t))
end

function Copy.FadeOut(seconds)
    if not (frame and frame:IsShown()) or not seconds or seconds <= 0 then return Copy.Hide() end
    local from = frame:GetAlpha()
    if _issecretvalue(from) or type(from) ~= "number" or from <= 0 then return Copy.Hide() end
    fade = { from = from, at = GetTime(), seconds = seconds }
    SP.Tick.Add(FADE_KEY, FadeStep)
end

function Copy.Fading() return fade ~= nil end

function Copy.Hide()
    Copy.StopFade()
    if frame then frame:Hide() end
    for i = 1, usedHolders do holders[i]:Hide() end
    usedHolders = 0
    if clip then clip:Hide() end
    if root then root:Hide() end
end

function Copy.IsShown()
    return frame ~= nil and frame:IsShown()
end
