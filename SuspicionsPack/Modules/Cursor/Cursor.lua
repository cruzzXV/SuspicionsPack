-- SuspicionsPack - Cursor.lua
-- Cursor circle that follows the mouse, with optional GCD sweep overlay.
-- Adapted from NorskenUI's CombatCursor.lua.

local SP = SuspicionsPack

-- Register as an AceAddon module with AceEvent-3.0 mixin
local Cursor = SP:NewModule("Cursor", "AceEvent-3.0")
SP.Cursor = Cursor

-- ============================================================
-- Constants
-- ============================================================
local MEDIA = "Interface\\AddOns\\SuspicionsPack\\Media\\CursorCircles\\"

-- Available circle textures (same files as NorskenUI)
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

-- ============================================================
-- Color helpers — respect colorSource settings
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

    -- ── Main circle ──────────────────────────────────────────
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

    -- Center dot — always white solid circle marking the exact click point
    local dotTex = f:CreateTexture(nil, "OVERLAY")
    dotTex:SetTexture(MEDIA .. "Click.tga")
    dotTex:SetPoint("CENTER", f, "CENTER", 0, 0)
    local dotSz = db.dotSize or 6
    dotTex:SetSize(dotSz, dotSz)
    dotTex:SetVertexColor(1, 1, 1, 1)   -- always white, never tinted by color settings
    if db.showDot then dotTex:Show() else dotTex:Hide() end
    f.dot = dotTex

    -- ── Click circle (second ring, visible only while mouse held ≥ 150 ms) ──
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

    -- ── Shared OnUpdate — follows cursor, handles click-circle visibility ──
    -- mouseHoldTime accumulates while any button is held; resets on release.
    -- The click circle fades in only after 150 ms to avoid flicker on quick clicks.
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

        -- Update positions for both circles (skip layout if cursor hasn't moved)
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
                -- Replace mode: swap main circle size/texture/color while mouse held,
                -- then restore cursor circle when released so the two sliders stay independent.
                if isDown then
                    if not frame._clickReplacing then
                        frame._clickReplacing = true
                        local nr, ng, nb = GetClickColor()
                        local clickTex = Cursor.Textures[cdb.clickTexture or "Thin"]
                            or Cursor.Textures["Thin"]
                        frame.texture:SetTexture(clickTex)
                        frame.texture:SetVertexColor(nr, ng, nb, 0.9)
                        -- Resize to click circle size (independent of cursor circle size)
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
                        -- Restore cursor circle size
                        local sz = cdb.size or 50
                        frame:SetSize(sz, sz)
                    end
                end
                if clickFrame then clickFrame:Hide() end
            else
                -- Overlay mode: show second ring when mouse held ≥ 0.15 s (original)
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
-- Public API (used by the GUI settings page)
-- ============================================================
function Cursor.Enable()
    local db = GetDB()
    if not db.enabled then return end
    if not mainFrame then CreateCursorFrame() end
    mainFrame:Show()
    -- click circle starts hidden; OnUpdate shows it when mouse held
end

function Cursor.Disable()
    if mainFrame   then mainFrame:Hide()  end
    if clickFrame  then clickFrame:Hide() end
end

function Cursor.Refresh()
    local db = GetDB()

    -- Lazy-create frames so settings (size, texture, color) take effect even
    -- when the cursor circle is currently disabled.
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
        -- keep alpha at 0 — OnUpdate reveals it when mouse held
        local cr, cg, cb = GetClickColor()
        clickFrame.texture:SetVertexColor(cr, cg, cb, 0)
        if not db.showClickCircle then clickFrame:Hide() end
    end

    if db.enabled then
        Cursor.Enable()
    else
        Cursor.Disable()
    end
end

-- Temporarily flash the click circle at full opacity so the user can see its
-- size when adjusting the slider (it's normally invisible unless a mouse
-- button is held).
-- Works in both overlay mode (flashes clickFrame) and replace mode (temporarily
-- morphs mainFrame to the click circle appearance).
local _previewClickTimer = nil
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
                -- Restore cursor circle appearance
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
-- ============================================================

function Cursor:OnEnable()
    -- If PLAYER_LOGIN already fired (e.g. another addon caused a late enable),
    -- initialise immediately instead of waiting for an event that will never come.
    if IsLoggedIn() then
        self:OnLogin()
    else
        self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
    end
end

function Cursor:OnDisable()
    self:UnregisterAllEvents()
    Cursor.Disable()
end

function Cursor:OnLogin()
    local db = GetDB()
    if db.enabled then
        CreateCursorFrame()
        mainFrame:Show()
    end
end
