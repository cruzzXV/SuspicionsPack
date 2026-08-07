-- SuspicionsPack - CVars.lua
-- Game CVar tweaks: Sharpen Game, class-colored friendly nameplates, etc.

local SP = SuspicionsPack

local CVars = SP:NewSPModule("CVars", "cvars")
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
--
-- Kept as a file-local rather than folded into ModuleMixin:GetDB(): SetCVar
-- below is a dot function (the GUI calls SP.CVars.SetCVar(key, v)) and
-- SyncFromCVars/ApplySettings are plain locals, so none of them have a `self`.
-- ============================================================
local function GetDB()
    return SP.GetDB().cvars
end

-- The `cvars` profile section is a bare key -> value map with no `enabled` key:
-- this module has no master toggle, every CVar has its own switch in the GUI.
-- ModuleMixin:IsOn() reads db.enabled, so without this override it would report
-- the module permanently off and Refresh() would Deactivate at login -- undoing
-- every setting the player made.
function CVars:IsOn()
    return self:GetDB() ~= nil
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
-- Original values
--
-- The module used to change the player's console variables and never put them
-- back -- switching it off, or removing the addon, left the game permanently
-- reconfigured. Every write now goes through WriteCVar, which captures the
-- pre-addon value exactly once, and Deactivate replays the snapshot.
-- ============================================================
local originals = {}

local function WriteCVar(key, value)
    -- Explicit `== nil`, not a truthiness test: a CVar can legitimately hold
    -- "" or "0", both truthy in Lua, and `false` is the marker for "the CVar
    -- had no value at all". nil is the one and only "not captured yet" state,
    -- so a second write never overwrites the snapshot with our own value.
    if originals[key] == nil then
        originals[key] = C_CVar.GetCVar(key) or false
    end
    C_CVar.SetCVar(key, value)
end

local function RestoreCVars()
    for key, original in pairs(originals) do
        if type(original) == "string" then
            C_CVar.SetCVar(key, original)
        end
    end
    wipe(originals)
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
                WriteCVar(key, ToCVarValue(dbValue, def.type))
            end
        end
    end
end

-- ============================================================
-- Public API (used by GUI)
-- ============================================================
function CVars.SetCVar(key, value)
    local db = GetDB()
    if not db then return end
    db[key] = value
    ApplySettings()
end

-- Live sync: if the player changes a CVar in-game (console, other addon, etc.),
-- update our DB so the GUI reflects the true current state.
-- Exception: for CVars marked reapplyOnLogin=true, if our DB has a value set,
-- re-enforce it rather than letting the game overwrite our preference.
--
-- There is no re-entrancy flag: CVAR_UPDATE is dispatched a frame after
-- SetCVar, so the old `_suppressUpdate` boolean was always back to false by the
-- time the event arrived and never suppressed anything. The compare below is
-- what actually breaks the loop -- after our own write the game value already
-- equals the DB value, so nothing is re-enforced.
function CVars:CVAR_UPDATE(_, cvarName)
    local db = GetDB()
    if not db then return end
    for _, def in ipairs(self.DEFS) do
        if def.key == cvarName then
            local current   = C_CVar.GetCVar(cvarName)
            local gameValue = FromCVarValue(current, def.type)
            -- For sticky CVars: if the game changed it away from our DB value, re-enforce ours
            if def.reapplyOnLogin and db[cvarName] ~= nil and db[cvarName] ~= gameValue then
                WriteCVar(cvarName, ToCVarValue(db[cvarName], def.type))
            else
                db[cvarName] = gameValue
            end
            break
        end
    end
end

-- ============================================================
-- Activate / Deactivate
-- Refresh, OnEnable and OnDisable all come from ModuleMixin -- see
-- Core/Module.lua. IsOn() is overridden above: this module has no db.enabled.
-- ============================================================
function CVars:Activate()
    -- CVAR_UPDATE keeps the DB in sync when the player changes a CVar in-game.
    self:RegisterEvent("CVAR_UPDATE")

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
        -- C_Timer.After cannot be cancelled, so re-read the state instead: the
        -- module may have been deactivated inside these five seconds, and this
        -- would otherwise write the CVars straight back after the restore.
        if not self:IsOn() then return end
        local db2 = GetDB()
        if not db2 then return end
        for _, def in ipairs(self.DEFS) do
            if def.reapplyOnLogin and db2[def.key] ~= nil then
                local current   = C_CVar.GetCVar(def.key)
                local gameValue = FromCVarValue(current, def.type)
                if db2[def.key] ~= gameValue then
                    WriteCVar(def.key, ToCVarValue(db2[def.key], def.type))
                end
            end
        end
    end)
end

function CVars:Deactivate()
    self:UnregisterEvent("CVAR_UPDATE")
    RestoreCVars()
end
