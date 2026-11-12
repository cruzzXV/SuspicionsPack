-- SuspicionsPack Options — the setup tour
--
-- Every module ships switched off, so a player who has just installed the pack
-- sees nothing happen. This tour opens once, at the first login of a fresh
-- install (Core.lua, SP.CheckChangelog, in place of "What's new"), and walks
-- through the features a step at a time: an animated scene of what each one does
-- (Core\SetupScenes.lua), a sentence, and the same switch as the top of its page.
-- /spack setup and the Home page bring it back.
--
-- The shape is ElvUI's installer: a list of steps on the side that can be
-- clicked, Back and Next, an "n / N" progress bar, and every step skippable.
-- Nothing is copied from it.
--
-- One list of steps for both clients: a feature whose page this client does not
-- load drops out, and a step left with no feature drops out with it. On Forever
-- that leaves the Forever steps and the everyday ones; on retail, the everyday
-- ones and "Group play".

local ADDON, ns = ...

local SP  = SuspicionsPack
local GUI = ns.GUI
local W   = GUI.W

-- ============================================================
-- What the tour shows
-- ============================================================

-- Per feature, keyed by its options page id: the module its switch refreshes
-- (the name the page hands GUI.ModulePage), its icon, and the sentence a step
-- shows (`text` on a step of its own, `line` under a smaller scene). The scene
-- is GUI.SetupScenes[page id].
local FEATURES = {
    datatexts        = { module = "Datatexts",        icon = "INV_Misc_Coin_01",
        text = "Small live bars for your gold, durability, the clock, your guild and your friends, and more. " ..
               "Hover one for details; most open their window when clicked. Put them anywhere." },
    noderadar        = { module = "NodeRadar",        icon = "INV_Misc_Flower_02",
        text = "The nearest herbs and veins circle your character like compass needles, each one turned " ..
               "toward its node, the closest one larger. Needs Find Herbs or Find Minerals on." },
    teleportmenu     = { module = "TeleportMenu",     icon = "INV_Misc_Rune_01",
        text = "Press Escape and your teleports wait beside the game menu: Hearthstone, Astral Recall, " ..
               "Moonglade, engineering trinkets, and every mage teleport and portal you know. One click casts it." },
    campwheel        = { module = "CampWheel",        icon = "Interface\\AddOns\\SuspicionsPack\\Media\\CampWheel\\campfire.png",
        text = "Stand near a campfire and a ring of the camp items you can use right now opens around it. " ..
               "Click one to use it. It stays hidden in combat and on a mount." },
    macroactionbar   = { module = "MacroActionBar",   icon = "Spell_Nature_Lightning",
        text = "A spellbook tab with a ready-made macro for each of your spells. Drag them to your bars, then " ..
               "right-click one to choose who it casts on: your mouseover, your focus, yourself." },
    professionmarks  = { module = "ProfessionMarks",  icon = "Trade_Alchemy",
        line = "Your professions' icons on the bag items they use." },
    consumablemacros = { module = "ConsumableMacros", icon = "INV_Drink_07",
        line = "Four macros that always use your best drink, food, bandage and potion." },
    simplestats      = { module = "SimpleStats",      icon = "INV_Chest_Cloth_17",
        line = "Long item bonus lines in short, in your client's language." },
    detailsskin      = { module = "DetailsSkin",      icon = "INV_Misc_Bone_HumanSkull_01",
        line = "A Forever look for the Details! damage meter." },
    movementalert    = { module = "MovementAlert",    icon = "Spell_Arcane_Blink",
        line = "\"No Blink\" and the seconds left while your movement spell recharges." },
    interruptalert   = { module = "InterruptAlert",   icon = "Ability_Kick",
        line = "Names the spell you just interrupted." },
    deathalert       = { module = "DeathAlert",       icon = "Ability_Rogue_FeignDeath",
        line = "A big line when someone in your group dies." },
    durability       = { module = "Durability",       icon = "Trade_BlackSmithing",
        line = "REPAIR NOW, before your gear breaks." },
    automation       = { module = "Automation",       icon = "INV_Misc_Coin_02",
        line = "Sells greys, repairs, skips cutscenes: tick the chores you want on its page." },
    fastloot         = { module = "FastLoot",         icon = "INV_Misc_Bag_10",
        line = "Empties a loot window the moment it opens." },
    copytooltip      = { module = "CopyTooltip",      icon = "INV_Misc_Note_01",
        line = "Ctrl+C over a tooltip opens its ID, ready to copy." },
    drawer           = { module = "Drawer",           icon = "INV_Misc_Spyglass_03",
        line = "Tucks your addons' minimap buttons into a drawer." },
    potionalert      = { module = "PotionAlert",      icon = "INV_Potion_54",
        line = "Tells you when your combat potion is ready." },
    bloodlustalert   = { module = "BloodlustAlert",   icon = "Spell_Nature_BloodLust",
        line = "A sound and a 40-second bar when Bloodlust lands." },
    autorelease      = { module = "AutoRelease",      icon = "Spell_Holy_Resurrection",
        line = "Releases in battlegrounds, accepts resurrections." },
    autobuy          = { module = "AutoBuy",          icon = "INV_Misc_Bag_07",
        line = "Restocks the consumables you choose." },
}

local SECTIONS = { forever = "Made for WoW: Forever", everyday = "Everyday", finish = "Finish" }

local STEPS = {
    { kind = "welcome", name = "Welcome" },
    { name = "Datatexts",        section = "forever", features = { "datatexts" } },
    { name = "Node radar",       section = "forever", features = { "noderadar" } },
    { name = "Teleport menu",    section = "forever", features = { "teleportmenu" } },
    { name = "Campfire wheel",   section = "forever", features = { "campwheel" } },
    { name = "Macro Action Bar", section = "forever", features = { "macroactionbar" } },
    { name = "Bags and macros",  section = "forever", features = { "professionmarks", "consumablemacros" },
      lead = "Two helpers for what you carry." },
    { name = "Tooltips and meters", section = "forever", features = { "simplestats", "detailsskin" },
      lead = "Easier to read at a glance." },
    { name = "Alerts",           section = "everyday", features = { "movementalert", "interruptalert", "deathalert", "durability" },
      lead = "Big, clear messages for the moments that matter. Each one can be moved and restyled later." },
    { name = "Fewer clicks",     section = "everyday", features = { "automation", "fastloot", "copytooltip", "drawer" },
      lead = "Small chores the pack takes off your hands." },
    { name = "Group play",       section = "everyday", features = { "potionalert", "bloodlustalert", "autorelease", "autobuy" },
      lead = "For dungeons, raids and battlegrounds." },
    { kind = "done", name = "All set", section = "finish" },
}

-- ============================================================
-- Features: on, off, and the switch
-- ============================================================

local function FeatureDB(id)
    local spec = GUI.Pages[id]
    if not (spec and spec.dbKey) then return nil end
    local db = (spec.charDB and SP.GetCharDB() or SP.GetDB())[spec.dbKey]
    return type(db) == "table" and db or nil, spec
end

local function IsOn(id)
    local db = FeatureDB(id)
    return db and db.enabled and true or false
end

-- The tour, once built; SetFeature tells it to repaint what shows the state.
local tour

-- The page header's switch, wired the same way (Categories.lua, GUI.ModulePage):
-- the module refreshes, the sidebar dot and the toast follow, and a page shown in
-- the window behind re-reads its switch.
local function SetFeature(id, on)
    local db, spec = FeatureDB(id)
    if not db then return end
    db.enabled = on and true or false
    GUI.Applier(FEATURES[id].module)()
    GUI.UpdateDots()
    GUI.Toast(spec.name, db.enabled)
    local active = GUI._activePage
    if active and active._page then active._page:Refresh() end
    if tour then tour:Sync() end
end

-- The tour's steps on this client: features it does not load are left out, then
-- steps left without one.
local function Steps()
    local out = {}
    for _, step in ipairs(STEPS) do
        local features = {}
        for _, id in ipairs(step.features or {}) do
            if FeatureDB(id) then features[#features + 1] = id end
        end
        if step.kind or #features > 0 then
            out[#out + 1] = { kind = step.kind, name = step.name, section = step.section,
                              lead = step.lead, features = features }
        end
    end
    return out
end

-- ============================================================
-- Layout
-- ============================================================

local WIDTH, HEIGHT = 880, 560
local RAIL_W = 196
local FOOT   = 60
local STAGE_H, CARD_STAGE_H, PAIR_STAGE_H = 240, 92, 170
local NAV_W  = 92
local SKIP_W = 96
local BAR_DIAMOND      = "Interface\\AddOns\\SuspicionsPack\\Media\\GUITextures\\diamond.png"
local BAR_DIAMOND_FILL = "Interface\\AddOns\\SuspicionsPack\\Media\\GUITextures\\diamond-fill.png"
local LOGO_TEX  = "Interface\\AddOns\\SuspicionsPack\\Media\\Icons\\icon128x128.png"
local CLOSE_TEX = "Interface\\AddOns\\SuspicionsPack\\Media\\GUITextures\\close.png"
local QUEST_SELECTED = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight"
local ON_GREEN = { 0.44, 0.75, 0.35 }

local function IconPath(icon)
    if icon:find("\\", 1, true) then return icon end
    return "Interface\\Icons\\" .. icon
end

-- An area a scene draws into: the dark, bronze-rimmed box of the Forever skin, a
-- rounded dark card on retail. Returns the box and the clipped frame inside it.
local function Stage(parent, w, h)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(w, h)
    if GUI.FOREVER then
        SP.Skin.PlumberBox(box)
    else
        GUI.Backdrop(box, "bgDark", 1, "border", 1, "rr6")
    end
    local holder = CreateFrame("Frame", nil, box)
    holder:SetPoint("TOPLEFT", 4, -4)
    holder:SetPoint("BOTTOMRIGHT", -4, 4)
    holder:SetClipsChildren(true)
    return box, holder
end

-- The switch of one feature: the options' own toggle, reading and writing
-- through SetFeature so every other view of the feature follows.
local function Switch(parent, id)
    local _, spec = FeatureDB(id)
    local scope = spec.charDB and "char" or "profile"
    local defaults = SP.DEFAULTS and SP.DEFAULTS[scope] and SP.DEFAULTS[scope][spec.dbKey]
    local row = W.Toggle(parent, {
        label   = "Turn on " .. spec.name,
        get     = function() return IsOn(id) end,
        set     = function(v) SetFeature(id, v) end,
        default = defaults and defaults.enabled,
    })
    row.featureId = id
    return row
end

local function Heading(page, step, index, total, w)
    local eyebrow = GUI.Text(page, 11, GUI.FOREVER and "heading" or "textMuted")
    eyebrow:SetPoint("TOPLEFT", 0, 0)
    local where = SECTIONS[step.section]
    eyebrow:SetText(string.upper(("Step %d of %d"):format(index, total)
        .. ((where and step.section ~= "finish") and ("  \194\183  " .. where) or "")))
    local title = GUI.Text(page, 24, "accent")
    title:SetPoint("TOPLEFT", 0, -16)
    title:SetText(step.kind == "done" and "You're all set" or step.name)
    return 50
end

local function Lead(page, text, y, w)
    local lead = GUI.Text(page, 12.5, "textMuted")
    lead:SetPoint("TOPLEFT", 0, -y)
    lead:SetWidth(w)
    lead:SetJustifyH("LEFT")
    lead:SetWordWrap(true)
    lead:SetText(text)
    return y + math.ceil(lead:GetStringHeight() or 14) + 10, lead
end

-- ---- the four kinds of page ----

local function BuildWelcome(page, ctx)
    local logo = page:CreateTexture(nil, "ARTWORK")
    if GUI.FOREVER then
        local eye = SP.Skin.DEMON_EYE
        logo:SetSize(eye.w * 2, eye.h * 2)
        logo:SetTexture(eye.file)
        logo:SetTexCoord(unpack(eye.uv))
        logo:SetVertexColor(eye.shade, eye.shade, eye.shade, 1)
    else
        logo:SetSize(80, 80)
        logo:SetTexture(LOGO_TEX)
        GUI.Paint(logo, function(t, th) t:SetVertexColor(th.accent[1], th.accent[2], th.accent[3], 1) end)
    end
    logo:SetPoint("TOP", 0, -14)

    local hello = GUI.Text(page, 13, "textMuted")
    hello:SetPoint("TOP", logo, "BOTTOM", 0, -14)
    hello:SetText("Welcome to")
    local title = GUI.Text(page, 30, "accent")
    title:SetPoint("TOP", hello, "BOTTOM", 0, -2)
    title:SetText("Suspicion's Pack")
    local body = GUI.Text(page, 14, "textPrimary")
    body:SetPoint("TOP", title, "BOTTOM", 0, -12)
    body:SetWidth(470)
    body:SetJustifyH("CENTER")
    body:SetWordWrap(true)
    body:SetText("Small tools that make the game smoother, made for the guild. Most features start switched " ..
                 "off: this short tour shows each one in action, and you turn on the ones you like.")

    -- The icons of the tour's features, in step order.
    local ids = {}
    for _, step in ipairs(ctx.steps) do
        for _, id in ipairs(step.features) do ids[#ids + 1] = id end
    end
    local shown = math.min(#ids, 12)
    local size, gap = 34, 8
    local row = CreateFrame("Frame", nil, page)
    row:SetSize(shown * size + (shown - 1) * gap, size)
    row:SetPoint("TOP", body, "BOTTOM", 0, -22)
    page.glows = {}
    for i = 1, shown do
        local edge = row:CreateTexture(nil, "BACKGROUND")
        edge:SetSize(size + 2, size + 2)
        edge:SetPoint("TOPLEFT", (i - 1) * (size + gap) - 1, 1)
        edge:SetColorTexture(0, 0, 0, 1)
        local t = row:CreateTexture(nil, "ARTWORK")
        t:SetSize(size, size)
        t:SetPoint("TOPLEFT", (i - 1) * (size + gap), 0)
        t:SetTexture(IconPath(FEATURES[ids[i]].icon))
        t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        page.glows[i] = t
    end
    local caption = GUI.Text(page, 11, GUI.FOREVER and "heading" or "textMuted")
    caption:SetPoint("TOP", row, "BOTTOM", 0, -9)
    caption:SetText(string.upper(("%d features in %d steps"):format(#ids, #ctx.steps - 2)))

    local start = W.Button(page, { text = "Start the tour", width = 180, height = GUI.FOREVER and 26 or 30,
                                   onClick = function() ctx.go(2) end })
    start:SetPoint("TOP", caption, "BOTTOM", 0, -20)
    page.start = start
    local hint = GUI.Text(page, 11, "textMuted")
    hint:SetPoint("TOP", start, "BOTTOM", 0, -10)
    hint:SetText("About a minute. You can leave at any step; /spack setup brings it back.")

    -- The icons light up one after the other.
    local t = 0
    return function(dt)
        t = t + dt
        for i, g in ipairs(page.glows) do
            local v = 0.75 + 0.25 * math.cos((t - i * 0.25) * 2.4)
            g:SetVertexColor(v, v, v)
        end
    end
end

local function BuildSingle(page, step, ctx)
    local y = Heading(page, step, ctx.index, ctx.total, ctx.w)
    local id = step.features[1]
    local box, holder = Stage(page, ctx.w, STAGE_H)
    box:SetPoint("TOPLEFT", 0, -y)
    local update = GUI.SetupScenes[id](holder, ctx.w - 8, STAGE_H - 8)
    y = y + STAGE_H + 10
    local desc = GUI.Text(page, 13.5, "textPrimary")
    desc:SetPoint("TOPLEFT", 2, -y)
    desc:SetWidth(ctx.w - 4)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetText(FEATURES[id].text or "")
    page.desc = desc
    y = y + math.ceil(desc:GetStringHeight() or 14) + 6
    local row = Switch(page, id)
    row:SetPoint("TOPLEFT", 0, -y)
    row:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    page.switches[#page.switches + 1] = row
    local _, spec = FeatureDB(id)
    local cat = ""
    for _, c in ipairs(GUI.Categories) do if c.id == spec.category then cat = c.name end end
    local hint = GUI.Text(row, 11, "textMuted")
    hint:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    hint:SetText(("More settings later: %s \226\128\186 %s"):format(cat, spec.name))
    page.used = y + row.h
    return update
end

local function BuildGroup(page, step, ctx)
    local y = Heading(page, step, ctx.index, ctx.total, ctx.w)
    y = Lead(page, step.lead or "", y - 4, ctx.w)
    local n = #step.features
    local cols = n == 1 and 1 or 2
    local gap = 14
    local cardW = (ctx.w - (cols - 1) * gap) / cols
    local stageH = n <= 2 and PAIR_STAGE_H or CARD_STAGE_H
    local updates = {}
    local rowY, rowH = y, 0
    for i, id in ipairs(step.features) do
        local col = (i - 1) % cols
        if col == 0 and i > 1 then rowY, rowH = rowY + rowH + 8, 0 end
        local x = col * (cardW + gap)
        local box, holder = Stage(page, cardW, stageH)
        box:SetPoint("TOPLEFT", x, -rowY)
        updates[#updates + 1] = GUI.SetupScenes[id](holder, cardW - 8, stageH - 8)
        local row = Switch(page, id)
        row:SetPoint("TOPLEFT", x, -(rowY + stageH + 2))
        row:SetWidth(cardW)
        page.switches[#page.switches + 1] = row
        local line = GUI.Text(page, 11.5, "textMuted")
        line:SetPoint("TOPLEFT", x + row.textX, -(rowY + stageH + row.h - 4))
        line:SetWidth(cardW - row.textX - 4)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(true)
        line:SetText(FEATURES[id].line or "")
        local h = stageH + row.h - 4 + math.ceil(line:GetStringHeight() or 12)
        if h > rowH then rowH = h end
    end
    page.used = rowY + rowH
    return function(dt)
        for _, u in ipairs(updates) do u(dt) end
    end
end

local function BuildDone(page, ctx)
    local y = Heading(page, { kind = "done", section = "finish" }, ctx.index, ctx.total, ctx.w)
    local ids = {}
    for _, step in ipairs(ctx.steps) do
        for _, id in ipairs(step.features) do ids[#ids + 1] = id end
    end
    local function Count()
        local on = 0
        for _, id in ipairs(ids) do if IsOn(id) then on = on + 1 end end
        return ("%d of %d features are on. Click an icon to change your mind."):format(on, #ids)
    end
    -- Measured with its text: an empty line measures nothing, and the icons below
    -- ran into the sentence once it was written.
    local lead
    y, lead = Lead(page, Count(), y - 4, ctx.w)
    page.lead = lead
    local cols = 6
    local cw = ctx.w / cols
    page.chips = {}
    local rows = 0
    for i, id in ipairs(ids) do
        local col, r = (i - 1) % cols, math.floor((i - 1) / cols)
        rows = r + 1
        local chip = CreateFrame("Button", nil, page)
        chip:SetSize(cw, 66)
        chip:SetPoint("TOPLEFT", col * cw, -(y + r * 70))
        chip.edge = chip:CreateTexture(nil, "BACKGROUND")
        chip.edge:SetSize(40, 40)
        chip.edge:SetPoint("TOP", 0, 0)
        -- Black under the icon: the campfire wheel's art is a flame on nothing, and the
        -- lit gold edge showed through it.
        chip.back = chip:CreateTexture(nil, "BORDER")
        chip.back:SetSize(38, 38)
        chip.back:SetPoint("CENTER", chip.edge, "CENTER")
        chip.back:SetColorTexture(0, 0, 0, 1)
        chip.icon = chip:CreateTexture(nil, "ARTWORK")
        chip.icon:SetSize(38, 38)
        chip.icon:SetPoint("CENTER", chip.edge, "CENTER")
        chip.icon:SetTexture(IconPath(FEATURES[id].icon))
        chip.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        chip.name = GUI.Text(chip, 11, "textMuted")
        chip.name:SetPoint("TOP", chip.edge, "BOTTOM", 0, -4)
        chip.name:SetWidth(cw - 6)
        chip.name:SetJustifyH("CENTER")
        local _, spec = FeatureDB(id)
        chip.name:SetText(spec.name)
        chip.featureId = id
        chip:SetScript("OnClick", function() SetFeature(id, not IsOn(id)) end)
        GUI.Tooltip(chip, spec.name, spec.tip)
        page.chips[#page.chips + 1] = chip
    end
    y = y + rows * 70 + 10

    local open = W.Button(page, { text = "Open the options", width = 150, height = GUI.FOREVER and 22 or 26,
                                  onClick = function() tour:Hide(); GUI.Show() end })
    open:SetPoint("TOPLEFT", 0, -y)
    page.open = open
    local note = GUI.Text(page, 11.5, "textMuted")
    note:SetPoint("LEFT", open, "RIGHT", 14, 0)
    note:SetJustifyH("LEFT")
    note:SetText("Finish reloads the interface. Every feature has more settings in the\n" ..
                 "options (/spack), and /spack setup brings this tour back.")
    page.used = y + 26

    function page:Paint()
        for _, chip in ipairs(self.chips) do
            local lit = IsOn(chip.featureId)
            chip.icon:SetDesaturated(not lit)
            local v = lit and 1 or 0.5
            chip.icon:SetVertexColor(v, v, v)
            local a = GUI.T.accent
            if lit then chip.edge:SetColorTexture(a[1], a[2], a[3], 1) else chip.edge:SetColorTexture(0, 0, 0, 1) end
            local c = lit and GUI.T.accent or GUI.T.textMuted
            chip.name:SetTextColor(c[1], c[2], c[3], 1)
        end
        self.lead:SetText(Count())
    end
    page:Paint()
end

-- ============================================================
-- The window
-- ============================================================

local function Build()
    local FOREVER = GUI.FOREVER
    local Skin    = SP.Skin
    local PAD  = FOREVER and 24 or 16
    local HEAD = FOREVER and 52 or 44
    local mainX = PAD + RAIL_W + 20
    local mainW = WIDTH - mainX - 34
    local mainH = HEIGHT - (HEAD + 12) - FOOT

    local f = CreateFrame("Frame", "SP_SetupPopup", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    -- Over the options window, which shares the strata, when opened from Home.
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(GUI.OVER_WINDOW)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    -- ---- frame and header ----
    local logo = f:CreateTexture(nil, "ARTWORK")
    local title = GUI.Text(f, 16, "accent")
    title:SetText("Suspicion's Pack")
    local sub = GUI.Text(f, 12, "textMuted")
    sub:SetText("setup")
    sub:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 1)
    local ver = GUI.Text(f, 11, "textMuted")
    ver:SetText("v" .. (SP.VERSION or "?"))
    if FOREVER then
        Skin.PlumberFrame(f, 0, function() f:Hide() end)
        local eye = Skin.DEMON_EYE
        logo:SetSize(eye.w, eye.h)
        logo:SetPoint("LEFT", f, "TOPLEFT", PAD, -HEAD / 2)
        logo:SetTexture(eye.file)
        logo:SetTexCoord(unpack(eye.uv))
        logo:SetVertexColor(eye.shade, eye.shade, eye.shade, 1)
        ver:SetPoint("RIGHT", f, "TOPRIGHT", -44, -HEAD / 2)
        local d = Skin.PlumberDivider(f)
        d:SetHeight(24)
        d:SetPoint("TOPLEFT",  f, "TOPLEFT",  PAD - 8, -(HEAD - 14))
        d:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD - 8), -(HEAD - 14))
    else
        GUI.Backdrop(f, "bgDark", 1, "border", 1, "rr10")
        logo:SetSize(26, 26)
        logo:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -9)
        logo:SetTexture(LOGO_TEX)
        GUI.Paint(logo, function(t, th) t:SetVertexColor(th.accent[1], th.accent[2], th.accent[3], 1) end)
        local close = CreateFrame("Button", nil, f)
        close:SetSize(24, 24)
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -10)
        local x = close:CreateTexture(nil, "ARTWORK")
        x:SetSize(13, 13)
        x:SetPoint("CENTER")
        x:SetTexture(CLOSE_TEX)
        local function Tint(key) local c = GUI.T[key]; x:SetVertexColor(c[1], c[2], c[3], 1) end
        GUI.Paint(x, function() Tint("textMuted") end)
        close:SetScript("OnEnter", function() Tint("accent") end)
        close:SetScript("OnLeave", function() Tint("textMuted") end)
        close:SetScript("OnClick", function() f:Hide() end)
        ver:SetPoint("RIGHT", close, "LEFT", -6, 0)
        local rule = GUI.Tex(f, "ARTWORK", "border", 1)
        rule:SetHeight(1)
        rule:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEAD)
        rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEAD)
    end
    title:SetPoint("LEFT", logo, "RIGHT", 10, 0)

    local steps = Steps()
    local total = #steps
    f.steps = steps
    local cur, seen = 1, {}

    -- ---- the step list ----
    local rail = CreateFrame("Frame", nil, f)
    rail:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(HEAD + 8))
    rail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
    rail:SetWidth(RAIL_W)
    local railBg = GUI.Tex(rail, "BACKGROUND", FOREVER and "bgLight" or "bgMedium", FOREVER and 1 or 0.6)
    railBg:SetAllPoints()
    local railEdge = GUI.Tex(rail, "BORDER", "border", 0.8)
    railEdge:SetWidth(1)
    railEdge:SetPoint("TOPRIGHT")
    railEdge:SetPoint("BOTTOMRIGHT")

    local go
    f.railRows = {}
    local y, lastSection = 8, nil
    for i, step in ipairs(steps) do
        if step.section and step.section ~= lastSection then
            lastSection = step.section
            local gh = GUI.Text(rail, 12, FOREVER and "heading" or "textMuted")
            gh:SetText(FOREVER and SECTIONS[step.section] or string.upper(SECTIONS[step.section]))
            if FOREVER then
                Skin.PlumberHeader(rail, gh, 4, -(y + 20), rail, -10)
                y = y + 30
            else
                gh:SetPoint("TOPLEFT", 12, -(y + 8))
                y = y + 26
            end
        end
        local r = CreateFrame("Button", nil, rail)
        r:SetHeight(25)
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", rail, "RIGHT", -1, 0)
        r.hl = r:CreateTexture(nil, "BACKGROUND")
        r.hl:SetAllPoints()
        if FOREVER then
            r.hl:SetTexture(QUEST_SELECTED)
            r.hl:SetBlendMode("ADD")
        else
            r.hl:SetTexture("Interface\\Buttons\\WHITE8X8")
            GUI.Paint(r.hl, function(t, th) t:SetVertexColor(th.selectedBg[1], th.selectedBg[2], th.selectedBg[3], th.selectedBg[4] or 0.25) end)
        end
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetSize(11, 11)
        r.mark:SetPoint("LEFT", 22, 0)
        r.label = GUI.Text(r, 13, "textPrimary")
        r.label:SetPoint("LEFT", r.mark, "RIGHT", 9, 0)
        r.label:SetText(step.name)
        r.on = GUI.Text(r, 10, "textMuted")
        r.on:SetPoint("RIGHT", -10, 0)
        r.on:SetText("ON")
        r.on:SetTextColor(ON_GREEN[1], ON_GREEN[2], ON_GREEN[3], 1)
        r:SetScript("OnClick", function() go(i) end)
        f.railRows[i] = r
        y = y + 25
    end

    -- ---- footer ----
    local skip = CreateFrame("Button", nil, f)
    skip:SetSize(SKIP_W, 22)
    skip:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", mainX, PAD - 2)
    local skipFS = GUI.Text(skip, 12, "textMuted")
    skipFS:SetPoint("LEFT")
    skipFS:SetText("Skip the tour")
    skip:SetScript("OnEnter", function() local c = GUI.T.textPrimary; skipFS:SetTextColor(c[1], c[2], c[3], 1) end)
    skip:SetScript("OnLeave", function() local c = GUI.T.textMuted; skipFS:SetTextColor(c[1], c[2], c[3], 1) end)
    skip:SetScript("OnClick", function() go(total) end)
    f.skip = skip

    local btnH = FOREVER and 22 or 24
    local nextBtn, backBtn
    nextBtn = W.Button(f, { text = "Next", width = NAV_W, height = btnH, onClick = function()
        -- Finish reloads the interface, so every feature turned on starts clean. In the
        -- click itself: the game only lets an addon reload on a click.
        if cur == total then
            f:Hide()
            local reload = C_UI and C_UI.Reload or ReloadUI
            if reload then reload() end
        else
            go(cur + 1)
        end
    end })
    nextBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, PAD - 2)
    backBtn = W.Button(f, { text = "Back", width = NAV_W, height = btnH, onClick = function() go(cur - 1) end })
    backBtn:SetPoint("RIGHT", nextBtn, "LEFT", -8, 0)
    f.nextBtn, f.backBtn = nextBtn, backBtn

    local barW = mainW - SKIP_W - 12 - (NAV_W * 2 + 8) - 12
    local bar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bar:SetSize(barW, 14)
    bar:SetPoint("LEFT", skip, "RIGHT", 12, 0)
    bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    GUI.Paint(bar, function(b, th)
        b:SetBackdropColor(0.03, 0.025, 0.02, 1)
        b:SetBackdropBorderColor(th.border[1], th.border[2], th.border[3], 1)
    end)
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", 1, 1)
    fill:SetWidth(0.1)
    -- The accent darkened: at full strength, the white "n / N" over it could not be read.
    GUI.Paint(fill, function(t, th)
        local a = th.accent
        t:SetGradient("VERTICAL", CreateColor(a[1] * 0.4, a[2] * 0.4, a[3] * 0.4, 1),
                                  CreateColor(a[1] * 0.7, a[2] * 0.7, a[3] * 0.7, 1))
    end)
    local barText = GUI.Text(bar, 11, "textPrimary")
    barText:SetPoint("CENTER")
    f.barFill, f.barText = fill, barText
    local fillW, barSerial = 0.1, 0

    -- ---- pages ----
    local main = CreateFrame("Frame", nil, f)
    main:SetPoint("TOPLEFT", f, "TOPLEFT", mainX, -(HEAD + 12))
    main:SetSize(mainW, mainH)
    f.mainW, f.mainH = mainW, mainH
    local pages = {}
    f.pages = pages

    local ctx = { steps = steps, total = total, w = mainW, h = mainH }
    local function Page(i)
        if pages[i] then return pages[i] end
        local page = CreateFrame("Frame", nil, main)
        page:SetAllPoints()
        page.switches = {}
        ctx.index = i
        ctx.go = function(n) go(n) end
        local step = steps[i]
        if step.kind == "welcome" then
            page.update = BuildWelcome(page, ctx)
        elseif step.kind == "done" then
            BuildDone(page, ctx)
        elseif #step.features == 1 and step.section == "forever" then
            page.update = BuildSingle(page, step, ctx)
        else
            page.update = BuildGroup(page, step, ctx)
        end
        pages[i] = page
        return page
    end

    function f:Sync()
        for i, r in ipairs(self.railRows) do
            local any = false
            for _, id in ipairs(steps[i].features) do any = any or IsOn(id) end
            r.on:SetShown(any)
            local here = i == cur
            r.hl:SetShown(here)
            r.mark:SetTexture((here or seen[i]) and BAR_DIAMOND_FILL or BAR_DIAMOND)
            local m = here and GUI.T.accent or (seen[i] and { 0.90, 0.72, 0.36 } or GUI.T.textMuted)
            r.mark:SetVertexColor(m[1], m[2], m[3], 1)
            local c = here and GUI.T.accent or GUI.T.textPrimary
            r.label:SetTextColor(c[1], c[2], c[3], 1)
        end
        for _, page in pairs(pages) do
            for _, row in ipairs(page.switches) do row:Refresh() end
            if page.Paint then page:Paint() end
        end
    end

    go = function(i)
        i = math.max(1, math.min(total, i))
        if pages[cur] then pages[cur]:Hide() end
        cur = i
        seen[i] = true
        local page = Page(i)
        page:Show()
        f.current = page
        backBtn:SetEnabled(i > 1)
        nextBtn:SetText(i == total and "Finish" or "Next")
        barText:SetText(("%d / %d"):format(i, total))
        -- Tick.Animate cannot be stopped: a quick second click starts a second
        -- animation, and only the newest may write.
        local to = math.max(0.1, (barW - 2) * i / total)
        barSerial = barSerial + 1
        local mine = barSerial
        SP.Tick.Animate(fillW, to, 0.3, function(v)
            if mine == barSerial then fillW = v; fill:SetWidth(v) end
        end)
        f:Sync()
    end
    f.Go = function(_, i) go(i) end
    f.Current = function() return cur end

    f:SetScript("OnUpdate", function(_, dt)
        local page = f.current
        if page and page.update then page.update(dt) end
    end)
    -- Each opening is a new walk through: back to the first step, nothing seen.
    f:SetScript("OnShow", function()
        wipe(seen)
        go(1)
    end)

    tinsert(UISpecialFrames, "SP_SetupPopup")
    return f
end

function GUI.ShowSetup()
    if not tour then
        tour = Build()
        GUI.setupPopup = tour
    end
    if tour:IsShown() then tour:Go(1) else tour:Show() end
end
