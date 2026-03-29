-- SuspicionsPack — Recuperate
local SP = SuspicionsPack

local REC = SP:NewModule("Recuperate", "AceEvent-3.0")
SP.Recuperate = REC

local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

REC.GlowTypes = { "none", "pixel", "autocast", "button", "proc" }

local function StopGlow(btn, proxy)
    if not LCG then LCG = LibStub and LibStub("LibCustomGlow-1.0", true) end
    if not LCG then return end
    for _, f in ipairs({ btn, proxy }) do
        if f then
            LCG.PixelGlow_Stop(f,    "recGlow")
            LCG.AutoCastGlow_Stop(f, "recGlow")
            LCG.ButtonGlow_Stop(f)
            LCG.ProcGlow_Stop(f,     "recGlow")
        end
    end
end

local function StartGlow(btn, proxy, glowType, color, size)
    if not LCG then LCG = LibStub and LibStub("LibCustomGlow-1.0", true) end
    if not LCG or not glowType or glowType == "none" then return end
    local c  = color or { 0, 1, 0.2, 1 }
    local sz = size  or 2
    if glowType == "pixel" then
        if btn then LCG.PixelGlow_Start(btn, c, 8, 0.25, 10, sz, 0, 0, false, "recGlow") end
    elseif glowType == "autocast" then
        if btn then LCG.AutoCastGlow_Start(btn, c, 8, 0.25, sz / 4, 0, 0, "recGlow") end
    elseif glowType == "button" then
        if proxy then LCG.ButtonGlow_Start(proxy, c, 0) end
    elseif glowType == "proc" then
        if proxy then LCG.ProcGlow_Start(proxy, { color = c, startAnim = false, duration = 1, key = "recGlow" }) end
    end
end

function REC:ApplyGlow()
    local db       = SP.GetDB and SP.GetDB().recuperate
    local glowType = (db and db.glowType)  or "pixel"
    local gr, gg, gb = SP.GetColorFromSource(
        (db and db.glowColorSource) or "custom",
        (db and db.glowColor) or { 0, 1, 0.2 })
    local glowColor = { gr, gg, gb, 1 }
    local glowSize  = (db and db.glowSize)  or 2
    if self.glowProxy and self.button then
        local btnSz = (db and db.size) or 40
        if glowType == "button" or glowType == "proc" then
            local pad = math.max(0, (glowSize - 1) * 4)
            self.glowProxy:ClearAllPoints()
            self.glowProxy:SetPoint("CENTER", self.button, "CENTER", 0, 0)
            self.glowProxy:SetSize(btnSz + pad * 2, btnSz + pad * 2)
        else
            self.glowProxy:ClearAllPoints()
            self.glowProxy:SetAllPoints(self.button)
        end
    end
    StopGlow(self.button, self.glowProxy)
    StartGlow(self.button, self.glowProxy, glowType, glowColor, glowSize)
end

local CreateFrame           = CreateFrame
local RegisterStateDriver   = RegisterStateDriver
local UnregisterStateDriver = UnregisterStateDriver
local UnitHealth            = UnitHealth
local UnitHealthMax         = UnitHealthMax
local UnitIsDeadOrGhost     = UnitIsDeadOrGhost
local InCombatLockdown      = InCombatLockdown
local UIParent              = UIParent
local C_Spell               = C_Spell

local RECUPERATE_SPELL_ID = 1231411
local VISIBILITY_STRING   = "[combat] hide; [dead] hide; show"

local function GetDB()
    return SP.GetDB().recuperate
end

REC.button       = nil
REC.isPreview    = false
REC.isDragMode   = false
REC._syncSliders = nil

function REC:UpdateAlpha(event, unit)
    if event == "UNIT_HEALTH" and unit ~= "player" then return end
    local btn = self.button
    if not btn or self.isPreview or self.isDragMode then return end

    if UnitIsDeadOrGhost("player") then btn:SetAlpha(0); return end

    local cur = UnitHealth("player")
    local max = UnitHealthMax("player")
    if not max or max == 0 or not cur then return end
    -- pcall: UnitHealth() can return a secret number in tainted threads
    local ok, pct = pcall(function() return (cur / max) * 100 end)
    if not ok then btn:SetAlpha(0); return end

    btn:SetAlpha(pct >= 50 and 0 or (50 - pct) / 50)
end

function REC:CreateButton()
    if self.button then return end
    local db   = GetDB()
    local size = db.size or 40

    local btn = CreateFrame("Button", "SP_RecuperateButton", UIParent,
        "SecureActionButtonTemplate,SecureHandlerStateTemplate")
    btn:SetSize(size, size)
    btn:SetMovable(true)
    btn:Hide()

    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type",  "spell")
    btn:SetAttribute("spell", RECUPERATE_SPELL_ID)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(btn)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local spellInfo = C_Spell.GetSpellInfo(RECUPERATE_SPELL_ID)
    if spellInfo and spellInfo.iconID then
        icon:SetTexture(spellInfo.iconID)
    end

    local function MakeBorderLine(point, relPoint, w, h)
        local t = btn:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0, 0, 0, 1)
        t:SetSize(w, h)
        t:SetPoint(point, btn, relPoint, 0, 0)
    end
    MakeBorderLine("TOPLEFT",    "TOPLEFT",    size, 1)
    MakeBorderLine("BOTTOMLEFT", "BOTTOMLEFT", size, 1)
    MakeBorderLine("TOPLEFT",    "TOPLEFT",    1,    size)
    MakeBorderLine("TOPRIGHT",   "TOPRIGHT",   1,    size)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn)
    hl:SetColorTexture(1, 1, 1, 0.2)
    hl:SetBlendMode("ADD")

    btn:SetScript("OnEnter", function(self2)
        GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(RECUPERATE_SPELL_ID)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local movLbl = btn:CreateFontString(nil, "OVERLAY")
    movLbl:SetPoint("TOP", btn, "BOTTOM", 0, -4)
    movLbl:SetFont("Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf", 10, "")
    movLbl:SetText("Drag to reposition")
    movLbl:SetTextColor(1, 0.82, 0.0, 1)
    movLbl:Hide()
    btn.movableLbl = movLbl

    btn:SetScript("OnDragStart", function(self2) self2:StartMoving() end)
    btn:SetScript("OnDragStop",  function(self2)
        self2:StopMovingOrSizing()
        local db2 = GetDB()
        if db2 then
            local cx, cy   = self2:GetCenter()
            local ucx, ucy = UIParent:GetCenter()
            db2.x = math.floor(cx - ucx + 0.5)
            db2.y = math.floor(cy - ucy + 0.5)
            if REC._syncSliders then REC._syncSliders(db2.x, db2.y) end
        end
    end)
    btn:EnableMouse(true)
    btn:SetMouseClickEnabled(true)

    self.button = btn

    local proxy = CreateFrame("Frame", nil, btn)
    proxy:SetAllPoints(btn)
    self.glowProxy = proxy

    self:ApplySettings()
    self:ApplyGlow()
end

function REC:ApplySettings()
    if not self.button then return end
    local db   = GetDB()
    local size = db.size or 40
    self.button:SetSize(size, size)
    self.button:ClearAllPoints()
    local anchorFrom  = db.anchorFrom  or "CENTER"
    local anchorTo    = db.anchorTo    or "CENTER"
    local anchorFrame = _G[db.anchorFrame or "UIParent"] or UIParent
    self.button:SetPoint(anchorFrom, anchorFrame, anchorTo, db.x or 0, db.y or 0)
    self.button:SetFrameStrata(db.frameStrata or "HIGH")
end

function REC:ShowPreview()
    if not self.button then self:CreateButton() end
    self.isPreview = true
    if not InCombatLockdown() then
        UnregisterStateDriver(self.button, "visibility")
        self.button:Show()
    end
    self.button:SetAlpha(1)
    self.button:RegisterForDrag("LeftButton")
    if self.button.movableLbl then self.button.movableLbl:Show() end
    self:ApplySettings()
end

function REC:HidePreview()
    self.isPreview = false
    if not self.button then return end
    if not self.isDragMode then
        self.button:RegisterForDrag()
        if self.button.movableLbl then self.button.movableLbl:Hide() end
    end
    if self.isDragMode then return end
    local db = GetDB()
    if db and db.enabled and not InCombatLockdown() then
        RegisterStateDriver(self.button, "visibility", VISIBILITY_STRING)
        C_Timer.After(0, function() if REC.button then REC:UpdateAlpha() end end)
    else
        self.button:Hide()
    end
end

function REC:StartDragMode()
    if not self.button then self:CreateButton() end
    self.isDragMode = true
    if not InCombatLockdown() then
        UnregisterStateDriver(self.button, "visibility")
        self.button:Show()
    end
    self.button:SetAlpha(1)
    self.button:RegisterForDrag("LeftButton")
    if self.button.movableLbl then self.button.movableLbl:Show() end
    self:ApplySettings()
end

function REC:EndDragMode()
    self.isDragMode = false
    if not self.button then return end
    if not self.isPreview then
        self.button:RegisterForDrag()
        if self.button.movableLbl then self.button.movableLbl:Hide() end
    end
    if self.isPreview then return end
    local db = GetDB()
    if db and db.enabled and not InCombatLockdown() then
        RegisterStateDriver(self.button, "visibility", VISIBILITY_STRING)
        C_Timer.After(0, function() if REC.button then REC:UpdateAlpha() end end)
    else
        self.button:Hide()
    end
end

function REC:Activate()
    local db = GetDB()
    if not db or not db.enabled then return end
    if InCombatLockdown() then return end

    self:CreateButton()
    self:ApplySettings()

    RegisterStateDriver(self.button, "visibility", VISIBILITY_STRING)

    self:RegisterEvent("UNIT_HEALTH",           "UpdateAlpha")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateAlpha")
    self:RegisterEvent("PLAYER_REGEN_ENABLED",  "UpdateAlpha")
    self:RegisterEvent("PLAYER_ALIVE",          "UpdateAlpha")
    self:RegisterEvent("PLAYER_UNGHOST",        "UpdateAlpha")

    -- Defer to next frame — RegisterStateDriver taints the current thread
    C_Timer.After(0, function() if REC.button then REC:UpdateAlpha() end end)
end

function REC:Deactivate()
    if self.button and not InCombatLockdown() then
        UnregisterStateDriver(self.button, "visibility")
        self.button:Hide()
    end
    self.isPreview  = false
    self.isDragMode = false
    self:UnregisterAllEvents()
end

function REC.Refresh()
    local db = GetDB()
    if db and db.enabled then REC:Activate() else REC:Deactivate() end
end

function REC:OnEnable()
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

function REC:OnDisable()
    self:Deactivate()
end
