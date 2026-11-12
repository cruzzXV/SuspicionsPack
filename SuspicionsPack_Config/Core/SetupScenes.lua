-- SuspicionsPack Options — the setup tour's illustrations
--
-- One small animated scene per feature, drawn from the game's own icons and the
-- pack's art (the radar's arrow, the campfire wheel's ring, the Details bars), so
-- the player sees what a feature does before turning it on. Names come from the
-- client where it has them (spells, items, the game menu), so a French client
-- shows French names.
--
--   GUI.SetupScenes[key](holder, width, height) -> update(elapsed) or nil
--
-- `holder` clips its children; the tour calls update from its own OnUpdate, so a
-- scene only moves while its step is on screen.

local ADDON, ns = ...

local SP  = SuspicionsPack
local GUI = ns.GUI

local Scenes = {}
GUI.SetupScenes = Scenes

local sin, cos, pi, floor, max, min = math.sin, math.cos, math.pi, math.floor, math.max, math.min

local ICONS  = "Interface\\Icons\\"
local MEDIA  = "Interface\\AddOns\\SuspicionsPack\\Media\\"
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local WHITE  = "Interface\\Buttons\\WHITE8X8"

-- ============================================================
-- Helpers
-- ============================================================

local function Path(icon)
    if type(icon) == "number" or icon:find("\\", 1, true) then return icon end
    return ICONS .. icon
end

-- An icon in a frame of its own, with the game's thin black edge, so a scene can
-- move or resize it as one piece.
local function Icon(parent, icon, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local edge = f:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetColorTexture(0, 0, 0, 1)
    f.edge = edge
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture(Path(icon))
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.tex = t
    return f
end

-- A round icon, as the radar and the wheel draw theirs.
local function RoundIcon(parent, icon, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture(Path(icon))
    t:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    local mask = f:CreateMaskTexture()
    mask:SetAllPoints()
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    t:AddMaskTexture(mask)
    f.tex = t
    return f
end

-- Scene text keeps its own colour (the scene's, not the theme's).
local function Text(parent, size, r, g, b, text, outline)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    GUI.ApplyFont(fs, size, outline)
    fs:SetTextColor(r, g, b, 1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    if text then fs:SetText(text) end
    return fs
end

local function Fill(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

-- Dark ground, lighter towards the top: the world behind most scenes.
local function Ground(holder)
    local t = holder:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetTexture(WHITE)
    t:SetGradient("VERTICAL", CreateColor(0.05, 0.045, 0.03, 1), CreateColor(0.18, 0.155, 0.105, 1))
    return t
end

-- The leather of the pack's frame, darkened: a screen behind the game's menus.
local function Screen(holder, shade)
    local t = holder:CreateTexture(nil, "BACKGROUND")
    t:SetAllPoints()
    t:SetTexture(MEDIA .. "Plumber\\SettingsPanelBackground.jpg")
    t:SetVertexColor(shade, shade, shade)
    return t
end

-- A dark box with a bronze edge, like a tooltip.
local function Box(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(0.03, 0.025, 0.02, 0.92)
    f:SetBackdropBorderColor(0.40, 0.32, 0.18, 1)
    return f
end

local function Ease(x)
    if x <= 0 then return 0 elseif x >= 1 then return 1 end
    return x * x * (3 - 2 * x)
end

local function Coins(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return floor(copper / 10000) .. "g"
end

local function SpellName(id, fallback)
    return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or fallback
end

local function ItemName(id, fallback)
    return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or fallback
end

local function ItemIcon(id, fallback)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or fallback
end


-- The game's own font for the game's own windows (dialogs, menus, cast bar).
local function GameText(parent, size, r, g, b, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    SP.SetFontSafe(fs, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "")
    fs:SetTextColor(r, g, b, 1)
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    if text then fs:SetText(text) end
    return fs
end

-- A module's alert text, styled from the player's own settings for it: the face,
-- size, outline and colour source the module reads.
local function AlertText(parent, db, faceKey, outlineKey)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local outline = db[outlineKey or "fontOutline"] or "OUTLINE"
    if outline == "NONE" then outline = "" end
    SP.SetFontSafe(fs, SP.ResolveFont(db[faceKey or "fontFace"] or "Expressway"), db.fontSize or 20, outline)
    local r, g, b = SP.GetColorFromSource(db.colorSource or "custom", db.color or { 1, 1, 1 })
    fs:SetTextColor(r, g, b, 1)
    return fs
end

-- The game's dialog box (StaticPopup), and one of its red buttons.
local function Dialog(parent, w, h)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32,
                    edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    return f
end

local function GameButton(parent, text, w)
    local b = parent:CreateTexture(nil, "ARTWORK")
    b:SetTexture("Interface\\Buttons\\UI-Panel-Button-Up")
    b:SetTexCoord(0, 0.625, 0, 0.6875)
    b:SetSize(w or 110, 22)
    local fs = GameText(parent, 11, 1, 0.82, 0, text)
    fs:SetPoint("CENTER", b, "CENTER", 0, 1)
    return b, fs
end

-- The game's mouse pointer, on a frame of its own above the scene's: a child frame's
-- art draws over its parent's whatever the layer, so on the scene itself the pointer
-- went under the datatext bar.
local function Pointer(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()
    f:SetFrameLevel(parent:GetFrameLevel() + 50)
    local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
    t:SetTexture("Interface\\Cursor\\Point")
    t:SetSize(28, 28)
    return t
end

-- Whether the player's minimap is round: the node radar's own test (NodeRadar.lua,
-- MinimapIsRound), EllesmereUI's minimap first, then the game's GetMinimapShape.
local function MinimapIsRound()
    local ui = EllesmereUI
    local module = type(ui) == "table" and type(ui._ModuleNS) == "table" and ui._ModuleNS.EllesmereUIMinimap
    if type(module) == "table" and type(module.MinimapShape) == "function" then
        local ok, shape = pcall(module.MinimapShape)
        if ok and (shape == "square" or shape == "rectangular") then return false end
        if ok and (shape == "circle" or shape == "textured_circle") then return true end
    end
    if GetMinimapShape then
        local ok, shape = pcall(GetMinimapShape)
        return not ok or shape == nil or shape == "ROUND"
    end
    return true
end

-- A minimap of the player's own shape, on `f`: a disc, or a square with a dark edge.
local function Minimap(f)
    local map = f:CreateTexture(nil, "ARTWORK")
    map:SetAllPoints()
    map:SetColorTexture(0.14, 0.18, 0.09, 1)
    if MinimapIsRound() then
        local mask = f:CreateMaskTexture()
        mask:SetAllPoints()
        mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        map:AddMaskTexture(mask)
    else
        local edge = f:CreateTexture(nil, "BACKGROUND")
        edge:SetPoint("TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", 1, -1)
        edge:SetColorTexture(0, 0, 0, 1)
    end
    return map
end

local function SpellIcon(id, fallback)
    return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or fallback
end

-- The first spell ID in a module's nested table of them.
local function FirstID(t)
    if type(t) == "number" then return t end
    if type(t) ~= "table" then return nil end
    for _, v in ipairs(t) do
        local id = FirstID(v)
        if id then return id end
    end
    for _, v in pairs(t) do
        local id = FirstID(v)
        if id then return id end
    end
end

-- ============================================================
-- Made for WoW: Forever
-- ============================================================

-- A real datatext bar: the player's first bar (or the default one), painted by the
-- module's own skin (DT.Skins.Apply), its slots' texts from the providers themselves
-- (pure reads: the character's own durability, gold and clock), label and value
-- coloured and set in the font the settings name. The pointer moves along it and a
-- tooltip in the datatexts' colours follows.
Scenes.datatexts = function(h, w, ht)
    Screen(h, 0.42)
    local DT = SP.Datatexts
    local db = SP.GetDB().datatexts or {}
    local cfg = db.bars and db.bars[1] or DT.MakeBar({ name = "Bar 1", width = 360, height = 22, numSlots = 3,
                                                       slots = { "durability", "gold", "time" } })
    local n = max(1, cfg.numSlots or 3)
    local bw, bh = cfg.width or 360, cfg.height or 22
    local note = Text(h, 11, 0.64, 0.62, 0.58, "Your screen, with a datatext bar where you want it")
    note:SetPoint("TOPLEFT", 14, -12)

    local bar = CreateFrame("Frame", nil, h)
    bar:SetSize(bw, bh)
    bar:SetScale(min(1, (w - 40) / bw))
    bar:SetPoint("BOTTOM", h, "BOTTOM", 0, 26 / bar:GetScale())
    DT.Skins.Apply(bar, cfg.skin or "box", n, bw / n, bw, bh, cfg.openEdge or "none",
                   (cfg.bgOpacity or 100) / 100, cfg.bgFade or "none",
                   (cfg.bgFadeStrength or DT.FADE_STRENGTH) / 100, cfg.bgCustom and cfg.bgColor or nil)

    local outline = db.fontOutline == "NONE" and "" or (db.fontOutline or "")
    local labelHex = DT.Hex(SP.GetColorFromSource(db.labelSource or "class", db.labelColor))
    local valueHex = DT.Hex(SP.GetColorFromSource(db.valueSource or "custom", db.valueColor or { 0.843, 0.753, 0.639 }))
    local function Compose(id)
        local def = DT.defs[id]
        if not def then return "" end
        local o = DT.O(id)
        local ok, value, label = pcall(def.Text, o)
        if not ok or value == nil then return "" end
        label = label or def.label
        if label and o.showLabel then return labelHex .. label .. "|r " .. valueHex .. value .. "|r" end
        return valueHex .. value .. "|r"
    end
    local slots = {}
    for i = 1, n do
        local id = cfg.slots and cfg.slots[i]
        local fs = bar:CreateFontString(nil, "OVERLAY")
        SP.SetFontSafe(fs, SP.ResolveFont(db.fontFace or "Friz Quadrata TT"), db.fontSize or 12, outline)
        fs:SetShadowColor(0, 0, 0, 0.9)
        fs:SetShadowOffset(1, -1)
        fs:SetPoint("LEFT", bar, "LEFT", (i - 1) * bw / n + 4, 0)
        fs:SetWidth(bw / n - 8)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        slots[i] = { id = id, fs = fs }
    end

    -- The tooltip's colours are the datatexts': header gold, label cream, value white.
    local tip = CreateFrame("Frame", nil, h)
    tip:SetSize(200, 64)
    if SP.Skin.FOREVER then SP.Skin.PlumberBox(tip) else Fill(tip, "BACKGROUND", 0.03, 0.025, 0.02, 0.92):SetAllPoints() end
    local tHead = Text(tip, 12, 1, 0.82, 0)
    tHead:SetPoint("TOPLEFT", 10, -9)
    local tBody = Text(tip, 11, 0.843, 0.753, 0.639)
    tBody:SetPoint("TOPLEFT", tHead, "BOTTOMLEFT", 0, -5)
    tBody:SetJustifyH("LEFT")
    local tips = {
        durability = { DURABILITY or "Durability", "Each slot's wear, lowest first" },
        gold = { "Gold", (UnitName("player") or "") .. "  |cffffffff" .. Coins(GetMoney and GetMoney() or 0) .. "|r" },
        time = { "Time", "Local and server time\nClick: calendar" },
    }
    local cursor = Pointer(h)

    local t, at, tick = 0, 0, 0
    local function Point(i)
        local s = slots[i]
        local info = tips[s.id] or { s.id or "", "" }
        tHead:SetText(info[1])
        tBody:SetText(info[2])
        local x = (w - bw * bar:GetScale()) / 2 + ((i - 0.5) * bw / n) * bar:GetScale()
        tip:ClearAllPoints()
        tip:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", max(6, min(w - 206, x - 100)), 26 + bh * bar:GetScale() + 8)
        cursor:ClearAllPoints()
        cursor:SetPoint("TOPLEFT", h, "BOTTOMLEFT", x, 26 + bh * bar:GetScale() / 2)
    end
    return function(dt)
        t, tick = t + dt, tick - dt
        if at == 0 or t >= 2.4 then
            t = 0
            at = at % n + 1
            Point(at)
        end
        if tick <= 0 then
            tick = 1
            for _, s in ipairs(slots) do s.fs:SetText(Compose(s.id)) end
        end
    end
end

-- The radar as its module draws it (Modules\NodeRadar\NodeRadar.lua, "The look"): these
-- values are the module's own, and tests/test_gui.lua checks them against it. The nodes
-- are its settings page's preview samples, drawn from its data (SP.NodeRadarData): the
-- minimap's own node symbol, greyed then tinted the node's colour, the arrow tinted the
-- same, halfway in, and the distance under the nearest only. Sizes, orbit, arrows and
-- distance follow the player's own radar settings.
local RADAR = {
    iconWidth = 30, arrowSize = 16, fontSize = 12,
    arrow = MEDIA .. "NodeRadar\\arrow.png",
    samples = { { "Peacebloom", 0.9 }, { "Copper Vein", 3 }, { "Silverleaf", 5 }, { "Tin Vein", 2 },
                { "Mageroyal", 4 }, { "Silver Vein", 0.1 }, { "Briarthorn", 5.6 }, { "Iron Deposit", 1.5 } },
}
Scenes.radarLook = RADAR

Scenes.noderadar = function(h, w, ht)
    Ground(h)
    local Data = SP.NodeRadarData
    local db = SP.GetDB().nodeRadar or {}
    local center = CreateFrame("Frame", nil, h)
    center:SetSize(1, 1)
    center:SetPoint("CENTER", h, "CENTER", -40, -4)

    -- The minimap, with Find Herbs on. Nothing in the middle: the radar draws nothing
    -- there, your character stands there.
    local mm = CreateFrame("Frame", nil, h)
    mm:SetSize(74, 74)
    mm:SetPoint("TOPRIGHT", -18, -16)
    Minimap(mm)
    local finder = RoundIcon(mm, (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(2383)) or "INV_Misc_Flower_02", 22)
    finder:SetPoint("CENTER")
    local fl = Text(h, 11, 0.55, 0.52, 0.47, SpellName(2383, "Find Herbs"))
    fl:SetPoint("TOP", mm, "BOTTOM", 0, -8)
    local walk = Text(h, 11, 0.64, 0.62, 0.58, "Walk, and the needles turn with you")
    walk:SetPoint("BOTTOMLEFT", 14, 12)

    local unit = GetLocale() == "frFR" and "m" or "yd"
    local count = min(db.maxNodes or 3, #RADAR.samples)
    local orbit = db.orbit or 70
    local full = floor(RADAR.iconWidth * (db.scale or 100) / 100 + 0.5)
    -- The arrows halfway from the middle to the nearest icon's edge, as the module has them.
    local at = max(0, (orbit - full / 2) / 2)
    local nodes = {}
    for i = 1, count do
        local sample = RADAR.samples[i]
        local info = Data.nodes[Data.Key(sample[1])]
        local symbol = Data.symbol[info.kind]
        local part = i == 1 and 1 or (db.otherScale or 70) / 100
        local width = floor(full * part + 0.5)
        local icon = center:CreateTexture(nil, "ARTWORK", nil, i == 1 and 2 or 1)
        icon:SetAtlas(symbol.atlas)
        icon:SetDesaturated(true)
        icon:SetVertexColor(info.r, info.g, info.b)
        icon:SetSize(width, floor(width * symbol.ratio + 0.5))
        local node = { way = sample[2], icon = icon }
        if db.showArrows ~= false then
            local size = floor(RADAR.arrowSize * (db.arrowScale or 100) / 100 * part + 0.5)
            node.arrow = center:CreateTexture(nil, "ARTWORK")
            node.arrow:SetTexture(RADAR.arrow)
            node.arrow:SetSize(size, size)
            node.arrow:SetVertexColor(info.r, info.g, info.b)
        end
        nodes[i] = node
    end
    local label
    if db.showDistance ~= false and nodes[1] then
        label = center:CreateFontString(nil, "OVERLAY")
        SP.SetFontSafe(label, SP.ResolveFont("Expressway"), RADAR.fontSize, "OUTLINE")
        label:SetPoint("TOP", nodes[1].icon, "BOTTOM", 0, -1)
    end

    -- You turn slowly from side to side and walk toward the nearest node.
    local t = 0
    return function(dt)
        t = t + dt
        local facing = sin(t * 0.5) * 0.6
        for _, n in ipairs(nodes) do
            local way = n.way + facing
            local s, c = sin(way), cos(way)
            n.icon:SetPoint("CENTER", center, "CENTER", orbit * s, orbit * c)
            if n.arrow then
                n.arrow:SetPoint("CENTER", center, "CENTER", at * s, at * c)
                n.arrow:SetRotation(-way)
            end
        end
        if label then label:SetText(floor(60 - (t * 7) % 52 + 0.5) .. " " .. unit) end
    end
end

-- The game menu and the teleports beside it, laid out as the module lays them (its own
-- lists and spacing, TM.COLUMN / TELEPORTS / PORTALS / LOOK, and the player's button
-- size): the column next to the menu, the mage's teleports on the row under it, the
-- portals under those. A mage-and-shaman sample, the faction's own cities. The pointer
-- clicks the Hearthstone, the menu closes, the cast bar fills.
Scenes.teleportmenu = function(h, w, ht)
    Screen(h, 0.36)
    local TM = SP.TeleportMenu
    local look = TM.LOOK
    local size = (SP.GetDB().teleportMenu or {}).size or 36
    local step = size + look.SPACING
    -- The menu and the buttons at the module's sizes, the whole shrunk to fit the
    -- picture: five rows of large buttons ran out of it.
    local menuH = 212
    local tall = max(menuH, 5 * step - look.SPACING)
    local wide = 150 + look.GAP + 3 * step
    local scale = min(1, (ht - 20) / tall, (w - 60) / wide)
    local group = CreateFrame("Frame", nil, h)
    group:SetSize(wide, tall)
    group:SetScale(scale)
    group:SetPoint("TOPRIGHT", h, "TOPRIGHT", -40 / scale, -10 / scale)

    local menu = Box(group)
    menu:SetSize(150, menuH)
    menu:SetPoint("TOPRIGHT")
    local title = GameText(menu, 13, 1, 0.82, 0, MAINMENU_BUTTON or "Game Menu")
    title:SetPoint("TOP", 0, -10)
    local labels = { GAMEMENU_SUPPORT or "Support", GAMEMENU_OPTIONS or "Options", MACROS or "Macros",
                     LOG_OUT or "Log Out", EXIT_GAME or "Exit Game", RETURN_TO_GAME or "Return to Game" }
    for i, l in ipairs(labels) do
        local b = GameButton(menu, l, 124)
        b:SetPoint("TOP", 0, -30 - (i - 1) * 28)
    end

    -- The sample: the column's first three entries, then the faction's three cities.
    local horde = UnitFactionGroup and UnitFactionGroup("player") == "Horde"
    local from = horde and 4 or 1
    local rows = {}
    rows[1] = { TM.COLUMN[1] }
    rows[2] = { TM.COLUMN[2] }
    rows[3] = { TM.COLUMN[3] }
    rows[4], rows[5] = {}, {}
    for c = 0, 2 do
        rows[4][#rows[4] + 1] = { kind = "spell", id = TM.TELEPORTS[from + c] }
        rows[5][#rows[5] + 1] = { kind = "spell", id = TM.PORTALS[from + c] }
    end
    local hearth
    for r, row in ipairs(rows) do
        for c, e in ipairs(row) do
            local b = CreateFrame("Frame", nil, group)
            b:SetSize(size, size)
            b:SetPoint("TOPRIGHT", menu, "TOPLEFT", -look.GAP - (c - 1) * step, -(r - 1) * step)
            Fill(b, "BACKGROUND", 0, 0, 0, 1):SetAllPoints()
            local icon = b:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("TOPLEFT", 1, -1)
            icon:SetPoint("BOTTOMRIGHT", -1, 1)
            icon:SetTexture(e.kind == "spell" and SpellIcon(e.id, ICONS .. "INV_Misc_QuestionMark")
                            or ItemIcon(e.id, ICONS .. "INV_Misc_Rune_01"))
            icon:SetTexCoord(look.ICON_CROP, 1 - look.ICON_CROP, look.ICON_CROP, 1 - look.ICON_CROP)
            b.hl = b:CreateTexture(nil, "HIGHLIGHT")
            b.hl:SetAllPoints(icon)
            b.hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            b.hl:SetBlendMode("ADD")
            if r == 1 then hearth = b end
        end
    end

    local cursor = Pointer(h)
    local cast = CreateFrame("Frame", nil, h)
    cast:SetSize(220, 14)
    cast:SetPoint("BOTTOM", 0, 18)
    Fill(cast, "BACKGROUND", 0, 0, 0, 0.75):SetAllPoints()
    local cfill = cast:CreateTexture(nil, "ARTWORK")
    cfill:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    cfill:SetVertexColor(1, 0.7, 0)
    cfill:SetPoint("TOPLEFT")
    cfill:SetPoint("BOTTOMLEFT")
    local cname = GameText(cast, 11, 1, 1, 1, ItemName(TM.COLUMN[1].id, "Hearthstone"))
    cname:SetPoint("CENTER")

    -- The pointer comes from the bottom left onto the Hearthstone, anchored to the button
    -- itself so it lands on it whatever the scale.
    local dx, dy = -(w - 120), -(ht - 60)
    local t = 0
    return function(dt)
        t = (t + dt) % 5.4
        local p = Ease((t - 0.5) / 1.1)
        cursor:ClearAllPoints()
        cursor:SetPoint("TOPLEFT", hearth, "CENTER", dx * (1 - p), dy * (1 - p))
        hearth.hl:SetShown(t > 1.5 and t < 2.0)
        local fade = Ease((t - 2.0) / 0.2)
        group:SetAlpha(1 - fade)
        cast:SetAlpha(fade)
        cfill:SetWidth(max(0.1, 220 * Ease((t - 2.0) / 2.6)))
    end
end

-- The real wheel at its real size: the module's own middle (glow, turning ring,
-- pointer, fire) and item images (CW.NewMiddle, CW.NewImage), its sample items, its
-- radius rule. The mouse goes round the items: each grows, lights up and draws the
-- pointer, as under the mouse in game.
Scenes.campwheel = function(h, w, ht)
    Ground(h)
    local CW = SP.CampWheel
    local look = CW.LOOK
    local c = CreateFrame("Frame", nil, h)
    c:SetSize(1, 1)
    c:SetPoint("CENTER", 0, 4)
    local middle = CW.NewMiddle(c)
    if middle.ringSpin then middle.ringSpin:Play() end

    local items = CW.SAMPLE
    local n = #items
    local radius = max(look.MIN_RADIUS, floor(n * look.ICON_SPACE / (2 * pi) + 0.5))
    local images = {}
    for i, id in ipairs(items) do
        local image = CW.NewImage(c)
        image.angle = pi / 2 - (i - 1) * 2 * pi / n
        image:SetPoint("CENTER", c, "CENTER", cos(image.angle) * radius, sin(image.angle) * radius)
        local icon = C_Item and C_Item.GetItemInfoInstant and select(5, C_Item.GetItemInfoInstant(id))
        image.icon:SetTexture(icon or ItemIcon(id, ICONS .. "INV_Misc_QuestionMark"))
        image.shine:Hide()
        images[i] = image
    end
    local name = Text(h, 12, 1, 0.82, 0)
    name:SetPoint("BOTTOM", 0, 12)

    local t, at, angle = 0, 1, images[1].angle
    return function(dt)
        t = t + dt
        if t >= 1.5 then t = 0; at = at % n + 1 end
        local light = min(1, t / 0.3)
        for i, image in ipairs(images) do
            local on = i == at
            image:SetScale(on and 1 + look.POP * min(1, t / 0.1) or 1)
            local g = on and look.GOLD_HOVER or look.GOLD
            image.ring:SetVertexColor(g[1], g[2], g[3], 1)
            image.shine:SetShown(on)
        end
        local target = images[at].angle
        local diff = (target - angle + pi) % (2 * pi) - pi
        angle = angle + diff * min(1, dt * 12)
        middle.pointer:SetRotation(angle - pi / 2)
        middle.pointer:SetAlpha(light)
        middle.glow:SetAlpha(look.GLOW_ALPHA * light)
        name:SetText(ItemName(items[at], ""))
    end
end

-- Spell macros for the player's class: Macro Action Bar's own list (SP.MAB), by ID so
-- the names are the client's own. Rank-1 Vanilla IDs if the module has none.
local CLASS_SPELLS = {
    WARRIOR = { 6673, 772, 100, 78 },    MAGE    = { 133, 116, 118, 1459 },
    PRIEST  = { 2050, 589, 17, 1243 },   SHAMAN  = { 331, 403, 8042, 324 },
    DRUID   = { 5185, 5176, 8921, 1126 }, HUNTER = { 75, 1978, 2973, 1130 },
    ROGUE   = { 1752, 2098, 1784, 921 }, WARLOCK = { 686, 172, 702, 687 },
    PALADIN = { 635, 20271, 19740, 465 },
}

local function ClassMacros(class)
    local smb, out = SP.MAB, {}
    local cfg = smb and smb.classConfigs and smb.classConfigs[class]
    for _, cat in ipairs(cfg and cfg.categories or {}) do
        for _, spell in ipairs(cat.spells or {}) do
            local id = smb.spellIDs and (smb.spellIDs[spell] or smb.spellIDs[(spell:gsub("%*", ""))])
            if type(id) == "number" and #out < 4 then out[#out + 1] = id end
        end
    end
    if #out == 0 then out = CLASS_SPELLS[class] or CLASS_SPELLS.MAGE end
    return out
end

local INK, SET = { 0.18, 0.106, 0.059 }, { 0.10, 0.38, 0.05 }

-- The page Macro Action Bar adds to the spellbook, drawn with its own pieces: its tab
-- (the spellbook tab frame and the macro icon it registers), entries with the
-- spellbook's icon frame and mask, the ink-coloured name and "Macro" under it, and the
-- glow of a macro not yet on a bar. One is dragged to the action bar, then
-- right-clicked: its Cast On menu, Mouseover picked, and the entry says Mouseover.
Scenes.macroactionbar = function(h, w, ht)
    Ground(h)
    local smb = SP.MAB or {}
    local page = h:CreateTexture(nil, "BORDER")
    page:SetTexture(WHITE)
    page:SetGradient("VERTICAL", CreateColor(0.62, 0.52, 0.36, 1), CreateColor(0.80, 0.70, 0.52, 1))
    page:SetPoint("TOPLEFT", 30, -12)
    page:SetSize(min(470, w - 110), ht - 76)

    local tab = h:CreateTexture(nil, "ARTWORK")
    tab:SetAtlas("spellbook-Tab-Frame-C60")
    tab:SetSize(44, 32)
    tab:SetPoint("TOPLEFT", page, "TOPRIGHT", 0, -14)
    local tabGlow = h:CreateTexture(nil, "ARTWORK", nil, 1)
    tabGlow:SetAtlas("spellbook-Tab-Frame-Glow-C60")
    tabGlow:SetAllPoints(tab)
    local tabIcon = h:CreateTexture(nil, "ARTWORK", nil, 2)
    tabIcon:SetTexture(smb.ICON_MACRO or "Interface\\MacroFrame\\MacroFrame-Icon")
    local tc = smb.ICON_MACRO_COORDS or { 0.15, 0.85, 0.15, 0.85 }
    tabIcon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    tabIcon:SetSize(34, 33)
    tabIcon:SetPoint("BOTTOM", tab, "BOTTOM", -1, 0)

    local _, class = UnitClass("player")
    local entries = {}
    for i, id in ipairs(ClassMacros(class)) do
        local col, row = (i - 1) % 2, floor((i - 1) / 2)
        local e = CreateFrame("Frame", nil, h)
        e:SetSize(217, 40)
        e:SetPoint("TOPLEFT", page, "TOPLEFT", 14 + col * 225, -16 - row * 56)
        local glow = e:CreateTexture(nil, "BACKGROUND")
        glow:SetAtlas("spellbook-item-unassigned-glow")
        local icon = e:CreateTexture(nil, "ARTWORK")
        icon:SetSize(36, 36)
        icon:SetPoint("LEFT", 2, 0)
        icon:SetTexture(SpellIcon(id, ICONS .. "INV_Misc_QuestionMark"))
        local mask = e:CreateMaskTexture()
        mask:SetAtlas("spellbook-item-spellicon-mask")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
        local frame = e:CreateTexture(nil, "OVERLAY")
        frame:SetAtlas("spellbook-item-iconframe")
        frame:SetPoint("TOPLEFT", icon, "TOPLEFT", -13, 3)
        frame:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 3, -9)
        glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, 5)
        glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 5, -5)
        local name = GameText(e, 14, INK[1], INK[2], INK[3], SpellName(id, "Spell"))
        name:SetShadowOffset(0, 0)
        name:SetPoint("TOPLEFT", e, "TOPLEFT", 50, -4)
        local sub = GameText(e, 11, INK[1], INK[2], INK[3], "Macro")
        sub:SetShadowOffset(0, 0)
        sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
        entries[i] = { e = e, icon = icon, glow = glow, sub = sub, id = id }
    end

    local slots = {}
    for i = 1, 6 do
        local s = h:CreateTexture(nil, "BORDER")
        s:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        s:SetSize(52, 52)
        s:SetPoint("BOTTOMLEFT", 22 + (i - 1) * 40, 0)
        slots[i] = s
    end
    local first = entries[1]
    local drag = h:CreateTexture(nil, "OVERLAY", nil, 6)
    drag:SetSize(32, 32)
    drag:SetTexture(SpellIcon(first.id, ICONS .. "INV_Misc_QuestionMark"))

    local menu = Box(h)
    menu:SetSize(140, 132)
    menu:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 22 + 2 * 40 + 44, 8)
    menu:SetFrameLevel(h:GetFrameLevel() + 12)
    local mTitle = GameText(menu, 12, 1, 0.82, 0, SpellName(first.id, "Spell"))
    mTitle:SetPoint("TOPLEFT", 10, -8)
    local mHead = GameText(menu, 11, 0.6, 0.6, 0.6, "Cast On")
    mHead:SetPoint("TOPLEFT", mTitle, "BOTTOMLEFT", 0, -4)
    local choices = { "Target", "Mouseover", "Focus", "Cursor", "Nearest Player", "Self" }
    local dots = {}
    for i, label in ipairs(choices) do
        local fs = GameText(menu, 11, 1, 1, 1, label)
        fs:SetPoint("TOPLEFT", mHead, "BOTTOMLEFT", 14, -2 - (i - 1) * 14)
        local dot = menu:CreateTexture(nil, "ARTWORK")
        dot:SetSize(7, 7)
        dot:SetPoint("RIGHT", fs, "LEFT", -5, 0)
        dot:SetTexture(CIRCLE)
        dots[i] = dot
    end

    local x0, y0 = 30 + 14 + 2 + 2, -(12 + 16 + 2)
    local x1, y1 = 22 + 2 * 40 + 10, -(ht - 42)
    local t = 0
    return function(dt)
        t = (t + dt) % 6.5
        local pulse = 0.2 + 0.8 * (0.5 + 0.5 * cos(t * pi / 0.5))
        for i, e in ipairs(entries) do e.glow:SetAlpha((i == 1 and t > 1.8) and 0 or pulse) end
        local p = Ease((t - 0.6) / 1.1)
        drag:SetPoint("TOPLEFT", h, "TOPLEFT", x0 + (x1 - x0) * p, y0 + (y1 - y0) * p)
        drag:SetShown(t > 0.5)
        local picked = t > 3.6
        menu:SetShown(t > 2.4 and t < 4.4)
        for i, dot in ipairs(dots) do
            local on = (picked and i == 2) or (not picked and i == 1)
            dot:SetVertexColor(on and 1 or 0.3, on and 0.82 or 0.3, on and 0 or 0.3)
        end
        if picked then
            first.sub:SetText("Mouseover")
            first.sub:SetTextColor(SET[1], SET[2], SET[3], 1)
        else
            first.sub:SetText("Macro")
            first.sub:SetTextColor(INK[1], INK[2], INK[3], 1)
        end
    end
end

-- A bag with Profession marks' own marks: the game's profession glyphs, chosen from the
-- module's data (SP.ProfessionItems) and drawn by the module itself (NewMarks,
-- ShowMarks), so they sit where they sit in your bags. Your professions when you
-- have some; Alchemy, Herbalism and Cooking otherwise.
local BAG = {
    { 2447, "INV_Misc_Flower_02" }, { 2589, "INV_Fabric_Linen_01" }, { 765, "INV_Misc_Herb_10" },
    { 4540, "INV_Misc_Food_11" },   { 2770, "INV_Ore_Copper_01" },  { 2318, "INV_Misc_LeatherScrap_03" },
    { 118, "INV_Potion_49" },       { 2835, "INV_Stone_04" },       { 2592, "INV_Fabric_Wool_01" },
    { 2771, "INV_Ore_Tin_01" },
}
local SAMPLE_LINES = { 171, 182, 185 }

-- [skill line] = its rank, main professions first, as the module ranks them.
local function MyLines(Data)
    local lines, rank = {}, 0
    if GetProfessions and GetProfessionInfo then
        local p1, p2, firstAid, fishing, cooking = GetProfessions()
        local order = { p1, p2, cooking, firstAid, fishing }
        for i = 1, 5 do
            local index = order[i]
            if index then
                local line = select(7, GetProfessionInfo(index))
                line = line and (Data.parents[line] or line)
                if line and Data.atlases[line] and not lines[line] then
                    rank = rank + 1
                    lines[line] = rank
                end
            end
        end
    end
    if rank == 0 then
        for i, line in ipairs(SAMPLE_LINES) do lines[line] = i end
    end
    return lines
end

-- The glyphs of the professions that use an item as a reagent, best ranked first.
local function MarksFor(Data, itemID, lines)
    local wanted = {}
    for line in pairs(Data.reagents[itemID] or {}) do
        if lines[line] then wanted[#wanted + 1] = line end
    end
    if #wanted == 0 then return nil end
    table.sort(wanted, function(a, b) return lines[a] < lines[b] end)
    local marks = {}
    for i, line in ipairs(wanted) do marks[i] = Data.atlases[line] end
    return marks
end

Scenes.professionmarks = function(h, w, ht)
    Ground(h)
    local Data, PM = SP.ProfessionItems, SP.ProfessionMarks
    local lines = MyLines(Data)
    local size = min(36, floor((w - 40) / 5) - 6)
    local gridW = 5 * (size + 6) - 6
    local x0, y0 = (w - gridW) / 2, -(ht - 2 * (size + 6)) / 2
    local slots = {}
    for i, item in ipairs(BAG) do
        local col, row = (i - 1) % 5, floor((i - 1) / 5)
        local f = Icon(h, ItemIcon(item[1], item[2]), size)
        f:SetPoint("TOPLEFT", h, "TOPLEFT", x0 + col * (size + 6), y0 - row * (size + 6))
        slots[i] = { marks = MarksFor(Data, item[1], lines), slot = PM.NewMarks(f) }
    end
    -- The marks come one slot after another, stay, and go.
    local t = 0
    return function(dt)
        t = (t + dt) % 5
        for i, s in ipairs(slots) do
            PM.ShowMarks(s.slot, (t > 0.3 * i and t < 4.3) and s.marks or nil)
        end
    end
end

-- The four macros on an action bar, under the names the module gives them (CM.MACROS),
-- each showing the item it would use now: from the module's data, a lower item, then
-- the better one picked up later. Drink only, as the food-and-drink macro is by default.
local UPGRADES = { { 159, 1179 }, { 2680, 724 }, { 1251, 2581 }, { 118, 858 } }

Scenes.consumablemacros = function(h, w, ht)
    Ground(h)
    local names = SP.ConsumableMacros.MACROS
    local data = SP.ConsumableData or {}
    local size = 36
    local gap = min(26, (w - 4 * size) / 5)
    local x0 = (w - (4 * size + 3 * gap)) / 2
    local buttons = {}
    for i, name in ipairs(names) do
        local slot = h:CreateTexture(nil, "BORDER")
        slot:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        slot:SetSize(size * 64 / 36, size * 64 / 36)
        local b = CreateFrame("Frame", nil, h)
        b:SetSize(size, size)
        b:SetPoint("TOPLEFT", h, "TOPLEFT", x0 + (i - 1) * (size + gap), -(ht / 2 - size / 2 - 4))
        slot:SetPoint("CENTER", b, "CENTER")
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.flash = b:CreateTexture(nil, "OVERLAY")
        b.flash:SetAllPoints()
        b.flash:SetTexture(WHITE)
        b.flash:SetBlendMode("ADD")
        b.flash:SetAlpha(0)
        -- An action button shows a macro's name along its bottom edge.
        local label = GameText(b, 10, 1, 1, 1, name)
        label:SetPoint("BOTTOM", b, "BOTTOM", 0, 2)
        b.items = UPGRADES[i]
        b.known = data[UPGRADES[i][1]] ~= nil
        buttons[i] = b
    end
    local function Show(b, better)
        local id = b.items[better and 2 or 1]
        b.icon:SetTexture(ItemIcon(id, ICONS .. "INV_Misc_QuestionMark"))
    end
    for _, b in ipairs(buttons) do Show(b, false) end
    local t, at, better = 0, 0, false
    return function(dt)
        t = t + dt
        if t >= 1.2 then
            t = 0
            at = at % #buttons + 1
            if at == 1 then better = not better end
            Show(buttons[at], better)
        end
        for i, b in ipairs(buttons) do b.flash:SetAlpha(i == at and max(0, 0.5 - t) or 0) end
    end
end

-- An item tooltip with Classic's two spell lines, damage and healing, then healing only:
-- the client's own sentences, then what Simple item stats writes for each (SS.Example,
-- the module's own shortening), so the words are the client's: "Puissance des sorts" and
-- "Soins des sorts" on a French client.
Scenes.simplestats = function(h, w, ht)
    Ground(h)
    local SS = SP.SimpleStats
    local function Line(value, key, long, short)
        local before, after
        if SS and SS.Example then before, after = SS.Example(value, key) end
        return before or long, after or short
    end
    local powerLong, powerShort = Line(12, nil,
        "Equip: Increases damage and healing done by magical spells and effects by up to 12.", "+12 Spell Power")
    local healLong, healShort = Line(22, "SPELL_HEALING_INCREASE",
        "Equip: Increases healing done by magical spells and effects by up to 22.", "+22 Spell Healing")

    local tipW = min(262, w - 24)
    local tip = Box(h)
    tip:SetWidth(tipW)
    tip:SetPoint("TOP", 0, -10)
    local name = Text(tip, 13, 0.64, 0.21, 0.93, ItemName(14152, "Robe of the Archmage"))
    name:SetPoint("TOPLEFT", 9, -8)
    local kind = Text(tip, 11, 1, 1, 1, (INVTYPE_ROBE or "Chest") .. "    " .. (ARMOR or "Armor"))
    kind:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    local power = Text(tip, 11, 0.12, 1, 0.12)
    power:SetPoint("TOPLEFT", kind, "BOTTOMLEFT", 0, -5)
    local heal = Text(tip, 11, 0.12, 1, 0.12)
    heal:SetPoint("TOPLEFT", power, "BOTTOMLEFT", 0, -3)
    for _, fs in ipairs({ power, heal }) do
        fs:SetWidth(tipW - 18)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
    end
    local tag = Text(h, 10.5, 0.55, 0.52, 0.47)
    tag:SetPoint("TOP", tip, "BOTTOM", 0, -4)

    local shown
    local function Show(short)
        if shown == short then return end
        shown = short
        power:SetText(short and powerShort or powerLong)
        heal:SetText(short and healShort or healLong)
        tag:SetText(short and "With Simple item stats" or "Without")
        tip:SetHeight(8 + 13 + 3 + 12 + 5 + math.ceil(power:GetStringHeight() or 12) + 3
                      + math.ceil(heal:GetStringHeight() or 12) + 9)
    end
    Show(false)
    local t = 0
    return function(dt)
        t = (t + dt) % 6
        Show(t >= 3)
        local a = (t % 3) / 0.3
        power:SetAlpha(a > 1 and 1 or a)
        heal:SetAlpha(a > 1 and 1 or a)
    end
end

-- A Details! window in the module's Forever skin (DS.FOREVER_SKIN, DS.BuildTitleArt,
-- DS.LOOK): its title art and gold title, rows of its height and gap, the class icons
-- of its sheet in their ring, the slab and the warmed stone track, the text in its font
-- and place. The bars race.
local CLASS_COORDS = {
    WARRIOR = { 0, 0.125, 0, 0.125 },     MAGE    = { 0.125, 0.248, 0, 0.125 },
    ROGUE   = { 0.248, 0.371, 0, 0.125 }, DRUID   = { 0.371, 0.494, 0, 0.125 },
    HUNTER  = { 0, 0.125, 0.125, 0.25 },  SHAMAN  = { 0.125, 0.248, 0.125, 0.25 },
    PRIEST  = { 0.248, 0.371, 0.125, 0.25 }, WARLOCK = { 0.371, 0.494, 0.125, 0.25 },
    PALADIN = { 0, 0.125, 0.25, 0.375 },
}

Scenes.detailsskin = function(h, w, ht)
    Ground(h)
    local DS = SP.DetailsSkin
    local props = DS.FOREVER_SKIN.instance_cprops
    local ri, look = props.row_info, DS.LOOK
    local rowH, gap = ri.height, ri.space.between
    local left = ri.row_offsets.left
    local ww = min(245, w - 20)
    local rows = 4
    local win = CreateFrame("Frame", nil, h)
    win:SetSize(ww, props.titlebar_height + rows * (rowH + gap))
    win:SetPoint("CENTER", 0, 2)

    local titleBar = CreateFrame("Frame", nil, win)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(props.titlebar_height)
    DS.BuildTitleArt(titleBar)
    local title = titleBar:CreateFontString(nil, "OVERLAY")
    SP.SetFontSafe(title, SP.ResolveFont("Expressway"), props.attribute_text.text_size or 12, "")
    title:SetTextColor(1, 0.82, 0, 1)
    title:SetPoint("BOTTOMLEFT", titleBar, "BOTTOMLEFT", 21, 17)
    title:SetText(DAMAGE or "Damage Done")

    local fontSize = ri.font_size or 11
    local cls = { "MAGE", "WARRIOR", "ROGUE", "PRIEST" }
    local names = { "Mirelle", "Brokk", "Thalor", "Aelis" }
    local track = ri.fixed_texture_background_color
    local barW = ww - left - 4
    local bars = {}
    local coords = Details and Details.class_coords
    for i = 1, rows do
        local row = CreateFrame("Frame", nil, win)
        row:SetSize(barW, rowH)
        row:SetPoint("TOPLEFT", win, "TOPLEFT", left, -(props.titlebar_height + (i - 1) * (rowH + gap)))
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(ri.texture_background_file)
        bg:SetVertexColor(track[1], track[2], track[3], track[4] or 1)
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls[i]] or { r = 0.6, g = 0.6, b = 0.6 }
        local fill = row:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT")
        fill:SetPoint("BOTTOMLEFT")
        fill:SetTexture(ri.texture_file)
        fill:SetVertexColor(cc.r, cc.g, cc.b)
        local icon = row:CreateTexture(nil, "OVERLAY", nil, 5)
        icon:SetSize(look.ICON_SIZE, look.ICON_SIZE)
        icon:SetPoint("LEFT", row, "LEFT", look.ICON_LEFT, 0)
        icon:SetTexture(ri.icon_file)
        local tc = coords and coords[cls[i]] or CLASS_COORDS[cls[i]]
        icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        local mask = row:CreateMaskTexture()
        mask:SetTexture(ri.icon_mask, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
        local ring = row:CreateTexture(nil, "OVERLAY", nil, look.RING_SUBLEVEL)
        ring:SetAtlas(look.RING_ATLAS)
        ring:SetSize(look.RING_SIZE, look.RING_SIZE)
        ring:SetPoint("CENTER", icon, "CENTER")
        local lt = row:CreateFontString(nil, "OVERLAY")
        SP.SetFontSafe(lt, SP.ResolveFont("Expressway"), fontSize, "")
        lt:SetPoint("LEFT", row, "LEFT", ri.textL_offset or 2, ri.text_yoffset or 5)
        lt:SetText(i .. ". " .. names[i])
        local rt = row:CreateFontString(nil, "OVERLAY")
        SP.SetFontSafe(rt, SP.ResolveFont("Expressway"), fontSize, "")
        rt:SetPoint("RIGHT", row, "RIGHT", -2, ri.text_yoffset or 5)
        bars[i] = { fill = fill, rt = rt, base = 1 - (i - 1) * 0.17 }
    end
    local t = 0
    return function(dt)
        t = t + dt
        for i, b in ipairs(bars) do
            local f = max(0.1, min(1, b.base + 0.06 * sin(t * 1.3 + i)))
            b.fill:SetWidth(barW * f)
            b.rt:SetText(("%.1fK"):format(f * 41.2))
        end
    end
end

-- ============================================================
-- Everyday
-- ============================================================

-- The countdown as the module writes it: "No <spell>" over the time left, at its
-- precision, in the player's font settings, no icon; gone when the spell is back. The
-- class's own movement spell (the module's table), Blink for a class without one.
Scenes.movementalert = function(h, w, ht)
    Ground(h)
    local MA = SP.MovementAlert or {}
    local db = SP.GetDB().movementAlert or {}
    local _, class = UnitClass("player")
    local list = MA.IS_FOREVER and MA.ForeverMovementAbilities or MA.MovementAbilities
    local id = FirstID(list and list[class]) or 1953
    local fs = AlertText(h, db, "fontFace", "outline")
    fs:SetShadowColor(0, 0, 0, db.shadowAlpha or 1)
    fs:SetShadowOffset(db.shadowX or 1, db.shadowY or -1)
    fs:SetPoint("CENTER")
    fs:SetJustifyH("CENTER")
    local fmt = "%." .. (db.precision or 0) .. "f"
    local head = (db.customText and db.customText ~= "") and db.customText or ("No " .. SpellName(id, "Blink"))
    local left = 8
    return function(dt)
        left = left - dt
        if left <= 0 then
            fs:SetText("")
            if left < -1 then left = 8 end
        else
            fs:SetText(head .. "\n" .. fmt:format(left))
        end
    end
end

-- The line as the module composes it: its text, the interrupted spell's icon at the
-- font's size, the spell's name; shown for its duration, then gone. Counterspell, as
-- the module's own preview.
Scenes.interruptalert = function(h, w, ht)
    Ground(h)
    local db = SP.GetDB().interruptAlert or {}
    local fs = AlertText(h, db)
    fs:SetPoint("CENTER")
    local size = db.fontSize or 20
    local name = SpellName(2139, "Counterspell")
    local icon = SpellIcon(2139, ICONS .. "Spell_Frost_IceShock")
    local line = db.showIcon ~= false
        and ("%s |T%s:%d:%d:0:0:64:64:5:59:5:59|t %s"):format(db.text or "Interrompu", tostring(icon), size, size, name)
        or ((db.text or "Interrompu") .. " " .. name)
    fs:SetText(line)
    local shown = db.duration or 3
    local t = 0
    return function(dt)
        t = (t + dt) % (shown + 1)
        fs:SetShown(t < shown)
    end
end

-- The death line as the module writes it: the name in its class colour, then its text
-- in white, in its font and size, outlined, no shadow; in over 0.3 s, held, out over 1 s.
Scenes.deathalert = function(h, w, ht)
    Ground(h)
    local db = SP.GetDB().deathAlert or {}
    local fs = h:CreateFontString(nil, "OVERLAY")
    SP.SetFontSafe(fs, SP.ResolveFont(db.fontName or "Expressway"), db.fontSize or 28, "OUTLINE")
    fs:SetShadowOffset(0, 0)
    fs:SetPoint("CENTER")
    local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS.WARRIOR
    local hex = cc and cc.colorStr or "ffc69b6d"
    fs:SetText("|c" .. hex .. "Brokk|r |cffffffff" .. (db.displayText or "died") .. "|r")
    local hold = db.messageDuration or 4
    local t = 0
    return function(dt)
        t = (t + dt) % (hold + 2)
        local a
        if t < 0.3 then a = t / 0.3
        elseif t < 0.3 + hold then a = 1
        else a = max(0, 1 - (t - 0.3 - hold)) end
        fs:SetAlpha(a)
    end
end

-- The warning as the module shows it: its text, font and colour, pulsing from full to
-- a quarter and back every 0.6 s.
Scenes.durability = function(h, w, ht)
    Ground(h)
    local db = SP.GetDB().durability or {}
    local fs = AlertText(h, db)
    fs:SetPoint("CENTER")
    fs:SetText(db.warningText or "REPAIR NOW")
    local t = 0
    return function(dt)
        t = t + dt
        local p = (t % 1.2) / 0.6
        if p > 1 then p = 2 - p end
        fs:SetAlpha(1 - 0.75 * Ease(p))
    end
end

-- At a merchant with its chores ticked: the grey items go, the gold counts up, the
-- gear is mended. The module writes nothing; this is what you see happen.
Scenes.automation = function(h, w, ht)
    Ground(h)
    local junk = { 7073, 4865, 7074 }
    local icons = {}
    for i, id in ipairs(junk) do
        local f = Icon(h, ItemIcon(id, ICONS .. "INV_Misc_Bone_01"), 28)
        f:SetPoint("LEFT", 16 + (i - 1) * 34, 6)
        f.edge:SetColorTexture(0.62, 0.62, 0.62, 1)
        icons[i] = f
    end
    local money = Text(h, 13, 1, 1, 1)
    money:SetPoint("LEFT", 130, 6)
    local repair = Text(h, 11, 0.64, 0.62, 0.58)
    repair:SetPoint("TOPLEFT", money, "BOTTOMLEFT", 0, -6)
    local note = Text(h, 10.5, 0.55, 0.52, 0.47, "At a merchant, with its chores ticked")
    note:SetPoint("BOTTOMLEFT", 14, 8)
    local base = GetMoney and GetMoney() or 1284330
    local t = 0
    return function(dt)
        t = (t + dt) % 4.5
        local sold = 0
        for i, f in ipairs(icons) do
            local gone = Ease((t - 0.4 * i) / 0.25)
            f:SetAlpha(1 - gone)
            if gone >= 1 then sold = sold + 1 end
        end
        money:SetText(Coins(base + sold * 1874))
        repair:SetText(t > 2 and ((DURABILITY or "Durability") .. " |cff6fbf5a100%|r") or ((DURABILITY or "Durability") .. " |cffff404023%|r"))
    end
end

-- A loot window that empties the moment it opens.
Scenes.fastloot = function(h, w, ht)
    Ground(h)
    local win = Box(h)
    win:SetSize(150, 72)
    win:SetPoint("CENTER")
    local loot = { { 2589, "INV_Fabric_Linen_01" }, { 2770, "INV_Ore_Copper_01" } }
    local rows = {}
    for i, it in ipairs(loot) do
        local r = CreateFrame("Frame", nil, win)
        r:SetSize(140, 20)
        local ic = Icon(r, ItemIcon(it[1], it[2]), 18)
        ic:SetPoint("LEFT", 2, 0)
        local fs = GameText(r, 11, 1, 1, 1, ItemName(it[1], ""))
        fs:SetPoint("LEFT", ic, "RIGHT", 6, 0)
        rows[i] = r
    end
    local coin = CreateFrame("Frame", nil, win)
    coin:SetSize(140, 20)
    local cfs = GameText(coin, 11, 1, 1, 1, Coins(4211))
    cfs:SetPoint("LEFT", 26, 0)
    rows[#rows + 1] = coin
    local t = 0
    return function(dt)
        t = (t + dt) % 3.2
        for i, r in ipairs(rows) do
            local p = Ease((t - 0.6 - 0.1 * i) / 0.2)
            r:SetPoint("TOPLEFT", win, "TOPLEFT", 5 + 40 * p, -4 - (i - 1) * 22)
            r:SetAlpha(1 - p)
        end
        win:SetAlpha(t > 1.3 and max(0, 1 - (t - 1.3) / 0.25) or 1)
    end
end

-- Ctrl+C over a tooltip: the game's own dialog opens, titled as the module titles it,
-- the ID in its box, selected.
Scenes.copytooltip = function(h, w, ht)
    Ground(h)
    local itemName = ItemName(2447, "Peacebloom")
    local tip = Box(h)
    tip:SetSize(120, 38)
    tip:SetPoint("LEFT", 12, 10)
    local name = GameText(tip, 12, 1, 1, 1, itemName)
    name:SetPoint("TOPLEFT", 8, -6)
    local sub = GameText(tip, 10.5, 1, 0.82, 0, "Ctrl+C")
    sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)

    local dlg = Dialog(h, 300, 104)
    dlg:SetScale(min(1, (w - 20) / 300, (ht - 6) / 104))
    dlg:SetPoint("CENTER", h, "CENTER", 0, 0)
    dlg:SetFrameLevel(h:GetFrameLevel() + 10)
    local title = GameText(dlg, 13, 1, 1, 1, "Ctrl+C  \226\128\148  " .. itemName)
    title:SetPoint("TOP", 0, -18)
    local box = CreateFrame("Frame", nil, dlg)
    box:SetSize(180, 20)
    box:SetPoint("TOP", title, "BOTTOM", 0, -8)
    local mid = box:CreateTexture(nil, "BACKGROUND")
    mid:SetAllPoints()
    mid:SetTexture("Interface\\Common\\Common-Input-Border")
    mid:SetTexCoord(0.0625, 0.9375, 0, 0.625)
    local sel = Fill(box, "BORDER", 0.2, 0.4, 0.9, 0.6)
    sel:SetSize(30, 14)
    sel:SetPoint("LEFT", 6, 0)
    local id = GameText(box, 12, 1, 1, 1, "2447")
    id:SetPoint("LEFT", 7, 0)
    local btn = GameButton(dlg, CLOSE or "Close", 90)
    btn:SetPoint("BOTTOM", 0, 14)

    local t = 0
    return function(dt)
        t = (t + dt) % 4
        tip:SetShown(t < 1.4)
        dlg:SetShown(t >= 1.4)
        sub:SetAlpha(t > 0.7 and 1 or 0.3)
    end
end

-- The drawer: the module's own tab on the minimap's left (its Forever art, Drawer.
-- DrawForeverTab, or its flat grey on retail), its panel, the buttons in its grid with
-- no border. The pointer hovers the tab: the panel shows at once; it leaves: the panel
-- goes 0.3 s later, as in game.
Scenes.drawer = function(h, w, ht)
    Ground(h)
    local db = SP.GetDB().drawer or {}
    local mm = CreateFrame("Frame", nil, h)
    mm:SetSize(ht - 24, ht - 24)
    mm:SetPoint("RIGHT", -16, 0)
    Minimap(mm)

    local tab = CreateFrame("Frame", nil, h)
    tab:SetSize(db.tabW or 6, db.tabH or 40)
    tab:SetPoint("CENTER", mm, "LEFT", 0, 0)
    if SP.Skin.FOREVER and SP.Drawer and SP.Drawer.DrawForeverTab then
        SP.Drawer.DrawForeverTab(tab)
    else
        local c = db.tabColor or { 0.6, 0.6, 0.6 }
        Fill(tab, "ARTWORK", c[1], c[2], c[3], 1):SetAllPoints()
        local edge = Fill(tab, "BACKGROUND", 0, 0, 0, 1)
        edge:SetPoint("TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", 1, -1)
    end

    local size, pad, margin = db.btnSize or 26, db.btnPad or 6, 10
    local icons = { "INV_Misc_Book_09", "INV_Misc_Bag_07", "INV_Misc_Gear_01", "Spell_Nature_Lightning" }
    local panel = CreateFrame("Frame", nil, h)
    panel:SetSize(2 * margin + #icons * (size + pad) - pad, 2 * margin + size)
    panel:SetPoint("RIGHT", tab, "LEFT", -2, 0)
    if SP.Skin.FOREVER then
        SP.Skin.PlumberBox(panel)
    else
        Fill(panel, "BACKGROUND", 0.06, 0.06, 0.06, 0.95):SetAllPoints()
    end
    for i, ic in ipairs(icons) do
        local b = panel:CreateTexture(nil, "ARTWORK")
        b:SetSize(db.iconSize or 18, db.iconSize or 18)
        b:SetPoint("CENTER", panel, "TOPLEFT", margin + (i - 1) * (size + pad) + size / 2, -(margin + size / 2))
        b:SetTexture(ICONS .. ic)
    end
    local cursor = Pointer(h)
    local t = 0
    return function(dt)
        t = (t + dt) % 4
        local over = t > 0.8 and t < 2.8
        cursor:SetPoint("TOPLEFT", tab, "CENTER", over and 0 or 30, over and 0 or -30)
        panel:SetShown(t > 0.8 and t < 2.8 + (db.hideDelay or 0.3))
    end
end

-- ============================================================
-- Group play (retail)
-- ============================================================

-- The alert as the module shows it: its text and colour, no icon, for 5 s.
Scenes.potionalert = function(h, w, ht)
    Ground(h)
    local db = SP.GetDB().potionAlert or {}
    local fs = AlertText(h, db)
    fs:SetPoint("CENTER")
    fs:SetText(db.displayText or "Potion Ready")
    local shown = db.displayDuration or 5
    local t = 0
    return function(dt)
        t = (t + dt) % (shown + 1)
        fs:SetShown(t < shown)
    end
end

-- The timer as the module draws it: its dark box, the seconds left, BLOODLUST under
-- them, the thin red bar running down from 40 (here five times faster).
Scenes.bloodlustalert = function(h, w, ht)
    Ground(h)
    local box = CreateFrame("Frame", nil, h, "BackdropTemplate")
    box:SetSize(80, 52)
    box:SetPoint("CENTER")
    box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    box:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    box:SetBackdropBorderColor(0.15, 0.15, 0.15, 0.85)
    local num = box:CreateFontString(nil, "OVERLAY")
    SP.SetFontSafe(num, SP.ResolveFont("Expressway"), 22, "OUTLINE")
    num:SetPoint("TOP", 0, -6)
    local label = box:CreateFontString(nil, "OVERLAY")
    SP.SetFontSafe(label, SP.ResolveFont("Expressway"), 9, "")
    label:SetTextColor(0.85, 0.85, 0.85, 0.7)
    label:SetPoint("BOTTOM", 0, 8)
    label:SetText("BLOODLUST")
    local track = Fill(box, "BORDER", 0.2, 0.2, 0.2, 1)
    track:SetPoint("BOTTOMLEFT", 1, 1)
    track:SetPoint("BOTTOMRIGHT", -1, 1)
    track:SetHeight(3)
    local fill = Fill(box, "ARTWORK", 0.93, 0.27, 0.27, 1)
    fill:SetPoint("BOTTOMLEFT", 1, 1)
    fill:SetHeight(3)
    local left = 40
    return function(dt)
        left = left - dt * 5
        if left <= 0 then left = 40 end
        num:SetText(math.ceil(left))
        fill:SetWidth(max(0.1, 78 * left / 40))
    end
end

-- The game's death dialog, released by the module 2 s later; then the resurrection
-- request, accepted. It writes nothing of its own.
Scenes.autorelease = function(h, w, ht)
    Ground(h)
    local dlg = Dialog(h, 300, 90)
    dlg:SetScale(min(1, (w - 20) / 300, (ht - 6) / 90))
    dlg:SetPoint("CENTER")
    local text = GameText(dlg, 13, 1, 0.82, 0)
    text:SetPoint("TOP", 0, -22)
    local button, label = GameButton(dlg, "", 140)
    button:SetPoint("BOTTOM", 0, 16)
    local delay = (SP.GetDB().autoRelease or {}).delay or 2
    local t = 0
    return function(dt)
        t = (t + dt) % (2 * delay + 3)
        local first = t < delay + 1.5
        text:SetText(first and (DEATH_RELEASE_NOTIMER or "You died.") or "Brokk wants to resurrect you.")
        label:SetText(first and (DEATH_RELEASE or "Release Spirit") or (ACCEPT or "Accept"))
        local stage = first and t or t - (delay + 1.5)
        dlg:SetShown(stage < delay)
    end
end

-- The module's panel at the auction house: its title bar and logo, a row per item with
-- what you hold of what you want and its Buy button; then the purchase line.
Scenes.autobuy = function(h, w, ht)
    Ground(h)
    local T = GUI.T
    local panel = CreateFrame("Frame", nil, h, "BackdropTemplate")
    panel:SetSize(240, 82)
    panel:SetPoint("TOP", 0, -6)
    panel:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    panel:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.8)
    panel:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    local bar = Fill(panel, "BORDER", T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(22)
    local title = panel:CreateFontString(nil, "OVERLAY")
    SP.SetFontSafe(title, SP.ResolveFont("Expressway"), 13, "OUTLINE")
    title:SetPoint("LEFT", bar, "LEFT", 8, 0)
    title:SetText("|cffe40f38Auto|r|cffffffffBuy|r")
    local items = { { 191383, "INV_Potion_54", 3 }, { 197784, "INV_Misc_Food_14", 8 } }
    local counts = {}
    for i, it in ipairs(items) do
        local y = -26 - (i - 1) * 26
        local ic = Icon(panel, ItemIcon(it[1], it[2]), 20)
        ic:SetPoint("TOPLEFT", 8, y)
        local nm = panel:CreateFontString(nil, "OVERLAY")
        SP.SetFontSafe(nm, SP.ResolveFont("Expressway"), 10, "OUTLINE")
        nm:SetPoint("LEFT", ic, "RIGHT", 6, 0)
        nm:SetText(ItemName(it[1], "Potion"))
        local q = panel:CreateFontString(nil, "OVERLAY")
        SP.SetFontSafe(q, SP.ResolveFont("Expressway"), 10, "OUTLINE")
        q:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        q:SetPoint("RIGHT", panel, "TOPRIGHT", -52, y - 10)
        local buy = panel:CreateFontString(nil, "OVERLAY")
        SP.SetFontSafe(buy, SP.ResolveFont("Expressway"), 9, "")
        buy:SetTextColor(0.3, 0.8, 0.4, 1)
        buy:SetPoint("RIGHT", panel, "TOPRIGHT", -12, y - 10)
        buy:SetText("Buy")
        counts[i] = { q = q, have = it[3] }
    end
    local toast = h:CreateFontString(nil, "OVERLAY")
    SP.SetFontSafe(toast, SP.ResolveFont("Expressway"), 12, "OUTLINE")
    toast:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    toast:SetPoint("TOP", panel, "BOTTOM", 0, -4)
    local t = 0
    return function(dt)
        t = (t + dt) % 4
        local bought = t > 1.6
        counts[1].q:SetText((bought and 20 or counts[1].have) .. "|cff888888/|r20")
        counts[2].q:SetText(counts[2].have .. "|cff888888/|r20")
        toast:SetText(bought and (ItemName(items[1][1], "Potion") .. " purchased \195\15117 for " .. Coins(170000)) or "")
    end
end
