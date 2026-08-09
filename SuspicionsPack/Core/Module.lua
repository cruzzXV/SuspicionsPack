-- SuspicionsPack — Module lifecycle mixin
--
-- Three different enable/disable contracts had grown side by side across the
-- 30 modules:
--   * 17 drive AceAddon's own Enable/Disable from Refresh()
--   * 11 hand-roll Activate()/Deactivate() and ignore AceAddon's state
--   *  2 have only an ad-hoc Refresh() and no OnDisable at all
-- Several use two of them at once, which is why MicroMenuSkin ended up calling
-- both self:Disable() AND self:Deactivate() -- belt and braces, because the
-- contract was ambiguous.
--
-- This is the single contract for new modules, and the target shape for the
-- old ones. A module implements only Activate / Deactivate / ApplySettings;
-- everything else comes from here.
--
--   local MyMod = SP:NewSPModule("MyMod", "myMod")
--
--   function MyMod:Activate()   -- create frames, register events, show
--   function MyMod:Deactivate() -- hide, unregister, release
--
-- WHAT YOU GET
--   GetDB()      -> SP.GetDB()[dbKey], nil-safe before OnInitialize
--   IsOn()       -> the user's setting, not AceAddon's flag
--   Refresh()    -> Activate or Deactivate depending on IsOn()
--   OnEnable()   -> deferred to PLAYER_LOGIN when needed, then Refresh()
--   OnDisable()  -> UnregisterAllEvents + Deactivate
--
-- WHY THE db.enabled GATE MATTERS
--   AceAddon has defaultModuleState = true and nothing here calls
--   SetDefaultModuleState(false), so EVERY module is Ace-enabled at login
--   regardless of the user's setting. `self:IsEnabled()` therefore says
--   nothing about whether the user wants the feature -- only `db.enabled`
--   does. Modules that confused the two ended up doing their work while
--   switched off (Automation ran seven of its nine features with the master
--   toggle off; TankMD did nothing until a /reload because it waited on an
--   IsEnabled() transition that never came).

local SP = SuspicionsPack

-- ============================================================
-- The mixin
-- ============================================================
local ModuleMixin = {}
SP.ModuleMixin = ModuleMixin

function ModuleMixin:GetDB()
    local db = SP.GetDB()
    return db and db[self.dbKey]
end

-- The user's setting. Deliberately NOT self:IsEnabled(), which is AceAddon's
-- own flag and is true for every module at login.
function ModuleMixin:IsOn()
    local db = self:GetDB()
    return (db and db.enabled) and true or false
end

-- Default no-ops so a module only has to implement what it actually needs.
function ModuleMixin:Activate()   end
function ModuleMixin:Deactivate() end

function ModuleMixin:Refresh()
    if self:IsOn() then
        -- Re-Enable first: the login sweep may have Ace-disabled this module,
        -- and OnEnable is where some modules do one-time setup. Without this a
        -- module switched on from the GUI would Activate while still flagged
        -- disabled, and IsEnabled() would lie about a live module.
        if self.IsEnabled and not self:IsEnabled() then
            self:Enable()   -- AceAddon's Enable -> OnEnable -> Refresh -> Activate
            return
        end
        self:Activate()
    else
        self:Deactivate()
        if self.IsEnabled and self:IsEnabled() then
            self:Disable()  -- -> OnDisable -> UnregisterAllEvents + Deactivate
        end
    end
end

function ModuleMixin:OnEnable()
    -- Frames and player data are not reliable before PLAYER_LOGIN, and
    -- OnEnable can fire earlier than that.
    if IsLoggedIn() then
        self:Refresh()
    else
        self:RegisterEvent("PLAYER_LOGIN", "OnSPLogin")
    end
end

function ModuleMixin:OnSPLogin()
    self:UnregisterEvent("PLAYER_LOGIN")
    self:Refresh()
end

function ModuleMixin:OnDisable()
    self:UnregisterAllEvents()
    self:Deactivate()
end

-- ============================================================
-- Factory
-- ============================================================
-- Same signature as SP:NewModule plus the DB key, and returns the module so
-- the call site reads exactly like the AceAddon one it replaces.
function SP:NewSPModule(name, dbKey, ...)
    local mod = self:NewModule(name, "AceEvent-3.0", ...)
    mod.dbKey = dbKey
    for k, v in pairs(ModuleMixin) do
        -- Never clobber something the module defined for itself: the module
        -- file loads after this and may already carry its own Activate.
        if mod[k] == nil then mod[k] = v end
    end
    return mod
end

-- ============================================================
-- Alert frame factory
--
-- Eight modules each hand-rolled the same "styled text at an anchor that pulses
-- and hides itself" frame: create a frame, size it, anchor it, set a strata and
-- level, disable the mouse, add a centred FontString, apply font/outline/colour,
-- and optionally attach a BOUNCE alpha animation. ~144 duplicated lines, and
-- they had already drifted -- some set SetMouseClickEnabled, some didn't; some
-- defaulted the outline to "" and some to "OUTLINE".
--
--   local f, txt = SP.CreateAlertFrame("SP_MyAlert", db, {
--       defaultY = -200, defaultSize = 20, defaultOutline = "OUTLINE",
--       defaultColor = { 1, 0.5, 0.2, 1 }, text = "REPAIR NOW",
--       pulse = { from = 1, to = 0.25, duration = 0.6 },
--   })
--
-- Returns frame, fontString. The pulse animation group, when requested, is on
-- frame.pulseAG.
-- ============================================================
function SP.CreateAlertFrame(globalName, db, opts)
    opts = opts or {}
    db   = db or {}

    local f = CreateFrame("Frame", globalName, UIParent)
    f:SetSize(opts.width or 200, opts.height or 30)
    f:SetFrameLevel(opts.frameLevel or 200)
    f:EnableMouse(false)
    if f.SetMouseClickEnabled then f:SetMouseClickEnabled(false) end
    f:Hide()

    SP.ApplyAnchor(f, db, opts.defaultX or 0, opts.defaultY or 0,
                   opts.defaultStrata or "HIGH")

    local txt = f:CreateFontString(nil, "OVERLAY")
    txt:SetPoint("CENTER", f, "CENTER", 0, 0)
    txt:SetJustifyH("CENTER")

    -- "NONE" is the GUI's word for no outline; SetFont wants an empty string.
    local outline = db.fontOutline
    if outline == nil or outline == "NONE" then
        outline = opts.defaultOutline or ""
    end
    -- SetFontSafe, not SetFont: at login an addon's own .ttf is sometimes not
    -- loadable yet, and a failed SetFont changes NOTHING -- the FontString keeps
    -- the size it was created with, silently and without an error. This factory
    -- is shared by eight modules, so the one line covers all of them.
    SP.SetFontSafe(txt, SP.ResolveFont(db.fontFace),
                   db.fontSize or opts.defaultSize or 20, outline)

    local c = db.color or opts.defaultColor or { 1, 1, 1, 1 }
    txt:SetTextColor(c[1], c[2], c[3], c[4] or 1)

    if opts.text then txt:SetText(opts.text) end

    local p = opts.pulse
    if p then
        local ag = f:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(p.from or 1)
        a:SetToAlpha(p.to or 0.25)
        a:SetDuration(p.duration or 0.6)
        a:SetSmoothing("IN_OUT")
        ag:Play()
        f.pulseAG = ag
    end

    f.text = txt
    return f, txt
end

-- ============================================================
-- Module name -> profile DB section, and the login sweep
--
-- The sweep was tried once before the modules were converted and had to be
-- reverted: AceAddon's flag and db.enabled were two different truths, modules
-- revived themselves through Refresh without ever calling Enable, and two of
-- them shadowed AceAddon's Disable with their own function. All three causes
-- are gone now -- every module is on ModuleMixin, where db.enabled is the only
-- truth and Activate/Deactivate are the only lifecycle.
--
-- AutoBuy is absent on purpose: its settings live in the per-character DB, and
-- it carries its own GetDB override. The sweep only walks the profile.
-- ============================================================

-- Reconciles AceAddon's per-module flag with the user's setting at login.
--
-- AceAddon enables every module regardless of db.enabled, so without this a
-- module the user switched off still ran its OnEnable and registered its
-- events every session. Only ever DISABLES: a module the user wants on has
-- already been started by its own OnEnable, and re-running Refresh would
-- pointlessly re-Activate it.
--
-- Safe now that every module is on ModuleMixin: Disable is always AceAddon's
-- (no module shadows it), OnDisable always routes to Deactivate, and the GUI
-- toggle always goes through Refresh, which re-Enables through the mixin.
function SP:ApplyModuleEnabledStates()
    local db = SP.GetDB()
    if not db then return end

    for _, mod in self:IterateModules() do
        -- Modules built by NewSPModule carry their own dbKey. Anything else
        -- (MinimapButton) has no enable setting and is skipped.
        local key = mod.dbKey
        local mdb = key and db[key]
        if mdb and mdb.enabled == false and mod.IsEnabled and mod:IsEnabled() then
            mod:Disable()
        end
    end
end
