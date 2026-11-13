-- SuspicionsPack - BuffThanks.lua
-- Thanks the players who buff you: a voiced emote aimed at them, or a whisper,
-- after a delay.
--
-- Behaviour read from KINDRED 3.1.2 (All Rights Reserved) and Thanks for the
-- Buff (Gogo1951, MIT). The code is ours; nothing is copied from either.
--
-- DETECTION. WoW: Forever has no combat log, and the UNIT_AURA payload can be
-- secret, so the payload is never read. Each UNIT_AURA on the player rescans the
-- helpful auras and compares their auraInstanceIDs with the last readable scan:
-- an ID seen for the first time is a buff just applied. A refresh keeps its ID
-- and is not thanked. While auras are secret (combat) the module is blind and
-- drops its baseline; the next readable scan only rebuilds it, so a buff that
-- lands in combat is skipped, never thanked late. A loading screen resends every
-- aura: for SETTLE seconds after one, scans only rebuild the baseline.
--
-- SENDING. One reaction at a time, `delay` seconds after the buff and at least
-- GAP after the previous one. A player is thanked at most once per `cooldown`.
-- Checked again when it goes out: an emote never plays in combat, a whisper
-- never goes out while the client locks chat. Either is then dropped, not kept.

local SP = SuspicionsPack

local BT = SP:NewSPModule("BuffThanks", "buffThanks")
SP.BuffThanks = BT

local GetTime, InCombatLockdown, UnitGUID = GetTime, InCombatLockdown, UnitGUID
local pcall, type, ipairs, pairs = pcall, type, ipairs, pairs
local math_max, math_random = math.max, math.random

local SETTLE     = 5      -- seconds after a loading screen where scans only rebuild the baseline
local GAP        = 1.5    -- seconds between two reactions
local MAX_AURAS  = 255
local MAX_CHAT   = 255    -- bytes SendChatMessage accepts
local TEST_SPELL = 1126   -- Mark of the Wild: rank 1 on Forever, the buff itself on retail

-- The voiced emotes offered, by C_ChatInfo.PerformEmote token (locale-free).
BT.EMOTES = {
    { token = "THANK",        key = "emoteThank" },
    { token = "CHEER",        key = "emoteCheer" },
    { token = "APPLAUD",      key = "emoteApplaud" },
    { token = "CONGRATULATE", key = "emoteCongratulate" },
    { token = "NOD",          key = "emoteNod" },
    { token = "KISS",         key = "emoteKiss" },
}

-- ============================================================
-- State
-- ============================================================
local active      = false
local known       = {}     -- auraInstanceID -> true, from the last readable scan
local primed      = false  -- `known` is a usable baseline
local enteredAt   = 0      -- GetTime() of the last loading screen (or of switching on)
local settleUntil = 0
local queue       = {}     -- { guid, spellID, at }, oldest first
local thanked     = {}     -- guid -> GetTime() of their last queued reaction
local timer, lastSent, lastEmote = nil, -math.huge, nil

local function Plain(v) return not (issecretvalue and issecretvalue(v)) end
local function Debug(...) SP:Debug("BuffThanks", ...) end

local function Say(msg)
    local ac = SP.Theme and SP.Theme.accent or { 1, 1, 1 }
    local hex = string.format("%02X%02X%02X", math.floor(ac[1] * 255 + 0.5),
        math.floor(ac[2] * 255 + 0.5), math.floor(ac[3] * 255 + 0.5))
    print("|cff" .. hex .. "Suspicion's|r Pack : " .. msg)
end

-- ============================================================
-- Where you are: the db key of the matching "where" switch
-- ============================================================
-- A raid group is "inRaid" wherever it is; a party outside instances is
-- "inWorldGroup", a party in a dungeon or scenario "inGroup".
function BT.Where()
    local inInstance, kind = IsInInstance()
    if inInstance then
        if kind == "pvp" or kind == "arena" then return "inPvP" end
        if kind == "raid" then return "inRaid" end
        if kind == "party" or kind == "scenario" then return "inGroup" end
    end
    if IsInRaid() then return "inRaid" end
    if IsInGroup() then return "inWorldGroup" end
    return "inWorld"
end

-- ============================================================
-- Who to aim at
-- ============================================================

-- The name /w and /thank take. On WoW: Forever names are "First Surname",
-- unique in the region and written without a realm.
function BT.Name(guid)
    if type(guid) ~= "string" or not GetPlayerInfoByGUID then return nil end
    local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
    if not ok or not Plain(name) or not Plain(realm) then return nil end
    if type(name) ~= "string" or name == "" then return nil end
    if RegionalUniqueNamesEnabled then
        local okR, regional = pcall(RegionalUniqueNamesEnabled)
        if okR and regional == true then return name end
    end
    if type(realm) == "string" and realm ~= "" then
        realm = realm:gsub("[%s%-]", "")
        local home = GetNormalizedRealmName and GetNormalizedRealmName() or ""
        if realm ~= home then return name .. "-" .. realm end
    end
    return name
end

-- A unit token when we hold one for them (group, target, focus, mouseover,
-- nameplate), else their name. nil means no emote: PerformEmote with no target
-- aims at whatever you have targeted.
function BT.EmoteTarget(guid)
    local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid)
    if Plain(unit) and type(unit) == "string" and unit ~= "" then
        -- A party member two zones away is still "party2": no emote to an empty room.
        local visible = UnitIsVisible(unit)
        if Plain(visible) and not visible then return nil end
        return unit
    end
    return BT.Name(guid)
end

-- ============================================================
-- Reactions
-- ============================================================

-- A random ticked emote, not the last one while another is ticked.
local function PickEmote(db)
    local pool = {}
    for _, e in ipairs(BT.EMOTES) do
        if db[e.key] and e.token ~= lastEmote then pool[#pool + 1] = e.token end
    end
    if #pool == 0 then
        for _, e in ipairs(BT.EMOTES) do
            if db[e.key] then pool[#pool + 1] = e.token end
        end
    end
    if #pool == 0 then return "THANK" end
    return pool[math_random(#pool)]
end

local function Emote(db, target)
    if not target then return false, "no target in sight" end
    local token = PickEmote(db)
    local ok, restricted = pcall(C_ChatInfo.PerformEmote, token, target)
    if not ok then return false, "PerformEmote failed" end
    -- The return is `restricted` (ChatFrameEditBox reads it that way), not success.
    if Plain(restricted) and restricted == true then return false, "emote restricted" end
    lastEmote = token
    return true, token .. " -> " .. target
end

-- The whisper text, or nil when it cannot fit in one chat line.
function BT.Message(db, spellID)
    local text = db.message
    if type(text) ~= "string" or text == "" then text = SP.DEFAULTS.profile.buffThanks.message end
    local name = C_Spell.GetSpellName(spellID) or "buff"
    local link = C_Spell.GetSpellLink and C_Spell.GetSpellLink(spellID) or name
    local out = text:gsub("{buff}", function() return link end)
    -- A link cut in half is not a link: fall back to the plain name first.
    if #out > MAX_CHAT then out = text:gsub("{buff}", function() return name end) end
    if #out > MAX_CHAT then return nil end
    return out
end

local function Whisper(db, name, spellID)
    if not name then return false, "no name" end
    if C_ChatInfo.InChatMessagingLockdown then
        local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
        if not ok or not Plain(locked) or locked then return false, "chat locked" end
    end
    local msg = BT.Message(db, spellID)
    if not msg then return false, "message too long" end
    local ok = pcall(C_ChatInfo.SendChatMessage, msg, "WHISPER", nil, name)
    if not ok then return false, "SendChatMessage failed" end
    return true, "whisper -> " .. name
end

-- Checked again at send time: the delay may have taken you into a fight or a raid.
function BT:Send(guid, spellID)
    local db = self:GetDB()
    if not db[BT.Where()] then return false, "off here" end
    if db.reaction == "whisper" then return Whisper(db, BT.Name(guid), spellID) end
    if InCombatLockdown() then return false, "in combat" end
    return Emote(db, BT.EmoteTarget(guid))
end

-- ============================================================
-- Queue
-- ============================================================
local function Kick()
    if timer or #queue == 0 then return end
    local at = math_max(queue[1].at, lastSent + GAP)
    timer = C_Timer.NewTimer(math_max(0, at - GetTime()), function()
        timer = nil
        BT:Process()
    end)
end

function BT:Process()
    local entry = table.remove(queue, 1)
    if entry then
        local ok, detail = self:Send(entry.guid, entry.spellID)
        Debug(ok and "sent" or "dropped", detail)
        lastSent = GetTime()
    end
    Kick()
end

function BT:Queue(guid, spellID)
    local db = self:GetDB()
    local where = BT.Where()
    if not db[where] then return Debug("off here", where, spellID) end
    local now = GetTime()
    for g, at in pairs(thanked) do
        if now - at >= db.cooldown then thanked[g] = nil end
    end
    if thanked[guid] then return Debug("already thanked", guid, spellID) end
    thanked[guid] = now
    queue[#queue + 1] = { guid = guid, spellID = spellID, at = now + db.delay }
    Debug("queued", guid, spellID)
    Kick()
end

-- ============================================================
-- Detection
-- ============================================================

-- The caster's GUID, plain, or nil.
local function CasterGUID(aura, id)
    local unit = aura.sourceUnit
    if not Plain(unit) then return nil end
    local guid
    if type(unit) == "string" and unit ~= "" then
        guid = UnitGUID(unit)
        if not Plain(guid) then return nil end
    end
    -- A stranger with no nameplate leaves sourceUnit empty.
    if guid == nil and C_UnitAuras.GetAuraCasterGUID then
        local ok, g = pcall(C_UnitAuras.GetAuraCasterGUID, "player", id)
        if ok and Plain(g) then guid = g end
    end
    return type(guid) == "string" and guid or nil
end

-- guid, spellID for a buff another player just gave us; nil, reason otherwise.
local function Received(aura, id)
    local spellID, duration, expires = aura.spellId, aura.duration, aura.expirationTime
    if not (Plain(spellID) and Plain(duration) and Plain(expires)) then return nil, "secret fields" end
    if type(spellID) ~= "number" then return nil, "no spell" end
    -- Paladin auras, zone auras and the like have no timer: they come and go
    -- with range, nobody handed them over.
    if type(duration) ~= "number" or duration <= 0 then return nil, "no duration" end
    -- Restored late after a loading screen, applied before it.
    if type(expires) == "number" and expires > 0 and expires - duration < enteredAt then
        return nil, "older than the loading screen"
    end
    local guid = CasterGUID(aura, id)
    if not guid then return nil, "caster unknown" end
    if guid:sub(1, 7) ~= "Player-" then return nil, "not a player" end
    if guid == UnitGUID("player") then return nil, "own buff" end
    return guid, spellID
end

-- Reacts only after the whole scan read cleanly. A scan that goes blind halfway
-- reacts to nothing and drops the baseline, as combat does.
local function Scan(forceBaseline)
    if not active then return end
    if SP.AurasSecret() then primed = false; return end
    local baseline = forceBaseline or not primed or GetTime() < settleUntil
    local seen, fresh = {}, {}
    for i = 1, MAX_AURAS do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not Plain(aura) then primed = false; return end
        if aura == nil then break end
        if canaccesstable and not canaccesstable(aura) then primed = false; return end
        local id = aura.auraInstanceID
        if not Plain(id) or type(id) ~= "number" then primed = false; return end
        seen[id] = true
        if not baseline and not known[id] then fresh[#fresh + 1] = aura end
    end
    known, primed = seen, true
    for _, aura in ipairs(fresh) do
        local guid, spellID = Received(aura, aura.auraInstanceID)
        if guid then BT:Queue(guid, spellID) else Debug("ignored", spellID) end
    end
end
-- Not AceEvent: it has no RegisterUnitEvent, and UNIT_AURA is wanted for the player only.
local events = CreateFrame("Frame")
BT._events = events   -- the tests deliver events through it
events:SetScript("OnEvent", SP.Perf.WrapEvent("BuffThanks", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        enteredAt   = GetTime()
        settleUntil = enteredAt + SETTLE
        -- The baseline has to exist before the first buff after the window,
        -- even if no aura changes during it.
        C_Timer.After(SETTLE, function() Scan(true) end)
    end
    Scan()
end))

-- ============================================================
-- Test button
-- ============================================================
function BT:Test()
    local db = self:GetDB()
    local ok, detail
    if db.reaction == "whisper" then
        ok, detail = Whisper(db, BT.Name(UnitGUID("player")), TEST_SPELL)
    else
        local guid = UnitGUID("target")
        if not (Plain(guid) and type(guid) == "string" and guid:sub(1, 7) == "Player-") then
            return Say("target a player to test the emote.")
        end
        if InCombatLockdown() then return Say("no emote in combat.") end
        ok, detail = Emote(db, BT.EmoteTarget(guid))
    end
    Debug("test", ok, detail)
    if not ok then Say("test not sent (" .. detail .. ").") end
end

-- ============================================================
-- Activate / Deactivate
-- Activate runs again on every settings change: it only starts what is not running.
-- ============================================================
function BT:Activate()
    if not self:IsOn() or active then return end
    active    = true
    primed    = false
    enteredAt = GetTime()
    events:RegisterUnitEvent("UNIT_AURA", "player")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    Scan()
end

function BT:Deactivate()
    active = false
    events:UnregisterAllEvents()
    if timer then timer:Cancel(); timer = nil end
    queue, known, primed = {}, {}, false
end
