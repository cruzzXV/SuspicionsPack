-- SuspicionsPack — DetailsSkin Module (WoW: Forever only)
--
-- Installs the "The War Within" look into Details! on the Forever client, where
-- the original addon (Details_TWW) is not published. Loaded only on Forever: the
-- .toc line carries [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic].
--
-- Port of "Details! Skin 'The War Within'" by Karl-Heinz Schneider,
-- https://github.com/Karl-HeinzSchneider/WoW-Details-Skin-TheWarWithin
-- MIT License, Copyright (c) 2024 Karl-HeinzSchneider. The skin table below is
-- his, with these changes:
--   * textures live under SuspicionsPack\Media\DetailsSkin and the LibSharedMedia
--     names are prefixed so they cannot collide with the original addon;
--   * spec icons are off (Forever has no specialisations) and the spec atlas is
--     not shipped;
--   * the Augmentation Evoker bar recolour is dropped (no Evokers on Forever);
--   * every text uses Expressway, the pack's font, instead of Friz Quadrata and
--     Accidental Presidency. Details resolves it by LibSharedMedia name, which
--     DeathAlert registers at file scope (it loads before this file);
--   * no Ace3 of its own, no slash command, no bundled profile: the profile export
--     string hard-codes the original addon's texture paths and cannot be re-pathed
--     without decoding it, so it is left out rather than shipped broken.
--
-- THE SECOND SKIN, "Forever" (2026-11-05)
--   The same idea in the pack's Forever look: the title over the options window's
--   section line with a copper arrow, slimmer bars so 7 rows fit where the first
--   skin shows 5, and the class icons in the bronze ring of the Forever unit frames.
--   Its track and class icons are made from his art, its bar is MerfinMain squeezed into
--   the bar's band (tests/gen_details_forever.js): Details stretches one texture over the
--   whole row, so MerfinMain itself would fill the row, under the text. The arrow and the
--   line are Plumber's, already in Media\Plumber; the ring is the client's own atlas, so
--   it adds no file. A Details skin is a table of settings, so the module draws the
--   arrow, the line and the rings on the window itself.
--
-- WHAT "ENABLED" MEANS HERE
--   Details has InstallSkin but no uninstall. Switching the module off only stops
--   it from (re)installing the skin at the next login; a window already using the
--   skin keeps it until the user picks another one in Details.
local SP = SuspicionsPack
-- Every hook in this file gets a row in /spack perf (Core\Perf.lua).
local hooksecurefunc = SP.Perf.HookFunc("DetailsSkin")

local DS = SP:NewSPModule("DetailsSkin", "detailsSkin")
SP.DetailsSkin = DS

-- ============================================================
-- Constants
-- ============================================================
local SKIN_NAME    = "|cffe51039Suspicion|r|cffffffffPack|r TWW"
local FOREVER_NAME = "|cffe51039Suspicion|r|cffffffffPack|r Forever"
DS.SKIN_NAME    = SKIN_NAME
DS.FOREVER_NAME = FOREVER_NAME

local MEDIA = [[Interface\AddOns\SuspicionsPack\Media\DetailsSkin\]]

-- LibSharedMedia names. Registered at file scope, like the original: Details
-- resolves statusbar textures by LSM name when it applies the skin, so the names
-- must exist before any window is skinned, including by Details itself at login.
local LSM_HEADER        = "SuspicionsPack TWW Header"
local LSM_BAR           = "SuspicionsPack TWW Bar"
local LSM_BACKGROUND    = "SuspicionsPack TWW Background"
local LSM_FOREVER_BAR   = "SuspicionsPack Forever Bar"
local LSM_FOREVER_TRACK = "SuspicionsPack Forever Track"

do
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        -- No extension on purpose: the files are .blp and the client resolves
        -- texture paths without one.
        LSM:Register("statusbar", LSM_HEADER,     MEDIA .. "header")
        LSM:Register("statusbar", LSM_BAR,        MEDIA .. "bar")
        LSM:Register("statusbar", LSM_BACKGROUND, MEDIA .. "background")
        LSM:Register("statusbar", LSM_FOREVER_BAR,   MEDIA .. "forever_bar.png")
        LSM:Register("statusbar", LSM_FOREVER_TRACK, MEDIA .. "forever_track.png")
    end
end

-- ============================================================
-- The skin table (Details:InstallSkin format)
-- ============================================================
local skinTable = {
    file    = [[Interface\AddOns\Details\images\skins\flat_skin.blp]],
    author  = "Karl-Heinz Schneider (ported by Cruzz)",
    version = C_AddOns.GetAddOnMetadata("SuspicionsPack", "Version"),
    site    = "https://github.com/Karl-HeinzSchneider/WoW-Details-Skin-TheWarWithin",
    desc    = "The War Within look, for WoW: Forever.",
    no_cache = true,

    -- micro frames
    micro_frames = { color = { 1, 1, 1, 1 }, font = "Expressway", size = 10, textymod = 1 },

    can_change_alpha_head = true,
    icon_anchor_main      = { -1, -5 },
    icon_anchor_plugins   = { -7, -13 },
    icon_plugins_size     = { 19, 18 },

    -- anchors
    icon_point_anchor   = { -37, 0 },
    left_corner_anchor  = { -107, 0 },
    right_corner_anchor = { 96, 0 },

    icon_point_anchor_bottom   = { -37, 12 },
    left_corner_anchor_bottom  = { -107, 0 },
    right_corner_anchor_bottom = { 96, 0 },

    icon_on_top             = true,
    icon_ignore_alpha       = true,
    icon_titletext_position = { 3, 3 },

    instance_cprops = {
        -- titlebar
        titlebar_shown         = true,
        titlebar_height        = 32,
        titlebar_texture       = LSM_HEADER,
        titlebar_texture_color = { 1.0, 1.0, 1.0, 1.0 },

        toolbar_icon_file = "Interface\\AddOns\\Details\\images\\toolbar_icons_shadow",
        toolbar_side      = 1,
        menu_anchor       = { 10, 10, side = 2 },

        attribute_text = {
            enabled            = true,
            shadow             = false,
            side               = 1,
            text_size          = 13,
            custom_text        = "{name}",
            text_face          = "Expressway",
            anchor             = { -4, 10 },
            text_color         = { NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, NORMAL_FONT_COLOR.a },
            enable_custom_text = false,
            show_timer         = true,
        },

        row_info = {
            texture_highlight = "Interface\\FriendsFrame\\UI-FriendsList-Highlight",
            fixed_text_color  = { 1, 1, 1 },
            height            = 28,
            space             = { right = 0, left = 0, between = 4 },
            row_offsets       = { left = 29, right = -29 - 8, top = 0, bottom = 0 },
            texture_background_class_color = false,
            font_face_file    = SP.DEFAULT_FONT,
            backdrop = {
                enabled = false,
                size    = 12,
                color   = { 1, 1, 1, 1 },
                texture = "Details BarBorder 2",
            },
            icon_file        = MEDIA .. "ClassIconsTWW",
            start_after_icon = false,
            icon_offset      = { -30, 0 },

            textL_show_number        = true,
            textL_outline            = false,
            textL_enable_custom_text = false,
            textL_custom_text        = "{data1}. {data3}{data2}",
            textL_class_colors       = false,

            textR_outline            = false,
            textR_bracket            = "(",
            textR_enable_custom_text = false,
            textR_custom_text        = "{data1} ({data2}, {data3}%)",
            textR_class_colors       = false,
            textR_show_data          = { true, true, true },

            fixed_texture_color = { 0, 0, 0 },
            models = {
                upper_model   = "Spells\\AcidBreath_SuperGreen.M2",
                lower_model   = "World\\EXPANSION02\\DOODADS\\Coldarra\\COLDARRALOCUS.m2",
                upper_alpha   = 0.5,
                lower_enabled = false,
                lower_alpha   = 0.1,
                upper_enabled = false,
            },
            texture_custom_file     = "Interface\\",
            texture_custom          = "",
            alpha                   = 1,
            no_icon                 = false,
            texture                 = LSM_BAR,
            texture_file            = MEDIA .. "bar",
            texture_background      = LSM_BACKGROUND,
            texture_background_file = MEDIA .. "background",

            fixed_texture_background_color = { 1, 1, 1, 1 },
            font_face        = "Expressway",
            font_size        = 11,
            textL_offset     = 0,
            text_yoffset     = 7,
            texture_class_colors = true,
            percent_type     = 1,
            fast_ps_update   = false,
            textR_separator  = ",",
            -- No specialisations on Forever: class icons only.
            use_spec_icons   = false,
            icon_size_offset = 1.2,
        },

        menu_icons_alpha = 1,
        show_statusbar   = false,
        menu_icons_size  = 1.07,
        color = { 0.333333333333333, 0.333333333333333, 0.333333333333333, 0 },
        bg_r  = 0.0941176470588235,
        hide_out_of_combat = false,
        following = {
            bar_color  = { 1, 1, 1 },
            enabled    = false,
            text_color = { 1, 1, 1 },
        },
        color_buttons   = { 1, 1, 1, 1 },
        skin_custom     = "",
        menu_anchor_down = { 16, -3 },
        micro_displays_locked = true,
        row_show_animation = { anim = "Fade", options = {} },
        tooltip   = { n_abilities = 3, n_enemies = 3 },
        total_bar = {
            enabled       = false,
            only_in_group = true,
            icon          = "Interface\\ICONS\\INV_Sigil_Thorim",
            color         = { 1, 1, 1 },
        },
        show_sidebars = false,
        instance_button_anchor = { -27, 1 },
        plugins_grow_direction = 1,
        menu_alpha = {
            enabled    = false,
            onleave    = 1,
            ignorebars = false,
            iconstoo   = true,
            onenter    = 1,
        },
        micro_displays_side = 2,
        grab_on_top    = false,
        strata         = "LOW",
        bars_grow_direction = 1,
        bg_alpha       = 0,
        ignore_mass_showhide = false,
        hide_in_combat_alpha = 0,
        menu_icons = { true, true, true, true, true, false, space = 0, shadow = false },
        auto_hide_menu = { left = false, right = false },
        statusbar_info = {
            alpha   = 0,
            overlay = { 0.333333333333333, 0.333333333333333, 0.333333333333333 },
        },
        window_scale     = 1,
        libwindow        = { y = 90.9987335205078, x = -80.0020751953125, point = "BOTTOMRIGHT" },
        backdrop_texture = "Details Ground",
        hide_icon        = true,
        bg_b             = 0.0941176470588235,
        bg_g             = 0.0941176470588235,
        desaturated_menu = false,
        wallpaper = {
            enabled  = false,
            texcoord = { 0, 1, 0, 0.7 },
            overlay  = { 1, 1, 1, 1 },
            anchor   = "all",
            height   = 114.042518615723,
            alpha    = 0.5,
            width    = 283.000183105469,
        },
        stretch_button_side = 1,
        bars_sort_direction = 1,
    },
}

-- ============================================================
-- The Forever skin: the table above, with its own title and bars
-- ============================================================
-- A deep copy of `base` with `over` written on top, table by table.
local function Derive(base, over)
    local t = {}
    for k, v in pairs(base) do
        t[k] = type(v) == "table" and Derive(v, {}) or v
    end
    for k, v in pairs(over) do
        if type(v) == "table" and type(t[k]) == "table" then
            t[k] = Derive(t[k], v)
        else
            t[k] = v
        end
    end
    return t
end

-- Row geometry, in the 245 wide window it was drawn for. The row is 22 high: the
-- name and values over 13, the slab under them over 9, and 4 between rows make 26,
-- so a window 182 high holds 7. forever_bar.png and forever_track.png are laid out
-- on these numbers.
local ROW_H, ROW_GAP  = 22, 4
local BAR_LEFT        = 26    -- the bars start here, right of the icon
local BAR_RIGHT       = 4     -- and stop this far from the window's right edge
local ICON_LEFT       = -25   -- the icon's left edge, from the row's left
local ICON_SIZE       = 20
local NAME_GAP        = 3     -- Details' own gap between the icon and the name
local TITLE_H         = 31

local foreverSkin = Derive(skinTable, {
    author = "Cruzz, from Karl-Heinz Schneider's skin",
    desc   = "The pack's look on WoW: Forever.",

    instance_cprops = {
        titlebar_height = TITLE_H,
        -- Details draws one texture across the title; here the module draws the
        -- title's art, so this one stays clear.
        titlebar_texture       = LSM_FOREVER_BAR,
        titlebar_texture_color = { 1, 1, 1, 0 },

        attribute_text = {
            text_size = 12,
            -- From the end of Details' title ball: x 21 past the window's left
            -- edge, y its top edge. Clear of the arrow, above the line.
            anchor = { -8, 17 },
        },

        row_info = {
            height = ROW_H,
            space  = { between = ROW_GAP },
            row_offsets = { left = BAR_LEFT, right = -(BAR_LEFT + BAR_RIGHT) },

            icon_file        = MEDIA .. "ClassIconsForever.png",
            -- The sheet's icons are round already; spell icons are square.
            icon_mask        = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
            icon_offset      = { ICON_LEFT, 0 },
            icon_size_offset = ICON_SIZE - ROW_H,

            -- The name starts where the bar does; the texts sit over the slab.
            textL_offset = -(ICON_LEFT + ICON_SIZE + NAME_GAP),
            text_yoffset = 5,

            texture                 = LSM_FOREVER_BAR,
            texture_file            = MEDIA .. "forever_bar.png",
            texture_background      = LSM_FOREVER_TRACK,
            texture_background_file = MEDIA .. "forever_track.png",
            -- The grey stone warmed to the pack's palette.
            fixed_texture_background_color = { 0.588, 0.518, 0.439, 1 },
        },
    },
})

-- ---- what the skin table cannot do ----------------------------------------------
-- Plumber's art, at the half scale the options window draws it (see Skin.PlumberHeader
-- for the line). The arrow points up in the sheet; these corners turn it to point right.
local ARROW = { x1 = 66 / 1024, x2 = 94 / 1024, y1 = 619 / 1024, y2 = 654 / 1024 }
local ARROW_W, ARROW_H = 18, 14
local LINE_H           = 20
local LINE_LEFT        = 12
local LINE_RIGHT       = 13
local BREAK_Y          = 14   -- the line's middle, above the title's bottom edge

-- The ring of the level badge on the Forever unit frames. The ring round their
-- portrait is painted in one piece with the frame's bars, so it cannot be drawn alone;
-- this is the same bronze, closed. Its art fills about 3/4 of its box, hence 32 for a
-- ring about 25 across, round an icon of 20. Under the icon, in case its middle is
-- filled: the icon is drawn at sublevel 5 of this layer.
local RING_ATLAS    = "UI-HUD-UnitFrame-SmallCircle"
local RING_SIZE     = 32
local RING_SUBLEVEL = 4

local titleArts = {}   -- baseframe -> frame holding the arrow and the line
local rings     = {}   -- row -> texture

local function BuildTitleArt(titleBar)
    local Skin = SP.Skin
    local P    = Skin.PLUMBER

    local art = CreateFrame("Frame", nil, titleBar)
    art:SetAllPoints(titleBar)

    local line = Skin.PlumberRect(art:CreateTexture(nil, "ARTWORK"), P.SHEET, 456, 736, 80, 120)
    line:SetHeight(LINE_H)
    line:SetPoint("LEFT", titleBar, "BOTTOMLEFT", LINE_LEFT, BREAK_Y)
    line:SetPoint("RIGHT", titleBar, "BOTTOMRIGHT", -LINE_RIGHT, BREAK_Y)

    local arrow = Skin.PlumberRect(art:CreateTexture(nil, "ARTWORK", nil, 1), P.FRAME, 66, 94, 619, 654)
    arrow:SetTexCoord(ARROW.x2, ARROW.y2, ARROW.x1, ARROW.y2, ARROW.x2, ARROW.y1, ARROW.x1, ARROW.y1)
    arrow:SetSize(ARROW_W, ARROW_H)
    arrow:SetPoint("LEFT", titleBar, "BOTTOMLEFT", 0, BREAK_Y)

    return art
end

-- For the setup tour's example window: the real skin's values and its title art.
DS.FOREVER_SKIN  = foreverSkin
DS.BuildTitleArt = BuildTitleArt
DS.LOOK = { ICON_LEFT = ICON_LEFT, ICON_SIZE = ICON_SIZE, RING_ATLAS = RING_ATLAS,
            RING_SIZE = RING_SIZE, RING_SUBLEVEL = RING_SUBLEVEL }

local function SetRing(row, on)
    local ring = rings[row]
    if not ring then
        if not on then return end
        ring = row.border:CreateTexture(nil, "OVERLAY", nil, RING_SUBLEVEL)
        ring:SetAtlas(RING_ATLAS)
        ring:SetSize(RING_SIZE, RING_SIZE)
        ring:SetPoint("CENTER", row.icone_classe, "CENTER")
        rings[row] = ring
    end
    ring:SetShown(on)
end

-- Shows or hides the module's art on a window, from the skin it wears now. Runs after
-- every skin change and every row refresh, which is how a row made later gets its ring;
-- it only creates what is missing, the rest is a Show or a Hide.
local function Decorate(inst)
    local base = inst.baseframe
    if not base then return end   -- Details itself, called with no window
    local on = inst.skin == FOREVER_NAME

    local art = titleArts[base]
    if on and not art then
        art = BuildTitleArt(base.titleBar)
        titleArts[base] = art
    end
    if art then art:SetShown(on) end

    local rows = inst.barras
    if rows then
        local withRing = on and not inst.row_info.no_icon
        for _, row in ipairs(rows) do
            SetRing(row, withRing)
        end
    end
end

-- ============================================================
-- Details access
-- ============================================================
local installed = false

-- Every active window, re-applying its current skin. Same as the original's
-- FixTitleBar: a window that was saved with this skin got Details' fallback at
-- login (the skin did not exist yet), and ChangeSkin() with no argument re-reads
-- the saved name now that InstallSkin has run.
local function RefreshInstances()
    local Details = _G.Details
    if not (Details and Details.GetNumInstances) then return end
    for i = 1, Details:GetNumInstances() do
        local inst = Details:GetInstance(i)
        if inst and inst.baseframe and inst.ativa then
            inst:ChangeSkin()
        end
    end
end

local function InstallSkin()
    if installed then return true end
    local Details = _G.Details
    if not (Details and Details.InstallSkin) then return false end
    -- Hooks first: InstallSkin itself puts the skin on a window that was waiting for it.
    hooksecurefunc(Details, "ChangeSkin", function(inst) Decorate(inst) end)
    -- InstanceRefreshRows takes the window as its argument from some callers.
    hooksecurefunc(Details, "InstanceRefreshRows", function(self, inst) Decorate(inst or self) end)
    Details:InstallSkin(SKIN_NAME, skinTable)
    Details:InstallSkin(FOREVER_NAME, foreverSkin)
    installed = true
    return true
end

-- Called by the options page. Puts a skin on every open Details window.
-- ChangeSkin copies the skin's settings (fonts, bar sizes...) only when the
-- window changes skin: on a window already using this one it just re-reads the
-- textures, so a window skinned before an update kept the old fonts. Clearing
-- the name forces the full apply, the same as picking the skin in Details' own
-- list; Details keeps position, scale and strata through it.
function DS:ApplyToAll(skinName)
    if not InstallSkin() then return false end
    local Details = _G.Details
    for i = 1, Details:GetNumInstances() do
        local inst = Details:GetInstance(i)
        if inst and inst.baseframe and inst.ativa then
            inst.skin = nil
            inst:ChangeSkin(skinName or SKIN_NAME)
        end
    end
    return true
end

-- ============================================================
-- Activate / Deactivate
-- Everything else (Refresh / OnEnable / OnDisable) comes from SP.ModuleMixin.
-- ============================================================
function DS:Activate()
    local Details = _G.Details

    -- Details is not a declared dependency, so it may load after us, or not be
    -- installed at all. Wait for its ADDON_LOADED rather than polling.
    if not (Details and Details.InstallSkin) then
        self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded")
        return
    end

    -- Details builds its windows a frame after login; the original waits the
    -- same way. Re-read the setting on the way back: the user may have switched
    -- the module off in between.
    if Details.IsLoaded and not Details.IsLoaded() then
        C_Timer.After(0, function()
            if self:IsOn() then self:Activate() end
        end)
        return
    end

    if InstallSkin() then
        RefreshInstances()
    end
end

function DS:OnAddonLoaded(_, addon)
    if addon == "Details" then
        self:UnregisterEvent("ADDON_LOADED")
        if self:IsOn() then self:Activate() end
    end
end

function DS:Deactivate()
    -- Nothing to undo: Details has no UninstallSkin. See the header note.
end
