-- SuspicionsPack - CVars.lua
-- Game CVar tweaks: Sharpen Game, class-colored friendly nameplates, etc.
-- Adapted from NorskenUI's MiscVars.lua.

local SP = SuspicionsPack

local CVars = SP:NewModule("CVars", "AceEvent-3.0")
SP.CVars = CVars

-- ============================================================
-- Locals
-- ============================================================
local C_CVar   = C_CVar
local C_Timer  = C_Timer
local ipairs   = ipairs

-- ============================================================
-- CVar definitions (exposed so GUI can iterate them)
-- ============================================================
CVars.DEFS = {
    {
        key   = "ResampleAlwaysSharpen",
        label = "Sharpen Game",
        desc  = "Applies a bilinear upsampling sharpening filter to the rendered image.",
        type  = "boolean",
    },
    {
        key   = "nameplateUseClassColorForFriendlyPlayerUnitNames",
        label = "Class Colored Friendly Names",
        desc  = "Colors friendly player nameplate names with their class color.",
        type  = "boolean",
    },
    {
        key   = "nameplateShowOnlyNameForFriendlyPlayerUnits",
        label = "Show Only Name (Friendly Players)",
        desc  = "Hides health bar on friendly player nameplates, showing only the name.",
        type  = "boolean",
    },
    {
        key            = "worldPreloadNonCritical",
        label          = "Preload World Non-Critical Objects (0)",
        desc           = "Recommended value: 0 (OFF). WoW skips pre-streaming assets outside the critical load radius. Reduces memory pressure and hitching in dense zones at the cost of minor pop-in.",
        type           = "boolean",
        reapplyOnLogin = true,   -- WoW resets this CVar at every login; re-enforce after a delay
    },
}

-- ============================================================
-- DB helper
-- ============================================================
local function GetDB()
    return SP.GetDB().cvars
end

-- ============================================================
-- CVar value helpers
-- ============================================================
local function ToCVarValue(value, cvarType)
    if cvarType == "boolean" then return value and 1 or 0 end
    return value
end

local function FromCVarValue(value, cvarType)
    if cvarType == "boolean" then return value == "1" end
    return value
end

-- ============================================================
-- Sync game CVars → DB (called once on login)
-- ============================================================
local function SyncFromCVars()
    local db = GetDB()
    if not db then return end
    for _, def in ipairs(CVars.DEFS) do
        if db[def.key] == nil then
            local current = C_CVar.GetCVar(def.key)
            db[def.key]   = FromCVarValue(current, def.type)
        end
    end
end

-- ============================================================
-- Apply DB settings → game CVars
-- ============================================================
local function ApplySettings()
    local db = GetDB()
    if not db then return end
    for _, def in ipairs(CVars.DEFS) do
        local key      = def.key
        local dbValue  = db[key]
        if dbValue ~= nil then
            local current      = C_CVar.GetCVar(key)
            local currentValue = FromCVarValue(current, def.type)
            if dbValue ~= currentValue then
                C_CVar.SetCVar(key, ToCVarValue(dbValue, def.type))
            end
        end
    end
end

-- ============================================================
-- Public API (used by GUI)
-- ============================================================
CVars._suppressUpdate = false

function CVars.SetCVar(key, value)
    local db = GetDB()
    if not db then return end
    db[key] = value
    CVars._suppressUpdate = true
    ApplySettings()
    CVars._suppressUpdate = false
end

function CVars.Refresh()
    ApplySettings()
end

-- ============================================================
-- AceAddon Module lifecycle
-- ============================================================
function CVars:OnEnable()
    -- CVAR_UPDATE keeps the DB in sync when the player changes a CVar in-game.
    self:RegisterEvent("CVAR_UPDATE")

    if IsLoggedIn() then
        self:OnLogin()
    else
        self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
    end
end

function CVars:OnDisable()
    self:UnregisterAllEvents()
end

-- Live sync: if the player changes a CVar in-game (console, other addon, etc.),
-- update our DB so the GUI reflects the true current state.
-- Exception: for CVars marked reapplyOnLogin=true, if our DB has a value set,
-- re-enforce it rather than letting the game overwrite our preference.
function CVars:CVAR_UPDATE(_, cvarName)
    if self._suppressUpdate then return end
    local db = GetDB()
    if not db then return end
    for _, def in ipairs(self.DEFS) do
        if def.key == cvarName then
            local current   = C_CVar.GetCVar(cvarName)
            local gameValue = FromCVarValue(current, def.type)
            -- For sticky CVars: if the game changed it away from our DB value, re-enforce ours
            if def.reapplyOnLogin and db[cvarName] ~= nil and db[cvarName] ~= gameValue then
                self._suppressUpdate = true
                C_CVar.SetCVar(cvarName, ToCVarValue(db[cvarName], def.type))
                self._suppressUpdate = false
            else
                db[cvarName] = gameValue
            end
            break
        end
    end
end

function CVars:OnLogin()
    self:UnregisterEvent("PLAYER_LOGIN")
    -- Read current game CVar values into the DB so the GUI shows the correct
    -- initial state.  We do NOT call ApplySettings() here — WoW already
    -- persists CVars in its own config files.  The addon only writes a CVar
    -- when the player explicitly toggles it through the GUI (CVars.SetCVar).
    -- Applying on login would risk overwriting the player's in-game preferences
    -- with a stale or incorrectly-synced DB value.
    SyncFromCVars()

    -- For CVars that WoW resets at every login (reapplyOnLogin=true),
    -- schedule a delayed re-enforce so our preference wins after WoW's own init.
    C_Timer.After(5, function()
        local db2 = GetDB()
        if not db2 then return end
        for _, def in ipairs(self.DEFS) do
            if def.reapplyOnLogin and db2[def.key] ~= nil then
                local current   = C_CVar.GetCVar(def.key)
                local gameValue = FromCVarValue(current, def.type)
                if db2[def.key] ~= gameValue then
                    self._suppressUpdate = true
                    C_CVar.SetCVar(def.key, ToCVarValue(db2[def.key], def.type))
                    self._suppressUpdate = false
                end
            end
        end
    end)
end
