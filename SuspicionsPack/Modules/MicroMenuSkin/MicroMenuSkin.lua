-- SuspicionsPack — MicroMenuSkin Module
-- Reskins the Blizzard micro menu (character, spellbook, talents, ...) in the
-- ElvUI style: flat dark backdrop + thin border per button, accent-coloured
-- border on hover, all of Blizzard's button chrome stripped away and the icon
-- glyph cropped so it fills the square.
--
-- VISUAL SKIN ONLY. Button placement stays wherever Blizzard / Edit Mode puts
-- it -- we never reparent or move buttons, which keeps this taint-free and
-- safe in combat.
--
-- Reference: ElvUI/Game/Shared/Modules/ActionBars/MicroBar.lua (chrome element
-- names, the OnEnter alpha workaround and the SetHighlightAtlas hook come from
-- there). No ElvUI media is used -- icons are Blizzard's own atlas glyphs.

local SP = SuspicionsPack

local MMS = SP:NewModule("MicroMenuSkin", "AceEvent-3.0")
SP.MicroMenuSkin = MMS

-- ============================================================
-- Locals
-- ============================================================
local _G             = _G
local hooksecurefunc = hooksecurefunc
local C_Timer        = C_Timer
local C_Texture      = C_Texture
local ipairs         = ipairs
local type           = type

-- Every micro button we know about. Not all exist on every build (Housing is
-- Midnight-only, PlayerSpells replaced Talent in TWW, the Classic-only names
-- never resolve on retail), so every lookup is guarded.
local MICRO_BUTTONS = {
    "CharacterMicroButton",
    "SpellbookMicroButton",
    "ProfessionMicroButton",
    "TalentMicroButton",
    "PlayerSpellsMicroButton",
    "AchievementMicroButton",
    "QuestLogMicroButton",
    "GuildMicroButton",
    "SocialsMicroButton",
    "LFDMicroButton",
    "LFGMicroButton",
    "EJMicroButton",
    "CollectionsMicroButton",
    "MainMenuMicroButton",
    "HelpMicroButton",
    "StoreMicroButton",
    "HousingMicroButton",
    "WorldMapMicroButton",
    "PVPMicroButton",
}

-- Blizzard's button chrome. Killing these leaves just the icon glyph on a
-- transparent button, which is what our backdrop sits behind.
local CHROME_KEYS = {
    "Background",
    "PushedBackground",
    "PushedShadow",
    "Flash",
    "FlashContent",
}

-- ============================================================
-- DB helper
-- ============================================================
local function GetDB()
    return SP.GetDB().microMenuSkin
end

-- Colour channels legitimately take 0, and 0 is truthy in Lua, so `or` here
-- only fires on nil -- which is exactly the fallback we want.
local function Col(c, dr, dg, db_, da)
    if type(c) == "table" then
        return c.r or dr, c.g or dg, c.b or db_, c.a or da
    end
    return dr, dg, db_, da
end

-- Numeric fallback that survives a stored 0 (Lua truthiness trap).
local function Num(v, default)
    if v == nil then return default end
    return v
end

-- ============================================================
-- Module state
-- ============================================================
local hookedUpdate = false   -- hooksecurefunc("UpdateMicroButtons") installed
local hookedPulse  = false   -- hooksecurefunc("MicroButtonPulse") installed
local applying     = false   -- re-entrancy guard
local pendingApply = false   -- coalescing flag for QueueApply
local hidPerfBar   = false   -- so the perf bar can be restored
local hidPVPTex    = false

-- GetAtlasInfo allocates a table per call and UpdateMicroButtons fires on
-- every bag/spell/quest/regen change, so results are cached by atlas name.
-- Atlas definitions are static for a session, so this never goes stale.
local atlasInfoCache = {}

local function GetCachedAtlasInfo(atlas)
    local info = atlasInfoCache[atlas]
    if info == nil then
        info = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) or false
        atlasInfoCache[atlas] = info
    end
    return info or nil
end

-- ============================================================
-- Texture helpers
-- ============================================================

-- Anchors a texture inside a frame with a uniform inset.
local function SetInside(tex, frame, inset)
    if not tex then return end
    inset = inset or 0
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT",     frame, "TOPLEFT",      inset, -inset)
    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset,  inset)
end

-- Crops a texture inward by `zoom` (0..0.45) so the glyph fills the square.
--
-- Retail micro buttons use atlas textures. SetTexCoord after SetAtlas would
-- discard the atlas sub-rect and show the whole packed sheet, so the atlas is
-- resolved to file + UVs first and the crop applied inside those UVs.
--
-- Atlas resolution is deliberately re-probed on every call:
--   * GetAtlas() returns the live atlas whenever Blizzard just set one, so
--     state-dependent art (main menu update indicator, character portrait)
--     stays current instead of freezing on the first atlas we ever saw.
--   * GetAtlas() returns nil right after WE call SetTexture(), so the cached
--     name is what we fall back on -- without it we would crop the raw sheet
--     and corrupt the icon permanently.
-- `false` in the cache means "probed, genuinely not atlas-based", and is
-- treated as nil so a texture Blizzard populates late still gets picked up.
local function ZoomTexture(tex, zoom)
    if not tex then return end

    local live = tex.GetAtlas and tex:GetAtlas()
    if live then tex._spAtlas = live end

    local atlas = tex._spAtlas
    if atlas == false then atlas = nil end

    if not zoom or zoom <= 0 then
        if atlas then
            tex:SetAtlas(atlas)
        else
            tex:SetTexCoord(0, 1, 0, 1)
        end
        return
    end

    if atlas then
        local info = GetCachedAtlasInfo(atlas)
        if info then
            local l = info.leftTexCoord   or 0
            local r = info.rightTexCoord  or 1
            local t = info.topTexCoord    or 0
            local b = info.bottomTexCoord or 1
            local dx = (r - l) * zoom
            local dy = (b - t) * zoom
            local file = info.file or info.filename
            if file then tex:SetTexture(file) end
            tex:SetTexCoord(l + dx, r - dx, t + dy, b - dy)
        end
        -- Atlas known but no info: leave the UVs alone rather than cropping
        -- the whole sheet.
        return
    end

    if tex.GetAtlas then tex._spAtlas = false end
    tex:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
end

-- Creates (once) the 5 textures that make up our backdrop: a fill plus four
-- edges. Drawn on the button itself at BACKGROUND sublevel -8/-7 so they sit
-- behind the icon glyph without any frame-level juggling.
local function EnsureBackdrop(button)
    if button._spmm then return button._spmm end

    local bd = {}
    bd.fill = button:CreateTexture(nil, "BACKGROUND", nil, -8)
    bd.fill:SetAllPoints(button)

    local names = { "top", "bottom", "left", "right" }
    for _, k in ipairs(names) do
        bd[k] = button:CreateTexture(nil, "BACKGROUND", nil, -7)
    end

    button._spmm = bd
    return bd
end

local function LayoutBackdrop(bd, button, thickness)
    bd.top:ClearAllPoints()
    bd.top:SetPoint("TOPLEFT",  button, "TOPLEFT",  0, 0)
    bd.top:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
    bd.top:SetHeight(thickness)

    bd.bottom:ClearAllPoints()
    bd.bottom:SetPoint("BOTTOMLEFT",  button, "BOTTOMLEFT",  0, 0)
    bd.bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    bd.bottom:SetHeight(thickness)

    bd.left:ClearAllPoints()
    bd.left:SetPoint("TOPLEFT",    button, "TOPLEFT",    0, 0)
    bd.left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
    bd.left:SetWidth(thickness)

    bd.right:ClearAllPoints()
    bd.right:SetPoint("TOPRIGHT",    button, "TOPRIGHT",    0, 0)
    bd.right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
    bd.right:SetWidth(thickness)
end

local function SetBorderColor(button, r, g, b, a)
    local bd = button._spmm
    if not bd then return end
    bd.top:SetColorTexture(r, g, b, a)
    bd.bottom:SetColorTexture(r, g, b, a)
    bd.left:SetColorTexture(r, g, b, a)
    bd.right:SetColorTexture(r, g, b, a)
end

-- ============================================================
-- Hover handlers
--
-- Hooked once per button. They read the DB live so colour changes in the GUI
-- apply on the next hover without a full re-skin pass.
-- ============================================================
local function OnEnterButton(button)
    local db = GetDB()
    if not (db and db.enabled) then return end

    -- ElvUI: once skinned, the normal texture is no longer baked into the
    -- highlight, so it has to be re-shown explicitly on hover.
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal then
        normal:SetAlpha(1)
        if db.desaturate then normal:SetDesaturated(false) end
    end

    if button.IsEnabled and not button:IsEnabled() then return end
    local r, g, b, a = Col(db.hoverColor, 0.90, 0.06, 0.22, 1)
    SetBorderColor(button, r, g, b, a)
end

local function OnLeaveButton(button)
    local db = GetDB()
    if not (db and db.enabled) then return end

    if db.desaturate then
        local normal = button.GetNormalTexture and button:GetNormalTexture()
        if normal then normal:SetDesaturated(true) end
    end

    local r, g, b, a = Col(db.borderColor, 0, 0, 0, 1)
    SetBorderColor(button, r, g, b, a)
end

-- ============================================================
-- Flash / pulse suppression
--
-- Blizzard runs MicroButtonPulse() on new-content alerts, which animates
-- button.FlashBorder. On an unskinned button that reads as a glow around the
-- Blizzard frame art; on our flat square it covers the whole button and reads
-- as the icon blinking. Killed outright rather than flattened.
-- ============================================================
local function KillTex(t)
    if not t then return end
    t:SetTexture(nil)
    t:SetAlpha(0)
    t:Hide()
end

local function KillFlash(button)
    -- Stop first. UIFrameFlashStop() resets alpha to 1 and shows the frame, so
    -- anything blanked before this call would be undone by it. Stopping also
    -- pulls the textures out of FLASHFRAMES, which is what actually prevents
    -- UIFrameFlash_OnUpdate from re-showing them every frame.
    if button.FlashBorder and type(_G.MicroButtonPulseStop) == "function" then
        _G.MicroButtonPulseStop(button)
    end

    -- Retail's MicroButtonPulse flashes FlashBorder *and* FlashContent.
    KillTex(button.FlashBorder)
    KillTex(button.FlashContent)
    KillTex(button.Flash)
end

-- Safety net for buttons that aren't in MICRO_BUTTONS: anything Blizzard adds
-- in a later build, plus HelpOpenWebTicketButton (the red "?" GM ticket button,
-- which lives outside MicroMenu and is anchored to it by
-- MicroMenuMixin:UpdateHelpTicketButtonAnchor). We only stop their flashing --
-- skinning a button we don't recognise could look worse than leaving it.
--
-- Deliberately NOT called from ApplySkin: every button it reaches has just been
-- handled by SkinButton, so per-pass it was ~195 duplicate C calls plus a table
-- allocation for the child list. Once at activation is enough -- the
-- MicroButtonPulse hook catches anything that starts flashing later.
local function KillStrayFlashes()
    local mm = _G.MicroMenu
    if mm and mm.GetChildren then
        local kids = { mm:GetChildren() }
        for i = 1, #kids do
            local c = kids[i]
            if c and (c.FlashBorder or c.FlashContent or c.Flash) then
                KillFlash(c)
            end
        end
    end

    local ticket = _G.HelpOpenWebTicketButton
    if ticket then KillFlash(ticket) end
end

-- ============================================================
-- Skinning
-- ============================================================
local ApplySkin   -- forward declaration: QueueApply's closure calls it
local QueueApply

-- Re-applies just the icon: inset, crop, desaturation, highlight wash.
--
-- Split out of SkinButton because it has to run SYNCHRONOUSLY from the atlas
-- setter hooks. MainMenuMicroButtonMixin:OnUpdate rewrites SetNormalAtlas /
-- SetPushedAtlas / SetDisabledAtlas / SetHighlightAtlas once per second (it
-- drives the file-streaming indicator), and each of those calls wipes our
-- crop. Re-cropping a frame later showed one frame of raw Blizzard art every
-- single second, which is what read as the game menu button blinking.
local function ApplyNormal(button, db)
    local tex = button.GetNormalTexture and button:GetNormalTexture()
    if not tex then return end
    SetInside(tex, button, Num(db.iconInset, 2))
    ZoomTexture(tex, Num(db.iconZoom, 0.10))
    tex:SetDesaturated(db.desaturate and true or false)
    tex:SetAlpha(1)
end

local function ApplyPushed(button, db)
    local tex = button.GetPushedTexture and button:GetPushedTexture()
    if not tex then return end
    SetInside(tex, button, Num(db.iconInset, 2))
    ZoomTexture(tex, Num(db.iconZoom, 0.10))
    local hr, hg, hb = Col(db.hoverColor, 0.90, 0.06, 0.22, 1)
    tex:SetVertexColor(hr * 1.5, hg * 1.5, hb * 1.5)
end

local function ApplyDisabled(button, db)
    local tex = button.GetDisabledTexture and button:GetDisabledTexture()
    if not tex then return end
    SetInside(tex, button, Num(db.iconInset, 2))
    ZoomTexture(tex, Num(db.iconZoom, 0.10))
    tex:SetDesaturated(true)
end

-- Flat white wash, ElvUI-style.
local function ApplyHighlight(button, db)
    local tex = button.GetHighlightTexture and button:GetHighlightTexture()
    if not tex then return end
    tex:SetColorTexture(1, 1, 1, Num(db.highlightAlpha, 0.20))
    SetInside(tex, button, Num(db.iconInset, 2))
end

local function ReskinIcon(button, db)
    ApplyNormal(button, db)
    ApplyPushed(button, db)
    ApplyDisabled(button, db)
    ApplyHighlight(button, db)
end

-- One handler per setter, so a hook only redoes the texture that setter just
-- wiped.
--
-- This matters more than it looks. A single UpdateMicroButtons() produces
-- roughly 33 SetHighlightAtlas calls -- StoreMicroButton and
-- MainMenuMicroButton each re-run the whole EnableMicroButtons() sweep, and
-- every SetNormal/SetPushed calls SetHighlightAtlas too. With one shared
-- handler that was ~33 full four-texture re-skins per pass instead of ~33
-- five-call highlight refreshes.
--
-- `applying` skips the work while a full ApplySkin pass is already running.
local function MakeSetterHook(applyFn)
    return function(button)
        if applying then return end
        local db = GetDB()
        if db and db.enabled then applyFn(button, db) end
    end
end

local SETTER_HOOKS = {
    SetNormalAtlas    = MakeSetterHook(ApplyNormal),
    SetPushedAtlas    = MakeSetterHook(ApplyPushed),
    SetDisabledAtlas  = MakeSetterHook(ApplyDisabled),
    SetHighlightAtlas = MakeSetterHook(ApplyHighlight),
}

local function SkinButton(button, name, db)
    local bd = EnsureBackdrop(button)

    -- Backdrop fill + border
    local br, bg, bb, ba = Col(db.backdropColor, 0.06, 0.06, 0.06, 0.85)
    bd.fill:SetColorTexture(br, bg, bb, ba)
    LayoutBackdrop(bd, button, Num(db.borderSize, 1))
    local er, eg, eb, ea = Col(db.borderColor, 0, 0, 0, 1)
    SetBorderColor(button, er, eg, eb, ea)

    bd.fill:SetShown(db.showBackdrop ~= false)
    local showBorder = db.showBorder ~= false
    bd.top:SetShown(showBorder)
    bd.bottom:SetShown(showBorder)
    bd.left:SetShown(showBorder)
    bd.right:SetShown(showBorder)

    -- Strip Blizzard chrome. These are the frame/shadow/flash art pieces --
    -- the icon glyph itself lives on the normal/pushed/disabled textures.
    for _, key in ipairs(CHROME_KEYS) do
        local t = button[key]
        if t and t.SetTexture then t:SetTexture(nil) end
    end
    if button.PortraitMask then button.PortraitMask:Hide() end

    local inset = Num(db.iconInset, 2)

    ReskinIcon(button, db)
    KillFlash(button)

    button:SetHitRectInsets(0, 0, 0, 0)

    -- Character button carries a 3D portrait instead of a glyph.
    if name == "CharacterMicroButton" then
        local portrait = _G.MicroButtonPortrait or button.Portrait
        if portrait then SetInside(portrait, button, inset) end
    end

    -- PVP button has a faction texture layered on top.
    if name == "PVPMicroButton" and _G.PVPMicroButtonTexture then
        _G.PVPMicroButtonTexture:SetAlpha(0)
        hidPVPTex = true
    end

    -- Hover handlers, hooked once.
    if not button._spmmHooked then
        button._spmmHooked = true
        button:HookScript("OnEnter", OnEnterButton)
        button:HookScript("OnLeave", OnLeaveButton)
    end

    -- Blizzard rewrites button art outside of UpdateMicroButtons, so every
    -- atlas setter gets its own hook and re-crops immediately.
    --
    -- All four matter: MainMenuMicroButtonMixin:OnUpdate calls every one of
    -- them once per second to drive the file-streaming indicator. Hooking only
    -- SetHighlightAtlas left the *normal* texture -- the visible icon -- raw
    -- until the next pass.
    --
    -- No recursion risk: we only ever call SetTexture/SetTexCoord/
    -- SetColorTexture on the texture objects, never these button setters.
    if not button._spmmTexHooked then
        button._spmmTexHooked = true

        for method, handler in pairs(SETTER_HOOKS) do
            if button[method] then
                hooksecurefunc(button, method, handler)
            end
        end

        -- Character button swaps its portrait rather than an atlas, and
        -- CharacterMicroButtonMixin overrides SetNormal/SetPushed without
        -- touching any atlas setter, so those need their own hook.
        if name == "CharacterMicroButton" then
            if button.SetPushed then hooksecurefunc(button, "SetPushed", QueueApply) end
            if button.SetNormal then hooksecurefunc(button, "SetNormal", QueueApply) end
        end
    end
end

-- The latency/FPS bar drawn over the main menu button. Always hidden -- it
-- clashes with the flat skin and there's no reason to keep it once skinned.
-- Alpha + scale rather than :Hide(), which can taint a protected child.
local function HidePerformanceBar()
    if hidPerfBar then return end
    local mm = _G.MainMenuMicroButton
    local bar = (mm and (mm.PerformanceIndicator or mm.MainMenuBarPerformanceBar))
                or _G.MainMenuBarPerformanceBar
    if not bar then return end
    bar:SetAlpha(0)
    bar:SetScale(0.00001)
    hidPerfBar = true
end

-- ============================================================
-- Layout (size + spacing)
--
-- We resize the buttons and then drive Blizzard's OWN grid rather than
-- re-anchoring buttons ourselves. MicroMenu is a GridLayoutFrame: setting
-- childXPadding/childYPadding and invalidating oldGridSettings makes
-- ShouldUpdateLayout() return true, and Blizzard's Layout() does the rest.
--
-- Doing it this way matters:
--   * the stacked two-row layout (vehicle / override bar / pet battle, where
--     MicroMenu gets a stride of numButtons/2) keeps working -- chaining
--     buttons LEFT->RIGHT ourselves would flatten both rows into one;
--   * MicroMenu's own size stays correct, so the Edit Mode selection box,
--     QueueStatusButton, FramerateFrame and the GM ticket button stay anchored;
--   * there is no ordering to guess, so no unstable sort on tied X positions.
--
-- No combat guard: micro buttons are plain Buttons, not protected frames, and
-- LayoutFrame methods are unprotected too.
-- ============================================================
local function ApproxEq(a, b)
    return a ~= nil and b ~= nil and math.abs(a - b) < 0.5
end

-- Blizzard's native padding, captured once. Held in a table so that a nil
-- native value round-trips correctly.
local nativePad

local function RelayoutMicroMenu(mm)
    mm.oldGridSettings = nil   -- forces ShouldUpdateLayout() to return true
    local container = _G.MicroMenuContainer
    if container and container.Layout then
        container:Layout()
    elseif mm.Layout then
        mm:Layout()
    end
end

local RestoreLayout   -- forward declaration: LayoutButtons calls it when the
                      -- override is switched back off

local function LayoutButtons(db)
    local mm = _G.MicroMenu
    if not mm then return end

    if nativePad == nil then
        nativePad = { x = mm.childXPadding, y = mm.childYPadding }
    end

    if not db.overrideLayout then
        -- Override just got turned off: hand the native geometry back.
        if MMS.layoutApplied then
            MMS.layoutApplied = false
            RestoreLayout()
        end
        return
    end

    local size = Num(db.buttonSize,    26)
    local gap  = Num(db.buttonSpacing,  0)
    local changed = false

    for _, name in ipairs(MICRO_BUTTONS) do
        local b = _G[name]
        if b then
            -- Native aspect ratio captured once so width tracks height.
            if b._spOrigW == nil then
                b._spOrigW = b:GetWidth()
                b._spOrigH = b:GetHeight()
            end
            local ratio = (b._spOrigH and b._spOrigH > 0) and (b._spOrigW / b._spOrigH) or 1
            if not ApproxEq(b:GetHeight(), size) then
                b:SetSize(size * ratio, size)
                changed = true
            end
        end
    end

    if mm.childXPadding ~= gap or mm.childYPadding ~= gap then
        mm.childXPadding = gap
        mm.childYPadding = gap
        changed = true
    end

    if changed then RelayoutMicroMenu(mm) end
    MMS.layoutApplied = true
end

-- Real implementation of the forward-declared local.
RestoreLayout = function()
    for _, name in ipairs(MICRO_BUTTONS) do
        local b = _G[name]
        if b and b._spOrigW then
            b:SetSize(b._spOrigW, b._spOrigH)
        end
    end

    local mm = _G.MicroMenu
    if mm and nativePad then
        mm.childXPadding = nativePad.x
        mm.childYPadding = nativePad.y
        RelayoutMicroMenu(mm)
    end
end

-- Real implementation of the forward-declared local.
ApplySkin = function()
    local db = GetDB()
    if not (db and db.enabled) then return end
    if applying then return end
    applying = true

    for _, name in ipairs(MICRO_BUTTONS) do
        local button = _G[name]
        if button then
            SkinButton(button, name, db)
        end
    end
    HidePerformanceBar()
    LayoutButtons(db)

    applying = false
end

-- SYNCHRONOUS re-skin, used by the UpdateMicroButtons hook.
--
-- This must not be deferred. hooksecurefunc runs in the same frame as
-- Blizzard's own call and before anything is drawn, so applying here is
-- invisible. Deferring by one frame (the old C_Timer.After(0) approach) meant
-- every UpdateMicroButtons -- bag, spell, bind, quest, cooldown, regen --
-- displayed one frame of raw Blizzard art before we re-cropped it, which reads
-- as the buttons blinking.
--
-- `applying` already guards re-entrancy, and the hook fires after the whole
-- UpdateMicroButtons pass, so every button is in its final state by now.
local function ApplyNow()
    local db = GetDB()
    if db and db.enabled then
        pendingApply = false
        ApplySkin()
    end
end

-- Deferred + coalesced path, used by the per-button setter hooks. Those fire
-- from inside UpdateMicroButton (so ApplyNow is about to run anyway) and can
-- fire in bursts, so a frame of delay is the right trade here.
QueueApply = function()
    if pendingApply then return end
    pendingApply = true
    C_Timer.After(0, function()
        if not pendingApply then return end
        pendingApply = false
        local db = GetDB()
        if db and db.enabled then ApplySkin() end
    end)
end

MMS.ApplySkin = ApplySkin

-- ============================================================
-- Restore
--
-- Best effort: hides our backdrop, un-crops the glyphs, un-desaturates. The
-- chrome textures Blizzard set at load time cannot be recovered without a
-- reload, so the GUI tells the user to /reload for a clean revert.
-- ============================================================
local function RestoreTexture(tex, button)
    if not tex then return end
    if tex._spAtlas then
        tex:SetAtlas(tex._spAtlas)
    else
        tex:SetTexCoord(0, 1, 0, 1)
    end
    tex:SetDesaturated(false)
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetAlpha(1)
    tex:ClearAllPoints()
    tex:SetAllPoints(button)
end

local function RemoveSkin()
    for _, name in ipairs(MICRO_BUTTONS) do
        local button = _G[name]
        local bd = button and button._spmm
        if bd then
            bd.fill:Hide()
            bd.top:Hide()
            bd.bottom:Hide()
            bd.left:Hide()
            bd.right:Hide()

            -- Restored one by one rather than via ipairs over a table literal:
            -- a nil in the first slot would silently end the iteration.
            RestoreTexture(button.GetNormalTexture   and button:GetNormalTexture(),   button)
            RestoreTexture(button.GetPushedTexture   and button:GetPushedTexture(),   button)
            RestoreTexture(button.GetDisabledTexture and button:GetDisabledTexture(), button)
        end
    end

    RestoreLayout()

    if hidPerfBar then
        local mm = _G.MainMenuMicroButton
        local bar = (mm and (mm.PerformanceIndicator or mm.MainMenuBarPerformanceBar))
                    or _G.MainMenuBarPerformanceBar
        if bar then
            bar:SetAlpha(1)
            bar:SetScale(1)
        end
        hidPerfBar = false
    end

    if hidPVPTex and _G.PVPMicroButtonTexture then
        _G.PVPMicroButtonTexture:SetAlpha(1)
        hidPVPTex = false
    end
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function MMS:Activate()
    -- Micro buttons are created during UI load, but some (Housing, Store) can
    -- appear a frame or two later, so the first pass is deferred.
    C_Timer.After(0.5, function()
        ApplySkin()
        KillStrayFlashes()

        -- Blizzard calls UpdateMicroButtons() on nearly every state change and
        -- resets the textures each time, so re-apply after it runs.
        if not hookedUpdate and type(_G.UpdateMicroButtons) == "function" then
            hookedUpdate = true
            hooksecurefunc("UpdateMicroButtons", ApplyNow)
        end

        -- Kill the new-content pulse at the source: MicroButtonPulse can fire
        -- outside UpdateMicroButtons, so waiting for our own pass would let a
        -- frame or two of blinking through.
        if not hookedPulse and type(_G.MicroButtonPulse) == "function" then
            hookedPulse = true
            hooksecurefunc("MicroButtonPulse", function(button)
                local db = GetDB()
                if db and db.enabled and button then KillFlash(button) end
            end)
        end
    end)
end

function MMS:Deactivate()
    self.layoutApplied = false
    RemoveSkin()
end

function MMS:Refresh()
    local db = GetDB()
    if db and db.enabled then
        if not self:IsEnabled() then self:Enable() end
        -- Must go through Activate(), not ApplySkin(): the first enable is
        -- what installs the UpdateMicroButtons hook, without which Blizzard
        -- wipes the skin on the next state change.
        self:Activate()
    else
        if self:IsEnabled() then self:Disable() end
        self:Deactivate()
    end
end

function MMS:OnEnable()
    if IsLoggedIn() then
        local db = GetDB()
        if db and db.enabled then self:Activate() end
    else
        self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
    end
end

function MMS:OnLogin()
    self:UnregisterEvent("PLAYER_LOGIN")
    local db = GetDB()
    if db and db.enabled then self:Activate() end
end

function MMS:OnDisable()
    self:UnregisterAllEvents()
    self:Deactivate()
end
