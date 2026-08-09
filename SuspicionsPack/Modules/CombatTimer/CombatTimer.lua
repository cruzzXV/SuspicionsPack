-- SuspicionsPack - CombatTimer.lua
-- Affiche un timer de combat à l'écran.

local SP = SuspicionsPack

local CT = SP:NewSPModule("CombatTimer", "combatTimer")
SP.CombatTimer = CT

-- ============================================================
-- Locals
-- ============================================================
local CreateFrame    = CreateFrame
local GetTime        = GetTime
local math_floor     = math.floor
local math_max       = math.max
local string_format  = string.format
local C_Timer        = C_Timer
local UIParent       = UIParent

local BLANK   = SP.BLANK


-- Font names now resolve through Core: SP.FONT_FACES is the single
-- source of truth and SP.ResolveFont falls back to the pack default.
-- The private table this used to carry SHADOWED LibSharedMedia, so any
-- font the user added via another addon silently became Expressway here.
local function GetFontPath(name)
    return SP.ResolveFont(name)
end

-- ============================================================
-- Module state
-- ============================================================
CT.frame     = nil
CT.text      = nil
CT.startTime = 0
CT.running   = false
CT.lastText  = ""
CT.isPreview = false

SP.lastCombatDuration = 0

-- ============================================================
-- Helpers
-- ============================================================
local function FormatTime(total, fmt)
    local mins = math_floor(total / 60)
    local secs = math_floor(total % 60)
    if fmt == "MM:SS:MS" then
        local ms = math_floor((total - math_floor(total)) * 10)
        return string_format("%02d:%02d.%d", mins, secs, ms)
    end
    return string_format("%02d:%02d", mins, secs)
end

local function GetRefreshRate(fmt)
    return (fmt == "MM:SS:MS") and 0.1 or 0.25
end

-- ============================================================
-- Frame creation
-- ============================================================
function CT:CreateTimerFrame()
    if self.frame then return end
    local db = self:GetDB()

    local f = CreateFrame("Frame", "SP_CombatTimerFrame", UIParent, "BackdropTemplate")
    f:SetSize(80, 30)
    f:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 250)
    f:SetFrameStrata(db.frameStrata or "TOOLTIP")
    f:SetFrameLevel(100)
    f:EnableMouse(false)
    f:SetMouseClickEnabled(false)
    f:Hide()

    local fontPath = GetFontPath(db.fontFace or "Expressway")
    local text = f:CreateFontString("SP_CombatTimerText", "OVERLAY")
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    SP.SetFontSafe(text, fontPath, db.fontSize or 18, db.outline or "SOFTOUTLINE")
    text:SetText("00:00")
    text:SetJustifyH("CENTER")

    self.frame = f
    self.text  = text
end

-- ============================================================
-- Apply all settings from DB
-- ============================================================
function CT:ApplySettings()
    local db = self:GetDB()
    if not self.text then return end

    self._cachedRate = GetRefreshRate(db.format or "MM:SS")

    local fontPath = GetFontPath(db.fontFace or "Expressway")
    SP.SetFontSafe(self.text, fontPath, db.fontSize or 18, db.outline or "SOFTOUTLINE")

    -- Font shadow
    if db.shadowEnabled then
        local sr, sg, sb = SP.GetColorFromSource(db.shadowColorSource or "custom", db.shadowColor or { 0, 0, 0 })
        self.text:SetShadowColor(sr, sg, sb, 1)
        self.text:SetShadowOffset(db.shadowX or 1, db.shadowY or -1)
    else
        self.text:SetShadowColor(0, 0, 0, 0)
        self.text:SetShadowOffset(0, 0)
    end

    -- Frame strata
    if self.frame then
        self.frame:SetFrameStrata(db.frameStrata or "TOOLTIP")
    end

    local cr, cg, cb
    if self.running then
        cr, cg, cb = SP.GetColorFromSource(db.colorInCombatSource or "custom",
            db.colorInCombat or { 1, 0.2, 0.2 })
    else
        cr, cg, cb = SP.GetColorFromSource(db.colorOutOfCombatSource or "custom",
            db.colorOutOfCombat or { 1, 1, 1 })
    end
    self.text:SetTextColor(cr, cg, cb, 1)

    -- Backdrop
    if self.frame then
        local bd = db.backdrop or {}
        if bd.enabled then
            local bSize = bd.borderSize or 1
            self.frame:SetBackdrop({
                bgFile   = BLANK, edgeFile = BLANK,
                tile = false, tileSize = 0,
                edgeSize = bSize,
                insets   = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            local c  = bd.color       or { 0, 0, 0, 0.6 }
            local bc = bd.borderColor or { 0, 0, 0, 1 }
            self.frame:SetBackdropColor(c[1], c[2], c[3], c[4] or 0.6)
            self.frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
        else
            self.frame:SetBackdrop(nil)
        end
    end

    self:UpdateFrameSize()
    self:UpdateText()
    self:ApplyPosition()
end

-- ============================================================
-- Position
-- ============================================================
function CT:ApplyPosition()
    if not self.frame then return end
    local db = self:GetDB()
    self.frame:ClearAllPoints()
    local anchorFrom  = db.anchorFrom  or "CENTER"
    local anchorTo    = db.anchorTo    or "CENTER"
    local anchorFrame = _G[db.anchorFrame or "UIParent"] or UIParent
    self.frame:SetPoint(anchorFrom, anchorFrame, anchorTo, db.x or 0, db.y or 250)
end

-- ============================================================
-- Frame sizing (auto-fit text + padding)
-- ============================================================
function CT:UpdateFrameSize()
    if not self.frame or not self.text then return end
    local db = self:GetDB()
    local bd = db.backdrop or {}
    local pw = bd.paddingW or 10
    local ph = bd.paddingH or 6
    local w  = math_max((self.text:GetStringWidth()  or 0) + pw * 2, 40)
    local h  = math_max((self.text:GetStringHeight() or 0) + ph * 2, 20)
    self.frame:SetSize(math_floor(w), math_floor(h))
end

-- ============================================================
-- Text update
-- ============================================================
function CT:UpdateText()
    if not self.text then return end
    local db    = self:GetDB()
    local total = self.running
        and (self.startTime > 0 and (GetTime() - self.startTime) or 0)
        or  (SP.lastCombatDuration or 0)

    local s = FormatTime(total, db.format or "MM:SS")
    if s ~= self.lastText then
        self.text:SetText(s)
        self.lastText = s
        self:UpdateFrameSize()
    end
end

-- ============================================================
-- Tick
--
-- The label needs 4 Hz (or 10 Hz with tenths). It used to be driven by a
-- per-frame OnUpdate that threw away ~56 of every 60 calls, armed in Activate()
-- and removed only in Deactivate() -- so with "show last duration" on it kept
-- running out of combat for the whole session.
--
-- Now it subscribes to the shared ticker only while the clock is actually
-- counting, and unsubscribes itself the moment it isn't.
-- ============================================================
local TICK_KEY = "combatTimer"

function CT:StartTicking()
    SP.Tick.Add(TICK_KEY, function(dt)
        -- Self-disarm: whoever cleared `running` does not have to remember to
        -- unsubscribe.
        --
        -- Preview is deliberately NOT a reason to tick: in preview `running` is
        -- false, so UpdateText renders the frozen SP.lastCombatDuration -- the
        -- old handler redrew that identical string 60 times a second.
        if not self.running then
            SP.Tick.Remove(TICK_KEY)
            return
        end
        self.elapsed = (self.elapsed or 0) + dt
        local rate = self._cachedRate or 0.25
        if self.elapsed < rate then return end
        self.elapsed = self.elapsed - rate
        self:UpdateText()
    end)
end

function CT:StopTicking()
    SP.Tick.Remove(TICK_KEY)
end

-- ============================================================
-- Combat events
-- ============================================================
function CT:OnEnterCombat()
    local db = self:GetDB()
    if self.running or not db.enabled then return end

    self.startTime        = GetTime()
    self.running          = true
    self.isPreview        = false
    SP.lastCombatDuration = 0
    self.lastText         = ""

    if self.frame then
        self.frame:EnableMouse(false)
        self.frame:SetMouseClickEnabled(false)
        self.frame:Show()
    end
    self:ApplySettings()
    self:UpdateText()
    self:StartTicking()
end

function CT:OnExitCombat()
    if not self.running then return end

    SP.lastCombatDuration = GetTime() - self.startTime
    self.running          = false
    self.startTime        = 0
    -- Clock stopped: the frozen final duration needs no per-frame work.
    self:StopTicking()

    local db  = self:GetDB()
    local dur = FormatTime(SP.lastCombatDuration, db.format or "MM:SS")
    if db.printToChat ~= false then
        local ac  = SP.Theme and SP.Theme.accent or { 1, 1, 1 }
        local hex = string_format("%02X%02X%02X",
            math_floor(ac[1] * 255 + 0.5),
            math_floor(ac[2] * 255 + 0.5),
            math_floor(ac[3] * 255 + 0.5))
        print("|cff" .. hex .. "Suspicion's|r Pack : Combat lasted " .. dur)
    end

    self:ApplySettings()
    self:UpdateText()

    if self.frame and not db.showLastDuration then
        self.frame:Hide()
    end
end

-- ============================================================
-- Preview (called from GUI "Preview" button)
-- ============================================================
function CT:ShowPreview()
    if not self.frame then self:CreateTimerFrame() end
    self.isPreview = true
    self.frame:Show()
    self:ApplySettings()
end

function CT:HidePreview()
    self.isPreview = false
    if self.frame then
        self.frame:Hide()
        -- Restore if the timer is genuinely running or showLastDuration is on
        local db = self:GetDB()
        if self.running or (db and db.showLastDuration) then
            self.frame:Show()
        end
    end
end

-- ============================================================
-- Activate / Deactivate
--
-- Called by the GUI enable toggle and by ModuleMixin:Refresh(). Refresh,
-- OnEnable and OnDisable all come from ModuleMixin -- see Core/Module.lua.
-- ============================================================
function CT:Activate()
    local db = self:GetDB()
    if not (db and db.enabled) then return end

    self:CreateTimerFrame()
    self:ApplySettings()
    C_Timer.After(0.5, function()
        if self.frame then self:ApplyPosition() end
    end)

    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEnterCombat")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",  "OnExitCombat")

    -- No OnUpdate here any more. The ticker is armed by OnEnterCombat and
    -- disarms itself when the clock stops -- so enabling the
    -- module no longer costs a per-frame dispatch for the rest of the session.
    -- Catch the case where the module is enabled mid-fight.
    if UnitAffectingCombat("player") then
        self:OnEnterCombat()
    elseif db.showLastDuration then
        self.frame:Show()
    end
end

function CT:Deactivate()
    self:StopTicking()
    if self.frame then
        self.frame:Hide()
    end
    self.running          = false
    self.isPreview        = false
    SP.lastCombatDuration = 0
    self:UnregisterAllEvents()
end
