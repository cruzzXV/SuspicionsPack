-- SuspicionsPack - FastLoot.lua
-- Loots all items instantly on LOOT_READY by calling LootSlot() directly,
-- bypassing the delay of the native autoLootDefault CVar.
-- Also sets the CVar as a fallback for any slots missed by the direct call.

local SP = SuspicionsPack

local FastLoot = SP:NewSPModule("FastLoot", "fastLoot")
SP.FastLoot = FastLoot

-- ============================================================
-- Locals
-- ============================================================
local C_CVar  = C_CVar
local C_Timer = C_Timer

local _retryPending  = false  -- prevents stacking 0.1s retries
local _suppressCVar  = false  -- suppresses CVAR_UPDATE echo from our own SetCVar
local _origAutoLoot  = nil    -- player's own autoLootDefault, snapshotted before we touch it

-- ============================================================
-- CVar management
--
-- autoLootDefault is a Blizzard setting this module does not own: it only
-- borrows it as a fallback while active. The previous version forced it to "0"
-- on disable, which silently turned off auto-loot for players who had it on
-- before ever enabling FastLoot. Snapshot on the first activation, put it back
-- on deactivation.
-- ============================================================
local function SetAutoLoot(value)
    _suppressCVar = true
    C_CVar.SetCVar("autoLootDefault", value)
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
-- Event handlers
-- ============================================================
function FastLoot:OnLootReady()
    if not self:IsOn() then return end

    -- Ensure the CVar is set so Blizzard's own pass also loots
    if C_CVar.GetCVar("autoLootDefault") ~= "1" then
        SetAutoLoot("1")
    end

    -- Loot every slot right now
    LootAll()

    -- One retry after 0.1 s catches any slots that needed an extra frame
    if not _retryPending then
        _retryPending = true
        C_Timer.After(0.1, function()
            _retryPending = false
            if self:IsOn() then LootAll() end
        end)
    end
end

function FastLoot:OnCVarUpdate(_, cvarName)
    if cvarName ~= "autoLootDefault" then return end
    if _suppressCVar then return end
    if not self:IsOn() then return end
    -- Re-apply if the game silently reverted the value (e.g. zone transition)
    if C_CVar.GetCVar("autoLootDefault") ~= "1" then
        SetAutoLoot("1")
    end
end

-- ============================================================
-- Module lifecycle
-- OnEnable / OnDisable / Refresh come from SP.ModuleMixin.
--
-- LOOT_READY and CVAR_UPDATE used to be registered in OnEnable only, while
-- Refresh merely flipped the CVar: any Ace-level disable left the module
-- permanently dead until a /reload. They live in Activate now.
-- ============================================================
function FastLoot:Activate()
    -- Snapshot before the first write so Deactivate can restore it.
    if _origAutoLoot == nil then
        _origAutoLoot = C_CVar.GetCVar("autoLootDefault") or "0"
    end

    self:RegisterEvent("LOOT_READY",  "OnLootReady")
    self:RegisterEvent("CVAR_UPDATE", "OnCVarUpdate")

    SetAutoLoot("1")

    -- Re-apply after 1 s: at login the game runs its own CVar restoration pass
    -- after PLAYER_LOGIN and would otherwise overwrite the value above.
    C_Timer.After(1.0, function()
        if self:IsOn() then SetAutoLoot("1") end
    end)
end

function FastLoot:Deactivate()
    self:UnregisterEvent("LOOT_READY")
    self:UnregisterEvent("CVAR_UPDATE")
    _retryPending = false

    if _origAutoLoot ~= nil then
        SetAutoLoot(_origAutoLoot)
        _origAutoLoot = nil
    end
end
