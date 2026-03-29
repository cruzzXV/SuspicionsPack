-- SuspicionsPack - FastLoot.lua
-- Loots all items instantly on LOOT_READY by calling LootSlot() directly,
-- bypassing the delay of the native autoLootDefault CVar.
-- Also sets the CVar as a fallback for any slots missed by the direct call.
-- Pattern adapted from NephUI and AzortharionUI fast-loot implementations.

local SP = SuspicionsPack

local FastLoot = SP:NewModule("FastLoot", "AceEvent-3.0")
SP.FastLoot = FastLoot

-- ============================================================
-- Locals
-- ============================================================
local C_CVar  = C_CVar
local C_Timer = C_Timer

local _retryPending  = false  -- prevents stacking 0.1s retries
local _suppressCVar  = false  -- suppresses CVAR_UPDATE echo from our own SetCVar

-- ============================================================
-- DB helper
-- ============================================================
local function GetDB()
    return SP.GetDB().fastLoot
end

-- ============================================================
-- CVar management
-- ============================================================
local function ApplyCVar(enable)
    _suppressCVar = true
    C_CVar.SetCVar("autoLootDefault", enable and "1" or "0")
    _suppressCVar = false
end

-- ============================================================
-- Core: loot all available slots immediately
-- ============================================================
local function LootAll()
    local n = GetNumLootItems()
    for i = 1, n do
        if LootSlotHasItem(i) then
            LootSlot(i)
        end
    end
end

-- ============================================================
-- Public API (used by GUI toggle)
-- ============================================================
function FastLoot.Refresh()
    local db = GetDB()
    ApplyCVar(db and db.enabled)
end

-- ============================================================
-- Event handlers
-- ============================================================
function FastLoot:OnLootReady()
    local db = GetDB()
    if not (db and db.enabled) then return end

    -- Ensure the CVar is set so Blizzard's own pass also loots
    if C_CVar.GetCVar("autoLootDefault") ~= "1" then
        ApplyCVar(true)
    end

    -- Loot every slot right now
    LootAll()

    -- One retry after 0.1 s catches any slots that needed an extra frame
    if not _retryPending then
        _retryPending = true
        C_Timer.After(0.1, function()
            _retryPending = false
            local db2 = GetDB()
            if db2 and db2.enabled then LootAll() end
        end)
    end
end

function FastLoot:OnCVarUpdate(_, cvarName)
    if cvarName ~= "autoLootDefault" then return end
    if _suppressCVar then return end
    local db = GetDB()
    if not (db and db.enabled) then return end
    -- Re-apply if the game silently reverted the value (e.g. zone transition)
    if C_CVar.GetCVar("autoLootDefault") ~= "1" then
        ApplyCVar(true)
    end
end

function FastLoot:OnLogin()
    local db = GetDB()
    if not (db and db.enabled) then return end
    -- 1 s delay so the game's own CVar restoration pass finishes first
    C_Timer.After(1.0, function() ApplyCVar(true) end)
end

-- ============================================================
-- AceAddon lifecycle
-- ============================================================
function FastLoot:OnEnable()
    if IsLoggedIn() then
        self:OnLogin()
    else
        self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
    end
    self:RegisterEvent("LOOT_READY",   "OnLootReady")
    self:RegisterEvent("CVAR_UPDATE",  "OnCVarUpdate")
end

function FastLoot:OnDisable()
    self:UnregisterAllEvents()
    _retryPending = false
    ApplyCVar(false)
end
