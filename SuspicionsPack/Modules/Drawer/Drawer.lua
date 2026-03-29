-- collapsible drawer for minimap addon buttons
local SP = SuspicionsPack

-- Register as an AceAddon module with AceEvent-3.0 mixin
local Drawer = SP:NewModule("Drawer", "AceEvent-3.0")
SP.Drawer = Drawer

local _G = _G

local abs   = math.abs
local ceil  = math.ceil
local floor = math.floor
local ipairs, pairs = ipairs, pairs
local min   = math.min
local tonumber = tonumber
local type  = type
local unpack, wipe = unpack, wipe

local CreateFrame      = CreateFrame
local C_Timer_NewTimer = C_Timer.NewTimer
local LibStub          = LibStub
local UIParent         = UIParent

local Px         = SP.Pixel
local WoWMinimap = _G.Minimap

local function GetDB()    return SP.GetDB().drawer end
local function GetRules() return SP.GetDB().drawer.buttonRules or {} end

local function BTN_SIZE()   return GetDB().btnSize   end
local function BTN_PAD()    return GetDB().btnPad    end
local function MARGIN()     return 10                end
local function MAX_COLS()   return GetDB().maxCols   end
local function TAB_W()      return GetDB().tabW      end
local function TAB_H()      return GetDB().tabH      end
local function HIDE_DELAY() return GetDB().hideDelay end
local function ICON_SIZE()  return GetDB().iconSize  end

local BORDER_TEXTURE_ID     = 136430
local BACKGROUND_TEXTURE_ID = 136467

local bar, bgFrame, tab
local buttons  = {}
local captured = {}
local hovering = false
local hideTimer
local side    = "LEFT"
local enabled = false

local noop = function() end

-- Forward declaration so Drawer.Create() polling code can reference GrabButton
-- (GrabButton body is defined later in the file; the upvalue slot is shared)
local GrabButton

-- ============================================================
-- Button tracking — populated during scans, used by the GUI
-- ============================================================
-- knownNames[name] = true      →  set of all button names seen in the last scan
-- hiddenButtons[btn] = true    →  buttons currently hidden by a "hide" rule
-- ignoredButtons[btn] = true   →  buttons kept on the minimap (rule == "ignore")
Drawer.knownNames    = {}
Drawer.hiddenButtons = {}
Drawer.ignoredButtons = {}

-- ============================================================
-- Built-in ignore list (system frames always excluded)
-- ============================================================
local ignoreList = {
    ["GameTimeFrame"]                     = true,
    ["MinimapBackdrop"]                   = true,
    ["MiniMapWorldMapButton"]             = true,
    ["MinimapZoomIn"]                     = true,
    ["MinimapZoomOut"]                    = true,
    ["MiniMapTracking"]                   = true,
    ["MiniMapMailFrame"]                  = true,
    ["MiniMapBattlefieldFrame"]           = true,
    ["MinimapZoneTextButton"]             = true,
    ["TimeManagerClockButton"]            = true,
    ["QueueStatusButton"]                 = true,
    ["GarrisonLandingPageMinimapButton"]  = true,
    ["ExpansionLandingPageMinimapButton"] = true,
    ["AddonCompartmentFrame"]             = true,
}

local ignorePatterns = {
    "^GatherMatePin%d+$",
    "^HandyNotes.*Pin$",
}

local function IsSystemIgnored(frame)
    local name = frame:GetName()
    if not name then return false end
    if ignoreList[name] then return true end
    for i = 1, #ignorePatterns do
        if name:match(ignorePatterns[i]) then return true end
    end
    return false
end

local function ClassifyTexture(region)
    local texPath = region:GetTexture()
    if texPath == BORDER_TEXTURE_ID or (type(texPath) == "string" and texPath:lower():find("minimap%-trackingborder")) then
        return "border"
    end
    if texPath == BACKGROUND_TEXTURE_ID or (type(texPath) == "string" and texPath:lower():find("ui%-minimap%-background")) then
        return "background"
    end
    return "content"
end

-- Extended border check used ONLY in ApplyMinimapBorderStyle (never in GrabButton).
-- Adds a size-based fallback for old addons like WIM whose texture may return nil
-- or an unrecognised value from GetTexture(): the circular border ring is always an
-- OVERLAY texture that is noticeably larger than the button itself (≥1.4×).
local function IsBorderTexture(region)
    local texPath = region:GetTexture()
    if texPath == BORDER_TEXTURE_ID or (type(texPath) == "string" and texPath:lower():find("minimap%-trackingborder")) then
        return true
    end
    if region:GetDrawLayer() == "OVERLAY" then
        local tw, th = region:GetSize()
        local parent = region:GetParent()
        if parent and tw and th then
            local bw, bh = parent:GetSize()
            if bw and bh and bw > 0 and bh > 0
                    and (tw / bw) >= 1.4 and (th / bh) >= 1.4 then
                return true
            end
        end
    end
    return false
end

local function IsVertical()
    return side == "TOP" or side == "BOTTOM"
end

local function UpdateTabSize()
    if not tab then return end
    local scaledW = Px.Scale(TAB_W())
    local scaledH = Px.Scale(TAB_H())
    if IsVertical() then
        tab:SetSize(scaledH, scaledW)
    else
        tab:SetSize(scaledW, scaledH)
    end
end

local function PositionTab()
    if not tab then return end
    tab:ClearAllPoints()
    tab:SetPoint("CENTER", WoWMinimap,
        side == "RIGHT"  and "RIGHT"  or
        side == "TOP"    and "TOP"    or
        side == "BOTTOM" and "BOTTOM" or "LEFT",
        0, 0)
end

local hasSessionError = false

local function CheckForErrors()
    if hasSessionError then return true end
    local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
    if ldb then
        local obj = ldb:GetDataObjectByName("BugSack")
        if obj and tonumber(obj.text) and tonumber(obj.text) > 0 then
            hasSessionError = true
            return true
        end
    end
    return false
end

local TAB_COLOR_ERROR       = { 0.937, 0.267, 0.267, 1 }
local TAB_COLOR_ERROR_HOVER = { 1, 0.4, 0.4, 1 }

-- Cached tab color tables — rebuilt only when Drawer.Refresh() is called.
-- Avoids allocating new {r,g,b,a} tables on every ApplyTabColor call.
local _cachedTabBase  = nil
local _cachedTabHover = nil

local function InvalidateTabColorCache()
    _cachedTabBase  = nil
    _cachedTabHover = nil
end

-- Returns the base (non-hover) tab RGBA based on tabColorSource:
--   "theme"  → addon accent color from SP.Theme
--   "class"  → player class color
--   "custom" → user-picked color (tabColor)
local function GetTabBaseColor()
    if _cachedTabBase then return _cachedTabBase end

    local db  = GetDB()
    local src = db.tabColorSource or "theme"

    if src == "theme" then
        local T = SP.Theme
        _cachedTabBase = { T.accent[1], T.accent[2], T.accent[3], 1 }
    elseif src == "class" then
        local _, cls = UnitClass("player")
        local c = RAID_CLASS_COLORS and cls and RAID_CLASS_COLORS[cls]
        _cachedTabBase = c and { c.r, c.g, c.b, 1 } or { 0.6, 0.6, 0.6, 1 }
    elseif db.tabColor then
        _cachedTabBase = { db.tabColor[1], db.tabColor[2], db.tabColor[3], 1 }
    else
        _cachedTabBase = { 0.6, 0.6, 0.6, 1 }
    end
    return _cachedTabBase
end

-- Returns a lightened version of the base color (40% lerp toward white)
local function GetTabHoverColor()
    if _cachedTabHover then return _cachedTabHover end

    local c = GetTabBaseColor()
    local t = 0.40
    _cachedTabHover = {
        c[1] + (1 - c[1]) * t,
        c[2] + (1 - c[2]) * t,
        c[3] + (1 - c[3]) * t,
        1,
    }
    return _cachedTabHover
end

local function TabColor(isHover)
    local db = GetDB()
    if hasSessionError and db.errorAlert ~= false then
        return isHover and TAB_COLOR_ERROR_HOVER or TAB_COLOR_ERROR
    end
    return isHover and GetTabHoverColor() or GetTabBaseColor()
end

local function ApplyTabColor(isHover)
    local c = TabColor(isHover)
    if tab and tab._bgTex then
        tab._bgTex:SetColorTexture(c[1], c[2], c[3], c[4])
    end
end

local function OnErrorCaught()
    hasSessionError = true
    if tab and not hovering then ApplyTabColor(false) end
end

local function CancelHide()
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
end

local function DoHide()
    bar:Hide()
    bgFrame:Hide()
    hovering = false
    ApplyTabColor(false)
    for i = 1, #buttons do buttons[i]:Hide() end
end

local function ScheduleHide()
    CancelHide()
    hideTimer = C_Timer_NewTimer(HIDE_DELAY(), DoHide)
end

local function DoShow()
    CancelHide()
    if not enabled or #buttons == 0 then return end

    local cols    = min(#buttons, MAX_COLS())
    local rows    = ceil(#buttons / MAX_COLS())
    local btnSize = Px.Scale(BTN_SIZE())
    local btnPad  = Px.Scale(BTN_PAD())
    local margin  = Px.Scale(MARGIN())

    local barW = margin + cols * (btnSize + btnPad) - btnPad + margin
    local barH = margin + rows * (btnSize + btnPad) - btnPad + margin

    bar:SetSize(barW, barH)
    bar:ClearAllPoints()
    bgFrame:SetSize(barW, barH)
    bgFrame:ClearAllPoints()

    local barPt, tabPt, offset = "RIGHT", "LEFT", -2
    if side == "RIGHT" then
        barPt, tabPt, offset = "LEFT", "RIGHT", 2
    elseif side == "TOP" then
        barPt, tabPt, offset = "BOTTOM", "TOP", 2
    elseif side == "BOTTOM" then
        barPt, tabPt, offset = "TOP", "BOTTOM", -2
    end

    if IsVertical() then
        bar:SetPoint(barPt, tab, tabPt, 0, offset)
        bgFrame:SetPoint(barPt, tab, tabPt, 0, offset)
    else
        bar:SetPoint(barPt, tab, tabPt, offset, 0)
        bgFrame:SetPoint(barPt, tab, tabPt, offset, 0)
    end

    for i = 1, #buttons do
        local btn = buttons[i]
        local col = (i - 1) % MAX_COLS()
        local row = floor((i - 1) / MAX_COLS())
        btn._sp_origFuncs.ClearAllPoints(btn)
        btn._sp_origFuncs.SetPoint(btn, "TOPLEFT", bar, "TOPLEFT",
            margin + col * (btnSize + btnPad),
            -(margin + row * (btnSize + btnPad)))
        btn:SetFrameStrata("MEDIUM")
        btn:SetFrameLevel(120)
        btn:Show()
        btn:SetAlpha(1)
    end

    bgFrame:Show()
    bar:Show()
    hovering = true
    ApplyTabColor(true)
end

function Drawer.SetSide(newSide)
    side = newSide or "LEFT"
    UpdateTabSize()
    PositionTab()
    if bar and bar:IsShown() then DoHide() end
end

function Drawer.Create()
    if bar then return end

    bgFrame = CreateFrame("Frame", "SP_AddonDrawerBg", UIParent, "BackdropTemplate")
    bgFrame:SetFrameStrata("MEDIUM")
    bgFrame:SetFrameLevel(100)
    local db = SP.GetDB().drawer
    local bR, bG, bB, bA = 0.12, 0.12, 0.12, (db and db.showBorder ~= false) and 1 or 0
    Px.SetupFrameBackdrop(bgFrame, 0.06, 0.06, 0.06, 0.95, bR, bG, bB, bA)
    bgFrame:EnableMouse(true)
    bgFrame:Hide()

    bar = CreateFrame("Frame", "SP_AddonDrawerBar", UIParent)
    bar:SetSize(200, 34)
    bar:SetFrameStrata("MEDIUM")
    bar:SetFrameLevel(110)
    bar:EnableMouse(true)
    bar:Hide()

    tab = CreateFrame("Button", "SP_AddonDrawerTab", UIParent)
    UpdateTabSize()
    tab:SetFrameStrata("MEDIUM")
    tab:SetFrameLevel(111)
    -- Solid color texture for the fill (dynamically recolored via ApplyTabColor)
    local tc = TabColor(false)
    tab._bgTex = tab:CreateTexture(nil, "BACKGROUND")
    tab._bgTex:SetAllPoints(tab)
    tab._bgTex:SetColorTexture(tc[1], tc[2], tc[3], tc[4])
    do  -- initial tab border (black, toggled by showTabBorder)
        local dbInit = SP.GetDB().drawer
        local tabBorderAInit = (dbInit and dbInit.showTabBorder) and 1 or 0
        -- transparent bg so _bgTex fill shows through; only the 1px black border is drawn
        Px.SetupFrameBackdrop(tab, 0, 0, 0, 0, 0, 0, 0, tabBorderAInit)
    end

    PositionTab()

    tab:SetScript("OnEnter", DoShow)
    tab:SetScript("OnLeave", ScheduleHide)
    tab:SetScript("OnMouseDown", function(_, button)
        if button == "RightButton" and hasSessionError then
            -- Dismiss the error alert; it will re-trigger on the next new Lua error.
            hasSessionError = false
            ApplyTabColor(false)
        end
    end)
    bar:SetScript("OnEnter", CancelHide)
    bar:SetScript("OnLeave", ScheduleHide)
    bgFrame:SetScript("OnEnter", CancelHide)
    bgFrame:SetScript("OnLeave", ScheduleHide)

    -- Primary: BugGrabber callback (works when BugGrabber addon is installed)
    if _G.BugGrabber then
        CheckForErrors()
        if _G.BugGrabber.RegisterCallback then
            _G.BugGrabber.RegisterCallback(Drawer, "BugGrabber_BugGrabbed", OnErrorCaught)
        end
    end

    -- Fallback: hook ScriptErrors_Display — the Lua function called for every
    -- script error before the frame is shown.  More reliable than hooking OnShow
    -- because ScriptErrorsFrame is created lazily by Blizzard_DebugTools and may
    -- be nil at Create() time.  hooksecurefunc works on named globals even if they
    -- load after us.
    if type(_G.ScriptErrors_Display) == "function" then
        hooksecurefunc("ScriptErrors_Display", OnErrorCaught)
    else
        -- Belt-and-suspenders: if the function name differs, also try the frame hook.
        -- We register for ADDON_LOADED so we catch it even if DebugTools loads late.
        local hookFrame = CreateFrame("Frame")
        hookFrame:RegisterEvent("ADDON_LOADED")
        hookFrame:SetScript("OnEvent", function(self, _, name)
            if type(_G.ScriptErrors_Display) == "function" then
                hooksecurefunc("ScriptErrors_Display", OnErrorCaught)
                self:UnregisterAllEvents()
            elseif _G.ScriptErrorsFrame then
                _G.ScriptErrorsFrame:HookScript("OnShow", OnErrorCaught)
                self:UnregisterAllEvents()
            end
        end)
    end

    -- ── Event-driven late-button capture ─────────────────────────
    -- Replaces the old OnUpdate polling loop.  Minimap buttons that load after
    -- CaptureButtons() (lazily-initialised addons) are caught via:
    --   1. LibDBIcon_IconCreated callback (already registered in CaptureButtons).
    --   2. ADDON_LOADED: triggers a cheap LDB + Minimap mini-scan each time any
    --      addon finishes loading — zero idle CPU cost.
    --   3. One-shot timers at 5 s, 15 s, 45 s and 90 s after Enable() to cover
    --      addons that register their button outside of their load event.
    -- UIParent scan is intentionally omitted here (same as before); it runs only
    -- inside CaptureButtons() at login and zone-change.

    local function MiniScan()
        if not enabled then return end
        local changed = false
        local LDB = LibStub and LibStub("LibDBIcon-1.0", true)
        if LDB then
            local list = LDB:GetButtonList()
            if list then
                for _, bname in ipairs(list) do
                    local btn = LDB:GetMinimapButton(bname)
                    if btn and not captured[btn] then
                        GrabButton(btn)
                        changed = true
                    end
                end
            end
        end
        if WoWMinimap then
            for _, child in ipairs({ WoWMinimap:GetChildren() }) do
                local ok, nm = pcall(child.GetName, child)
                if ok and nm and child:IsObjectType("Button")
                        and not IsSystemIgnored(child)
                        and not captured[child] then
                    GrabButton(child)
                    changed = true
                end
            end
        end
        if changed then
            Drawer.ApplyAllBorderStyles()
            if bar and bar:IsShown() then DoShow() end
        end
    end
    Drawer._miniScan = MiniScan

    -- Schedule one-shot passes to catch late-loaders
    local function ScheduleLatePasses()
        for _, delay in ipairs({ 5, 15, 45, 90 }) do
            C_Timer_NewTimer(delay, MiniScan)
        end
    end
    Drawer._scheduleLatePasses = ScheduleLatePasses

    Px.OnScaleChange("SPDrawer", Drawer.Refresh)
end

local function FindIconTexture(btn)
    local iconTex = btn.Icon or btn.icon
    if iconTex then return iconTex end
    for _, region in pairs({ btn:GetRegions() }) do
        if region:IsObjectType("Texture") then
            if ClassifyTexture(region) == "content" then
                local layer = region:GetDrawLayer()
                if layer == "BACKGROUND" or layer == "ARTWORK" then
                    return region
                end
            end
        end
    end
    return nil
end

local function HasClickHandler(frame)
    if not frame.HasScript then return false end
    if frame:HasScript("OnClick")     and frame:GetScript("OnClick")     then return true end
    if frame:HasScript("OnMouseUp")   and frame:GetScript("OnMouseUp")   then return true end
    if frame:HasScript("OnMouseDown") and frame:GetScript("OnMouseDown") then return true end
    return false
end

local function LooksLikeButton(frame)
    if not frame or frame:IsForbidden() then return false end
    -- Do NOT check IsShown() — buttons may be hidden at scan time (e.g. ElvUI startup)
    local w, h = frame:GetSize()
    if w < 16 or h < 16 or w > 60 or h > 60 then return false end
    if abs(w - h) > 10 then return false end
    if HasClickHandler(frame) then return true end
    for _, child in pairs({ frame:GetChildren() }) do
        if HasClickHandler(child) then return true end
    end
    return false
end

local function FreezeButton(btn)
    if btn._sp_frozen then return end
    btn._sp_frozen = true
    btn._sp_origFuncs = {
        SetPoint       = btn.SetPoint,
        ClearAllPoints = btn.ClearAllPoints,
        SetParent      = btn.SetParent,
        SetScale       = btn.SetScale,
        SetSize        = btn.SetSize,
        SetWidth       = btn.SetWidth,
        SetHeight      = btn.SetHeight,
    }
    if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
    if btn.SetFixedFrameLevel  then btn:SetFixedFrameLevel(false)  end
    btn.SetPoint       = noop
    btn.ClearAllPoints = noop
    btn.SetParent      = noop
    btn.SetScale       = noop
    btn.SetSize        = noop
    btn.SetWidth       = noop
    btn.SetHeight      = noop
end

local function UnfreezeButton(btn)
    if not btn._sp_frozen then return end
    btn._sp_frozen = nil
    if btn._sp_origFuncs then
        for name, func in pairs(btn._sp_origFuncs) do btn[name] = func end
        btn._sp_origFuncs = nil
    end
end

-- ============================================================
-- GrabButton — respects user rules before the system ignore list
-- (assigned to the forward-declared upvalue so Drawer.Create() can use it)
-- ============================================================
GrabButton = function(btn)
    local rawName = btn:GetName()
    -- Strip LibDBIcon prefix so the name matches what LDB:GetButtonList() returns
    -- e.g. "LibDBIcon10_WeakAuras" → "WeakAuras"
    local name = rawName and rawName:gsub("^LibDBIcon10_", ""):gsub(".*_LibDBIcon_", "") or rawName

    -- Track every button we encounter (used by the GUI exclusion list)
    if name then Drawer.knownNames[name] = true end

    -- ── User-defined rules ────────────────────────────────
    local rule = name and GetRules()[name]

    if rule == "ignore" then
        -- Leave the button on the minimap as-is (no forced repositioning).
        -- Track for border styling
        Drawer.ignoredButtons[btn] = true
        return
    end

    if rule == "hide" then
        -- Completely hide the button from the minimap
        if not btn._sp_hidden then
            btn._sp_hidden    = true
            btn._sp_origShow  = btn.Show
            btn.Show          = noop
            btn:Hide()
            btn:EnableMouse(false)
            Drawer.hiddenButtons[btn] = true
        end
        return
    end

    -- ── Default: add to drawer ────────────────────────────
    if captured[btn] then return end
    if IsSystemIgnored(btn) then return end

    -- Skip buttons with no icon texture — they'd show as empty circles
    if not FindIconTexture(btn) then return end

    captured[btn] = true

    local pts = {}
    for i = 1, btn:GetNumPoints() do pts[i] = { btn:GetPoint(i) } end
    btn._sp_orig = {
        parent = btn:GetParent(),
        points = pts,
        strata = btn:GetFrameStrata(),
        level  = btn:GetFrameLevel(),
        scale  = btn:GetScale(),
        alpha  = btn:GetAlpha(),
        width  = btn:GetWidth(),
        height = btn:GetHeight(),
    }

    FreezeButton(btn)
    btn._sp_origFuncs.SetParent(btn, bar)
    btn._sp_origFuncs.SetSize(btn, Px.Scale(BTN_SIZE()), Px.Scale(BTN_SIZE()))

    local iconTex        = FindIconTexture(btn)
    local scaledIconSize = Px.Scale(ICON_SIZE())
    for _, region in pairs({ btn:GetRegions() }) do
        if region:IsObjectType("Texture") then
            if region == iconTex then
                region:ClearAllPoints()
                region:SetPoint("CENTER")
                region:SetSize(scaledIconSize, scaledIconSize)
                region:Show()
            elseif ClassifyTexture(region) ~= "content" then
                region:Hide()
            end
        end
    end

    btn:Hide()
    buttons[#buttons + 1] = btn

    if not btn._sp_hooked then
        btn:HookScript("OnEnter", CancelHide)
        btn:HookScript("OnLeave", ScheduleHide)
        btn._sp_hooked = true
    end
end

local function ReleaseButton(btn)
    if not captured[btn] then return end
    captured[btn] = nil
    UnfreezeButton(btn)
    if btn._sp_orig then
        local orig = btn._sp_orig
        btn:SetParent(orig.parent)
        btn:ClearAllPoints()
        for _, pt in ipairs(orig.points) do btn:SetPoint(unpack(pt)) end
        btn:SetFrameStrata(orig.strata)
        btn:SetFrameLevel(orig.level)
        btn:SetScale(orig.scale)
        btn:SetAlpha(orig.alpha)
        btn:SetSize(orig.width, orig.height)
        for _, region in pairs({ btn:GetRegions() }) do
            if region:IsObjectType("Texture") then
                region:Show()
            end
        end
        btn:Show()
        btn._sp_orig = nil
    end
    for i = #buttons, 1, -1 do
        if buttons[i] == btn then table.remove(buttons, i); break end
    end
end

-- Restore a button that was hidden by "hide" rule
local function UnhideButton(btn)
    if not btn._sp_hidden then return end
    btn._sp_hidden = nil
    if btn._sp_origShow then
        btn.Show = btn._sp_origShow
        btn._sp_origShow = nil
    end
    btn:Show()
    btn:EnableMouse(true)
end

local function ReleaseAllButtons()
    for i = #buttons, 1, -1 do ReleaseButton(buttons[i]) end
    wipe(buttons)
    wipe(captured)
end

local function ScanMinimapChildren(parent)
    if not parent then return end
    -- Use EQoL-style detection: IsObjectType("Button") + named frame only.
    -- No size filter — ElvUI reskins buttons to non-standard sizes.
    -- pcall on GetName guards against non-Frame objects in TWW's child lists.
    for _, child in ipairs({ parent:GetChildren() }) do
        local ok, nm = pcall(child.GetName, child)
        if ok and nm and child:IsObjectType("Button")
                and not IsSystemIgnored(child)
                and not captured[child] then
            GrabButton(child)
        end
    end
end

local function ScanLibDBIcon()
    local LDB = LibStub and LibStub("LibDBIcon-1.0", true)
    if not LDB then return end
    local list = LDB:GetButtonList()
    if not list then return end
    for _, name in ipairs(list) do
        local btn = LDB:GetMinimapButton(name)
        if btn and not captured[btn] then GrabButton(btn) end
    end
end

local function OnLibDBIconCreated(_, btn)
    if not enabled then return end
    if btn and not captured[btn] then GrabButton(btn) end
end

-- ============================================================
-- Minimap border styling — applies to ALL non-captured minimap buttons
-- ============================================================
-- Recolors every border-class texture on btn:
--   "default" → golden ring (vertex color 1,1,1,1 — WoW renders it gold naturally)
--   "dark"    → dark gray ring
--   "none"    → fully transparent (alpha 0) — invisible but not removed
local function ApplyMinimapBorderStyle(btn, style)
    for _, region in pairs({ btn:GetRegions() }) do
        if region:IsObjectType("Texture") and IsBorderTexture(region) then
            if style == "none" then
                region:SetVertexColor(1, 1, 1, 0)
            elseif style == "dark" then
                region:SetVertexColor(0.25, 0.25, 0.25, 1)
            else  -- "default" / gold
                region:SetVertexColor(1, 1, 1, 1)
            end
        end
    end
end

-- Module-level upvalue written at the start of ApplyAllBorderStyles so that
-- _TryApply and _ScanMinimapChildren are permanent closures (defined once at
-- load time) rather than new closures created on every call.
local _borderStyle = "default"

local function _TryApply(btn)
    if not btn or captured[btn] then return end
    if IsSystemIgnored(btn) then return end
    ApplyMinimapBorderStyle(btn, _borderStyle)
end

local function _ScanMinimapChildren(parent)
    if not parent then return end
    for _, child in ipairs({ parent:GetChildren() }) do
        local ok, isBtn = pcall(child.IsObjectType, child, "Button")
        if ok and isBtn then _TryApply(child) end
    end
end

-- Applies the saved border style to minimap buttons.
-- Covers: ignore-rule buttons, LibDBIcon buttons, Minimap/MinimapBackdrop children,
-- UIParent-parented buttons (WIM free-mode), and buttons currently in the drawer.
-- Pre-applying to drawer buttons means their ring colour is correct the moment
-- they are released back to the minimap via a rule change.
function Drawer.ApplyAllBorderStyles()
    _borderStyle = GetDB().buttonBorderStyle or "default"

    -- LibDBIcon buttons (non-captured only — captured ones skip via _TryApply guard).
    local LDB = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDB then
        local list = LDB:GetButtonList()
        if list then
            for _, name in ipairs(list) do
                _TryApply(LDB:GetMinimapButton(name))
            end
        end
    end

    -- Minimap, MinimapBackdrop, and the minimap's own parent frame (MinimapCluster
    -- or equivalent) — covers every common anchoring pattern for minimap buttons.
    _ScanMinimapChildren(WoWMinimap)
    _ScanMinimapChildren(_G.MinimapBackdrop)
    local minimapParent = WoWMinimap and WoWMinimap:GetParent()
    if minimapParent and minimapParent ~= UIParent then
        _ScanMinimapChildren(minimapParent)
    end

    -- "ignore"-rule buttons: kept on the minimap but still need border styling.
    -- These are tracked in Drawer.ignoredButtons regardless of their parent frame,
    -- so this replaces the previous full UIParent scan (O(hundreds) every call)
    -- with a targeted O(ignored buttons only) pass.
    for btn in pairs(Drawer.ignoredButtons) do
        _TryApply(btn)
    end
end

function Drawer.CaptureButtons()
    -- 1. Restore all currently-hidden buttons so they can be re-evaluated
    for btn in pairs(Drawer.hiddenButtons) do UnhideButton(btn) end
    wipe(Drawer.hiddenButtons)

    -- 2. Release all currently-grabbed buttons
    ReleaseAllButtons()

    -- 3. Reset tracking sets for a fresh scan
    wipe(Drawer.knownNames)
    wipe(Drawer.ignoredButtons)

    -- 4. Scan for buttons, applying rules inside GrabButton
    ScanLibDBIcon()
    ScanMinimapChildren(WoWMinimap)
    ScanMinimapChildren(_G.MinimapBackdrop)

    -- 4b. UIParent scan: catches minimap buttons that use UIParent as parent
    -- (e.g. WIM in "free" mode, or any addon that skips Minimap parenting).
    -- Uses strict texture-ID check (ClassifyTexture == "border") rather than the
    -- size-based IsBorderTexture fallback, which caused false positives on addons
    -- like ClassReminders whose glow/overlay textures happen to be oversized.
    if UIParent then
        for _, child in ipairs({ UIParent:GetChildren() }) do
            local ok, nm = pcall(child.GetName, child)
            if ok and nm and child:IsObjectType("Button")
                    and not IsSystemIgnored(child)
                    and not captured[child] then
                for _, region in pairs({ child:GetRegions() }) do
                    if region:IsObjectType("Texture") and ClassifyTexture(region) == "border" then
                        GrabButton(child)
                        break
                    end
                end
            end
        end
    end

    -- 5. Apply minimap border styles to "ignore"-rule buttons
    Drawer.ApplyAllBorderStyles()

    -- 6. Subscribe to future LibDBIcon registrations
    local LDB = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDB and LDB.RegisterCallback then
        LDB.RegisterCallback(Drawer, "LibDBIcon_IconCreated", OnLibDBIconCreated)
    end
end

-- GetKnownNames: sorted list of all button names seen in the last scan
function Drawer.GetKnownNames()
    local list = {}
    for name in pairs(Drawer.knownNames) do
        list[#list + 1] = name
    end
    table.sort(list)
    return list
end

function Drawer.Enable()
    enabled = true
    Drawer.Create()
    if tab then tab:Show() end
    Drawer.CaptureButtons()
    if Drawer._scheduleLatePasses then Drawer._scheduleLatePasses() end
    SP.GetDB().drawer.enabled = true
end

function Drawer.Disable()
    enabled = false
    local LDB = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDB and LDB.UnregisterCallback then
        LDB.UnregisterCallback(Drawer, "LibDBIcon_IconCreated")
    end
    if tab     then tab:Hide()     end
    if bar     then bar:Hide()     end
    if bgFrame then bgFrame:Hide() end
    ReleaseAllButtons()
    SP.GetDB().drawer.enabled = false
end

-- ============================================================
-- AceAddon Module lifecycle
-- ============================================================

-- OnEnable is called automatically after the parent addon (SP) fully initialises.
-- At this point SP.GetDB() is available (AceDB is set up in SP:OnInitialize).
function Drawer:OnEnable()
    if IsLoggedIn() then
        self:OnLogin()
    else
        self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
    end
end

-- OnDisable is called if the module is disabled at runtime.
function Drawer:OnDisable()
    self:UnregisterAllEvents()
    Drawer.Disable()
end

-- After login the DB is live and character data is available (class color, etc.)
function Drawer:OnLogin()
    local db = SP.GetDB()
    if db and db.drawer and db.drawer.enabled then
        Drawer.SetSide(db.drawer.side)
        Drawer.Enable()
        self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
        -- Run a mini-scan each time an addon finishes loading (zero idle cost).
        self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded")
    end
end

function Drawer:OnAddonLoaded()
    if Drawer._miniScan then Drawer._miniScan() end
end

-- Called after PLAYER_ENTERING_WORLD; gives all addons extra time to register
-- their minimap buttons (e.g. WIM which parents its button lazily).
function Drawer:OnEnteringWorld()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    Drawer.CaptureButtons()
    -- Schedule delayed passes for any buttons that load after zone change
    if Drawer._scheduleLatePasses then Drawer._scheduleLatePasses() end
end


function Drawer.Refresh()
    if not enabled or not tab then return end
    InvalidateTabColorCache()  -- settings may have changed color source
    local db = SP.GetDB().drawer
    if bgFrame then
        local bA = (db and db.showBorder ~= false) and 1 or 0
        local bR, bG, bB = 0.12, 0.12, 0.12
        if bA > 0 then
            local src = db and db.borderColorSource or "theme"
            if src == "theme" then
                local ac = SP.Theme and SP.Theme.accent or { 0.9, 0.06, 0.22 }
                bR, bG, bB = ac[1], ac[2], ac[3]
            elseif src == "class" then
                local _, cls = UnitClass("player")
                local c = RAID_CLASS_COLORS and cls and RAID_CLASS_COLORS[cls]
                if c then bR, bG, bB = c.r, c.g, c.b end
            end
        end
        Px.SetupFrameBackdrop(bgFrame, 0.06, 0.06, 0.06, 0.95, bR, bG, bB, bA)
    end
    if tab then
        local tabBorderA = (db and db.showTabBorder) and 1 or 0
        -- transparent bg so _bgTex fill shows through; only the 1px black border is drawn
        Px.SetupFrameBackdrop(tab, 0, 0, 0, 0, 0, 0, 0, tabBorderA)
    end
    -- Update tab color via texture (reliable, no BackdropTemplate quirks)
    ApplyTabColor(hovering)
    UpdateTabSize()
    local btnSize  = Px.Scale(BTN_SIZE())
    local iconSize = Px.Scale(ICON_SIZE())
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn._sp_origFuncs then
            btn._sp_origFuncs.SetSize(btn, btnSize, btnSize)
        end
        local iconTex = FindIconTexture(btn)
        if iconTex then iconTex:SetSize(iconSize, iconSize) end
    end
    -- Refresh border styles on "ignore"-rule minimap buttons
    Drawer.ApplyAllBorderStyles()
    if bar and bar:IsShown() then DoShow() end
end
