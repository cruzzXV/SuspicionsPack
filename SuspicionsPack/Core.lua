local ADDON_NAME, NS = ...

-- ============================================================
-- Create the addon object via AceAddon-3.0
-- Mixins: AceEvent-3.0 (global events), AceConsole-3.0 (chat commands)
-- ============================================================
local SP = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")
_G.SuspicionsPack = SP
SP.VERSION = "2.4.0"
SP.DEBUG   = false   -- set true in-game with: /run SuspicionsPack.DEBUG = true

--- Conditional debug print. Usage: SP:Debug("AutoBuy", "price=", total)
function SP:Debug(tag, ...)
    if not SP.DEBUG then return end
    local parts = { "|cff888888[SP:" .. tag .. "]|r" }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    print(table.concat(parts, " "))
end

-- ============================================================
-- Color source resolver
-- source: "theme" | "class" | "custom"
-- customColor: {r, g, b} table used when source == "custom"
-- Returns r, g, b
-- ============================================================
function SP.GetColorFromSource(source, customColor)
    local T = SP.Theme
    if source == "theme" then
        return T.accent[1], T.accent[2], T.accent[3]
    elseif source == "class" then
        local _, cls = UnitClass("player")
        local c = RAID_CLASS_COLORS and cls and RAID_CLASS_COLORS[cls]
        if c then return c.r, c.g, c.b end
        return T.accent[1], T.accent[2], T.accent[3]
    else -- "custom"
        local cc = customColor or { 1, 1, 1 }
        return cc[1], cc[2], cc[3]
    end
end

-- ============================================================
-- Font helpers (LibSharedMedia)
-- ============================================================

-- Validate a font path by attempting SetFont on a hidden Font object.
-- Uses the same probe technique as DBM: CreateFont() gives us a lightweight
-- Font object (no rendering), and pcall(probe.SetFont, ...) returns false if
-- WoW can't load the file — catching bad LSM registrations before they reach
-- any FontString or StatusBar.
local _fontProbe
local function GetFontProbe()
    if not _fontProbe then
        _fontProbe = CreateFont("SP_FontValidationProbe")
    end
    return _fontProbe
end

-- True only if the asset actually exists. SetFont both throws on a missing file
-- ("Invalid font asset (Fonts\NIMROD.TTF): file not found") AND returns false on
-- some failures, so both have to be checked -- returning pcall's results raw
-- would leak a second value and let a `false` return through as valid.
local _fontValidCache = {}

function SP.IsFontPathValid(path)
    if type(path) ~= "string" or path == "" then return false end

    local cached = _fontValidCache[path]
    if cached ~= nil then return cached end

    local probe = GetFontProbe()
    local ok, res = pcall(probe.SetFont, probe, path, 12, "")
    local valid = ok and res ~= false
    _fontValidCache[path] = valid
    return valid
end

local _fontListCache = nil

function SP.GetFontList()
    if _fontListCache then return _fontListCache end
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    local names = {}
    if lsm then
        for name, path in pairs(lsm:HashTable("font")) do
            -- Skip assets the client no longer ships. Blizzard drops fonts
            -- between expansions (Fonts\NIMROD.TTF is gone on Midnight) and LSM
            -- keeps advertising them, so offering one in the dropdown meant
            -- SetFont threw and took down the whole options page.
            if SP.IsFontPathValid(path) then
                names[#names + 1] = name
            end
        end
        table.sort(names)
    end
    if #names == 0 then
        names = { "Arial Narrow", "Expressway", "Friz Quadrata TT", "Morpheus", "Skurri" }
    end
    _fontListCache = names
    return names
end

-- The pack's own font, and the fallback for every unresolved name.
SP.DEFAULT_FONT = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"

-- Names the GUI dropdowns offer on top of whatever LibSharedMedia knows.
-- Single source of truth: six modules used to carry a private copy of this
-- table, which SHADOWED this resolver -- so any LSM font the user picked
-- (including fonts registered by other addons) silently fell back to Expressway
-- in those modules while working everywhere else.
SP.FONT_FACES = {
    ["Expressway"]    = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf",
    ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"]  = "Fonts\\ARIALN.TTF",
    ["Arial"]         = "Fonts\\ARIALN.TTF",   -- legacy alias (Durability)
    ["Morpheus"]      = "Fonts\\MORPHEUS.TTF",
    ["Skurri"]        = "Fonts\\SKURRI.TTF",
    ["Damage"]        = "Fonts\\DAMAGE.TTF",
    ["Ambiguity"]     = "Fonts\\2002.TTF",
    ["Nimrod MT"]     = "Fonts\\NIMROD.TTF",
}

-- Resolves a font name to a path. Returns nil on a miss so callers that want to
-- distinguish "unknown" from "default" still can; use SP.ResolveFont when you
-- just want something usable.
function SP.GetFontPath(name)
    if not name then return nil end

    -- LibSharedMedia FIRST. Checking the builtin table first would SHADOW it --
    -- the very bug this table replaced six private copies of. LSM maps
    -- "Morpheus" and "Skurri" to the _CYR variants, so preferring the builtin
    -- path silently changed those two fonts' glyphs.
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    if lsm then
        local path = lsm:Fetch("font", name, true)   -- noDefault: we want a real miss
        if path and SP.IsFontPathValid(path) then
            return path
        end
    end

    -- Fallback for names LSM does not know. Validated too: Blizzard removes
    -- font assets between expansions (Fonts\NIMROD.TTF is gone on Midnight) and
    -- an unvalidated return made SetFont throw inside a GUI page builder,
    -- killing the whole page.
    local builtin = SP.FONT_FACES[name]
    if builtin and SP.IsFontPathValid(builtin) then return builtin end

    return nil
end

-- Always returns a usable path. This is what modules should call.
function SP.ResolveFont(name)
    return SP.GetFontPath(name) or SP.DEFAULT_FONT
end

-- The flat white texture, used as a backdrop/border fill all over the addon.
-- Was written out as a literal in six separate files.
SP.BLANK = "Interface\\Buttons\\WHITE8X8"

-- Applies the standard anchor block that eight alert modules each hand-rolled:
-- clear points, resolve the named anchor frame, place it, set the strata.
--
-- The anchor frame is resolved by name at call time, matching what the modules
-- already do individually -- this helper is a de-duplication, not a fix.
-- NOTE when migrating CombatTimer: its ApplyPosition deliberately does NOT set
-- the frame strata, while this helper always does.
function SP.ApplyAnchor(frame, db, defX, defY, defStrata)
    if not (frame and db) then return end

    local anchorTo = _G[db.anchorFrame or "UIParent"] or UIParent
    frame:ClearAllPoints()
    frame:SetPoint(
        db.anchorFrom or "CENTER",
        anchorTo,
        db.anchorTo   or "CENTER",
        db.x          or defX or 0,
        db.y          or defY or 0
    )
    frame:SetFrameStrata(db.frameStrata or defStrata or "HIGH")
end

-- StatusBar texture helpers (LibSharedMedia)
local _statusBarListCache = nil

function SP.GetStatusBarList()
    if _statusBarListCache then return _statusBarListCache end
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    local names = {}
    if lsm then
        for name in pairs(lsm:HashTable("statusbar")) do
            names[#names + 1] = name
        end
        table.sort(names)
    end
    if #names == 0 then
        names = { "Blizzard" }
    end
    _statusBarListCache = names
    return names
end

function SP.GetStatusBarPath(name)
    if not name then return "Interface\\TargetingFrame\\UI-StatusBar" end
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    if lsm and lsm:IsValid("statusbar", name) then
        return lsm:Fetch("statusbar", name)
    end
    return "Interface\\TargetingFrame\\UI-StatusBar"
end

-- Theme presets
-- ============================================================
SP.ThemePresets = {
    -- Values taken from the approved options mockup. Two things mattered:
    -- `border` was pure black, so every card edge and hairline was invisible
    -- against a near-black background; and the three greys sat within 0.09 of
    -- each other, so chrome, page and card read as one flat surface.
    ["Suspicion"] = {
        bgDark        = { 0.0667, 0.0667, 0.0784, 1    },  -- page canvas   #111114
        bgMedium      = { 0.0902, 0.0902, 0.1098, 1    },  -- window chrome #17171C
        bgLight       = { 0.0863, 0.0863, 0.1059, 1    },  -- cards         #16161B
        bgHover       = { 0.1176, 0.1176, 0.1451, 1    },  --               #1E1E25
        border        = { 0.1451, 0.1451, 0.1725, 1    },  -- visible hairline #25252C
        accent        = { 0.8980, 0.0627, 0.2235, 1    },
        accentHover   = { 0.8980, 0.0627, 0.2235, 0.25 },
        accentDim     = { 0.8980, 0.0627, 0.2235, 1    },
        textPrimary   = { 0.9020, 0.9020, 0.9176, 1    },  --               #E6E6EA
        textSecondary = { 0.6588, 0.6588, 0.7059, 1    },  --               #A8A8B4
        textMuted     = { 0.4314, 0.4314, 0.4706, 1    },  --               #6E6E78
        selectedBg    = { 0.8980, 0.0627, 0.2235, 0.25 },
        selectedText  = { 0.8980, 0.0627, 0.2235, 1    },
        error         = { 0.90,   0.30,   0.30,   1    },
        success       = { 0.30,   0.80,   0.40,   1    },
        warning       = { 0.90,   0.75,   0.30,   1    },
    },
}

-- One theme. The picker and the other twelve presets are gone: the addon has
-- a single visual identity and thirteen palettes to maintain was not one.
-- SP.ThemePresetOrder went with them -- it existed only to order the picker's
-- dropdown, and a one-entry ordering table with no reader is just a claim that
-- a picker still exists somewhere.

-- ============================================================
-- SP.Theme — live table referenced by the GUI
-- All color keys are updated by SP.RefreshTheme().
-- Dimension keys are fixed (not per-preset).
-- ============================================================
local echoDefaults = SP.ThemePresets["Suspicion"]
SP.Theme = {
    -- Colors (from preset, mutated by RefreshTheme)
    bgDark        = { echoDefaults.bgDark[1],        echoDefaults.bgDark[2],        echoDefaults.bgDark[3],        echoDefaults.bgDark[4]        },
    bgMedium      = { echoDefaults.bgMedium[1],      echoDefaults.bgMedium[2],      echoDefaults.bgMedium[3],      echoDefaults.bgMedium[4]      },
    bgLight       = { echoDefaults.bgLight[1],        echoDefaults.bgLight[2],       echoDefaults.bgLight[3],       echoDefaults.bgLight[4]       },
    bgHover       = { echoDefaults.bgHover[1],        echoDefaults.bgHover[2],       echoDefaults.bgHover[3],       echoDefaults.bgHover[4]       },
    border        = { echoDefaults.border[1],         echoDefaults.border[2],        echoDefaults.border[3],        echoDefaults.border[4]        },
    accent        = { echoDefaults.accent[1],         echoDefaults.accent[2],        echoDefaults.accent[3],        echoDefaults.accent[4]        },
    accentHover   = { echoDefaults.accentHover[1],    echoDefaults.accentHover[2],   echoDefaults.accentHover[3],   echoDefaults.accentHover[4]   },
    accentDim     = { echoDefaults.accentDim[1],      echoDefaults.accentDim[2],     echoDefaults.accentDim[3],     echoDefaults.accentDim[4]     },
    textPrimary   = { echoDefaults.textPrimary[1],    echoDefaults.textPrimary[2],   echoDefaults.textPrimary[3],   echoDefaults.textPrimary[4]   },
    textSecondary = { echoDefaults.textSecondary[1],  echoDefaults.textSecondary[2], echoDefaults.textSecondary[3], echoDefaults.textSecondary[4] },
    textMuted     = { echoDefaults.textMuted[1],      echoDefaults.textMuted[2],     echoDefaults.textMuted[3],     echoDefaults.textMuted[4]     },
    selectedBg    = { echoDefaults.selectedBg[1],     echoDefaults.selectedBg[2],    echoDefaults.selectedBg[3],    echoDefaults.selectedBg[4]    },
    selectedText  = { echoDefaults.selectedText[1],   echoDefaults.selectedText[2],  echoDefaults.selectedText[3],  echoDefaults.selectedText[4]  },
    error         = { echoDefaults.error[1],          echoDefaults.error[2],         echoDefaults.error[3],         echoDefaults.error[4]         },
    success       = { echoDefaults.success[1],        echoDefaults.success[2],       echoDefaults.success[3],       echoDefaults.success[4]       },
    warning       = { echoDefaults.warning[1],        echoDefaults.warning[2],       echoDefaults.warning[3],       echoDefaults.warning[4]       },

    -- Fixed dimensions (not per-preset)
    headerHeight  = 36,
    footerHeight  = 26,
    sidebarWidth  = 162,
    padding       = 8,
    paddingSmall  = 4,
    borderSize    = 1,
    winW          = 810,
    winH          = 810,
    winMinW       = 810,
    winMinH       = 380,
}

-- RefreshTheme: update SP.Theme colors from the saved preset, then rebuild the GUI
function SP.RefreshTheme()
    local db     = SP.GetDB()
    local name   = db and db.settings and db.settings.theme and db.settings.theme.preset or "Suspicion"
    local preset = SP.ThemePresets[name] or SP.ThemePresets["Suspicion"]
    local T      = SP.Theme

    local colorKeys = {
        "bgDark","bgMedium","bgLight","bgHover","border",
        "accent","accentHover","accentDim",
        "textPrimary","textSecondary","textMuted",
        "selectedBg","selectedText","error","success","warning",
    }
    for _, k in ipairs(colorKeys) do
        local src = preset[k]
        if src then
            T[k][1] = src[1]; T[k][2] = src[2]; T[k][3] = src[3]; T[k][4] = src[4]
        end
    end

    -- Update minimap icon tint to match new theme accent.
    -- Setting iconR/G/B via the LDB proxy fires OnAttributeChanged so LibDBIcon
    -- receives the change automatically.  Refresh() is a belt-and-suspenders
    -- call for implementations that don't watch the callback.
    if SP.MinimapDataObj then
        SP.MinimapDataObj.iconR = T.accent[1]
        SP.MinimapDataObj.iconG = T.accent[2]
        SP.MinimapDataObj.iconB = T.accent[3]
        local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
        if LDBIcon and LDBIcon.Refresh then LDBIcon:Refresh("SuspicionsPack") end
    end

    -- Repaint the options window in place.
    --
    -- This used to destroy and rebuild the whole window (SetParent(nil) on the
    -- frame, wipe the pools, drop the page cache). WoW cannot free a frame, so
    -- every preset click abandoned the entire tree -- on the order of 1800
    -- frames once a few pages had been visited -- and the window visibly blinked
    -- shut and reopened. Every widget now registers a painter instead, so this
    -- walks that registry and creates nothing.
    if SP.GUI and SP.GUI.OnThemeChanged then SP.GUI.OnThemeChanged() end

    -- Repaint the drawer tab — it won't update on its own after a theme switch
    if SP.Drawer then SP.Drawer.Refresh() end

    -- Repaint the cursor if it's using the theme accent color
    if SP.Cursor and SP.Cursor.Refresh then SP.Cursor.Refresh() end

    -- Rebuild CraftShopper frame so accent-baked colors pick up the new theme
    if SP.CraftShopper and SP.CraftShopper.RebuildShopFrame then
        SP.CraftShopper.RebuildShopFrame()
    end
end

-- ============================================================
-- Saved variable defaults (AceDB profile format)
-- ============================================================
local DEFAULTS = {
    profile = {
        settings = {
            theme = { preset = "Suspicion" },
            lastSeenVersion = "",
        },
        drawer = {
            enabled       = false,
            side          = "LEFT",
            btnSize       = 26,
            btnPad        = 6,
            maxCols       = 5,
            hideDelay     = 0.3,
            iconSize      = 18,
            tabW          = 6,
            tabH          = 40,
            tabColorSource = "custom",   -- "theme" | "class" | "custom"
            tabColor       = { 0.6, 0.6, 0.6 },  -- #999999
            errorAlert     = true,        -- tab turns red when BugGrabber catches a Lua error
            showBorder          = true,       -- 1px border around the drawer panel
            borderColorSource   = "theme",    -- "theme" | "class"  (panel border color)
            showTabBorder  = true,       -- 1px black border around the tab handle
            buttonRules       = {},
            buttonBorderStyle = "default",  -- "default" (gold) | "dark" | "none"
        },
        minimapButton  = { hide = false },
        copyTooltip    = { enabled = false, modifier = "ctrl", key = "C" },
        fastLoot       = { enabled = false },
        filterExpansionOnly = { enabled = false },
        cvars          = {},   -- individual CVar values are synced from game on login
        combatTimer = {
            enabled           = false,
            printToChat       = true,
            showLastDuration  = false,
            format            = "MM:SS",
            x                = 0,
            y                = 250,
            anchorFrom       = "CENTER",
            anchorTo         = "CENTER",
            anchorFrame      = "UIParent",
            frameStrata      = "TOOLTIP",
            fontFace         = "Expressway",
            fontSize         = 18,
            outline          = "SOFTOUTLINE",
            colorInCombat    = { 1, 0.2, 0.2, 1 },
            colorOutOfCombat = { 1, 1, 1, 0.7 },
            colorInCombatSource    = "custom",   -- "theme" | "class" | "custom"
            colorOutOfCombatSource = "custom",   -- "theme" | "class" | "custom"
            -- Font shadow (only read when shadowEnabled is true)
            shadowEnabled     = false,
            shadowColorSource = "custom",   -- "theme" | "class" | "custom"
            shadowColor       = { 0, 0, 0 },
            shadowX           = 1,
            shadowY           = -1,
            backdrop = {
                enabled     = false,
                color       = { 0, 0, 0, 0.6 },
                borderColor = { 0, 0, 0, 1 },
                borderSize  = 1,
                paddingW    = 10,
                paddingH    = 6,
            },
        },
        combatCross = {
            enabled                = false,
            x                      = 0,
            y                      = 0,
            anchorFrom             = "CENTER",
            anchorTo               = "CENTER",
            anchorFrame            = "UIParent",
            frameStrata            = "HIGH",
            thickness              = 14,       -- font size = thickness * 2
            outline                = true,
            colorSource            = "theme",  -- "theme" | "class" | "custom"
            color                  = { 1, 1, 1 },
            outOfRangeColor         = { 1, 0, 0, 1 },
            rangeColorMeleeEnabled  = false,
            rangeColorRangedEnabled = false,
        },
        cursor = {
            opacityInCombat    = 100,
            opacityOutOfCombat = 100,
            trail         = false,
            trailShape    = "Dot",
            trailLength   = 20,
            trailSize     = 24,
            trailSpacing  = 50,
            trailAlpha    = 80,
            trailDuration = 2.0,
            enabled          = false,
            size             = 50,
            texture          = "Thick",
            colorSource      = "theme",       -- "theme" | "class" | "custom"
            cursorColor      = { 1.0, 1.0, 1.0 },
            showDot          = true,
            dotSize          = 6,
            -- Click circle (second ring, visible while mouse button held ≥ 150 ms)
            showClickCircle  = false,
            clickMode        = "overlay",     -- "overlay" = extra ring | "replace" = morph the main ring
            clickSize        = 70,
            clickTexture     = "Thin",
            clickColorSource = "theme",       -- "theme" | "class" | "custom"
            clickColor       = { 1.0, 1.0, 1.0 },
            limitUpdateRate  = false,
            updateInterval   = 0.02,          -- seconds between updates (0.02 s = 50 fps)
        },
        automation = {
            enabled          = false,
            autoFillDelete   = false,
            autoRoleCheck    = false,
            autoGuildInvite  = false,
            autoFriendInvite = false,
            skipCinematics   = false,
            hideTalkingHead  = false,
            hideBagsBar      = false,
            autoSellJunk     = false,
            autoRepair       = false,
            useGuildFunds    = false,
            autoDecorVendor  = false,
            autoSwitchFlight = false,
        },
        -- Releasing is boss by boss, so `zones` ships EMPTY on purpose. An ID
        -- that is subtly wrong never matches and the feature just looks broken;
        -- the options page reads your current spot and adds it in one click.
        autoRelease = {
            enabled = false,
            inPvP   = true,
            delay   = 2,
            zones   = {},
            -- Hard rezzes only, and onlyWhenFightOver is what makes that true:
            -- a resurrection castable out of combat CANNOT be cast in combat,
            -- so a caster who is in combat is casting a battle rez. Turning it
            -- off accepts those too, which is not a thing to do by accident.
            acceptRez         = false,
            onlyWhenFightOver = true,
        },
        autoInvite = {
            enabled       = false,
            inviteAll     = true,
            inviteFriends = true,
            inviteGuild   = true,
            keywords      = { "inv", "123" },
        },
        performance = {
            enabled             = false,
            autoClearCombatLog  = false,
            hideScreenshotMsg   = false,
            setSoundChannels    = false,
            soundChannelCount   = 32,
            soundChannelNotify  = true,
        },
        enhancedObjectiveText = {
            enabled  = false,
            fontSize = 22,
            y        = 0,
        },
        cleanObjectiveTrackerHeader = {
            enabled = false,
        },
        microMenuSkin = {
            enabled        = false,
            iconsPerRow    = 0,
            alpha          = 100,
            fadeOnHover    = false,
            showBackdrop   = true,
            showBorder     = true,
            borderSize     = 1,
            iconInset      = 2,
            iconZoom       = 0.10,
            highlightAlpha = 0.20,
            desaturate     = false,
            overrideLayout = false,
            buttonSize     = 26,
            buttonSpacing  = 0,
            backdropColor  = { r = 0.06, g = 0.06, b = 0.06, a = 0.85 },
            borderColor    = { r = 0.00, g = 0.00, b = 0.00, a = 1.00 },
            hoverColor     = { r = 0.90, g = 0.06, b = 0.22, a = 1.00 },
        },
        tankMD = {
            enabled         = false,
            selectionMethod = "tankRoleOnly",
        },
        focusTargetMarker = {
            enabled  = false,
            announce = true,
            marker   = 5,   -- Moon
        },
        reapMeter = {
            enabled = false,
            -- Every key below is also written by LoadSizesFromDB() in
            -- Modules/ReapPredict/ReapPredict.lua the first time the module
            -- enables. Restated here so the options UI can show a modified dot,
            -- revert a row, and let a profile import through -- the values MUST
            -- stay identical to the module's own fallbacks.
            -- layout.barTexture is deliberately absent: it has no default and
            -- nil legitimately means "Solid".
            layout = {
                -- Soul bar
                width          = 360,
                height         = 22,
                font           = 13,
                fontKey        = "Arial Narrow",   -- LSM font name
                locked         = false,
                showSoulBar    = true,
                showMocPreview = true,
                showCsCounter  = true,
                cellMode       = false,
                mocRailOffsetX = 0,
                mocRailOffsetY = 0,
                -- Fury bar
                showFuryBar        = true,
                showFuryMocPreview = false,
                furyWidth          = 360,
                furyHeight         = 14,
                furyFont           = 13,
                furyLocked         = false,
                furyOffsetX        = 0,
                furyOffsetY        = 0,
                furyPreviewAlpha   = 0.18,   -- stored 0-1; the slider works in percent
                -- Snap to an external bar (defaults live in Snap.Wanted / Snap.Name)
                snapToBar   = false,
                snapBarName = "ERB_PrimaryBar",   -- EllesmereUI's primary (power) bar
                -- Cooldown Manager sync
                syncToCDM  = false,
                cdmOffsetX = 0,
                cdmOffsetY = -4,
                -- Fading
                fadingEnabled         = false,
                fadingOpacity         = 0,
                fadingTriggerNoTarget = true,
                fadingTriggerOOC      = false,
                fadingTriggerMounted  = false,
            },
            colors = {   -- { r, g, b, a }; mirrors DEFAULT_COLORS in ReapPredict.lua
                bg             = { 0.05, 0.04, 0.08, 0.90 },
                edge           = { 0.02, 0.02, 0.04, 1.00 },
                growthBuild    = { 0.30, 0.46, 0.88, 1.00 },
                beyondBuild    = { 0.05, 0.04, 0.08, 0.90 },
                growthVM       = { 0.18, 0.30, 0.62, 1.00 },
                beyondVM       = { 0.05, 0.04, 0.08, 0.90 },
                sfBase         = { 0.92, 0.62, 0.22, 1.00 },
                sfMoc          = { 1.00, 0.76, 0.32, 1.00 },
                mocRailFill    = { 1.00, 0.88, 0.55, 1.00 },
                mocRailTrack   = { 0.28, 0.16, 0.06, 0.80 },
                numberLabel    = { 0.98, 0.95, 0.88, 1.00 },
                sfNumberLabel  = { 1.00, 0.86, 0.52, 1.00 },
                thresholdBuild = { 0.96, 0.92, 0.78, 0.90 },
                thresholdVM    = { 0.96, 0.92, 0.78, 0.90 },
                furyTick       = { 0.96, 0.92, 0.78, 0.90 },
                furyFill       = { 0.32, 0.28, 0.62, 1.00 },
                furyConsume    = { 0.45, 0.38, 0.78, 1.00 },
                furyFlat       = { 0.58, 0.50, 0.82, 1.00 },
                furySoul       = { 0.68, 0.62, 0.90, 1.00 },
                furyLabel      = { 0.98, 0.95, 0.88, 1.00 },
            },
        },
        deathAlert = {
            enabled         = false,
            displayText     = "died",
            fontName        = "Expressway",
            fontSize        = 28,
            messageDuration = 4,
            x               = 0,
            y               = 200,
            -- Anchor settings
            anchorFrom      = "CENTER",
            anchorTo        = "CENTER",
            anchorFrame     = "UIParent",
            frameStrata     = "HIGH",
            showForSelf     = true,
            -- Sound
            playSound       = false,
            sound           = "readycheck",
            -- TTS
            playTTS         = false,
            ttsText         = "{name} died",
            ttsVolume       = 50,
            -- Role-based overrides (raid only)
            byRole = {
                DAMAGER = { showText = true, playSound = true },
                HEALER  = { showText = true, playSound = true },
                TANK    = { showText = true, playSound = true },
            },
        },
        groupJoinedReminder = {
            enabled = false,
        },
        movementAlert = {
            enabled          = false,
            anchorFrom       = "CENTER",
            anchorTo         = "CENTER",
            anchorFrame      = "UIParent",
            x                = 0,
            y                = 300,
            frameStrata      = "MEDIUM",
            frameLevel       = 50,
            fontFace         = "Expressway",
            fontSize         = 14,
            outline          = "OUTLINE",
            justify          = "CENTER",
            colorSource      = "custom",   -- "theme" | "class" | "custom"
            color            = { 1, 1, 1, 1 },
            shadowX          = 1,
            shadowY          = -1,
            shadowAlpha      = 1,
            precision        = 0,
            updateInterval   = 0.1,
            showTimeSpiral   = true,
            timeSpiralText   = "Free Movement",
            timeSpiralColor  = { 0.451, 0.741, 0.522, 1 },
            timeSpiralPlaySound = false,
            timeSpiralSound  = nil,   -- LSM sound name (string)
            timeSpiralTextX      = 0,
            timeSpiralTextY      = 200,
            timeSpiralShowIcon   = false,
            timeSpiralIconSize   = 50,
            timeSpiralIconX      = 0,
            timeSpiralIconY      = 250,
            timeSpiralIconAnchorFrame  = "UIParent",
            timeSpiralIconAnchorFrom   = "CENTER",
            timeSpiralIconAnchorTo     = "CENTER",
            timeSpiralIconFrameStrata  = "MEDIUM",
            disabledSpells   = {},   -- [spellId] = true to skip that spell
            spellOverrides   = {},   -- [spellId] = { enabled, customText } for user-added spells
        },
        autoPlaystyle = {
            enabled   = false,
            playstyle = 3,  -- 1=Learning 2=Relaxed 3=Competitive 4=Carry Offered
        },
        craftShopper = {
            enabled = false,
        },
        whisperAlert = {
            enabled      = false,
            sound        = "SuspicionsPack Whisper",
            bnetSound    = "SuspicionsPack Whisper",
            channel      = "Master",
            muteInCombat = false,
        },
        gatewayAlert = {
            enabled     = false,
            fontSize    = 16,
            fontFace    = "Expressway",
            fontOutline = "OUTLINE",
            frameStrata = "HIGH",
            colorSource = "custom",   -- "theme" | "class" | "custom"
            color       = { 0.3, 1.0, 0.4, 1 },   -- bright green
            x           = 0,
            y           = -100,
            anchorFrom  = "CENTER",
            anchorTo    = "CENTER",
            anchorFrame = "UIParent",
        },
        durability = {
            enabled     = false,
            threshold   = 30,   -- show warning when durability <= this %
            warningText = "REPAIR NOW",
            fontSize    = 20,
            fontFace    = "Expressway",
            fontOutline = "OUTLINE",
            frameStrata = "HIGH",
            colorSource = "custom",   -- "theme" | "class" | "custom"
            color       = { 1, 0.537, 0.2, 1 },
            x           = 0,
            y           = -200,
            anchorFrom  = "CENTER",
            anchorTo    = "CENTER",
            anchorFrame = "UIParent",
        },
        silvermoonMapIcon = {
            enabled             = false,
            showOnlyProfessions = true,
        },
        potionAlert = {
            enabled           = false,
            enabledInDungeons = true,
            enabledInRaids    = true,
            displayText       = "Potion Ready",
            colorSource       = "custom",
            color             = { 0.4, 1, 0.4, 1 },
            fontFace          = "Expressway",
            fontSize          = 20,
            fontOutline       = "OUTLINE",
            frameStrata       = "HIGH",
            x                 = 0,
            y                 = 200,
            anchorFrom        = "CENTER",
            anchorTo          = "CENTER",
            anchorFrame       = "UIParent",
            displayDuration   = 5,    -- seconds before auto-hide; 0 = stay forever
            playTTS           = false,
            ttsText           = "Potion Ready",
            ttsVolume         = 75,   -- 0-100
            ttsVoiceId        = 0,    -- voiceID from C_VoiceChat.GetTtsVoices()
        },
        bloodlustAlert = {
            enabled    = false,
            -- Detection: BL / Heroism / Time Warp add exactly +30 pp of haste in one
            -- server tick. Threshold is hardcoded to MIN_GAIN = 30 in BloodlustAlert.lua
            -- (a physical constant, not a user setting).
            playSound  = true,
            sound      = "hotnigga",
            channel    = "Master",
            -- Timer display
            timerEnabled      = true,
            timerX            = 0,
            timerY            = -220,
            timerAnchorFrom   = "CENTER",
            timerAnchorTo     = "CENTER",
            timerAnchorFrame  = "UIParent",
            frameStrata       = "HIGH",   -- strata of the timer frame (the only frame this module draws)
            timerNumColor     = { 1, 1, 1, 1 },
            timerBarColor     = { 0.93, 0.27, 0.27, 1 },
            timerNumColorSource = "custom",   -- "theme" | "class" | "custom"
            timerBarColorSource = "custom",   -- "theme" | "class" | "custom"
            timerFontFace     = "Expressway",
            timerFontSize     = 22,
            timerOutline      = "OUTLINE",
            timerShowLabel    = true,
            timerShowBar      = true,
            timerBgOpacity    = 0.85,
        },
        spellEffectAlpha = {
            enabled       = false,
            globalDefault = 100,
            specs         = {
                [250]=100,[251]=100,[252]=100, -- Death Knight
                [577]=100,[581]=100,[1480]=100, -- Demon Hunter
                [102]=100,[103]=100,[104]=100,[105]=100, -- Druid
                [1467]=100,[1468]=100,[1473]=100, -- Evoker
                [253]=100,[254]=100,[255]=100, -- Hunter
                [62]=100,[63]=100,[64]=100, -- Mage
                [268]=100,[269]=100,[270]=100, -- Monk
                [65]=100,[66]=100,[70]=100, -- Paladin
                [256]=100,[257]=100,[258]=100, -- Priest
                [259]=100,[260]=100,[261]=100, -- Rogue
                [262]=100,[263]=100,[264]=100, -- Shaman
                [265]=100,[266]=100,[267]=100, -- Warlock
                [71]=100,[72]=100,[73]=100, -- Warrior
            },
        },
    },
    -- ── Per-character data (not shared across alts) ──────────────────────
    char = {
        autoBuy = {
            enabled     = false,
            items       = {
                -- Preset item overrides: [Q1 itemID] = { enabled, quantity, buyQty, quality }
                -- quantity: MIN QTY — trigger a purchase if bags drop below this amount
                -- buyQty:   BUY QTY — how many to purchase each time (0 = use preset default)
                -- quality:  1 = buy Q1 variant, 2 = buy Q2 variant (default for items with q2)
                -- ── Flasks ────────────────────────────────────────────
                [241323] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Flask of the Magisters
                [241325] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Flask of the Blood Knights
                [241327] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Flask of the Shattered Sun
                [241321] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Flask of Thalassian Resistance
                -- ── Health/Mana Potions ───────────────────────────────
                [241305] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Silvermoon Health Potion
                [241301] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Lightfused Mana Potion
                [241299] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Amani Extract
                [241287] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Light's Preservation
                -- ── Combat Potions ────────────────────────────────────
                [241309] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Light's Potential
                [241303] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Void-Shrouded Tincture
                [241289] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Potion of Recklessness
                [241293] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Draught of Rampant Abandon
                [241295] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Potion of Devoured Dreams
                [241297] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Potion of Zealotry
                [241339] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Enlightenment Tonic
                -- ── Augment Runes ─────────────────────────────────────
                [259085] = { enabled = false, quantity = 0, buyQty = 0, quality = 1 }, -- Void-Touched Augment Rune (no Q2)
                -- ── Weapon Oils ───────────────────────────────────────
                [243733] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Thalassian Phoenix Oil
                [243735] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Oil of Dawn
                [243737] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Smuggler's Enchanted Edge
                -- ── Individual Food ───────────────────────────────────
                [242274] = { enabled = false, quantity = 0, buyQty = 0, quality = 1 }, -- Champion's Bento (no Q2)
                [242275] = { enabled = false, quantity = 0, buyQty = 0, quality = 1 }, -- Royal Roast (no Q2)
                -- ── Raid Feasts ───────────────────────────────────────
                [255845] = { enabled = false, quantity = 0, buyQty = 0, quality = 1 }, -- Silvermoon Parade (no Q2)
                [255846] = { enabled = false, quantity = 0, buyQty = 0, quality = 1 }, -- Harandar Celebration (no Q2)
                [242272] = { enabled = false, quantity = 0, buyQty = 0, quality = 1 }, -- Quel'dorei Medley (no Q2)
                [242273] = { enabled = false, quantity = 0, buyQty = 0, quality = 1 }, -- Blooming Feast (no Q2)
            },
        },
    },
}

-- Exposed so the GUI profile import can use the current schema as a
-- whitelist: without it, importing a string exported before a section was
-- deleted re-injects those dead keys permanently.
SP.DEFAULTS = DEFAULTS

-- ============================================================
-- DB accessor — always returns the current profile table.
-- All module code uses SP.GetDB().drawer, SP.GetDB().cursor, etc.
-- ============================================================
function SP.GetDB()
    return SP.db and SP.db.profile or {}
end

-- Per-character DB accessor (not shared across alts).
-- Use for settings that differ between characters (e.g. AutoBuy presets).
function SP.GetCharDB()
    return SP.db and SP.db.char or {}
end

-- ============================================================
-- Pixel utilities
-- ============================================================
SP.Pixel = {}
local Px = SP.Pixel

local BLANK = [[Interface\Buttons\WHITE8X8]]

local floor, ceil = math.floor, math.ceil
local physW, physH = GetPhysicalScreenSize()
local perfect      = 768 / physH
local mult         = 1
local scaleCallbacks = {}

local function UpdateMult()
    physW, physH = GetPhysicalScreenSize()
    perfect      = 768 / physH
    local scale  = UIParent:GetEffectiveScale()
    mult = perfect / scale
end

function Px.Scale(val)
    if val == 0 or mult == 1 then return val end
    if mult > 1 then
        return val > 0 and ceil(val / mult) * mult or floor(val / mult) * mult
    end
    return val > 0 and floor(val / mult) * mult or ceil(val / mult) * mult
end

function Px.OnScaleChange(id, fn)
    scaleCallbacks[id] = fn
end

local function GiveBackdrop(frame)
    if frame.SetBackdrop then return end
    for k, v in pairs(BackdropTemplateMixin) do
        if type(v) == "function" then frame[k] = v end
    end
    if frame.OnBackdropSizeChanged then
        frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged)
    end
end

local bdCache = {}
local function GetBD(edge)
    if not bdCache[edge] then
        bdCache[edge] = { bgFile = BLANK, edgeFile = BLANK, edgeSize = edge }
    end
    return bdCache[edge]
end

function Px.SetupFrameBackdrop(frame, bgR, bgG, bgB, bgA, brR, brG, brB, brA, size)
    GiveBackdrop(frame)
    local edge = Px.Scale(size or 1)
    if frame._bdEdge ~= edge or not frame.backdropInfo then
        frame._bdEdge = edge
        frame:SetBackdrop(GetBD(edge))
    end
    frame:SetBackdropColor(bgR or 0.05, bgG or 0.05, bgB or 0.05, bgA or 0.97)
    frame:SetBackdropBorderColor(brR or 0.12, brG or 0.12, brB or 0.12, brA or 1)
end

function Px.ApplyFont(fs, size, fontPath)
    if not fs then return end
    fs:SetFont(fontPath or "Fonts\\FRIZQT__.TTF", size, "")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
end

local scaleWatcher = CreateFrame("Frame")
scaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
scaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleWatcher:SetScript("OnEvent", function()
    UpdateMult()
    for _, fn in pairs(scaleCallbacks) do fn() end
end)
hooksecurefunc(UIParent, "SetScale", function()
    UpdateMult()
    for _, fn in pairs(scaleCallbacks) do fn() end
end)
UpdateMult()

-- ============================================================
-- AceAddon lifecycle
-- ============================================================

-- OnInitialize: called by AceAddon when ADDON_LOADED fires for this addon.
-- The DB is set up here — all modules can call SP.GetDB() from OnEnable onwards.
function SP:OnInitialize()
    -- AceDB-3.0 manages SavedVariables, deep-copies defaults, and handles profiles.
    -- Passing "Default" as the 3rd arg means all characters share the "Default"
    -- profile by default (equivalent to the old single global saved variable).
    -- Migrations run against the RAW saved table, before AceDB copies defaults
    -- on top of it. Doing it after would mean pruning keys that AceDB has just
    -- rawset back in, and the prune would silently do nothing.
    if SP.RunMigrations then
        SP.RunMigrations(_G.SuspicionsPackDB)
    end

    self.db = LibStub("AceDB-3.0"):New("SuspicionsPackDB", DEFAULTS, "Default")

    -- Apply the saved theme into SP.Theme before the GUI is ever built
    local profile = self.db.profile
    local saved   = profile.settings and profile.settings.theme and profile.settings.theme.preset or "Suspicion"
    local preset = SP.ThemePresets[saved] or SP.ThemePresets["Suspicion"]
    local T      = SP.Theme
    local colorKeys = {
        "bgDark","bgMedium","bgLight","bgHover","border",
        "accent","accentHover","accentDim",
        "textPrimary","textSecondary","textMuted",
        "selectedBg","selectedText","error","success","warning",
    }
    for _, k in ipairs(colorKeys) do
        local src = preset[k]
        if src then
            T[k][1] = src[1]; T[k][2] = src[2]
            T[k][3] = src[3]; T[k][4] = src[4]
        end
    end

    -- Register slash commands via AceConsole
    self:RegisterChatCommand("spack",     "ToggleGUI")
    self:RegisterChatCommand("suspicion", "ToggleGUI")
end

-- OnEnable: called right after OnInitialize (and after all module OnEnable calls).
function SP:OnEnable()
    -- Reconcile AceAddon's module flags with the user's settings before any
    -- login event fires, so a module the user turned off never gets a chance
    -- to register anything.
    if SP.ApplyModuleEnabledStates then
        SP:ApplyModuleEnabledStates()
    end

    local ac = SP.Theme.accent
    local aHex = string.format("%02X%02X%02X",
        math.floor(ac[1]*255+0.5), math.floor(ac[2]*255+0.5), math.floor(ac[3]*255+0.5))
    print("|cff" .. aHex .. "Suspicion's|r Pack : |cff" .. aHex .. "/spack|r, |cff" .. aHex .. "/suspicion|r to open settings.")

    -- Re-apply CVars that WoW resets on every login.
    -- Registered on PLAYER_LOGIN (not ADDON_LOADED) so we run after the
    -- game engine's own startup CVar sweep has already finished.
    local function ApplyCVars()
        SetCVar("preloadWorldNonCriticalObjects", 1)
    end
    if IsLoggedIn() then
        ApplyCVars()
        SP.CheckChangelog()
    else
        self:RegisterEvent("PLAYER_LOGIN", function()
            ApplyCVars()
            SP.CheckChangelog()
        end)
    end
end

-- ============================================================
-- SP.ShowNotification(text)
-- Displays a short fade-in/fade-out text at the center of the
-- screen as a short fade-in/fade-out notification.
-- text: pre-colored string, e.g. "|cff4DCC66Module: On|r"
-- ============================================================
local SP_NOTIFY_FONT = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"

function SP.ShowNotification(text)
    -- Kill any existing notification
    if SP._notifFrame then
        SP._notifFrame:Hide()
        SP._notifFrame = nil
    end

    local f = CreateFrame("Frame", nil, UIParent)
    f:SetToplevel(true)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(150)
    f:SetSize(400, 50)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 300)

    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    fs:SetFont(SP_NOTIFY_FONT, 16, "SOFTOUTLINE")
    fs:SetText(text)

    UIFrameFadeIn(fs, 0.2, 0, 1)
    f:Show()

    C_Timer.After(2, function()
        UIFrameFadeOut(fs, 1.5, 1, 0)
        C_Timer.After(1.6, function()
            f:Hide()
            if SP._notifFrame == f then SP._notifFrame = nil end
        end)
    end)

    SP._notifFrame = f
end

-- ============================================================
-- SP.CreateReloadPrompt(reason)
-- Shows a themed two-button dialog asking the player to reload.
-- Usage: SP.CreateReloadPrompt("Disabling X requires a reload.")

-- ============================================================
local SP_RELOAD_DIALOG = "SP_RELOAD_PROMPT"
local _reloadDialogCreated = false

function SP.CreateReloadPrompt(reason)
    if not _reloadDialogCreated then
        _reloadDialogCreated = true
        StaticPopupDialogs[SP_RELOAD_DIALOG] = {
            text          = reason or "A UI reload is required for this change to take effect.",
            button1       = "Reload Now",
            button2       = "Later",
            OnAccept      = function() ReloadUI() end,
            timeout       = 0,
            whileDead     = true,
            hideOnEscape  = true,
            preferredIndex = 4,
        }
    else
        -- Update the text in case it differs from a prior call
        StaticPopupDialogs[SP_RELOAD_DIALOG].text = reason
            or "A UI reload is required for this change to take effect."
    end
    StaticPopup_Show(SP_RELOAD_DIALOG)
end

-- Slash command handler
-- "/spack" → toggle the Settings GUI
-- Loads the options UI on demand.
--
-- The options UI is 39 files -- a widget layer, a layout engine, a window shell
-- and one file per page -- and nothing needs any of it until the user actually
-- opens the window, so it lives in a LoadOnDemand companion addon and is kept
-- off the login path entirely.
--
-- Returns true once SP.GUI exists. Safe to call repeatedly: LoadAddOn is a
-- no-op on an already-loaded addon.
function SP.EnsureGUI()
    if SP.GUI then return true end

    local load = (C_AddOns and C_AddOns.LoadAddOn) or _G.LoadAddOn
    if not load then return false end

    local ok, reason = load("SuspicionsPack_Config")
    if not ok then
        print("|cffff4444[SuspicionsPack]|r Could not load the options UI ("
              .. tostring(reason) .. "). Make sure \"SuspicionsPack Options\" "
              .. "is enabled in the AddOns list.")
        return false
    end
    if not SP.GUI then
        -- LoadAddOn reported success but nothing defined SP.GUI: a Lua error in
        -- one of the 39 files, or an incomplete install (a truncated file has
        -- shipped before). Without this the button silently does nothing forever
        -- and re-calls LoadAddOn on every click.
        print("|cffff4444[SuspicionsPack]|r The options UI loaded but failed to "
              .. "initialise. Check your Lua error frame and reinstall the "
              .. "options addon.")
        return false
    end
    return true
end

-- Prints where you are standing, with the IDs the auto-release list matches on.
--
-- The options page has a card that shows the same thing with an Add button, and
-- that is the one to use normally. This exists for the case the card cannot
-- cover: you are in a raid, in front of the boss, and opening a settings window
-- over the encounter to read one number is not going to happen.
function SP.PrintZoneInfo()
    local mod = SP.AutoRelease
    if not (mod and mod.Describe) then
        print("SuspicionsPack: the auto-release module is not loaded.")
        return
    end
    local h  = mod.Describe()
    local ac = SP.Theme and SP.Theme.accent or { 1, 0, 0 }
    local hex = string.format("|cff%02X%02X%02X",
        math.floor(ac[1] * 255 + 0.5), math.floor(ac[2] * 255 + 0.5), math.floor(ac[3] * 255 + 0.5))
    print(hex .. "SuspicionsPack|r zone:")
    print(("  zone       |cffffffff%s|r"):format(h.zone ~= "" and h.zone or "-"))
    print(("  subzone    |cffffffff%s|r"):format(h.subZone ~= "" and h.subZone or "-"))
    print(("  instanceID |cffffffff%s|r   uiMapID |cffffffff%s|r   type |cffffffff%s|r")
        :format(tostring(h.instanceID), tostring(h.uiMapID), h.instanceType))
end

function SP:ToggleGUI(input)
    local arg = (input or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    -- Both spellings: `debug zoneid` reads well, `zoneid` is what you actually
    -- type when you are dead on the floor and the pull is resetting.
    if arg == "debug zoneid" or arg == "zoneid" or arg == "zone" then
        SP.PrintZoneInfo()
        return
    end
    if arg == "debug trail" or arg == "trail" then
        if SP.Cursor and SP.Cursor.DebugTrail then SP.Cursor.DebugTrail()
        else print("SuspicionsPack: the cursor module is not loaded.") end
        return
    end
    if not SP.EnsureGUI() then return end
    SP.GUI.Toggle()
end

-- ============================================================
-- Changelog data — add a new entry for each version.
-- Entries are shown newest-first in the popup.
-- ============================================================
SP.Changelog = {
    ["2.4.0"] = {
        { type = "fix", text = "The cursor trail no longer thins out when your frame rate drops. Copies are laid along the path travelled instead of one per frame, so alt-tabbing no longer wrecks it." },
        { type = "fix", text = "The trail is a soft dot by default instead of the cursor ring, which was all but invisible once it shrank and faded." },
        { type = "new", text = "Trail spacing is yours to set: tight for a solid smear, wide for a light trail." },
        { type = "new", text = "Trail shape: dot, circle or ring." },
        { type = "fix", text = "Switches and their labels sit on the same line again. Every control was a few pixels low against its own text." },
    },
    ["2.3.0"] = {
        { type = "new", text = "The cursor circle can leave a trail behind it: shape, length, size, fade time and opacity." },
        { type = "new", text = "Separate cursor opacity in and out of combat. Dungeons and raids count as combat throughout, so it holds steady between pulls instead of flicking on every one." },
        { type = "new", text = "/spack debug trail reports what the trail is doing, for when it is not doing it." },
    },
    ["2.2.0"] = {
        { type = "new", text = "Release and rez: a new page for what happens when you die." },
        { type = "new", text = "Resurrections can be accepted for you. Battle rezzes are left alone, so mid-fight you still pick your own moment." },
        { type = "new", text = "Your spirit can be released automatically in battlegrounds and arenas, and on the raid bosses you add to a list." },
        { type = "new", text = "The page reads the spot you are standing on and adds it to that list in one click. /spack debug zoneid prints the same thing without opening the window." },
        { type = "new", text = "The micro menu has an opacity slider, and can go back to full opacity while the cursor is over it." },
        { type = "new", text = "The micro menu can be wrapped onto several rows: set how many icons you want per row." },
        { type = "new", text = "Pages are listed alphabetically inside each sidebar category." },
        { type = "fix", text = "Switching a module on or off announces itself on screen again." },
    },
    ["2.1.1"] = {
        { type = "new", text = "The options window has been rebuilt from scratch: rounded panels, a quieter palette, and visible card edges." },
        { type = "new", text = "You can now search across every setting, not just the page names." },
        { type = "new", text = "Each setting is one line now: its name and a short explanation on the left, its control on the right." },
        { type = "new", text = "The footer counts how many settings you have changed on a page, and Reset page puts them all back." },
        { type = "new", text = "Dots in the sidebar show at a glance which modules are switched on." },
        { type = "new", text = "Every page opens with the module's name, what it does, and its on/off switch." },
        { type = "new", text = "The window remembers its position and size between sessions." },
        { type = "new", text = "Long dropdown lists have a scrollbar now, and open on the value you already have rather than at the top." },
        { type = "fix", text = "Settings now update on screen after a profile import or a colour reset, instead of showing old values until you close and reopen the window." },
        { type = "fix", text = "Switching a module on or off announces itself on screen again, as it did before the rebuild." },
        { type = "fix", text = "Greyed-out buttons, anchor grids and item rows no longer respond to clicks." },
        { type = "fix", text = "Auto Buy: 15 of the 25 preset items were stored under the wrong item ID and could never be read." },
        { type = "fix", text = "Reap Predict settings were silently discarded when you imported a profile." },
        { type = "fix", text = "Copy Anything and Auto Buy wrote to your saved settings just from having their page opened." },
        { type = "fix", text = "Micro Menu Skin's master switch left its 13 sub-settings active, and Death Alert's re-enabled the speech rows its own switch had just turned off." },
        { type = "fix", text = "Enhanced Objective Text's Preview ran while the module was off and left Blizzard's error frame resized." },
        { type = "fix", text = "Repair Warning, Combat Timer, Gateway Alert, Bloodlust Alert, Movement Alert, Combat Cross and Cursor settings can now be reset, and survive a profile import." },
        { type = "fix", text = "This what's-new window used to show an empty box on a fresh release, and only ever listed one version." },
    },
    ["2.0.0"] = {
        { type = "new", text = "Full architecture rebuild. Every module was rewritten onto a shared foundation." },
        { type = "new", text = "A module you turn off now costs nothing at all \226\128\148 it registers no events and runs no code." },
        { type = "new", text = "Animations and timers stop completely when idle instead of running all session." },
        { type = "new", text = "The options window is loaded only when you open it: 43% less code read at login." },
        { type = "new", text = "Your settings are migrated and cleaned up on upgrade." },
        { type = "fix", text = "Dozens of fixes across the pack, including settings that only applied after a /reload." },
    },
    ["1.13.1"] = {
        { type = "fix", text = "Focus Target Marker no longer announces your kick marker on healer specs \226\128\148 except Restoration Shaman. The macro still works on every spec." },
    },
    ["1.13.0"] = {
        { type = "new", text = "All 30 modules now share one enable/disable contract \226\128\148 a module you turn off registers nothing at login." },
        { type = "fix", text = "TankMD now works as soon as you enable it, without a /reload." },
        { type = "fix", text = "FastLoot no longer hijacks your Blizzard auto-loot setting, and restores it when disabled." },
        { type = "fix", text = "CVars are restored to your own values when the module is disabled." },
    },
    ["1.12.0"] = {
        { type = "fix", text = "Automation: the master toggle now actually turns everything off \226\128\148 seven features kept running when it was off." },
        { type = "fix", text = "Auto role check no longer keeps accepting after you switch it off." },
        { type = "fix", text = "MovementAlert and Automation now clean up properly when disabled." },
    },
    ["1.11.1"] = {
        { type = "fix", text = "ReapPredict: the 100 fury tick was misplaced while snapped to an external bar." },
    },
    ["1.11.0"] = {
        { type = "new", text = "The options UI is now a load-on-demand companion addon: 43% less code parsed at login." },
        { type = "new", text = "Saved variables are migrated and pruned on upgrade \226\128\148 dead settings from removed modules are cleaned out." },
        { type = "fix", text = "Profile import no longer re-injects settings from deleted features." },
    },
    ["1.10.0"] = {
        { type = "new", text = "Shared ticker: per-frame loops now stop entirely when idle." },
        { type = "fix", text = "CombatTimer no longer runs a per-frame loop out of combat." },
        { type = "fix", text = "MovementAlert no longer scans cooldowns 10x/second with nothing on screen." },
        { type = "fix", text = "ReapPredict: the 10 Hz meter poll costs no per-frame Lua any more." },
    },
    ["1.9.4"] = {
        { type = "fix", text = "Fonts: assets removed by Blizzard (Nimrod) no longer break an options page \226\128\148 they are validated and filtered out of the dropdown." },
    },
    ["1.9.3"] = {
        { type = "fix", text = "GUI: option pages could stack on top of each other. A failing page is now cached before it builds, so it can always be hidden." },
        { type = "fix", text = "Focus Target Marker: a saved marker outside 1-8 aborted the page." },
    },
    ["1.9.2"] = {
        { type = "fix",  text = "ReapPredict: 8 raw unit events (UNIT_AURA, UNIT_POWER_FREQUENT) no longer registered for non-Devourer characters." },
        { type = "fix",  text = "SpellEffectAlpha / Performance: no longer overwrite your Blizzard CVars at login while disabled." },
        { type = "fix",  text = "Fonts: LibSharedMedia fonts now resolve in every module (six private tables were shadowing the resolver)." },
        { type = "fix",  text = "Removed ~130 lines of dead code." },
    },
    ["1.9.1"] = {
        { type = "fix", text = "GUI: 21 settings only applied after a /reload (Refresh called without self)." },
        { type = "fix", text = "Taint: issecretvalue guards added in CombatCross, MovementAlert, ReapPredict, BloodlustAlert, PotionAlert." },
        { type = "fix", text = "Performance: the quest watch sweep no longer freezes the client (spread over frames)." },
        { type = "fix", text = "AutoBuy: vendor purchases were broken (wrong API return) and could hang in a loop." },
        { type = "fix", text = "PotionAlert: the alert showed permanently when you did not carry the potion." },
        { type = "fix", text = "CombatCross: range fixed for Vengeance, Guardian and Protection Paladin." },
        { type = "fix", text = "SilvermoonMapIcon: professions were partly ignored (iteration over a table with holes)." },
        { type = "fix", text = "CraftShopper: cancelling an AH purchase could throw a Lua error." },
    },
    ["1.9.0"] = {
        { type = "new", text = "Micro Menu Skin: new module \226\128\148 flat reskin of the micro menu, with adjustable size and spacing." },
    },
    ["1.8.15"] = {
        { type = "fix", text = "ReapPredict: reverted to the native bar interpolation \226\128\148 no more gaps." },
    },
    ["1.8.14"] = {
        { type = "fix", text = "ReapPredict: fixed a taint error in the bar smoothing." },
    },
    ["1.8.13"] = {
        { type = "fix", text = "ReapPredict: fixed a compatibility issue in the bar smoothing." },
    },
    ["1.8.12"] = {
        { type = "fix", text = "ReapPredict: Match Ellesmere width button added to the Fury Bar too." },
    },
    ["1.8.11"] = {
        { type = "new", text = "ReapPredict: smooth bar fill, plus a Match Ellesmere width button." },
    },
    ["1.8.10"] = {
        { type = "fix", text = "BloodlustAlert: fixed a truncated file from an earlier merge." },
    },
    ["1.8.9"] = {
        { type = "fix", text = "BloodlustAlert: the OIIA Psytrance sound was missing from the v1.8.8 zip." },
    },
    ["1.8.8"] = {
        { type = "new", text = "pull request de valdum (ntm)" },
    },
    ["1.8.7"] = {
        { type = "fix", text = "PotionAlert: migrated to C_Item.GetItemCooldown API." },
        { type = "fix", text = "PotionAlert: added CHALLENGE_MODE_START and ENCOUNTER_END detection." },
        { type = "fix", text = "PotionAlert: skip redundant BAG_UPDATE_COOLDOWN checks while potion is on cooldown." },
    },
    ["1.8.4"] = {
        { type = "change", text = "Code cleanup across all modules." },
        { type = "fix",    text = "PotionAlert: fixed module not triggering correctly." },
    },
    ["1.8.3"] = {
        { type = "fix", text = "Hotfix: corrected corrupted files from v1.8.1 release (GUI.lua truncated, MovementAlert/Durability/ReapPredict ended with null bytes). TROLLEG" },
    },
    ["1.8.1"] = {
        { type = "fix", text = "Hotfix: corrected truncated Core.lua from v1.8.0 release." },
    },
    ["1.8.0"] = {
        { type = "new", text = "PotionAlert: new module — shows a configurable text alert when your combat potion comes off cooldown (Tempered Potion, Draught of Rampant Abandon, Light's Potential, Potion of Recklessness). Active in M+ and raids only." },
        { type = "new", text = "PetStatus: new module — displays PET MISSING / PET DEAD / PET PASSIVE text alert for Hunter, Warlock, and Unholy DK." },
    },
    ["1.7.3"] = {
        { type = "fix",    text = "MovementAlert: guard isOnGCD comparisons with issecretvalue to fix taint error crashing Blizzard_CooldownViewer" },
        { type = "fix",    text = "GUI: add AnimateBorderFocus focus animation to all remaining EditBox widgets (Durability, Auto Invite, Death Alert, Craft Shopper)" },
        { type = "fix",    text = "GUI: Silvermoon Map Icons — Filter card now grays out when module is disabled" },
        { type = "change", text = "GUI: unify all animation durations to 0.18s (border hover, dropdown arrows, sidebar expand)" },
        { type = "change", text = "GUI: BuildColorPickerInfo now supports optional alpha channel — passes hasOpacity to WoW's color picker" },
        { type = "remove", text = "GUI: remove unused CreateNativeSlider dead code" },
    },
    ["1.7.0"] = {
        { type = "new", text = "Auto Combat Log: rewrote detection — per-instance memory, ACL prompt, M+ support via CHALLENGE_MODE_START. Your choice is saved per dungeon/difficulty and never asked twice." },
    },
    ["1.6.9"] = {
        { type = "fix", text = "BloodlustAlert: rewrote detection from haste-spike (broken in 12.0.5) to UNIT_AURA debuff tracking (Sated / Exhaustion / Temporal Displacement)." },
    },
    ["1.6.8"] = {
        { type = "new", text = "For better FPS, set audio channel count on login to 32 or higher and prevent BigWigs/Nsky/Dbm to put it back to 64/128." },
        { type = "fix", text = "Sound Channels: applies on /reload, notification on toggle, description text no longer overflows card." },
    },
    ["1.6.7"] = {
        { type = "fix", text = "Performance page no longer crashes when opening (dropdown {key,label} table bug)." },
    },
    ["1.6.6"] = {
        { type = "new", text = "For better FPS, set audio channel count on login to 32 or higher and prevent BigWigs/Nsky/Dbm to put it back to 64/128." },
    },
    ["1.6.5"] = {
        { type = "change", text = "Bump TOC to 12.0.5 patch version" },
    },
    ["1.6.4"] = {
        { type = "new", text = "Theme button added to GUI footer (opens Themes page directly)" },
        { type = "fix", text = "ESC key now properly closes the GUI" },
    },
    ["1.6.3"] = {
        { type = "new", text = "Changelog button added to GUI footer (next to Preview All)" },
        { type = "fix", text = "DeathAlert: group member deaths no longer missed (Blizzard UnitTokenFromGUID regression in 12.x)" },
    },
    ["1.6.0"] = {
        { type = "new",    text = "6 new color themes: Catppuccin, Rose Pine, Tokyo Night, Nord, Dracula, Gruvbox" },
        { type = "remove", text = "Removed AutoPI and AutoInnervate modules" },
        { type = "fix",    text = "Various bug fixes" },
    },
}

-- ============================================================
-- SP.ShowChangelogPopup()
-- Displays a themed popup listing every release, newest first.
-- Called automatically on login when the version has changed.
--
-- TAG_COLOR / TAG_LABEL cover all four entry types SP.Changelog uses. They are
-- immediately above the function on purpose: tests/test_gui.lua slices this
-- region out of the file verbatim and runs it, so anything the popup reads must
-- live inside the slice.
-- ============================================================
local TAG_COLOR = {
    new    = { 0.20, 0.85, 0.45 },
    fix    = { 0.40, 0.70, 1.00 },
    remove = { 1.00, 0.45, 0.35 },
    change = { 1.00, 0.80, 0.20 },
}
local TAG_LABEL = {
    new    = "NEW",
    fix    = "FIX",
    remove = "REMOVE",
    change = "CHANGE",
}

function SP.ShowChangelogPopup()
    if SP._changelogFrame then SP._changelogFrame:Show(); return end

    local T    = SP.Theme
    local Skin = SP.Skin
    -- Core\Skin.lua is second in the toc, so this is satisfied today. It is
    -- guarded anyway because the failure is a hard error three seconds after
    -- login, on a timer, with no recovery: reordering the toc or shipping a
    -- Skin.lua that fails to parse would break the client's UI rather than
    -- merely skipping a popup nobody asked for.
    if not (Skin and Skin.Round) then return end
    local W, H = 520, 470
    local PAD  = 16

    -- Every version, newest first. The old popup looked up SP.Changelog[VERSION]
    -- and showed nothing at all when the running version had no entry -- which is
    -- exactly what a fresh release looks like before its notes are written. It
    -- also hid the other 34 releases, which were sitting in the table unread.
    local versions = {}
    for v in pairs(SP.Changelog) do versions[#versions + 1] = v end
    local function Parts(v)
        local a, b, c = v:match("^(%d+)%.(%d+)%.(%d+)$")
        return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
    end
    table.sort(versions, function(x, y)
        local x1, x2, x3 = Parts(x)
        local y1, y2, y3 = Parts(y)
        if x1 ~= y1 then return x1 > y1 end
        if x2 ~= y2 then return x2 > y2 end
        return x3 > y3
    end)

    local function Font(fs, size)
        fs:SetFont(SP.ResolveFont("Expressway"), size, "")
        fs:SetShadowColor(0, 0, 0, 0.9)
        fs:SetShadowOffset(1, -1)
    end

    -- ---- frame ----
    local f = CreateFrame("Frame", "SP_ChangelogPopup", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(20)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)
    local bg, br = Skin.Round(f, "rr10")
    bg:SetVertexColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 1)
    br:SetVertexColor(T.border[1], T.border[2], T.border[3], 1)

    -- ---- header ----
    local HEAD = 44
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(26, 26)
    logo:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -9)
    logo:SetTexture("Interface\\AddOns\\SuspicionsPack\\Media\\Icons\\icon128x128.png")
    logo:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
    logo:SetTexelSnappingBias(0)
    logo:SetSnapToPixelGrid(false)

    local title = f:CreateFontString(nil, "OVERLAY")
    Font(title, 14)
    title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    title:SetText("What's new")
    title:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -10)
    local xTex = close:CreateTexture(nil, "ARTWORK")
    xTex:SetSize(13, 13)
    xTex:SetPoint("CENTER")
    xTex:SetTexture("Interface\\AddOns\\SuspicionsPack\\Media\\GUITextures\\close.png")
    xTex:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
    close:SetScript("OnEnter", function() xTex:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1) end)
    close:SetScript("OnLeave", function() xTex:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1) end)
    close:SetScript("OnClick", function() f:Hide() end)

    local ver = f:CreateFontString(nil, "OVERLAY")
    Font(ver, 11)
    ver:SetPoint("RIGHT", close, "LEFT", -6, 0)
    ver:SetText("v" .. (SP.VERSION or "?"))
    ver:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    local headRule = f:CreateTexture(nil, "ARTWORK")
    headRule:SetHeight(1)
    headRule:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -HEAD)
    headRule:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEAD)
    headRule:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)

    -- ---- footer ----
    local FOOT = 46
    local footRule = f:CreateTexture(nil, "ARTWORK")
    footRule:SetHeight(1)
    footRule:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, FOOT)
    footRule:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, FOOT)
    footRule:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)

    local count = f:CreateFontString(nil, "OVERLAY")
    Font(count, 11)
    count:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, 18)
    count:SetText(#versions .. (#versions == 1 and " release" or " releases"))
    count:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    local okBtn = CreateFrame("Button", nil, f)
    okBtn:SetSize(96, 24)
    okBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, 12)
    local obg, obr = Skin.Round(okBtn, "rr4")
    obg:SetVertexColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    obr:SetVertexColor(T.border[1], T.border[2], T.border[3], 1)
    local okLbl = okBtn:CreateFontString(nil, "OVERLAY")
    Font(okLbl, 12)
    okLbl:SetAllPoints()
    okLbl:SetText("Got it")
    okLbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
    okBtn:SetScript("OnEnter", function() obr:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1) end)
    okBtn:SetScript("OnLeave", function() obr:SetVertexColor(T.border[1], T.border[2], T.border[3], 1) end)
    okBtn:SetScript("OnClick", function() f:Hide() end)

    -- ---- scrolling body ----
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT",     f, "TOPLEFT",      PAD, -(HEAD + 4))
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PAD + 6), FOOT + 6)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetWidth(W - PAD * 2 - 6)
    body:SetHeight(1)
    scroll:SetScrollChild(body)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(s, d)
        local range = s:GetVerticalScrollRange() or 0
        local v = s:GetVerticalScroll() - d * 40
        if v < 0 then v = 0 elseif v > range then v = range end
        s:SetVerticalScroll(v)
    end)

    -- Newest version in accent, the rest muted: the eye needs to land on what
    -- changed just now, not on the whole history at equal weight.
    -- 46px, not 34: the column has to hold "REMOVE" and "CHANGE" on one line.
    local BADGE_W, y = 46, 4
    for i, v in ipairs(versions) do
        local head = body:CreateFontString(nil, "OVERLAY")
        Font(head, 13)
        head:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
        head:SetText(v)
        if i == 1 then head:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        else head:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1) end

        local rule = body:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        rule:SetPoint("LEFT",  head, "RIGHT", 10, 0)
        rule:SetPoint("RIGHT", body, "RIGHT", 0, 0)
        rule:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
        y = y + 22

        for _, e in ipairs(SP.Changelog[v]) do
            -- Four entry types ship in SP.Changelog, not two. Collapsing them to
            -- new/fix put a FIX badge on "Removed AutoPI and AutoInnervate
            -- modules". TAG_LABEL / TAG_COLOR carry all four; anything with an
            -- unrecognised type falls back to FIX rather than rendering blank.
            local tag = TAG_LABEL[e.type] and e.type or "fix"
            local col = TAG_COLOR[tag]
            local badge = body:CreateFontString(nil, "OVERLAY")
            Font(badge, 9)
            badge:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(y + 2))
            badge:SetWidth(BADGE_W)
            badge:SetJustifyH("CENTER")
            badge:SetWordWrap(false)
            badge:SetText(TAG_LABEL[tag])
            badge:SetTextColor(col[1], col[2], col[3], 1)

            local txt = body:CreateFontString(nil, "OVERLAY")
            Font(txt, 12)
            txt:SetPoint("TOPLEFT",  body, "TOPLEFT", BADGE_W + 10, -y)
            txt:SetPoint("RIGHT",    body, "RIGHT", 0, 0)
            txt:SetJustifyH("LEFT")
            txt:SetWordWrap(true)
            txt:SetText(e.text)
            txt:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

            -- Wrapped text only reports its height once it has a width, which it
            -- has here because the body's width is explicit.
            y = y + math.max(18, math.ceil(txt:GetStringHeight()) + 6)
        end
        y = y + 10
    end
    body:SetHeight(math.max(1, y))

    -- ESC closes it. Guarded: this function can only build once, but the guard
    -- costs nothing and a duplicate entry in UISpecialFrames is forever.
    if not SP._changelogEsc then
        tinsert(UISpecialFrames, "SP_ChangelogPopup")
        SP._changelogEsc = true
    end

    SP._changelogFrame = f
    f:Show()
end

-- ============================================================
-- Preview Manager
-- Automatically shows all enabled positioned-frame modules in
-- preview mode while the SP GUI is open, and hides them on close.
-- ============================================================
local PreviewManager = {}
SP.PreviewManager = PreviewManager

-- { mod = key on SP global, dbKey = key in GetDB(), show/hide = method names }
local PREVIEW_MODULES = {
    { mod = "Durability",     dbKey = "durability",     show = "ShowPreview",      hide = "HidePreview"      },
    { mod = "CombatTimer",    dbKey = "combatTimer",    show = "ShowPreview",      hide = "HidePreview"      },
    { mod = "MovementAlert",  dbKey = "movementAlert",  show = "ShowPreview",      hide = "HidePreview"      },
    { mod = "GatewayAlert",   dbKey = "gatewayAlert",   show = "ShowPreview",      hide = "HidePreview"      },
    { mod = "CombatCross",    dbKey = "combatCross",    show = "ShowPreview",      hide = "HidePreview"      },
    { mod = "PotionAlert",    dbKey = "potionAlert",    show = "ShowPreview",      hide = "HidePreview"      },
    -- BloodlustAlert exposes the timer frame via its own preview methods
    { mod = "BloodlustAlert", dbKey = "bloodlustAlert", dbSubKey = "timerEnabled", show = "ShowTimerPreview", hide = "HideTimerPreview" },
}

PreviewManager.active = false

function PreviewManager:Start()
    if self.active then return end
    self.active = true
    local db = SP.GetDB()
    if not db then return end
    for _, entry in ipairs(PREVIEW_MODULES) do
        local mod = SP[entry.mod]
        if mod then
            local mdb = db[entry.dbKey]
            if mdb then
                -- dbSubKey entries use ~=false so that nil (not yet set) counts as enabled,
                -- while an explicit false (user disabled) suppresses the preview.
                -- Explicit branch, not `a and b or c`: when the middle term is
                -- false that idiom falls through to `or mdb.enabled` and
                -- returns true, which is the opposite of what the comment above
                -- describes (a disabled sub-feature still previewed).
                local enabled
                if entry.dbSubKey then
                    enabled = mdb.enabled and mdb[entry.dbSubKey] ~= false
                else
                    enabled = mdb.enabled
                end
                if enabled and mod[entry.show] then
                    mod[entry.show](mod)
                end
            end
        end
    end
end

function PreviewManager:Stop()
    if not self.active then return end
    self.active = false
    for _, entry in ipairs(PREVIEW_MODULES) do
        local mod = SP[entry.mod]
        if mod and mod[entry.hide] then
            mod[entry.hide](mod)
        end
    end
end

-- ============================================================
-- SP.CheckChangelog()
-- Called on PLAYER_LOGIN. Shows the popup once per version.
-- ============================================================
function SP.CheckChangelog()
    local db = SP.GetDB()
    if not db or not db.settings then return end
    if db.settings.lastSeenVersion == SP.VERSION then return end
    -- No SP.Changelog[SP.VERSION] check. The popup lists EVERY release, so it
    -- has something to show whatever the running version is -- and gating on
    -- "does this exact version have notes" made the popup unreachable on every
    -- release whose notes lag the toc bump, which is how 2.1.1 shipped with a
    -- popup that could never appear. lastSeenVersion above is the real gate.

    db.settings.lastSeenVersion = SP.VERSION

    -- Small delay so the UI is fully loaded before we show the popup
    C_Timer.After(3, function()
        SP.ShowChangelogPopup()
    end)
end
