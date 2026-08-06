-- SuspicionsPack — Saved-variable migration runner
--
-- Until this existed the addon had NO migration story at all: no schema
-- version, no pruning. Every key ever shipped stayed in every user's
-- SuspicionsPackDB forever, including whole sections for modules that were
-- deleted (AutoPI, AutoInnervate, CombatLog, PetStatus) and 111 keys that no
-- code has read in months. AceDB rawsets every default into the saved table, so
-- all of it is rewritten to disk on every logout.
--
-- Worse, GUI profile import deep-merges an arbitrary user-supplied string into
-- the live profile with no version field, so importing an old string
-- re-injected dead keys permanently.
--
-- USAGE
--   SP.RegisterMigration({
--       id    = "prune_dead_sections_2026_08",
--       scope = "profile",              -- "global" | "profile"
--       body  = function(ctx)
--           ctx.profile.interruptTracker = nil
--       end,
--   })
--
-- GUARANTEES
--   * The body runs inside pcall: a buggy migration cannot break login.
--   * The flag is stamped ONLY on success, so a failed body retries next
--     session instead of being silently skipped forever.
--   * "profile" scope walks EVERY stored profile, so a user with one profile
--     per character is migrated in a single pass -- not just the active one.
--   * Flags live next to the data they describe (`_migrations` on the profile
--     for profile scope, on the root for global scope), so copying a profile
--     carries its migration state with it.
--
-- AUTHORING RULES
--   1. IDs are forever. Never change an existing id -- register a new
--      migration instead. The flag is keyed on the id.
--   2. Bodies must be idempotent. Write them so re-running on already-migrated
--      data is harmless; the flag is a shortcut, not the correctness argument.
--   3. Do NOT iterate profiles yourself when scope is "profile" -- the runner
--      does it. Iterating inside the body would migrate other profiles without
--      stamping their flags.
--   4. Do NOT call live game APIs. This runs at ADDON_LOADED, before the player
--      exists: UnitClass, GetSpecialization and friends are not reliable yet.
--   5. Walk the RAW stored table via ctx.profile, never SP.db.profile -- AceDB
--      has not been created yet when this runs.

local SP = SuspicionsPack

-- Bump when the on-disk shape changes in a way worth stamping. Purely
-- informational: the per-migration flags are what actually gate execution.
SP.DB_VERSION = 2

local _migrations     = {}
local _migrationsById = {}
local _errors         = {}

SP.MigrationErrors = _errors

local VALID_SCOPES = { global = true, profile = true }

function SP.RegisterMigration(spec)
    if type(spec) ~= "table" then
        error("RegisterMigration: spec must be a table", 2)
    end
    if type(spec.id) ~= "string" or spec.id == "" then
        error("RegisterMigration: spec.id must be a non-empty string", 2)
    end
    if type(spec.body) ~= "function" then
        error("RegisterMigration: spec.body must be a function", 2)
    end
    if not VALID_SCOPES[spec.scope] then
        error("RegisterMigration: spec.scope must be 'global' or 'profile' (got '"
              .. tostring(spec.scope) .. "')", 2)
    end
    if _migrationsById[spec.id] then
        error("RegisterMigration: duplicate migration id '" .. spec.id .. "'", 2)
    end
    _migrations[#_migrations + 1] = spec
    _migrationsById[spec.id]      = spec
end

local function GetFlagTable(host)
    if not host._migrations then host._migrations = {} end
    return host._migrations
end

local function RunOne(spec, ctx, flagHost)
    local flags = GetFlagTable(flagHost)
    if flags[spec.id] then return end

    local ok, err = pcall(spec.body, ctx)
    if ok then
        flags[spec.id] = true
    else
        -- Deliberately not stamped: a body that errored gets another chance
        -- next login rather than leaving the data half-migrated forever.
        _errors[#_errors + 1] = {
            id    = spec.id,
            scope = spec.scope,
            err   = tostring(err),
        }
        -- Say something: an unstamped body retries every login, so a silent
        -- failure would repeat forever without anyone finding out.
        if SP.Debug then SP:Debug("Migration", spec.id, tostring(err)) end
    end
end

-- Runs every registered migration against the raw SavedVariables table.
-- Must be called BEFORE AceDB:New, so the defaults are not copied on top of
-- data we are about to rewrite.
function SP.RunMigrations(sv)
    if type(sv) ~= "table" then return end

    for _, spec in ipairs(_migrations) do
        if spec.scope == "global" then
            RunOne(spec, { db = sv }, sv)
        elseif spec.scope == "profile" then
            local profiles = sv.profiles
            if type(profiles) == "table" then
                for name, profile in pairs(profiles) do
                    if type(profile) == "table" then
                        RunOne(spec, { profile = profile, profileName = name }, profile)
                    end
                end
            end
        end
    end

    sv._dbVersion = SP.DB_VERSION
end

-- ============================================================
-- Registered migrations
-- ============================================================

-- Sections belonging to features that no longer exist. AceDB rawsets defaults
-- into the saved table, so these were being written to disk on every logout for
-- every profile long after the code that read them was deleted.
SP.RegisterMigration({
    id    = "prune_dead_sections_2026_08",
    scope = "profile",
    body  = function(ctx)
        local p = ctx.profile
        -- Never read by any module or by the GUI (51 + 60 keys).
        p.interruptTracker = nil
        p.mythicCast       = nil
        -- Modules removed in earlier versions.
        p.autoPI           = nil
        p.autoInnervate    = nil
        p.combatLog        = nil
        p.petStatus        = nil
    end,
})

-- potionAlert.playSound / soundKey were saved settings with no implementation
-- and no GUI row -- the module never called PlaySound.
SP.RegisterMigration({
    id    = "prune_potionalert_sound_2026_08",
    scope = "profile",
    body  = function(ctx)
        local pa = ctx.profile.potionAlert
        if type(pa) ~= "table" then return end
        pa.playSound = nil
        pa.soundKey  = nil
    end,
})
