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

local MMS = SP:NewSPModule("MicroMenuSkin", "microMenuSkin")
SP.MicroMenuSkin = MMS

-- ============================================================
-- Locals
-- ============================================================
local _G             = _G
local hooksecurefunc = hooksecurefunc
local C_Timer        = C_Timer
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
--
-- Kept as a file-local rather than folded into ModuleMixin:GetDB(): almost
-- every reader here (the hover handlers, the setter hooks, ApplySkin, the
-- MicroButtonPulse hook) is a plain local function with no `self` to reach the
-- module through, and several of them run from Blizzard's own call stack.
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

-- Numeric fallback. Guards `false`, which IS falsy in Lua -- a stored 0 is not,
-- and would survive a plain `or` on its own.
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
local hidPerfBar   = false   -- so the perf bar can be restored
local hidPVPTex    = false
local hidBarArt    = false   -- Forever's frame art around the bar, see HideBarArt

-- ============================================================
-- Texture helpers
-- ============================================================

-- Re-entry guard shared by every SetPoint pin (see PinArt): set while the
-- skin itself is anchoring something, so its own calls are not taken for
-- Blizzard moving the art.
local pinning = false

-- Anchors a texture inside a frame with a uniform inset.
local function SetInside(tex, frame, inset)
    if not tex then return end
    inset = inset or 0
    local was = pinning
    pinning = true
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT",     frame, "TOPLEFT",      inset, -inset)
    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset,  inset)
    pinning = was
end

-- Crops a texture inward by `zoom` (0..0.45) so the glyph fills the square.
--
-- The crop is taken INSIDE the rect the texture is showing, read back with
-- GetTexCoord, and the file is never touched. For an atlas that rect is the
-- icon's sub-rect of the packed sheet, so cropping inside it is always right.
--
-- The previous version swapped the atlas for its file and remembered the atlas
-- name to find the sub-rect again. When GetAtlas() came back empty and no name
-- was remembered, it fell through to a crop of 0..1 -- the whole sheet. On WoW:
-- Forever that showed every micro menu icon shrunk into each button as soon as
-- a hover or click re-ran the crop (reported 2026-10-20, with a screenshot).
--
-- Idempotent across passes: `_spOut` is the rect we set last. If the texture
-- still shows exactly that, the native rect is the one recorded before; if it
-- shows anything else, Blizzard has re-set the art (new atlas, new file, a
-- state change), and what is there now is the new native rect.
local UV_EPSILON = 1e-4

local function SameRect(rect, l, r, t, b)
    return rect ~= nil
        and math.abs(rect[1] - l) < UV_EPSILON and math.abs(rect[2] - r) < UV_EPSILON
        and math.abs(rect[3] - t) < UV_EPSILON and math.abs(rect[4] - b) < UV_EPSILON
end

local function ZoomTexture(tex, zoom)
    if not (tex and tex.GetTexCoord) then return end

    -- GetTexCoord returns the four corners: UL, LL, UR, LR. The art here is
    -- never rotated, so UL gives left/top and LR gives right/bottom.
    local ulx, uly, _, _, _, _, lrx, lry = tex:GetTexCoord()
    if not ulx then return end

    local native = tex._spUV
    if not native then
        native = {}
        tex._spUV = native
    end
    if not SameRect(tex._spOut, ulx, lrx, uly, lry) then
        native[1], native[2], native[3], native[4] = ulx, lrx, uly, lry
    end

    local l, r, t, b = native[1], native[2], native[3], native[4]
    if zoom and zoom > 0 then
        local dx, dy = (r - l) * zoom, (b - t) * zoom
        l, r, t, b = l + dx, r - dx, t + dy, b - dy
    end
    tex:SetTexCoord(l, r, t, b)

    -- Reused, not reallocated: this runs on nearly every UpdateMicroButtons.
    local out = tex._spOut
    if not out then
        out = {}
        tex._spOut = out
    end
    out[1], out[2], out[3], out[4] = l, r, t, b
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
-- ============================================================
-- Bar opacity
--
-- Set on MicroMenu rather than on each button, so it covers the backdrops and
-- the borders too and stays correct when Blizzard adds a button.
--
-- The hover half needs the deferred re-check below: sliding from one button to
-- the next fires OnLeave BEFORE the next OnEnter, so acting on OnLeave alone
-- makes the bar blink at every boundary.
-- ============================================================
local function ApplyAlpha(hovering)
    local db = GetDB()
    local mm = _G.MicroMenu
    if not (mm and db and db.enabled) then return end

    local a = Num(db.alpha, 100) / 100
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    if hovering and db.fadeOnHover then a = 1 end
    mm:SetAlpha(a)
end
MMS.ApplyAlpha = ApplyAlpha

local function OnEnterButton(button)
    local db = GetDB()
    if not (db and db.enabled) then return end

    ApplyAlpha(true)

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

    -- Deferred by a frame, then asked again: the cursor moving between two
    -- buttons leaves one before entering the next, and dimming in that gap is
    -- a visible flicker all the way along the bar.
    if db.fadeOnHover then
        C_Timer.After(0, function()
            local mm = _G.MicroMenu
            ApplyAlpha(mm and mm.IsMouseOver and mm:IsMouseOver())
        end)
    end

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
-- The buttons actually in the bar
--
-- MICRO_BUTTONS alone was wrong on WoW: Forever. Blizzard builds the bar from
-- MicroMenuMixin:GenerateButtonInfos(), which differs per client: Forever adds
-- LegacyMicroButton, which no list of ours knew, and drops Achievement and the
-- buttons its game rules turn off. A dropped button still exists as a global
-- (every one is defined in the shared XML), so the old loop skinned and resized
-- frames that were never in the bar, and missed one that was.
--
-- The truth is MicroMenu itself: MicroMenuMixin:AddButton parents each button
-- it keeps to the bar and gives it a layoutIndex. Excluded ones get neither.
-- MICRO_BUTTONS stays as the fallback for a build where that does not hold.
--
-- Cached: ApplySkin runs from the UpdateMicroButtons hook on nearly every state
-- change, and GetChildren allocates. Buttons are only added in OnLoad, so the
-- list is rebuilt once per Activate.
-- ============================================================
local buttonCache

local function CollectButtons()
    local list = {}
    local mm = _G.MicroMenu
    if mm and mm.GetChildren then
        local kids = { mm:GetChildren() }
        for i = 1, #kids do
            local b = kids[i]
            local name = b.GetName and b:GetName()
            if name and b.layoutIndex and name:find("MicroButton$") then
                list[#list + 1] = { name = name, button = b }
            end
        end
        table.sort(list, function(a, b) return a.button.layoutIndex < b.button.layoutIndex end)
    end
    if #list == 0 then
        for _, name in ipairs(MICRO_BUTTONS) do
            local b = _G[name]
            if b then list[#list + 1] = { name = name, button = b } end
        end
    end
    return list
end

local function GetButtons()
    if not buttonCache then buttonCache = CollectButtons() end
    return buttonCache
end

-- ============================================================
-- Skinning
-- ============================================================
local ApplySkin   -- forward declaration: defined after the layout helpers it uses

-- Re-applies just the icon: inset, crop, desaturation, highlight wash.
--
-- Split out of SkinButton because it has to run SYNCHRONOUSLY from the atlas
-- setter hooks. MainMenuMicroButtonMixin:OnUpdate rewrites SetNormalAtlas /
-- SetPushedAtlas / SetDisabledAtlas / SetHighlightAtlas once per second (it
-- drives the file-streaming indicator), and each of those calls wipes our
-- crop. Re-cropping a frame later showed one frame of raw Blizzard art every
-- single second, which is what read as the game menu button blinking.
-- Whether the cursor is on this button right now. A full pass runs from
-- UpdateMicroButtons, which a click on a button that opens a window triggers
-- while the cursor is still on it: everything a pass paints must agree with
-- what the hover handlers painted, or the click visibly undoes the hover.
local function IsHovered(button)
    if not (button.IsMouseOver and button:IsMouseOver()) then return false end
    return not (button.IsEnabled and not button:IsEnabled())
end

local function ApplyNormal(button, db)
    local tex = button.GetNormalTexture and button:GetNormalTexture()
    if not tex then return end
    SetInside(tex, button, Num(db.iconInset, 2))
    ZoomTexture(tex, Num(db.iconZoom, 0.10))
    -- Coloured back in under the cursor, like OnEnterButton does.
    tex:SetDesaturated((db.desaturate and not IsHovered(button)) and true or false)
    tex:SetAlpha(1)
end

-- The pressed state shows the button's resting art, tinted. Blizzard's "-Down"
-- atlas is the same glyph drawn pressed in, a pixel off: on its own beveled
-- button that reads as a press, on the flat skin as the icon twitching on every
-- click. ElvUI makes the same choice. The atlas name comes from the button's
-- textureName (LoadMicroButtonTextures builds "UI-HUD-MicroMenu-<name>-Up"),
-- and is checked once, so a button without one keeps Blizzard's art.
local upAtlasOk = {}

local function UpAtlas(button)
    local name = button.textureName
    if type(name) ~= "string" then return nil end
    local atlas = "UI-HUD-MicroMenu-" .. name .. "-Up"
    local ok = upAtlasOk[atlas]
    if ok == nil then
        ok = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)) and true or false
        upAtlasOk[atlas] = ok
    end
    return ok and atlas or nil
end

local function ApplyPushed(button, db)
    local tex = button.GetPushedTexture and button:GetPushedTexture()
    if not tex then return end
    -- Before the crop: ZoomTexture reads the rect back and sees new art.
    local up = UpAtlas(button)
    if up then tex:SetAtlas(up) end
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
    -- SetPushed passes "ADD" to SetHighlightAtlas; the flat wash is BLEND.
    tex:SetBlendMode("BLEND")
    SetInside(tex, button, Num(db.iconInset, 2))
end

local function ReskinIcon(button, db)
    ApplyNormal(button, db)
    ApplyPushed(button, db)
    ApplyDisabled(button, db)
    ApplyHighlight(button, db)
end

-- What a button looks like right now, for the hover/click report on WoW:
-- Forever. Only built when SP.DEBUG is on: GetTexCoord alone returns 8 values.
-- Size and position, rounded to the pixel: "WxH@left,bottom".
local function Rect(region)
    if not (region and region.GetLeft) then return "-" end
    local l, b = region:GetLeft(), region:GetBottom()
    if not (l and b) then return "unplaced" end
    return ("%.1fx%.1f@%.1f,%.1f"):format(region:GetWidth(), region:GetHeight(), l, b)
end

-- Short UVs: left,right,top,bottom from the 8-value GetTexCoord.
local function UV(tex)
    if not (tex and tex.GetTexCoord) then return "-" end
    local ulx, uly, _, _, _, _, lrx, lry = tex:GetTexCoord()
    if not ulx then return "-" end
    return ("%.3f,%.3f,%.3f,%.3f"):format(ulx, lrx, uly, lry)
end

local function DescribeButton(button, event)
    local n = button.GetNormalTexture and button:GetNormalTexture()
    local p = button.GetPushedTexture and button:GetPushedTexture()
    local h = button.GetHighlightTexture and button:GetHighlightTexture()
    local mm = _G.MicroMenu
    local extra = ""
    local portrait = button.Portrait
    if portrait then extra = " | portrait " .. Rect(portrait) end
    if button.Emblem then extra = extra .. " | emblem " .. Rect(button.Emblem) end
    return ("%s %s state=%s btn=%s | normal %s uv=%s a=%.2f %s | pushed %s uv=%s %s | hl %s a=%.2f | bar=%s a=%.2f" .. extra):format(
        button:GetName() or "?", event,
        tostring(button.GetButtonState and button:GetButtonState()), Rect(button),
        tostring(n and n.GetAtlas and n:GetAtlas()), UV(n), n and n:GetAlpha() or -1, Rect(n),
        tostring(p and p.GetAtlas and p:GetAtlas()), UV(p), Rect(p),
        tostring(h and h:GetBlendMode()), h and h:GetAlpha() or -1,
        Rect(mm), mm and mm:GetAlpha() or -1)
end

-- Post-hooked on OnEnter, OnMouseDown and OnMouseUp. With SP.DEBUG, prints
-- what the button looks like at that moment, BEFORE anything below touches it.
--
-- On mouse down and up it then re-applies the icon. The press swaps the
-- button to its pushed texture (SetButtonState "PUSHED"), and every button was
-- reported to twitch at that moment; re-cropping right after Blizzard, in the
-- same frame, holds whatever the press resets. This used to also undo the
-- hover state (desaturation back on under the cursor); ApplyNormal now reads
-- the hover itself, so it is safe. Not on enter: nothing there needs it.
local function TraceButton(event)
    local reapply = (event == "down" or event == "up")
    return function(button)
        if SP.DEBUG then SP:Debug("MicroMenuSkin", DescribeButton(button, event)) end
        if reapply and not applying then
            local db = GetDB()
            if db and db.enabled then ReskinIcon(button, db) end
        end
    end
end
local TraceOnEnter, TraceOnDown, TraceOnUp =
    TraceButton("enter"), TraceButton("down"), TraceButton("up")

-- ============================================================
-- Pinning art where the skin put it
--
-- Blizzard re-anchors parts of a micro button with its own fixed offsets, made
-- for its 32x40 beveled button. On the skinned button each of those reads as
-- the button twitching on a click:
--   * CharacterMicroButtonMixin:SetPushed / SetNormal re-anchor the portrait
--     with FIXED 7 px insets (TOPLEFT 7,-7 / BOTTOMRIGHT -6,5 pushed, -7,7
--     normal), which shrinks it into a stamp on a smaller button (screenshot,
--     2026-10-20);
--   * GuildMicroButtonMixin moves the tabard emblem the same way;
--   * the icon textures themselves come back anchored to the whole button
--     between two clicks, then the skin re-insets them on the click: traces
--     showed 23.2x29 at rest and 17.2x23 after a click, on every button. Our
--     own code never anchors them that way, and no setter we hook fires, so
--     something re-anchors them directly.
-- Post-hooks on the caller (SetPushed...) did not hold. Each region is pinned
-- at the source instead, on its own SetPoint / SetAllPoints: whoever moves it,
-- by whatever path, it is put back in the same call. With SP.DEBUG, a move of
-- an icon texture also prints who made it.
--
-- `pinning` is the shared re-entry guard (see SetInside, which holds it too).
-- ============================================================

local function PlacePortrait(button, portrait)
    if pinning then return end
    local db = GetDB()
    if not (db and db.enabled) then return end
    SetInside(portrait, button, Num(db.iconInset, 2))
end

local function PlaceEmblem(button, emblem)
    if pinning then return end
    local db = GetDB()
    if not (db and db.enabled) then return end
    pinning = true
    -- Blizzard's resting spot (GuildMicroButtonMixin:SetNormal).
    emblem:ClearAllPoints()
    emblem:SetPoint("CENTER", button, "CENTER", 0, 2)
    pinning = false
end

-- Normal, pushed, disabled and highlight textures: the icon's inset.
local function PlaceStateTexture(button, tex, kind)
    if pinning then return end
    local db = GetDB()
    if not (db and db.enabled) then return end
    if SP.DEBUG and debugstack then
        local from = (debugstack(3, 2, 0) or "?"):gsub("\n", " | ")
        SP:Debug("MicroMenuSkin", ("%s %s re-anchored by: %s"):format(
            button:GetName() or "?", kind, from))
    end
    SetInside(tex, button, Num(db.iconInset, 2))
end

local STATE_TEXTURES = {
    { "normal",    "GetNormalTexture" },
    { "pushed",    "GetPushedTexture" },
    { "disabled",  "GetDisabledTexture" },
    { "highlight", "GetHighlightTexture" },
}

local function PinArt(button)
    if button._spmmArtPinned then return end
    button._spmmArtPinned = true

    if button == _G.CharacterMicroButton then
        local portrait = _G.MicroButtonPortrait or button.Portrait
        if portrait and portrait.SetPoint then
            hooksecurefunc(portrait, "SetPoint", function() PlacePortrait(button, portrait) end)
        end
    end

    local emblem = button.Emblem
    if emblem and emblem.SetPoint then
        hooksecurefunc(emblem, "SetPoint", function() PlaceEmblem(button, emblem) end)
    end

    for _, s in ipairs(STATE_TEXTURES) do
        local getter = button[s[2]]
        local tex = getter and getter(button)
        if tex and tex.SetPoint then
            local kind = s[1]
            local function Back() PlaceStateTexture(button, tex, kind) end
            hooksecurefunc(tex, "SetPoint", Back)
            if tex.SetAllPoints then hooksecurefunc(tex, "SetAllPoints", Back) end
        end
    end
end

-- Post-hooked on every button's SetPushed and SetNormal, so it runs after the
-- whole of Blizzard's body. Undoes the pressed look meant for Blizzard's
-- beveled buttons: the highlight halves to 0.5 and turns additive in
-- SetPushed, back to 1 and BLEND in SetNormal -- the wash pulsed on every
-- click. The portrait and the emblem are re-placed here too, in case their
-- own pin was installed after Blizzard last moved them.
-- Nothing else: no re-skin, so the hover state painted by OnEnterButton holds.
local function PinPressArt(button)
    local db = GetDB()
    if not (db and db.enabled) then return end

    local hl = button.GetHighlightTexture and button:GetHighlightTexture()
    if hl then
        hl:SetBlendMode("BLEND")
        hl:SetAlpha(1)
    end

    if button == _G.CharacterMicroButton then
        local portrait = _G.MicroButtonPortrait or button.Portrait
        if portrait then PlacePortrait(button, portrait) end
        if button.PortraitMask then button.PortraitMask:Hide() end
    end
    if button.Emblem then PlaceEmblem(button, button.Emblem) end
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
    -- The hover accent stays on the button under the cursor. This pass runs on
    -- every click that opens a window, and repainting the resting colour there
    -- was the border flashing off mid-click.
    local er, eg, eb, ea
    if IsHovered(button) then
        er, eg, eb, ea = Col(db.hoverColor, 0.90, 0.06, 0.22, 1)
    else
        er, eg, eb, ea = Col(db.borderColor, 0, 0, 0, 1)
    end
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

    -- Character button carries a 3D portrait instead of a glyph; it and the
    -- guild emblem are pinned where they belong, see PinArt.
    if name == "CharacterMicroButton" then
        local portrait = _G.MicroButtonPortrait or button.Portrait
        if portrait then PlacePortrait(button, portrait) end
    end
    PinArt(button)

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
        -- Debug traces only, see TraceButton.
        button:HookScript("OnEnter",     TraceOnEnter)
        button:HookScript("OnMouseDown", TraceOnDown)
        button:HookScript("OnMouseUp",   TraceOnUp)
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

        -- Every button: SetPushed / SetNormal change the highlight on all of
        -- them, and move art on Character and Guild. Synchronous, see PinPressArt.
        if button.SetPushed then hooksecurefunc(button, "SetPushed", PinPressArt) end
        if button.SetNormal then hooksecurefunc(button, "SetNormal", PinPressArt) end
    end
end

-- WoW: Forever draws the action-bar frame around the micro menu: two textures
-- on MicroMenu itself (Camelot\MainMenuBarMicroMenu.xml, atlases
-- UI-HUD-ActionBar-Frame and UI-HUD-ActionBar-IconFrame-Background). Retail
-- has neither, so this is a no-op there. Left visible, it boxes the flat skin.
local BAR_ART_KEYS = { "BorderArt", "BackgroundArt" }

local function HideBarArt()
    local mm = _G.MicroMenu
    if not mm then return end
    for _, key in ipairs(BAR_ART_KEYS) do
        local t = mm[key]
        if t and t.SetAlpha then
            t:SetAlpha(0)
            hidBarArt = true
        end
    end
end

local function RestoreBarArt()
    if not hidBarArt then return end
    local mm = _G.MicroMenu
    if mm then
        for _, key in ipairs(BAR_ART_KEYS) do
            local t = mm[key]
            if t and t.SetAlpha then t:SetAlpha(1) end
        end
    end
    hidBarArt = false
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

-- Same trick for the grid's stride: MicroMenu's native value can legitimately
-- be nil, and `nativeStride or default` would never give it back.
local nativeStride

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

    for _, e in ipairs(GetButtons()) do
        local b = e.button
        if b then
            -- Native aspect ratio captured once so width tracks height.
            if b._spOrigW == nil then
                b._spOrigW = b:GetWidth()
                b._spOrigH = b:GetHeight()
            end
            local ratio = (b._spOrigH and b._spOrigH > 0) and (b._spOrigW / b._spOrigH) or 1
            if not ApproxEq(b:GetHeight(), size) then
                if SP.DEBUG then
                    SP:Debug("MicroMenuSkin", ("resize %s from %.1fx%.1f to %.1fx%.1f"):format(
                        e.name, b:GetWidth(), b:GetHeight(), size * ratio, size))
                end
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

    -- Icons per row.
    --
    -- MicroMenu is a GridLayoutFrame, and a grid's `stride` IS its number of
    -- children per row -- so wrapping the bar onto two or three rows is one
    -- assignment plus the same relayout the padding already triggers. No
    -- re-anchoring, which is what keeps the Edit Mode box, QueueStatusButton
    -- and the GM ticket button attached.
    --
    -- 0 means "leave it to Blizzard". That matters more than it looks: the
    -- vehicle, override and pet battle bars set a stride of their own
    -- (numButtons/2) when they take over, and forcing ours would flatten those
    -- back out. We re-apply on every UpdateMicroButtons, so an override that
    -- reclaims the stride mid-session gets ours back on its next pass.
    local perRow = math.floor(Num(db.iconsPerRow, 0) + 0.5)
    if perRow > 0 then
        if nativeStride == nil then nativeStride = { v = mm.stride } end
        if mm.stride ~= perRow then
            mm.stride = perRow
            changed = true
        end
    elseif nativeStride ~= nil and mm.stride ~= nativeStride.v then
        mm.stride = nativeStride.v
        changed = true
    end

    if changed then
        if SP.DEBUG then
            SP:Debug("MicroMenuSkin", ("relayout: bar %s, padding %s/%s, stride %s"):format(
                Rect(mm), tostring(mm.childXPadding), tostring(mm.childYPadding), tostring(mm.stride)))
        end
        RelayoutMicroMenu(mm)
    end
    MMS.layoutApplied = true
end

-- Real implementation of the forward-declared local.
RestoreLayout = function()
    -- Opacity is ours, so hand it back before anything else.
    local restore = _G.MicroMenu
    if restore then restore:SetAlpha(1) end

    for _, e in ipairs(GetButtons()) do
        local b = e.button
        if b._spOrigW then
            b:SetSize(b._spOrigW, b._spOrigH)
        end
    end

    local mm = _G.MicroMenu
    if mm and nativePad then
        mm.childXPadding = nativePad.x
        mm.childYPadding = nativePad.y
        if nativeStride ~= nil then mm.stride = nativeStride.v end
        RelayoutMicroMenu(mm)
    end
end

-- Real implementation of the forward-declared local.
ApplySkin = function()
    local db = GetDB()
    if not (db and db.enabled) then return end
    if applying then return end
    applying = true

    for _, e in ipairs(GetButtons()) do
        SkinButton(e.button, e.name, db)
    end
    HidePerformanceBar()
    HideBarArt()
    LayoutButtons(db)
    -- Not ApplyAlpha(false): with "full opacity on mouseover", a click under
    -- the cursor dropped the whole bar back to its faded opacity.
    local mm = _G.MicroMenu
    ApplyAlpha(mm and mm.IsMouseOver and mm:IsMouseOver())

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
        ApplySkin()
    end
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
    -- Back to the native rect ZoomTexture recorded. Only when the texture still
    -- shows our crop: if Blizzard re-set it since, its rect is already native.
    local native, out = tex._spUV, tex._spOut
    if native and out and tex.GetTexCoord then
        local ulx, uly, _, _, _, _, lrx, lry = tex:GetTexCoord()
        if ulx and SameRect(out, ulx, lrx, uly, lry) then
            tex:SetTexCoord(native[1], native[2], native[3], native[4])
        end
    end
    tex._spOut = nil
    tex:SetDesaturated(false)
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetAlpha(1)
    tex:ClearAllPoints()
    tex:SetAllPoints(button)
end

local function RemoveSkin()
    for _, e in ipairs(GetButtons()) do
        local button = e.button
        local bd = button._spmm
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
    RestoreBarArt()

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
--
-- Only Activate / Deactivate live here. Refresh, OnEnable (with its
-- PLAYER_LOGIN deferral) and OnDisable all come from ModuleMixin -- see
-- Core/Module.lua. In particular Refresh no longer drives AceAddon's
-- Enable/Disable: `db.enabled` is the single source of truth, and every hook
-- installed below re-reads it, so a switched-off module is inert.
--
-- Refresh() must route through Activate() and not straight to ApplySkin():
-- the first activation is what installs the UpdateMicroButtons hook, without
-- which Blizzard wipes the skin on the next state change.
-- ============================================================
function MMS:Activate()
    -- Micro buttons are created during UI load, but some (Housing, Store) can
    -- appear a frame or two later, so the first pass is deferred.
    C_Timer.After(0.5, function()
        -- Re-read the setting: C_Timer.After cannot be cancelled, so this can
        -- land after a Deactivate. ApplySkin already gates on db.enabled, but
        -- KillStrayFlashes does not, and neither should install hooks for a
        -- module the user just switched off.
        local db = GetDB()
        if not (db and db.enabled) then return end

        buttonCache = nil
        if SP.Debug then
            local names = {}
            for _, e in ipairs(GetButtons()) do names[#names + 1] = e.name end
            SP:Debug("MicroMenuSkin", #names .. " buttons: " .. table.concat(names, ", "))
        end

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
