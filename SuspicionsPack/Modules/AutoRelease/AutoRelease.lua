-- SuspicionsPack — AutoRelease Module
--
-- Releases your spirit for you, but only where releasing is actually the right
-- call. Two cases, deliberately kept separate:
--
--   * PvP -- in a battleground you always run back, so a blanket rule is fine.
--   * PvE -- boss by boss. Most encounters you wait for a battle rez; a few you
--     release and run in. There is no API that tells you which, so it is a list
--     you build yourself, and the options page has a one-click reader for the
--     current spot so building it is a two-second job in front of the boss
--     rather than an evening on Wowhead.
--
-- WHY THE LIST SHIPS EMPTY: an entry is a set of numeric IDs. One that is
-- subtly wrong does not error, it just never matches -- the feature looks
-- broken with no way to tell why. An empty list plus a working "Add current
-- location" button is honest; a guessed ID is not.
--
-- THE DELAY IS NOT COSMETIC. A battle rez that lands while you are lying there
-- is exactly what you want to keep, so the release is deferred and re-checked:
-- if a resurrection is pending by then, we leave you alone.

local SP = SuspicionsPack

local AutoRelease = SP:NewSPModule("AutoRelease", "autoRelease")
SP.AutoRelease = AutoRelease

-- ============================================================
-- Where am I?
--
-- One implementation, three consumers: the release check, the options page's
-- reader card, and the slash command. They cannot disagree.
-- ============================================================
function AutoRelease.Describe()
    local zoneName, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    local uiMapID
    if C_Map and C_Map.GetBestMapForUnit then
        uiMapID = C_Map.GetBestMapForUnit("player")
    end
    return {
        zone         = (GetRealZoneText and GetRealZoneText()) or zoneName or "",
        subZone      = (GetSubZoneText and GetSubZoneText()) or "",
        instanceName = zoneName or "",
        instanceType = instanceType or "none",
        instanceID   = instanceID,
        uiMapID      = uiMapID,
    }
end

-- ============================================================
-- Matching
-- ============================================================

-- An entry matches when every field it DECLARES agrees with where you are.
-- Fields it leaves out are wildcards, so { instanceID = 2549 } covers a whole
-- raid while adding a subZone narrows it to one platform.
function AutoRelease.EntryMatches(entry, here)
    if type(entry) ~= "table" then return false end

    local hasInstance = entry.instanceID ~= nil
    local hasMap      = entry.uiMapID ~= nil
    local hasSub      = entry.subZone ~= nil and entry.subZone ~= ""

    -- An entry that declares nothing would match the whole game, including the
    -- middle of a raid boss. Refuse it rather than trust it.
    if not (hasInstance or hasMap or hasSub) then return false end

    if hasInstance and entry.instanceID ~= here.instanceID then return false end
    if hasMap      and entry.uiMapID    ~= here.uiMapID    then return false end
    if hasSub      and entry.subZone    ~= here.subZone    then return false end
    return true
end

local function ShouldRelease(db, here)
    -- Battlegrounds and arenas: always, if the option is on.
    if db.inPvP and (here.instanceType == "pvp" or here.instanceType == "arena") then
        return true, "pvp"
    end

    for _, entry in ipairs(db.zones or {}) do
        if entry.enabled ~= false and AutoRelease.EntryMatches(entry, here) then
            return true, entry.name or "zone"
        end
    end
    return false
end

-- ============================================================
-- Release
-- ============================================================

local pending = false

local function DoRelease()
    pending = false

    -- Re-checked at the last moment, not at scheduling time. A battle rez that
    -- landed during the delay is the whole reason the delay exists: releasing
    -- through it throws away someone's cooldown.
    if IsResurrectPending and IsResurrectPending() then return end
    if not UnitIsDeadOrGhost("player") then return end
    if UnitIsGhost("player") then return end          -- already released

    -- Blizzard shows a confirmation in instances where you cannot run back;
    -- RepopMe simply does nothing there, which is the behaviour we want.
    if RepopMe then pcall(RepopMe) end
end

function AutoRelease:OnPlayerDead()
    if not self:IsOn() then return end

    local db = SP.GetDB().autoRelease
    if not db then return end

    if pending then return end

    local here = AutoRelease.Describe()
    local ok = ShouldRelease(db, here)
    if not ok then return end

    -- `delay == nil`, spelled out. Not because `or` would eat a 0 -- it would
    -- not, 0 is true in Lua -- but because "was this ever set" and "is this
    -- zero" are different questions and the code should ask the one it means.
    local delay = db.delay
    if delay == nil then delay = 2 end

    pending = true
    if delay <= 0 then
        DoRelease()
    else
        C_Timer.After(delay, DoRelease)
    end
end

-- Getting rezzed cancels nothing by itself -- DoRelease re-checks -- but
-- clearing the flag lets a second death schedule a second release.
function AutoRelease:OnPlayerAlive()
    pending = false
end

-- ============================================================
-- The other half of dying: accepting a resurrection.
--
-- HARD REZ ONLY, NEVER A BATTLE REZ -- and the test is one line, because the
-- game already encodes the answer: resurrection spells that work out of combat
-- CANNOT be cast in combat. So a caster who is in combat is casting a battle
-- rez, and a caster who is not, is not. Nothing else needs deciding.
--
-- This mirrors Leatrix Plus, which has shipped this for years. An earlier
-- version here read the combat log and matched spell IDs; it was more code, it
-- had more ways to be wrong, and it did not work.
-- ============================================================

-- `caster` is RESURRECT_REQUEST's one argument: the NAME of whoever is offering.
-- A player name doubles as a unit token, which is what makes this answerable.
function AutoRelease.ShouldAcceptRez(db, caster)
    if not (db and db.enabled and db.acceptRez) then return false end
    if not caster or caster == "" then return true end

    -- NOT A UNIT -> an object: the Failure Detection Pylon or the Brazier of
    -- Awakening, both battle rezzes. Leatrix excludes those by name across ten
    -- locales, which is the only option when all you have is a name; asking
    -- whether the caster is a unit at all is the same test in every language,
    -- and it keeps working when Blizzard adds the next one.
    if not UnitExists(caster) then return false end

    -- THE TEST.
    if db.onlyWhenFightOver ~= false and UnitAffectingCombat(caster) then return false end
    return true
end

-- Accepted straight away, not deferred: there is nothing left to wait for now
-- that the decision needs no second source.
function AutoRelease:OnResurrectRequest(_, caster)
    if not self:IsOn() then return end
    if not AutoRelease.ShouldAcceptRez(SP.GetDB().autoRelease, caster) then return end

    if AcceptResurrect then pcall(AcceptResurrect) end
    -- Accepting does not take the dialog down on its own; without this it sits
    -- there afterwards with nothing left to answer.
    if StaticPopup_Hide then pcall(StaticPopup_Hide, "RESURRECT_NO_TIMER") end
end

-- ============================================================
-- Module lifecycle
-- OnEnable / OnDisable / Refresh come from SP.ModuleMixin.
-- ============================================================
function AutoRelease:Activate()
    self:RegisterEvent("PLAYER_DEAD",        "OnPlayerDead")
    self:RegisterEvent("PLAYER_ALIVE",       "OnPlayerAlive")
    self:RegisterEvent("PLAYER_UNGHOST",     "OnPlayerAlive")
    self:RegisterEvent("RESURRECT_REQUEST",  "OnResurrectRequest")
end

function AutoRelease:Deactivate()
    self:UnregisterEvent("PLAYER_DEAD")
    self:UnregisterEvent("PLAYER_ALIVE")
    self:UnregisterEvent("PLAYER_UNGHOST")
    self:UnregisterEvent("RESURRECT_REQUEST")
    pending = false
end
