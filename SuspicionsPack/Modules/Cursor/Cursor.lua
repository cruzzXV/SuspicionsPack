-- SuspicionsPack - Cursor.lua
-- Cercle curseur qui suit la souris.

local SP = SuspicionsPack

local Cursor = SP:NewSPModule("Cursor", "cursor")
SP.Cursor = Cursor

-- ============================================================
-- Constants
-- ============================================================
local MEDIA = "Interface\\AddOns\\SuspicionsPack\\Media\\CursorCircles\\"

Cursor.Textures = {
    ["Thin"]   = MEDIA .. "nauraThin.png",
    ["Medium"] = MEDIA .. "nauraMedium.png",
    ["Thick"]  = MEDIA .. "nauraThick.png",
    ["Aura 1"] = MEDIA .. "Aura73.tga",
    ["Aura 2"] = MEDIA .. "Aura103.tga",
    ["Circle"] = MEDIA .. "Circle.tga",
}
Cursor.TextureOrder = { "Thin", "Medium", "Thick", "Aura 1", "Aura 2", "Circle" }

-- ============================================================
-- DB helpers
-- ============================================================
local function GetDB()
    return SP.GetDB().cursor
end

-- ============================================================
-- Internal state
-- ============================================================
local mainFrame  = nil
local clickFrame = nil   -- second circle, visible only while mouse button held ≥ 150 ms

-- Declared up here, not next to PreviewClickCircle: Deactivate cancels it, and
-- a closure cannot see a `local` declared further down the file.
local _previewClickTimer = nil

-- ============================================================
-- Color helpers
-- ============================================================
local function GetCursorColor()
    local db  = GetDB()
    local src = db.colorSource or "theme"
    local T   = SP.Theme

    if src == "theme" then
        return T.accent[1], T.accent[2], T.accent[3]
    end

    if src == "class" then
        local _, cls = UnitClass("player")
        local c = RAID_CLASS_COLORS and cls and RAID_CLASS_COLORS[cls]
        if c then return c.r, c.g, c.b end
    end

    -- "custom"
    local cc = db.cursorColor or { 1, 1, 1 }
    return cc[1], cc[2], cc[3]
end

local function GetClickColor()
    local db  = GetDB()
    local src = db.clickColorSource or "theme"
    local T   = SP.Theme

    if src == "theme" then
        return T.accent[1], T.accent[2], T.accent[3]
    end

    if src == "class" then
        local _, cls = UnitClass("player")
        local c = RAID_CLASS_COLORS and cls and RAID_CLASS_COLORS[cls]
        if c then return c.r, c.g, c.b end
    end

    local cc = db.clickColor or { 1, 1, 1 }
    return cc[1], cc[2], cc[3]
end

-- ============================================================
-- Frame creation
-- ============================================================
local function CreateCursorFrame()
    if mainFrame then return end

    local db = GetDB()
    local sz = db.size or 50

    local texPath = Cursor.Textures[db.texture or "Thick"] or Cursor.Textures["Thick"]

    local f = CreateFrame("Frame", "SP_CursorCircle", UIParent)
    f:SetSize(sz, sz)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(200)
    f:EnableMouse(false)   -- must never intercept mouse clicks
    f:SetClampedToScreen(false)
    f:Hide()

    f.texture = f:CreateTexture(nil, "BACKGROUND")
    f.texture:SetAllPoints()
    f.texture:SetTexture(texPath)
    local r, g, b = GetCursorColor()
    f.texture:SetVertexColor(r, g, b, 0.9)

    local dotTex = f:CreateTexture(nil, "OVERLAY")
    dotTex:SetTexture(MEDIA .. "Click.tga")
    dotTex:SetPoint("CENTER", f, "CENTER", 0, 0)
    local dotSz = db.dotSize or 6
    dotTex:SetSize(dotSz, dotSz)
    dotTex:SetVertexColor(1, 1, 1, 1)
    if db.showDot then dotTex:Show() else dotTex:Hide() end
    f.dot = dotTex

    local clickSz   = db.clickSize   or 70
    local clickTex  = Cursor.Textures[db.clickTexture or "Thin"] or Cursor.Textures["Thin"]
    local cr, cg, cb = GetClickColor()

    local cf = CreateFrame("Frame", "SP_CursorClickCircle", UIParent)
    cf:SetSize(clickSz, clickSz)
    cf:SetFrameStrata("MEDIUM")
    cf:SetFrameLevel(199)
    cf:EnableMouse(false)
    cf:SetClampedToScreen(false)
    cf:Hide()

    cf.texture = cf:CreateTexture(nil, "BACKGROUND")
    cf.texture:SetAllPoints()
    cf.texture:SetTexture(clickTex)
    cf.texture:SetVertexColor(cr, cg, cb, 0)   -- start transparent

    clickFrame = cf

    local _lastCX, _lastCY = -1, -1
    local mouseHoldTime    = 0
    local updateElapsed    = 0
    f:SetScript("OnUpdate", function(frame, elapsed)
        local cdb0 = GetDB()
        if cdb0.limitUpdateRate then
            updateElapsed = updateElapsed + elapsed
            if updateElapsed < (cdb0.updateInterval or 0.016) then return end
            updateElapsed = 0
        end

        local x, y = GetCursorPosition()

        if x ~= _lastCX or y ~= _lastCY then
            _lastCX, _lastCY = x, y
            local scale = frame:GetEffectiveScale()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
            if clickFrame and clickFrame:IsShown() then
                local cscale = clickFrame:GetEffectiveScale()
                clickFrame:ClearAllPoints()
                clickFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / cscale, y / cscale)
            end
        end

        -- Click circle / replace logic
        local cdb = GetDB()
        if cdb.showClickCircle then
            local isDown = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
            local clickMode = cdb.clickMode or "overlay"

            if clickMode == "replace" then
                if isDown then
                    if not frame._clickReplacing then
                        frame._clickReplacing = true
                        local nr, ng, nb = GetClickColor()
                        local clickTex = Cursor.Textures[cdb.clickTexture or "Thin"]
                            or Cursor.Textures["Thin"]
                        frame.texture:SetTexture(clickTex)
                        frame.texture:SetVertexColor(nr, ng, nb, 0.9)
                        local clickSz = cdb.clickSize or 70
                        frame:SetSize(clickSz, clickSz)
                    end
                else
                    if frame._clickReplacing then
                        frame._clickReplacing = false
                        local r2, g2, b2 = GetCursorColor()
                        local origTex = Cursor.Textures[cdb.texture or "Thick"]
                            or Cursor.Textures["Thick"]
                        frame.texture:SetTexture(origTex)
                        frame.texture:SetVertexColor(r2, g2, b2, 0.9)
                        local sz = cdb.size or 50
                        frame:SetSize(sz, sz)
                    end
                end
                if clickFrame then clickFrame:Hide() end
            else
                if frame._clickReplacing then
                    frame._clickReplacing = false
                    local r2, g2, b2 = GetCursorColor()
                    local origTex = Cursor.Textures[cdb.texture or "Thick"]
                        or Cursor.Textures["Thick"]
                    frame.texture:SetTexture(origTex)
                    frame.texture:SetVertexColor(r2, g2, b2, 0.9)
                end
                if clickFrame then
                    if isDown then
                        mouseHoldTime = mouseHoldTime + elapsed
                        if mouseHoldTime >= 0.15 then
                            local cscale = clickFrame:GetEffectiveScale()
                            clickFrame:ClearAllPoints()
                            clickFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / cscale, y / cscale)
                            clickFrame:Show()
                            local nr, ng, nb = GetClickColor()
                            clickFrame.texture:SetVertexColor(nr, ng, nb, 0.9)
                        end
                    else
                        mouseHoldTime = 0
                        clickFrame.texture:SetVertexColor(0, 0, 0, 0)
                        clickFrame:Hide()
                    end
                end
            end
        else
            if clickFrame then clickFrame:Hide() end
            if frame._clickReplacing then
                frame._clickReplacing = false
                local cdb2 = GetDB()
                local r2, g2, b2 = GetCursorColor()
                local origTex = Cursor.Textures[cdb2.texture or "Thick"]
                    or Cursor.Textures["Thick"]
                frame.texture:SetTexture(origTex)
                frame.texture:SetVertexColor(r2, g2, b2, 0.9)
            end
        end
    end)

    mainFrame = f
end

-- ============================================================
-- Public API
-- ============================================================
-- Named Activate/Deactivate, NOT Enable/Disable.
-- AceAddon puts its own Enable/Disable mixin on every module table, so a
-- module function with those names SHADOWS the lifecycle: any caller doing
-- mod:Disable() then ran the feature teardown with a stray `self` argument
-- instead of the AceAddon one, never cleared enabledState, and here also
-- wrote to the saved variables.
--
-- Deliberately DOT functions that never touch `self`: the GUI and Core call
-- SP.Cursor.Refresh() while ModuleMixin calls self:Activate()/self:Deactivate(),
-- so the module table arrives as a stray first argument on one of the two
-- paths. Ignoring it entirely is the only shape that is correct for both.
function Cursor.Activate()
    local db = GetDB()
    if not db.enabled then return end
    if not mainFrame then CreateCursorFrame() end
    mainFrame:Show()
end

function Cursor.Deactivate()
    -- The cursor is driven by an OnUpdate on mainFrame, which is parented to
    -- UIParent: hiding it is what actually stops the driver.
    if mainFrame   then mainFrame:Hide()  end
    if clickFrame  then clickFrame:Hide() end
    if _previewClickTimer then
        _previewClickTimer:Cancel()
        _previewClickTimer = nil
    end
end

-- Doubles as ModuleMixin:Refresh -- it already dispatches to Activate or
-- Deactivate on db.enabled, so OnEnable/OnDisable come from the mixin.
function Cursor.Refresh()
    local db = GetDB()

    -- Keep AceAddon's flag tracking db.enabled. Without this the feature runs
    -- while the module is flagged disabled, and a later mod:Disable() is a
    -- no-op -- AceAddon returns early and OnDisable/Deactivate never run.
    if db and db.enabled and Cursor.IsEnabled and not Cursor:IsEnabled() then
        Cursor:Enable()
        return
    elseif not (db and db.enabled) and Cursor.IsEnabled and Cursor:IsEnabled() then
        Cursor:Disable()
        return
    end

    if not mainFrame then CreateCursorFrame() end

    if mainFrame then
        mainFrame:EnableMouse(false)
        mainFrame._clickReplacing = false  -- reset replace state on refresh

        local sz = db.size or 50
        mainFrame:SetSize(sz, sz)

        local texPath = Cursor.Textures[db.texture or "Thick"] or Cursor.Textures["Thick"]
        mainFrame.texture:SetTexture(texPath)
        local r, g, b = GetCursorColor()
        mainFrame.texture:SetVertexColor(r, g, b, 0.9)

        if mainFrame.dot then
            local dotSz = db.dotSize or 6
            mainFrame.dot:SetSize(dotSz, dotSz)
            if db.showDot then mainFrame.dot:Show() else mainFrame.dot:Hide() end
        end
    end

    -- Sync click circle settings
    if clickFrame then
        local clickSz  = db.clickSize   or 70
        local clickTex = Cursor.Textures[db.clickTexture or "Thin"] or Cursor.Textures["Thin"]
        clickFrame:SetSize(clickSz, clickSz)
        clickFrame.texture:SetTexture(clickTex)
            local cr, cg, cb = GetClickColor()
        clickFrame.texture:SetVertexColor(cr, cg, cb, 0)
        if not db.showClickCircle then clickFrame:Hide() end
    end

    if db.enabled then
        Cursor.Activate()
    else
        Cursor.Deactivate()
    end
end

function Cursor.PreviewClickCircle()
    local db = GetDB()
    local cr, cg, cb = GetClickColor()
    local clickSz  = db.clickSize   or 70
    local clickTex = Cursor.Textures[db.clickTexture or "Thin"] or Cursor.Textures["Thin"]
    local x, y     = GetCursorPosition()

    if (db.clickMode or "overlay") == "replace" then
        -- Replace mode: morph mainFrame briefly
        if not mainFrame then return end
        mainFrame.texture:SetTexture(clickTex)
        mainFrame.texture:SetVertexColor(cr, cg, cb, 0.9)
        mainFrame:SetSize(clickSz, clickSz)
        local scale = mainFrame:GetEffectiveScale()
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        mainFrame:Show()
        if _previewClickTimer then _previewClickTimer:Cancel() end
        _previewClickTimer = C_Timer.NewTimer(1.2, function()
            _previewClickTimer = nil
            if mainFrame and not mainFrame._clickReplacing then
                local r2, g2, b2 = GetCursorColor()
                local origTex = Cursor.Textures[db.texture or "Thick"] or Cursor.Textures["Thick"]
                mainFrame.texture:SetTexture(origTex)
                mainFrame.texture:SetVertexColor(r2, g2, b2, 0.9)
                local sz = db.size or 50
                mainFrame:SetSize(sz, sz)
                if not db.enabled then mainFrame:Hide() end
            end
        end)
    else
        -- Overlay mode: flash clickFrame
        if not clickFrame then return end
        clickFrame:SetSize(clickSz, clickSz)
        clickFrame.texture:SetTexture(clickTex)
        clickFrame.texture:SetVertexColor(cr, cg, cb, 0.85)
        local scale = clickFrame:GetEffectiveScale()
        clickFrame:ClearAllPoints()
        clickFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        clickFrame:Show()
        if _previewClickTimer then _previewClickTimer:Cancel() end
        _previewClickTimer = C_Timer.NewTimer(1.2, function()
            _previewClickTimer = nil
            if clickFrame then
                clickFrame.texture:SetVertexColor(cr, cg, cb, 0)
                if not db.showClickCircle then clickFrame:Hide() end
            end
        end)
    end
end

-- ============================================================
-- AceAddon Module lifecycle
--
-- Nothing left to write: OnEnable (deferred to PLAYER_LOGIN, then Refresh) and
-- OnDisable (UnregisterAllEvents + Deactivate) both come from SP.ModuleMixin --
-- see Core/Module.lua. Cursor.Refresh above is the mixin's Refresh.
-- ============================================================
