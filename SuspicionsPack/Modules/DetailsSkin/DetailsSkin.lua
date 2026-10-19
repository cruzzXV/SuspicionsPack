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
--   * no Ace3 of its own, no slash command, no bundled profile: the profile export
--     string hard-codes the original addon's texture paths and cannot be re-pathed
--     without decoding it, so it is left out rather than shipped broken.
--
-- WHAT "ENABLED" MEANS HERE
--   Details has InstallSkin but no uninstall. Switching the module off only stops
--   it from (re)installing the skin at the next login; a window already using the
--   skin keeps it until the user picks another one in Details.
local SP = SuspicionsPack

local DS = SP:NewSPModule("DetailsSkin", "detailsSkin")
SP.DetailsSkin = DS

-- ============================================================
-- Constants
-- ============================================================
local SKIN_NAME = "|cffe51039Suspicion|r|cffffffffPack|r TWW"
DS.SKIN_NAME = SKIN_NAME

local MEDIA = [[Interface\AddOns\SuspicionsPack\Media\DetailsSkin\]]

-- LibSharedMedia names. Registered at file scope, like the original: Details
-- resolves statusbar textures by LSM name when it applies the skin, so the names
-- must exist before any window is skinned, including by Details itself at login.
local LSM_HEADER     = "SuspicionsPack TWW Header"
local LSM_BAR        = "SuspicionsPack TWW Bar"
local LSM_BACKGROUND = "SuspicionsPack TWW Background"

do
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        -- No extension on purpose: the files are .blp and the client resolves
        -- texture paths without one.
        LSM:Register("statusbar", LSM_HEADER,     MEDIA .. "header")
        LSM:Register("statusbar", LSM_BAR,        MEDIA .. "bar")
        LSM:Register("statusbar", LSM_BACKGROUND, MEDIA .. "background")
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
    micro_frames = { color = { 1, 1, 1, 1 }, font = "Accidental Presidency", size = 10, textymod = 1 },

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
            text_face          = "Friz Quadrata TT",
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
            font_face_file    = "Interface\\Addons\\Details\\fonts\\Accidental Presidency.ttf",
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
            font_face        = "Friz Quadrata TT",
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
    Details:InstallSkin(SKIN_NAME, skinTable)
    installed = true
    return true
end

-- Called by the options page. Puts the skin on every open Details window.
function DS:ApplyToAll()
    if not InstallSkin() then return false end
    local Details = _G.Details
    for i = 1, Details:GetNumInstances() do
        local inst = Details:GetInstance(i)
        if inst and inst.baseframe and inst.ativa then
            inst:ChangeSkin(SKIN_NAME)
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
