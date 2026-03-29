-- SuspicionsPack - CombatTimer.lua
-- Displays a running combat timer on-screen.
-- Forked from NorskenUI's CombatTimer.lua.
-- Positioning: simple X/Y offset from screen CENTER (no anchor system needed).

local SP = SuspicionsPack

local CT = SP:NewModule("CombatTimer", "AceEvent-3.0")
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

local SP_FONT = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"
local BLANK   = "Interface\\Buttons\\WHITE8X8"

-- Available font faces for the timer text
local FONT_FACES = {
    ["Expressway"]    = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf",
    ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
    ["Arial Narrow"]  = "Fonts\\ARIALN.TTF",
    ["Morpheus"]      = "Fonts\\MORPHEUS.TTF",
    ["Skurri"]        = "Fonts\\SKURRI.TTF",
    ["Damage"]        = "Fonts\\DAMAGE.TTF",
    ["Ambiguity"]     = "Fonts\\2002.TTF",
    ["Nimrod MT"]     = "Fonts\\NIMROD.TTF",
}
CT.FontFaceOrder = {
    "Expressway", "Friz Quadrata", "Arial Narrow", "Morpheus",
    "Skurri", "Damage", "Ambiguity", "Nimrod MT",
}

local function GetFontPath(name)
    return FONT_FACES[name]
        or (SP.GetFontPath and SP.GetFontPath(name))
        or SP_FONT
end

-- ============================================================
-- DB helper
-- ============================================================
local function GetDB()
    return SP.GetDB().combatTimer
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
    local db = GetDB()

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
    text:SetFont(fontPath, db.fontSize or 18, db.outline or "SOFTOUTLINE")
    text:SetText("00:00")
    text:SetJustifyH("CENTER")

    -- "MOVABLE" accent label — shown only during preview
    local movableLbl = f:CreateFontString(nil, "OVERLAY")
    movableLbl:SetPoint("TOP", f, "TOP", 0, 14)
    movableLbl:SetFont(FONT_FACES["Expressway"] or SP_FONT, 8, "OUTLINE")
    movableLbl:SetTextColor(1, 0.82, 0, 1)
    movableLbl:SetText("MOVABLE")
    movableLbl:Hide()
    f.movableLbl = movableLbl

    -- Drag support — only active during preview; saves position to DB on release
    f:SetMovable(true)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db2 = GetDB()
        if db2 then
            local cx,  cy  = self:GetCenter()
            local ucx, ucy = UIParent:GetCenter()
            db2.anchorFrom  = "CENTER"
            db2.anchorTo    = "CENTER"
            db2.anchorFrame = "UIParent"
            db2.x           = math.floor(cx - ucx + 0.5)
            db2.y           = math.floor(cy - ucy + 0.5)
        end
    end)
    -- Mouse disabled by default; enabled only during preview
    f:EnableMouse(false)
    f:SetMouseClickEnabled(false)

    self.frame = f
    self.text  = text
end

-- ============================================================
-- Apply all settings from DB
-- ============================================================
function CT:ApplySettings()
    local db = GetDB()
    if not self.text then return end

    -- Cache the refresh rate so OnUpdate never needs a DB lookup per frame
    self._cachedRate = GetRefreshRate(db.format or "MM:SS")

    -- Font face + size + outline
    local fontPath = GetFontPath(db.fontFace or "Expressway")
    self.text:SetFont(fontPath, db.fontSize or 18, db.outline or "SOFTOUTLINE")

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

    -- Color depending on state (respects colorSource setting)
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
    local db = GetDB()
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
    local db = GetDB()
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
    local db    = GetDB()
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
-- OnUpdate throttle
-- ============================================================
function CT:OnUpdate(elapsed)
    if not self.running and not self.isPreview then return end
    self.elapsed = (self.elapsed or 0) + elapsed
    -- Use cached rate (set in ApplySettings) to avoid a DB lookup every frame
    local rate = self._cachedRate or 0.25
    if self.elapsed < rate then return end
    self.elapsed = self.elapsed - rate
    self:UpdateText()
end

-- ============================================================
-- Combat events
-- ============================================================
function CT:OnEnterCombat()
    local db = GetDB()
    if self.running or not db.enabled then return end

    self.startTime = GetTime()
    self.running   = true
    self.isPreview = false
    SP.lastCombatDuration = 0
    self.lastText  = ""

    if self.frame then
        -- Disable drag + hide MOVABLE label when real combat starts
        self.frame:EnableMouse(false)
        self.frame:SetMouseClickEnabled(false)
        if self.frame.movableLbl then self.frame.movableLbl:Hide() end
        self.frame:Show()
    end
    self:ApplySettings()
    self:UpdateText()
end

function CT:OnExitCombat()
    if not self.running then return end

    SP.lastCombatDuration = GetTime() - self.startTime
    self.running   = false
    self.startTime = 0

    local db  = GetDB()
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

    -- Hide the timer unless the player wants to keep the last duration visible.
    -- If the preview button is active it stays visible (isPreview check in ShowPreview).
    if not self.isPreview then
        if self.frame and not db.showLastDuration then
            self.frame:Hide()
        end
    end
end

-- ============================================================
-- Preview (called from GUI "Preview" button)
-- ============================================================
function CT:ShowPreview()
    if not self.frame then self:CreateTimerFrame() end
    self.isPreview = true
    -- Enable drag during preview
    self.frame:EnableMouse(true)
    self.frame:SetMouseClickEnabled(true)
    self.frame:RegisterForDrag("LeftButton")
    if self.frame.movableLbl then self.frame.movableLbl:Show() end
    self.frame:Show()
    self:ApplySettings()
end

function CT:HidePreview()
    self.isPreview = false
    -- Disable drag + hide label
    if self.frame then
        self.frame:EnableMouse(false)
        self.frame:SetMouseClickEnabled(false)
        if self.frame.movableLbl then self.frame.movableLbl:Hide() end
        -- Always hide the frame when not actively in combat
        if not self.running then self.frame:Hide() end
    end
end

-- ============================================================
-- Activate / Deactivate — called by GUI enable toggle
-- ============================================================
function CT:Activate()
    local db = GetDB()
    if not db.enabled then return end

    self:CreateTimerFrame()
    self:ApplySettings()
    C_Timer.After(0.5, function()
        if self.frame then self:ApplyPosition() end
    end)

    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEnterCombat")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",  "OnExitCombat")

    self.frame:SetScript("OnUpdate", function(_, elapsed)
        self:OnUpdate(elapsed)
    end)

    -- Do NOT show the frame here — it only appears during active combat.
    -- OnEnterCombat will show it when the player enters combat.
end

function CT:Deactivate()
    if self.frame then
        self.frame:SetScript("OnUpdate", nil)
        self.frame:Hide()
    end
    self.running   = false
    self.isPreview = false
    self:UnregisterAllEvents()
end

-- Called from GUI toggle (mirrors other modules' .Refresh pattern)
function CT.Refresh()
    local db = GetDB()
    if db.enabled then
        CT:Activate()
    else
        CT:Deactivate()
    end
end

-- ============================================================
-- AceAddon lifecycle
-- ============================================================
function CT:OnEnable()
    if IsLoggedIn() then
        local db = GetDB()
        if db and db.enabled then self:Activate() end
    else
        self:RegisterEvent("PLAYER_LOGIN", function()
            local db = GetDB()
            if db and db.enabled then self:Activate() end
        end)
    end
end

function CT:OnDisable()
    self:Deactivate()
end
