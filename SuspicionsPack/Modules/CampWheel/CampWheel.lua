-- SuspicionsPack — CampWheel (WoW: Forever only, see the .toc gate)
--
-- Near a campfire, a small wheel opens with the camp items you can place right now, and
-- the two toys that go with a camp. Click one to use it. The middle sits you down.
--
-- The only sign of a fire is the player's Campfire Nearby buff, which reaches 100 yards.
-- Placing an item needs you closer than that, so the wheel can open a little early; the
-- game then answers the click with its usual error.
--
-- Two sets of frames, because the wheel animates and secure buttons may not move in combat:
--   * What you click: holder and its secure buttons. Invisible, and they stay where they
--     belong. They only change out of combat. A state driver hides them in combat, on a
--     mount and when dead, because nothing else can hide them in combat. A driver shows
--     its frame again every 0.2 s, so to close the wheel the driver has to go, not just
--     the frame.
--   * What you see: visual and the images on it. Plain frames that take no mouse, free to
--     move at any time. Holder showing and hiding is what starts their animations, so a
--     fight or a mount closes the wheel the same way a click does.
--
-- Idle costs one buff lookup per player UNIT_AURA: no driver and no bag or cooldown events
-- until a fire is near. The per-frame update only runs while something is moving.

local SP = SuspicionsPack

local CW = SP:NewSPModule("CampWheel", "campWheel")
SP.CampWheel = CW

local _issecretvalue = issecretvalue or function() return false end
local sin, cos, pi, abs, floor, max, min = math.sin, math.cos, math.pi, math.abs, math.floor, math.max, math.min

-- ============================================================
-- The game's data, build 1.60.1.70790
-- ============================================================
local FIRE_BUFF = 1283391

-- Every item with the shared "Camping Feature" cooldown, profession by profession. The
-- campfire kits are left out on purpose: you are already at a fire.
local OBJECTS = {
    279956, 279970, 279990,         -- Alchemy: Mana Well, Fermenter, Alchemy Laboratory
    279944, 279988, 279955,         -- Blacksmithing: Sharpening Wheel, Anvil, Master Forge
    279957, 279982,                 -- Cooking: Cookie's Feast, Iron Oven
    279976, 279985, 279987,         -- Enchanting: Enchanted Lute, Arcane Salvager, Arcane Forge
    279950, 279949, 279989,         -- Engineering: Reagent Bot, Repair Bot, Anarchist's Workbench
    279968, 279940, 279951,         -- First Aid: First Aid Kit, Toxin Study, Plague Doctor's Laboratory
    279967, 279965, 279966,         -- Fishing: Fish Bowl, Fishing Rack, Fishing Hut
    279962, 279964, 279947,         -- Herbalism: Incense Candle, Greenhouse, Seed Hybridizer
    279978, 279941, 279945,         -- Leatherworking: Camp Tent, Tanning Rack, Sewing Machine
    279960, 279948, 279952,         -- Mining: Lodestone, Rock Garden, Molten Foundry
    279979, 279969, 279938,         -- Skinning: Camp Chair, Field Guide, Trapper's Workbench
    279973, 279972, 279943, 279959, -- Tailoring: Faction Banners, Spinning Wheel, Loom
    278030,                         -- Scarlet Banner
}
local TOYS = {
    289439, -- Pouch of Violet Dust
    288185, -- Adventurer's Tent
}
local SAMPLE = { 279979, 279978, 279967, 279968, 289439 }

-- ============================================================
-- Settings that are not settings
-- ============================================================
-- [@player,dead]: a bare [dead] would ask about the target.
local WHEN_NEAR    = "[combat][mounted][@player,dead] hide; show"
local WHEN_PREVIEW = "[combat] hide; show"
local GLOBAL_COOLDOWN = 2   -- seconds: a cooldown this short is not the item's own
local GATHER = 0.2          -- seconds: bursts of bag and cooldown events become one update
local NEAR_EVENTS = { "BAG_UPDATE_DELAYED", "BAG_UPDATE_COOLDOWN", "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_USABLE", "TOYS_UPDATED" }

-- The look.
local MEDIA  = "Interface\\AddOns\\SuspicionsPack\\Media\\CampWheel\\"   -- see CREDITS.txt there
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ICON_SIZE, MIDDLE_SIZE = 36, 44
local ICON_CROP = 0.12      -- how much of each edge of an icon is cut, to zoom it in its frame
local CAMPFIRE_SIZE, RING_SIZE, POINTER_SIZE, GLOW_SIZE = 30, 44, 52, 72
local MIN_RADIUS = 46
local ICON_SPACE = 44       -- pixels of the circle each icon takes
local GOLD        = { 0.72, 0.60, 0.36 }
local GOLD_HOVER  = { 1, 0.88, 0.54 }
local FLAME       = { 0.96, 0.72, 0.38 }
local FLAME_HOVER = { 1, 0.86, 0.58 }

-- The motion, after OPie's ring: same timings, our own code.
local MIN_FPS     = 20      -- below this, no transition
local TURN_TIME   = 0.25    -- seconds to open or to close
local RING_PERIOD = 4       -- seconds for one turn of the ring
local CLOSE_TURN  = pi / 4  -- how far the icons turn as they leave
local POP_TIME    = 0.1     -- seconds for a hovered icon to grow
local LIGHT_TIME  = 0.3     -- seconds for the glow and the pointer to fade
local GLOW_ALPHA  = 0.75

-- ============================================================
-- State
-- ============================================================
local active     = false
local nearFire   = false
local dismissed  = false    -- closed by a click, until the next fire
local previewing = false
local gathering  = false    -- an update is on its way
local driven     = nil      -- the driver's condition while the wheel is up
local onButtons  = nil      -- what the buttons show, so they are only touched on a change
local cooldownTimer = nil

local holder, hub                   -- what you click
local anchor, visual                -- what you see
local fire, ring, ringSpin, pointer, glow
local buttons = {}

local base     = 1      -- the size setting
local radius   = MIN_RADIUS
local popBy    = 0.10   -- how much a hovered icon grows
local phase    = nil    -- "opening", "closing", or nil when still
local timeLeft = 0
local growth, spread, slide = 0, 0, 0   -- this transition's reach
local hovered  = nil    -- the image under the mouse
local light    = 0      -- 0 to 1: the glow and the pointer
local pointerAngle = nil

local Sync

-- ============================================================
-- The game
-- ============================================================
local function FireNearby()
    -- pcall: aura lookups may refuse to run at all while auras are restricted.
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, FIRE_BUFF)
    if not ok or _issecretvalue(aura) then return false end
    return aura ~= nil
end

-- A toy is in no bag, so it asks what Blizzard's toy box asks.
local function ReadCooldown(id, isToy)
    if not isToy then return C_Container.GetItemCooldown(id) end
    local info = C_Spell.GetItemCooldown(id)
    if _issecretvalue(info) or not info then return nil end
    return info.startTime, info.duration
end

-- Seconds before an item is ready again.
local function Remaining(id, isToy)
    local start, duration = ReadCooldown(id, isToy)
    if _issecretvalue(start) or _issecretvalue(duration) then return 0 end
    if not (start and duration) or duration <= GLOBAL_COOLDOWN then return 0 end
    local left = start + duration - GetTime()
    return left > 0 and left or 0
end

-- What can be placed now, and how long until something on cooldown comes back.
local function ReadItems()
    local list, soonest = {}, nil
    local function Offer(id, isToy, count)
        local left = Remaining(id, isToy)
        if left <= 0 then
            list[#list + 1] = { id = id, isToy = isToy, count = count }
        elseif not soonest or left < soonest then
            soonest = left
        end
    end
    for _, id in ipairs(OBJECTS) do
        local count = C_Item.GetItemCount(id)
        -- Not usable: the item asks for more of its profession than you have.
        if count > 0 and C_Item.IsUsableItem(id) then Offer(id, false, count) end
    end
    for _, id in ipairs(TOYS) do
        if PlayerHasToy(id) then Offer(id, true, 0) end
    end
    return list, soonest
end

local function SampleItems()
    local list = {}
    for i, id in ipairs(SAMPLE) do list[i] = { id = id, sample = true, count = 0 } end
    return list
end

-- ============================================================
-- The motion
-- ============================================================
local function Clamp(value, low, high)
    return max(low, min(high, value))
end

local function Tint(texture, color)
    texture:SetVertexColor(color[1], color[2], color[3], 1)
end

-- Off the pixel grid, or a texture shimmers as it scales and turns.
local function Smooth(texture)
    texture:SetTexelSnappingBias(0)
    texture:SetSnapToPixelGrid(false)
    return texture
end

-- An image on the circle, turned back by `turn` radians and pushed `away` along the circle.
local function MoveImage(image, turn, away)
    local a = image.angle - turn
    image:SetPoint("CENTER", visual, "CENTER",
        radius * cos(a) + away * cos(a - pi / 2),
        radius * sin(a) + away * sin(a - pi / 2))
end

-- Every image where it belongs, at rest.
local function SettleImages()
    for i = 1, #buttons do
        local image = buttons[i].image
        image.size = 1
        image:SetScale(1)
        Tint(image.ring, GOLD)
        image.shine:Hide()
        MoveImage(image, 0, 0)
    end
end

local function FinishClosing()
    phase = nil
    visual:SetScript("OnUpdate", nil)
    visual:Hide()
    ringSpin:Stop()
end

-- The wheel, while it opens or closes. False once it is not doing either.
local function StepTransition(elapsed)
    if not phase then return false end
    timeLeft = timeLeft - elapsed
    local r = timeLeft > 0 and timeLeft / TURN_TIME or 0
    if phase == "opening" then
        -- Starts big and slows as it lands. Fully there at 60 % of the way.
        visual:SetScale(base * (1 + growth * r / (1 + (1 - r) / 0.375)))
        visual:SetAlpha(r > 0.4 and (1 - r) / 0.6 or 1)
        if r == 0 then phase = nil end
    elseif r == 0 then
        FinishClosing()
    else
        local gone = 1 - r
        visual:SetScale(base * (1 + spread * gone))
        visual:SetAlpha(r)
        for i = 1, #buttons do
            MoveImage(buttons[i].image, CLOSE_TURN * gone, slide * gone)
        end
    end
    return true
end

-- The hovered icon grows, and its scale pushes it a little away from the middle.
local function StepIcons(elapsed)
    local moving = false
    local step = popBy * elapsed / POP_TIME
    for i = 1, #buttons do
        local image = buttons[i].image
        local want = image == hovered and 1 + popBy or 1
        if image.size ~= want then
            image.size = image.size + Clamp(want - image.size, -step, step)
            image:SetScale(image.size)
            moving = true
        end
    end
    return moving
end

-- Degrees per second: the further the pointer has to go, the faster it goes.
local function PointerSpeed(degrees)
    local function Sine(d) return sin(min(90, d) * pi / 180) end
    if degrees > 60 then return 420 + 120 * Sine(degrees - 60) end
    if degrees > 15 then return 180 + 240 * Sine((degrees - 15) * 2) end
    return 20 + 160 * Sine(degrees * 6)
end

-- The glow behind the middle, and the pointer turning towards the hovered icon.
local function StepLight(elapsed)
    local moving = false
    local want = hovered and 1 or 0
    if light ~= want then
        local step = elapsed / LIGHT_TIME
        light = light + Clamp(want - light, -step, step)
        glow:SetAlpha(GLOW_ALPHA * light)
        pointer:SetAlpha(light)
        moving = true
    end
    if hovered then
        -- The pointer's art points up, which is the angle pi / 2.
        local target = hovered.angle - pi / 2
        if not pointerAngle then pointerAngle = target end
        local apart = (target - pointerAngle + pi) % (2 * pi) - pi
        local limit = 1.25 * PointerSpeed(abs(apart) * 180 / pi) * elapsed * pi / 180
        if abs(apart) <= limit then
            pointerAngle = target
        else
            pointerAngle = pointerAngle + (apart > 0 and limit or -limit)
            moving = true
        end
        pointer:SetRotation(pointerAngle)
    elseif light == 0 then
        pointerAngle = nil
    end
    return moving
end

local function Step(_, elapsed)
    local changing = StepTransition(elapsed)
    local icons, lit = StepIcons(elapsed), StepLight(elapsed)
    if not (changing or icons or lit) then visual:SetScript("OnUpdate", nil) end
end
local function Wake()
    visual:SetScript("OnUpdate", SP.Perf.Wrap("CampWheel", "OnUpdate", Step))
end

-- How far this transition reaches: the smaller the wheel on screen, the further.
local function ReadReach(fps)
    local _, screenHeight = GetPhysicalScreenSize()
    local pixels = (34 + radius) * UIParent:GetEffectiveScale() * base / 768 * screenHeight
    local zoom = 2100 * pixels ^ -1.375
    growth = Clamp(zoom, 0.25, 1.5)
    spread = Clamp(0.4 * zoom, 0.4, 0.75)
    slide = 150 * Clamp(fps * fps * fps / 216000, 0.15, 1)
end

-- Holder showing and hiding: both only touch plain frames, as they can run in combat.
local function PlayOpening()
    light, pointerAngle = 0, nil
    glow:SetAlpha(0)
    pointer:SetAlpha(0)
    Tint(fire, FLAME)
    SettleImages()
    visual:Show()
    ringSpin:Play()
    local fps = GetFramerate()
    if fps < MIN_FPS then
        phase = nil
        visual:SetAlpha(1)
        visual:SetScale(base)
        return
    end
    ReadReach(fps)
    phase, timeLeft = "opening", TURN_TIME
    Wake()
    Step(visual, 0)     -- its first look, before the first frame draws it at full size
end

local function PlayClosing()
    hovered = nil
    local fps = GetFramerate()
    if fps < MIN_FPS then
        FinishClosing()
        return
    end
    ReadReach(fps)
    phase, timeLeft = "closing", TURN_TIME
    Wake()
end

-- ============================================================
-- The frames
-- ============================================================
local function ButtonEnter(b)
    local image = b.image
    hovered = image
    Tint(image.ring, GOLD_HOVER)
    image.shine:Show()
    Wake()
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if b.isToy then GameTooltip:SetToyByItemID(b.itemID) else GameTooltip:SetItemByID(b.itemID) end
    GameTooltip:Show()
end

local function ButtonLeave(b)
    local image = b.image
    hovered = nil
    Tint(image.ring, GOLD)
    image.shine:Hide()
    Wake()
    GameTooltip:Hide()
end

local function HubEnter(self)
    Tint(fire, FLAME_HOVER)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Campfire wheel")
    GameTooltip:AddLine("Click: sit down", 1, 1, 1)
    GameTooltip:AddLine("Right-click: close until the next campfire", 1, 1, 1)
    GameTooltip:Show()
end

local function HubLeave()
    Tint(fire, FLAME)
    GameTooltip:Hide()
end

-- The left click is the button's own: the secure macro.
local function HubPostClick(_, button)
    if button ~= "RightButton" then return end
    dismissed = true
    GameTooltip:Hide()
    Sync()
end

-- A disc, `inset` pixels inside the frame's edge (negative: outside it).
local function Disc(parent, sublevel, inset, r, g, b, a)
    local t = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel)
    t:SetTexture(CIRCLE)
    t:SetPoint("TOPLEFT", inset, -inset)
    t:SetPoint("BOTTOMRIGHT", -inset, inset)
    t:SetVertexColor(r, g, b, a)
    return Smooth(t)
end

-- A texture from our folder, centred on `parent`: the wheel's own frame unless given.
local function Part(file, layer, size, parent)
    parent = parent or visual
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(MEDIA .. file)
    t:SetSize(size, size)
    t:SetPoint("CENTER", parent, "CENTER", 0, 0)
    return Smooth(t)
end

-- The wheel's middle on `parent`: the glow, the turning ring, the pointer and the fire.
local function NewMiddle(parent)
    local m = {}
    m.glow = Part("glow.png", "BACKGROUND", GLOW_SIZE, parent)
    m.glow:SetBlendMode("ADD")
    Tint(m.glow, FLAME)

    m.ring = Part("ring.png", "BORDER", RING_SIZE, parent)
    Tint(m.ring, GOLD)
    m.ringSpin = m.ring:CreateAnimationGroup()
    m.ringSpin:SetLooping("REPEAT")
    local turn = m.ringSpin:CreateAnimation("Rotation")
    turn:SetDegrees(-360)
    turn:SetDuration(RING_PERIOD)
    turn:SetOrigin("CENTER", 0, 0)

    m.pointer = Part("pointer.png", "BORDER", POINTER_SIZE, parent)
    Tint(m.pointer, GOLD_HOVER)

    m.fire = Part("campfire.png", "ARTWORK", CAMPFIRE_SIZE, parent)
    Tint(m.fire, FLAME)
    return m
end

local function EnsureFrames()
    if holder then return end

    -- An anchor with no scale of its own, so the wheel grows around its centre.
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetSize(1, 1)
    visual = CreateFrame("Frame", "SP_CampWheelVisual", UIParent)
    visual:SetSize(1, 1)
    visual:SetFrameStrata("MEDIUM")
    visual:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    visual:Hide()

    local middle = NewMiddle(visual)
    glow, ring, ringSpin = middle.glow, middle.ring, middle.ringSpin
    pointer, fire = middle.pointer, middle.fire

    holder = CreateFrame("Frame", "SP_CampWheel", UIParent)
    holder:SetSize(1, 1)
    holder:SetFrameStrata("MEDIUM")
    -- Hidden so that the driver's first Show counts as showing it, and opens the wheel.
    holder:Hide()
    holder:HookScript("OnShow", SP.Perf.Wrap("CampWheel", "holder OnShow", PlayOpening))
    holder:HookScript("OnHide", SP.Perf.Wrap("CampWheel", "holder OnHide", PlayClosing))

    hub = CreateFrame("Button", nil, holder, "SecureActionButtonTemplate")
    hub:SetSize(MIDDLE_SIZE, MIDDLE_SIZE)
    hub:SetPoint("CENTER", holder, "CENTER", 0, 0)
    hub:RegisterForClicks("AnyUp")
    hub:SetAttribute("useOnKeyDown", false)
    -- Addon code may not call the emote itself. /sit exists in every language.
    hub:SetAttribute("*type1", "macro")
    hub:SetAttribute("*macrotext1", "/sit")
    -- Only the circle takes clicks, not the empty corners next to an icon.
    hub:SetHitRectInsets(6, 6, 6, 6)
    hub:SetScript("OnEnter", HubEnter)
    hub:SetScript("OnLeave", HubLeave)
    hub:SetScript("PostClick", HubPostClick)
end

-- What an item looks like, on `parent` (the wheel's frame unless given). Grown and moved
-- freely, it takes no mouse.
local function NewImage(parent)
    local image = CreateFrame("Frame", nil, parent or visual)
    image:SetSize(ICON_SIZE, ICON_SIZE)

    Disc(image, 0, -3, 0, 0, 0, 1)
    image.ring = Disc(image, 1, -2, GOLD[1], GOLD[2], GOLD[3], 1)

    image.icon = Smooth(image:CreateTexture(nil, "ARTWORK"))
    image.icon:SetAllPoints(image)
    image.icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    local mask = image:CreateMaskTexture()
    mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(image.icon)
    image.icon:AddMaskTexture(mask)

    image.shine = Smooth(image:CreateTexture(nil, "OVERLAY"))
    image.shine:SetTexture(CIRCLE)
    image.shine:SetAllPoints(image.icon)
    image.shine:SetBlendMode("ADD")
    image.shine:SetVertexColor(1, 0.75, 0.35, 0.3)

    image.count = image:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    image.count:SetPoint("BOTTOMRIGHT", image, "BOTTOMRIGHT", -1, 1)
    return image
end

-- For the setup tour's example wheel: the wheel's own parts, colours and sizes.
CW.NewMiddle, CW.NewImage = NewMiddle, NewImage
CW.SAMPLE = SAMPLE
CW.LOOK = { GOLD = GOLD, GOLD_HOVER = GOLD_HOVER, FLAME = FLAME, FLAME_HOVER = FLAME_HOVER,
            GLOW_ALPHA = GLOW_ALPHA, ICON_SIZE = ICON_SIZE, MIN_RADIUS = MIN_RADIUS,
            ICON_SPACE = ICON_SPACE, POP = 0.10 }

-- What an item does when clicked. Invisible, and it stays put.
local function NewButton(index)
    local b = CreateFrame("Button", nil, holder, "SecureActionButtonTemplate")
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b:RegisterForClicks("AnyUp")
    -- Fire on release. Without this the ActionButtonUseKeyDown CVar applies, and when on,
    -- an "AnyUp" button never fires (same reason as the Hearthstone datatext).
    b:SetAttribute("useOnKeyDown", false)
    b:SetScript("OnEnter", ButtonEnter)
    b:SetScript("OnLeave", ButtonLeave)
    b.image = NewImage()
    buttons[index] = b
    return b
end

-- "*": with a modifier held, a left click still uses it.
local function SetAction(b, entry)
    local id = entry.id
    local kind = (not entry.sample) and (entry.isToy and "toy" or "item") or nil
    b:SetAttribute("*type1", kind)
    b:SetAttribute("*item1", kind == "item" and ("item:" .. id) or nil)
    b:SetAttribute("*toy1", kind == "toy" and id or nil)
    b:EnableMouse(not entry.sample)
    b.itemID, b.isToy = id, entry.isToy
    local _, _, _, _, icon = C_Item.GetItemInfoInstant(id)
    b.image.icon:SetTexture(icon)
    b.image.count:SetText(entry.count > 1 and entry.count or "")
end

-- The first item at the top, the others clockwise.
local function Layout(list)
    local count = #list
    radius = max(MIN_RADIUS, floor(count * ICON_SPACE / (2 * pi) + 0.5))
    popBy = radius > 200 and 0.05 or 0.10
    -- The hovered icon may be gone, and a button hidden under the mouse may never hear OnLeave.
    if hovered then
        hovered = nil
        GameTooltip:Hide()
        Wake()
    end
    for i, entry in ipairs(list) do
        local b = buttons[i] or NewButton(i)
        local angle = pi / 2 - (i - 1) * 2 * pi / count
        b:ClearAllPoints()
        b:SetPoint("CENTER", holder, "CENTER", radius * cos(angle), radius * sin(angle))
        SetAction(b, entry)
        b:Show()
        b.image.angle = angle
        b.image:Show()
    end
    for i = count + 1, #buttons do
        buttons[i]:Hide()
        buttons[i].image:Hide()
    end
    hub:EnableMouse(not list[1].sample)
    SettleImages()
end

-- A sample's objects have a count of 0 and a real one's never do, so the two never match.
local function Signature(list)
    local parts = {}
    for i, entry in ipairs(list) do
        parts[i] = entry.id .. ":" .. entry.count
    end
    return table.concat(parts, ",")
end

local function Open(list)
    EnsureFrames()
    -- A frame's offsets are in its own scale, so holder's are divided by it.
    local db = CW:GetDB()
    base = db.scale / 100
    anchor:ClearAllPoints()
    anchor:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    holder:ClearAllPoints()
    holder:SetPoint("CENTER", UIParent, "CENTER", db.x / base, db.y / base)
    holder:SetScale(base)
    if not phase then visual:SetScale(base) end

    local signature = Signature(list)
    if signature ~= onButtons then
        Layout(list)
        onButtons = signature
    end
    local when = previewing and WHEN_PREVIEW or WHEN_NEAR
    if driven ~= when then
        RegisterStateDriver(holder, "visibility", when)
        driven = when
    end
end

local function Close()
    if not driven then return end
    UnregisterStateDriver(holder, "visibility")
    driven = nil
    holder:Hide()
end

-- ============================================================
-- Keeping it true
-- ============================================================
local function ListenNearFire(on)
    for _, event in ipairs(NEAR_EVENTS) do
        if on then CW:RegisterEvent(event, "OnNearFireEvent") else CW:UnregisterEvent(event) end
    end
end

-- An item coming off cooldown sends no event: this brings it back.
local function WakeAfter(seconds)
    if cooldownTimer then
        cooldownTimer:Cancel()
        cooldownTimer = nil
    end
    if seconds then
        cooldownTimer = C_Timer.NewTimer(seconds + 0.1, function()
            cooldownTimer = nil
            Sync()
        end)
    end
end

-- The one place the wheel changes. In combat it waits: PLAYER_REGEN_ENABLED runs it again.
function Sync()
    if InCombatLockdown() then return end

    local near = active and FireNearby()
    if near ~= nearFire then
        nearFire = near
        dismissed = false
        ListenNearFire(near)
    end

    local list, soonest
    if previewing then
        list = SampleItems()
    elseif near and not dismissed then
        list, soonest = ReadItems()
    end
    WakeAfter(soonest)

    if list and list[1] then Open(list) else Close() end
end

function CW:OnNearFireEvent()
    if gathering then return end
    gathering = true
    C_Timer.After(GATHER, function()
        gathering = false
        Sync()
    end)
end

-- Not AceEvent: UNIT_AURA only for the player, and a switch-off in combat has to outlive
-- the module's own events to finish when the fight does.
local events = CreateFrame("Frame")
events:SetScript("OnEvent", SP.Perf.WrapEvent("CampWheel", function(self)
    if not active then self:UnregisterAllEvents() end
    Sync()
end))

-- ============================================================
-- The module
-- ============================================================
-- Runs again on every settings change.
function CW:Activate()
    active = true
    events:RegisterUnitEvent("UNIT_AURA", "player")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    Sync()
end

-- The mixin follows this with AceEvent's UnregisterAllEvents, which ends the bag events.
function CW:Deactivate()
    active, previewing, nearFire = false, false, false
    if InCombatLockdown() then
        events:UnregisterEvent("UNIT_AURA")
    else
        events:UnregisterAllEvents()
    end
    Sync()
end

-- The settings page's Preview: a sample wheel to place, that does nothing when clicked.
function CW:SetPreview(on)
    if on and (not active or InCombatLockdown()) then return end
    previewing = on and true or false
    Sync()
end

function CW:IsPreviewing()
    return previewing
end

-- /spack camp status: what the wheel sees at the moment you ask. Asked far from a fire and
-- then close to it, it also shows whether the game's "usable" answer depends on the distance.
function CW.PrintStatus()
    print(("SuspicionsPack: campfire wheel: on %s, fire buff %s, closed by click %s, preview %s, up %s"):format(
        tostring(active), tostring(FireNearby()), tostring(dismissed), tostring(previewing), tostring(driven ~= nil)))
    if InCombatLockdown() then
        print("  In combat: ask again after the fight for the items.")
        return
    end
    local function Line(id, isToy, what)
        print(("  %s (%d): %s, cooldown %d s"):format(
            tostring(C_Item.GetItemNameByID(id)), id, what, floor(Remaining(id, isToy))))
    end
    for _, id in ipairs(OBJECTS) do
        local count = C_Item.GetItemCount(id)
        if count > 0 then
            Line(id, false, ("%d carried, usable %s"):format(count, tostring(C_Item.IsUsableItem(id))))
        end
    end
    for _, id in ipairs(TOYS) do
        local usable = C_ToyBox and C_ToyBox.IsToyUsable and tostring(C_ToyBox.IsToyUsable(id)) or "unknown"
        Line(id, true, ("toy, owned %s, usable %s"):format(tostring(PlayerHasToy(id)), usable))
    end
end
