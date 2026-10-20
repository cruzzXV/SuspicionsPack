-- SuspicionsPack — AnimatedPortraits Module
--
-- Living 3D models in place of the flat portrait pictures: unit frames, party
-- frames, NPC dialogue windows and the windows that draw a unit (character,
-- inspect, trade...).
--
-- The game draws every portrait through SetPortraitTexture(texture, unit),
-- which is hooked; each portrait texture gets one PlayerModel of its own laid
-- over it, and the flat picture is made invisible while the model shows. On
-- top of that: per-frame choice, camera framing and rotation, animation and
-- freeze, NPCs that talk, background styles including the unit's class
-- colour, combat behaviour.
--
-- WHY THE DISC AND THE FADE
--   Blizzard's portraits are round: masked to a circle and framed by ring art.
--   A model cannot be masked, it is a square, and its corners would cut a
--   straight edge across the circle. So the model gets a disc behind it and a
--   soft fade over its edges, both textures, which CAN be masked to the circle.
--   On a unit frame the three are slid one strata under the frame, so the ring
--   art and the level badge are drawn over them (see Levels).
--
-- WHEN THE FLAT PICTURE COMES BACK
--   The unit is gone or out of sight, the model has not loaded, the game put a
--   plain picture on the texture (book or class icon), the game tints the
--   picture to say something (dead, ghost, tapped, offline), the identity is
--   secret, the part is switched off, or the module is.
--
-- All state lives in local tables keyed by texture; nothing is written onto
-- Blizzard frames. Every value read from a unit can be a secret on retail and
-- is tested with issecretvalue before any comparison (see tasks/lessons.md).
local SP = SuspicionsPack

local AP = SP:NewSPModule("AnimatedPortraits", "animatedPortraits")
SP.AnimatedPortraits = AP

-- ============================================================
-- Constants
-- ============================================================
-- The model square on a unit frame, as a share of the circle, is the user's
-- `frameFill`. A window keeps its square here: no ring is drawn over it, so
-- its corners must stay inside the circle.
local WINDOW_SQ  = 0.70
local FADE_EDGE  = 0.70  -- Media\Portraits\fade.tga is opaque from this share of its radius out
local LOAD_CHECK = 0.25  -- seconds; a cached model may never fire OnModelLoaded
local CIRCLE     = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local FADE       = "Interface\\AddOns\\SuspicionsPack\\Media\\Portraits\\fade"
local DARK       = { 0.04, 0.04, 0.06 }

-- Animation IDs (AnimationData). A model that lacks one falls back to Stand.
local ANIM_STAND = 0
local ANIM_TALK  = 60

-- One strata down puts our frames under every part of a unit frame, whatever
-- their levels (the player frame sits at level 1-2, with no room below).
local STRATA_BELOW = {
    LOW = "BACKGROUND", MEDIUM = "LOW", HIGH = "MEDIUM", DIALOG = "HIGH",
    FULLSCREEN = "DIALOG", FULLSCREEN_DIALOG = "FULLSCREEN", TOOLTIP = "FULLSCREEN_DIALOG",
}

-- Category -> DB key of its toggle.
local CATEGORY_KEYS = {
    player       = "showPlayer",
    target       = "showTarget",
    focus        = "showFocus",
    pet          = "showPet",
    targettarget = "showTargetTarget",
    party        = "showParty",
    boss         = "showBoss",
    npc          = "showNPC",
    windows      = "showWindows",
    other        = "showOther",
}

-- Which side of the screen a unit frame's portrait looks from, for "faces look
-- at each other". Windows and NPC dialogues have no opposite and stay as set.
local FACE_SIDE = {
    player = "player", pet = "player", party = "player",
    target = "target", focus = "target", targettarget = "target", boss = "target",
}

-- ============================================================
-- State
-- ============================================================
-- [texture] = { unit, guid, alpha, round, framed, category, model, back, disc,
--               cover, fade, dirty, loaded, checking, loadTime, shown, hiding,
--               tinted, gameTint, blocked, w, h, camScale, showing }
local entries = {}
local pending = {}   -- [texture] = true, waiting for combat to end
local hooked  = {}   -- [texture] = true, per-texture hooks installed
local portraitHooked = false

local watcher        -- event frame, created on first Activate
local Swapped        -- defined with the events below
local Refresh        -- forward declaration: the per-texture hooks call it

-- ============================================================
-- Helpers
-- ============================================================
local function DB() return AP:GetDB() end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

-- A test on a unit that may come back secret: a secret answer counts as no.
local function Is(fn, unit)
    if not fn then return false end
    local v = fn(unit)
    if Secret(v) then return false end
    return v and true or false
end

-- The game tints the flat picture for these (grey, blue, desaturated); a model
-- would hide that, so the picture stays -- unless the user asked otherwise.
local function Tinted(unit)
    return Is(UnitIsDeadOrGhost, unit) or Is(UnitIsTapDenied, unit)
        or (Is(UnitIsPlayer, unit) and UnitIsConnected and not Is(UnitIsConnected, unit))
end

-- The game keeps some units' identity from addons (SetUnit then fails); a
-- secret answer counts as hidden.
local function Hidden(unit)
    local fn = C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret
    if not fn then return false end
    local v = fn(unit)
    if Secret(v) then return true end
    return v and true or false
end

local function Same(a, b)
    if a == b then return true end
    local same = UnitIsUnit(a, b)
    return not Secret(same) and same and true or false
end

-- Which toggle governs this portrait. `framed` = on a unit frame, so a player
-- portrait in the character window counts as a window, not as "player".
local function Category(unit, framed)
    unit = unit:lower()
    if unit == "npc" or unit == "questnpc" then return "npc" end
    if not framed then return "windows" end
    if unit:find("^party") or unit:find("^raid") then return "party" end
    if unit == "player" or unit == "vehicle" then return "player" end
    if unit == "target" then return "target" end
    if unit == "focus" then return "focus" end
    if unit == "pet" then return "pet" end
    if unit:find("target$") then return "targettarget" end
    if unit:find("^boss") or unit:find("^arena") then return "boss" end
    return "other"
end

-- A unit frame is a secure unit button carrying a "unit" attribute; its
-- portrait sits one to three frames below it. Windows that draw a unit's
-- portrait (character, inspect, NPC dialogues) have no such attribute.
local function OnUnitFrame(texture)
    local frame = texture:GetParent()
    for _ = 1, 3 do
        if not frame or (frame.IsForbidden and frame:IsForbidden()) then return false end
        if frame.GetAttribute and frame:GetAttribute("unit") then return true end
        frame = frame:GetParent()
    end
    return false
end

local function MinSize()
    local db = DB()
    local v = db and db.minSize
    if v == nil then return 30 end
    return v
end

local function BigEnough(texture)
    local w, h = texture:GetSize()
    return w and h and math.min(w, h) >= MinSize()
end

-- Only for the load check: the model is cleared before a new unit, so a file
-- ID is the new unit's.
local function Loaded(model)
    if not model.GetModelFileID then return true end
    local id = model:GetModelFileID()
    return id ~= nil and id ~= 0
end

local function Wanted(texture, e)
    local db = DB()
    if not (db and db.enabled) or not e.unit then return false end
    if not db[CATEGORY_KEYS[e.category] or "showOther"] then return false end
    if db.flatInCombat and InCombatLockdown() then return false end
    if not texture:IsShown() or not BigEnough(texture) then return false end
    -- The game's own tint on the picture, or a state it leaves untinted (a
    -- dead mob). "keepFlatWhenTinted" off: the model stays anyway.
    e.tinted = e.gameTint or Tinted(e.unit)
    if e.tinted and db.keepFlatWhenTinted ~= false then return false end
    return UnitExists(e.unit) and UnitIsVisible(e.unit)
end

-- ============================================================
-- Look
-- ============================================================

-- The disc and fade colour: dark, the unit's class, the theme, or custom.
local function BackgroundColor(e)
    local db = DB()
    local style = db.backgroundStyle or "dark"
    if style == "unitclass" and e.unit then
        local _, cls = UnitClass(e.unit)
        if cls and not Secret(cls) then
            local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
            if c then return c.r, c.g, c.b end
        end
        return DARK[1], DARK[2], DARK[3]
    elseif style == "theme" or style == "custom" then
        return SP.GetColorFromSource(style, db.backgroundColor)
    end
    return DARK[1], DARK[2], DARK[3]
end

local function Percent(v, default)
    if v == nil then v = default end
    return v / 100
end

-- Animation and pause. Called on load, on show, on combat and on settings.
local function ApplyMotion(e)
    local model = e.model
    if not model then return end
    local db = DB()

    local anim = db.animation or ANIM_STAND
    if e.category == "npc" and db.npcTalk then anim = ANIM_TALK end

    local paused = (db.animate == false)
        or (db.pauseInCombat and InCombatLockdown()) and true or false

    -- SetPaused where the model type has it; otherwise a frozen first frame of
    -- the same animation, and SetAnimation again to let it play.
    if model.SetPaused then
        if model.SetAnimation then model:SetAnimation(anim) end
        model:SetPaused(paused)
    elseif paused and model.FreezeAnimation then
        model:FreezeAnimation(anim, 0, 0)
    elseif model.SetAnimation then
        model:SetAnimation(anim)
    end
end

-- Camera: how much of the body, how close, which way it faces, where it sits.
local function ApplyCamera(e)
    local model = e.model
    if not model then return end
    local db = DB()
    model:SetPortraitZoom(Percent(db.zoom, 100))
    model:SetCamDistanceScale(e.camScale or 1)
    local ox = (db.offsetX or 0) / 100
    local oy = (db.offsetY or 0) / 100
    model:SetPosition(0, ox, oy)
    if model.SetFacing then
        local deg = db.rotation or 0
        -- Faces look at each other. Flipping the sign of `rotation` alone did
        -- nothing at the default rotation of 0, so the option also turns each
        -- side inward by `faceTurn`: positive facing turns a model's face to
        -- the viewer's right, toward the target, so the player side gets +turn
        -- and the target side the mirror of everything. A negative faceTurn
        -- turns them apart, which is also the escape hatch if a client turns
        -- the other way.
        if db.mirrorTargetSide then
            local side = FACE_SIDE[e.category]
            local turn = db.faceTurn or 25
            if side == "target" then
                deg = -deg - turn
            elseif side == "player" then
                deg = deg + turn
            end
        end
        model:SetFacing(math.rad(deg))
    end
end

local function Flat(texture)
    local e = entries[texture]
    if not e then return end
    -- Already flat: the game redraws some portraits every frame.
    if not e.shown and not (e.model and e.model:IsShown()) then return end
    if e.model then
        e.model:SetAlpha(0)
        e.model:Hide()
        e.back:Hide()
        e.cover:Hide()
    end
    e.shown = false
    e.hiding = true
    texture:SetAlpha(e.alpha)
    e.hiding = false
end

local function Show3D(texture)
    local e = entries[texture]
    if e.showing then return end
    local db = DB()
    -- Showing a model can fire its OnModelLoaded at once, which comes back here.
    e.showing = true
    if not e.model:IsShown() then e.model:Show() end
    e.showing = false

    e.model:SetAlpha(Percent(db.modelAlpha, 100))

    local r, g, b = BackgroundColor(e)
    local a = Percent(db.backgroundAlpha, 100)
    e.disc:SetColorTexture(r, g, b, a)
    e.fade:SetVertexColor(r, g, b, a)
    local bg = db.background ~= false
    e.back:SetShown(bg)
    e.cover:SetShown(e.round and bg and db.edgeFade ~= false)

    ApplyMotion(e)

    e.shown = true
    e.hiding = true
    texture:SetAlpha(0)
    e.hiding = false
end

-- back (disc) < model < cover (fade) < the unit frame's own parts.
-- A window keeps our frames on top of its portrait: one strata down would put
-- them under the window's own background.
local function Levels(texture, e)
    local host = texture:GetParent()
    local level = host:GetFrameLevel()
    local below = STRATA_BELOW[host:GetFrameStrata()]
    if below and e.framed then
        e.back:SetFrameStrata(below)
        e.model:SetFrameStrata(below)
        e.cover:SetFrameStrata(below)
        e.back:SetFrameLevel(1)
        e.model:SetFrameLevel(2)
        e.cover:SetFrameLevel(3)
        return
    end
    e.back:SetFrameLevel(level + 1)
    e.model:SetFrameLevel(level + 2)
    e.cover:SetFrameLevel(level + 3)
end

local function Layout(texture, e)
    local model = e.model
    model:ClearAllPoints()
    if e.round then
        local w, h = texture:GetSize()
        local d = math.min(w, h)
        -- Two separate things:
        --   square -- how far the model reaches toward the ring. The model
        --             cannot be masked round, so between its edge and the ring
        --             the dark disc shows, as a thin black ring (reported with a
        --             screenshot, 2026-10-20). Bigger closes that gap; past the
        --             ring's thickness the square's corners show at the
        --             diagonals, where the bars and the level badge usually sit.
        --   fill   -- how big the face is in the circle. Pure camera: a smaller
        --             face pulls the camera back inside the same square.
        -- They used to be one value, min(fill, 0.80), which pinned the model
        -- at 80% of the circle whatever the face size.
        local db = DB()
        local fill = Percent(db.size, 80)
        local square
        if e.framed then
            square = Percent(db.frameFill, 90)
        else
            square = math.min(fill, WINDOW_SQ)
        end
        e.camScale = square / fill
        model:SetPoint("CENTER", texture, "CENTER")
        model:SetSize(d * square, d * square)
        -- The fade is opaque from FADE_EDGE of its radius out. It stays the
        -- size of the portrait (a bigger one runs past the game's mask, whose
        -- edge pixels then smear outward) and is zoomed with texture
        -- coordinates so its opaque edge lands on the model's edge.
        local half = 0.5 * FADE_EDGE / square
        e.fade:SetTexCoord(0.5 - half, 0.5 + half, 0.5 - half, 0.5 + half)
    else
        e.camScale = 1
        model:SetAllPoints(texture)
    end
    ApplyCamera(e)
    Levels(texture, e)
end

local function Build(texture, e)
    local host = texture:GetParent()

    local back = CreateFrame("Frame", nil, host)
    back:SetAllPoints(texture)
    local disc = back:CreateTexture(nil, "BACKGROUND")
    disc:SetAllPoints()
    disc:SetColorTexture(DARK[1], DARK[2], DARK[3], 1)
    back:Hide()

    local model = CreateFrame("PlayerModel", nil, host)
    model:SetAlpha(0)
    model:Hide()
    model:SetScript("OnModelLoaded", function()
        local entry = entries[texture]
        if not entry then return end
        entry.loaded = true
        ApplyCamera(entry)
        if Wanted(texture, entry) then Show3D(texture) end
    end)
    -- Hidden (target cleared, frame closed): the unit may look different by
    -- the time it is back, so its model is loaded again then.
    model:SetScript("OnHide", function()
        local entry = entries[texture]
        if entry then entry.dirty = true end
    end)

    -- Above the model: fades its square edges into the disc.
    local cover = CreateFrame("Frame", nil, host)
    cover:SetAllPoints(texture)
    local fade = cover:CreateTexture(nil, "OVERLAY")
    fade:SetAllPoints(texture)
    fade:SetTexture(FADE)
    cover:Hide()

    -- The same shape the game cuts the portrait with: its own mask, copied.
    if e.round then
        local own = texture.GetMaskTexture and texture:GetMaskTexture(1)
        for _, region in ipairs({ disc, fade }) do
            local mask = region:GetParent():CreateMaskTexture()
            local atlas = own and own.GetAtlas and own:GetAtlas()
            if atlas then
                mask:SetAtlas(atlas)
            else
                mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            end
            if own and own:GetNumPoints() > 0 then
                for i = 1, own:GetNumPoints() do mask:SetPoint(own:GetPoint(i)) end
                mask:SetSize(own:GetSize())
            else
                mask:SetAllPoints(texture)
            end
            region:AddMaskTexture(mask)
        end
    end

    e.model, e.back, e.disc, e.cover, e.fade = model, back, disc, cover, fade
end

-- Real implementation of the forward-declared local.
Refresh = function(texture, force)
    local e = entries[texture]
    if not e then return end
    if not Wanted(texture, e) then
        Flat(texture)
        return
    end

    if not e.model then
        if InCombatLockdown() and texture:GetParent():IsProtected() then
            pending[texture] = true
            Flat(texture)
            return
        end
        Build(texture, e)
        e.dirty = true
    end

    -- The target of target is redrawn every frame: nothing new, nothing to do.
    local w, h = texture:GetSize()
    local resized = w ~= e.w or h ~= e.h
    if e.shown and not e.dirty and not force and not resized then return end

    -- No model for a hidden identity: the picture stays until the next swap or
    -- the end of combat.
    if e.dirty and (e.blocked or Hidden(e.unit)) then
        pending[texture] = true
        Flat(texture)
        return
    end

    if force or resized then
        e.w, e.h = w, h
        Layout(texture, e)
    end

    local model = e.model
    -- A new unit: nothing of the last one's model may show (cleared before
    -- Show, which can fire OnModelLoaded).
    local fresh = e.dirty and not e.shown
    if fresh then model:ClearModel() end
    if not model:IsShown() then model:Show() end
    if e.dirty then
        e.dirty = false
        e.loaded = false
        local ok, set = pcall(model.SetUnit, model, e.unit)
        if not ok or (not Secret(set) and set == false) then
            e.dirty, e.blocked = true, true
            model:ClearModel()
            pending[texture] = true
            Flat(texture)
            return
        end
        -- The game's update and our event may both ask for the same new unit.
        if fresh then e.loadTime = GetTime() end
        ApplyCamera(e)
    elseif force then
        ApplyCamera(e)
    end

    -- A model already on screen stays while the same unit loads again.
    if e.loaded or e.shown then
        Show3D(texture)
    elseif not e.checking then
        -- Keep the flat picture until the model is there; one check at a time.
        e.checking = true
        C_Timer.After(LOAD_CHECK, function()
            local entry = entries[texture]
            if not entry then return end
            entry.checking = nil
            if entry.model and not entry.loaded and not entry.dirty and Loaded(entry.model) then
                entry.loaded = true
            end
            if entry.loaded and Wanted(texture, entry) then Show3D(texture) end
        end)
    end
end

-- ============================================================
-- Hooks
-- ============================================================
local function Hook(texture)
    if hooked[texture] then return end
    hooked[texture] = true

    -- The game put a plain picture here (book, class or buyback icon).
    local function Picture()
        local e = entries[texture]
        if e then
            e.unit = nil
            Flat(texture)
        end
    end
    hooksecurefunc(texture, "SetTexture", Picture)
    hooksecurefunc(texture, "SetAtlas", Picture)

    -- The game sets the portrait's alpha now and then; the flat picture gets
    -- it back later, under a model the texture stays hidden.
    hooksecurefunc(texture, "SetAlpha", function(_, alpha)
        local e = entries[texture]
        if not e or e.hiding then return end
        if not Secret(alpha) and type(alpha) == "number" then e.alpha = alpha end
        if e.shown then
            e.hiding = true
            texture:SetAlpha(0)
            e.hiding = false
        end
    end)

    -- The game tints the picture to show a state; the flat picture then shows it.
    local function Tint()
        local e = entries[texture]
        -- Only unit frames tint their portrait to show a state.
        if not e or not e.framed then return end
        local tinted = false
        if texture.IsDesaturated then
            local d = texture:IsDesaturated()
            if not Secret(d) and d then tinted = true end
        end
        if not tinted and texture.GetVertexColor then
            local r, g, b = texture:GetVertexColor()
            if not (Secret(r) or Secret(g) or Secret(b)) and r and g and b then
                tinted = r < 0.99 or g < 0.99 or b < 0.99
            end
        end
        if tinted ~= (e.gameTint or false) then
            e.gameTint = tinted
            Refresh(texture)
        end
    end
    hooksecurefunc(texture, "SetVertexColor", Tint)
    if texture.SetDesaturated then hooksecurefunc(texture, "SetDesaturated", Tint) end
    if texture.SetDesaturation then hooksecurefunc(texture, "SetDesaturation", Tint) end

    local function Sync() Refresh(texture) end
    hooksecurefunc(texture, "Show", Sync)
    hooksecurefunc(texture, "Hide", Sync)
    hooksecurefunc(texture, "SetShown", Sync)
end

local function OnPortrait(texture, unit)
    -- The hook is permanent (hooksecurefunc cannot be removed): it gates itself
    -- on the live setting, and does nothing at all while the module is off.
    if not AP:IsOn() then return end
    if type(texture) ~= "table" or type(unit) ~= "string" or not texture.GetObjectType then return end
    if texture.IsForbidden and texture:IsForbidden() then return end
    -- The character micro button draws your portrait too; a model there would
    -- not fade with a hidden menu bar, and the micro menu skin owns it.
    if CharacterMicroButton and texture == CharacterMicroButton.Portrait then return end
    -- Nor the side tabs of the character and inspect windows, which are buttons.
    local parent = texture:GetParent()
    if parent and parent.InitializeIconAnchoring then return end
    if PaperDollSidebarTab1 and texture == PaperDollSidebarTab1.Icon then return end

    local e = entries[texture]
    if not e then
        if not BigEnough(texture) then return end
        local framed = OnUnitFrame(texture)
        e = {
            alpha  = texture:GetAlpha(),
            round  = (texture.GetNumMaskTextures and texture:GetNumMaskTextures() or 0) > 0,
            framed = framed,
        }
        entries[texture] = e
        Hook(texture)
    end

    -- The game redraws portraits all the time; load a model only for a new
    -- unit. Until it is there the game's fresh flat picture shows, not the
    -- previous unit's model.
    local guid = UnitGUID(unit)
    -- A hidden identity can't be compared; a new unit is then told by the
    -- target / focus / group events instead (see Swapped).
    if Secret(guid) then guid = nil end
    if e.unit ~= unit or e.guid ~= guid then
        Flat(texture)
        e.unit, e.guid = unit, guid
        e.category = Category(unit, e.framed)
        e.dirty, e.blocked = true, nil
    end
    Refresh(texture)
end

-- ============================================================
-- Events
-- ============================================================

-- New gear or shape: load the model again; a portrait update needs no reload.
local function UnitChanged(unit, reload)
    if not unit then return end
    for texture, e in pairs(entries) do
        if e.unit and Same(e.unit, unit) then
            if reload then e.dirty = true end
            -- A closed window loads it when it is drawn again.
            if texture:IsVisible() then Refresh(texture) end
        end
    end
end

-- Another unit on a portrait whose identity is hidden (no GUID to compare):
-- the flat picture first, then the new model.
Swapped = function(pattern)
    for texture, e in pairs(entries) do
        -- Not when the game's own update for this event loaded it fresh already.
        if e.unit and e.guid == nil and e.unit:find(pattern) and e.loadTime ~= GetTime() then
            Flat(texture)
            e.dirty, e.blocked = true, nil
            Refresh(texture)
        end
    end
end

-- Died, released, came back, went offline, got tapped: only a change of that
-- look refreshes the portrait. UNIT_HEALTH comes often, so the cheap unit
-- equality runs before anything else.
local function StateChanged(unit)
    if not unit then return end
    for texture, e in pairs(entries) do
        if e.unit and texture:IsVisible() and Same(e.unit, unit) then
            local tinted = e.gameTint or Tinted(e.unit)
            if tinted ~= e.tinted then
                e.tinted = tinted
                Refresh(texture)
            end
        end
    end
end

-- Settings change the look; a part switched off and on loads its models anew.
local function ApplyAll()
    for texture, e in pairs(entries) do
        e.w = nil  -- laid out again
        if texture:IsVisible() then
            -- Forced: re-lays it out, and Show3D re-reads colours, alpha, motion.
            Refresh(texture, true)
        else
            -- A closed window: the picture, and a new model once drawn again.
            Flat(texture)
            e.dirty = true
        end
    end
end
AP.ApplyAll = ApplyAll

local function OnCombatEnd()
    -- A refresh may put a texture back on the list.
    local list = {}
    for texture in pairs(pending) do list[#list + 1] = texture end
    wipe(pending)
    for _, texture in ipairs(list) do
        local e = entries[texture]
        if e then e.blocked = nil end
        Refresh(texture)
    end
    local db = DB()
    if db and (db.flatInCombat or db.pauseInCombat) then ApplyAll() end
end

local function OnCombatStart()
    local db = DB()
    if not db then return end
    if db.flatInCombat then
        for texture in pairs(entries) do Flat(texture) end
    elseif db.pauseInCombat then
        for _, e in pairs(entries) do
            if e.shown then ApplyMotion(e) end
        end
    end
end

local EVENTS = {
    "UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE",
    "UNIT_HEALTH", "UNIT_FLAGS", "UNIT_CONNECTION", "UNIT_FACTION",
    "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_TARGET", "UNIT_PET",
    "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
}

local function OnEvent(_, event, unit)
    if event == "UNIT_HEALTH" or event == "UNIT_FLAGS"
        or event == "UNIT_CONNECTION" or event == "UNIT_FACTION" then
        StateChanged(unit)
    elseif event == "PLAYER_TARGET_CHANGED" then
        Swapped("^target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        Swapped("^focus")
    elseif event == "UNIT_TARGET" then
        if unit == "target" then Swapped("^targettarget$") end
    elseif event == "UNIT_PET" then
        if unit == "player" then Swapped("^pet$") end
    elseif event == "GROUP_ROSTER_UPDATE" then
        Swapped("^party")
    elseif event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnCombatEnd()
    else
        UnitChanged(unit, event == "UNIT_MODEL_CHANGED")
    end
end

-- The Edit Mode party background sits at level 1 of the party frames' strata,
-- where the models (one strata down) would be under it. It is a plain
-- backdrop, so it moves to the bottom, after the game has placed it.
local partyBgHooked = false
local function LowerPartyBackground()
    local bg = PartyFrame and PartyFrame.Background
    if not bg or (bg.IsProtected and bg:IsProtected()) then return end
    if not partyBgHooked then
        partyBgHooked = true
        bg:HookScript("OnShow", function(self)
            if not AP:IsOn() then return end
            self:SetFrameStrata("BACKGROUND")
            self:SetFrameLevel(0)
        end)
    end
    if bg:IsShown() then
        bg:SetFrameStrata("BACKGROUND")
        bg:SetFrameLevel(0)
    end
end

-- Portraits already on screen when the module turns on are only redrawn by the
-- game on its next update, which for your own frame can be a long wait. This
-- asks for them again, through the same SetPortraitTexture the game uses, so
-- the hook above picks them up. Paths are the Midnight-family frames shared by
-- Forever; a missing one is skipped. Out of combat only.
local PRIME = {
    { "player", function() return PlayerFrame and PlayerFrame.PlayerFrameContainer
                                  and PlayerFrame.PlayerFrameContainer.PlayerPortrait end },
    { "target", function() return TargetFrame and TargetFrame.TargetFrameContainer
                                  and TargetFrame.TargetFrameContainer.Portrait end },
    { "focus",  function() return FocusFrame and FocusFrame.TargetFrameContainer
                                  and FocusFrame.TargetFrameContainer.Portrait end },
    { "pet",    function() return _G.PetPortrait end },
}

local function PrimePortraits()
    if InCombatLockdown() then return end
    local function Ask(texture, unit)
        if texture and UnitExists(unit) then pcall(SetPortraitTexture, texture, unit) end
    end
    for _, p in ipairs(PRIME) do Ask(p[2](), p[1]) end
    local party = PartyFrame
    if party then
        for i = 1, 4 do
            local member = party["MemberFrame" .. i]
            Ask(member and member.Portrait, "party" .. i)
        end
    end
end

-- ============================================================
-- Activate / Deactivate
-- Everything else (Refresh / OnEnable / OnDisable) comes from SP.ModuleMixin.
-- The GUI calls Refresh -> Activate on every setting it touches, so Activate
-- is idempotent: hooks once, events re-registered, everything re-applied.
-- ============================================================
function AP:Activate()
    if not portraitHooked then
        portraitHooked = true
        hooksecurefunc("SetPortraitTexture", OnPortrait)
    end
    if not watcher then
        watcher = CreateFrame("Frame")
        watcher:SetScript("OnEvent", OnEvent)
    end
    for _, event in ipairs(EVENTS) do watcher:RegisterEvent(event) end
    LowerPartyBackground()
    ApplyAll()
    PrimePortraits()
end

function AP:Deactivate()
    if watcher then watcher:UnregisterAllEvents() end
    wipe(pending)
    -- Back to the flat pictures; a model is loaded anew if switched back on.
    for texture, e in pairs(entries) do
        Flat(texture)
        e.dirty = true
    end
end

-- ============================================================
-- Debug: /spack debug portraits
-- The real numbers of every portrait on screen, so the look can be tuned to
-- the game's frames instead of guessed.
-- ============================================================
function AP.DebugDump()
    local function name(f) return f and (f.GetDebugName and f:GetDebugName() or f:GetName()) or "-" end
    local function lvl(f) return f and (f:GetFrameStrata() .. " " .. f:GetFrameLevel()) or "-" end
    local count = 0
    print("|cffe51039SuspicionsPack|r animated portraits:" .. (AP:IsOn() and "" or " |cffff5555module off|r"))
    for texture, e in pairs(entries) do
        if e.unit and texture:IsVisible() then
            count = count + 1
            local w, h = texture:GetSize()
            print(("  %s [%s, %s] %.1fx%.1f round=%s framed=%s shown=%s tinted=%s blocked=%s"):format(
                name(texture), e.unit, tostring(e.category), w, h, tostring(e.round),
                tostring(e.framed), tostring(e.shown), tostring(e.tinted), tostring(e.blocked)))
            if e.model then
                print(("    back %s, model %s (%.1f, cam %.2f), cover %s"):format(
                    lvl(e.back), lvl(e.model), e.model:GetWidth(), e.camScale or 1, lvl(e.cover)))
            end
        end
    end
    if count == 0 then print("  no portrait on screen") end
end
