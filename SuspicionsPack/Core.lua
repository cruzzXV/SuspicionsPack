local ADDON_NAME, NS = ...

-- ============================================================
-- Create the addon object via AceAddon-3.0
-- Mixins: AceEvent-3.0 (global events), AceConsole-3.0 (chat commands)
-- ============================================================
local SP = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")
_G.SuspicionsPack = SP
NS.SP = SP

SP.VERSION = "1.6.1"
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
local _fontListCache = nil

function SP.GetFontList()
    if _fontListCache then return _fontListCache end
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    local names = {}
    if lsm then
        for name in pairs(lsm:HashTable("font")) do
            names[#names + 1] = name
        end
        table.sort(names)
    end
    if #names == 0 then
        names = { "Arial Narrow", "Expressway", "Friz Quadrata TT", "Morpheus", "Skurri" }
    end
    _fontListCache = names
    return names
end

function SP.GetFontPath(name)
    if not name then return nil end
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    if lsm then
        return lsm:Fetch("font", name)
    end
    return nil
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

-- ============================================================
-- Colors (base palette used by Drawer module only — GUI uses SP.Theme)
-- ============================================================
SP.C = {
    SUBTEXT = { 0.6, 0.6, 0.6, 1 },
}

-- ============================================================
-- Theme presets — same as NorskenUI (AddonTheme.lua)
-- ============================================================
SP.ThemePresets = {
    ["Suspicion"] = {
        bgDark        = { 0.0235, 0.0235, 0.0235, 0.97 },
        bgMedium      = { 0.0431, 0.0431, 0.0431, 1    },
        bgLight       = { 0.1176, 0.1176, 0.1176, 1    },
        bgHover       = { 0.22,   0.22,   0.24,   1    },
        border        = { 0,      0,      0,      1    },
        accent        = { 0.8980, 0.0627, 0.2235, 1    },
        accentHover   = { 0.8980, 0.0627, 0.2235, 0.25 },
        accentDim     = { 0.8980, 0.0627, 0.2235, 1    },
        textPrimary   = { 0.95,   0.95,   0.95,   1    },
        textSecondary = { 0.70,   0.70,   0.70,   1    },
        textMuted     = { 0.50,   0.50,   0.50,   1    },
        selectedBg    = { 0.8980, 0.0627, 0.2235, 0.25 },
        selectedText  = { 0.8980, 0.0627, 0.2235, 1    },
        error         = { 0.90,   0.30,   0.30,   1    },
        success       = { 0.30,   0.80,   0.40,   1    },
        warning       = { 0.90,   0.75,   0.30,   1    },
    },
    ["Warpaint"] = {
        bgDark        = { 0.0745, 0.0588, 0.0510, 0.97 },
        bgMedium      = { 0.0745, 0.0588, 0.0510, 1    },
        bgLight       = { 0.1176, 0.1176, 0.1176, 1    },
        bgHover       = { 0.22,   0.22,   0.24,   1    },
        border        = { 0,      0,      0,      1    },
        accent        = { 0.7098, 0.2000, 0.1412, 1    },
        accentHover   = { 0.7098, 0.2000, 0.1412, 0.25 },
        accentDim     = { 0.7098, 0.2000, 0.1412, 1    },
        textPrimary   = { 0.95,   0.95,   0.95,   1    },
        textSecondary = { 0.70,   0.70,   0.70,   1    },
        textMuted     = { 0.50,   0.50,   0.50,   1    },
        selectedBg    = { 0.7098, 0.2000, 0.1412, 0.25 },
        selectedText  = { 0.7098, 0.2000, 0.1412, 1    },
        error         = { 0.90,   0.30,   0.30,   1    },
        success       = { 0.30,   0.80,   0.40,   1    },
        warning       = { 0.90,   0.75,   0.30,   1    },
    },
    ["Greenwake"] = {
        bgDark        = { 0.031, 0.106, 0.106, 0.97 },
        bgMedium      = { 0.031, 0.106, 0.106, 1    },
        bgLight       = { 0.125, 0.231, 0.216, 1    },
        bgHover       = { 0.22,  0.22,  0.24,  1    },
        border        = { 0,     0,     0,     1    },
        accent        = { 0.933, 0.910, 0.698, 1    },
        accentHover   = { 0.933, 0.910, 0.698, 0.25 },
        accentDim     = { 0.933, 0.910, 0.698, 1    },
        textPrimary   = { 0.95,  0.95,  0.95,  1    },
        textSecondary = { 0.70,  0.70,  0.70,  1    },
        textMuted     = { 0.50,  0.50,  0.50,  1    },
        selectedBg    = { 0.933, 0.910, 0.698, 0.25 },
        selectedText  = { 0.933, 0.910, 0.698, 1    },
        error         = { 0.90,  0.30,  0.30,  1    },
        success       = { 0.30,  0.80,  0.40,  1    },
        warning       = { 0.90,  0.75,  0.30,  1    },
    },
    ["Timberfall"] = {
        bgDark        = { 0.092, 0.069, 0.018, 0.97 },
        bgMedium      = { 0.092, 0.069, 0.018, 1    },
        bgLight       = { 0.1176, 0.1176, 0.1176, 1    },
        bgHover       = { 0.22,  0.22,  0.24,  1    },
        border        = { 0,     0,     0,     1    },
        accent        = { 0.988, 0.361, 0.008, 1    },
        accentHover   = { 0.988, 0.361, 0.008, 0.25 },
        accentDim     = { 0.988, 0.361, 0.008, 1    },
        textPrimary   = { 0.95,  0.95,  0.95,  1    },
        textSecondary = { 0.70,  0.70,  0.70,  1    },
        textMuted     = { 0.50,  0.50,  0.50,  1    },
        selectedBg    = { 0.988, 0.361, 0.008, 0.25 },
        selectedText  = { 0.988, 0.361, 0.008, 1    },
        error         = { 0.90,  0.30,  0.30,  1    },
        success       = { 0.30,  0.80,  0.40,  1    },
        warning       = { 0.90,  0.75,  0.30,  1    },
    },
    ["Obsidian"] = {
        bgDark        = { 0.014, 0.047, 0.063, 0.97 },
        bgMedium      = { 0.014, 0.047, 0.063, 1    },
        bgLight       = { 0.114, 0.147, 0.163, 1    },
        bgHover       = { 0.22,  0.22,  0.24,  1    },
        border        = { 0,     0,     0,     1    },
        accent        = { 0.900, 0.467, 0.976, 1    },
        accentHover   = { 0.900, 0.467, 0.976, 0.25 },
        accentDim     = { 0.900, 0.467, 0.976, 1    },
        textPrimary   = { 0.95,  0.95,  0.95,  1    },
        textSecondary = { 0.70,  0.70,  0.70,  1    },
        textMuted     = { 0.50,  0.50,  0.50,  1    },
        selectedBg    = { 0.900, 0.467, 0.976, 0.15 },
        selectedText  = { 0.900, 0.467, 0.976, 1    },
        error         = { 0.90,  0.30,  0.30,  1    },
        success       = { 0.30,  0.80,  0.40,  1    },
        warning       = { 0.90,  0.75,  0.30,  1    },
    },
    ["Blorb"] = {
        bgDark        = { 0.0588, 0.0559, 0.0294, 0.97 },
        bgMedium      = { 0.0588, 0.0559, 0.0294, 1    },
        bgLight       = { 0.1019, 0.0969, 0.0510, 1    },
        bgHover       = { 0.22,   0.22,   0.24,   1    },
        border        = { 0,      0,      0,      1    },
        accent        = { 0.7451, 0.9412, 0.0000, 1    },
        accentHover   = { 0.7451, 0.9412, 0.0000, 0.25 },
        accentDim     = { 0.7451, 0.9412, 0.0000, 1    },
        textPrimary   = { 0.95,   0.95,   0.95,   1    },
        textSecondary = { 0.70,   0.70,   0.70,   1    },
        textMuted     = { 0.50,   0.50,   0.50,   1    },
        selectedBg    = { 0.7451, 0.9412, 0.0000, 0.25 },
        selectedText  = { 0.7451, 0.9412, 0.0000, 1    },
        error         = { 0.90,   0.30,   0.30,   1    },
        success       = { 0.30,   0.80,   0.40,   1    },
        warning       = { 0.90,   0.75,   0.30,   1    },
    },
    ["Frost"] = {
        bgDark        = { 0.024, 0.078, 0.106, 0.97 },
        bgMedium      = { 0.024, 0.078, 0.106, 1    },
        bgLight       = { 0.067, 0.129, 0.176, 1    },
        bgHover       = { 0.22,  0.22,  0.24,  1    },
        border        = { 0,     0,     0,     1    },
        accent        = { 0.790, 0.857, 0.872, 1    },
        accentHover   = { 0.790, 0.857, 0.872, 0.25 },
        accentDim     = { 0.790, 0.857, 0.872, 1    },
        textPrimary   = { 0.95,  0.95,  0.95,  1    },
        textSecondary = { 0.70,  0.70,  0.70,  1    },
        textMuted     = { 0.50,  0.50,  0.50,  1    },
        selectedBg    = { 0.790, 0.857, 0.872, 0.25 },
        selectedText  = { 0.790, 0.857, 0.872, 1    },
        error         = { 0.90,  0.30,  0.30,  1    },
        success       = { 0.30,  0.80,  0.40,  1    },
        warning       = { 0.90,  0.75,  0.30,  1    },
    },
    -- Catppuccin Mocha: #11111b bg / #313244 surface / #89b4fa blue accent
    ["Catppuccin"] = {
        bgDark        = { 0.067, 0.067, 0.106, 0.97 },
        bgMedium      = { 0.067, 0.067, 0.106, 1    },
        bgLight       = { 0.192, 0.196, 0.267, 1    },
        bgHover       = { 0.22,  0.22,  0.28,  1    },
        border        = { 0,     0,     0,     1    },
        accent        = { 0.537, 0.706, 0.980, 1    },
        accentHover   = { 0.537, 0.706, 0.980, 0.25 },
        accentDim     = { 0.537, 0.706, 0.980, 1    },
        textPrimary   = { 0.95,  0.95,  0.95,  1    },
        textSecondary = { 0.70,  0.70,  0.70,  1    },
        textMuted     = { 0.50,  0.50,  0.50,  1    },
        selectedBg    = { 0.537, 0.706, 0.980, 0.20 },
        selectedText  = { 0.537, 0.706, 0.980, 1    },
        error         = { 0.90,  0.30,  0.30,  1    },
        success       = { 0.30,  0.80,  0.40,  1    },
        warning       = { 0.90,  0.75,  0.30,  1    },
    },
    -- Rosé Pine: #191724 bg / #1f1d2e surface / #eb6f92 rose accent
    ["Rosé Pine"] = {
        bgDark        = { 0.098, 0.090, 0.141, 0.97 },
        bgMedium      = { 0.098, 0.090, 0.141, 1    },
        bgLight       = { 0.122, 0.114, 0.180, 1    },
        bgHover       = { 0.22,  0.20,  0.26,  1    },
        border        = { 0,     0,     0,     1    },
        accent        = { 0.922, 0.435, 0.573, 1    },
        accentHover   = { 0.922, 0.435, 0.573, 0.25 },
        accentDim     = { 0.922, 0.435, 0.573, 1    },
        textPrimary   = { 0.95,  0.95,  0.95,  1    },
        textSecondary = { 0.70,  0.70,  0.70,  1    },
        textMuted     = { 0.50,  0.50,  0.50,  1    },
        selectedBg    = { 0.922, 0.435, 0.573, 0.20 },
        selectedText  = { 0.922, 0.435, 0.573, 1    },
        error         = { 0.90,  0.30,  0.30,  1    },
        success       = { 0.30,  0.80,  0.40,  1    },
        warning       = { 0.90,  0.75,  0.30,  1    },
    },
    -- Tokyo Night: #1a1b26 bg / #24283b surface / #bb9af7 purple accent
    ["Tokyo Night"] = {
        bgDark        = { 0.102, 0.106, 0.149, 0.97 },
        bgMedium      = { 0.102, 0.106, 0.149, 1    },
        bgLight       = { 0.141, 0.157, 0.231, 1    },
        bgHover       = { 0.22,  0.22,  0.28,  1    },
        border        = { 0,     0,     0,     1    },
        accent        = { 0.733, 0.604, 0.969, 1    },
        accentHover   = { 0.733, 0.604, 0.969, 0.25 },
        accentDim     = { 0.733, 0.604, 0.969, 1    },
        textPrimary   = { 0.95,  0.95,  0.95,  1    },
        textSecondary = { 0.70,  0.70,  0.70,  1    },
        textMuted     = { 0.50,  0.50,  0.50,  1    },
        selectedBg    = { 0.733, 0.604, 0.969, 0.20 },
        selectedText  = { 0.733, 0.604, 0.969, 1    },
        error         = { 0.90,  0.30,  0.30,  1    },
        success       = { 0.30,  0.80,  0.40,  1    },
        warning       = { 0.90,  0.75,  0.30,  1    },
    },
    -- Nord: #2e3440 bg / #3b4252 surface / #88c0d0 arctic cyan accent
    ["Nord"] = {
        bgDark        = { 0.180, 0.204, 0.251, 0.97 },
        bgMedium      = { 0.180, 0.204, 0.251, 1    },
        bgLight       = { 0.231, 0.259, 0.322, 1    },
        bgHover       = { 0.27,  0.29,  0.36,  1    },
        border        = { 0,     0,     0,     1    },
        accent        = { 0.533, 0.753, 0.816, 1    },
        accentHover   = { 0.533, 0.753, 0.816, 0.25 },
        accentDim     = { 0.533, 0.753, 0.816, 1    },
        textPrimary   = { 0.95,  0.95,  0.95,  1    },
        textSecondary = { 0.70,  0.70,  0.70,  1    },
        textMuted     = { 0.50,  0.50,  0.50,  1    },
        selectedBg    = { 0.533, 0.753, 0.816, 0.20 },
        selectedText  = { 0.533, 0.753, 0.816, 1    },
        error         = { 0.90,  0.30,  0.30,  1    },
        success       = { 0.30,  0.80,  0.40,  1    },
        warning       = { 0.90,  0.75,  0.30,  1    },
    },
    -- Dracula: #282a36 bg / #44475a surface / #bd93f9 purple accent
    ["Dracula"] = {
        bgDark        = { 0.157, 0.165, 0.212, 0.97 },
        bgMedium      = { 0.157, 0.165, 0.212, 1    },
        bgLight       = { 0.267, 0.278, 0.353, 1    },
        bgHover       = { 0.30,  0.30,  0.38,  1    },
        border        = { 0,     0,     0,     1    },
        accent        = { 0.741, 0.576, 0.976, 1    },
        accentHover   = { 0.741, 0.576, 0.976, 0.25 },
        accentDim     = { 0.741, 0.576, 0.976, 1    },
        textPrimary   = { 0.95,  0.95,  0.95,  1    },
        textSecondary = { 0.70,  0.70,  0.70,  1    },
        textMuted     = { 0.50,  0.50,  0.50,  1    },
        selectedBg    = { 0.741, 0.576, 0.976, 0.20 },
        selectedText  = { 0.741, 0.576, 0.976, 1    },
        error         = { 0.90,  0.30,  0.30,  1    },
        success       = { 0.30,  0.80,  0.40,  1    },
        warning       = { 0.90,  0.75,  0.30,  1    },
    },
    -- Gruvbox: #282828 bg / #3c3836 surface / #fabd2f warm yellow accent
    ["Gruvbox"] = {
        bgDark        = { 0.157, 0.157, 0.157, 0.97 },
        bgMedium      = { 0.157, 0.157, 0.157, 1    },
        bgLight       = { 0.235, 0.220, 0.212, 1    },
        bgHover       = { 0.28,  0.26,  0.24,  1    },
        border        = { 0,     0,     0,     1    },
        accent        = { 0.980, 0.741, 0.184, 1    },
        accentHover   = { 0.980, 0.741, 0.184, 0.25 },
        accentDim     = { 0.980, 0.741, 0.184, 1    },
        textPrimary   = { 0.95,  0.95,  0.95,  1    },
        textSecondary = { 0.70,  0.70,  0.70,  1    },
        textMuted     = { 0.50,  0.50,  0.50,  1    },
        selectedBg    = { 0.980, 0.741, 0.184, 0.20 },
        selectedText  = { 0.980, 0.741, 0.184, 1    },
        error         = { 0.90,  0.30,  0.30,  1    },
        success       = { 0.30,  0.80,  0.40,  1    },
        warning       = { 0.90,  0.75,  0.30,  1    },
    },
}

SP.ThemePresetOrder = { "Suspicion", "Warpaint", "Greenwake", "Timberfall", "Obsidian", "Blorb", "Frost", "Catppuccin", "Rosé Pine", "Tokyo Night", "Nord", "Dracula", "Gruvbox" }

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

    -- Rebuild the GUI window so new colors take effect
    if SP.GUI then
        local wasOpen = SP.GUI.mainFrame and SP.GUI.mainFrame:IsShown()
        SP.GUI:Rebuild()
        if wasOpen then SP.GUI.Show() end
    end

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
            fontSize         = 18,
            outline          = "SOFTOUTLINE",
            colorInCombat    = { 1, 0.2, 0.2, 1 },
            colorOutOfCombat = { 1, 1, 1, 0.7 },
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
            enabled          = false,
            size             = 50,
            texture          = "Thick",
            colorSource      = "theme",       -- "theme" | "class" | "custom"
            cursorColor      = { 1.0, 1.0, 1.0 },
            showDot          = true,
            dotSize          = 6,
            -- Click circle (second ring, visible while mouse button held ≥ 150 ms)
            showClickCircle  = false,
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
        },
        enhancedObjectiveText = {
            enabled  = false,
            fontSize = 22,
            y        = 0,
        },
        cleanObjectiveTrackerHeader = {
            enabled = false,
        },
        tankMD = {
            enabled         = false,
            prioritizeFocus = false,
            selectionMethod = "tankRoleOnly",
        },
        focusTargetMarker = {
            enabled  = false,
            announce = true,
            marker   = 5,   -- Moon
        },
        meterReset = {
            enabled = false,
        },
        combatLog = {
            enabled     = false,
            stopOnLeave = false,
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
            fontOutline = "OUTLINE",
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
            timerNumColor     = { 1, 1, 1, 1 },
            timerBarColor     = { 0.93, 0.27, 0.27, 1 },
            timerFontSize     = 22,
            timerShowLabel    = true,
            timerShowBar      = true,
            timerBgOpacity    = 0.85,
        },
        interruptTracker = {
            enabled        = false,
            locked         = true,
            preview        = false,
            posX           = 0,
            posY           = -200,
            anchorFrom     = "CENTER",
            anchorTo       = "CENTER",
            anchorFrame    = "UIParent",
            growDirection  = "Down",
            maxBars        = 5,
            spacing        = 2,
            showPlayerName = true,
            showTimer      = true,
            showReadyText  = false,
            readyText      = "Ready",
            barWidth       = 200,
            barHeight      = 24,
            iconSize       = 24,
            useClassColor  = true,
            -- Bar visual
            barTexture      = "Blizzard",
            fgColorR        = 0.2,  fgColorG  = 0.8,  fgColorB  = 1.0,
            bgColorR        = 0.1,  bgColorG  = 0.1,  bgColorB  = 0.1,  bgColorA = 0.7,
            -- Border
            enableBorder    = false,
            borderThickness = 1,
            borderPadding   = 0,
            borderColorR    = 0.5,  borderColorG = 0.5, borderColorB = 0.5,
            -- Icon
            showIcon        = true,
            iconPosition    = "LEFT",
            iconOffsetX     = -4,   iconOffsetY  = 0,
            -- Name font
            nameFontFace    = "Friz Quadrata TT",
            nameFontSize    = 11,
            nameFontOutline = "OUTLINE",
            nameColorR      = 1,    nameColorG   = 1,   nameColorB   = 1,
            nameShadow      = false,
            nameOffsetX     = 5,    nameOffsetY  = 0,
            nameShadowX     = 1.6,  nameShadowY  = -0.7,
            -- Timer font
            timerFontFace    = "Friz Quadrata TT",
            timerFontSize    = 11,
            timerFontOutline = "OUTLINE",
            timerColorR      = 1,   timerColorG  = 1,   timerColorB  = 1,
            timerShadow      = false,
            timerOffsetX     = -5,  timerOffsetY = 0,
            timerShadowX     = 1.0, timerShadowY = -1.0,
        },
        mythicCast = {
            enabled       = false,
            locked        = true,
            preview       = false,
            posX          = 0,
            posY          = 100,
            anchorFrom    = "CENTER",
            anchorTo      = "CENTER",
            anchorFrame   = "UIParent",
            growDirection = "Up",
            maxBars       = 6,
            spacing       = 2,
            showTimer     = true,
            showTarget    = true,
            showRaidIcon  = true,
            barWidth      = 224,
            barHeight     = 28,
            iconSize      = 30,
            raidIconSize  = 24,
            -- Bar visual
            barTexture      = "Blizzard",
            fgColorINT_R    = 0.3,  fgColorINT_G = 0.85, fgColorINT_B = 0.3,
            fgColorNI_R     = 1.0,  fgColorNI_G  = 0.13, fgColorNI_B  = 0.17,
            bgColorR        = 0.27, bgColorG     = 0.27, bgColorB     = 0.27, bgColorA = 0.7,
            -- Border
            enableBorder    = false,
            borderThickness = 1,
            borderPadding   = 0,
            borderColorR    = 0.5,  borderColorG = 0.5, borderColorB = 0.5,
            -- Icon
            showIcon        = true,
            iconPosition    = "LEFT",
            iconOffsetX     = 2,    iconOffsetY  = 0,
            -- Raid mark offsets
            raidMarkOffsetX = -2,   raidMarkOffsetY = -2,
            -- Spell name font
            spellAlignment  = "LEFT",
            spellFontFace   = "Friz Quadrata TT",
            spellFontSize   = 12,
            spellFontOutline = "OUTLINE",
            spellColorR     = 1,    spellColorG  = 1,   spellColorB  = 1,
            spellShadow     = false,
            spellOffsetX    = 36,   spellOffsetY = 0,
            spellShadowX    = 1.0,  spellShadowY = -1.0,
            -- Target (mob) name font
            targetAlignment  = "CENTER",
            targetFontFace   = "Friz Quadrata TT",
            targetFontSize   = 12,
            targetFontOutline = "OUTLINE",
            targetColorR    = 0.3,  targetColorG = 0.85, targetColorB = 0.3,
            targetShadow    = false,
            targetOffsetX   = 0,    targetOffsetY = 0,
            targetShadowX   = 1.0,  targetShadowY = -1.0,
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
                [241322] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Flask of the Magisters
                [241324] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Flask of the Blood Knights
                [241326] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Flask of the Shattered Sun
                [241320] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Flask of Thalassian Resistance
                -- ── Health/Mana Potions ───────────────────────────────
                [241304] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Silvermoon Health Potion
                [241300] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Lightfused Mana Potion
                [241298] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Amani Extract
                [241286] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Light's Preservation
                -- ── Combat Potions ────────────────────────────────────
                [241308] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Light's Potential
                [241302] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Void-Shrouded Tincture
                [241288] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Potion of Recklessness
                [241292] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Draught of Rampant Abandon
                [241294] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Potion of Devoured Dreams
                [241296] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Potion of Zealotry
                [241338] = { enabled = false, quantity = 0, buyQty = 0, quality = 2 }, -- Enlightenment Tonic
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

function Px.SetBackgroundColor(frame, r, g, b, a)
    if frame.SetBackdropColor then frame:SetBackdropColor(r, g, b, a) end
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
-- screen — mirrors NorskenUI's CreateMessagePopup.
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
-- Mirrors NorskenUI's NRSKNUI:CreateReloadPrompt pattern.
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
function SP:ToggleGUI(input)
    if self.GUI then self.GUI.Toggle() end
end

-- ============================================================
-- Changelog data — add a new entry for each version.
-- Entries are shown newest-first in the popup.
-- ============================================================
SP.Changelog = {
    ["1.6.1"] = {
        { type = "fix",  text = "DeathAlert: mort de membres du groupe non détectée corrigée (régression Blizzard UnitTokenFromGUID en 12.x)" },
    },
    ["1.6.0"] = {
        { type = "new",  text = "6 nouveaux thèmes de couleurs : Catppuccin, Rosé Pine, Tokyo Night, Nord, Dracula, Gruvbox" },
        { type = "remove", text = "Modules AutoPI et AutoInnervate supprimés" },
        { type = "fix",  text = "Corrections de bugs divers" },
    },
}

SP.ChangelogOrder = { "1.6.1", "1.6.0" }

-- ============================================================
-- SP.ShowChangelogPopup()
-- Displays a themed popup with the changelog for the current version.
-- Called automatically on login when the version has changed.
-- ============================================================
local SP_CL_FONT      = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"
local SP_CL_W         = 420
local SP_CL_PADDING   = 18

local TAG_COLOR = {
    new    = { 0.20, 0.85, 0.45 },   -- green
    fix    = { 0.40, 0.70, 1.00 },   -- blue
    remove = { 1.00, 0.45, 0.35 },   -- red
    change = { 1.00, 0.80, 0.20 },   -- yellow
}
local TAG_LABEL = {
    new    = "NOUVEAU",
    fix    = "FIXÉ",
    remove = "RETIRÉ",
    change = "MODIFIÉ",
}

function SP.ShowChangelogPopup()
    if SP._changelogFrame then
        SP._changelogFrame:Show()
        return
    end

    local T  = SP.Theme
    local ac = T.accent

    -- ── collect lines to display ─────────────────────────────
    -- Show only the current version's entries
    local version   = SP.VERSION
    local entries   = SP.Changelog[version] or {}

    -- ── compute height ───────────────────────────────────────
    local lineH     = 18
    local tagW      = 60
    local headerH   = 46   -- title bar
    local footerH   = 46   -- close button row
    local bodyH     = math.max(60, #entries * (lineH + 6) + SP_CL_PADDING * 2)
    local totalH    = headerH + bodyH + footerH

    -- ── root frame ───────────────────────────────────────────
    local f = CreateFrame("Frame", "SP_ChangelogPopup", UIParent, "BackdropTemplate")
    f:SetSize(SP_CL_W, totalH)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetToplevel(true)

    -- outer border (1px accent line)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], T.bgDark[4])
    f:SetBackdropBorderColor(ac[1], ac[2], ac[3], 0.6)

    -- ── title bar ────────────────────────────────────────────
    local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT",  f, "TOPLEFT",  1, -1)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(headerH - 1)
    titleBar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    titleBar:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)

    -- accent left stripe
    local stripe = titleBar:CreateTexture(nil, "OVERLAY")
    stripe:SetPoint("TOPLEFT",    titleBar, "TOPLEFT",    0, 0)
    stripe:SetPoint("BOTTOMLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    stripe:SetWidth(3)
    stripe:SetColorTexture(ac[1], ac[2], ac[3], 1)

    -- title text
    local titleFS = titleBar:CreateFontString(nil, "OVERLAY")
    titleFS:SetPoint("LEFT", titleBar, "LEFT", 16, 0)
    titleFS:SetFont(SP_CL_FONT, 13, "")
    titleFS:SetTextColor(1, 1, 1, 1)
    titleFS:SetText("Suspicion's Pack  —  v" .. version)

    -- sub-title "Nouveautés"
    local subFS = titleBar:CreateFontString(nil, "OVERLAY")
    subFS:SetPoint("RIGHT", titleBar, "RIGHT", -12, 0)
    subFS:SetFont(SP_CL_FONT, 10, "")
    subFS:SetTextColor(ac[1], ac[2], ac[3], 0.9)
    subFS:SetText("Nouveautés")

    -- ── body ─────────────────────────────────────────────────
    local body = CreateFrame("Frame", nil, f, "BackdropTemplate")
    body:SetPoint("TOPLEFT",     f, "TOPLEFT",  1, -(headerH - 1))
    body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, footerH)
    body:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    body:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 1)

    -- separator line under title
    local sepTop = body:CreateTexture(nil, "ARTWORK")
    sepTop:SetPoint("TOPLEFT",  body, "TOPLEFT",  0, 0)
    sepTop:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    sepTop:SetHeight(1)
    sepTop:SetColorTexture(ac[1], ac[2], ac[3], 0.25)

    local yOff = -SP_CL_PADDING
    for _, entry in ipairs(entries) do
        local tc = TAG_COLOR[entry.type]  or TAG_COLOR.change
        local tl = TAG_LABEL[entry.type]  or string.upper(entry.type)

        -- tag badge
        local badge = body:CreateTexture(nil, "ARTWORK")
        badge:SetPoint("TOPLEFT", body, "TOPLEFT", SP_CL_PADDING, yOff)
        badge:SetSize(tagW, lineH)
        badge:SetColorTexture(tc[1], tc[2], tc[3], 0.15)

        local badgeFS = body:CreateFontString(nil, "OVERLAY")
        badgeFS:SetPoint("CENTER", badge, "CENTER", 0, 0)
        badgeFS:SetFont(SP_CL_FONT, 8, "")
        badgeFS:SetTextColor(tc[1], tc[2], tc[3], 1)
        badgeFS:SetText(tl)

        -- entry text
        local entryFS = body:CreateFontString(nil, "OVERLAY")
        entryFS:SetPoint("LEFT",  body, "LEFT",  SP_CL_PADDING + tagW + 8, 0)
        entryFS:SetPoint("RIGHT", body, "RIGHT", -SP_CL_PADDING, 0)
        entryFS:SetPoint("TOP",   body, "TOP",   0, yOff - math.floor((lineH - 12) / 2))
        entryFS:SetFont(SP_CL_FONT, 11, "")
        entryFS:SetTextColor(T.textPrimary[1] or 0.85, T.textPrimary[2] or 0.85, T.textPrimary[3] or 0.85, 1)
        entryFS:SetJustifyH("LEFT")
        entryFS:SetWordWrap(true)
        entryFS:SetText(entry.text)

        yOff = yOff - lineH - 6
    end

    -- ── footer / close button ─────────────────────────────────
    local footer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    footer:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  1,  1)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    footer:SetHeight(footerH - 1)
    footer:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    footer:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)

    -- separator line above footer
    local sepBot = footer:CreateTexture(nil, "ARTWORK")
    sepBot:SetPoint("TOPLEFT",  footer, "TOPLEFT",  0, 0)
    sepBot:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
    sepBot:SetHeight(1)
    sepBot:SetColorTexture(ac[1], ac[2], ac[3], 0.25)

    local closeBtn = CreateFrame("Button", nil, footer, "BackdropTemplate")
    closeBtn:SetSize(120, 26)
    closeBtn:SetPoint("CENTER", footer, "CENTER", 0, 0)
    closeBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                           edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    closeBtn:SetBackdropColor(ac[1], ac[2], ac[3], 0.85)
    closeBtn:SetBackdropBorderColor(ac[1], ac[2], ac[3], 1)

    local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY")
    closeLbl:SetPoint("CENTER")
    closeLbl:SetFont(SP_CL_FONT, 11, "")
    closeLbl:SetTextColor(0.04, 0.04, 0.04, 1)
    closeLbl:SetText("OK, compris !")

    closeBtn:SetScript("OnEnter", function(btn)
        btn:SetBackdropColor(ac[1]*1.15, ac[2]*1.15, ac[3]*1.15, 1)
    end)
    closeBtn:SetScript("OnLeave", function(btn)
        btn:SetBackdropColor(ac[1], ac[2], ac[3], 0.85)
    end)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
    end)

    -- ESC closes the popup
    tinsert(UISpecialFrames, "SP_ChangelogPopup")

    SP._changelogFrame = f
    f:Show()
end

-- ============================================================
-- SP.CheckChangelog()
-- Called on PLAYER_LOGIN. Shows the popup once per version.
-- ============================================================
function SP.CheckChangelog()
    local db = SP.GetDB()
    if not db or not db.settings then return end
    if db.settings.lastSeenVersion == SP.VERSION then return end
    -- Only show if there's actually changelog data for this version
    if not SP.Changelog[SP.VERSION] then return end

    db.settings.lastSeenVersion = SP.VERSION

    -- Small delay so the UI is fully loaded before we show the popup
    C_Timer.After(3, function()
        SP.ShowChangelogPopup()
    end)
end
