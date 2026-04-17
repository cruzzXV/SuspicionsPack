-- Suspicion's Pack — GUI
-- Architecture inspired by NorskenUI:
--   • SP.Theme live table (same presets as NorskenUI, mutated by SP.RefreshTheme)
--   • Animated slide toggle  (knob + color animation)
--   • Card-based content layout with titled headers
--   • Collapsible sidebar with animated arrow indicators
--   • Scrollable / resizable window
--   • Button exclusion system: ignore (stays on minimap) or hide (invisible)
-- GUI.lua loads after Core.lua, so _G.SuspicionsPack is the AceAddon object.
local SP = SuspicionsPack

local GUI = {}
SP.GUI = GUI

local CreateFrame    = CreateFrame
local C_Timer        = C_Timer
local math           = math
local ipairs, pairs  = ipairs, pairs
local wipe           = wipe
local table_insert   = table.insert
local table_sort     = table.sort
local UIParent       = UIParent
local BLANK          = "Interface\\Buttons\\WHITE8X8"
local SP_MEDIA       = "Interface\\AddOns\\SuspicionsPack\\Media\\GUITextures\\"
local SP_LOGO_TEX    = "Interface\\AddOns\\SuspicionsPack\\Media\\Icons\\icon128x128.png"
local ARROW_TEX      = SP_MEDIA .. "collapse.tga"
local CLOSE_TEX      = SP_MEDIA .. "cross.png"
local RESIZE_TEX     = SP_MEDIA .. "resize.png"
local CURSOR_MEDIA   = "Interface\\AddOns\\SuspicionsPack\\Media\\CursorCircles\\"

-- SP.Theme is initialised in Core.lua before this file loads.
-- T is a reference to the same table, so RefreshTheme mutations are seen here.
local T = SP.Theme

-- Returns the current accent colour as a 6-char uppercase hex string (e.g. "E51039")
-- Always reads from the live T table so it reflects the active theme.
local function GetAccentHex()
    return string.format("%02X%02X%02X",
        math.floor(T.accent[1]*255+0.5),
        math.floor(T.accent[2]*255+0.5),
        math.floor(T.accent[3]*255+0.5))
end

-- ============================================================
-- Helpers
-- ============================================================
local SP_FONT      = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"
local SP_ICON_FONT = "Fonts\\FRIZQT__.TTF"   -- WoW default — has full Unicode block/arrow glyphs

-- Single shared fullscreen click-catcher reused by ALL dropdowns.
-- Avoids creating a new UIParent frame on every dropdown open (WoW frames are never GC'd).
local sharedCloser = CreateFrame("Frame", "SP_GUICloser", UIParent)
sharedCloser:SetAllPoints()
sharedCloser:SetFrameStrata("TOOLTIP")
sharedCloser:SetFrameLevel(199)
sharedCloser:EnableMouse(true)
sharedCloser:Hide()

local function ApplyFont(fs, size)
    if not fs then return end
    fs:SetFont(SP_FONT, size or 12, "")
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
end

-- For symbol-only FontStrings (▾ ▶ × ⤡ etc.) where Expressway has no glyph
local function ApplyIconFont(fs, size)
    if not fs then return end
    fs:SetFont(SP_ICON_FONT, size or 12, "")
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
end

local function SetBackdrop(frame, bgR, bgG, bgB, bgA, brR, brG, brB, brA)
    frame:SetBackdrop({
        bgFile = BLANK, edgeFile = BLANK, edgeSize = T.borderSize,
    })
    frame:SetBackdropColor(bgR, bgG, bgB, bgA)
    frame:SetBackdropBorderColor(
        brR or T.border[1], brG or T.border[2], brB or T.border[3], brA or 1)
end

-- Animate a frame border between T.border and T.accent (0.15 s ease-out).
-- Used for both focus (editboxes) and hover (buttons, dropdowns, anchor grid).
-- Starts from the frame's CURRENT border colour so mid-animation reversals are smooth.
local function AnimateBorderFocus(frame, focused)
    if frame._borderTicker then frame._borderTicker:Cancel(); frame._borderTicker = nil end
    local startTime = GetTime()
    local DUR = 0.15
    -- Read current colour so there is no flash if the animation is interrupted mid-way
    -- or if the frame is already at the target colour (e.g. a drag-active button on hover).
    local sr, sg, sb = frame:GetBackdropBorderColor()
    if not sr then
        sr = focused and T.border[1] or T.accent[1]
        sg = focused and T.border[2] or T.accent[2]
        sb = focused and T.border[3] or T.accent[3]
    end
    local tr, tg, tb
    if focused then
        tr, tg, tb = T.accent[1], T.accent[2], T.accent[3]
    else
        tr, tg, tb = T.border[1], T.border[2], T.border[3]
    end
    frame._borderTicker = C_Timer.NewTicker(0.016, function()
        local p = math.min((GetTime() - startTime) / DUR, 1)
        p = 1 - (1 - p) * (1 - p)   -- ease-out quadratic
        frame:SetBackdropBorderColor(sr + (tr-sr)*p, sg + (tg-sg)*p, sb + (tb-sb)*p, 1)
        if p >= 1 then frame._borderTicker:Cancel(); frame._borderTicker = nil end
    end)
end

-- ============================================================
-- Widget: Inline Dropdown
-- ============================================================
-- options  = { {key="x", label="Label"}, ... }
-- onSelect = function(key) fired on change
-- Returns the trigger button; exposes :SetValue(key) / :GetValue()
--
-- A single lazy catcher frame is shared across all dropdowns —
-- Small inline dropdown widget — shares GUI._activeDropdownClose with GUI:CreateDropdown
-- so all open dropdowns on the page close each other properly.

-- Helper: convert plain string list to {key,label} objects for CreateDropdown
local function StrOptions(list)
    local r = {}
    for _, v in ipairs(list) do r[#r+1] = { key = v, label = v } end
    return r
end

local function CreateDropdown(parent, options, initialKey, onSelect, width)
    local DDW      = width or 110
    local DDH      = 22
    local ITEM_H   = 20
    local currentKey = initialKey

    local ARROW_CLOSED = -math.pi / 2   -- ◄ collapsed
    local ARROW_OPEN   =  0             -- ▼ expanded
    local ANIM_DUR     = 0.15

    -- ── trigger button ────────────────────────────────────────
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(DDW, DDH)
    SetBackdrop(btn, T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)

    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetPoint("LEFT",  btn, "LEFT",  6,   0)
    lbl:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
    ApplyFont(lbl, 10)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)

    -- Arrow texture (same asset + animation as GUI:CreateDropdown)
    local arrowTex = btn:CreateTexture(nil, "OVERLAY")
    arrowTex:SetSize(10, 10)
    arrowTex:SetPoint("RIGHT", btn, "RIGHT", -5, 0)
    arrowTex:SetTexture(ARROW_TEX)
    arrowTex:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
    arrowTex:SetTexelSnappingBias(0)
    arrowTex:SetSnapToPixelGrid(false)

    local arrowCurrent = ARROW_CLOSED
    arrowTex:SetRotation(arrowCurrent)

    local arrowTicker = nil
    local function AnimateArrow(targetRot)
        if arrowTicker then arrowTicker:Cancel(); arrowTicker = nil end
        local startRot  = arrowCurrent
        local startTime = GetTime()
        arrowTicker = C_Timer.NewTicker(0.016, function()
            local p = math.min((GetTime() - startTime) / ANIM_DUR, 1)
            p = 1 - (1-p)*(1-p)
            arrowCurrent = startRot + (targetRot - startRot) * p
            arrowTex:SetRotation(arrowCurrent)
            if p >= 1 then
                arrowCurrent = targetRot
                arrowTex:SetRotation(targetRot)
                arrowTicker:Cancel(); arrowTicker = nil
            end
        end)
    end

    -- set initial label text
    for _, opt in ipairs(options) do
        if opt.key == initialKey then lbl:SetText(opt.label); break end
    end

    -- ── popup state ───────────────────────────────────────────
    local popup
    local menuTicker = nil
    local isClosing  = false
    local closer = false

    local CloseDD
    CloseDD = function(instant)
        if GUI._activeDropdownClose == CloseDD then
            GUI._activeDropdownClose = nil
        end
        AnimateArrow(ARROW_CLOSED)
        SetBackdrop(btn, T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
        if closer then sharedCloser:Hide(); sharedCloser:SetScript("OnMouseDown", nil); closer = false end

        if instant or not popup or not popup:IsShown() then
            if menuTicker then menuTicker:Cancel(); menuTicker = nil end
            if popup then popup:Hide() end
            isClosing = false
            return
        end
        if isClosing then return end
        isClosing = true

        -- Slide-up close animation
        local startH    = popup:GetHeight()
        local startTime = GetTime()
        local CLOSE_DUR = 0.12
        if menuTicker then menuTicker:Cancel(); menuTicker = nil end
        menuTicker = C_Timer.NewTicker(0.016, function()
            local p = math.min((GetTime() - startTime) / CLOSE_DUR, 1)
            p = p * p  -- ease-in
            popup:SetHeight(math.max(1, math.floor(startH * (1-p) + 0.5)))
            if p >= 1 then
                menuTicker:Cancel(); menuTicker = nil
                popup:Hide()
                isClosing = false
            end
        end)
    end

    -- ── popup (built lazily on first open) ───────────────────
    local function BuildPopup()
        local fullH = ITEM_H * #options + 2
        popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        popup:SetFrameStrata("TOOLTIP")
        popup:SetFrameLevel(200)
        popup:SetSize(DDW, 1)
        popup:SetClipsChildren(true)
        SetBackdrop(popup,
            T.bgDark[1], T.bgDark[2], T.bgDark[3], 1,
            T.accent[1], T.accent[2], T.accent[3], 0.8)
        popup:Hide()
        popup._fullH = fullH

        for i, opt in ipairs(options) do
            local item = CreateFrame("Button", nil, popup)
            item:SetPoint("TOPLEFT", popup, "TOPLEFT", 1, -(1 + (i - 1) * ITEM_H))
            item:SetSize(DDW - 2, ITEM_H)

            local fill = item:CreateTexture(nil, "BACKGROUND")
            fill:SetAllPoints(); fill:SetColorTexture(0, 0, 0, 0)

            local bar = item:CreateTexture(nil, "ARTWORK")
            bar:SetWidth(2)
            bar:SetPoint("TOPLEFT",    item, "TOPLEFT",    0, -2)
            bar:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0,  2)
            bar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
            bar:Hide()

            local iLbl = item:CreateFontString(nil, "OVERLAY")
            iLbl:SetPoint("LEFT",  item, "LEFT",  10, 0)
            iLbl:SetPoint("RIGHT", item, "RIGHT", -4, 0)
            ApplyFont(iLbl, 10)
            iLbl:SetJustifyH("LEFT")
            iLbl:SetText(opt.label)

            local function Paint()
                if opt.key == currentKey then
                    fill:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.15)
                    iLbl:SetTextColor(1, 1, 1, 1)
                    bar:Show()
                else
                    fill:SetColorTexture(0, 0, 0, 0)
                    iLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
                    bar:Hide()
                end
            end
            item._paint = Paint

            item:SetScript("OnEnter", function()
                if opt.key ~= currentKey then
                    fill:SetColorTexture(T.bgHover[1], T.bgHover[2], T.bgHover[3], 1)
                    iLbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
                end
            end)
            item:SetScript("OnLeave", Paint)
            item:SetScript("OnClick", function()
                currentKey = opt.key
                lbl:SetText(opt.label)
                for _, ch in ipairs({ popup:GetChildren() }) do
                    if ch._paint then ch._paint() end
                end
                CloseDD()
                onSelect(opt.key)
            end)
        end
    end

    local function OpenDD()
        -- Close any other open dropdown (GUI:CreateDropdown or another CreateDropdown)
        if GUI._activeDropdownClose then GUI._activeDropdownClose(true) end
        GUI._activeDropdownClose = CloseDD

        AnimateArrow(ARROW_OPEN)

        if not popup then BuildPopup() end

        for _, ch in ipairs({ popup:GetChildren() }) do
            if ch._paint then ch._paint() end
        end

        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)
        popup:SetHeight(1)
        popup:SetClipsChildren(true)
        popup:Show()
        btn:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)

        -- Slide-down open animation
        local fullH     = popup._fullH
        local startTime = GetTime()
        isClosing = false
        if menuTicker then menuTicker:Cancel(); menuTicker = nil end
        menuTicker = C_Timer.NewTicker(0.016, function()
            if isClosing then return end
            local p = math.min((GetTime() - startTime) / ANIM_DUR, 1)
            p = 1 - (1-p)*(1-p)  -- ease-out
            popup:SetHeight(math.max(1, math.floor(p * fullH + 0.5)))
            if p >= 1 then
                popup:SetHeight(fullH)
                popup:SetClipsChildren(false)
                menuTicker:Cancel(); menuTicker = nil
            end
        end)

        -- Reuse shared click-outside catcher
        sharedCloser:SetScript("OnMouseDown", function() CloseDD() end)
        sharedCloser:Show()
        closer = true
    end

    btn:SetScript("OnClick", function()
        if popup and popup:IsShown() then CloseDD() else OpenDD() end
    end)
    btn:SetScript("OnEnter", function()
        if not (popup and popup:IsShown()) then
            AnimateBorderFocus(btn, true)
        end
    end)
    btn:SetScript("OnLeave", function()
        if not (popup and popup:IsShown()) then
            AnimateBorderFocus(btn, false)
        end
    end)

    function btn:SetValue(key)
        currentKey = key
        for _, opt in ipairs(options) do
            if opt.key == key then lbl:SetText(opt.label); return end
        end
    end
    function btn:GetValue() return currentKey end

    return btn
end

-- ============================================================
-- Content Registry
-- ============================================================
GUI.ContentBuilders = {}

function GUI:RegisterContent(itemId, builderFn)
    self.ContentBuilders[itemId] = builderFn
end

-- Sidebar config — add sections / items as the addon grows
GUI.SidebarConfig = {
    {
        type = "section", id = "general", text = "GENERAL",
        defaultExpanded = true,
        items = {
            { id = "home", text = "Home" },
        },
    },
    {
        type = "section", id = "combat", text = "COMBAT",
        defaultExpanded = true,
        items = {
            { id = "tankmd",           text = "Auto Misdirection"  },
            { id = "bloodlustalert",   text = "Bloodlust Alert"    },
            { id = "combatcross",      text = "Combat Cross"       },
            { id = "combattimer",      text = "Combat Timer"       },
            { id = "cursor",           text = "Cursor Circle"      },
            { id = "deathalert",       text = "Death Alert"        },
            { id = "gatewayalert",     text = "Gateway Alert"      },
            { id = "movementalert",    text = "Movement Alert"     },
            { id = "spelleffectalpha", text = "Spell Effect Alpha" },
        },
    },
    {
        type = "section", id = "mythicplus", text = "MYTHIC PLUS",
        defaultExpanded = true,
        items = {
            { id = "focustargetmarker", text = "Focus Target Marker"  },
            { id = "groupjoinedreminder", text = "Group Joined Reminder" },
            { id = "autoplaystyle",     text = "M+ Auto Playstyle"    },
        },
    },
    {
        type = "section", id = "items", text = "ITEMS",
        defaultExpanded = true,
        items = {
            { id = "filterexpansiononly", text = "Filter Expansion Only" },
            { id = "autobuy",      text = "Auto Buy"       },
            { id = "craftshopper", text = "CraftShopper"   },
            { id = "fastloot",     text = "Fast Loot"      },
            { id = "durability",   text = "Repair Warning" },
        },
    },
    {
        type = "section", id = "social", text = "SOCIAL",
        defaultExpanded = true,
        items = {
            { id = "invitationgroupe", text = "Group Invitations" },
            { id = "whisperalert",     text = "Whisper Alert"     },
        },
    },
    {
        type = "section", id = "automation", text = "AUTOMATION",
        defaultExpanded = true,
        items = {
            { id = "combatlog",  text = "Auto Combat Log" },
            { id = "automation", text = "Automation"      },
            { id = "meterreset", text = "Meter Reset"     },
        },
    },
    {
        type = "section", id = "interface", text = "INTERFACE",
        defaultExpanded = true,
        items = {
            { id = "cleanobjectivetrackerheader", text = "Clean Objective Header"  },
            { id = "copytooltip",                 text = "Copy Anything"           },
            { id = "enhancedobjectivetext",       text = "Enhanced Objective Text" },
            { id = "drawer",                      text = "Minimap Drawer"          },
            { id = "editmode",                    text = "Nudge Tool"              },
            { id = "performance",                 text = "Performance"             },
            { id = "silvermoonmapicon",            text = "Silvermoon Map Icons"    },
        },
    },
    {
        type = "section", id = "customise", text = "CUSTOMISE",
        defaultExpanded = true,
        items = {
            { id = "cvars",  text = "CVars"  },
            { id = "themes", text = "Themes" },
        },
    },
}

-- ============================================================
-- Widget: Animated Toggle
-- ============================================================
-- moduleName (optional): if provided, shows a coloured "ModuleName: On/Off"
-- notification in the centre of the screen when the toggle is clicked.
function GUI:CreateToggle(parent, labelText, initialState, onChange, moduleName)
    local TOGGLE_W  = 40   -- was 48 — slightly narrower
    local TOGGLE_H  = 12   -- was 24 — halved
    local KNOB_SIZE = 10   -- fits inside TOGGLE_H with 1px padding each side
    local KNOB_PAD  = 1
    local ANIM_DUR  = 0.18
    local OFF_X     = KNOB_PAD
    local ON_X      = TOGGLE_W - KNOB_SIZE - KNOB_PAD  -- 29

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(24)   -- inline: toggle + label on the same line

    -- Toggle anchored to the left edge, vertically centred
    local toggle = CreateFrame("Frame", nil, row, "BackdropTemplate")
    toggle:SetSize(TOGGLE_W, TOGGLE_H)
    toggle:SetPoint("LEFT", row, "LEFT", 0, 0)
    SetBackdrop(toggle, T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)

    -- Label fills the remaining space on the right, vertically centred
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("LEFT",  toggle, "RIGHT", T.padding, 0)
    label:SetPoint("RIGHT", row,    "RIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
    ApplyFont(label, 11)
    label:SetText(labelText or "")
    label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    row.label = label

    local knob = CreateFrame("Frame", nil, toggle, "BackdropTemplate")
    knob:SetSize(KNOB_SIZE, KNOB_SIZE)
    knob:SetPoint("LEFT", toggle, "LEFT", OFF_X, 0)
    SetBackdrop(knob, 0.05, 0.05, 0.05, 1, T.border[1], T.border[2], T.border[3], 1)

    local knobTex = knob:CreateTexture(nil, "ARTWORK")
    knobTex:SetAllPoints()
    knobTex:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.4)

    local slideGroup = knob:CreateAnimationGroup()
    local slideAnim  = slideGroup:CreateAnimation("Translation")
    slideAnim:SetDuration(ANIM_DUR)
    slideAnim:SetSmoothing("OUT")

    local colorGroup = toggle:CreateAnimationGroup()
    colorGroup:SetLooping("NONE")
    colorGroup:CreateAnimation("Animation"):SetDuration(ANIM_DUR)

    local state = initialState or false
    local isAnimating = false
    local knobR, knobG, knobB, knobA = T.accent[1], T.accent[2], T.accent[3], 0.4
    local colorFrom, colorTo = {}, {}

    colorGroup:SetScript("OnUpdate", function(self)
        local p = self:GetProgress() or 0
        toggle:SetBackdropColor(
            colorFrom.bgR + (colorTo.bgR - colorFrom.bgR) * p,
            colorFrom.bgG + (colorTo.bgG - colorFrom.bgG) * p,
            colorFrom.bgB + (colorTo.bgB - colorFrom.bgB) * p, 1)
        local kR = colorFrom.kR + (colorTo.kR - colorFrom.kR) * p
        local kG = colorFrom.kG + (colorTo.kG - colorFrom.kG) * p
        local kB = colorFrom.kB + (colorTo.kB - colorFrom.kB) * p
        local kA = colorFrom.kA + (colorTo.kA - colorFrom.kA) * p
        knobTex:SetColorTexture(kR, kG, kB, kA)
        knobR, knobG, knobB, knobA = kR, kG, kB, kA
    end)
    colorGroup:SetScript("OnFinished", function()
        toggle:SetBackdropColor(colorTo.bgR, colorTo.bgG, colorTo.bgB, 1)
        knobTex:SetColorTexture(colorTo.kR, colorTo.kG, colorTo.kB, colorTo.kA)
        knobR, knobG, knobB, knobA = colorTo.kR, colorTo.kG, colorTo.kB, colorTo.kA
    end)

    local function UpdateColors(toState, instant)
        if instant then
            local bg = toState and T.accent[1]*0.45 or T.bgMedium[1]
            toggle:SetBackdropColor(bg, toState and T.accent[2]*0.45 or T.bgMedium[2],
                toState and T.accent[3]*0.45 or T.bgMedium[3], 1)
            local kA = toState and 1 or 0.35
            knobTex:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], kA)
            knobR, knobG, knobB, knobA = T.accent[1], T.accent[2], T.accent[3], kA
        else
            colorGroup:Stop()
            colorFrom.bgR, colorFrom.bgG, colorFrom.bgB = toggle:GetBackdropColor()
            colorFrom.kR, colorFrom.kG, colorFrom.kB, colorFrom.kA = knobR, knobG, knobB, knobA
            colorTo.bgR = toState and T.accent[1]*0.45 or T.bgMedium[1]
            colorTo.bgG = toState and T.accent[2]*0.45 or T.bgMedium[2]
            colorTo.bgB = toState and T.accent[3]*0.45 or T.bgMedium[3]
            colorTo.kR, colorTo.kG, colorTo.kB = T.accent[1], T.accent[2], T.accent[3]
            colorTo.kA = toState and 1 or 0.35
            colorGroup:Play()
        end
    end

    local function AnimateTo(toState, instant)
        if isAnimating and not instant then return end
        isAnimating = true
        state = toState
        local targetX  = toState and ON_X or OFF_X
        local currentX = select(4, knob:GetPoint()) or OFF_X
        local deltaX   = targetX - currentX
        if instant or math.abs(deltaX) < 1 then
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", toggle, "LEFT", targetX, 0)
            UpdateColors(toState, true)
            isAnimating = false
        else
            UpdateColors(toState, false)
            slideGroup:Stop()
            knob:ClearAllPoints()
            knob:SetPoint("LEFT", toggle, "LEFT", currentX, 0)
            slideAnim:SetOffset(deltaX, 0)
            slideGroup:SetScript("OnFinished", function()
                knob:ClearAllPoints()
                knob:SetPoint("LEFT", toggle, "LEFT", targetX, 0)
                isAnimating = false
            end)
            slideGroup:Play()
        end
    end

    AnimateTo(state, true)

    local btn = CreateFrame("Button", nil, toggle)
    btn:SetAllPoints()
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function()
        if slideGroup:IsPlaying() or colorGroup:IsPlaying() then return end
        local newState = not state
        AnimateTo(newState, false)
        if onChange then C_Timer.After(ANIM_DUR, function()
            onChange(newState)
            -- Update sidebar checkmark dots in-place — no hide/re-show so OnEnter never re-fires
            if moduleName then GUI.UpdateSidebarCheckmarks() end
        end) end
        -- On/Off notification (only for named modules)
        if moduleName and SP.ShowNotification then
            -- Accent colour for the module name + colon
            local acc = string.format("%02X%02X%02X",
                math.floor(T.accent[1]*255+0.5),
                math.floor(T.accent[2]*255+0.5),
                math.floor(T.accent[3]*255+0.5))
            -- Lighter tint for "On" / "Off": 50 % lerp toward white
            local lr = T.accent[1] + (1 - T.accent[1]) * 0.5
            local lg = T.accent[2] + (1 - T.accent[2]) * 0.5
            local lb = T.accent[3] + (1 - T.accent[3]) * 0.5
            local light = string.format("%02X%02X%02X",
                math.floor(lr*255+0.5),
                math.floor(lg*255+0.5),
                math.floor(lb*255+0.5))
            local msg = newState
                and ("|cff" .. acc .. moduleName .. ":|r |cff" .. light .. "On|r")
                or  ("|cff" .. acc .. moduleName .. ":|r |cff" .. light .. "Off|r")
            SP.ShowNotification(msg)
        end
    end)
    btn:SetScript("OnEnter", function()
        knobTex:SetColorTexture(
            math.min(T.accent[1]*1.25, 1), math.min(T.accent[2]*1.25, 1),
            math.min(T.accent[3]*1.25, 1), state and 1 or 0.55)
    end)
    btn:SetScript("OnLeave", function()
        knobTex:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], state and 1 or 0.35)
        knobR, knobG, knobB, knobA = T.accent[1], T.accent[2], T.accent[3], state and 1 or 0.35
    end)

    toggle.SetValue = function(_, val, instant)
        if val ~= state then AnimateTo(val, instant) end
    end
    toggle.GetValue = function() return state end

    function row:SetEnabled(en)
        toggle:SetAlpha(en and 1 or 0.4)
        label:SetAlpha(en and 1 or 0.4)
        btn:EnableMouse(en)
    end

    row.toggle = toggle
    return row
end

-- ============================================================
-- Widget: Dropdown  (with animated arrow + sliding menu)
-- ============================================================
function GUI:CreateDropdown(parent, labelText, options, currentValue, onChange, fontResolver)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(40)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
    label:SetJustifyH("LEFT")
    ApplyFont(label, 11)
    label:SetText(labelText or "")
    label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

    local MAX_BTN_W = 200
    local btn = CreateFrame("Button", nil, row, "BackdropTemplate")
    btn:SetHeight(22)
    btn:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -16)
    btn:SetWidth(MAX_BTN_W)
    SetBackdrop(btn, T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)

    local valText = btn:CreateFontString(nil, "OVERLAY")
    valText:SetPoint("LEFT",  btn, "LEFT",  6,   0)
    valText:SetPoint("RIGHT", btn, "RIGHT", -20, 0)
    valText:SetJustifyH("LEFT")
    ApplyFont(valText, 11)
    valText:SetText(currentValue or "")
    valText:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)

    local arrowTex = btn:CreateTexture(nil, "OVERLAY")
    arrowTex:SetSize(12, 12)
    arrowTex:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    arrowTex:SetTexture(ARROW_TEX)
    arrowTex:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
    arrowTex:SetTexelSnappingBias(0)
    arrowTex:SetSnapToPixelGrid(false)

    -- Animation state: arrow closed = pointing left (-pi/2 ◄), open = pointing down (0 ▼)
    -- collapse.tga natural direction at rotation 0 is DOWN (▼). WoW rotates CCW.
    -- -pi/2 = 90° CW rotation → DOWN becomes LEFT (◄).
    local ARROW_CLOSED = -math.pi / 2
    local ARROW_OPEN   =  0
    local ANIM_DUR     = 0.15
    local arrowCurrent = ARROW_CLOSED
    arrowTex:SetRotation(arrowCurrent)

    local arrowTicker = nil
    local function AnimateArrow(targetRot)
        if arrowTicker then arrowTicker:Cancel(); arrowTicker = nil end
        local startRot  = arrowCurrent
        local startTime = GetTime()
        arrowTicker = C_Timer.NewTicker(0.016, function()
            local p = math.min((GetTime() - startTime) / ANIM_DUR, 1)
            p = 1 - (1-p)*(1-p)  -- ease-out quadratic
            arrowCurrent = startRot + (targetRot - startRot) * p
            arrowTex:SetRotation(arrowCurrent)
            if p >= 1 then
                arrowCurrent = targetRot
                arrowTex:SetRotation(targetRot)
                arrowTicker:Cancel(); arrowTicker = nil
            end
        end)
    end

    btn:SetScript("OnEnter", function() AnimateBorderFocus(btn, true)  end)
    btn:SetScript("OnLeave", function() AnimateBorderFocus(btn, false) end)

    -- Build popup menu ONCE — reused on every open (no per-open frame allocation)
    local itemH       = 22
    local MAX_VISIBLE = 8
    local SBAR_W      = 4   -- scrollbar track/thumb width in pixels
    local SBAR_GAP    = 3   -- gap between list items and scrollbar
    local fullH       = #options * itemH + 2
    local visH        = math.min(fullH, MAX_VISIBLE * itemH + 2)
    local maxScroll   = math.max(0, fullH - visH)
    local needsBar    = maxScroll > 0
    local scrollOffset = 0
    -- Item area is narrowed when a scrollbar is present
    local itemAreaW   = btn:GetWidth() - (needsBar and (SBAR_W + SBAR_GAP) or 0)

    local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(200)
    menu:SetSize(btn:GetWidth(), visH)
    menu:SetClipsChildren(true)
    SetBackdrop(menu, T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    menu:Hide()

    -- Inner scroll container — all items live here; shifted up to scroll
    local inner = CreateFrame("Frame", nil, menu)
    inner:SetSize(itemAreaW, fullH)
    inner:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, 0)

    -- Visible scrollbar (track + thumb), only when the list is taller than MAX_VISIBLE
    local UpdateScrollbar
    if needsBar then
        local sbarTrack = menu:CreateTexture(nil, "ARTWORK")
        sbarTrack:SetWidth(SBAR_W)
        sbarTrack:SetPoint("TOPRIGHT",    menu, "TOPRIGHT",    0, -2)
        sbarTrack:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", 0,  2)
        sbarTrack:SetColorTexture(T.bgDark[1], T.bgDark[2], T.bgDark[3], 1)

        local sbarThumb = menu:CreateTexture(nil, "OVERLAY")
        sbarThumb:SetWidth(SBAR_W)
        sbarThumb:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.75)

        UpdateScrollbar = function()
            local trackH = visH - 4
            local thumbH = math.max(16, trackH * visH / fullH)
            local range  = trackH - thumbH
            local thumbY = (scrollOffset / maxScroll) * range
            sbarThumb:SetHeight(thumbH)
            sbarThumb:ClearAllPoints()
            sbarThumb:SetPoint("TOPRIGHT", menu, "TOPRIGHT", 0, -2 - thumbY)
        end
    end

    local function ScrollTo(offset)
        scrollOffset = math.max(0, math.min(offset, maxScroll))
        inner:ClearAllPoints()
        inner:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, scrollOffset)
        if UpdateScrollbar then UpdateScrollbar() end
    end

    if needsBar then
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", function(_, delta)
            ScrollTo(scrollOffset - delta * itemH * 3)
        end)
    end

    local menuItems  = {}
    local menuTicker = nil
    local isClosing  = false
    local CloseMenu  -- forward-declare so OnClick closures capture the upvalue

    -- Populate items once; _paint() updates selection highlight on every open
    for i, opt in ipairs(options) do
        local item = CreateFrame("Button", nil, inner)
        item:SetHeight(itemH)
        item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -(i-1)*itemH - 1)
        item:SetPoint("RIGHT",   inner, "RIGHT",  -1, 0)
        local iLbl = item:CreateFontString(nil, "OVERLAY")
        iLbl:SetPoint("LEFT", item, "LEFT", 8, 0)
        ApplyFont(iLbl, 11)
        if fontResolver then
            local fp = fontResolver(opt)
            if fp then iLbl:SetFont(fp, 11, "") end
        end
        iLbl:SetText(opt)
        local bar = item:CreateTexture(nil, "OVERLAY")
        bar:SetWidth(2)
        bar:SetPoint("TOPLEFT",    item, "TOPLEFT",    0, 0)
        bar:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, 0)
        bar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
        bar:Hide()
        local function Paint()
            local isSel = (opt == currentValue)
            iLbl:SetTextColor(
                isSel and T.accent[1] or T.textSecondary[1],
                isSel and T.accent[2] or T.textSecondary[2],
                isSel and T.accent[3] or T.textSecondary[3], 1)
            if isSel then bar:Show() else bar:Hide() end
        end
        item._paint = Paint
        item:SetScript("OnEnter", function()
            iLbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        end)
        item:SetScript("OnLeave", Paint)
        item:SetScript("OnClick", function()
            currentValue = opt; valText:SetText(opt)
            if onChange then onChange(opt) end
            CloseMenu()
        end)
        table.insert(menuItems, item)
    end

    local function DoHide()
        isClosing = false
        if menuTicker then menuTicker:Cancel(); menuTicker = nil end
        sharedCloser:Hide()
        menu:Hide()
    end

    CloseMenu = function(instant)
        if GUI._activeDropdownClose == CloseMenu then
            GUI._activeDropdownClose = nil
        end
        AnimateArrow(ARROW_CLOSED)
        if instant then DoHide(); return end
        if isClosing then return end
        isClosing = true
        local startH    = menu:GetHeight()
        local startTime = GetTime()
        local CLOSE_DUR = 0.12
        if menuTicker then menuTicker:Cancel(); menuTicker = nil end
        menuTicker = C_Timer.NewTicker(0.016, function()
            local p = math.min((GetTime() - startTime) / CLOSE_DUR, 1)
            p = p * p
            menu:SetHeight(math.max(1, math.floor(startH * (1-p) + 0.5)))
            if p >= 1 then menuTicker:Cancel(); menuTicker = nil; DoHide() end
        end)
    end

    btn:SetScript("OnClick", function()
        if menu:IsShown() then CloseMenu(); return end
        if GUI._activeDropdownClose then GUI._activeDropdownClose(true) end

        AnimateArrow(ARROW_OPEN)

        -- Repaint items to reflect current selection before showing
        for _, item in ipairs(menuItems) do item._paint() end

        menu:SetSize(btn:GetWidth(), 1)
        menu:SetClipsChildren(true)
        menu:ClearAllPoints()
        menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -1)

        -- Always open from the top
        ScrollTo(0)

        menu:Show()
        btn:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)

        isClosing = false
        local startTime = GetTime()
        if menuTicker then menuTicker:Cancel(); menuTicker = nil end
        menuTicker = C_Timer.NewTicker(0.016, function()
            if isClosing then return end
            local p = math.min((GetTime() - startTime) / ANIM_DUR, 1)
            p = 1 - (1-p)*(1-p)
            menu:SetHeight(math.max(1, math.floor(p * visH + 0.5)))
            if p >= 1 then
                menu:SetHeight(visH)
                menuTicker:Cancel(); menuTicker = nil
            end
        end)

        GUI._activeDropdownClose = CloseMenu
        sharedCloser:SetScript("OnMouseDown", function() CloseMenu() end)
        sharedCloser:Show()
    end)

    row.btn = btn
    function row:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        btn:EnableMouse(en)
    end
    row.SetValue = function(val) currentValue = val; valText:SetText(val) end

    -- Close the popup menu instantly when the row is hidden (e.g. page switch).
    -- The menu is parented to UIParent and won't hide automatically with the row.
    row:SetScript("OnHide", function() CloseMenu(true) end)

    -- Responsive width: shrink to fit HRow cells, but never grow past MAX_BTN_W.
    local _labelOffset = 0  -- px reserved on the left for an inline label
    row:SetScript("OnSizeChanged", function(self, w)
        if w < 4 then return end
        local bw = math.min(w - _labelOffset, MAX_BTN_W)
        if bw < 20 then bw = 20 end
        btn:SetWidth(bw)
        local newItemAreaW = bw - (needsBar and (SBAR_W + SBAR_GAP) or 0)
        if newItemAreaW > 0 then inner:SetWidth(newItemAreaW) end
    end)

    -- Repositions the label to the left of the button (inline mode).
    -- px = horizontal space reserved for the label text.
    function row:SetLabelInline(px)
        _labelOffset = px or 50
        label:ClearAllPoints()
        label:SetPoint("LEFT", row, "LEFT", 0, -22)  -- vertically centred with the button
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", row, "TOPLEFT", _labelOffset, -16)
        -- Re-trigger sizing with the new offset
        local w = row:GetWidth()
        if w and w > 1 then
            local bw = math.min(w - _labelOffset, MAX_BTN_W)
            if bw < 20 then bw = 20 end
            btn:SetWidth(bw)
            local newItemAreaW = bw - (needsBar and (SBAR_W + SBAR_GAP) or 0)
            if newItemAreaW > 0 then inner:SetWidth(newItemAreaW) end
        end
    end

    return row
end

-- ============================================================
-- Widget: Font Dropdown  (LSM list + renders names in their own typeface)
-- ============================================================
function GUI:CreateFontDropdown(parent, labelText, currentValue, onChange)
    local fontNames = SP.GetFontList()
    -- Ensure currentValue is in the list; fall back to first entry
    local found = false
    for _, n in ipairs(fontNames) do
        if n == currentValue then found = true; break end
    end
    if not found and #fontNames > 0 then currentValue = fontNames[1] end
    return GUI:CreateDropdown(parent, labelText, fontNames, currentValue, onChange,
        function(name) return SP.GetFontPath(name) end)
end

-- ============================================================
-- Widget: Slider
-- ============================================================
function GUI:CreateSlider(parent, labelText, minVal, maxVal, step, currentValue, onChange)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(44)

    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
    label:SetJustifyH("LEFT")
    ApplyFont(label, 11)
    label:SetText(labelText or "")
    label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

    local valBox = CreateFrame("EditBox", nil, row, "BackdropTemplate")
    valBox:SetSize(52, 20)           -- wider to accommodate negative values (e.g. "-100")
    valBox:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -16)
    valBox:SetAutoFocus(false)
    -- SetNumeric(true) removed: it strips the minus sign, breaking negative slider values
    valBox:SetMaxLetters(6)          -- allow "-1000" (5 chars) plus sign
    ApplyFont(valBox, 11)
    valBox:SetJustifyH("CENTER")
    valBox:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
    SetBackdrop(valBox, T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)

    local slider = CreateFrame("Slider", nil, row, "BackdropTemplate")
    slider:SetPoint("TOPLEFT",  row,    "TOPLEFT",  0,  -16)
    slider:SetPoint("TOPRIGHT", valBox, "TOPLEFT",  -6, 0)
    slider:SetHeight(20)
    slider:SetOrientation("HORIZONTAL")
    slider:SetValueStep(step or 1)
    slider:SetMinMaxValues(minVal or 0, maxVal or 100)
    slider:SetObeyStepOnDrag(true)

    -- ── Rail (BACKGROUND → BORDER → ARTWORK → OVERLAY thumb) ─
    -- Use bgDark so the rail is visible against the bgLight card background.
    local trackBg = slider:CreateTexture(nil, "BACKGROUND")
    trackBg:SetPoint("LEFT",  slider, "LEFT",  0, 0)
    trackBg:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    trackBg:SetHeight(6)
    trackBg:SetColorTexture(T.bgDark[1], T.bgDark[2], T.bgDark[3], 1)

    -- 1-px border around the rail (BORDER layer sits below ARTWORK fill)
    local bT = slider:CreateTexture(nil, "BORDER")
    bT:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    bT:SetHeight(1)
    bT:SetPoint("TOPLEFT",  trackBg, "TOPLEFT",  0, 0)
    bT:SetPoint("TOPRIGHT", trackBg, "TOPRIGHT", 0, 0)

    local bB = slider:CreateTexture(nil, "BORDER")
    bB:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    bB:SetHeight(1)
    bB:SetPoint("BOTTOMLEFT",  trackBg, "BOTTOMLEFT",  0, 0)
    bB:SetPoint("BOTTOMRIGHT", trackBg, "BOTTOMRIGHT", 0, 0)

    local bL = slider:CreateTexture(nil, "BORDER")
    bL:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    bL:SetWidth(1)
    bL:SetPoint("TOPLEFT",    trackBg, "TOPLEFT",    0, 0)
    bL:SetPoint("BOTTOMLEFT", trackBg, "BOTTOMLEFT", 0, 0)

    local bR = slider:CreateTexture(nil, "BORDER")
    bR:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)
    bR:SetWidth(1)
    bR:SetPoint("TOPRIGHT",    trackBg, "TOPRIGHT",    0, 0)
    bR:SetPoint("BOTTOMRIGHT", trackBg, "BOTTOMRIGHT", 0, 0)

    -- Accent fill: 1 px inset from left/right borders so borders always show
    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", slider, "LEFT", 1, 0)
    fill:SetHeight(4)
    fill:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.85)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(4, 16)
    thumb:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
    slider:SetThumbTexture(thumb)

    local value = currentValue or minVal or 0
    slider:SetValue(value)
    valBox:SetText(tostring(value))

    local function UpdateFill(v)
        local range = maxVal - minVal
        if range <= 0 then return end
        local pct  = (v - minVal) / range
        local w    = slider:GetWidth()
        -- Subtract 2 px for the 1-px left + right rail borders so fill stays inside
        if w and w > 2 then fill:SetWidth(math.max(1, pct * (w - 2))) end
    end
    UpdateFill(value)

    local throttleTimer
    slider:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / (step or 1) + 0.5) * (step or 1)
        valBox:SetText(tostring(v))
        UpdateFill(v)
        if onChange then
            if throttleTimer then throttleTimer:Cancel() end
            throttleTimer = C_Timer.NewTimer(0.15, function() onChange(v) end)
        end
    end)
    slider:SetScript("OnSizeChanged", function() UpdateFill(slider:GetValue()) end)

    valBox:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then slider:SetValue(math.max(minVal, math.min(maxVal, v))) end
        self:ClearFocus()
    end)
    valBox:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(slider:GetValue())); self:ClearFocus()
    end)
    valBox:SetScript("OnEditFocusGained", function() AnimateBorderFocus(valBox, true)  end)
    valBox:SetScript("OnEditFocusLost",   function() AnimateBorderFocus(valBox, false) end)

    row.slider   = slider
    function row:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        slider:EnableMouse(en)
        valBox:SetEnabled(en)
    end
    row.SetValue = function(v) slider:SetValue(v); valBox:SetText(tostring(v)); UpdateFill(v) end

    -- Repositions the label to the left of the slider bar (inline mode).
    -- px = horizontal space reserved for the label text.
    function row:SetLabelInline(px)
        px = px or 60
        label:ClearAllPoints()
        label:SetPoint("LEFT", row, "LEFT", 0, -26)  -- vertically centred with the slider bar
        slider:ClearAllPoints()
        slider:SetPoint("TOPLEFT",  row,    "TOPLEFT",  px, -16)
        slider:SetPoint("TOPRIGHT", valBox, "TOPLEFT",  -6,   0)
    end

    return row
end

-- ============================================================
-- Widget: NativeSlider (MinimalSliderWithSteppersTemplate — ExwindTools approach)
-- Uses the built-in WoW template so SetWidth() resizes it correctly inside HRows.
-- ============================================================
function GUI:CreateNativeSlider(parent, labelText, minVal, maxVal, curVal, step, onChange)
    local slider = CreateFrame("Slider", nil, parent, "MinimalSliderWithSteppersTemplate")

    -- Label above the slider track
    if slider.Title then
        slider.Title:SetText(labelText or "")
    end

    -- Value display: update on change
    local function UpdateText(v)
        if slider.ValueText then
            slider.ValueText:SetText(tostring(math.floor(v + 0.5)))
        end
    end

    -- Register callback once per widget (ExwindTools pattern)
    if not slider._spInit then
        slider:RegisterCallback("OnValueChanged", function(s, v)
            if s._onChange then s._onChange(v) end
            UpdateText(v)
        end, slider)
        slider._spInit = true
    end
    slider._onChange = onChange

    -- Init slider (sets min/max/step/current value)
    local steps = (maxVal - minVal) / (step or 1)
    if slider.Init then
        slider:Init(curVal or minVal, minVal, maxVal, steps)
    end
    UpdateText(curVal or minVal)

    -- SetEnabled support for childRows enable/disable
    function slider:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        self:EnableMouse(en)
    end

    return slider
end

-- ============================================================
-- Widget: Button
-- ============================================================
function GUI:CreateButton(parent, text, onClick, width, height)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 100, height or 24)
    SetBackdrop(btn, T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)

    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetAllPoints(); ApplyFont(lbl, 12)
    lbl:SetText(text or "")
    lbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
    btn.lbl = lbl  -- expose for callers that want to update the label text

    btn:SetScript("OnEnter", function() AnimateBorderFocus(btn, true)  end)
    btn:SetScript("OnLeave", function() AnimateBorderFocus(btn, false) end)
    btn:SetScript("OnClick", onClick or function() end)
    return btn
end

-- ============================================================
-- Widget: Anchor Selector  (3×3 grid of WoW anchor point buttons)
-- ============================================================
local ANCHOR_GRID = {
    { "TOPLEFT",    "TOP",    "TOPRIGHT"    },
    { "LEFT",       "CENTER", "RIGHT"       },
    { "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
}
local ANCHOR_BTN_SIZE = 33
local ANCHOR_PAD      = 3

function GUI:CreateAnchorSelector(parent, currentAnchor, onChange)
    local selected = currentAnchor or "CENTER"
    local GRID_W = ANCHOR_BTN_SIZE * 3 + ANCHOR_PAD * 2
    local GRID_H = ANCHOR_BTN_SIZE * 3 + ANCHOR_PAD * 2

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(GRID_W, GRID_H)

    local allBtns = {}

    local function RefreshBtns()
        for _, btn in ipairs(allBtns) do
            local isSel = (btn.anchorPoint == selected)
            if isSel then
                btn:SetBackdropColor(T.accent[1], T.accent[2], T.accent[3], 0.75)
                btn:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
                if btn._lbl then btn._lbl:SetTextColor(1, 1, 1, 1) end
            else
                btn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
                btn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
                if btn._lbl then btn._lbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.8) end
            end
        end
    end

    for ri, row in ipairs(ANCHOR_GRID) do
        for ci, ap in ipairs(row) do
            local btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
            btn:SetSize(ANCHOR_BTN_SIZE, ANCHOR_BTN_SIZE)
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                (ci - 1) * (ANCHOR_BTN_SIZE + ANCHOR_PAD),
                -(ri - 1) * (ANCHOR_BTN_SIZE + ANCHOR_PAD))
            btn.anchorPoint = ap
            btn:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })

            btn:SetScript("OnClick", function()
                selected = ap
                -- Cancel any running hover animation before RefreshBtns snaps colours.
                if btn._borderTicker then btn._borderTicker:Cancel(); btn._borderTicker = nil end
                RefreshBtns()
                if onChange then onChange(ap) end
            end)
            btn:SetScript("OnEnter", function()
                if ap ~= selected then AnimateBorderFocus(btn, true) end
            end)
            btn:SetScript("OnLeave", function()
                -- Cancel hover animation; RefreshBtns sets the correct final colour.
                if btn._borderTicker then btn._borderTicker:Cancel(); btn._borderTicker = nil end
                RefreshBtns()
            end)
            table_insert(allBtns, btn)
        end
    end

    RefreshBtns()
    frame.GetValue = function() return selected end
    frame.SetValue = function(_, v) selected = v; RefreshBtns() end
    return frame
end

-- ============================================================
-- ============================================================
-- Anchor Picker Overlay  (singleton, lazy-created)
-- Full-screen TOOLTIP-strata frame that intercepts the next
-- left-click so the user can visually pick any frame as anchor.
-- Usage: GetAnchorPickerOverlay():Activate(callback)
-- ============================================================
local _anchorPicker = nil
local function GetAnchorPickerOverlay()
    if _anchorPicker then return _anchorPicker end

    -- ── The overlay does NOT block mouse events (EnableMouse false).
    -- Instead OnUpdate polls IsMouseButtonDown() so GetMouseFocus() always
    -- reflects the real frame under the cursor (same technique as NorskenUI).
    local picker = CreateFrame("Frame", "SP_AnchorPickerOverlay", UIParent)
    picker:SetFrameStrata("TOOLTIP")
    picker:SetAllPoints(UIParent)
    picker:EnableMouse(false)   -- pass-through: clicks reach the actual frames
    picker:Hide()

    -- Accent highlight border that tracks the hovered frame
    local hlBox = CreateFrame("Frame", nil, picker, "BackdropTemplate")
    hlBox:SetFrameStrata("TOOLTIP")
    hlBox:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
    hlBox:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
    hlBox:Hide()

    -- Instruction bar at the bottom of the screen
    local barBg = CreateFrame("Frame", nil, picker, "BackdropTemplate")
    barBg:SetSize(500, 40)
    barBg:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 60)
    barBg:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    barBg:SetBackdropColor(0.05, 0.05, 0.05, 0.93)
    barBg:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)

    local barLbl = barBg:CreateFontString(nil, "OVERLAY")
    barLbl:SetPoint("CENTER", barBg, "CENTER", 0, 0)
    ApplyFont(barLbl, 11)
    barLbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
    barLbl:SetText(
        "|cffFFFFFF Left-click|r any frame to select it as anchor   "..
        "|cffFFFFFF Right-click|r to cancel")

    local _cb          = nil
    local _curFocus    = nil   -- named ancestor frame currently highlighted
    local _curName     = nil
    local _waitRelease = false -- true while waiting for the opener click to be released

    -- Frame name prefixes / exact names that must never be selectable.
    local BLACKLIST = { "SP_", "NRSKNUIFrameChooser" }
    local function IsBlacklisted(name)
        if not name then return false end
        for _, pat in ipairs(BLACKLIST) do
            if name:sub(1, #pat) == pat then return true end
        end
        return false
    end

    -- Walk up from the raw GetMouseFocus result to find the nearest named
    -- ancestor that is not blacklisted.
    -- Anchoring to the named ancestor (instead of the raw focus) prevents the
    -- highlight from twitching as the cursor crosses unnamed child regions of
    -- the same logical frame.
    -- Returns (namedFrame, name). Falls back to (UIParent, "UIParent") so the
    -- user can always select UIParent by hovering over empty screen space.
    local function ResolveFrame(f)
        if not f then return UIParent, "UIParent" end
        local cur = f
        while cur do
            local name = cur.GetName and cur:GetName() or nil
            if name and name ~= "" and name ~= "WorldFrame" and not IsBlacklisted(name) then
                return cur, name
            end
            cur = cur.GetParent and cur:GetParent() or nil
        end
        return UIParent, "UIParent"
    end

    local function StopPicker()
        -- Do NOT nil the OnUpdate script — hidden frames don't fire it, so
        -- picker:Hide() pauses it naturally. Nil-ing would break re-activation.
        picker:Hide()
        hlBox:Hide()
        _curFocus    = nil
        _curName     = nil
        _waitRelease = false
    end

    local function Cancel()
        _cb = nil
        StopPicker()
    end

    local function Confirm()
        local cb   = _cb
        local name = _curName
        _cb = nil
        StopPicker()
        if cb and name then cb(name) end
    end

    picker:SetScript("OnUpdate", function()
        if not _cb then picker:Hide(); return end

        -- Wait for the activating click to be released so we don't fire
        -- Confirm() immediately on the "Select Frame" button click itself.
        if _waitRelease then
            if IsMouseButtonDown("LeftButton") then return end
            _waitRelease = false
        end

        -- Right-click → cancel
        if IsMouseButtonDown("RightButton") then
            Cancel()
            return
        end

        -- Get raw focus (passes through because EnableMouse is false on picker)
        local rawF = GetMouseFocus and GetMouseFocus() or nil
        if not rawF and GetMouseFoci then
            local foci = GetMouseFoci()
            rawF = foci and foci[1] or nil
        end

        -- Resolve to the named ancestor so the highlight stays stable when the
        -- cursor crosses unnamed child regions of the same logical frame.
        local namedF, name = ResolveFrame(rawF)

        -- Update tracking state when the target frame changes.
        if namedF ~= _curFocus then
            _curFocus = namedF
            _curName  = name
        end

        -- Position hlBox using absolute screen coords anchored to UIParent.
        -- Cross-frame anchors (SetPoint to an external frame) cause WoW's
        -- layout engine to jitter the child every tick → visible twitching.
        -- Reading GetLeft/GetBottom/GetWidth/GetHeight and anchoring to the
        -- static UIParent origin gives a rock-solid position.
        local fl = namedF:GetLeft()
        local fb = namedF:GetBottom()
        local fw = namedF:GetWidth()
        local fh = namedF:GetHeight()
        if fl and fb and fw and fh then
            hlBox:ClearAllPoints()
            hlBox:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", fl - 2, fb - 2)
            hlBox:SetSize(fw + 4, fh + 4)
            hlBox:Show()
        else
            hlBox:Hide()
        end

        -- Left-click → confirm
        if IsMouseButtonDown("LeftButton") and _curName then
            Confirm()
        end
    end)

    function picker:Activate(callback)
        _cb          = callback
        _curFocus    = nil
        _curName     = nil
        _waitRelease = true   -- ignore LeftButton until the opener click is released
        self:Show()
    end

    _anchorPicker = picker
    return picker
end

-- ============================================================
-- Helper: compact "pick anchor frame" button.
-- Small (w <= 28): renders a texture crosshair icon in the accent color —
--   avoids relying on Unicode symbols that Expressway doesn't cover.
-- Wide (w > 28): renders "Select Frame" text as before.
-- onPick(name) is called when the user selects a frame in the picker overlay.
-- ============================================================
local PICK_BTN_W = 24   -- width used for the inline pick button
local function MakePickBtn(container, x, y, w, onPick)
    local btn = CreateFrame("Frame", nil, container, "BackdropTemplate")
    btn:SetSize(w, 22)
    btn:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
    btn:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    btn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    btn:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 0.5)
    btn:EnableMouse(true)

    local iconAlpha = 0.85
    if w <= 28 then
        -- Draw a small crosshair with two solid-color texture bars.
        -- This works with any font including Expressway (no Unicode needed).
        local hBar = btn:CreateTexture(nil, "OVERLAY")
        hBar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], iconAlpha)
        hBar:SetSize(12, 2)
        hBar:SetPoint("CENTER", btn, "CENTER", 0, 0)

        local vBar = btn:CreateTexture(nil, "OVERLAY")
        vBar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], iconAlpha)
        vBar:SetSize(2, 12)
        vBar:SetPoint("CENTER", btn, "CENTER", 0, 0)

        -- Small dot in the centre to turn + into a target crosshair
        local dot = btn:CreateTexture(nil, "OVERLAY")
        dot:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], iconAlpha)
        dot:SetSize(4, 4)
        dot:SetPoint("CENTER", btn, "CENTER", 0, 0)

        btn._iconBars = { hBar, vBar, dot }

        btn:SetScript("OnEnter", function()
            btn:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
            btn:SetBackdropColor(T.accent[1]*0.12, T.accent[2]*0.12, T.accent[3]*0.12, 1)
            for _, bar in ipairs(btn._iconBars) do
                bar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
            end
            GameTooltip:SetOwner(btn, "ANCHOR_TOPRIGHT")
            GameTooltip:SetText("Pick Anchor Frame", 1, 1, 1)
            GameTooltip:AddLine("Click, then click any UI frame to use it as anchor.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            btn:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 0.5)
            btn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
            for _, bar in ipairs(btn._iconBars) do
                bar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], iconAlpha)
            end
            GameTooltip:Hide()
        end)
    else
        -- Wide button: text label
        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetAllPoints(btn)
        lbl:SetJustifyH("CENTER"); lbl:SetJustifyV("MIDDLE")
        ApplyFont(lbl, 11)
        lbl:SetText("Select Frame")
        lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], iconAlpha)

        btn:SetScript("OnEnter", function()
            btn:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
            btn:SetBackdropColor(T.accent[1]*0.12, T.accent[2]*0.12, T.accent[3]*0.12, 1)
            lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
            GameTooltip:SetOwner(btn, "ANCHOR_TOPRIGHT")
            GameTooltip:SetText("Pick Anchor Frame", 1, 1, 1)
            GameTooltip:AddLine("Click, then click any UI frame to use it as anchor.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            btn:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 0.5)
            btn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
            lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], iconAlpha)
            GameTooltip:Hide()
        end)
    end

    btn:SetScript("OnMouseDown", function()
        GetAnchorPickerOverlay():Activate(function(name)
            if onPick then onPick(name) end
        end)
    end)
    return btn
end

-- ============================================================
-- Widget: Anchor Row
-- strataOpts (optional) = { default="HIGH", onChange=fn }
--   With strataOpts: renders [Frame Strata | Anchored To] header row ABOVE
--                    the 2-col anchor grids.
--   Without:         classic 3-col layout (Anchor From | To Frame's | Anchored To).
-- Returns: row frame, row height
-- ============================================================
function GUI:CreateAnchorRow(parent, db, applyFn, strataOpts)
    local GRID_W    = ANCHOR_BTN_SIZE * 3 + ANCHOR_PAD * 2  -- 105 px (33*3+3*2)
    local GRID_H    = ANCHOR_BTN_SIZE * 3 + ANCHOR_PAD * 2  -- 105 px
    local COL_GAP   = 16
    local COL2_X    = GRID_W + COL_GAP                      -- 121
    local GRIDS_W   = COL2_X + GRID_W                       -- 226 (2 grid cols)

    local frameBox   -- exposed for SetEnabled
    local strataBtn  -- exposed for SetEnabled (strata layout only)
    local pickBtn    -- exposed for SetEnabled
    local fromSel, toSel

    local row
    local rowH

    if strataOpts then
        -- ── strataOpts layout ─────────────────────────────────────────────
        -- Header (40 px): [Frame Strata label+dropdown] | [Anchored To label + editbox + ⊙ btn inline]
        -- Gap (4 px)
        -- Grids  (121 px): [Anchor From 3×3] [To Frame's 3×3]
        local HEADER_H = 40  -- label(18) + editbox(22)
        local GRIDS_H  = 16 + GRID_H   -- label + grid = 121
        rowH = HEADER_H + 4 + GRIDS_H  -- 165

        row = CreateFrame("Frame", nil, parent)
        row:SetHeight(rowH)

        local inner = CreateFrame("Frame", nil, row)
        inner:SetSize(GRIDS_W, rowH)
        inner:SetPoint("CENTER", row, "CENTER", 0, 0)

        local halfW = math.floor(GRIDS_W / 2 - COL_GAP / 2)  -- ~105 px per column

        -- Frame Strata label + dropdown
        local strataLbl = inner:CreateFontString(nil, "OVERLAY")
        strataLbl:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -2)
        ApplyFont(strataLbl, 11); strataLbl:SetText("Frame Strata")
        strataLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

        strataBtn = CreateDropdown(inner,
            StrOptions({ "LOW", "MEDIUM", "HIGH", "DIALOG", "TOOLTIP" }),
            db.frameStrata or (strataOpts.default or "HIGH"),
            function(v)
                db.frameStrata = v
                if strataOpts.onChange then strataOpts.onChange(v) end
            end, halfW)
        strataBtn:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -18)

        -- Anchored To label + editbox (narrowed to make room for inline pick btn)
        local atoX     = halfW + COL_GAP
        local boxW     = halfW - PICK_BTN_W - 2  -- leave 2 px gap before the button
        local atoLbl = inner:CreateFontString(nil, "OVERLAY")
        atoLbl:SetPoint("TOPLEFT", inner, "TOPLEFT", atoX, -2)
        ApplyFont(atoLbl, 11); atoLbl:SetText("Anchored To")
        atoLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

        frameBox = CreateFrame("EditBox", nil, inner, "BackdropTemplate")
        frameBox:SetSize(boxW, 22)
        frameBox:SetPoint("TOPLEFT", inner, "TOPLEFT", atoX, -18)
        frameBox:SetAutoFocus(false); frameBox:SetMaxLetters(64)
        frameBox:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
        frameBox:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
        frameBox:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
        frameBox:SetTextInsets(6, 6, 0, 0)
        ApplyFont(frameBox, 11)
        frameBox:SetText(db.anchorFrame or "UIParent")
        frameBox:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        frameBox:SetScript("OnEnterPressed", function(self)
            db.anchorFrame = self:GetText(); applyFn(); self:ClearFocus()
        end)
        frameBox:SetScript("OnEscapePressed", function(self)
            self:SetText(db.anchorFrame or "UIParent"); self:ClearFocus()
        end)
        frameBox:SetScript("OnEditFocusGained", function() AnimateBorderFocus(frameBox, true)  end)
        frameBox:SetScript("OnEditFocusLost",   function() AnimateBorderFocus(frameBox, false) end)

        -- Pick button: inline to the right of the editbox
        pickBtn = MakePickBtn(inner, atoX + boxW + 2, -18, PICK_BTN_W, function(name)
            db.anchorFrame = name
            frameBox:SetText(name)
            applyFn()
        end)

        -- Anchor From grid
        local gridY = HEADER_H + 4
        local fromLbl = inner:CreateFontString(nil, "OVERLAY")
        fromLbl:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -(gridY + 2))
        ApplyFont(fromLbl, 11); fromLbl:SetText("Anchor From")
        fromLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        fromSel = GUI:CreateAnchorSelector(inner,
            db.anchorFrom or "CENTER",
            function(v) db.anchorFrom = v; applyFn() end)
        fromSel:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -(gridY + 16))

        -- To Frame's grid
        local toLbl = inner:CreateFontString(nil, "OVERLAY")
        toLbl:SetPoint("TOPLEFT", inner, "TOPLEFT", COL2_X, -(gridY + 2))
        ApplyFont(toLbl, 11); toLbl:SetText("To Frame's")
        toLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        toSel = GUI:CreateAnchorSelector(inner,
            db.anchorTo or "CENTER",
            function(v) db.anchorTo = v; applyFn() end)
        toSel:SetPoint("TOPLEFT", inner, "TOPLEFT", COL2_X, -(gridY + 16))

    else
        -- ── Classic 3-col layout ───────────────────────────────────────────
        local EDITBOX_W = 110
        local COL3_X    = COL2_X + GRID_W + COL_GAP  -- 242
        local totalW    = COL3_X + EDITBOX_W          -- 352
        rowH = 16 + GRID_H                            -- 121

        row = CreateFrame("Frame", nil, parent)
        row:SetHeight(rowH)

        local inner = CreateFrame("Frame", nil, row)
        inner:SetSize(totalW, rowH)
        inner:SetPoint("CENTER", row, "CENTER", 0, 0)

        local fromLbl = inner:CreateFontString(nil, "OVERLAY")
        fromLbl:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -2)
        ApplyFont(fromLbl, 11); fromLbl:SetText("Anchor From")
        fromLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        fromSel = GUI:CreateAnchorSelector(inner,
            db.anchorFrom or "CENTER",
            function(v) db.anchorFrom = v; applyFn() end)
        fromSel:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, -16)

        local toLbl = inner:CreateFontString(nil, "OVERLAY")
        toLbl:SetPoint("TOPLEFT", inner, "TOPLEFT", COL2_X, -2)
        ApplyFont(toLbl, 11); toLbl:SetText("To Frame's")
        toLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        toSel = GUI:CreateAnchorSelector(inner,
            db.anchorTo or "CENTER",
            function(v) db.anchorTo = v; applyFn() end)
        toSel:SetPoint("TOPLEFT", inner, "TOPLEFT", COL2_X, -16)

        local COL3_X2  = COL2_X + GRID_W + COL_GAP
        local boxW     = EDITBOX_W - PICK_BTN_W - 2
        local frameLbl = inner:CreateFontString(nil, "OVERLAY")
        frameLbl:SetPoint("TOPLEFT", inner, "TOPLEFT", COL3_X2, -2)
        ApplyFont(frameLbl, 11); frameLbl:SetText("Anchored To")
        frameLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

        frameBox = CreateFrame("EditBox", nil, inner, "BackdropTemplate")
        frameBox:SetSize(boxW, 22)
        frameBox:SetPoint("TOPLEFT", inner, "TOPLEFT", COL3_X2, -18)
        frameBox:SetAutoFocus(false); frameBox:SetMaxLetters(64)
        frameBox:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
        frameBox:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
        frameBox:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
        frameBox:SetTextInsets(6, 6, 0, 0)
        ApplyFont(frameBox, 11)
        frameBox:SetText(db.anchorFrame or "UIParent")
        frameBox:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        frameBox:SetScript("OnEnterPressed", function(self)
            db.anchorFrame = self:GetText(); applyFn(); self:ClearFocus()
        end)
        frameBox:SetScript("OnEscapePressed", function(self)
            self:SetText(db.anchorFrame or "UIParent"); self:ClearFocus()
        end)
        frameBox:SetScript("OnEditFocusGained", function() AnimateBorderFocus(frameBox, true)  end)
        frameBox:SetScript("OnEditFocusLost",   function() AnimateBorderFocus(frameBox, false) end)

        -- Pick button: inline to the right of the editbox
        pickBtn = MakePickBtn(inner, COL3_X2 + boxW + 2, -18, PICK_BTN_W, function(name)
            db.anchorFrame = name
            frameBox:SetText(name)
            applyFn()
        end)
    end

    function row:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        fromSel:EnableMouse(en)
        toSel:EnableMouse(en)
        frameBox:SetEnabled(en)
        if strataBtn then strataBtn:EnableMouse(en) end
        if pickBtn   then pickBtn:EnableMouse(en)   end
    end

    return row, rowH
end

-- ============================================================
-- Widget: ColorSwatch  (opens Blizzard ColorPickerFrame on click)
-- Same pattern as NorskenUI's GUI-NUIColorPicker.lua
-- callback(r, g, b) called live and on confirm
-- ============================================================
local function ColorToHex(r, g, b)
    return string.format("#%02X%02X%02X",
        math.floor(r*255+0.5), math.floor(g*255+0.5), math.floor(b*255+0.5))
end

local function BuildColorPickerInfo(r, g, b, onUpdate, onCancel)
    local info = { r = r, g = g, b = b }
    info.swatchFunc  = function()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        onUpdate(nr or r, ng or g, nb or b)
    end
    info.cancelFunc  = function() onCancel() end
    info.opacityFunc = info.swatchFunc
    return info
end

-- ============================================================
-- Shared helper: swatch button with 2×2 checkerboard background
-- (visible alpha bg + 1px animated border)
-- ============================================================
local function MakeCheckerSwatch(parent, w, h)
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(w, h)
    -- 2×2 checkerboard (dark/light alternating quads)
    local D, L = 0.28, 0.50
    local hw = math.floor(w / 2)
    local hh = math.floor(h / 2)
    local quads = {
        { D, D, D,  0,  0, hw, hh },   -- top-left  dark
        { L, L, L, hw,  0,  w, hh },   -- top-right light
        { L, L, L,  0, hh, hw,  h },   -- bot-left  light
        { D, D, D, hw, hh,  w,  h },   -- bot-right dark
    }
    for _, q in ipairs(quads) do
        local tx = swatch:CreateTexture(nil, "BACKGROUND")
        tx:SetColorTexture(q[1], q[2], q[3], 1)
        tx:SetPoint("TOPLEFT",     swatch, "TOPLEFT", q[4], -q[5])
        tx:SetPoint("BOTTOMRIGHT", swatch, "TOPLEFT", q[6], -q[7])
    end
    -- Solid color fill (ARTWORK layer, inset 1px so checker peeks at edges)
    local colorTex = swatch:CreateTexture(nil, "ARTWORK")
    colorTex:SetPoint("TOPLEFT",     swatch, "TOPLEFT",     1, -1)
    colorTex:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1,  1)
    colorTex:SetColorTexture(1, 1, 1, 1)
    swatch.colorTex = colorTex
    -- 1px border child frame
    local brd = CreateFrame("Frame", nil, swatch, "BackdropTemplate")
    brd:SetAllPoints()
    brd:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    brd:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    swatch.border = brd
    -- Hover: accent border highlight
    swatch:SetScript("OnEnter", function()
        brd:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end)
    swatch:SetScript("OnLeave", function()
        brd:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    end)
    function swatch:Refresh(r, g, b)
        colorTex:SetColorTexture(r, g, b, 1)
    end
    return swatch
end

function GUI:CreateColorSwatch(parent, labelText, r, g, b, callback)
    local rowH = 40
    local row  = CreateFrame("Frame", nil, parent)
    row:SetHeight(rowH)

    -- Label (shrunk to leave room for hex + swatch on the right)
    local lbl = row:CreateFontString(nil, "OVERLAY")
    lbl:SetPoint("LEFT",  row, "LEFT",  0, 0)
    lbl:SetPoint("RIGHT", row, "RIGHT", -120, 0)
    ApplyFont(lbl, 12)
    lbl:SetText(labelText or "")
    lbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

    -- Colored swatch button (with checkerboard alpha bg)
    local swatch = MakeCheckerSwatch(row, 48, 22)
    swatch:SetPoint("RIGHT", row, "RIGHT", 0, 0)

    -- Hex code label (between label and swatch)
    local hexLbl = row:CreateFontString(nil, "OVERLAY")
    hexLbl:SetPoint("RIGHT", swatch, "LEFT", -6, 0)
    hexLbl:SetWidth(62)
    ApplyFont(hexLbl, 10)
    hexLbl:SetJustifyH("RIGHT")
    hexLbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
    hexLbl:SetText(ColorToHex(r, g, b))

    local function RefreshSwatch(nr, ng, nb)
        swatch:Refresh(nr, ng, nb)
        hexLbl:SetText(ColorToHex(nr, ng, nb))
    end
    RefreshSwatch(r, g, b)

    swatch:SetScript("OnClick", function()
        local prevR, prevG, prevB = r, g, b
        local function UpdateColor(nr, ng, nb)
            r, g, b = nr, ng, nb
            RefreshSwatch(r, g, b)
            if callback then callback(r, g, b) end
        end
        ColorPickerFrame:SetupColorPickerAndShow(
            BuildColorPickerInfo(prevR, prevG, prevB,
                UpdateColor,
                function() UpdateColor(prevR, prevG, prevB) end))
    end)

    function row:SetColor(nr, ng, nb)
        r, g, b = nr, ng, nb
        RefreshSwatch(nr, ng, nb)
    end
    function row:GetColor() return r, g, b end
    function row:SetEnabled(en)
        swatch:EnableMouse(en and true or false)
        swatch:SetAlpha(en and 1 or 0.4)
        lbl:SetTextColor(
            T.textSecondary[1], T.textSecondary[2], T.textSecondary[3],
            en and 1 or 0.5)
    end

    return row
end

-- ============================================================
-- Widget: StackedColorSwatch  — label on top, swatch + hex below-left
-- Used by CombatTimer and Backdrop color entries
-- ============================================================
function GUI:CreateStackedColorSwatch(parent, labelStr, r0, g0, b0, onChanged)
    local ROW_H = 52
    local row   = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)

    local lbl = row:CreateFontString(nil, "OVERLAY")
    lbl:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
    ApplyFont(lbl, 11)
    lbl:SetText(labelStr or "")
    lbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

    local r, g, b = r0, g0, b0

    local swatch = MakeCheckerSwatch(row, 64, 26)
    swatch:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)

    -- Hex code label to the right of the swatch
    local hexLbl = row:CreateFontString(nil, "OVERLAY")
    hexLbl:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    hexLbl:SetWidth(64)
    ApplyFont(hexLbl, 10)
    hexLbl:SetJustifyH("LEFT")
    hexLbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
    hexLbl:SetText(ColorToHex(r, g, b))

    local function RefreshSwatch(nr, ng, nb)
        swatch:Refresh(nr, ng, nb)
        hexLbl:SetText(ColorToHex(nr, ng, nb))
    end
    RefreshSwatch(r, g, b)

    swatch:SetScript("OnClick", function()
        local prevR, prevG, prevB = r, g, b
        local function UpdateColor(nr, ng, nb)
            r, g, b = nr, ng, nb
            RefreshSwatch(r, g, b)
            if onChanged then onChanged(r, g, b) end
        end
        ColorPickerFrame:SetupColorPickerAndShow(
            BuildColorPickerInfo(prevR, prevG, prevB,
                UpdateColor,
                function() UpdateColor(prevR, prevG, prevB) end))
    end)

    function row:SetColor(nr, ng, nb) r, g, b = nr, ng, nb; RefreshSwatch(nr, ng, nb) end
    function row:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        swatch:EnableMouse(en and true or false)
    end
    return row
end

-- ============================================================
-- Widget: ColorWithSource
-- Combines a "Color Source" dropdown (Theme/Class/Custom) with a
-- stacked color swatch that is grayed when source != "custom".
-- Returns:
--   srcRow  (44 px) — dropdown row to AddRow into card
--   swRow   (52 px) — swatch row to AddRow into card
--   GetColor()      — resolves current color based on source
-- Usage:
--   local srcRow, swRow, getColor = GUI:CreateColorWithSource(
--       parent, "Shadow Color", db, "shadowColorSource", "shadowColor", {0,0,0}, applyFn)
--   card:AddSeparator(); card:AddRow(srcRow, 44)
--   card:AddSeparator(); card:AddRow(swRow, 52)
-- ============================================================
function GUI:CreateColorWithSource(parent, labelText, db, srcKey, colorKey, defaultColor, onChanged)
    local SRC_LABELS  = { "Theme Color", "Class Color", "Custom Color" }
    local SRC_TO_LABEL = { theme = "Theme Color", class = "Class Color", custom = "Custom Color" }
    local LABEL_TO_SRC = { ["Theme Color"] = "theme", ["Class Color"] = "class", ["Custom Color"] = "custom" }

    local SetSwEnabled  -- forward declare

    local srcRow = GUI:CreateDropdown(parent, "Color Source",
        SRC_LABELS,
        SRC_TO_LABEL[db[srcKey] or "custom"],
        function(v)
            db[srcKey] = LABEL_TO_SRC[v]
            if SetSwEnabled then SetSwEnabled(db[srcKey] == "custom") end
            if onChanged then onChanged() end
        end)

    -- Stacked color swatch row (same layout as CreateStackedColorSwatch)
    local cc = db[colorKey] or defaultColor or { 1, 1, 1 }
    local r, g, b = cc[1], cc[2], cc[3]

    local swRow = CreateFrame("Frame", nil, parent)
    swRow:SetHeight(52)

    local swLbl = swRow:CreateFontString(nil, "OVERLAY")
    swLbl:SetPoint("TOPLEFT", swRow, "TOPLEFT", 0, -2)
    swLbl:SetJustifyH("LEFT"); ApplyFont(swLbl, 11)
    swLbl:SetText(labelText)
    swLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

    local swatch = MakeCheckerSwatch(swRow, 64, 26)
    swatch:SetPoint("BOTTOMLEFT", swRow, "BOTTOMLEFT", 0, 2)

    local hexLbl = swRow:CreateFontString(nil, "OVERLAY")
    hexLbl:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    ApplyFont(hexLbl, 11); hexLbl:SetJustifyH("LEFT")
    hexLbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    local function RefreshSwatch(nr, ng, nb)
        swatch:Refresh(nr, ng, nb)
        hexLbl:SetText(ColorToHex(nr, ng, nb))
    end
    RefreshSwatch(r, g, b)

    swatch:SetScript("OnClick", function()
        local pr, pg, pb = r, g, b
        local function Upd(nr, ng, nb)
            r, g, b = nr, ng, nb; RefreshSwatch(nr, ng, nb)
            if not db[colorKey] then db[colorKey] = {} end
            db[colorKey][1] = nr; db[colorKey][2] = ng; db[colorKey][3] = nb
            if onChanged then onChanged() end
        end
        ColorPickerFrame:SetupColorPickerAndShow(
            BuildColorPickerInfo(pr, pg, pb, Upd, function() Upd(pr, pg, pb) end))
    end)

    SetSwEnabled = function(en)
        swRow:SetAlpha(en and 1 or 0.4)
        swatch:EnableMouse(en and true or false)
    end

    function swRow:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        swatch:EnableMouse(en and true or false)
    end

    -- Apply initial grey state based on current source
    SetSwEnabled((db[srcKey] or "custom") == "custom")

    local function GetColor()
        return SP.GetColorFromSource(db[srcKey] or "custom", db[colorKey] or defaultColor)
    end

    return srcRow, swRow, GetColor
end

-- ============================================================
-- Widget: DualColorRow  (two stacked color swatches side-by-side)
-- Each half: label on top, swatch + hex below-left
-- Used when two related colors sit in the same card section
-- ============================================================
function GUI:CreateDualColorRow(parent,
        label1, r1, g1, b1, cb1,
        label2, r2, g2, b2, cb2)
    local ROW_H = 52
    local row   = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)

    local rA, gA, bA = r1, g1, b1
    local rB, gB, bB = r2, g2, b2

    -- ── Left half ───────────────────────────────────────────
    local lblA = row:CreateFontString(nil, "OVERLAY")
    lblA:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
    ApplyFont(lblA, 11)
    lblA:SetText(label1 or "")
    lblA:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

    local swatchA = MakeCheckerSwatch(row, 64, 26)
    swatchA:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)

    local hexA = row:CreateFontString(nil, "OVERLAY")
    hexA:SetPoint("LEFT", swatchA, "RIGHT", 6, 0)
    hexA:SetWidth(64)
    ApplyFont(hexA, 10); hexA:SetJustifyH("LEFT")
    hexA:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    local function RefreshA(nr, ng, nb)
        swatchA:Refresh(nr, ng, nb)
        hexA:SetText(ColorToHex(nr, ng, nb))
    end
    RefreshA(rA, gA, bA)
    swatchA:SetScript("OnClick", function()
        local pr, pg, pb = rA, gA, bA
        local function Upd(nr, ng, nb)
            rA, gA, bA = nr, ng, nb; RefreshA(nr, ng, nb)
            if cb1 then cb1(nr, ng, nb) end
        end
        ColorPickerFrame:SetupColorPickerAndShow(
            BuildColorPickerInfo(pr, pg, pb, Upd, function() Upd(pr, pg, pb) end))
    end)

    -- ── Right half ──────────────────────────────────────────
    local lblB = row:CreateFontString(nil, "OVERLAY")
    lblB:SetPoint("TOPLEFT", row, "TOP", 8, -2)
    ApplyFont(lblB, 11)
    lblB:SetText(label2 or "")
    lblB:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

    local swatchB = MakeCheckerSwatch(row, 64, 26)
    swatchB:SetPoint("BOTTOMLEFT", row, "BOTTOM", 8, 2)

    local hexB = row:CreateFontString(nil, "OVERLAY")
    hexB:SetPoint("LEFT", swatchB, "RIGHT", 6, 0)
    hexB:SetWidth(64)
    ApplyFont(hexB, 10); hexB:SetJustifyH("LEFT")
    hexB:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    local function RefreshB(nr, ng, nb)
        swatchB:Refresh(nr, ng, nb)
        hexB:SetText(ColorToHex(nr, ng, nb))
    end
    RefreshB(rB, gB, bB)
    swatchB:SetScript("OnClick", function()
        local pr, pg, pb = rB, gB, bB
        local function Upd(nr, ng, nb)
            rB, gB, bB = nr, ng, nb; RefreshB(nr, ng, nb)
            if cb2 then cb2(nr, ng, nb) end
        end
        ColorPickerFrame:SetupColorPickerAndShow(
            BuildColorPickerInfo(pr, pg, pb, Upd, function() Upd(pr, pg, pb) end))
    end)

    function row:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        swatchA:EnableMouse(en and true or false)
        swatchB:EnableMouse(en and true or false)
    end
    return row
end

-- ============================================================
-- Widget: Horizontal Row (NorskenUI-style proportional multi-widget layout)
-- Usage:
--   local hr = GUI:CreateHRow(parent, 44)
--   hr:Add(widgetA, 0.6)   -- widgetA takes 60 % of row width
--   hr:Add(widgetB, 0.4)   -- widgetB takes 40 % of row width
--   card:AddRow(hr, 44)
-- ============================================================
function GUI:CreateHRow(parent, height, gap)
    height = height or 44
    local GAP = (gap ~= nil) and gap or T.paddingSmall   -- default 4 px gap between widgets

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height)
    row._hwidgets = {}

    -- Register a widget that will share this row proportionally.
    function row:Add(widget, widthPct)
        widthPct = widthPct or 0.5
        widget:SetParent(self)
        widget:ClearAllPoints()
        widget._hWidthPct = widthPct
        table_insert(self._hwidgets, widget)
        -- Immediate layout if the row already has a real width
        local w = self:GetWidth()
        if w and w > 1 then self:_Layout(w) end
    end

    -- Recompute all widget positions / widths from the current row width.
    function row:_Layout(w)
        if #self._hwidgets == 0 then return end
        local x = 0
        for _, wgt in ipairs(self._hwidgets) do
            local ww = w * wgt._hWidthPct - GAP
            if ww < 1 then ww = 1 end
            wgt:ClearAllPoints()
            wgt:SetPoint("TOPLEFT", self, "TOPLEFT", x, 0)
            wgt:SetWidth(ww)
            x = x + ww + GAP
        end
    end

    -- Forward enable / disable to all children.
    function row:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        for _, wgt in ipairs(self._hwidgets) do
            if wgt.SetEnabled then wgt:SetEnabled(en) end
        end
    end

    row:SetScript("OnSizeChanged", function(self, w)
        if #self._hwidgets > 0 and w > 1 then
            self:_Layout(w)
        end
    end)

    return row
end

-- ============================================================
-- Card system
-- ============================================================
function GUI:CreateCard(parent, title, yOffset)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetPoint("TOPLEFT",  parent, "TOPLEFT",  T.paddingSmall, -(yOffset or 0) + T.paddingSmall)
    card:SetPoint("RIGHT",    parent, "RIGHT",    -T.paddingSmall, 0)
    SetBackdrop(card, T.bgLight[1], T.bgLight[2], T.bgLight[3], 0.9)

    local headerH = 0
    if title and title ~= "" then
        headerH = 30
        local hdr = CreateFrame("Frame", nil, card, "BackdropTemplate")
        hdr:SetHeight(headerH)
        hdr:SetPoint("TOPLEFT",  card, "TOPLEFT",  0, 0)
        hdr:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
        SetBackdrop(hdr, T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)

        local accentBar = hdr:CreateTexture(nil, "OVERLAY")
        accentBar:SetWidth(3)
        accentBar:SetPoint("TOPLEFT",    hdr, "TOPLEFT",    0, 0)
        accentBar:SetPoint("BOTTOMLEFT", hdr, "BOTTOMLEFT", 0, 0)
        accentBar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)

        local titleStr = hdr:CreateFontString(nil, "OVERLAY")
        titleStr:SetPoint("LEFT", hdr, "LEFT", T.padding + 4, 0)
        ApplyFont(titleStr, 13)
        titleStr:SetText(title)
        titleStr:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        card.header = hdr
    end
    card.headerH = headerH

    local content = CreateFrame("Frame", nil, card)
    content:SetPoint("TOPLEFT",  card, "TOPLEFT",  T.padding, -(headerH + T.padding))
    content:SetPoint("TOPRIGHT", card, "TOPRIGHT", -T.padding, -(headerH + T.padding))
    content:SetHeight(1)
    card.content  = content
    card.currentY = 0
    card.rows     = {}
    card.labels   = {}  -- FontStrings added via AddLabel, for GrayContent

    function card:AddRow(widget, height, spacing)
        height  = height  or widget:GetHeight() or 24
        spacing = spacing or T.paddingSmall
        widget:SetParent(self.content)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT",  self.content, "TOPLEFT",  0, -self.currentY)
        widget:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -self.currentY)
        self.currentY = self.currentY + height + spacing
        table_insert(self.rows, widget)
        self.content:SetHeight(self.currentY)
        self:_UpdateHeight()
        return widget
    end

    function card:AddLabel(text, color)
        local lbl = self.content:CreateFontString(nil, "OVERLAY")
        lbl:SetPoint("TOPLEFT",  self.content, "TOPLEFT",  0, -self.currentY)
        lbl:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -self.currentY)
        lbl:SetJustifyH("LEFT")
        ApplyFont(lbl, 11)
        lbl:SetText(text)
        local c = color or T.textMuted
        lbl:SetTextColor(c[1], c[2], c[3], 1)
        local h = lbl:GetStringHeight() or 14
        self.currentY = self.currentY + h + T.paddingSmall
        self.content:SetHeight(self.currentY)
        self:_UpdateHeight()
        table_insert(self.labels, lbl)
        return lbl
    end

    function card:AddSeparator()
        -- NorskenUI-style: 1 px gradient line that fades in from the left and out to the right.
        -- Two textures split at the horizontal midpoint of content.
        local sp = T.paddingSmall
        local y  = self.currentY + sp
        local br, bg, bb = T.border[1], T.border[2], T.border[3]
        local PEAK = 0.22
        local sepL = self.content:CreateTexture(nil, "ARTWORK")
        sepL:SetHeight(1)
        sepL:SetPoint("TOPLEFT",  self.content, "TOPLEFT", 0, -y)
        sepL:SetPoint("TOPRIGHT", self.content, "TOP",     0, -y)
        sepL:SetGradient("HORIZONTAL",
            CreateColor(br, bg, bb, 0), CreateColor(br, bg, bb, PEAK))
        local sepR = self.content:CreateTexture(nil, "ARTWORK")
        sepR:SetHeight(1)
        sepR:SetPoint("TOPLEFT",  self.content, "TOP",      0, -y)
        sepR:SetPoint("TOPRIGHT", self.content, "TOPRIGHT", 0, -y)
        sepR:SetGradient("HORIZONTAL",
            CreateColor(br, bg, bb, PEAK), CreateColor(br, bg, bb, 0))
        self.currentY = self.currentY + 1 + sp * 2
        self.content:SetHeight(self.currentY)
        self:_UpdateHeight()
    end

    -- Gray (or restore) all content in this card, optionally skipping one row.
    -- Rows call their own SetEnabled if they have it; labels alpha-fade.
    -- Use this whenever a card has an enable toggle as its first row:
    --   card:GrayContent(db.enabled, enableRow)
    function card:GrayContent(en, skipRow)
        for _, row in ipairs(self.rows) do
            if row ~= skipRow then
                if row.SetEnabled then row:SetEnabled(en)
                else row:SetAlpha(en and 1 or 0.4) end
            end
        end
        for _, lbl in ipairs(self.labels) do
            lbl:SetAlpha(en and 1 or 0.4)
        end
    end

    function card:AddSpacing(amount)
        self.currentY = self.currentY + (amount or T.padding)
        self.content:SetHeight(self.currentY)
        self:_UpdateHeight()
    end

    function card:_UpdateHeight()
        self:SetHeight(self.headerH + self.currentY + T.padding * 2)
    end

    function card:GetTotalHeight()
        return self.headerH + self.currentY + T.padding * 2
    end

    card:_UpdateHeight()
    return card
end

-- ============================================================
-- Sidebar
-- ============================================================
local sidebarPool = {}
local headerPool  = {}
local expanded    = {}
local selectedItem

local SECTION_H = 32
local ITEM_H    = 26

local function GetSectionHeader()
    for _, h in ipairs(headerPool) do
        if not h.inUse then h.inUse = true; h:Show(); return h end
    end
    local h = CreateFrame("Button", nil, UIParent)
    h:SetHeight(SECTION_H); h:EnableMouse(true); h:RegisterForClicks("LeftButtonUp")

    local hoverTex = h:CreateTexture(nil, "ARTWORK")
    hoverTex:SetAllPoints()
    hoverTex:SetColorTexture(T.bgHover[1], T.bgHover[2], T.bgHover[3], 0.5)
    hoverTex:Hide()
    h.hoverTex = hoverTex

    local lbl = h:CreateFontString(nil, "OVERLAY")
    lbl:SetPoint("LEFT", h, "LEFT", T.padding, 0)
    ApplyFont(lbl, 13)
    lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    h.label = lbl

    local arrow = h:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", h, "RIGHT", -T.padding, 0)
    arrow:SetTexture(ARROW_TEX)
    arrow:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
    arrow:SetTexelSnappingBias(0)
    arrow:SetSnapToPixelGrid(false)
    h.arrow = arrow

    h:SetScript("OnEnter", function() hoverTex:Show() end)
    h:SetScript("OnLeave", function() hoverTex:Hide() end)
    h:SetScript("OnClick", function(self)
        expanded[self.sectionId] = not expanded[self.sectionId]
        if GUI.mainFrame then GUI:RefreshSidebar() end
    end)

    h.inUse = true; table_insert(headerPool, h); return h
end

-- Returns true if the module/feature for a given sidebar ID is currently enabled.
-- Used by RefreshSidebar() to show/hide the accent checkmark indicator.
local function ItemEnabledState(id)
    local db = SP.GetDB()
    if id == "drawer"        then return db.drawer       and db.drawer.enabled       or false
    elseif id == "cursor"    then return db.cursor       and db.cursor.enabled       or false
    elseif id == "copytooltip" then return db.copyTooltip and db.copyTooltip.enabled or false
    elseif id == "fastloot"  then return db.fastLoot     and db.fastLoot.enabled     or false
    elseif id == "automation" then return db.automation  and db.automation.enabled   or false
    elseif id == "combattimer" then return db.combatTimer and db.combatTimer.enabled or false
    elseif id == "bloodlustalert" then return db.bloodlustAlert and db.bloodlustAlert.enabled or false
    elseif id == "tankmd"            then return db.tankMD            and db.tankMD.enabled            or false
    elseif id == "focustargetmarker" then return db.focusTargetMarker and db.focusTargetMarker.enabled or false
    elseif id == "meterreset"        then return db.meterReset and db.meterReset.enabled   or false
    elseif id == "combatlog"         then return db.combatLog  and db.combatLog.enabled    or false
    elseif id == "invitationgroupe"    then return db.autoInvite          and db.autoInvite.enabled          or false
    elseif id == "deathalert"          then return db.deathAlert          and db.deathAlert.enabled          or false
    elseif id == "groupjoinedreminder" then return db.groupJoinedReminder and db.groupJoinedReminder.enabled or false
    elseif id == "autoplaystyle"       then return db.autoPlaystyle       and db.autoPlaystyle.enabled       or false
    elseif id == "craftshopper"        then return db.craftShopper        and db.craftShopper.enabled        or false
    elseif id == "silvermoonmapicon"   then return db.silvermoonMapIcon   and db.silvermoonMapIcon.enabled   or false
    elseif id == "gatewayalert"        then return db.gatewayAlert         and db.gatewayAlert.enabled         or false
    elseif id == "durability"          then return db.durability           and db.durability.enabled           or false
    elseif id == "performance"         then return db.performance          and db.performance.enabled          or false
    elseif id == "enhancedobjectivetext"      then return db.enhancedObjectiveText      and db.enhancedObjectiveText.enabled      or false
    elseif id == "cleanobjectivetrackerheader" then return db.cleanObjectiveTrackerHeader and db.cleanObjectiveTrackerHeader.enabled or false
    elseif id == "whisperalert"      then return db.whisperAlert and db.whisperAlert.enabled or false
    elseif id == "filterexpansiononly" then return db.filterExpansionOnly and db.filterExpansionOnly.enabled or false
    elseif id == "autobuy"           then local cdb = SP.GetCharDB(); return cdb.autoBuy and cdb.autoBuy.enabled or false
    elseif id == "spelleffectalpha"  then return db.spellEffectAlpha  and db.spellEffectAlpha.enabled  or false
    elseif id == "combatcross"       then return db.combatCross       and db.combatCross.enabled       or false
    elseif id == "movementalert"     then return db.movementAlert     and db.movementAlert.enabled     or false
    elseif id == "editmode"          then return true
    end
    return false
end

-- Lightweight dot-only refresh — walks the live pool without hiding/repositioning items.
-- Avoids the OnEnter re-fire bug that a full RefreshSidebar would cause.
function GUI.UpdateSidebarCheckmarks()
    for _, item in ipairs(sidebarPool) do
        if item.inUse and item.id and item.checkmark then
            if ItemEnabledState(item.id) then
                item.checkmark:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
                item.checkmark:Show()
            else
                item.checkmark:Hide()
            end
        end
    end
end

local function GetSidebarItem()
    for _, item in ipairs(sidebarPool) do
        if not item.inUse then item.inUse = true; item:Show(); return item end
    end
    local item = CreateFrame("Button", nil, UIParent)
    item:SetHeight(ITEM_H); item:EnableMouse(true); item:RegisterForClicks("LeftButtonUp")

    local selOv = item:CreateTexture(nil, "ARTWORK")
    selOv:SetAllPoints(); selOv:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.12)
    selOv:Hide(); item.selOv = selOv

    local hoverOv = item:CreateTexture(nil, "ARTWORK")
    hoverOv:SetAllPoints(); hoverOv:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.07)
    hoverOv:Hide(); item.hoverOv = hoverOv

    local selBar = item:CreateTexture(nil, "OVERLAY")
    selBar:SetWidth(2)
    selBar:SetPoint("TOPLEFT",    item, "TOPLEFT",    0, -3)
    selBar:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0,  3)
    selBar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
    selBar:Hide(); item.selBar = selBar

    local lbl = item:CreateFontString(nil, "OVERLAY")
    lbl:SetPoint("LEFT",  item, "LEFT",  16, 0)
    lbl:SetPoint("RIGHT", item, "RIGHT", -20, 0)   -- leave room for checkmark
    ApplyFont(lbl, 12); lbl:SetJustifyH("LEFT"); lbl:SetWordWrap(false)
    item.label = lbl

    -- Dot: solid 5×5 square — no mask needed at this size, and masks on sub-6px
    -- textures cause inconsistent alpha depending on UI scale / texture filtering.
    local ck = item:CreateTexture(nil, "OVERLAY")
    ck:SetSize(5, 5)
    ck:SetPoint("RIGHT", item, "RIGHT", -7, 0)
    ck:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
    ck:Hide()
    item.checkmarkBorder = nil   -- no longer used; kept for nil-safe existing calls
    item.checkmark = ck

    item:SetScript("OnEnter", function(self)
        if self.id ~= selectedItem then hoverOv:Show() end
        self.label:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
    end)
    item:SetScript("OnLeave", function(self)
        hoverOv:Hide()
        if self.id ~= selectedItem then
            self.label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        end
    end)
    item:SetScript("OnClick", function(self) GUI:SelectItem(self.id) end)

    item.inUse = true; table_insert(sidebarPool, item); return item
end

-- Tracks current arrow rotation per sectionId for smooth sidebar animations
local sectionArrowRot = {}

function GUI:RefreshSidebar()
    if not self.sidebarScrollChild then return end
    local sc = self.sidebarScrollChild

    for _, h    in ipairs(headerPool)  do
        h.inUse = false; h:Hide(); h:ClearAllPoints()
        if h._arrowTicker then h._arrowTicker:Cancel(); h._arrowTicker = nil end
    end
    for _, item in ipairs(sidebarPool) do item.inUse = false; item:Hide(); item:ClearAllPoints() end

    -- Search filter
    local query       = self.searchQuery and self.searchQuery ~= "" and self.searchQuery:lower() or nil
    local firstMatch  = nil  -- first matching item id, for Enter-to-navigate

    local yOff = T.paddingSmall
    for _, section in ipairs(self.SidebarConfig) do
        if section.type == "section" then
            local sectionItems = section.items or {}

            -- When filtering, pre-check if this section has any matching items
            local sectionVisible = true
            if query then
                sectionVisible = false
                for _, cfg in ipairs(sectionItems) do
                    if (cfg.text or ""):lower():find(query, 1, true) then
                        sectionVisible = true; break
                    end
                end
            end

            if sectionVisible then
                local isExpanded = query and true or expanded[section.id]
                local hdr = GetSectionHeader()
                hdr:SetParent(sc)
                hdr:SetPoint("TOPLEFT",  sc, "TOPLEFT",  T.paddingSmall, -yOff)
                hdr:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -T.paddingSmall, -yOff)
                hdr.sectionId = section.id
                hdr.label:SetText(section.text or "")
                -- Animate sidebar arrow: expanded = ▼ (0), collapsed = ◄ (-pi/2)
                local targetRot  = isExpanded and 0 or (-math.pi / 2)
                local currentRot = sectionArrowRot[section.id]
                if currentRot == nil then
                    hdr.arrow:SetRotation(targetRot)
                    sectionArrowRot[section.id] = targetRot
                elseif math.abs(currentRot - targetRot) < 0.01 then
                    hdr.arrow:SetRotation(targetRot)
                else
                    local startRot  = currentRot
                    local startTime = GetTime()
                    local ANIM_DUR  = 0.15
                    local sid       = section.id
                    hdr._arrowTicker = C_Timer.NewTicker(0.016, function()
                        local p = math.min((GetTime() - startTime) / ANIM_DUR, 1)
                        p = 1 - (1-p)*(1-p)
                        local rot = startRot + (targetRot - startRot) * p
                        hdr.arrow:SetRotation(rot)
                        sectionArrowRot[sid] = rot
                        if p >= 1 then
                            hdr.arrow:SetRotation(targetRot)
                            sectionArrowRot[sid] = targetRot
                            hdr._arrowTicker:Cancel(); hdr._arrowTicker = nil
                        end
                    end)
                end
                yOff = yOff + SECTION_H

                if isExpanded then
                    for _, cfg in ipairs(sectionItems) do
                        local itemVisible = not query or (cfg.text or ""):lower():find(query, 1, true)
                        if itemVisible then
                            if not firstMatch then firstMatch = cfg.id end

                            local it = GetSidebarItem()
                            it:SetParent(sc)
                            it:SetPoint("TOPLEFT",  sc, "TOPLEFT",  T.paddingSmall, -yOff)
                            it:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -T.paddingSmall, -yOff)
                            it.id = cfg.id
                            it.label:SetText(cfg.text or "")
                            if cfg.id == selectedItem then
                                it.selOv:Show(); it.selBar:Show()
                                it.label:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
                            else
                                it.selOv:Hide(); it.selBar:Hide()
                                it.label:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
                            end
                            if ItemEnabledState(cfg.id) then
                                it.checkmark:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
                                it.checkmark:Show()
                            else
                                it.checkmark:Hide()
                            end
                            yOff = yOff + ITEM_H + 2
                        end
                    end
                end
                yOff = yOff + 2
            end
        end
    end

    -- Store first match so Enter can navigate to it
    self._searchFirstMatch = firstMatch

    sc:SetHeight(yOff + T.paddingSmall)
end

function GUI:SelectItem(itemId)
    selectedItem = itemId
    -- Reset scroll position to top whenever a different page is opened
    if self.contentScroll then
        self.contentScroll:SetVerticalScroll(0)
        self.contentScroll._scrollTarget = 0
        if self.contentScroll._scrollTicker then
            self.contentScroll._scrollTicker:Cancel()
            self.contentScroll._scrollTicker = nil
        end
    end
    self:RefreshSidebar()
    self:RefreshContent()
end

-- ============================================================
-- Content area
-- ============================================================
function GUI:RefreshContent()
    if not self.contentScrollChild then return end
    local sc = self.contentScrollChild
    self.PageCache = self.PageCache or {}

    -- Hide every cached page container. mainFrame:Show() re-shows all sc children
    -- each time the GUI opens, so we must hide all of them, not just _activePage.
    for _, container in pairs(self.PageCache) do
        container:Hide()
    end
    self._activePage = nil

    local cached = self.PageCache[selectedItem]
    if cached then
        -- Run any pre-show relayout BEFORE Show() so frames are positioned correctly
        -- the instant they become visible (avoids one-frame flicker at wrong positions).
        if cached._onPageShow then cached._onPageShow() end
        cached:Show()
        sc:SetHeight(cached:GetHeight())
        self._activePage = cached
    else
        local builder = self.ContentBuilders[selectedItem]
        if builder then
            -- Each page lives inside its own container frame so Hide/Show is trivial
            -- and never suffers from the child-reparent snapshot-diff fragility.
            local container = CreateFrame("Frame", nil, sc)
            container:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, 0)
            container:SetPoint("RIGHT",   sc, "RIGHT",   0, 0)
            container:SetHeight(1)

            builder(container)

            -- Sync sc height to content height set by the builder (parent:SetHeight(y))
            sc:SetHeight(container:GetHeight())
            self.PageCache[selectedItem] = container
            self._activePage = container
        else
            local msg = sc:CreateFontString(nil, "OVERLAY")
            msg:SetPoint("CENTER", sc, "CENTER", 0, 0)
            ApplyFont(msg, 13)
            msg:SetText("No settings available.")
            msg:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
        end
    end
end

-- ============================================================
-- Main Window
-- ============================================================
local mainFrame

function GUI:BuildMainFrame()
    if mainFrame then return end

    mainFrame = CreateFrame("Frame", "SP_GUIMainFrame", UIParent, "BackdropTemplate")
    self.mainFrame = mainFrame
    mainFrame:SetSize(T.winW, T.winH)
    -- Restore user-resized window size if a previous session saved it
    if self._savedSize then
        mainFrame:SetSize(self._savedSize[1], self._savedSize[2])
        self._savedSize = nil
    end
    if self._savedPos then
        local sp = self._savedPos
        mainFrame:SetPoint(sp[1], UIParent, sp[2], sp[3], sp[4])
        self._savedPos = nil
    else
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    mainFrame:SetResizable(true)
    mainFrame:SetResizeBounds(T.winMinW, T.winMinH)
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetFrameLevel(50)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    -- Always release sizing/moving on mouse-up anywhere on the frame,
    -- and on hide — prevents WoW staying in StartSizing mode if the
    -- cursor left the resize button before releasing, which blocks right-clicks.
    mainFrame:SetScript("OnMouseUp", function() mainFrame:StopMovingOrSizing() end)
    mainFrame:SetScript("OnHide", function()
        mainFrame:StopMovingOrSizing()
        -- If a dropdown was open when the window closed, its fullscreen closer frame
        -- would otherwise persist and block all right-clicks globally.  Force-close it.
        if GUI._activeDropdownClose then GUI._activeDropdownClose() end
    end)
    mainFrame:Hide()
    SetBackdrop(mainFrame,
        T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.80)

    -- Header
    local header = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    header:SetHeight(T.headerHeight)
    header:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  0, 0)
    header:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 0, 0)
    SetBackdrop(header, T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() mainFrame:StartMoving() end)
    header:SetScript("OnDragStop",  function() mainFrame:StopMovingOrSizing() end)

    -- Top accent gradient bar
    local topBar = header:CreateTexture(nil, "OVERLAY")
    topBar:SetHeight(2)
    topBar:SetPoint("TOPLEFT",  header, "TOPLEFT",  0, 0)
    topBar:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    topBar:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)

    -- Addon logo — 72×72, overflows the top-left corner of the window.
    -- Parented to mainFrame at a high frame level so it renders above the header.
    -- Acts as a Button: brightens on hover, navigates to Home on click.
    local logoFrame = CreateFrame("Button", nil, mainFrame)
    logoFrame:SetSize(72, 72)
    -- x=-17 overflow left, y=18 overflow above
    logoFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", -17, 18)
    logoFrame:SetFrameLevel(header:GetFrameLevel() + 50)

    local logoIcon = logoFrame:CreateTexture(nil, "ARTWORK")
    logoIcon:SetAllPoints(logoFrame)
    logoIcon:SetTexture(SP_LOGO_TEX)
    logoIcon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.9)
    logoIcon:SetTexelSnappingBias(0)
    logoIcon:SetSnapToPixelGrid(false)

    logoFrame:SetScript("OnEnter", function()
        logoIcon:SetVertexColor(
            math.min(T.accent[1] * 1.35 + 0.15, 1),
            math.min(T.accent[2] * 1.35 + 0.15, 1),
            math.min(T.accent[3] * 1.35 + 0.15, 1), 1)
    end)
    logoFrame:SetScript("OnLeave", function()
        logoIcon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.9)
    end)
    logoFrame:SetScript("OnClick", function()
        GUI:SelectItem("home")
    end)

    -- "Pack" in white, closer to logo
    local titleStr = header:CreateFontString(nil, "OVERLAY")
    titleStr:SetPoint("LEFT", header, "LEFT", 56, 4)
    ApplyFont(titleStr, 15)
    titleStr:SetText("|cffffffffPack|r")

    -- "by cruzz" smaller, slightly lower and close to Pack
    local authorStr = header:CreateFontString(nil, "OVERLAY")
    authorStr:SetPoint("LEFT", titleStr, "RIGHT", 1, -4)
    ApplyFont(authorStr, 9)
    authorStr:SetText("by cruzz")
    authorStr:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    -- Version string — small, below Pack
    local verStr = header:CreateFontString(nil, "OVERLAY")
    verStr:SetPoint("TOPLEFT", titleStr, "BOTTOMLEFT", 0, -1)
    ApplyFont(verStr, 9)
    verStr:SetText("v" .. SP.VERSION)
    verStr:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.7)

    -- Close button — NorskenUI cross texture
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(22, 22)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -T.paddingSmall, 0)
    local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
    closeTex:SetAllPoints()
    closeTex:SetTexture(CLOSE_TEX)
    closeTex:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
    closeTex:SetTexelSnappingBias(0)
    closeTex:SetSnapToPixelGrid(false)
    closeTex:SetRotation(math.rad(45))
    closeBtn:SetScript("OnEnter", function()
        closeTex:SetVertexColor(
            math.min(T.accent[1] * 1.3, 1),
            math.min(T.accent[2] * 1.3, 1),
            math.min(T.accent[3] * 1.3, 1), 1) end)
    closeBtn:SetScript("OnLeave", function()
        closeTex:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1) end)
    closeBtn:SetScript("OnClick", function() GUI.Hide() end)

    -- ── Search bar (header, left of close button) ─────────────
    local SEARCH_W       = 180
    local SEARCH_H       = 22
    local SEARCH_PLACEHOLDER = "Search..."
    GUI.searchQuery = ""

    local searchWrap = CreateFrame("Frame", nil, header, "BackdropTemplate")
    searchWrap:SetSize(SEARCH_W, SEARCH_H)
    searchWrap:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    searchWrap:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    searchWrap:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 1)
    searchWrap:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

    -- Search icon (🔍 via WoW texture atlas)
    local searchIcon = searchWrap:CreateTexture(nil, "ARTWORK")
    searchIcon:SetSize(12, 12)
    searchIcon:SetPoint("LEFT", searchWrap, "LEFT", 6, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.7)

    local searchBox = CreateFrame("EditBox", nil, searchWrap)
    searchBox:SetPoint("LEFT",  searchWrap, "LEFT",  22, 0)
    searchBox:SetPoint("RIGHT", searchWrap, "RIGHT", -6, 0)
    searchBox:SetHeight(SEARCH_H)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(64)
    ApplyFont(searchBox, 11)
    searchBox:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
    searchBox:SetText(SEARCH_PLACEHOLDER)
    searchBox:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.5)

    -- Track focus so hover-leave doesn't dim the border while typing
    local searchFocused = false

    -- Stop header dragging when clicking the search box
    searchWrap:EnableMouse(true)
    searchWrap:SetScript("OnMouseDown", function() searchBox:SetFocus() end)

    -- Hover — same AnimateBorderFocus animation as every other button/input.
    -- The EditBox child captures mouse events, so we must hook both the wrapper
    -- AND the searchBox; otherwise OnEnter only fires over the loupe icon.
    local function OnSearchHoverEnter()
        AnimateBorderFocus(searchWrap, true)
        searchIcon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.9)
    end
    local function OnSearchHoverLeave()
        if not searchFocused then
            AnimateBorderFocus(searchWrap, false)
            searchIcon:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.7)
        end
    end
    searchWrap:SetScript("OnEnter", OnSearchHoverEnter)
    searchWrap:SetScript("OnLeave", OnSearchHoverLeave)
    searchBox:SetScript("OnEnter", OnSearchHoverEnter)
    searchBox:SetScript("OnLeave", OnSearchHoverLeave)

    searchBox:SetScript("OnEditFocusGained", function(self)
        searchFocused = true
        AnimateBorderFocus(searchWrap, true)
        searchIcon:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.9)
        if self:GetText() == SEARCH_PLACEHOLDER then
            self:SetText("")
            self:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        end
    end)

    searchBox:SetScript("OnEditFocusLost", function(self)
        searchFocused = false
        AnimateBorderFocus(searchWrap, false)
        searchIcon:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.7)
        if self:GetText() == "" then
            self:SetText(SEARCH_PLACEHOLDER)
            self:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.5)
        end
    end)

    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        local txt = self:GetText()
        if txt == SEARCH_PLACEHOLDER then return end
        GUI.searchQuery = txt
        GUI:RefreshSidebar()
        -- Auto-navigate to single match
        if txt ~= "" and GUI._searchFirstMatch and GUI._searchFirstMatch ~= selectedItem then
            -- Only auto-navigate when exactly one result is visible (UX: don't jump around while typing)
        end
    end)

    searchBox:SetScript("OnEnterPressed", function(self)
        -- Navigate to first match on Enter
        if GUI._searchFirstMatch then
            GUI:SelectItem(GUI._searchFirstMatch)
            self:ClearFocus()
            self:SetText("")
            self:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.5)
            GUI.searchQuery = ""
            GUI:RefreshSidebar()
        else
            self:ClearFocus()
        end
    end)

    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.5)
        self:ClearFocus()
        GUI.searchQuery = ""
        GUI:RefreshSidebar()
    end)

    -- Footer
    local footer = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    footer:SetHeight(T.footerHeight)
    footer:SetPoint("BOTTOMLEFT",  mainFrame, "BOTTOMLEFT",  0, 0)
    footer:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, 0)
    SetBackdrop(footer, T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)

    local resizeBtn = CreateFrame("Button", nil, footer)
    resizeBtn:SetSize(20, 20)
    resizeBtn:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", -2, 2)
    local resizeTex = resizeBtn:CreateTexture(nil, "ARTWORK")
    resizeTex:SetAllPoints()
    resizeTex:SetTexture(RESIZE_TEX)
    resizeTex:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
    resizeTex:SetTexelSnappingBias(0)
    resizeTex:SetSnapToPixelGrid(false)
    resizeBtn:SetScript("OnEnter", function()
        resizeTex:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1) end)
    resizeBtn:SetScript("OnLeave", function()
        resizeTex:SetVertexColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1) end)
    -- RegisterForDrag + OnDragStop guarantees StopMovingOrSizing is called
    -- even when the cursor leaves the button or the frame during resize.
    -- OnMouseDown/OnMouseUp on a button doesn't fire OnMouseUp if the cursor
    -- drifts outside the button bounds before release — leaving WoW stuck in
    -- sizing mode and blocking right-clicks globally.
    resizeBtn:RegisterForDrag("LeftButton")
    resizeBtn:SetScript("OnDragStart", function() mainFrame:StartSizing("BOTTOMRIGHT") end)
    resizeBtn:SetScript("OnDragStop",  function() mainFrame:StopMovingOrSizing() end)

    local footerLbl = footer:CreateFontString(nil, "OVERLAY")
    footerLbl:SetPoint("LEFT", footer, "LEFT", T.padding, 0)
    ApplyFont(footerLbl, 10)
    footerLbl:SetText("Suspicion's Pack  ·  /spack")
    footerLbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.6)

    -- "Preview All" button: previews every enabled module simultaneously so the
    -- player can spot overlaps between stance alerts, gate alerts, bloodlust, etc.
    -- Placed in the footer to the right of the label, left of the resize handle.
    local PREVIEW_ALL_MODULES = {
        { mod = "GatewayAlert", key = "gatewayAlert"  },
        { mod = "Durability",   key = "durability"    },
        { mod = "CombatTimer",  key = "combatTimer"   },
    }
    local _previewAllTimer = nil
    local previewAllBtn = CreateFrame("Frame", nil, footer, "BackdropTemplate")
    previewAllBtn:SetSize(100, T.footerHeight - 6)
    previewAllBtn:SetPoint("RIGHT", resizeBtn, "LEFT", -8, 0)
    previewAllBtn:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    previewAllBtn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    previewAllBtn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    previewAllBtn:EnableMouse(true)

    local previewAllLbl = previewAllBtn:CreateFontString(nil, "OVERLAY")
    previewAllLbl:SetAllPoints(previewAllBtn)
    previewAllLbl:SetJustifyH("CENTER"); previewAllLbl:SetJustifyV("MIDDLE")
    ApplyFont(previewAllLbl, 11)
    previewAllLbl:SetText("Preview All")
    previewAllLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

    previewAllBtn:SetScript("OnEnter", function()
        AnimateBorderFocus(previewAllBtn, true)
        previewAllLbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end)
    previewAllBtn:SetScript("OnLeave", function()
        AnimateBorderFocus(previewAllBtn, false)
        previewAllLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    end)
    previewAllBtn:SetScript("OnMouseDown", function()
        if _previewAllTimer then _previewAllTimer:Cancel(); _previewAllTimer = nil end
        local db = SP.GetDB()
        local shown = {}
        for _, entry in ipairs(PREVIEW_ALL_MODULES) do
            local mod = SP[entry.mod]
            local mdb = db[entry.key]
            if mod and mod.ShowPreview and mdb and mdb.enabled then
                mod:ShowPreview()
                shown[#shown + 1] = mod
            end
        end
        if #shown > 0 then
            _previewAllTimer = C_Timer.NewTimer(5, function()
                _previewAllTimer = nil
                for _, mod in ipairs(shown) do
                    if mod.HidePreview then mod:HidePreview() end
                end
            end)
        end
    end)

    -- "Theme" button — opens the Themes page directly
    local themeBtn = CreateFrame("Frame", nil, footer, "BackdropTemplate")
    themeBtn:SetSize(72, T.footerHeight - 6)
    themeBtn:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    themeBtn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    themeBtn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    themeBtn:EnableMouse(true)

    local themeLbl = themeBtn:CreateFontString(nil, "OVERLAY")
    themeLbl:SetAllPoints(themeBtn)
    themeLbl:SetJustifyH("CENTER"); themeLbl:SetJustifyV("MIDDLE")
    ApplyFont(themeLbl, 11)
    themeLbl:SetText("Theme")
    themeLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

    themeBtn:SetScript("OnEnter", function()
        AnimateBorderFocus(themeBtn, true)
        themeLbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end)
    themeBtn:SetScript("OnLeave", function()
        AnimateBorderFocus(themeBtn, false)
        themeLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    end)
    themeBtn:SetScript("OnMouseDown", function()
        GUI:SelectItem("themes")
    end)

    -- "Changelog" button — left of Preview All, opens SP.ShowChangelogPopup()
    local changelogBtn = CreateFrame("Frame", nil, footer, "BackdropTemplate")
    changelogBtn:SetSize(90, T.footerHeight - 6)
    changelogBtn:SetPoint("RIGHT", previewAllBtn, "LEFT", -6, 0)
    -- themeBtn anchored here now that changelogBtn is defined
    themeBtn:SetPoint("RIGHT", changelogBtn, "LEFT", -6, 0)
    changelogBtn:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    changelogBtn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    changelogBtn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    changelogBtn:EnableMouse(true)

    local changelogLbl = changelogBtn:CreateFontString(nil, "OVERLAY")
    changelogLbl:SetAllPoints(changelogBtn)
    changelogLbl:SetJustifyH("CENTER"); changelogLbl:SetJustifyV("MIDDLE")
    ApplyFont(changelogLbl, 11)
    changelogLbl:SetText("Changelog")
    changelogLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

    changelogBtn:SetScript("OnEnter", function()
        AnimateBorderFocus(changelogBtn, true)
        changelogLbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end)
    changelogBtn:SetScript("OnLeave", function()
        AnimateBorderFocus(changelogBtn, false)
        changelogLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    end)
    changelogBtn:SetScript("OnMouseDown", function()
        if SP.ShowChangelogPopup then SP.ShowChangelogPopup() end
    end)

    -- Sidebar (flush layout — no gaps between sidebar, topbar, content)
    local LAYOUT_GAP = 0
    local sidebar = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    sidebar:SetWidth(T.sidebarWidth)
    sidebar:SetPoint("TOPLEFT",    mainFrame, "TOPLEFT",    0, -(T.headerHeight + LAYOUT_GAP))
    sidebar:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 0,  T.footerHeight)
    SetBackdrop(sidebar, T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)

    local sidebarBorder = sidebar:CreateTexture(nil, "OVERLAY")
    sidebarBorder:SetWidth(1)
    sidebarBorder:SetPoint("TOPRIGHT",    sidebar, "TOPRIGHT",    0, 0)
    sidebarBorder:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarBorder:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)

    local sidebarScroll = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    sidebarScroll:SetPoint("TOPLEFT",     sidebar, "TOPLEFT",     0, -T.paddingSmall)
    sidebarScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -1, T.paddingSmall)
    if sidebarScroll.ScrollBar then
        local ssb = sidebarScroll.ScrollBar
        ssb:SetAlpha(0)
        -- Hide named children and prevent them from ever showing again
        for _, k in ipairs({ "Background","Top","Middle","Bottom","ScrollUpButton","ScrollDownButton","trackBG" }) do
            if ssb[k] then
                ssb[k]:Hide()
                ssb[k]:SetScript("OnShow", function(s) s:Hide() end)
            end
        end
    end
    -- Permanently suppress Button children of the scroll frame (WoW 10.x template variation)
    for _, child in ipairs({ sidebarScroll:GetChildren() }) do
        if child:IsObjectType("Button") then
            child:Hide()
            child:SetScript("OnShow", function(s) s:Hide() end)
        end
    end

    local sidebarSC = CreateFrame("Frame", nil, sidebarScroll)
    sidebarSC:SetWidth(T.sidebarWidth - 1)
    sidebarSC:SetHeight(1)
    sidebarScroll:SetScrollChild(sidebarSC)
    self.sidebarScrollChild = sidebarSC

    -- ── Smooth mouse-wheel scroll (sidebar) ──────────────────────────────
    sidebarScroll:EnableMouseWheel(true)
    sidebarScroll._scrollTarget = 0
    sidebarScroll:SetScript("OnMouseWheel", function(sf, delta)
        local maxScroll = sf:GetVerticalScrollRange()
        sf._scrollTarget = math.max(0, math.min(sf._scrollTarget - delta * 60, maxScroll))
        if sf._scrollTicker then return end
        sf._scrollTicker = C_Timer.NewTicker(0.016, function()
            local cur = sf:GetVerticalScroll()
            local d   = sf._scrollTarget - cur
            if math.abs(d) < 0.5 then
                sf:SetVerticalScroll(sf._scrollTarget)
                sf._scrollTicker:Cancel(); sf._scrollTicker = nil
                return
            end
            sf:SetVerticalScroll(cur + d * 0.25)
        end)
    end)

    -- ── Sidebar scroll-fade indicators ───────────────────────────────────
    -- The gradients must render above the scroll child's content.
    -- Textures parented directly to `sidebar` are drawn at sidebar's frame
    -- level, which is below sidebarScroll and its children.  The fix: a
    -- dedicated overlay Frame at a high frame level so it stacks on top.
    do
        local FADE_H = 40
        local ar, ag, ab = T.accent[1], T.accent[2], T.accent[3]

        -- This frame sits above all scroll content (frame level 500).
        local fadeHolder = CreateFrame("Frame", nil, sidebar)
        fadeHolder:SetAllPoints(sidebar)
        fadeHolder:SetFrameLevel(sidebar:GetFrameLevel() + 500)

        -- Bottom fade: accent transparent (top) → accent opaque (bottom)
        -- SetGradient("VERTICAL", minColor=bottom, maxColor=top)
        local fadeBottom = fadeHolder:CreateTexture(nil, "OVERLAY")
        fadeBottom:SetTexture(BLANK)
        fadeBottom:SetPoint("BOTTOMLEFT",  sidebar, "BOTTOMLEFT",  0,  T.paddingSmall - 1)
        fadeBottom:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -1, T.paddingSmall - 1)
        fadeBottom:SetHeight(FADE_H)
        fadeBottom:SetGradient("VERTICAL",
            CreateColor(ar, ag, ab, 0.55),   -- bottom = opaque
            CreateColor(ar, ag, ab, 0))      -- top    = transparent

        -- Top fade: accent opaque (top) → accent transparent (bottom)
        local fadeTop = fadeHolder:CreateTexture(nil, "OVERLAY")
        fadeTop:SetTexture(BLANK)
        fadeTop:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  0,  -T.paddingSmall)
        fadeTop:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -1, -T.paddingSmall)
        fadeTop:SetHeight(FADE_H)
        fadeTop:SetGradient("VERTICAL",
            CreateColor(ar, ag, ab, 0),      -- bottom = transparent
            CreateColor(ar, ag, ab, 0.55))   -- top    = opaque
        fadeTop:Hide()

        -- Cheap OnUpdate: two comparisons + two SetShown per frame.
        local fadeWatcher = CreateFrame("Frame", nil, fadeHolder)
        fadeWatcher:SetScript("OnUpdate", function()
            local cur = sidebarScroll:GetVerticalScroll()      or 0
            local max = sidebarScroll:GetVerticalScrollRange() or 0
            fadeTop:SetShown(cur > 2)
            fadeBottom:SetShown(max > 2 and cur < max - 2)
        end)
    end

    -- Content area (LAYOUT_GAP px gap from sidebar)
    local contentArea = CreateFrame("Frame", nil, mainFrame)
    contentArea:SetPoint("TOPLEFT",     sidebar, "TOPRIGHT",    LAYOUT_GAP, 0)
    contentArea:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", 0, T.footerHeight)
    contentArea:SetPoint("TOP",         mainFrame, "TOP",         0, -(T.headerHeight + LAYOUT_GAP))

    local SB_W = 4  -- scrollbar track width

    local contentScroll = CreateFrame("ScrollFrame", nil, contentArea, "UIPanelScrollFrameTemplate")
    contentScroll:SetPoint("TOPLEFT",     contentArea, "TOPLEFT",     T.paddingSmall, -T.paddingSmall)
    contentScroll:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -(T.paddingSmall + SB_W + 4), T.paddingSmall)

    -- ── Custom scrollbar ─────────────────────────────────────────────────────
    local sb = contentScroll.ScrollBar
    if sb then
        sb:ClearAllPoints()
        sb:SetPoint("TOPRIGHT",    contentArea, "TOPRIGHT",    -(T.paddingSmall), -T.paddingSmall - 2)
        sb:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -(T.paddingSmall),  T.paddingSmall + 2)
        sb:SetWidth(SB_W)
        -- Permanently suppress every Blizzard element (named keys)
        for _, k in ipairs({ "Background","Top","Middle","Bottom","ScrollUpButton","ScrollDownButton","trackBG" }) do
            if sb[k] then
                sb[k]:Hide()
                sb[k]:SetScript("OnShow", function(s) s:Hide() end)
            end
        end

        -- Track background — same dark fill as the slider rail
        local track = sb:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetColorTexture(T.bgDark[1], T.bgDark[2], T.bgDark[3], 1)

        -- Thumb: accent-colored pill
        sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local thumb = sb:GetThumbTexture()
        if thumb then
            thumb:SetWidth(SB_W)
            thumb:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.75)
        end

        -- Hide until actually needed
        sb:SetAlpha(0)
    end
    -- Permanently suppress Button children on the content scroll frame (WoW 10.x template variation)
    for _, child in ipairs({ contentScroll:GetChildren() }) do
        if child:IsObjectType("Button") then
            child:Hide()
            child:SetScript("OnShow", function(s) s:Hide() end)
        end
    end

    -- Scroll-child (content container)
    local contentSC = CreateFrame("Frame", nil, contentScroll)
    contentSC:SetWidth(contentArea:GetWidth() - T.paddingSmall*2 - SB_W - 4)
    contentSC:SetHeight(1)
    contentScroll:SetScrollChild(contentSC)
    self.contentScrollChild = contentSC
    self.contentScroll      = contentScroll

    -- Dynamic scrollbar visibility + child width on resize
    local function UpdateScrollbar()
        if not sb then return end
        local ch = contentSC:GetHeight()
        local fh = contentScroll:GetHeight()
        sb:SetAlpha((ch > fh + 2) and 1 or 0)
    end
    contentScroll:HookScript("OnVerticalScroll", UpdateScrollbar)
    contentSC:HookScript("OnSizeChanged",        UpdateScrollbar)

    contentArea:SetScript("OnSizeChanged", function(self, w)
        contentSC:SetWidth(w - T.paddingSmall*2 - SB_W - 4)
        UpdateScrollbar()
    end)

    -- ── Smooth mouse-wheel scroll (content) ──────────────────────────────
    contentScroll:EnableMouseWheel(true)
    contentScroll._scrollTarget = 0
    contentScroll:SetScript("OnMouseWheel", function(sf, delta)
        local maxScroll = sf:GetVerticalScrollRange()
        sf._scrollTarget = math.max(0, math.min(sf._scrollTarget - delta * 80, maxScroll))
        if sf._scrollTicker then return end
        sf._scrollTicker = C_Timer.NewTicker(0.016, function()
            local cur = sf:GetVerticalScroll()
            local d   = sf._scrollTarget - cur
            if math.abs(d) < 0.5 then
                sf:SetVerticalScroll(sf._scrollTarget)
                sf._scrollTicker:Cancel(); sf._scrollTicker = nil
                return
            end
            sf:SetVerticalScroll(cur + d * 0.25)
        end)
    end)

    -- ESC closes the GUI. UISpecialFrames is unreliable in TWW — use OnKeyDown instead.
    mainFrame:EnableKeyboard(true)
    mainFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            GUI.Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    -- Default sidebar state
    for _, section in ipairs(self.SidebarConfig) do
        if section.type == "section" and section.defaultExpanded then
            expanded[section.id] = true
        end
    end
    -- Select first item only on first build; preserve selection across theme rebuilds
    if not selectedItem then
        for _, section in ipairs(self.SidebarConfig) do
            if section.type == "section" and section.items and #section.items > 0 then
                selectedItem = section.items[1].id; break
            end
        end
    end
end

-- ============================================================
-- Rebuild (called after theme change)
-- ============================================================
function GUI:Rebuild()
    if mainFrame then
        -- Save current position and size before destroying so theme changes
        -- don't recenter or resize the window back to defaults.
        local p, _, rp, x, y = mainFrame:GetPoint()
        if p then self._savedPos = { p, rp, x, y } end
        local w, h = mainFrame:GetSize()
        if w and w > 0 then self._savedSize = { w, h } end
        mainFrame:Hide()
        mainFrame:SetParent(nil)
        mainFrame = nil
    end
    self.mainFrame = nil

    -- Recycle pools so they are recreated with new theme colors
    for _, h in ipairs(headerPool) do
        if h._arrowTicker then h._arrowTicker:Cancel(); h._arrowTicker = nil end
        h:Hide(); h:SetParent(nil)
    end
    for _, i in ipairs(sidebarPool) do i:Hide(); i:SetParent(nil) end
    wipe(headerPool)
    wipe(sidebarPool)
    wipe(sectionArrowRot)  -- reset animation state; arrows will snap on first draw

    self.sidebarScrollChild = nil
    self.contentScrollChild = nil
    self.contentScroll      = nil

    -- Clear page cache — frames are children of the now-destroyed scroll child;
    -- they'll be rebuilt once on next visit after the window is reopened.
    self.PageCache   = nil
    self._activePage = nil
end

-- ============================================================
-- Public API
-- ============================================================
function GUI.Show()
    if not mainFrame then GUI:BuildMainFrame() end
    mainFrame:Show()
    GUI:RefreshSidebar()
    GUI:RefreshContent()
end

function GUI.Hide()
    if mainFrame then mainFrame:Hide() end
end

function GUI.Toggle()
    if mainFrame and mainFrame:IsShown() then GUI.Hide() else GUI.Show() end
end

-- ============================================================
-- Page: Home
-- ============================================================
GUI:RegisterContent("home", function(parent)
    local y = 0

    -- ── Hero banner ───────────────────────────────────────
    -- Mimics NorskenUI's top banner: title, greeting, version/author
    local charName = UnitName("player") or "Adventurer"
    local _, classToken = UnitClass("player")
    local classColor = RAID_CLASS_COLORS and classToken and RAID_CLASS_COLORS[classToken]
    local nameR = classColor and classColor.r or T.accent[1]
    local nameG = classColor and classColor.g or T.accent[2]
    local nameB = classColor and classColor.b or T.accent[3]
    local nameHex = string.format("%02X%02X%02X",
        math.floor(nameR*255+0.5), math.floor(nameG*255+0.5), math.floor(nameB*255+0.5))
    local accentHex = string.format("%02X%02X%02X",
        math.floor(T.accent[1]*255+0.5), math.floor(T.accent[2]*255+0.5), math.floor(T.accent[3]*255+0.5))

    local BANNER_H = 96
    local banner = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    -- Mirror CreateCard anchors exactly: TOPLEFT + RIGHT, both offset by T.paddingSmall
    banner:SetPoint("TOPLEFT", parent, "TOPLEFT", T.paddingSmall, -(y - T.paddingSmall))
    banner:SetPoint("RIGHT",   parent, "RIGHT",   -T.paddingSmall, 0)
    banner:SetHeight(BANNER_H)
    banner:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    banner:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    banner:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

    -- Thin accent bar on the left edge
    -- "Welcome to" (small, muted, top-left)
    local welcomeLbl = banner:CreateFontString(nil, "OVERLAY")
    welcomeLbl:SetPoint("TOPLEFT", banner, "TOPLEFT", 12, -12)
    welcomeLbl:SetFont(SP_FONT, 11, "")
    welcomeLbl:SetShadowColor(0, 0, 0, 0.8); welcomeLbl:SetShadowOffset(1, -1)
    welcomeLbl:SetText("Welcome to")
    welcomeLbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    -- "Suspicion's Pack" (large, accent-colored)
    local titleLbl = banner:CreateFontString(nil, "OVERLAY")
    titleLbl:SetPoint("TOPLEFT", welcomeLbl, "BOTTOMLEFT", 0, -2)
    titleLbl:SetFont(SP_FONT, 22, "")
    titleLbl:SetShadowColor(0, 0, 0, 0.9); titleLbl:SetShadowOffset(1, -1)
    titleLbl:SetText("Suspicion's Pack")
    titleLbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)

    -- Thin divider line
    local divider = banner:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT",  banner, "TOPLEFT",  14, -(12 + 16 + 28))
    divider:SetPoint("TOPRIGHT", banner, "TOPRIGHT", -14, -(12 + 16 + 28))
    divider:SetColorTexture(T.border[1], T.border[2], T.border[3], 1)

    -- "Hello, CharName!" — name in class color
    local helloLbl = banner:CreateFontString(nil, "OVERLAY")
    helloLbl:SetPoint("TOPLEFT", banner, "TOPLEFT", 14, -(12 + 16 + 28 + 8))
    helloLbl:SetFont(SP_FONT, 14, "")
    helloLbl:SetShadowColor(0, 0, 0, 0.9); helloLbl:SetShadowOffset(1, -1)
    helloLbl:SetText(string.format("Hello, |cff%s%s|r !", nameHex, charName))
    helloLbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)

    -- "vX.X.X  ·  Author: Cruzz" (small, muted, below hello)
    local verLbl = banner:CreateFontString(nil, "OVERLAY")
    verLbl:SetPoint("TOPLEFT", helloLbl, "BOTTOMLEFT", 0, -4)
    verLbl:SetFont(SP_FONT, 10, "")
    verLbl:SetShadowColor(0, 0, 0, 0.8); verLbl:SetShadowOffset(1, -1)
    verLbl:SetText(string.format("v%s  ·  Author: |cff%scruzz|r", SP.VERSION or "1.0.0", accentHex))
    verLbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    y = y + BANNER_H + T.paddingSmall * 2

    -- ── Getting Started card ───────────────────────────────
    local cardGS = GUI:CreateCard(parent, "Getting Started", y)
    cardGS:AddLabel(
        "Suspicion's Pack is a lightweight quality-of-life addon. Each feature can be toggled on or off independently from the sidebar.",
        T.textSecondary)
    cardGS:AddSpacing(4)
    cardGS:AddLabel(
        "|cff" .. accentHex .. "›|r  " .. string.format("Use |cff%s/spack|r or |cff%s/suspicion|r to open this window at any time.", accentHex, accentHex),
        T.textSecondary)
    cardGS:AddSpacing(2)
    cardGS:AddLabel(
        "|cff" .. accentHex .. "›|r  " .. "Navigate the sidebar on the left to find each module's settings.",
        T.textSecondary)
    cardGS:AddSpacing(2)
    cardGS:AddLabel(
        "|cff" .. accentHex .. "›|r  " .. string.format("Change the addon's accent colour under |cff%sCUSTOMISE > Themes|r.", accentHex),
        T.textSecondary)
    y = y + cardGS:GetTotalHeight() + T.paddingSmall

    -- ── Support card ──────────────────────────────────────
    local cardSup = GUI:CreateCard(parent, "Support", y)
    cardSup:AddLabel(
        "If any issue, or LUA error please dm me with the error and a good explanation.",
        T.textMuted)
    y = y + cardSup:GetTotalHeight() + T.paddingSmall

    -- ── Privacy notice ────────────────────────────────────
    local cardPriv = GUI:CreateCard(parent, "Notice", y)
    cardPriv:AddLabel(
        "This addon is a private guild project and is not intended to be published on any platform. Please do not share it with just anyone.",
        T.textMuted)
    y = y + cardPriv:GetTotalHeight() + T.paddingSmall

    -- ── Profiles card ─────────────────────────────────────────────────────
    -- AceSerializer-3.0 + LibDeflate: safe serialization + compression.
    local AceSer  = LibStub and LibStub("AceSerializer-3.0", true)
    local LibDefl = LibStub and LibStub("LibDeflate",        true)

    local function SP_Export(data)
        if not AceSer or not LibDefl then return nil, "AceSerializer or LibDeflate not loaded" end
        local serialized = AceSer:Serialize(data)
        local compressed = LibDefl:CompressDeflate(serialized, { level = 9 })
        return LibDefl:EncodeForPrint(compressed), nil
    end

    local function SP_Import(str)
        if not AceSer or not LibDefl then return nil, "AceSerializer or LibDeflate not loaded" end
        if not str or str:match("^%s*$") then return nil, "Empty string" end
        local decoded = LibDefl:DecodeForPrint(str)
        if not decoded then return nil, "Decode failed — not a valid profile string" end
        local decompressed = LibDefl:DecompressDeflate(decoded)
        if not decompressed then return nil, "Decompress failed — string may be corrupted" end
        local ok, result = AceSer:Deserialize(decompressed)
        if not ok then return nil, "Deserialize failed: " .. tostring(result) end
        if type(result) ~= "table" then return nil, "Not a valid profile table" end
        return result, nil
    end

    local function SP_DeepMerge(dest, src)
        for k, v in pairs(src) do
            if type(v) == "table" and type(dest[k]) == "table" then
                SP_DeepMerge(dest[k], v)
            else
                dest[k] = v
            end
        end
    end

    -- ── Large custom text dialog (shared by Export and Import) ────────────
    -- Lazy-initialised: created once on first Export/Import click, then reused.
    local function GetProfileDialog()
        if SP._profileDialog then return SP._profileDialog end

        local BLANK = "Interface\\Buttons\\WHITE8X8"
        local PFONT = SP.GetFontPath and SP.GetFontPath("Expressway")
                   or "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"
        local SB_W  = 4   -- scrollbar track/thumb width (matches SP main scrollbar)

        local dlg = CreateFrame("Frame", "SP_ProfileDialog", UIParent, "BackdropTemplate")
        dlg:SetSize(620, 480)
        dlg:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
        dlg:SetFrameStrata("DIALOG")
        dlg:SetFrameLevel(200)
        dlg:EnableMouse(true)
        dlg:SetMovable(true)
        dlg:RegisterForDrag("LeftButton")
        dlg:SetScript("OnDragStart", dlg.StartMoving)
        dlg:SetScript("OnDragStop",  dlg.StopMovingOrSizing)
        dlg:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
        dlg:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 0.97)
        dlg:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
        dlg:Hide()

        -- Title bar
        local titleBar = CreateFrame("Frame", nil, dlg, "BackdropTemplate")
        titleBar:SetHeight(34)
        titleBar:SetPoint("TOPLEFT",  dlg, "TOPLEFT",  0, 0)
        titleBar:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", 0, 0)
        titleBar:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
        titleBar:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
        titleBar:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

        local accentBar = titleBar:CreateTexture(nil, "OVERLAY")
        accentBar:SetHeight(2)
        accentBar:SetPoint("BOTTOMLEFT",  titleBar, "BOTTOMLEFT",  0, 0)
        accentBar:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
        accentBar:SetTexture(BLANK)
        accentBar:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 0.9)

        local titleFS = titleBar:CreateFontString(nil, "OVERLAY")
        titleFS:SetFont(PFONT, 13, "")
        titleFS:SetPoint("LEFT", titleBar, "LEFT", 14, 0)
        titleFS:SetTextColor(1, 1, 1, 1)
        dlg._titleFS = titleFS

        local closeBtn = CreateFrame("Button", nil, titleBar)
        closeBtn:SetSize(30, 30)
        closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -6, 0)
        local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY")
        closeTxt:SetFont(PFONT, 18, "")
        closeTxt:SetAllPoints()
        closeTxt:SetJustifyH("CENTER")
        closeTxt:SetText("|cff555555×|r")
        closeBtn:SetScript("OnEnter", function() closeTxt:SetText("|cffffffff×|r") end)
        closeBtn:SetScript("OnLeave", function() closeTxt:SetText("|cff555555×|r") end)
        closeBtn:SetScript("OnClick", function() dlg:Hide() end)

        -- Description
        local descFS = dlg:CreateFontString(nil, "OVERLAY")
        descFS:SetFont(PFONT, 11, "")
        descFS:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",  14, -10)
        descFS:SetPoint("TOPRIGHT", dlg,      "TOPRIGHT",   -14,   0)
        descFS:SetJustifyH("LEFT")
        descFS:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
        dlg._descFS = descFS

        -- EditBox background
        local boxBg = CreateFrame("Frame", nil, dlg, "BackdropTemplate")
        boxBg:SetPoint("TOPLEFT",     descFS, "BOTTOMLEFT",  -2, -10)
        boxBg:SetPoint("BOTTOMRIGHT", dlg,    "BOTTOMRIGHT", -14,  52)
        boxBg:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
        boxBg:SetBackdropColor(0, 0, 0, 0.6)
        boxBg:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

        -- ScrollFrame (plain, no Blizzard template UI chrome) ─────────────
        local scrollFrame = CreateFrame("ScrollFrame", nil, boxBg, "UIPanelScrollFrameTemplate")
        -- Leave room on the right for the custom scrollbar (SB_W + 4px gap)
        scrollFrame:SetPoint("TOPLEFT",     boxBg, "TOPLEFT",      6,          -6)
        scrollFrame:SetPoint("BOTTOMRIGHT", boxBg, "BOTTOMRIGHT", -(SB_W + 8),  6)

        -- ── SP-style custom scrollbar ──────────────────────────────────────
        local sb = scrollFrame.ScrollBar
        if sb then
            sb:ClearAllPoints()
            sb:SetPoint("TOPRIGHT",    boxBg, "TOPRIGHT",    -4, -6)
            sb:SetPoint("BOTTOMRIGHT", boxBg, "BOTTOMRIGHT", -4,  6)
            sb:SetWidth(SB_W)
            -- Suppress all Blizzard default chrome on the scrollbar
            for _, k in ipairs({ "Background","Top","Middle","Bottom","ScrollUpButton","ScrollDownButton","trackBG" }) do
                if sb[k] then
                    sb[k]:Hide()
                    sb[k]:SetScript("OnShow", function(s) s:Hide() end)
                end
            end
            -- Also suppress any Button children (WoW 10.x template variation)
            for _, child in ipairs({ sb:GetChildren() }) do
                if child:IsObjectType("Button") then
                    child:Hide()
                    child:SetScript("OnShow", function(s) s:Hide() end)
                end
            end
            -- Track background
            local track = sb:CreateTexture(nil, "BACKGROUND")
            track:SetAllPoints()
            track:SetColorTexture(T.bgDark[1], T.bgDark[2], T.bgDark[3], 1)
            -- Thumb: accent-coloured pill
            sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
            local thumb = sb:GetThumbTexture()
            if thumb then
                thumb:SetWidth(SB_W)
                thumb:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 0.75)
            end
            sb:SetAlpha(0)  -- hidden until content overflows
        end
        -- Suppress any stray Button children on the scrollframe itself
        for _, child in ipairs({ scrollFrame:GetChildren() }) do
            if child:IsObjectType("Button") then
                child:Hide()
                child:SetScript("OnShow", function(s) s:Hide() end)
            end
        end

        -- EditBox inside the scroll frame
        local editBox = CreateFrame("EditBox", nil, scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetMaxLetters(0)
        editBox:SetFont(PFONT, 10, "")
        editBox:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        editBox:SetTextInsets(4, 4, 4, 4)
        editBox:EnableMouse(true)
        editBox:SetWidth(scrollFrame:GetWidth())
        scrollFrame:SetScrollChild(editBox)

        -- Keep editBox width in sync with scroll frame width
        scrollFrame:SetScript("OnSizeChanged", function(sf)
            editBox:SetWidth(sf:GetWidth())
        end)

        -- Show/hide scrollbar based on content overflow
        local function UpdateDlgScrollbar()
            if not sb then return end
            local ch = editBox:GetHeight()
            local fh = scrollFrame:GetHeight()
            sb:SetAlpha((ch > fh + 2) and 1 or 0)
        end
        scrollFrame:HookScript("OnVerticalScroll", UpdateDlgScrollbar)
        editBox:HookScript("OnSizeChanged",        UpdateDlgScrollbar)

        -- Mouse-wheel scroll
        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(sf, delta)
            local max = sf:GetVerticalScrollRange()
            sf:SetVerticalScroll(math.max(0, math.min(sf:GetVerticalScroll() - delta * 60, max)))
            UpdateDlgScrollbar()
        end)

        editBox:SetScript("OnEscapePressed", function() dlg:Hide() end)
        dlg._editBox = editBox

        -- Hint label (bottom-left)
        local hintFS = dlg:CreateFontString(nil, "OVERLAY")
        hintFS:SetFont(PFONT, 10, "")
        hintFS:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 14, 16)
        hintFS:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
        dlg._hintFS = hintFS

        -- Action button (bottom-right) — uses SP button style via GUI:CreateButton
        local actionWrap = CreateFrame("Frame", nil, dlg)
        actionWrap:SetSize(120, 30)
        actionWrap:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -14, 12)
        function actionWrap:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end
        local actionBtn = GUI:CreateButton(actionWrap, "Close", function() dlg:Hide() end, 120, 30)
        actionBtn:SetPoint("LEFT", actionWrap, "LEFT", 0, 0)
        dlg._actionWrap = actionWrap
        dlg._actionBtn  = actionBtn

        SP._profileDialog = dlg
        return dlg
    end

    local cardProf = GUI:CreateCard(parent, "Profiles", y)
    cardProf:AddLabel(
        "Export your current settings as a compact shareable string. Send it to a guildie so they can import your exact profile.",
        T.textMuted)
    cardProf:AddSeparator()

    -- Export button row
    local exportWrap = CreateFrame("Frame", nil, parent)
    exportWrap:SetHeight(28)
    function exportWrap:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end
    local exportBtn = GUI:CreateButton(exportWrap, "Export Profile", nil, 150, 28)
    exportBtn:SetPoint("LEFT", exportWrap, "LEFT", 0, 0)
    exportBtn:SetScript("OnClick", function()
        local str, err = SP_Export(SP.db.profile)
        if not str then
            print("|cffff4444[SuspicionsPack]|r Export failed: " .. (err or "unknown error"))
            return
        end
        local dlg = GetProfileDialog()
        dlg._titleFS:SetText("|cff" .. accentHex .. "Suspicion's Pack|r — Export Profile")
        dlg._descFS:SetText("Select all (Ctrl+A) then copy (Ctrl+C). Send this string to your guildmates.")
        dlg._hintFS:SetText("Compressed with LibDeflate  ·  " .. #str .. " characters")
        -- Keep editBox fully enabled so the user can click, select, and copy text
        dlg._editBox:SetEnabled(true)
        dlg._editBox:SetText(str)
        dlg._editBox:HighlightText()
        dlg._actionBtn.lbl:SetText("Close")
        dlg._actionBtn:SetScript("OnClick", function() dlg:Hide() end)
        dlg:Show()
        dlg._editBox:SetFocus()
    end)
    cardProf:AddRow(exportWrap, 28)

    cardProf:AddSpacing(4)

    -- Import button row
    local importWrap = CreateFrame("Frame", nil, parent)
    importWrap:SetHeight(28)
    function importWrap:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end
    local importBtn = GUI:CreateButton(importWrap, "Import Profile", nil, 150, 28)
    importBtn:SetPoint("LEFT", importWrap, "LEFT", 0, 0)
    importBtn:SetScript("OnClick", function()
        local dlg = GetProfileDialog()
        dlg._titleFS:SetText("|cff" .. accentHex .. "Suspicion's Pack|r — Import Profile")
        dlg._descFS:SetText("Paste the profile string below, then click Apply Import.")
        dlg._hintFS:SetText("Deep-merge: only overwrites keys present in the string.")
        dlg._editBox:SetEnabled(true)
        dlg._editBox:SetText("")
        dlg._actionBtn.lbl:SetText("Apply Import")
        dlg._actionBtn:SetScript("OnClick", function()
            local str = dlg._editBox:GetText()
            local data, err = SP_Import(str)
            if not data then
                print("|cffff4444[SuspicionsPack]|r Import failed: " .. (err or "unknown error"))
                return
            end
            SP_DeepMerge(SP.db.profile, data)
            if SP.RefreshTheme then SP.RefreshTheme() end
            dlg:Hide()
            print("|cff" .. accentHex .. "[SuspicionsPack]|r Profile imported. Type /reload for full effect.")
        end)
        dlg:Show()
        dlg._editBox:SetFocus()
    end)
    cardProf:AddRow(importWrap, 28)

    cardProf:AddSpacing(4)
    cardProf:AddLabel("Captures all shared module settings. Strings are compressed — safe to paste in Discord or chat.", T.textMuted)

    y = y + cardProf:GetTotalHeight() + T.paddingSmall

    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Drawer Settings
-- ============================================================
GUI:RegisterContent("drawer", function(parent)
    local db = SP.GetDB().drawer
    local y  = 0

    -- Shared label/value maps for color source dropdowns
    local csLabels    = { "Theme Color", "Class Color" }
    local csToLabel   = { theme = "Theme Color", class = "Class Color" }
    local csToKey     = { ["Theme Color"] = "theme", ["Class Color"] = "class" }

    -- Tab color source (3 options incl. Custom)
    local tcLabels   = { "Theme Color", "Class Color", "Custom Color" }
    local tcToLabel  = { theme = "Theme Color", class = "Class Color", custom = "Custom Color" }
    local tcToKey    = { ["Theme Color"] = "theme", ["Class Color"] = "class", ["Custom Color"] = "custom" }

    -- Child rows/cards — grayed when the module master toggle is OFF
    local childRows  = {}
    local childCards = {}

    -- Forward-declare the panel border color row so the border toggle can reference it
    local borderColorRow
    local enableRow  -- forward-declared; used in UpdateChildState closure
    local card1      -- forward-declared for UpdateChildState closure

    local function UpdateChildState(en)
        card1:GrayContent(en, enableRow)
        for _, r in ipairs(childRows)  do r:SetEnabled(en) end
        for _, c in ipairs(childCards) do c:SetAlpha(en and 1 or 0.4) end
        -- Sub-dependency: border color row only usable when border is also ON
        if borderColorRow then
            borderColorRow:SetEnabled(en and (db.showBorder ~= false))
        end
    end

    -- ── Card 1: Minimap Drawer (general + behavior) ────────
    card1 = GUI:CreateCard(parent, "Minimap Drawer", y)
    card1:AddLabel("Collect addon minimap buttons into a sliding drawer.", T.textMuted)
    card1:AddSeparator()

    enableRow = GUI:CreateToggle(parent, "Enable Drawer", db.enabled, function(v)
        db.enabled = v
        UpdateChildState(v)
        if v then SP.Drawer.Enable() else SP.Drawer.Disable() end
    end, "Minimap Drawer")
    card1:AddRow(enableRow, 28)
    card1:AddSeparator()

    local sideRow = GUI:CreateDropdown(parent, "Drawer Side",
        { "LEFT", "RIGHT", "TOP", "BOTTOM" }, db.side or "LEFT",
        function(v) db.side = v; SP.Drawer.SetSide(v) end)
    card1:AddRow(sideRow, 40)
    table.insert(childRows, sideRow)

    local hideDelayRow = GUI:CreateSlider(parent, "Hide Delay (s × 10)", 1, 20, 1,
        math.floor(db.hideDelay * 10 + 0.5),
        function(v) db.hideDelay = v / 10 end)
    card1:AddRow(hideDelayRow, 44)
    table.insert(childRows, hideDelayRow)

    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- ── Card: Tab ─────────────────────────────────────────
    local cardTab = GUI:CreateCard(parent, "Tab", y)
    cardTab:AddLabel("Customise the size and colour of the minimap drawer tab.", T.textMuted)
    cardTab:AddSeparator()

    local tabWRow = GUI:CreateSlider(parent, "Tab Width",  4, 48, 1, db.tabW,
        function(v) db.tabW = v; SP.Drawer.Refresh() end)
    cardTab:AddRow(tabWRow, 44)

    local tabHRow = GUI:CreateSlider(parent, "Tab Height", 16, 80, 1, db.tabH,
        function(v) db.tabH = v; SP.Drawer.Refresh() end)
    cardTab:AddRow(tabHRow, 44)

    cardTab:AddSeparator()

    local tabBorderRow = GUI:CreateToggle(parent, "Tab Border",
        db.showTabBorder or false,
        function(v) db.showTabBorder = v; SP.Drawer.Refresh() end)
    cardTab:AddRow(tabBorderRow, 28)

    local errorAlertRow = GUI:CreateToggle(parent, "Error Alert",
        db.errorAlert ~= false,
        function(v)
            db.errorAlert = v
            SP.Drawer.Refresh()
        end)
    cardTab:AddRow(errorAlertRow, 28)
    cardTab:AddLabel(
        "Tab turns red when a Lua error is caught by BugGrabber during the session.",
        T.textMuted)

    cardTab:AddSeparator()

    -- Tab color source (Theme / Class / Custom)
    local SetTabSwatchEnabled  -- forward-declared; defined after swatchRow is built
    local tabSrcRow = GUI:CreateDropdown(parent, "Color Source",
        tcLabels,
        tcToLabel[db.tabColorSource or "theme"],
        function(v)
            db.tabColorSource = tcToKey[v]
            SP.Drawer.Refresh()
            if SetTabSwatchEnabled then SetTabSwatchEnabled(tcToKey[v] == "custom") end
        end)
    cardTab:AddRow(tabSrcRow, 40)
    cardTab:AddSeparator()

    -- Custom color swatch
    local tc = db.tabColor or { 0.6, 0.6, 0.6 }
    local cr, cg, cb = tc[1], tc[2], tc[3]

    local swatchRow = CreateFrame("Frame", nil, parent)
    swatchRow:SetHeight(52)

    local ccLbl = swatchRow:CreateFontString(nil, "OVERLAY")
    ccLbl:SetPoint("TOPLEFT", swatchRow, "TOPLEFT", 0, -2)
    ccLbl:SetJustifyH("LEFT")
    ApplyFont(ccLbl, 11)
    ccLbl:SetText("Custom Color")
    ccLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

    local swatch = MakeCheckerSwatch(swatchRow, 48, 24)
    swatch:SetPoint("TOPLEFT", swatchRow, "TOPLEFT", 0, -18)

    local drawerHexLbl = swatchRow:CreateFontString(nil, "OVERLAY")
    drawerHexLbl:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
    ApplyFont(drawerHexLbl, 11)
    drawerHexLbl:SetJustifyH("LEFT")
    drawerHexLbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    local function RefreshDrawerSwatch(nr, ng, nb)
        swatch:Refresh(nr, ng, nb)
        drawerHexLbl:SetText(ColorToHex(nr, ng, nb))
    end
    RefreshDrawerSwatch(cr, cg, cb)
    swatch:SetScript("OnClick", function()
        local prevR, prevG, prevB = cr, cg, cb
        local function UpdateColor(nr, ng, nb)
            cr, cg, cb = nr, ng, nb
            RefreshDrawerSwatch(cr, cg, cb)
            if not db.tabColor then db.tabColor = {} end
            db.tabColor[1] = cr; db.tabColor[2] = cg; db.tabColor[3] = cb
            SP.Drawer.Refresh()
        end
        local info = {
            r = prevR, g = prevG, b = prevB,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                UpdateColor(nr or prevR, ng or prevG, nb or prevB)
            end,
            cancelFunc = function() UpdateColor(prevR, prevG, prevB) end,
        }
        info.opacityFunc = info.swatchFunc
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)

    cardTab:AddRow(swatchRow, 52)

    -- Wire up enable/disable; grey when colorSource is not "custom"
    SetTabSwatchEnabled = function(en)
        swatchRow:SetAlpha(en and 1 or 0.4)
        swatch:EnableMouse(en)
    end
    SetTabSwatchEnabled((db.tabColorSource or "theme") == "custom")

    table.insert(childCards, cardTab)
    y = y + cardTab:GetTotalHeight() + T.paddingSmall

    -- ── Card: Button Layout ───────────────────────────────
    local card2 = GUI:CreateCard(parent, "Button Layout", y)
    card2:AddLabel("Adjust the panel border, button padding, and icon sizing inside the drawer.", T.textMuted)
    card2:AddSeparator()

    local borderRow = GUI:CreateToggle(parent, "Panel Border",
        db.showBorder ~= false,
        function(v)
            db.showBorder = v
            SP.Drawer.Refresh()
            -- Gray the border color dropdown when border is toggled off
            if borderColorRow then
                borderColorRow:SetEnabled(db.enabled and v)
            end
        end)
    card2:AddRow(borderRow, 28)

    -- Panel border color source (only active when Panel Border is ON)
    borderColorRow = GUI:CreateDropdown(parent, "Border Color",
        csLabels,
        csToLabel[db.borderColorSource or "theme"],
        function(v)
            db.borderColorSource = csToKey[v]
            SP.Drawer.Refresh()
        end)
    card2:AddRow(borderColorRow, 40)

    card2:AddSeparator()

    card2:AddRow(GUI:CreateSlider(parent, "Button Size", 14, 40, 1, db.btnSize,
        function(v) db.btnSize = v; SP.Drawer.Refresh() end), 44)
    card2:AddRow(GUI:CreateSlider(parent, "Icon Size", 10, 36, 1, db.iconSize,
        function(v) db.iconSize = v; SP.Drawer.Refresh() end), 44)
    card2:AddRow(GUI:CreateSlider(parent, "Button Padding", 2, 16, 1, db.btnPad,
        function(v) db.btnPad = v; SP.Drawer.Refresh() end), 44)
    card2:AddRow(GUI:CreateSlider(parent, "Max Columns", 1, 10, 1, db.maxCols,
        function(v) db.maxCols = v; SP.Drawer.Refresh() end), 44)

    table.insert(childCards, card2)
    y = y + card2:GetTotalHeight() + T.paddingSmall

    -- ── Card: Minimap Button Borders ──────────────────────
    -- Styles the circular gold border on buttons kept on the minimap (rule = "Minimap").
    local cardBorder = GUI:CreateCard(parent, "Minimap Button Borders", y)
    cardBorder:AddLabel(
        "Style for the circular border ring on buttons kept on the minimap.",
        T.textMuted)
    cardBorder:AddSeparator()

    local bsRow = CreateFrame("Frame", nil, parent)
    bsRow:SetHeight(42)

    local bsRowLbl = bsRow:CreateFontString(nil, "OVERLAY")
    bsRowLbl:SetPoint("TOPLEFT", bsRow, "TOPLEFT", 0, -2)
    ApplyFont(bsRowLbl, 11)
    bsRowLbl:SetText("Border Style")
    bsRowLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    bsRowLbl:SetJustifyH("LEFT")

    local bsDD = CreateDropdown(bsRow,
        {
            { key = "default", label = "Gold" },
            { key = "dark",    label = "Dark" },
            { key = "none",    label = "None" },
        },
        db.buttonBorderStyle or "default",
        function(key)
            db.buttonBorderStyle = key
            if SP.Drawer then SP.Drawer.ApplyAllBorderStyles() end
        end,
        110)
    bsDD:SetPoint("BOTTOMLEFT", bsRow, "BOTTOMLEFT", 0, 0)

    cardBorder:AddRow(bsRow, 42)
    table.insert(childCards, cardBorder)
    y = y + cardBorder:GetTotalHeight() + T.paddingSmall

    -- ── Card: Button Rules ────────────────────────────────
    if not db.buttonRules then db.buttonRules = {} end
    local names = SP.Drawer and SP.Drawer.GetKnownNames() or {}

    -- Rule options for the dropdown
    local RULE_OPTIONS = {
        { key = "",       label = "Drawer"  },
        { key = "ignore", label = "Minimap" },
        { key = "hide",   label = "Hide"    },
    }
    local RULE_DD_W = 110

    -- Builds a row: addon name label (top) + dropdown below it.
    -- Returns a Frame with a :SetEnabled(bool) method.
    local function CreateRuleRow(rowParent, addonName)
        local row = CreateFrame("Frame", nil, rowParent)
        row:SetHeight(42)

        -- Addon name label (top-left)
        local lbl = row:CreateFontString(nil, "OVERLAY")
        lbl:SetPoint("TOPLEFT",  row, "TOPLEFT",  0, -2)
        lbl:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
        ApplyFont(lbl, 11)
        lbl:SetText(addonName)
        lbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(false)
        lbl:SetNonSpaceWrap(false)

        -- Dropdown below the label (left-aligned, full width)
        local dd = CreateDropdown(row, RULE_OPTIONS, db.buttonRules[addonName] or "",
            function(key)
                if key == "" then
                    db.buttonRules[addonName] = nil
                else
                    db.buttonRules[addonName] = key
                end
                if SP.Drawer then SP.Drawer.CaptureButtons() end
            end, RULE_DD_W)
        dd:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)

        function row:SetEnabled(en)
            self:SetAlpha(en and 1 or 0.4)
            dd:EnableMouse(en)
        end

        return row
    end

    local card5 = GUI:CreateCard(parent, "Button Rules", y)
    if #names == 0 then
        card5:AddLabel(
            "No buttons detected yet — enable the drawer and enter the world first.",
            T.textMuted)
    else
        card5:AddLabel(
            "Choose what happens to each addon button.",
            T.textMuted)
        card5:AddSeparator()
        for _, name in ipairs(names) do
            local row = CreateRuleRow(parent, name)
            card5:AddRow(row, 42)
            table.insert(childRows, row)
        end
    end

    table.insert(childCards, card5)
    y = y + card5:GetTotalHeight() + T.paddingSmall

    -- Apply initial state (grays everything when drawer is disabled)
    UpdateChildState(db.enabled)

    parent:SetHeight(y)
end)

-- ============================================================
-- Cursor texture picker widget
-- Six square buttons showing the actual ring texture; selected one
-- gets an accent-coloured border.  Mirrors NorskenUI's selector.
-- ============================================================
local function MakeCursorTexturePicker(parent, textures, order, getColorFunc, onSelect)
    local BTN_SZ   = 70
    local MIN_GAP  = 8
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(BTN_SZ)

    local buttons = {}
    local current = nil   -- set via container:SetValue()

    for i, textureName in ipairs(order) do
        local texPath = textures[textureName]

        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetSize(BTN_SZ, BTN_SZ)
        btn:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
        btn:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 1)
        btn.textureName = textureName

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT",     btn, "TOPLEFT",     8, -8)
        tex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -8,  8)
        tex:SetTexture(texPath)
        btn.tex = tex

        local function UpdateVisuals()
            local r, g, b = 1, 1, 1
            if getColorFunc then r, g, b = getColorFunc() end
            if btn.disabled then
                btn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.6)
                tex:SetVertexColor(r * 0.3, g * 0.3, b * 0.3)
                tex:SetAlpha(0.5)
            elseif current == btn.textureName then
                btn:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
                tex:SetVertexColor(r, g, b)
                tex:SetAlpha(0.9)
            elseif btn.hover then
                btn:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 0.7)
                tex:SetVertexColor(r * 0.85, g * 0.85, b * 0.85)
                tex:SetAlpha(0.85)
            else
                btn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
                tex:SetVertexColor(r * 0.6, g * 0.6, b * 0.6)
                tex:SetAlpha(0.75)
            end
        end
        btn.UpdateVisuals = UpdateVisuals

        btn:SetScript("OnEnter", function(self)
            self.hover = true
            UpdateVisuals()
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(textureName, 1, 0.82, 0)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self.hover = false
            UpdateVisuals()
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function(self)
            if self.disabled then return end
            current = self.textureName
            for _, b in ipairs(buttons) do b.UpdateVisuals() end
            if onSelect then onSelect(self.textureName) end
        end)

        buttons[i] = btn
    end

    container:SetScript("OnSizeChanged", function(self, w)
        if not w or w <= 0 then return end
        local fw = math.floor(w)
        if math.abs(fw - (self._lastW or 0)) < 2 then return end
        self._lastW = fw
        local n = #buttons
        if n == 0 then return end
        local spacing = math.max(MIN_GAP,
            math.floor((fw - n * BTN_SZ - T.paddingSmall) / (n - 1)))
        for i, btn in ipairs(buttons) do
            btn:ClearAllPoints()
            if i == 1 then
                btn:SetPoint("LEFT", self, "LEFT", 0, 0)
            else
                btn:SetPoint("LEFT", buttons[i-1], "RIGHT", spacing, 0)
            end
        end
    end)

    function container:SetValue(v)
        current = v
        for _, b in ipairs(buttons) do b.UpdateVisuals() end
    end

    function container:SetEnabled(en)
        for _, b in ipairs(buttons) do
            b.disabled = not en
            b:EnableMouse(en)
            b.UpdateVisuals()
        end
    end

    function container:RefreshColors()
        for _, b in ipairs(buttons) do b.UpdateVisuals() end
    end

    return container
end

-- ============================================================
-- Page: Cursor Circle
-- ============================================================
GUI:RegisterContent("cursor", function(parent)
    local db = SP.GetDB().cursor
    local y  = 0

    -- ── Preview helpers (declared first so all cards can call UpdatePreview) ──
    local previewCircTex, previewDotTex

    local function GetPreviewColor()
        local src = db.colorSource or "theme"
        if src == "theme" then return T.accent[1], T.accent[2], T.accent[3] end
        if src == "class" then
            local _, cls = UnitClass("player")
            local c = RAID_CLASS_COLORS and cls and RAID_CLASS_COLORS[cls]
            if c then return c.r, c.g, c.b end
        end
        local cc = db.cursorColor or { 1, 1, 1 }
        return cc[1], cc[2], cc[3]
    end

    local function UpdatePreview()
        if not previewCircTex then return end
        local texPath = SP.Cursor and SP.Cursor.Textures
            and SP.Cursor.Textures[db.texture or "Thick"]
        if texPath then
            -- SetTexture() never throws a Lua error in WoW — it silently shows blank
            -- on failure, so pcall does not help.  Reset to nil first to force a full
            -- reload (fixes Thick/PNG not refreshing on first preview open), then apply.
            previewCircTex:SetTexture(nil)
            previewCircTex:SetTexture(texPath)
            previewCircTex:SetBlendMode("BLEND")
        end
        local r, g, b = GetPreviewColor()
        previewCircTex:SetVertexColor(r, g, b, 0.9)
        local gs = db.size or 50
        local ds = math.floor(24 + (gs - 20) * (72 - 24) / (120 - 20) + 0.5)
        ds = math.max(24, math.min(72, ds))
        previewCircTex:SetSize(ds, ds)
        if previewDotTex then
            if db.showDot then previewDotTex:Show() else previewDotTex:Hide() end
            local dotDisp = math.max(2, math.floor((db.dotSize or 6) * 1.3 + 0.5))
            previewDotTex:SetSize(dotDisp, dotDisp)
        end
    end

    -- ── Card 1: Preview (at the top) ──────────────────────
    local PREV_BOX = 100
    local card1 = GUI:CreateCard(parent, "Preview", y)
    card1:AddLabel("Live preview of the cursor circle with the current settings applied.", T.textMuted)
    -- Match the card body color to the dark preview window inside it
    card1:SetBackdropColor(0.04, 0.04, 0.04, 1)

    local wrapRow = CreateFrame("Frame", nil, parent)
    wrapRow:SetHeight(PREV_BOX + T.paddingSmall * 2)
    wrapRow:EnableMouse(false)

    local prevBg = CreateFrame("Frame", nil, wrapRow, "BackdropTemplate")
    prevBg:SetSize(PREV_BOX, PREV_BOX)
    prevBg:SetPoint("CENTER", wrapRow, "CENTER", 0, 0)
    prevBg:EnableMouse(false)
    prevBg:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    prevBg:SetBackdropColor(0.04, 0.04, 0.04, 1)
    prevBg:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)

    local function MakeLine(w, h, a)
        local l = prevBg:CreateTexture(nil, "ARTWORK")
        l:SetSize(w, h); l:SetColorTexture(1, 1, 1, a); return l
    end
    local hLine = MakeLine(PREV_BOX - 4, 1, 0.04)
    hLine:SetPoint("CENTER", prevBg, "CENTER", 0, 0)
    local vLine = MakeLine(1, PREV_BOX - 4, 0.04)
    vLine:SetPoint("CENTER", prevBg, "CENTER", 0, 0)

    previewCircTex = prevBg:CreateTexture(nil, "ARTWORK")
    previewCircTex:SetPoint("CENTER", prevBg, "CENTER", 0, 0)
    previewCircTex:SetSize(50, 50)   -- initial size avoids 0×0 render before UpdatePreview fires
    previewCircTex:SetTexelSnappingBias(0)
    previewCircTex:SetSnapToPixelGrid(false)

    previewDotTex = prevBg:CreateTexture(nil, "OVERLAY")
    previewDotTex:SetTexture(CURSOR_MEDIA .. "Click.tga")
    previewDotTex:SetPoint("CENTER", prevBg, "CENTER", 0, 0)
    previewDotTex:SetVertexColor(1, 1, 1, 1)
    previewDotTex:SetTexelSnappingBias(0)
    previewDotTex:SetSnapToPixelGrid(false)

    card1:AddRow(wrapRow, PREV_BOX + T.paddingSmall * 2)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- ── Card 2: Settings ──────────────────────────────────
    local card2 = GUI:CreateCard(parent, "Cursor Circle", y)
    card2:AddLabel("A decorative ring that follows your mouse cursor on screen.", T.textMuted)
    card2:AddSeparator()

    local cursorEnableRow  -- forward-declared; used in UpdateCursorChildState closure
    local cursorChildCards = {}
    local function UpdateCursorChildState(en)
        card2:GrayContent(en, cursorEnableRow)
        for _, c in ipairs(cursorChildCards) do c:SetAlpha(en and 1 or 0.4) end
    end

    cursorEnableRow = GUI:CreateToggle(parent, "Enable Cursor Circle",
        db.enabled,
        function(v) db.enabled = v; UpdateCursorChildState(v); SP.Cursor.Refresh(); UpdatePreview() end,
        "Cursor Circle")
    card2:AddRow(cursorEnableRow, 28)
    card2:AddSeparator()

    local sizeRow = GUI:CreateSlider(parent, "Size", 20, 120, 2, db.size,
        function(v) db.size = v; SP.Cursor.Refresh(); UpdatePreview() end)
    card2:AddRow(sizeRow, 44)
    card2:AddSeparator()

    local texPickerLbl = CreateFrame("Frame", nil, parent)
    texPickerLbl:SetHeight(14)
    local _tpl = texPickerLbl:CreateFontString(nil, "OVERLAY")
    _tpl:SetAllPoints(); _tpl:SetJustifyH("LEFT"); ApplyFont(_tpl, 11)
    _tpl:SetText("Texture")
    _tpl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    function texPickerLbl:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end
    card2:AddRow(texPickerLbl, 14, 4)

    local texPicker = MakeCursorTexturePicker(parent,
        SP.Cursor.Textures, SP.Cursor.TextureOrder,
        GetPreviewColor,
        function(v) db.texture = v; SP.Cursor.Refresh(); UpdatePreview();
            texPicker:SetValue(v) end)
    texPicker:SetValue(db.texture or "Thick")
    card2:AddRow(texPicker, 70)
    card2:AddSeparator()

    local dotToggleRow = GUI:CreateToggle(parent, "Center Dot",
        db.showDot,
        function(v) db.showDot = v; SP.Cursor.Refresh(); UpdatePreview() end)
    card2:AddRow(dotToggleRow, 28)

    local dotSizeRow = GUI:CreateSlider(parent, "Dot Size", 2, 16, 1, db.dotSize,
        function(v) db.dotSize = v; SP.Cursor.Refresh(); UpdatePreview() end)
    card2:AddRow(dotSizeRow, 44)
    card2:AddSeparator()

    local cSrcLabels  = { "Theme Color", "Class Color", "Custom Color" }
    local cSrcToLabel = { theme = "Theme Color", class = "Class Color", custom = "Custom Color" }
    local cLabelToSrc = { ["Theme Color"] = "theme", ["Class Color"] = "class", ["Custom Color"] = "custom" }
    local SetCursorSwatchEnabled  -- forward-declared; defined after cSwatchRow is built
    card2:AddRow(GUI:CreateDropdown(parent, "Color Source",
        cSrcLabels,
        cSrcToLabel[db.colorSource or "theme"],
        function(v)
            db.colorSource = cLabelToSrc[v]
            SP.Cursor.Refresh(); UpdatePreview()
            if texPicker then texPicker:RefreshColors() end
            if SetCursorSwatchEnabled then SetCursorSwatchEnabled(cLabelToSrc[v] == "custom") end
        end), 40)
    card2:AddSeparator()

    local cc = db.cursorColor or { 1, 1, 1 }
    local ccr, ccg, ccb = cc[1], cc[2], cc[3]

    local cSwatchRow = CreateFrame("Frame", nil, parent)
    cSwatchRow:SetHeight(52)

    local cSwLbl = cSwatchRow:CreateFontString(nil, "OVERLAY")
    cSwLbl:SetPoint("TOPLEFT", cSwatchRow, "TOPLEFT", 0, -2)
    cSwLbl:SetJustifyH("LEFT"); ApplyFont(cSwLbl, 11)
    cSwLbl:SetText("Custom Color")
    cSwLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

    local cSwatch = MakeCheckerSwatch(cSwatchRow, 48, 24)
    cSwatch:SetPoint("TOPLEFT", cSwatchRow, "TOPLEFT", 0, -18)

    local cSwHexLbl = cSwatchRow:CreateFontString(nil, "OVERLAY")
    cSwHexLbl:SetPoint("LEFT", cSwatch, "RIGHT", 6, 0)
    ApplyFont(cSwHexLbl, 11)
    cSwHexLbl:SetJustifyH("LEFT")
    cSwHexLbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    local function RefreshCursorSwatch(nr, ng, nb)
        cSwatch:Refresh(nr, ng, nb)
        cSwHexLbl:SetText(ColorToHex(nr, ng, nb))
    end
    RefreshCursorSwatch(ccr, ccg, ccb)
    cSwatch:SetScript("OnClick", function()
        local prevR, prevG, prevB = ccr, ccg, ccb
        local function UpdateCursorColor(nr, ng, nb)
            ccr, ccg, ccb = nr, ng, nb
            RefreshCursorSwatch(ccr, ccg, ccb)
            if not db.cursorColor then db.cursorColor = {} end
            db.cursorColor[1] = ccr; db.cursorColor[2] = ccg; db.cursorColor[3] = ccb
            SP.Cursor.Refresh(); UpdatePreview()
            if texPicker then texPicker:RefreshColors() end
        end
        local info = {
            r = prevR, g = prevG, b = prevB,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                UpdateCursorColor(nr or prevR, ng or prevG, nb or prevB)
            end,
            cancelFunc = function() UpdateCursorColor(prevR, prevG, prevB) end,
        }
        info.opacityFunc = info.swatchFunc
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)
    card2:AddRow(cSwatchRow, 52)

    -- Wire up enable/disable; grey when colorSource is not "custom"
    SetCursorSwatchEnabled = function(en)
        cSwatchRow:SetAlpha(en and 1 or 0.4)
        cSwatch:EnableMouse(en)
    end
    SetCursorSwatchEnabled((db.colorSource or "theme") == "custom")

    y = y + card2:GetTotalHeight() + T.paddingSmall

    -- ── Card 4: Click Circle ──────────────────────────────
    local card4 = GUI:CreateCard(parent, "Click Circle", y)
    table.insert(cursorChildCards, card4)
    card4:AddLabel("A ring that appears or replaces the cursor while a mouse button is held.", T.textMuted)
    card4:AddSeparator()

    local clickEnRow  -- forward-declared; used in GrayContent skip + closure
    local SetClickSwatchEnabled

    clickEnRow = GUI:CreateToggle(parent, "Enable Click Circle",
        db.showClickCircle or false,
        function(v)
            db.showClickCircle = v
            card4:GrayContent(v, clickEnRow)
            SP.Cursor.Refresh()
        end)
    card4:AddRow(clickEnRow, 28)
    card4:AddSeparator()

    -- Mode: Overlay (second ring) vs Replace (swap main ring)
    local clickModeRow = GUI:CreateDropdown(parent, "Mode",
        { "Overlay", "Replace" },
        (db.clickMode == "replace") and "Replace" or "Overlay",
        function(v)
            db.clickMode = (v == "Replace") and "replace" or "overlay"
            SP.Cursor.Refresh()
        end)
    card4:AddRow(clickModeRow, 44)
    card4:AddSeparator()

    local clickSzRow = GUI:CreateSlider(parent, "Size", 20, 150, 2, db.clickSize or 70,
        function(v) db.clickSize = v; SP.Cursor.Refresh(); SP.Cursor.PreviewClickCircle() end)
    card4:AddRow(clickSzRow, 44)
    card4:AddSeparator()

    local clickTexPickerLbl = CreateFrame("Frame", nil, parent)
    clickTexPickerLbl:SetHeight(14)
    local _ctpl = clickTexPickerLbl:CreateFontString(nil, "OVERLAY")
    _ctpl:SetAllPoints(); _ctpl:SetJustifyH("LEFT"); ApplyFont(_ctpl, 11)
    _ctpl:SetText("Texture")
    _ctpl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    function clickTexPickerLbl:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end
    card4:AddRow(clickTexPickerLbl, 14, 4)

    local function GetClickPreviewColor()
        local src = db.clickColorSource or "theme"
        if src == "theme" then return T.accent[1], T.accent[2], T.accent[3] end
        if src == "class" then
            local _, cls = UnitClass("player")
            local c = RAID_CLASS_COLORS and cls and RAID_CLASS_COLORS[cls]
            if c then return c.r, c.g, c.b end
        end
        local cc = db.clickColor or { 1, 1, 1 }
        return cc[1], cc[2], cc[3]
    end

    local clickTexPicker = MakeCursorTexturePicker(parent,
        SP.Cursor.Textures, SP.Cursor.TextureOrder,
        GetClickPreviewColor,
        function(v) db.clickTexture = v; SP.Cursor.Refresh();
            clickTexPicker:SetValue(v) end)
    clickTexPicker:SetValue(db.clickTexture or "Thin")
    card4:AddRow(clickTexPicker, 70)
    card4:AddSeparator()

    -- Color source for click circle
    local cklSrcLabels  = { "Theme Color", "Class Color", "Custom Color" }
    local cklSrcToLabel = { theme = "Theme Color", class = "Class Color", custom = "Custom Color" }
    local cklLabelToSrc = { ["Theme Color"] = "theme", ["Class Color"] = "class", ["Custom Color"] = "custom" }
    local clickSrcRow = GUI:CreateDropdown(parent, "Color Source",
        cklSrcLabels,
        cklSrcToLabel[db.clickColorSource or "theme"],
        function(v)
            db.clickColorSource = cklLabelToSrc[v]
            SP.Cursor.Refresh()
            if clickTexPicker then clickTexPicker:RefreshColors() end
            if SetClickSwatchEnabled then SetClickSwatchEnabled(cklLabelToSrc[v] == "custom") end
        end)
    card4:AddRow(clickSrcRow, 44)
    card4:AddSeparator()

    -- Custom color swatch for click circle
    local ckc = db.clickColor or { 1, 1, 1 }
    local cklR, cklG, cklB = ckc[1], ckc[2], ckc[3]

    local cklSwRow = CreateFrame("Frame", nil, parent)
    cklSwRow:SetHeight(52)

    local cklSwLbl = cklSwRow:CreateFontString(nil, "OVERLAY")
    cklSwLbl:SetPoint("TOPLEFT", cklSwRow, "TOPLEFT", 0, -2)
    cklSwLbl:SetJustifyH("LEFT"); ApplyFont(cklSwLbl, 11)
    cklSwLbl:SetText("Custom Color")
    cklSwLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)

    local cklSwatch = MakeCheckerSwatch(cklSwRow, 48, 24)
    cklSwatch:SetPoint("TOPLEFT", cklSwRow, "TOPLEFT", 0, -18)

    local cklHexLbl = cklSwRow:CreateFontString(nil, "OVERLAY")
    cklHexLbl:SetPoint("LEFT", cklSwatch, "RIGHT", 6, 0)
    ApplyFont(cklHexLbl, 11)
    cklHexLbl:SetJustifyH("LEFT")
    cklHexLbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

    local function RefreshClickSwatch(nr, ng, nb)
        cklSwatch:Refresh(nr, ng, nb)
        cklHexLbl:SetText(ColorToHex(nr, ng, nb))
    end
    RefreshClickSwatch(cklR, cklG, cklB)
    cklSwatch:SetScript("OnClick", function()
        local prevR, prevG, prevB = cklR, cklG, cklB
        local function UpdateClickColor(nr, ng, nb)
            cklR, cklG, cklB = nr, ng, nb
            RefreshClickSwatch(cklR, cklG, cklB)
            if not db.clickColor then db.clickColor = {} end
            db.clickColor[1] = cklR; db.clickColor[2] = cklG; db.clickColor[3] = cklB
            SP.Cursor.Refresh()
            if clickTexPicker then clickTexPicker:RefreshColors() end
        end
        local info = {
            r = prevR, g = prevG, b = prevB,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                UpdateClickColor(nr or prevR, ng or prevG, nb or prevB)
            end,
            cancelFunc = function() UpdateClickColor(prevR, prevG, prevB) end,
        }
        info.opacityFunc = info.swatchFunc
        ColorPickerFrame:SetupColorPickerAndShow(info)
    end)
    function cklSwRow:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        cklSwatch:EnableMouse(en)
    end
    card4:AddRow(cklSwRow, 52)

    SetClickSwatchEnabled = function(en)
        cklSwRow:SetAlpha(en and 1 or 0.4)
        cklSwatch:EnableMouse(en)
    end
    SetClickSwatchEnabled((db.clickColorSource or "theme") == "custom")
    card4:GrayContent(db.showClickCircle or false, clickEnRow)

    y = y + card4:GetTotalHeight() + T.paddingSmall

    -- Card 5: Performance
    local card5 = GUI:CreateCard(parent, "Performance", y)
    table.insert(cursorChildCards, card5)

    local limitRow = GUI:CreateToggle(parent, "Limit Update Rate (saves CPU)", db.limitUpdateRate,
        function(v)
            db.limitUpdateRate = v
            Cursor.Refresh()
        end)
    card5:AddRow(limitRow, 28)
    card5:AddSeparator()

    -- Slider works in whole milliseconds (8–200 ms) and converts to seconds for the DB.
    local function MsFromDb() return math.floor((db.updateInterval or 0.02) * 1000 + 0.5) end
    local intervalRow = GUI:CreateSlider(parent, "Update Interval (ms)", 8, 200, 1,
        MsFromDb(),
        function(v) db.updateInterval = v / 1000; Cursor.Refresh() end)
    card5:AddRow(intervalRow, 44)

    y = y + card5:GetTotalHeight() + T.paddingSmall

    -- Initialise preview and child state with current DB values
    UpdatePreview()
    UpdateCursorChildState(db.enabled)

    -- SP_CursorCircle and SP_CursorClickCircle are parented to UIParent, so
    -- hiding the page container does NOT hide them automatically.
    -- Reset their state when navigating away, exactly like Durability does.
    parent:HookScript("OnHide", function()
        if SP.Cursor then SP.Cursor.Refresh() end
    end)

    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Copy Anything
-- ============================================================
GUI:RegisterContent("copytooltip", function(parent)
    local db = SP.GetDB().copyTooltip
    local y  = 0
    local aHex = GetAccentHex()

    -- Always use Ctrl as the modifier — no configuration needed
    db.modifier = "ctrl"

    -- ── Card 1: General ───────────────────────────────────
    local card1 = GUI:CreateCard(parent, "Copy Anything", y)
    card1:AddLabel(
        string.format("Hover any tooltip and press |cff%sCtrl+C|r to copy its ID into a dialog — ready to paste.", aHex),
        T.textMuted)
    card1:AddSeparator()
    card1:AddRow(GUI:CreateToggle(parent, "Enable Copy Anything",
        db.enabled,
        function(v)
            db.enabled = v
            if SP.CopyTooltip then SP.CopyTooltip.Refresh() end
        end, "Copy Anything"), 28)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- ── Card 3: Supported Types ───────────────────────────
    local card3 = GUI:CreateCard(parent, "Supported Types", y)
    card3:AddLabel("Spells — copies Spell ID", T.textMuted)
    card3:AddLabel("Items — copies Item ID", T.textMuted)
    card3:AddLabel("Units / NPCs — copies NPC ID or player name", T.textMuted)
    card3:AddLabel("Auras / Buffs / Debuffs — copies Aura ID", T.textMuted)
    card3:AddLabel("Macros — copies the underlying Spell or Item ID", T.textMuted)
    y = y + card3:GetTotalHeight() + T.paddingSmall

    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Filter Expansion Only
-- ============================================================
GUI:RegisterContent("filterexpansiononly", function(parent)
    local db = SP.GetDB().filterExpansionOnly
    local y  = 0

    local card1     -- forward-declared for UpdateChildState closure
    local enableRow -- forward-declared for GrayContent skip
    local function UpdateChildState(en)
        card1:GrayContent(en, enableRow)
    end

    card1 = GUI:CreateCard(parent, "Filter Expansion Only", y)
    card1:AddLabel(
        "Automatically applies the Current Expansion Only filter when opening the Auction House and the Crafting Orders browser — hiding items and orders from older expansions.",
        T.textMuted)
    card1:AddSeparator()
    enableRow = GUI:CreateToggle(parent, "Enable Filter Expansion Only", db.enabled,
        function(v)
            db.enabled = v
            UpdateChildState(v)
            if SP.FilterExpansionOnly then SP.FilterExpansionOnly.Refresh() end
        end, "Filter Expansion Only")
    card1:AddRow(enableRow, 28)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    UpdateChildState(db.enabled)
    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Fast Loot
-- ============================================================
GUI:RegisterContent("fastloot", function(parent)
    local db = SP.GetDB().fastLoot
    local y  = 0

    local card1 = GUI:CreateCard(parent, "Fast Loot", y)
    card1:AddLabel(
        "Improves the speed at which you loot containers and corpses.",
        T.textMuted)
    card1:AddSeparator()
    card1:AddRow(GUI:CreateToggle(parent, "Enable Fast Loot",
        db.enabled,
        function(v)
            db.enabled = v
            if SP.FastLoot then SP.FastLoot.Refresh() end
        end, "Fast Loot"), 28)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Repair Warning (Durability)
-- ============================================================
GUI:RegisterContent("durability", function(parent)
    local T  = SP.Theme
    local db = SP.GetDB().durability

    local function ApplySettings()
        if SP.Durability then SP.Durability.Refresh() end
    end

    local y            = 0
    local durChildRows  = {}
    local durChildCards = {}
    local enableRow
    local card1

    local function UpdateDurChildState(en)
        card1:GrayContent(en, enableRow)
        for _, r in ipairs(durChildRows)  do r:SetEnabled(en) end
        for _, c in ipairs(durChildCards) do c:SetAlpha(en and 1 or 0.4) end
    end

    -- ── Card 1: General ───────────────────────────────────────
    card1 = GUI:CreateCard(parent, "Repair Warning", y)
    card1:AddLabel(
        "Displays a warning text on screen when your gear durability drops below the configured threshold. Never shown during combat.",
        T.textMuted)
    card1:AddSeparator()

    enableRow = GUI:CreateToggle(parent, "Enable Repair Warning", db.enabled,
        function(v)
            db.enabled = v
            UpdateDurChildState(v)
            ApplySettings()
        end, "Repair Warning")
    card1:AddRow(enableRow, 28)
    card1:AddSeparator()

    -- Threshold slider
    local threshRow = GUI:CreateSlider(parent, "Warning Threshold (%)", 1, 100, 1,
        db.threshold or 30,
        function(v) db.threshold = v; ApplySettings() end)
    card1:AddRow(threshRow, 44)
    table.insert(durChildRows, threshRow)
    card1:AddSeparator()

    -- Warning Text editbox
    local wtLblFrame = CreateFrame("Frame", nil, parent)
    wtLblFrame:SetHeight(44)
    local wtLabel = wtLblFrame:CreateFontString(nil, "OVERLAY")
    wtLabel:SetPoint("TOPLEFT", wtLblFrame, "TOPLEFT", 0, -2)
    ApplyFont(wtLabel, 11)
    wtLabel:SetText("Warning Text")
    wtLabel:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    local wtBox = CreateFrame("EditBox", nil, wtLblFrame, "BackdropTemplate")
    wtBox:SetSize(200, 22)
    wtBox:SetPoint("TOPLEFT", wtLblFrame, "TOPLEFT", 0, -18)
    wtBox:SetAutoFocus(false)
    wtBox:SetMaxLetters(64)
    wtBox:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    wtBox:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    wtBox:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    wtBox:SetTextInsets(6, 6, 0, 0)
    ApplyFont(wtBox, 11)
    wtBox:SetText(db.warningText or "REPAIR NOW")
    wtBox:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
    wtBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        db.warningText = self:GetText()
        ApplySettings()
    end)
    wtBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        self:SetText(db.warningText or "REPAIR NOW")
    end)
    function wtLblFrame:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        wtBox:SetEnabled(en)
    end
    card1:AddRow(wtLblFrame, 44)
    table.insert(durChildRows, wtLblFrame)

    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- ── Card 2: Appearance ────────────────────────────────────
    local card2 = GUI:CreateCard(parent, "Appearance", y)
    table.insert(durChildCards, card2)
    card2:AddLabel("Customise the font, size, and colour of the warning text.", T.textMuted)
    card2:AddSeparator()

    -- Font Face
    local durFontFaceRow = GUI:CreateFontDropdown(parent, "Font Face",
        db.fontFace or "Expressway",
        function(v) db.fontFace = v; ApplySettings() end)
    card2:AddRow(durFontFaceRow, 44)
    table.insert(durChildRows, durFontFaceRow)
    card2:AddSeparator()

    -- Font Size + Outline side by side
    local durFontHRow = GUI:CreateHRow(parent, 44)
    local durFontSzRow = GUI:CreateSlider(parent, "Font Size", 8, 60, 1,
        db.fontSize or 20,
        function(v) db.fontSize = v; ApplySettings() end)
    local durOutlineRow = GUI:CreateDropdown(parent, "Outline",
        { "NONE", "OUTLINE", "THICKOUTLINE" },
        db.fontOutline or "OUTLINE",
        function(v) db.fontOutline = v; ApplySettings() end)
    durFontHRow:Add(durFontSzRow, 0.55)
    durFontHRow:Add(durOutlineRow, 0.45)
    card2:AddRow(durFontHRow, 44)
    table.insert(durChildRows, durFontHRow)

    -- Text Color with source
    card2:AddSeparator()
    local durColorSrcRow, durColorSwRow = GUI:CreateColorWithSource(
        parent, "Text Color", db, "colorSource", "color", { 1, 0.537, 0.2 },
        function() ApplySettings() end)
    card2:AddRow(durColorSrcRow, 44)
    table.insert(durChildRows, durColorSrcRow)
    card2:AddSeparator()
    card2:AddRow(durColorSwRow, 52)
    table.insert(durChildRows, durColorSwRow)

    y = y + card2:GetTotalHeight() + T.paddingSmall

    -- ── Card 3: Position ──────────────────────────────────────
    local card3 = GUI:CreateCard(parent, "Position", y)
    table.insert(durChildCards, card3)
    card3:AddLabel(
        "Click Preview to test the current look. Click Drag to Move to drag the frame anywhere on screen, then Lock Position when done. Fine-tune with the sliders below.",
        T.textMuted)
    card3:AddSeparator()

    local durAnchorRow, durAnchorRowH = GUI:CreateAnchorRow(parent, db, ApplySettings,
        { default = "HIGH", onChange = function() ApplySettings() end })
    card3:AddRow(durAnchorRow, durAnchorRowH)
    table.insert(durChildRows, durAnchorRow)
    card3:AddSeparator()

    -- X / Y offsets side by side
    local durXYHRow = GUI:CreateHRow(parent, 44)
    local durXRow = GUI:CreateSlider(parent, "X Offset", -2000, 2000, 1,
        db.x or 0,
        function(v) db.x = v; ApplySettings() end)
    local durYRow = GUI:CreateSlider(parent, "Y Offset", -2000, 2000, 1,
        db.y or -200,
        function(v) db.y = v; ApplySettings() end)
    durXYHRow:Add(durXRow, 0.5)
    durXYHRow:Add(durYRow, 0.5)
    card3:AddRow(durXYHRow, 44)
    table.insert(durChildRows, durXYHRow)

    -- Sync sliders when position updated via drag
    if SP.Durability then
        SP.Durability._syncSliders = function(nx, ny)
            if durXRow and durXRow.SetValue then durXRow.SetValue(nx) end
            if durYRow and durYRow.SetValue then durYRow.SetValue(ny) end
        end
    end

    card3:AddSeparator()

    -- Preview button (toggle)
    local function StyleDurBtn(btn, isActive)
        if isActive then
            btn:SetBackdropColor(T.accent[1], T.accent[2], T.accent[3], 0.25)
            btn.lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        else
            btn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
            btn.lbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        end
    end

    local durPreviewActive = false
    local durPrevWrap = CreateFrame("Frame", nil, parent)
    durPrevWrap:SetHeight(28)
    function durPrevWrap:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end

    local durPrevBtn = GUI:CreateButton(durPrevWrap, "Preview", nil, 140, 28)
    durPrevBtn:SetPoint("LEFT", durPrevWrap, "LEFT", 0, 0)

    local function UpdateDurPrevBtn()
        StyleDurBtn(durPrevBtn, durPreviewActive)
        durPrevBtn.lbl:SetText(durPreviewActive and "Stop Preview" or "Preview")
        AnimateBorderFocus(durPrevBtn, durPreviewActive)
    end

    durPrevBtn:SetScript("OnLeave", function() UpdateDurPrevBtn() end)
    durPrevBtn:SetScript("OnClick", function()
        durPreviewActive = not durPreviewActive
        if durPreviewActive then
            if SP.Durability then SP.Durability:ShowPreview() end
        else
            if SP.Durability then SP.Durability:HidePreview() end
        end
        UpdateDurPrevBtn()
    end)
    card3:AddRow(durPrevWrap, 28)
    table.insert(durChildRows, durPrevWrap)
    card3:AddSeparator()

    -- Drag to Move button
    local durDragActive = false
    local durDragWrap = CreateFrame("Frame", nil, parent)
    durDragWrap:SetHeight(28)
    function durDragWrap:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end

    local durDragBtn = GUI:CreateButton(durDragWrap, "Drag to Move", nil, 140, 28)
    durDragBtn:SetPoint("LEFT", durDragWrap, "LEFT", 0, 0)

    local function UpdateDurDragBtn()
        if durDragActive then
            durDragBtn.lbl:SetText("Lock Position")
            StyleDurBtn(durDragBtn, true)
        else
            durDragBtn.lbl:SetText("Drag to Move")
            StyleDurBtn(durDragBtn, false)
        end
        AnimateBorderFocus(durDragBtn, durDragActive)
    end

    durDragBtn:SetScript("OnLeave", function() UpdateDurDragBtn() end)
    durDragBtn:SetScript("OnClick", function()
        if durDragActive then
            durDragActive = false
            if SP.Durability then SP.Durability:EndDragMode() end
        else
            durDragActive = true
            if SP.Durability then SP.Durability:StartDragMode() end
        end
        UpdateDurDragBtn()
    end)
    card3:AddRow(durDragWrap, 28)
    table.insert(durChildRows, durDragWrap)

    y = y + card3:GetTotalHeight() + T.paddingSmall

    -- Initial state
    UpdateDurChildState(db.enabled)

    parent:SetHeight(y)
end)

-- ============================================================
-- Page: CVars
-- ============================================================
GUI:RegisterContent("cvars", function(parent)
    local db  = SP.GetDB().cvars
    local y   = 0
    local mod = SP.CVars

    local card1 = GUI:CreateCard(parent, "CVars", y)
    card1:AddLabel(
        "Game CVar tweaks applied on login. Changes take effect immediately.",
        T.textMuted)
    card1:AddSeparator()

    if mod and mod.DEFS then
        for i, def in ipairs(mod.DEFS) do
            local key = def.key
            -- Use current db value; nil → read from game
            local curVal = db[key]
            if curVal == nil then
                local raw = C_CVar and C_CVar.GetCVar(key)
                curVal = (raw == "1")
            end
            card1:AddRow(GUI:CreateToggle(parent, def.label, curVal,
                function(v) SP.CVars.SetCVar(key, v) end), 28)
            if i < #mod.DEFS then card1:AddSeparator() end
        end
    end

    y = y + card1:GetTotalHeight() + T.paddingSmall
    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Theme Selector
-- ============================================================
GUI:RegisterContent("themes", function(parent)
    local db            = SP.GetDB()
    local currentPreset = (db.settings and db.settings.theme and db.settings.theme.preset) or "Suspicion"
    local y             = 0

    local CELL_H   = 56
    local CELL_PAD = T.paddingSmall
    local COLS     = 2
    local presets  = SP.ThemePresetOrder

    local card = GUI:CreateCard(parent, "Theme Preset", y)
    card:AddLabel("Choose a colour theme for the addon interface.", T.textMuted)
    card:AddSeparator()

    for rowIdx = 1, math.ceil(#presets / COLS) do
        local rowFrame = CreateFrame("Frame", nil, parent)
        rowFrame:SetHeight(CELL_H)

        for colIdx = 1, COLS do
            local pIdx = (rowIdx - 1) * COLS + colIdx
            local name = presets[pIdx]
            if name then
                local p          = SP.ThemePresets[name]
                local isSelected = (name == currentPreset)

                local cell = CreateFrame("Button", nil, rowFrame, "BackdropTemplate")
                cell:SetHeight(CELL_H)

                -- 2-column layout using "CENTER" (valid WoW anchor = midpoint of rowFrame)
                -- col 1: LEFT edge to rowFrame LEFT, RIGHT edge to rowFrame CENTER minus half-pad
                -- col 2: LEFT edge to rowFrame CENTER plus half-pad, RIGHT edge to rowFrame RIGHT
                if colIdx == 1 then
                    cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT",  0, 0)
                    cell:SetPoint("RIGHT",   rowFrame, "CENTER",  -CELL_PAD / 2, 0)
                else
                    cell:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", 0, 0)
                    cell:SetPoint("LEFT",     rowFrame, "CENTER",   CELL_PAD / 2, 0)
                end

                local function ApplyCellBG(sel)
                    cell:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = T.borderSize })
                    if sel then
                        cell:SetBackdropColor(p.bgLight[1], p.bgLight[2], p.bgLight[3], 1)
                        cell:SetBackdropBorderColor(p.accent[1], p.accent[2], p.accent[3], 1)
                    else
                        cell:SetBackdropColor(p.bgMedium[1], p.bgMedium[2], p.bgMedium[3], 1)
                        cell:SetBackdropBorderColor(p.border[1], p.border[2], p.border[3], 1)
                    end
                end
                ApplyCellBG(isSelected)

                -- Colour swatch strip (bgDark / accent / bgLight)
                local swatchBar = CreateFrame("Frame", nil, cell)
                swatchBar:SetHeight(14)
                swatchBar:SetPoint("TOPLEFT",  cell, "TOPLEFT",  6, -6)
                swatchBar:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -6, -6)

                local sw1 = swatchBar:CreateTexture(nil, "ARTWORK")
                sw1:SetHeight(14)
                sw1:SetColorTexture(p.bgDark[1], p.bgDark[2], p.bgDark[3], 1)

                local sw2 = swatchBar:CreateTexture(nil, "ARTWORK")
                sw2:SetHeight(14)
                sw2:SetColorTexture(p.accent[1], p.accent[2], p.accent[3], 1)

                local sw3 = swatchBar:CreateTexture(nil, "ARTWORK")
                sw3:SetHeight(14)
                sw3:SetColorTexture(p.bgLight[1], p.bgLight[2], p.bgLight[3], 1)

                swatchBar:SetScript("OnSizeChanged", function(self, w)
                    sw1:ClearAllPoints()
                    sw1:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
                    sw1:SetWidth(math.max(1, w * 0.33))

                    sw2:ClearAllPoints()
                    sw2:SetPoint("TOPLEFT", self, "TOPLEFT", w * 0.33, 0)
                    sw2:SetWidth(math.max(1, w * 0.34))

                    sw3:ClearAllPoints()
                    sw3:SetPoint("TOPLEFT", self, "TOPLEFT", w * 0.67, 0)
                    sw3:SetWidth(math.max(1, w * 0.33))
                end)

                -- Preset name
                local nameLbl = cell:CreateFontString(nil, "OVERLAY")
                nameLbl:SetPoint("BOTTOMLEFT",  cell, "BOTTOMLEFT",  8, 8)
                nameLbl:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -8, 8)
                nameLbl:SetJustifyH("LEFT")
                ApplyFont(nameLbl, 12)
                nameLbl:SetText(name)
                nameLbl:SetTextColor(p.textPrimary[1], p.textPrimary[2], p.textPrimary[3], 1)

                -- Selected indicator dot — SetColorTexture writes accent directly, no texture tinting issues
                if isSelected then
                    local tick = cell:CreateTexture(nil, "OVERLAY")
                    tick:SetSize(8, 8)
                    tick:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -8, 8)
                    tick:SetTexture(BLANK)
                    tick:SetColorTexture(T.accent[1], T.accent[2], T.accent[3], 1)
                end

                cell:SetScript("OnEnter", function()
                    if not isSelected then
                        cell:SetBackdropColor(p.bgLight[1], p.bgLight[2], p.bgLight[3], 1)
                        cell:SetBackdropBorderColor(p.accent[1], p.accent[2], p.accent[3], 0.5)
                    end
                end)
                cell:SetScript("OnLeave", function() ApplyCellBG(isSelected) end)
                cell:SetScript("OnClick", function()
                    if not db.settings       then db.settings       = {} end
                    if not db.settings.theme then db.settings.theme = {} end
                    db.settings.theme.preset = name
                    SP.RefreshTheme()
                end)
            end
        end

        card:AddRow(rowFrame, CELL_H, T.paddingSmall)
    end

    y = y + card:GetTotalHeight() + T.paddingSmall
    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Automation
-- ============================================================
GUI:RegisterContent("automation", function(parent)
    local db = SP.GetDB().automation
    local y  = 0

    local card = GUI:CreateCard(parent, "Automation", y)
    card:AddLabel("Auto-accept various dialogs and popups, sell junk and repair at merchants.", T.textMuted)
    card:AddSeparator()

    -- Track child rows and their description labels for unified enable/disable dimming.
    -- r9 / r9Desc are declared later but captured by reference (Lua upvalue), so the
    -- sub-dependency check inside UpdateChildState sees their final assigned value.
    local childRows   = {}
    local childLabels = {}
    local r9, r9Desc  -- forward-declared so UpdateChildState can reference them
    local enableRow   -- forward-declared; used in UpdateChildState closure
    local function UpdateChildState(enabled)
        card:GrayContent(enabled, enableRow)
        for _, row in ipairs(childRows) do
            row:SetEnabled(enabled)
        end
        for _, lbl in ipairs(childLabels) do
            lbl:SetAlpha(enabled and 1 or 0.4)
        end
        -- Use Guild Funds is a sub-option of Auto Repair: keep it grayed
        -- whenever the master is off OR Auto Repair itself is off.
        if r9 and r9Desc then
            local r9En = enabled and db.autoRepair
            r9:SetEnabled(r9En)
            r9Desc:SetAlpha(r9En and 1 or 0.4)
        end
    end

    local function AddDesc(text)
        local lbl = card:AddLabel(text, T.textMuted)
        table.insert(childLabels, lbl)
        card:AddSpacing(2)
        return lbl
    end

    enableRow = GUI:CreateToggle(parent, "Enable Automation", db.enabled,
        function(v)
            db.enabled = v
            UpdateChildState(v)
            if SP.Automation then SP.Automation:Refresh() end
        end, "Automation")
    card:AddRow(enableRow, 28)
    card:AddSeparator()

    -- ── Dialogs & Popups ──────────────────────────────────────

    -- Auto Fill Delete uses hooksecurefunc — permanent, irreversible hook.
    -- Disabling requires a UI reload to take effect.
    local r1 = GUI:CreateToggle(parent, "Auto Fill Delete", db.autoFillDelete,
        function(v)
            db.autoFillDelete = v
            if SP.Automation then SP.Automation:Refresh() end
            if not v then
                SP.CreateReloadPrompt("Disabling Auto Fill Delete requires a reload to take full effect.")
            end
        end)
    card:AddRow(r1, 28); table.insert(childRows, r1)
    AddDesc("Types 'DELETE' automatically when destroying a good item, skipping manual confirmation.")

    local r5 = GUI:CreateToggle(parent, "Skip Cinematics", db.skipCinematics,
        function(v) db.skipCinematics = v; if SP.Automation then SP.Automation:Refresh() end end)
    card:AddRow(r5, 28); table.insert(childRows, r5)
    AddDesc("Immediately cancels in-game cutscenes and movies when they start.")

    local r6 = GUI:CreateToggle(parent, "Hide Talking Head", db.hideTalkingHead,
        function(v) db.hideTalkingHead = v; if SP.Automation then SP.Automation:Refresh() end end)
    card:AddRow(r6, 28); table.insert(childRows, r6)
    AddDesc("Hides the talking head popup that appears at the bottom of the screen during quests.")

    local r6c = GUI:CreateToggle(parent, "Hide Bags Bar", db.hideBagsBar,
        function(v) db.hideBagsBar = v; if SP.Automation then SP.Automation:Refresh() end end)
    card:AddRow(r6c, 28); table.insert(childRows, r6c)
    AddDesc("Hides the bags bar (backpack buttons) from the main action bar.")

    local dbPerf = SP.GetDB().performance
    local r6b = GUI:CreateToggle(parent, "Hide Screenshot Notification", dbPerf and dbPerf.hideScreenshotMsg or false,
        function(v)
            local p = SP.GetDB().performance
            if p then p.hideScreenshotMsg = v end
            if SP.Performance then SP.Performance.Refresh() end
        end)
    card:AddRow(r6b, 28); table.insert(childRows, r6b)
    AddDesc("Suppresses the \"Screenshot saved\" message.")

    card:AddSeparator()

    -- ── Merchant ──────────────────────────────────────────────

    local r7 = GUI:CreateToggle(parent, "Auto Sell Junk", db.autoSellJunk,
        function(v) db.autoSellJunk = v; if SP.Automation then SP.Automation:Refresh() end end)
    card:AddRow(r7, 28); table.insert(childRows, r7)
    AddDesc("Automatically sells all grey (poor quality) items in your bags when you open a merchant.")

    local r8 = GUI:CreateToggle(parent, "Auto Repair", db.autoRepair,
        function(v)
            db.autoRepair = v
            -- Use Guild Funds only makes sense when Auto Repair is on
            if r9 then r9:SetEnabled(db.enabled and v) end
            if r9Desc then r9Desc:SetAlpha(db.enabled and v and 1 or 0.4) end
            if SP.Automation then SP.Automation:Refresh() end
        end)
    card:AddRow(r8, 28); table.insert(childRows, r8)
    AddDesc("Automatically repairs all your gear when you open a merchant that offers repairs.")

    r9 = GUI:CreateToggle(parent, "Use Guild Funds", db.useGuildFunds,
        function(v) db.useGuildFunds = v; if SP.Automation then SP.Automation:Refresh() end end)
    card:AddRow(r9, 28); table.insert(childRows, r9)
    r9Desc = AddDesc("Uses the guild bank to pay for auto-repairs instead of your own gold (requires sufficient guild bank access).")

    local r10 = GUI:CreateToggle(parent, "Auto Accept Decor Prompt", db.autoDecorVendor,
        function(v) db.autoDecorVendor = v; if SP.Automation then SP.Automation:Refresh() end end)
    card:AddRow(r10, 28); table.insert(childRows, r10)
    AddDesc("Automatically confirms the purchase prompt when buying decoration items from a vendor.")

    card:AddSeparator()

    -- ── Druid ─────────────────────────────────────────────────

    local r11 = GUI:CreateToggle(parent, "Auto Switch to Flight Form", db.autoSwitchFlight,
        function(v) db.autoSwitchFlight = v; if SP.Automation then SP.Automation:Refresh() end end)
    card:AddRow(r11, 28); table.insert(childRows, r11)
    AddDesc("Druid only. Cancels ground Travel Form automatically when flying is allowed so you can take off straight away.")

    -- Apply initial state (also handles the Auto Repair → Use Guild Funds dependency)
    UpdateChildState(db.enabled)

    y = y + card:GetTotalHeight() + T.paddingSmall

    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Group Invitations
-- ============================================================
GUI:RegisterContent("invitationgroupe", function(parent)
    local db    = SP.GetDB().autoInvite
    local dbAut = SP.GetDB().automation
    local y     = 0

    local function KeywordsToStr(kws)
        return table.concat(kws or {}, ", ")
    end
    local function StrToKeywords(str)
        local kws = {}
        for part in str:gmatch("[^,]+") do
            local kw = part:match("^%s*(.-)%s*$")
            if kw ~= "" then table.insert(kws, kw) end
        end
        return kws
    end

    local aiChildRows = {}
    local enableRow   -- forward-declared; used in UpdateAIChildState closure
    local card        -- forward-declared for UpdateAIChildState closure
    local function UpdateAIChildState(en)
        card:GrayContent(en, enableRow)
        for _, r in ipairs(aiChildRows) do r:SetEnabled(en) end
    end

    -- ── Card 1: Auto Invite (keyword-based) ──────────────────
    card = GUI:CreateCard(parent, "Auto Invite", y)
    card:AddLabel(
        "Automatically invites players who whisper a keyword. Only activates when you are group leader or alone. Can invite anyone, or restrict to friends and/or guild members.",
        T.textMuted)
    card:AddSeparator()

    enableRow = GUI:CreateToggle(parent, "Enable Auto Invite", db.enabled,
        function(v)
            db.enabled = v
            if SP.AutoInvite then SP.AutoInvite.Refresh() end
            UpdateAIChildState(v)
        end, "Group Invitations")
    card:AddRow(enableRow, 28)
    card:AddSeparator()

    -- Declare upfront so allRow's callback can reference them before they're assigned
    local friendRow, guildRow

    local allRow = GUI:CreateToggle(parent, "Invite Anyone",
        db.inviteAll,
        function(v)
            db.inviteAll = v
            if friendRow then friendRow:SetEnabled(not v) end
            if guildRow  then guildRow:SetEnabled(not v)  end
        end)
    card:AddRow(allRow, 28)
    table.insert(aiChildRows, allRow)

    friendRow = GUI:CreateToggle(parent, "Invite Friends",
        db.inviteFriends,
        function(v) db.inviteFriends = v end)
    card:AddRow(friendRow, 28)
    table.insert(aiChildRows, friendRow)

    guildRow = GUI:CreateToggle(parent, "Invite Guild Members",
        db.inviteGuild,
        function(v) db.inviteGuild = v end)
    card:AddRow(guildRow, 28)
    table.insert(aiChildRows, guildRow)

    -- Reflect initial state: if inviteAll is on, friends/guild rows are greyed out
    if db.inviteAll then
        friendRow:SetEnabled(false)
        guildRow:SetEnabled(false)
    end
    card:AddSeparator()

    -- Keywords editbox row (stacked: label on top, box below on the left)
    local kwRow = CreateFrame("Frame", nil, parent)
    kwRow:SetHeight(44)
    local kwLbl = kwRow:CreateFontString(nil, "OVERLAY")
    kwLbl:SetPoint("TOPLEFT", kwRow, "TOPLEFT", 0, -2)
    ApplyFont(kwLbl, 11)
    kwLbl:SetText("Keywords")
    kwLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    local kwBox = CreateFrame("EditBox", nil, kwRow, "BackdropTemplate")
    kwBox:SetSize(180, 22)
    kwBox:SetPoint("TOPLEFT", kwRow, "TOPLEFT", 0, -18)
    kwBox:SetAutoFocus(false); kwBox:SetMaxLetters(128)
    kwBox:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    kwBox:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    kwBox:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    kwBox:SetTextInsets(6, 6, 0, 0)
    ApplyFont(kwBox, 11)
    kwBox:SetText(KeywordsToStr(db.keywords))
    kwBox:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
    kwBox:SetScript("OnEnterPressed", function(self)
        db.keywords = StrToKeywords(self:GetText())
        self:SetText(KeywordsToStr(db.keywords))
        self:ClearFocus()
    end)
    kwBox:SetScript("OnEscapePressed", function(self)
        self:SetText(KeywordsToStr(db.keywords))
        self:ClearFocus()
    end)
    function kwRow:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        kwBox:SetEnabled(en)
    end
    card:AddRow(kwRow, 44)
    table.insert(aiChildRows, kwRow)
    card:AddLabel("Comma-separated. Exact match, case-insensitive. Press Enter to save.", T.textMuted)

    UpdateAIChildState(db.enabled)
    y = y + card:GetTotalHeight() + T.paddingSmall

    -- ── Card 2: Auto Accept ───────────────────────────────────
    local card2 = GUI:CreateCard(parent, "Auto Accept", y)
    card2:AddLabel(
        "Automatically accepts group invitations and role check popups.",
        T.textMuted)
    card2:AddSeparator()

    local rRole = GUI:CreateToggle(parent, "Auto Role Check", dbAut.autoRoleCheck,
        function(v)
            dbAut.autoRoleCheck = v
            if SP.Automation then SP.Automation:Refresh() end
            if not v then
                SP.CreateReloadPrompt("Disabling Auto Role Check requires a reload to take full effect.")
            end
        end)
    card2:AddRow(rRole, 28)
    card2:AddLabel("Instantly accepts LFD and LFG role check popups the moment they appear.", T.textMuted)

    local rGuild = GUI:CreateToggle(parent, "Auto Guild Invite", dbAut.autoGuildInvite,
        function(v) dbAut.autoGuildInvite = v; if SP.Automation then SP.Automation:Refresh() end end)
    card2:AddRow(rGuild, 28)
    card2:AddLabel("Automatically accepts group invitations received from your guildmates.", T.textMuted)

    local rFriend = GUI:CreateToggle(parent, "Auto Friend Invite", dbAut.autoFriendInvite,
        function(v) dbAut.autoFriendInvite = v; if SP.Automation then SP.Automation:Refresh() end end)
    card2:AddRow(rFriend, 28)
    card2:AddLabel("Automatically accepts group invitations received from your friends.", T.textMuted)

    y = y + card2:GetTotalHeight() + T.paddingSmall

    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Combat Timer
-- ============================================================
GUI:RegisterContent("combattimer", function(parent)
    local db = SP.GetDB().combatTimer
    local y  = 0

    local function GetCT() return SP.CombatTimer end
    local function ApplySettings()
        local ct = GetCT()
        if ct and ct.ApplySettings then ct:ApplySettings() end
    end

    -- ── Card 1: General ───────────────────────────────────
    local card1 = GUI:CreateCard(parent, "Combat Timer", y)
    card1:AddLabel("Displays a running timer during combat.", T.textMuted)
    card1:AddSeparator()

    local ctChildRows  = {}
    local ctChildCards = {}
    local ctEnableRow  -- forward-declared; used in UpdateCTChildState closure
    local function UpdateCTChildState(en)
        card1:GrayContent(en, ctEnableRow)
        for _, r in ipairs(ctChildRows)  do r:SetEnabled(en) end
        for _, c in ipairs(ctChildCards) do c:SetAlpha(en and 1 or 0.4) end
    end

    ctEnableRow = GUI:CreateToggle(parent, "Enable Combat Timer",
        db.enabled,
        function(v)
            db.enabled = v
            UpdateCTChildState(v)
            local ct = GetCT()
            if ct then
                if v then ct:Activate() else ct:Deactivate() end
            end
        end, "Combat Timer")
    card1:AddRow(ctEnableRow, 28)
    card1:AddSeparator()

    local formatRow = GUI:CreateDropdown(parent, "Format",
        { "MM:SS", "MM:SS:MS" },
        db.format or "MM:SS",
        function(v) db.format = v; ApplySettings() end)
    card1:AddRow(formatRow, 44)
    table.insert(ctChildRows, formatRow)

    local printRow = GUI:CreateToggle(parent, "Print duration to chat",
        db.printToChat ~= false,
        function(v) db.printToChat = v end)
    card1:AddRow(printRow, 28)
    table.insert(ctChildRows, printRow)

    local showLastRow = GUI:CreateToggle(parent, "Show last duration on frame",
        db.showLastDuration or false,
        function(v)
            db.showLastDuration = v
            local ct = GetCT()
            if not ct or not ct.frame then return end
            if v then
                ct.frame:Show()
            elseif not ct.running then
                ct.frame:Hide()
            end
        end)
    card1:AddRow(showLastRow, 28)
    table.insert(ctChildRows, showLastRow)

    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- ── Card 2: Position / Anchor ─────────────────────────
    local card2 = GUI:CreateCard(parent, "Position", y)
    card2:AddLabel("Set where the timer appears on screen.", T.textMuted)
    card2:AddSeparator()
    table.insert(ctChildCards, card2)

    local ctAnchorRow, ctAnchorRowH = GUI:CreateAnchorRow(parent, db, ApplySettings,
        { default = "TOOLTIP", onChange = function() ApplySettings() end })
    card2:AddRow(ctAnchorRow, ctAnchorRowH)
    card2:AddSeparator()

    local ctXRow = GUI:CreateSlider(parent, "X Offset", -2000, 2000, 1, db.x or 0,
        function(v) db.x = v; ApplySettings() end)
    local ctYRow = GUI:CreateSlider(parent, "Y Offset", -2000, 2000, 1, db.y or 250,
        function(v) db.y = v; ApplySettings() end)
    local ctXYRow = GUI:CreateHRow(parent, 44)
    ctXYRow:Add(ctXRow, 0.5)
    ctXYRow:Add(ctYRow, 0.5)
    card2:AddRow(ctXYRow, 44)

    -- Preview button — fixed 120px, bgMedium default, border-only hover animation
    local previewActive = false
    local previewWrap = CreateFrame("Frame", nil, parent)
    previewWrap:SetHeight(28)
    local previewBtn = GUI:CreateButton(previewWrap, "Preview", nil, 140, 28)
    previewBtn:SetPoint("LEFT", previewWrap, "LEFT", 0, 0)
    previewBtn:SetScript("OnLeave", function()
        AnimateBorderFocus(previewBtn, previewActive)
        previewBtn.lbl:SetTextColor(
            previewActive and T.accent[1] or T.textPrimary[1],
            previewActive and T.accent[2] or T.textPrimary[2],
            previewActive and T.accent[3] or T.textPrimary[3], 1)
    end)
    previewBtn:SetScript("OnClick", function()
        local ct = GetCT()
        if not ct then return end
        previewActive = not previewActive
        if previewActive then
            ct:ShowPreview()
            -- Tint the MOVABLE label with theme accent (T is in scope here)
            if ct.frame and ct.frame.movableLbl then
                ct.frame.movableLbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
            end
            previewBtn.lbl:SetText("Stop Preview")
            previewBtn.lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        else
            ct:HidePreview()
            previewBtn.lbl:SetText("Preview")
            previewBtn.lbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        end
    end)
    card2:AddRow(previewWrap, 28)
    y = y + card2:GetTotalHeight() + T.paddingSmall

    -- ── Card 3: Font ──────────────────────────────────────
    local card3 = GUI:CreateCard(parent, "Font", y)
    card3:AddLabel("Choose the typeface, outline, and size for the timer text.", T.textMuted)
    card3:AddSeparator()
    -- Font Face + Outline share the same row (NorskenUI-style)
    local fontFaceHRow = GUI:CreateHRow(parent, 44)
    local ddFontFace = GUI:CreateFontDropdown(parent, "Font Face",
        db.fontFace or "Expressway",
        function(v) db.fontFace = v; ApplySettings() end)
    local ddOutline = GUI:CreateDropdown(parent, "Outline",
        { "NONE", "OUTLINE", "THICKOUTLINE", "SOFTOUTLINE" },
        db.outline or "SOFTOUTLINE",
        function(v) db.outline = v; ApplySettings() end)
    fontFaceHRow:Add(ddFontFace, 0.6)
    fontFaceHRow:Add(ddOutline, 0.4)
    card3:AddRow(fontFaceHRow, 44)
    card3:AddSeparator()
    card3:AddRow(GUI:CreateSlider(parent, "Font Size", 8, 60, 1, db.fontSize or 18,
        function(v) db.fontSize = v; ApplySettings() end), 44)
    table.insert(ctChildCards, card3)
    y = y + card3:GetTotalHeight() + T.paddingSmall

    -- ── Card: Font Shadow ─────────────────────────────────
    local cardShadow = GUI:CreateCard(parent, "Font Shadow", y)
    cardShadow:AddLabel("Add a drop shadow to the timer text for better readability.", T.textMuted)
    cardShadow:AddSeparator()
    cardShadow:AddRow(GUI:CreateToggle(parent, "Enable Font Shadow",
        db.shadowEnabled,
        function(v) db.shadowEnabled = v; ApplySettings() end), 28)
    cardShadow:AddSeparator()
    local ctShadowSrcRow, ctShadowSwRow = GUI:CreateColorWithSource(
        parent, "Shadow Color", db, "shadowColorSource", "shadowColor", { 0, 0, 0 },
        function() ApplySettings() end)
    cardShadow:AddRow(ctShadowSrcRow, 44)
    cardShadow:AddSeparator()
    cardShadow:AddRow(ctShadowSwRow, 52)
    cardShadow:AddSeparator()
    -- Shadow X + Shadow Y on the same row
    local shadowXYRow = GUI:CreateHRow(parent, 44)
    local slShadowX = GUI:CreateSlider(parent, "Shadow X", -5, 5, 1, db.shadowX or 1,
        function(v) db.shadowX = v; ApplySettings() end)
    local slShadowY = GUI:CreateSlider(parent, "Shadow Y", -5, 5, 1, db.shadowY or -1,
        function(v) db.shadowY = v; ApplySettings() end)
    shadowXYRow:Add(slShadowX, 0.5)
    shadowXYRow:Add(slShadowY, 0.5)
    cardShadow:AddRow(shadowXYRow, 44)
    table.insert(ctChildCards, cardShadow)
    y = y + cardShadow:GetTotalHeight() + T.paddingSmall

    -- ── Card 4: Colors ────────────────────────────────────
    local card4 = GUI:CreateCard(parent, "Colors", y)
    card4:AddLabel("Colour the timer text differently in and out of combat.", T.textMuted)
    card4:AddSeparator()
    local ctInSrcRow, ctInSwRow = GUI:CreateColorWithSource(
        parent, "In Combat Color", db, "colorInCombatSource", "colorInCombat", { 1, 0.2, 0.2 },
        function() ApplySettings() end)
    card4:AddRow(ctInSrcRow, 44)
    card4:AddSeparator()
    card4:AddRow(ctInSwRow, 52)
    card4:AddSeparator()
    local ctOutSrcRow, ctOutSwRow = GUI:CreateColorWithSource(
        parent, "Out of Combat Color", db, "colorOutOfCombatSource", "colorOutOfCombat", { 1, 1, 1 },
        function() ApplySettings() end)
    card4:AddRow(ctOutSrcRow, 44)
    card4:AddSeparator()
    card4:AddRow(ctOutSwRow, 52)
    table.insert(ctChildCards, card4)
    y = y + card4:GetTotalHeight() + T.paddingSmall

    -- ── Card 5: Backdrop ──────────────────────────────────
    local bd = db.backdrop or {}
    local card5 = GUI:CreateCard(parent, "Backdrop", y)
    card5:AddLabel("Configure the background panel behind the timer.", T.textMuted)
    card5:AddSeparator()
    card5:AddRow(GUI:CreateToggle(parent, "Enable Backdrop",
        bd.enabled,
        function(v)
            db.backdrop.enabled = v
            ApplySettings()
        end), 28)
    card5:AddSeparator()
    -- Border Size + Padding W + Padding H on one row
    local bdSizePadRow = GUI:CreateHRow(parent, 44)
    local slBorderSize = GUI:CreateSlider(parent, "Border Size", 1, 10, 1, bd.borderSize or 1,
        function(v) db.backdrop.borderSize = v; ApplySettings() end)
    local slPadW = GUI:CreateSlider(parent, "Pad W", 0, 40, 1, bd.paddingW or 10,
        function(v) db.backdrop.paddingW = v; ApplySettings() end)
    local slPadH = GUI:CreateSlider(parent, "Pad H", 0, 40, 1, bd.paddingH or 6,
        function(v) db.backdrop.paddingH = v; ApplySettings() end)
    bdSizePadRow:Add(slBorderSize, 0.34)
    bdSizePadRow:Add(slPadW, 0.33)
    bdSizePadRow:Add(slPadH, 0.33)
    card5:AddRow(bdSizePadRow, 44)
    card5:AddSeparator()
    -- Background Color + Border Color side by side
    local bc = bd.color       or { 0, 0, 0 }
    local bb = bd.borderColor or { 0, 0, 0 }
    card5:AddRow(GUI:CreateDualColorRow(parent,
        "Background Color", bc[1], bc[2], bc[3],
        function(r, g, b) db.backdrop.color = { r, g, b, 0.6 }; ApplySettings() end,
        "Border Color", bb[1], bb[2], bb[3],
        function(r, g, b) db.backdrop.borderColor = { r, g, b, 1 }; ApplySettings() end
    ), 52)
    table.insert(ctChildCards, card5)
    y = y + card5:GetTotalHeight() + T.paddingSmall

    -- Apply initial state
    UpdateCTChildState(db.enabled)

    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Movement Alert
-- ============================================================
GUI:RegisterContent("movementalert", function(parent)
    local db = SP.GetDB().movementAlert
    local y  = 0

    local function GetMA() return SP.MovementAlert end
    local function Refresh()
        local ma = GetMA()
        if ma then ma:Refresh() end
    end

    local maChildRows  = {}
    local maChildCards = {}
    local maEnableRow  -- forward-declared; used in UpdateChildState closure
    local card1        -- forward-declared for UpdateChildState closure
    local function UpdateChildState(en)
        card1:GrayContent(en, maEnableRow)
        for _, r in ipairs(maChildRows)  do r:SetEnabled(en) end
        for _, c in ipairs(maChildCards) do c:SetAlpha(en and 1 or 0.4) end
    end

    -- ── Card 1: General ───────────────────────────────────
    card1 = GUI:CreateCard(parent, "Movement Alert", y)
    card1:AddLabel("Shows a cooldown when your movement ability is on CD.", T.textMuted)
    card1:AddSeparator()

    maEnableRow = GUI:CreateToggle(parent, "Enable Movement Alert",
        db.enabled,
        function(v)
            db.enabled = v
            UpdateChildState(v)
            Refresh()
        end, "Movement Alert")
    card1:AddRow(maEnableRow, 28)
    card1:AddSeparator()

    local precRow = GUI:CreateSlider(parent, "Decimal Precision", 0, 1, 1,
        db.precision or 0,
        function(v) db.precision = v end)
    local intervalRow = GUI:CreateSlider(parent, "Update Interval (ms)", 50, 500, 10,
        math.floor((db.updateInterval or 0.1) * 1000 + 0.5),
        function(v) db.updateInterval = v / 1000 end)
    local precIntervalRow = GUI:CreateHRow(parent, 44)
    precIntervalRow:Add(precRow, 0.5)
    precIntervalRow:Add(intervalRow, 0.5)
    card1:AddRow(precIntervalRow, 44)
    table.insert(maChildRows, precIntervalRow)

    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- ── Card: Tracked Spells ──────────────────────────────
    -- Built dynamically from the current player's class.
    -- Each spell gets a toggle; unchecking disables it from tracking.
    do
        local _, playerClass = UnitClass("player")
        local ma = SP.MovementAlert
        local byClass = ma and ma.MovementAbilities and ma.MovementAbilities[playerClass]

        if byClass then
            -- Collect unique spell IDs (sorted, deduplicated)
            local seen   = {}
            local unique = {}
            for _, spells in pairs(byClass) do
                for _, sid in ipairs(spells) do
                    if not seen[sid] then
                        seen[sid] = true
                        unique[#unique + 1] = sid
                    end
                end
            end
            table.sort(unique)

            if #unique > 0 then
                local cardSpells = GUI:CreateCard(parent, "Tracked Spells", y)
                cardSpells:AddLabel("Choose which abilities this module tracks for your class.", T.textMuted)
                cardSpells:AddSeparator()
                table.insert(maChildCards, cardSpells)

                if not db.disabledSpells then db.disabledSpells = {} end

                for _, sid in ipairs(unique) do
                    local info   = C_Spell.GetSpellInfo(sid)
                    local sName  = info and info.name or ("Spell " .. sid)
                    local iconID = info and info.iconID
                    local label  = iconID
                        and ("|T" .. iconID .. ":16:16|t  " .. sName)
                        or sName

                    local spellRow = GUI:CreateToggle(parent, label,
                        not db.disabledSpells[sid],
                        function(v)
                            if v then
                                db.disabledSpells[sid] = nil
                            else
                                db.disabledSpells[sid] = true
                            end
                            Refresh()
                        end)
                    cardSpells:AddRow(spellRow, 28)
                    table.insert(maChildRows, spellRow)
                end

                y = y + cardSpells:GetTotalHeight() + T.paddingSmall
            end
        end
    end

    -- ── Card 2: Position ──────────────────────────────────
    local card2 = GUI:CreateCard(parent, "Position", y)
    card2:AddLabel("Click Preview to see the text on screen. Drag it anywhere, then fine-tune with the sliders.", T.textMuted)
    card2:AddSeparator()
    table.insert(maChildCards, card2)

    -- Anchor row (strata + anchor from/to/frame)
    local maAnchorRow, maAnchorRowH = GUI:CreateAnchorRow(parent, db, Refresh,
        { default = "MEDIUM", onChange = function() Refresh() end })
    card2:AddRow(maAnchorRow, maAnchorRowH)
    table.insert(maChildRows, maAnchorRow)
    card2:AddSeparator()

    -- X / Y side by side
    local maXYRow = GUI:CreateHRow(parent, 44)
    local slX = GUI:CreateSlider(parent, "X Offset", -2000, 2000, 1, db.x or 0,
        function(v) db.x = v; Refresh() end)
    local slY = GUI:CreateSlider(parent, "Y Offset", -2000, 2000, 1, db.y or 300,
        function(v) db.y = v; Refresh() end)
    maXYRow:Add(slX, 0.5)
    maXYRow:Add(slY, 0.5)
    card2:AddRow(maXYRow, 44)
    table.insert(maChildRows, maXYRow)
    card2:AddSeparator()

    -- Preview button (toggle: shows frame + enables drag)
    local previewActive = false
    local previewWrap = CreateFrame("Frame", nil, parent)
    previewWrap:SetHeight(28)
    function previewWrap:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end
    local previewBtn = GUI:CreateButton(previewWrap, "Preview", nil, 140, 28)
    previewBtn:SetPoint("LEFT", previewWrap, "LEFT", 0, 0)
    previewBtn:SetScript("OnLeave", function()
        AnimateBorderFocus(previewBtn, previewActive)
        previewBtn.lbl:SetTextColor(
            previewActive and T.accent[1] or T.textPrimary[1],
            previewActive and T.accent[2] or T.textPrimary[2],
            previewActive and T.accent[3] or T.textPrimary[3], 1)
    end)
    previewBtn:SetScript("OnClick", function()
        local ma = SP.MovementAlert
        if not ma then return end
        previewActive = not previewActive
        if previewActive then
            ma:ShowPreview()
            if ma.frame and ma.frame.movableLbl then
                ma.frame.movableLbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
            end
            previewBtn.lbl:SetText("Stop Preview")
            previewBtn.lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        else
            ma:HidePreview()
            previewBtn.lbl:SetText("Preview")
            previewBtn.lbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        end
        AnimateBorderFocus(previewBtn, previewActive)
    end)
    card2:AddRow(previewWrap, 28)
    table.insert(maChildRows, previewWrap)

    -- Sync sliders when frame is dragged
    local ma = SP.MovementAlert
    if ma then
        ma._syncSliders = function(nx, ny)
            if slX and slX.SetValue then slX.SetValue(nx) end
            if slY and slY.SetValue then slY.SetValue(ny) end
        end
        -- Reset button label when the 5 s auto-cancel fires
        ma._maPreviewEndCallback = function()
            previewActive = false
            previewBtn.lbl:SetText("Preview")
            previewBtn.lbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
            AnimateBorderFocus(previewBtn, false)
        end
    end

    y = y + card2:GetTotalHeight() + T.paddingSmall

    -- ── Card 3: Font ──────────────────────────────────────
    local card3 = GUI:CreateCard(parent, "Font", y)
    card3:AddLabel("Typeface and size of the cooldown text.", T.textMuted)
    card3:AddSeparator()
    table.insert(maChildCards, card3)

    local fontHRow = GUI:CreateHRow(parent, 44)
    local ddFontFace = GUI:CreateFontDropdown(parent, "Font Face",
        db.fontFace or "Expressway",
        function(v) db.fontFace = v; Refresh() end)
    local ddOutline = GUI:CreateDropdown(parent, "Outline",
        { "NONE", "OUTLINE", "THICKOUTLINE", "SOFTOUTLINE" },
        db.outline or "OUTLINE",
        function(v) db.outline = v; Refresh() end)
    fontHRow:Add(ddFontFace, 0.6)
    fontHRow:Add(ddOutline, 0.4)
    card3:AddRow(fontHRow, 44)
    card3:AddSeparator()
    card3:AddRow(GUI:CreateSlider(parent, "Font Size", 8, 60, 1, db.fontSize or 14,
        function(v) db.fontSize = v; Refresh() end), 44)
    card3:AddSeparator()

    -- Text color
    local maTxtSrcRow, maTxtSwRow = GUI:CreateColorWithSource(
        parent, "Text Color", db, "colorSource", "color", { 1, 1, 1 },
        function() Refresh() end)
    card3:AddRow(maTxtSrcRow, 44)
    card3:AddSeparator()
    card3:AddRow(maTxtSwRow, 52)

    y = y + card3:GetTotalHeight() + T.paddingSmall

    -- ── Card 4: Time Spiral ───────────────────────────────
    local card4 = GUI:CreateCard(parent, "Time Spiral", y)
    card4:AddLabel("Shows a free-movement countdown when triggered by a glow overlay.", T.textMuted)
    card4:AddSeparator()
    table.insert(maChildCards, card4)

    local tsRows      = {}
    local tsSoundRows = {}

    local function UpdateTSSoundState(en)
        for _, r in ipairs(tsSoundRows) do r:SetEnabled(en) end
    end
    local function UpdateTSChildState(en)
        for _, r in ipairs(tsRows) do r:SetEnabled(en) end
        if en then UpdateTSSoundState(db.timeSpiralPlaySound) end
    end

    local tsEnableRow = GUI:CreateToggle(parent, "Enable Time Spiral",
        db.showTimeSpiral ~= false,
        function(v)
            db.showTimeSpiral = v
            UpdateTSChildState(v)
        end)
    card4:AddRow(tsEnableRow, 28)
    card4:AddSeparator()

    -- ── Display text editbox ──────────────────────────────
    local tsLabelRow = CreateFrame("Frame", nil, parent)
    tsLabelRow:SetHeight(44)
    local tsLabelHdr = tsLabelRow:CreateFontString(nil, "OVERLAY")
    tsLabelHdr:SetPoint("TOPLEFT", tsLabelRow, "TOPLEFT", 0, -2)
    ApplyFont(tsLabelHdr, 11)
    tsLabelHdr:SetText("Display Text")
    tsLabelHdr:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    local tsLabelBox = CreateFrame("EditBox", nil, tsLabelRow, "BackdropTemplate")
    tsLabelBox:SetSize(180, 22)
    tsLabelBox:SetPoint("TOPLEFT", tsLabelRow, "TOPLEFT", 0, -18)
    tsLabelBox:SetAutoFocus(false)
    tsLabelBox:SetMaxLetters(64)
    tsLabelBox:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    tsLabelBox:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    tsLabelBox:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    tsLabelBox:SetTextInsets(6, 6, 0, 0)
    ApplyFont(tsLabelBox, 11)
    tsLabelBox:SetText(db.timeSpiralText or "Free Movement")
    tsLabelBox:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
    tsLabelBox:SetScript("OnEditFocusGained", function() AnimateBorderFocus(tsLabelBox, true)  end)
    tsLabelBox:SetScript("OnEditFocusLost",   function() AnimateBorderFocus(tsLabelBox, false) end)
    tsLabelBox:SetScript("OnEnterPressed", function(self)
        db.timeSpiralText = self:GetText()
        self:ClearFocus()
    end)
    tsLabelBox:SetScript("OnEscapePressed", function(self)
        self:SetText(db.timeSpiralText or "Free Movement")
        self:ClearFocus()
    end)
    function tsLabelRow:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        tsLabelBox:SetEnabled(en)
    end
    card4:AddRow(tsLabelRow, 44)
    table.insert(tsRows, tsLabelRow)
    card4:AddLabel("Text shown during a Time Spiral proc. Press Enter to save.", T.textMuted)
    card4:AddSeparator()

    -- ── Text color ────────────────────────────────────────
    local tsSrcRow, tsSwRow = GUI:CreateColorWithSource(
        parent, "Time Spiral Color", db, "timeSpiralColorSource", "timeSpiralColor",
        { 0.451, 0.741, 0.522 },
        function() Refresh() end)
    card4:AddRow(tsSrcRow, 44)
    card4:AddSeparator()
    card4:AddRow(tsSwRow, 52)
    table.insert(tsRows, tsSrcRow)
    table.insert(tsRows, tsSwRow)
    card4:AddSeparator()

    -- ── Sound (toggle + dropdown + Listen on one line) ────
    local tsPlaySoundRow = GUI:CreateToggle(parent, "Play Sound on Trigger",
        db.timeSpiralPlaySound,
        function(v)
            db.timeSpiralPlaySound = v
            UpdateTSSoundState(v)
        end)

    -- Build sorted LSM sound list with "None" first
    local tsSndNames = {}
    do
        local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
        if lsm then
            for name in pairs(lsm:HashTable("sound")) do
                table.insert(tsSndNames, name)
            end
            table.sort(tsSndNames)
        end
        for i, v in ipairs(tsSndNames) do
            if v == "None" then table.remove(tsSndNames, i); break end
        end
        table.insert(tsSndNames, 1, "None")
    end

    local tsSndDd = GUI:CreateDropdown(parent, "Sound",
        tsSndNames, db.timeSpiralSound or "None",
        function(v)
            db.timeSpiralSound = (v ~= "None") and v or nil
        end)

    -- "Listen" button anchored to the right edge of the dropdown
    local tsSndHandle, tsSndPlaying = nil, false
    local tsSndPreviewLbl
    local tsSndPreviewBtn = CreateFrame("Button", nil, tsSndDd, "BackdropTemplate")
    tsSndPreviewBtn:SetSize(46, 22)
    tsSndPreviewBtn:SetPoint("BOTTOMLEFT", tsSndDd, "BOTTOMRIGHT", 4, 0)
    SetBackdrop(tsSndPreviewBtn, T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    tsSndPreviewLbl = tsSndPreviewBtn:CreateFontString(nil, "OVERLAY")
    tsSndPreviewLbl:SetAllPoints(); ApplyFont(tsSndPreviewLbl, 11)
    tsSndPreviewLbl:SetText("Listen")
    tsSndPreviewLbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    tsSndPreviewBtn.lbl = tsSndPreviewLbl
    local function StopTsSound()
        if tsSndHandle then StopSound(tsSndHandle, 200); tsSndHandle = nil end
        tsSndPlaying = false
        tsSndPreviewLbl:SetText("Listen")
        tsSndPreviewLbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    end
    tsSndPreviewBtn:SetScript("OnEnter", function() AnimateBorderFocus(tsSndPreviewBtn, true)  end)
    tsSndPreviewBtn:SetScript("OnLeave", function() AnimateBorderFocus(tsSndPreviewBtn, false) end)
    tsSndPreviewBtn:SetScript("OnClick", function()
        if tsSndPlaying then StopTsSound(); return end
        local soundName = db.timeSpiralSound
        if not soundName or soundName == "None" then return end
        local lsm  = LibStub and LibStub("LibSharedMedia-3.0", true)
        local file = lsm and lsm:Fetch("sound", soundName)
        if not file then return end
        local ok, h = PlaySoundFile(file, "Master")
        if ok then
            tsSndHandle  = h
            tsSndPlaying = true
            tsSndPreviewLbl:SetText("Stop")
            tsSndPreviewLbl:SetTextColor(1, 0.3, 0.3, 1)
        end
    end)
    -- Extend SetEnabled to cover the inline Listen button
    local _origTsSndSetEnabled = tsSndDd.SetEnabled
    function tsSndDd:SetEnabled(en)
        _origTsSndSetEnabled(self, en)
        tsSndPreviewBtn:EnableMouse(en)
        tsSndPreviewBtn:SetAlpha(en and 1 or 0.4)
        if not en then StopTsSound() end
    end

    -- Label inline so it doesn't wrap when the dropdown is narrowed in the HRow
    tsSndDd:SetLabelInline(40)

    -- Place toggle + dropdown on one row
    local tsSoundHRow = GUI:CreateHRow(parent, 44)
    tsSoundHRow:Add(tsPlaySoundRow, 0.55)
    tsSoundHRow:Add(tsSndDd, 0.45)
    card4:AddRow(tsSoundHRow, 44)
    table.insert(tsRows, tsSoundHRow)
    table.insert(tsSoundRows, tsSndDd)
    card4:AddSeparator()

    -- ── Anchor + strata ───────────────────────────────────
    local tsIconDb = setmetatable({}, {
        __index = function(_, k)
            if k == "anchorFrame"  then return db.timeSpiralIconAnchorFrame
            elseif k == "anchorFrom"  then return db.timeSpiralIconAnchorFrom
            elseif k == "anchorTo"    then return db.timeSpiralIconAnchorTo
            elseif k == "frameStrata" then return db.timeSpiralIconFrameStrata
            else return db[k] end
        end,
        __newindex = function(_, k, v)
            if k == "anchorFrame"  then db.timeSpiralIconAnchorFrame = v
            elseif k == "anchorFrom"  then db.timeSpiralIconAnchorFrom = v
            elseif k == "anchorTo"    then db.timeSpiralIconAnchorTo = v
            elseif k == "frameStrata" then db.timeSpiralIconFrameStrata = v
            else db[k] = v end
        end,
    })
    local tsIconAnchorRow, tsIconAnchorRowH = GUI:CreateAnchorRow(parent, tsIconDb, function()
        local ma = GetMA()
        if ma and ma.Refresh then ma:Refresh() end
    end, { default = "MEDIUM", onChange = function() end })
    card4:AddRow(tsIconAnchorRow, tsIconAnchorRowH)
    table.insert(tsRows, tsIconAnchorRow)
    card4:AddSeparator()

    -- ── Text position ─────────────────────────────────────
    local tsTxtXRow = GUI:CreateSlider(parent, "Text X", -500, 500, 1,
        db.timeSpiralTextX or 0,
        function(v) db.timeSpiralTextX = v end)
    local tsTxtYRow = GUI:CreateSlider(parent, "Text Y", -500, 500, 1,
        db.timeSpiralTextY or 200,
        function(v) db.timeSpiralTextY = v end)
    local tsTxtXYRow = GUI:CreateHRow(parent, 44)
    tsTxtXYRow:Add(tsTxtXRow, 0.5)
    tsTxtXYRow:Add(tsTxtYRow, 0.5)
    card4:AddRow(tsTxtXYRow, 44)
    table.insert(tsRows, tsTxtXYRow)
    card4:AddLabel("Position of the countdown text when Time Spiral is active.", T.textMuted)
    card4:AddSeparator()

    -- ── Icon display ──────────────────────────────────────
    local tsShowIconRow = GUI:CreateToggle(parent, "Show Spell Icon",
        db.timeSpiralShowIcon or false,
        function(v)
            db.timeSpiralShowIcon = v
            local ma = GetMA()
            if ma and ma.Refresh then ma:Refresh() end
        end)
    local tsIconSizeRow = GUI:CreateSlider(parent, "Icon Size", 20, 100, 1,
        db.timeSpiralIconSize or 50,
        function(v)
            db.timeSpiralIconSize = v
            local ma = GetMA()
            if ma and ma.Refresh then ma:Refresh() end
        end)
    -- Label inline so it doesn't sit above the slider when narrowed in the HRow
    tsIconSizeRow:SetLabelInline(60)

    local tsShowIconHRow = GUI:CreateHRow(parent, 44)
    tsShowIconHRow:Add(tsShowIconRow, 0.45)
    tsShowIconHRow:Add(tsIconSizeRow, 0.55)
    card4:AddRow(tsShowIconHRow, 44)
    table.insert(tsRows, tsShowIconHRow)

    -- Icon X / Y on one line
    local tsIconXRow = GUI:CreateSlider(parent, "Icon X", -500, 500, 1,
        db.timeSpiralIconX or 0,
        function(v)
            db.timeSpiralIconX = v
            local ma = GetMA()
            if ma and ma.Refresh then ma:Refresh() end
        end)
    local tsIconYRow = GUI:CreateSlider(parent, "Icon Y", -500, 500, 1,
        db.timeSpiralIconY or 250,
        function(v)
            db.timeSpiralIconY = v
            local ma = GetMA()
            if ma and ma.Refresh then ma:Refresh() end
        end)
    local tsIconXYRow = GUI:CreateHRow(parent, 44)
    tsIconXYRow:Add(tsIconXRow, 0.5)
    tsIconXYRow:Add(tsIconYRow, 0.5)
    card4:AddRow(tsIconXYRow, 44)
    table.insert(tsRows, tsIconXYRow)
    card4:AddSeparator()

    -- ── Time Spiral preview button ────────────────────────
    local tsPreviewActive = false
    local tsPreviewBtn    -- forward-declared; assigned below
    local tsPreviewWrap = CreateFrame("Frame", nil, parent)
    tsPreviewWrap:SetHeight(28)
    function tsPreviewWrap:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        tsPreviewBtn:EnableMouse(en)
    end
    tsPreviewBtn = GUI:CreateButton(tsPreviewWrap, "Preview", nil, 140, 28)
    tsPreviewBtn:SetPoint("LEFT", tsPreviewWrap, "LEFT", 0, 0)
    tsPreviewBtn:SetScript("OnLeave", function()
        AnimateBorderFocus(tsPreviewBtn, tsPreviewActive)
        tsPreviewBtn.lbl:SetTextColor(
            tsPreviewActive and T.accent[1] or T.textPrimary[1],
            tsPreviewActive and T.accent[2] or T.textPrimary[2],
            tsPreviewActive and T.accent[3] or T.textPrimary[3], 1)
    end)
    tsPreviewBtn:SetScript("OnClick", function()
        local ma = GetMA()
        if not ma then return end
        tsPreviewActive = not tsPreviewActive
        if tsPreviewActive then
            ma:ShowTimeSpiralPreview()
            tsPreviewBtn.lbl:SetText("Stop Preview")
            tsPreviewBtn.lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        else
            ma:HideTimeSpiralPreview()
            tsPreviewBtn.lbl:SetText("Preview")
            tsPreviewBtn.lbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        end
        AnimateBorderFocus(tsPreviewBtn, tsPreviewActive)
    end)
    card4:AddRow(tsPreviewWrap, 28)
    table.insert(tsRows, tsPreviewWrap)

    -- When the 5 s auto-cancel fires, reset the button label
    local tsMa = GetMA()
    if tsMa then
        tsMa._tsPreviewEndCallback = function()
            tsPreviewActive = false
            tsPreviewBtn.lbl:SetText("Preview")
            tsPreviewBtn.lbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
            AnimateBorderFocus(tsPreviewBtn, false)
        end
    end

    y = y + card4:GetTotalHeight() + T.paddingSmall

    -- Apply initial state
    UpdateChildState(db.enabled)
    UpdateTSChildState(db.showTimeSpiral ~= false)

    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Nudge Tool
-- ============================================================
GUI:RegisterContent("editmode", function(parent)
    local y      = 0
    local aHex   = GetAccentHex()
    local loaded = SP.nudgeFrame ~= nil

    -- ── Card 1: Plugin status ─────────────────────────────
    local statusCard = GUI:CreateCard(parent, "Nudge Tool", y)
    if loaded then
        statusCard:AddLabel(
            "|cff4DCC66Plugin active|r  —  The Nudge Tool is loaded and operational.",
            T.textPrimary)
    else
        statusCard:AddLabel(
            "|cffFF4444Plugin inactive|r  —  The Nudge Tool is a separate addon.",
            T.textPrimary)
        statusCard:AddSeparator()
        statusCard:AddLabel(
            string.format("To activate: open the WoW addon list (Esc |cff%s>|r AddOns), check |cff%sSuspicionsPackNudgeTool|r, then reload the interface.", aHex, aHex),
            T.textMuted)
        statusCard:AddLabel(
            "To deactivate: uncheck it in the same list and reload.",
            T.textMuted)
    end
    y = y + statusCard:GetTotalHeight() + T.paddingSmall

    if loaded then
        -- ── Card 2: How to use ────────────────────────────
        local card1 = GUI:CreateCard(parent, "Usage", y)
        card1:AddLabel(
            string.format("Open Blizzard's Edit Mode (Game Menu |cff%s>|r Edit Mode) and click any element to select it — the Nudge panel appears automatically below the settings window.", aHex),
            T.textMuted)
        y = y + card1:GetTotalHeight() + T.paddingSmall

        -- ── Card 3: Controls ──────────────────────────────
        local card2 = GUI:CreateCard(parent, "Controls", y)
        card2:AddLabel(
            string.format("|cff%sD-Pad Arrows|r  — Move the selected frame by 1 pixel.", aHex),
            T.textMuted)
        card2:AddSpacing(2)
        card2:AddLabel(
            string.format("|cff%sX / Y Fields|r  — Enter a value and press Enter to set it directly.", aHex),
            T.textMuted)
        card2:AddSpacing(2)
        card2:AddLabel(
            string.format("|cff%sSelf Point|r  — Anchor point on the frame itself.", aHex),
            T.textMuted)
        card2:AddSpacing(2)
        card2:AddLabel(
            string.format("|cff%sAnchor to|r  — Name of the frame to anchor to (default: UIParent).", aHex),
            T.textMuted)
        card2:AddSpacing(2)
        card2:AddLabel(
            string.format("|cff%sAnchor Point|r  — Point on the anchor frame.", aHex),
            T.textMuted)
        y = y + card2:GetTotalHeight() + T.paddingSmall

        -- ── Card 4: Compatible elements ───────────────────
        local card3 = GUI:CreateCard(parent, "Compatible Elements", y)
        card3:AddLabel(
            "Works with any frame exposed in Blizzard's Edit Mode (PlayerFrame, Minimap, action bars, cast bars, buffs, etc.).",
            T.textMuted)
        card3:AddSeparator()
        card3:AddLabel(
            "Changes are saved by Blizzard's layout system — click Save in the Edit Mode window to keep them.",
            T.textMuted)
        y = y + card3:GetTotalHeight() + T.paddingSmall
    end

    parent:SetHeight(y)
end)


-- ============================================================
-- Page: Bloodlust Alert
-- ============================================================
GUI:RegisterContent("bloodlustalert", function(parent)
    local db = SP.GetDB().bloodlustAlert
    local y  = 0

    local function ApplySettings()
        if SP.BloodlustAlert and SP.BloodlustAlert.Refresh then
            SP.BloodlustAlert:Refresh()
        end
    end

    local childRows       = {}
    local childCards      = {}
    local playSoundChildRows = {}   -- gated by db.enabled AND db.playSound
    local enableRow       -- forward-declared; used in UpdateChildState closure
    local card1           -- forward-declared for UpdateChildState closure

    local function UpdateChildState(enabled)
        card1:GrayContent(enabled, enableRow)
        for _, r in ipairs(childRows)  do r:SetEnabled(enabled) end
        for _, c in ipairs(childCards) do c:SetAlpha(enabled and 1 or 0.4) end
        -- Secondary gate: sound sub-options only active when Play Sound is on
        local soundEffective = enabled and (db.playSound ~= false)
        for _, r in ipairs(playSoundChildRows) do r:SetEnabled(soundEffective) end
    end

    -- ── Card: General ─────────────────────────────────────
    card1 = GUI:CreateCard(parent, "Bloodlust Alert", y)

    card1:AddLabel(
        "Plays a sound when Bloodlust / Heroism / Time Warp is detected. Detection uses two independent signals — a haste spike (>= 30 pp in a single event) and a new debuff on the player — both must fire within 0.3 s to confirm. Event-driven only, no polling.",
        T.textMuted)
    card1:AddSeparator()

    enableRow = GUI:CreateToggle(parent, "Enable Bloodlust Alert", db.enabled,
        function(v)
            db.enabled = v
            UpdateChildState(v)
            ApplySettings()
        end, "Bloodlust Alert")
    card1:AddRow(enableRow, 28)

    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- ── Card: Audio ───────────────────────────────────────
    local card3 = GUI:CreateCard(parent, "Audio", y)
    card3:AddLabel("Play a sound when Bloodlust, Heroism, or Time Warp is detected.", T.textMuted)
    card3:AddSeparator()
    table.insert(childCards, card3)

    -- Play sound toggle
    local playSoundRow = GUI:CreateToggle(parent, "Play Sound", db.playSound ~= false,
        function(v)
            db.playSound = v
            UpdateChildState(db.enabled)
        end, "Bloodlust Alert")
    card3:AddRow(playSoundRow, 28)
    table.insert(childRows, playSoundRow)

    -- Track random mode separately from the specific sound choice.
    -- When random is on, db.sound == "random"; the dropdown still remembers the last real pick.
    local isRandom     = (db.sound == "random")
    local lastRealSound = (db.sound and db.sound ~= "random") and db.sound or "hotnigga"

    -- Build sound list WITHOUT a "Random" entry — random is now a separate toggle
    local soundLabels    = {}
    local soundLabelToKey = {}
    local currentSoundLabel = lastRealSound
    if SP.BloodlustAlert and SP.BloodlustAlert.Sounds then
        for _, s in ipairs(SP.BloodlustAlert.Sounds) do
            table.insert(soundLabels, s.label)
            soundLabelToKey[s.label] = s.key
            if s.key == lastRealSound then
                currentSoundLabel = s.label
            end
        end
    end

    -- Preview state
    local previewHandle  = nil
    local previewPlaying = false
    local previewBtn  -- forward declare so StopPreview can reference it

    local function StopPreview()
        if previewHandle then
            StopSound(previewHandle, 200)
            previewHandle  = nil
            previewPlaying = false
        end
        if previewBtn then
            previewBtn.lbl:SetText("Listen")
            previewBtn.lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        end
    end

    local soundRow = GUI:CreateDropdown(parent, "Sound",
        soundLabels, currentSoundLabel,
        function(v)
            lastRealSound = soundLabelToKey[v] or "hotnigga"
            if not isRandom then db.sound = lastRealSound end
            StopPreview()
        end)
    card3:AddRow(soundRow, 40)
    table.insert(playSoundChildRows, soundRow)

    -- ▶ / ■ preview button — sits inline to the right of the dropdown button
    previewBtn = CreateFrame("Button", nil, soundRow, "BackdropTemplate")
    previewBtn:SetSize(46, 22)
    previewBtn:SetPoint("TOPLEFT", soundRow, "TOPLEFT", 208, -16)
    SetBackdrop(previewBtn, T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)

    local previewLbl = previewBtn:CreateFontString(nil, "OVERLAY")
    previewLbl:SetAllPoints(); ApplyFont(previewLbl, 11)
    previewLbl:SetText("Listen")
    previewLbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
    previewBtn.lbl = previewLbl

    previewBtn:SetScript("OnEnter", function() AnimateBorderFocus(previewBtn, true)  end)
    previewBtn:SetScript("OnLeave", function() AnimateBorderFocus(previewBtn, false) end)
    previewBtn:SetScript("OnClick", function()
        if previewPlaying then
            StopPreview()
            return
        end
        -- Resolve file for the currently selected sound
        local key  = db.sound or "hotnigga"
        local file = nil
        if key == "random" then
            local choices = {}
            if SP.BloodlustAlert and SP.BloodlustAlert.Sounds then
                for _, s in ipairs(SP.BloodlustAlert.Sounds) do
                    if s.file then table.insert(choices, s.file) end
                end
            end
            if #choices > 0 then
                file = choices[math.random(#choices)]
            end
        elseif SP.BloodlustAlert and SP.BloodlustAlert.Sounds then
            for _, s in ipairs(SP.BloodlustAlert.Sounds) do
                if s.key == key then file = s.file; break end
            end
        end
        if not file then return end
        local ok, h = PlaySoundFile(file, "Master")
        if ok then
            previewHandle  = h
            previewPlaying = true
            previewLbl:SetText("Stop")
            previewLbl:SetTextColor(1, 0.3, 0.3, 1)
        end
    end)

    -- Extend soundRow's SetEnabled to also cover the preview button and respect Random mode.
    local _origSetEnabled = soundRow.SetEnabled
    function soundRow:SetEnabled(en)
        local effective = en and not isRandom
        _origSetEnabled(self, effective)
        previewBtn:EnableMouse(effective)
        previewBtn:SetAlpha(effective and 1 or 0.4)
        if not effective then StopPreview() end
    end

    -- Random toggle — when on, grays out the sound picker and preview
    local randomRow = GUI:CreateToggle(parent, "Random Sound", isRandom,
        function(v)
            isRandom = v
            if v then
                lastRealSound = (db.sound ~= "random") and db.sound or lastRealSound
                db.sound = "random"
                StopPreview()
            else
                db.sound = lastRealSound
            end
            -- Re-evaluate enabled state for sound row (parent enable + playSound + isRandom)
            soundRow:SetEnabled(db.enabled and (db.playSound ~= false))
        end)
    card3:AddRow(randomRow, 28)
    table.insert(playSoundChildRows, randomRow)
    card3:AddLabel("Picks a different sound each time Bloodlust is detected.", T.textMuted)

    card3:AddSeparator()

    local chLabels = { "Master", "Music", "SFX", "Ambience", "Dialog" }
    local chRow = GUI:CreateDropdown(parent, "Audio Channel",
        chLabels, db.channel,
        function(v) db.channel = v end)
    card3:AddRow(chRow, 40)
    table.insert(playSoundChildRows, chRow)

    card3:AddLabel("Volume channel for the bloodlust sound.", T.textMuted)

    y = y + card3:GetTotalHeight() + T.paddingSmall

    -- ── Card 4: Timer Display ──────────────────────────────
    local card4 = GUI:CreateCard(parent, "Timer Display", y)
    card4:AddLabel("An optional countdown showing how long the Bloodlust buff lasts.", T.textMuted)
    card4:AddSeparator()
    table.insert(childCards, card4)

    local function ApplyTimerSettings()
        if SP.BloodlustAlert and SP.BloodlustAlert.ApplyTimerSettings then
            SP.BloodlustAlert:ApplyTimerSettings()
        end
    end

    -- Sub-rows gated by the timer enabled toggle
    local timerChildRows = {}
    local function UpdateTimerChildState(en)
        for _, r in ipairs(timerChildRows) do r:SetEnabled(en) end
    end

    -- Forward-declare preview state so the enable toggle can reference it
    local timerPreviewActive = false
    local timerPreviewBtn    -- assigned below

    -- Enable toggle (pill)
    local timerEnableRow = GUI:CreateToggle(parent, "Enable Timer",
        db.timerEnabled ~= false,
        function(v)
            db.timerEnabled = v
            UpdateTimerChildState(v)
            if not v then
                -- Kill active preview when timer is disabled
                if timerPreviewActive and timerPreviewBtn then
                    timerPreviewActive = false
                    timerPreviewBtn.lbl:SetText("Preview")
                    timerPreviewBtn.lbl:SetTextColor(
                        T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
                end
                if SP.BloodlustAlert then SP.BloodlustAlert:HideTimerPreview() end
            end
        end)
    card4:AddRow(timerEnableRow, 28)
    table.insert(childRows, timerEnableRow)
    card4:AddSeparator()

    -- Anchor row + Preview button (combined) — anchors centered, preview top-left
    -- Layout: [Frame Strata | Anchored To] header + [Anchor From | To Frame's] grids
    local GRID_W      = ANCHOR_BTN_SIZE * 3 + ANCHOR_PAD * 2   -- 105 px
    local GRID_H      = ANCHOR_BTN_SIZE * 3 + ANCHOR_PAD * 2   -- 105 px
    local COL_GAP     = 16
    local COL2_X      = GRID_W + COL_GAP                       -- 121
    local GRIDS_W     = COL2_X + GRID_W                        -- 226 (2-col)
    local HEADER_H    = 40
    local anchorRowH  = HEADER_H + 4 + 16 + GRID_H             -- 145 px
    local halfW       = math.floor(GRIDS_W / 2 - COL_GAP / 2)  -- ~85 px

    local timerAnchorRow = CreateFrame("Frame", nil, parent)
    timerAnchorRow:SetHeight(anchorRowH)

    -- Inner centered container
    local taInner = CreateFrame("Frame", nil, timerAnchorRow)
    taInner:SetSize(GRIDS_W, anchorRowH)
    taInner:SetPoint("CENTER", timerAnchorRow, "CENTER", 0, 0)

    -- ── Header: Frame Strata (left) + Anchored To (right) ──────────────
    local taStrataLbl = taInner:CreateFontString(nil, "OVERLAY")
    taStrataLbl:SetPoint("TOPLEFT", taInner, "TOPLEFT", 0, -2)
    ApplyFont(taStrataLbl, 11); taStrataLbl:SetText("Frame Strata")
    taStrataLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    local taStrataBtn = CreateDropdown(taInner,
        StrOptions({ "LOW", "MEDIUM", "HIGH", "DIALOG", "TOOLTIP" }),
        db.frameStrata or "TOOLTIP",
        function(v) db.frameStrata = v; ApplyTimerSettings() end, halfW)
    taStrataBtn:SetPoint("TOPLEFT", taInner, "TOPLEFT", 0, -18)

    local atoX = halfW + COL_GAP
    local taFrameLbl = taInner:CreateFontString(nil, "OVERLAY")
    taFrameLbl:SetPoint("TOPLEFT", taInner, "TOPLEFT", atoX, -2)
    ApplyFont(taFrameLbl, 11); taFrameLbl:SetText("Anchored To")
    taFrameLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    local tfiBoxW = halfW - PICK_BTN_W - 2  -- leave room for inline pick button
    local tfiBox = CreateFrame("EditBox", nil, taInner, "BackdropTemplate")
    tfiBox:SetSize(tfiBoxW, 22)
    tfiBox:SetPoint("TOPLEFT", taInner, "TOPLEFT", atoX, -18)
    tfiBox:SetAutoFocus(false); tfiBox:SetMaxLetters(64)
    tfiBox:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
    tfiBox:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
    tfiBox:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
    tfiBox:SetTextInsets(6, 6, 0, 0)
    ApplyFont(tfiBox, 11)
    tfiBox:SetText(db.timerAnchorFrame or "UIParent")
    tfiBox:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
    tfiBox:SetScript("OnEnterPressed", function(self)
        db.timerAnchorFrame = self:GetText(); ApplyTimerSettings(); self:ClearFocus()
    end)
    tfiBox:SetScript("OnEscapePressed", function(self)
        self:SetText(db.timerAnchorFrame or "UIParent"); self:ClearFocus()
    end)
    tfiBox:SetScript("OnEditFocusGained", function() AnimateBorderFocus(tfiBox, true)  end)
    tfiBox:SetScript("OnEditFocusLost",   function() AnimateBorderFocus(tfiBox, false) end)

    -- Pick button: inline to the right of the editbox
    local taPickBtn = MakePickBtn(taInner, atoX + tfiBoxW + 2, -18, PICK_BTN_W, function(name)
        db.timerAnchorFrame = name
        tfiBox:SetText(name)
        ApplyTimerSettings()
    end)

    -- ── Anchor grids (2-col below header) ──────────────────────────────
    local gridY = HEADER_H + 4
    local taFromLbl = taInner:CreateFontString(nil, "OVERLAY")
    taFromLbl:SetPoint("TOPLEFT", taInner, "TOPLEFT", 0, -(gridY + 2))
    ApplyFont(taFromLbl, 11); taFromLbl:SetText("Anchor From")
    taFromLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    local taFromSel = GUI:CreateAnchorSelector(taInner,
        db.timerAnchorFrom or "CENTER",
        function(v) db.timerAnchorFrom = v; ApplyTimerSettings() end)
    taFromSel:SetPoint("TOPLEFT", taInner, "TOPLEFT", 0, -(gridY + 16))

    local taToLbl = taInner:CreateFontString(nil, "OVERLAY")
    taToLbl:SetPoint("TOPLEFT", taInner, "TOPLEFT", COL2_X, -(gridY + 2))
    ApplyFont(taToLbl, 11); taToLbl:SetText("To Frame's")
    taToLbl:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
    local taToSel = GUI:CreateAnchorSelector(taInner,
        db.timerAnchorTo or "CENTER",
        function(v) db.timerAnchorTo = v; ApplyTimerSettings() end)
    taToSel:SetPoint("TOPLEFT", taInner, "TOPLEFT", COL2_X, -(gridY + 16))

    -- SetEnabled: gray anchors only (preview managed separately below)
    function timerAnchorRow:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        taFromSel:EnableMouse(en)
        taToSel:EnableMouse(en)
        tfiBox:SetEnabled(en)
        taStrataBtn:EnableMouse(en)
        taPickBtn:EnableMouse(en)
    end
    card4:AddRow(timerAnchorRow, anchorRowH)
    table.insert(timerChildRows, timerAnchorRow)
    card4:AddSeparator()

    -- Preview button — separate row below the anchor grid
    local timerPreviewWrap = CreateFrame("Frame", nil, parent)
    timerPreviewWrap:SetHeight(28)
    function timerPreviewWrap:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        if timerPreviewBtn then timerPreviewBtn:EnableMouse(en) end
    end

    timerPreviewBtn = GUI:CreateButton(timerPreviewWrap, "Preview", nil, 140, 28)
    timerPreviewBtn:SetPoint("LEFT", timerPreviewWrap, "LEFT", 0, 0)
    timerPreviewBtn:SetScript("OnLeave", function()
        AnimateBorderFocus(timerPreviewBtn, timerPreviewActive)
        timerPreviewBtn.lbl:SetTextColor(
            timerPreviewActive and T.accent[1] or T.textPrimary[1],
            timerPreviewActive and T.accent[2] or T.textPrimary[2],
            timerPreviewActive and T.accent[3] or T.textPrimary[3], 1)
    end)
    timerPreviewBtn:SetScript("OnClick", function()
        local bla = SP.BloodlustAlert
        if not bla then return end
        timerPreviewActive = not timerPreviewActive
        if timerPreviewActive then
            bla:ShowTimerPreview()
            local tf = _G["SPBLTimerFrame"]
            if tf and tf.movableLbl then
                tf.movableLbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
            end
            timerPreviewBtn.lbl:SetText("Stop Preview")
            timerPreviewBtn.lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        else
            bla:HideTimerPreview()
            timerPreviewBtn.lbl:SetText("Preview")
            timerPreviewBtn.lbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        end
    end)
    card4:AddRow(timerPreviewWrap, 28)
    table.insert(timerChildRows, timerPreviewWrap)
    card4:AddSeparator()

    -- X / Y offset — side by side
    local xyOffsetRow = GUI:CreateHRow(parent, 44)
    local txRow = GUI:CreateSlider(parent, "X Offset", -2000, 2000, 1, db.timerX or 0,
        function(v) db.timerX = v; ApplyTimerSettings() end)
    local tyRow = GUI:CreateSlider(parent, "Y Offset", -2000, 2000, 1, db.timerY or -220,
        function(v) db.timerY = v; ApplyTimerSettings() end)
    xyOffsetRow:Add(txRow, 0.5)
    xyOffsetRow:Add(tyRow, 0.5)
    card4:AddRow(xyOffsetRow, 44)
    table.insert(timerChildRows, xyOffsetRow)

    card4:AddSeparator()

    -- Font Face + Outline — side by side
    local blFontHRow = GUI:CreateHRow(parent, 44)
    local blDdFontFace = GUI:CreateFontDropdown(parent, "Font Face",
        db.timerFontFace or "Expressway",
        function(v) db.timerFontFace = v; ApplyTimerSettings() end)
    local blDdOutline = GUI:CreateDropdown(parent, "Outline",
        { "NONE", "OUTLINE", "THICKOUTLINE", "SOFTOUTLINE" },
        db.timerOutline or "OUTLINE",
        function(v) db.timerOutline = v; ApplyTimerSettings() end)
    blFontHRow:Add(blDdFontFace, 0.6)
    blFontHRow:Add(blDdOutline, 0.4)
    card4:AddRow(blFontHRow, 44)
    table.insert(timerChildRows, blFontHRow)

    card4:AddSeparator()

    -- Font size
    local tFontRow = GUI:CreateSlider(parent, "Font Size", 10, 60, 1, db.timerFontSize or 22,
        function(v) db.timerFontSize = v; ApplyTimerSettings() end)
    card4:AddRow(tFontRow, 44)
    table.insert(timerChildRows, tFontRow)

    card4:AddSeparator()

    -- Show Label + Show Bar — side by side, left-packed with small gap
    local showTogglesRow = CreateFrame("Frame", nil, parent)
    showTogglesRow:SetHeight(28)
    local tShowLabelRow = GUI:CreateToggle(parent, "Show Label",
        db.timerShowLabel ~= false,
        function(v) db.timerShowLabel = v; ApplyTimerSettings() end)
    local tShowBarRow = GUI:CreateToggle(parent, "Show Bar",
        db.timerShowBar ~= false,
        function(v) db.timerShowBar = v; ApplyTimerSettings() end)
    local PILL_W, PILL_GAP = 120, 12
    tShowLabelRow:SetParent(showTogglesRow)
    tShowBarRow:SetParent(showTogglesRow)
    tShowLabelRow:SetSize(PILL_W, 24); tShowLabelRow:SetPoint("TOPLEFT", showTogglesRow, "TOPLEFT", 0, -2)
    tShowBarRow:SetSize(PILL_W, 24);  tShowBarRow:SetPoint("TOPLEFT", tShowLabelRow, "TOPRIGHT", PILL_GAP, 0)
    function showTogglesRow:SetEnabled(en)
        self:SetAlpha(en and 1 or 0.4)
        tShowLabelRow:EnableMouse(en); tShowBarRow:EnableMouse(en)
    end
    card4:AddRow(showTogglesRow, 28)
    table.insert(timerChildRows, showTogglesRow)

    card4:AddSeparator()

    -- Backdrop opacity
    local tOpacityRow = GUI:CreateSlider(parent, "Backdrop Opacity", 0, 1, 0.05,
        db.timerBgOpacity ~= nil and db.timerBgOpacity or 0.85,
        function(v) db.timerBgOpacity = v; ApplyTimerSettings() end)
    card4:AddRow(tOpacityRow, 44)
    table.insert(timerChildRows, tOpacityRow)

    card4:AddSeparator()

    -- Number Color with source dropdown
    local tNumSrcRow, tNumSwRow = GUI:CreateColorWithSource(
        parent, "Number Color", db, "timerNumColorSource", "timerNumColor", { 1, 1, 1 },
        function() ApplyTimerSettings() end)
    card4:AddRow(tNumSrcRow, 44)
    table.insert(timerChildRows, tNumSrcRow)
    card4:AddSeparator()
    card4:AddRow(tNumSwRow, 52)
    table.insert(timerChildRows, tNumSwRow)
    card4:AddSeparator()

    -- Bar Color with source dropdown
    local tBarSrcRow, tBarSwRow = GUI:CreateColorWithSource(
        parent, "Bar Color", db, "timerBarColorSource", "timerBarColor", { 0.93, 0.27, 0.27 },
        function() ApplyTimerSettings() end)
    card4:AddRow(tBarSrcRow, 44)
    table.insert(timerChildRows, tBarSrcRow)
    card4:AddSeparator()
    card4:AddRow(tBarSwRow, 52)
    table.insert(timerChildRows, tBarSwRow)

    -- Apply initial timer child state based on toggle value
    UpdateTimerChildState(db.timerEnabled ~= false)

    y = y + card4:GetTotalHeight() + T.paddingSmall

    UpdateChildState(db.enabled)
    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Auto Misdirection
-- ============================================================
GUI:RegisterContent("tankmd", function(parent)
    local T  = SP.Theme
    local db = SP.GetDB().tankMD

    local function ApplySettings()
        if SP.TankMD then SP.TankMD:Refresh() end
    end

    -- Copy dialog for macro snippets
    local SP_MACRO_DIALOG = "SP_TANKMD_MACRO_COPY"
    if not StaticPopupDialogs[SP_MACRO_DIALOG] then
        StaticPopupDialogs[SP_MACRO_DIALOG] = {
            text      = "Press  |cffffffffCtrl+C|r  to copy.",
            button1   = CLOSE,
            hasEditBox = true,
            EditBoxWidth = 320,
            timeout   = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnShow = function(dialog, data)
                dialog.EditBox:SetMaxLetters(0)
                dialog.EditBox:SetText(data or "")
                dialog.EditBox:HighlightText()
                local function Close() dialog:Hide() end
                dialog.EditBox:SetScript("OnEscapePressed", Close)
                dialog.EditBox:SetScript("OnEnterPressed",  Close)
            end,
        }
    end

    -- Helper: link-style button (same layout as home MakeLink) with outlined text + "copy" hint
    local function MakeMacroLink(card, labelText, snippetText)
        local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
        row:SetHeight(28)
        SetBackdrop(row, T.bgDark[1], T.bgDark[2], T.bgDark[3], 1,
                    T.border[1], T.border[2], T.border[3], 0)

        local lbl = row:CreateFontString(nil, "OVERLAY")
        lbl:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3)
        lbl:SetJustifyH("LEFT")
        ApplyFont(lbl, 9)
        lbl:SetText(labelText)
        lbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)

        local val = row:CreateFontString(nil, "OVERLAY")
        val:SetPoint("TOPLEFT",  row, "TOPLEFT",  6, -13)
        val:SetPoint("TOPRIGHT", row, "TOPRIGHT", -36, -13)
        val:SetJustifyH("LEFT")
        val:SetFont(SP_FONT, 10, "OUTLINE")
        val:SetShadowOffset(0, 0)
        val:SetText(snippetText)
        val:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)

        local hint = row:CreateFontString(nil, "OVERLAY")
        hint:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        hint:SetFont(SP_FONT, 9, "OUTLINE")
        hint:SetShadowOffset(0, 0)
        hint:SetText("copy")
        hint:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 0)

        row:SetScript("OnEnter", function()
            row:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
            hint:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        end)
        row:SetScript("OnLeave", function()
            row:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0)
            hint:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 0)
        end)
        row:SetScript("OnClick", function()
            StaticPopup_Show(SP_MACRO_DIALOG, nil, nil, snippetText)
        end)

        card:AddRow(row, 28)
    end

    local y = 0

    -- Card 1: Overview
    local card1 = GUI:CreateCard(parent, "Auto Misdirection", y)
    card1:AddLabel(
        "Creates hidden macro buttons (TankMDButton1–5) that always target the current tanks (or healers for Druids). Insert a button click in any macro and it will always fire on the right person without manually updating targets. Supports Hunter, Rogue, and Druid.",
        T.textMuted)
    card1:AddSeparator()

    local childRows  = {}
    local childCards = {}
    local enableRow  -- forward-declared; used in UpdateChildState closure
    local function UpdateChildState(en)
        card1:GrayContent(en, enableRow)
        for _, r in ipairs(childRows)  do r:SetEnabled(en) end
        for _, c in ipairs(childCards) do c:SetAlpha(en and 1 or 0.4) end
    end

    enableRow = GUI:CreateToggle(parent, "Enable Auto Misdirection", db.enabled,
        function(v)
            db.enabled = v
            ApplySettings()
            UpdateChildState(v)
        end, "Auto Misdirection")
    card1:AddRow(enableRow, 28)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- Card 2: Options
    local card2 = GUI:CreateCard(parent, "Options", y)
    card2:AddLabel("Fine-tune target selection for misdirection macros.", T.textMuted)
    card2:AddSeparator()
    table.insert(childCards, card2)

    local focusRow = GUI:CreateToggle(parent, "Prioritize Focus Target",
        db.prioritizeFocus,
        function(v) db.prioritizeFocus = v; ApplySettings() end)
    card2:AddRow(focusRow, 28)
    table.insert(childRows, focusRow)
    card2:AddSeparator()

    local METHODS = { "tankRoleOnly", "tanksAndMainTanks", "prioritizeMainTanks", "mainTanksOnly" }
    local METHOD_LABELS = {
        tankRoleOnly        = "Tank Role Only",
        tanksAndMainTanks   = "Tanks + Main Tanks",
        prioritizeMainTanks = "Prioritize Main Tanks",
        mainTanksOnly       = "Main Tanks Only",
    }
    local methodDisplayList = {}
    for _, m in ipairs(METHODS) do table.insert(methodDisplayList, METHOD_LABELS[m]) end
    local function MethodToLabel(m) return METHOD_LABELS[m] or m end
    local function LabelToMethod(lbl)
        for _, m in ipairs(METHODS) do
            if METHOD_LABELS[m] == lbl then return m end
        end
        return "tankRoleOnly"
    end

    local methodRow = GUI:CreateDropdown(parent, "Selection Method",
        methodDisplayList,
        MethodToLabel(db.selectionMethod or "tankRoleOnly"),
        function(lbl) db.selectionMethod = LabelToMethod(lbl); ApplySettings() end)
    card2:AddRow(methodRow, 44)
    table.insert(childRows, methodRow)
    y = y + card2:GetTotalHeight() + T.paddingSmall

    -- Card 3: Macro Usage with click-to-copy snippets
    local card3 = GUI:CreateCard(parent, "Macro Usage", y)
    table.insert(childCards, card3)
    card3:AddLabel(
        "Put this in a macro for your misdirection / tricks / rescue spell. The buttons update automatically when your roster changes. Type /tankmd in chat to see current assignments.",
        T.textMuted)
    card3:AddSeparator()

    MakeMacroLink(card3, "Button 1 (primary target)",
        "#showtooltip [Your spell]  /click TankMDButton1")
    card3:AddSeparator()
    MakeMacroLink(card3, "Button 2 (secondary target)",
        "#showtooltip [Your spell]  /click TankMDButton2")

    y = y + card3:GetTotalHeight() + T.paddingSmall

    UpdateChildState(db.enabled)
    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Focus Target Marker
-- ============================================================
GUI:RegisterContent("focustargetmarker", function(parent)
    local T  = SP.Theme
    local db = SP.GetDB().focusTargetMarker

    local function ApplySettings()
        if SP.FocusTargetMarker then SP.FocusTargetMarker:Refresh() end
    end

    -- Raid marker icon texture coords (same atlas as ItruliaQoL's RaidMarkerString)
    local MARKER_COORDS = {
        [1] = {0.00, 0.25, 0.00, 0.25},  -- Star
        [2] = {0.25, 0.50, 0.00, 0.25},  -- Circle
        [3] = {0.50, 0.75, 0.00, 0.25},  -- Diamond
        [4] = {0.75, 1.00, 0.00, 0.25},  -- Triangle
        [5] = {0.00, 0.25, 0.25, 0.50},  -- Moon
        [6] = {0.25, 0.50, 0.25, 0.50},  -- Square
        [7] = {0.50, 0.75, 0.25, 0.50},  -- Cross
        [8] = {0.75, 1.00, 0.25, 0.50},  -- Skull
    }
    local function MarkerLabel(i)
        local t = MARKER_COORDS[i]
        return string.format(
            "|TInterface\\TargetingFrame\\UI-RaidTargetingIcons:16:16:0:0:256:256:%d:%d:%d:%d|t %s",
            t[1]*256, t[2]*256, t[3]*256, t[4]*256,
            _G["RAID_TARGET_" .. i] or "Marker " .. i
        )
    end
    local markerDisplayList = {}
    for i = 1, 8 do markerDisplayList[i] = MarkerLabel(i) end

    local y = 0

    -- Card 1: Overview
    local card1 = GUI:CreateCard(parent, "Focus Target Marker", y)
    card1:AddLabel(
        "Creates a macro named \"FocusTargetMarker\" that focuses and marks your mouseover (or target fallback) with the chosen raid marker. The macro is rewritten automatically on login and ready checks.",
        T.textMuted)
    card1:AddSeparator()

    local childRows  = {}
    local childCards = {}
    local enableRow  -- forward-declared; used in UpdateChildState closure
    local function UpdateChildState(en)
        card1:GrayContent(en, enableRow)
        for _, r in ipairs(childRows)  do r:SetEnabled(en) end
        for _, c in ipairs(childCards) do c:SetAlpha(en and 1 or 0.4) end
    end

    enableRow = GUI:CreateToggle(parent, "Enable Focus Target Marker", db.enabled,
        function(v)
            db.enabled = v
            ApplySettings()
            UpdateChildState(v)
        end, "Focus Target Marker")
    card1:AddRow(enableRow, 28)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- Card 2: Options
    local card2 = GUI:CreateCard(parent, "Options", y)
    card2:AddLabel("Pick the raid marker and toggle the ready-check announcement.", T.textMuted)
    card2:AddSeparator()
    table.insert(childCards, card2)

    local announceRow = GUI:CreateToggle(parent, "Announce on Ready Check",
        db.announce,
        function(v) db.announce = v end)
    card2:AddRow(announceRow, 28)
    table.insert(childRows, announceRow)
    card2:AddSeparator()

    local markerRow = GUI:CreateDropdown(parent, "Raid Marker",
        markerDisplayList,
        MarkerLabel(db.marker or 5),
        function(lbl)
            for i = 1, 8 do
                if MarkerLabel(i) == lbl then
                    db.marker = i
                    -- Rewrite the macro immediately if the module is active
                    if SP.FocusTargetMarker and SP.FocusTargetMarker:IsEnabled() then
                        SP.FocusTargetMarker:Activate()
                    end
                    break
                end
            end
        end)
    card2:AddRow(markerRow, 44)
    table.insert(childRows, markerRow)
    y = y + card2:GetTotalHeight() + T.paddingSmall

    -- Card 3: Macro usage hint
    local card3 = GUI:CreateCard(parent, "Macro Usage", y)
    table.insert(childCards, card3)
    card3:AddLabel(
        "Once enabled, bind the macro to a key or call it from another macro with /click. The marker index is embedded directly so the macro works even without a focus.",
        T.textMuted)
    y = y + card3:GetTotalHeight() + T.paddingSmall

    UpdateChildState(db.enabled)
    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Meter Reset
-- ============================================================
-- Auto Combat Log page
-- ============================================================
GUI:RegisterContent("combatlog", function(parent)
    local T  = SP.Theme
    local db = SP.GetDB().combatLog

    local function ApplySettings()
        if SP.CombatLog then SP.CombatLog.Refresh() end
    end

    local y = 0

    local card1 = GUI:CreateCard(parent, "Auto Combat Log", y)
    card1:AddLabel(
        "Automatically starts the combat log when you enter a dungeon or raid instance.",
        T.textMuted)
    card1:AddSeparator()

    local enableRow = GUI:CreateToggle(parent, "Enable Auto Combat Log", db.enabled,
        function(v)
            db.enabled = v
            ApplySettings()
        end, "Auto Combat Log")
    card1:AddRow(enableRow, 28)

    local stopRow = GUI:CreateToggle(parent, "Stop logging when leaving instance", db.stopOnLeave,
        function(v)
            db.stopOnLeave = v
        end, "Stop logging when leaving instance")
    card1:AddRow(stopRow, 28)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    parent:SetHeight(y)
end)

-- ============================================================
GUI:RegisterContent("meterreset", function(parent)
    local T  = SP.Theme
    local db = SP.GetDB().meterReset

    local function ApplySettings()
        if SP.MeterReset then SP.MeterReset.Refresh() end
    end

    local y = 0

    local card1 = GUI:CreateCard(parent, "Meter Reset", y)
    card1:AddLabel(
        "When you enter a dungeon or raid instance, a popup will ask if you want to reset your damage meter.",
        T.textMuted)
    card1:AddSeparator()

    local enableRow = GUI:CreateToggle(parent, "Enable Meter Reset Prompt", db.enabled,
        function(v)
            db.enabled = v
            ApplySettings()
        end, "Meter Reset")
    card1:AddRow(enableRow, 28)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    parent:SetHeight(y)
end)


-- ============================================================
-- M+ Auto Playstyle page
-- ============================================================
GUI:RegisterContent("autoplaystyle", function(parent)
    local T  = SP.Theme
    local db = SP.GetDB().autoPlaystyle

    local function ApplySettings()
        if SP.AutoPlaystyle then SP.AutoPlaystyle.Refresh() end
    end

    local y = 0

    local childRows = {}
    local enableRow -- forward-declared; used in UpdateChildState closure
    local card1     -- forward-declared for UpdateChildState closure
    local function UpdateChildState(en)
        card1:GrayContent(en, enableRow)
        for _, r in ipairs(childRows) do r:SetEnabled(en) end
    end

    card1 = GUI:CreateCard(parent, "M+ Auto Playstyle", y)
    card1:AddLabel(
        "Automatically pre-selects your preferred playstyle when you open the Group Finder listing creation dialog for a Mythic+ group. The setting is applied every time the dialog opens, including after switching to a different activity.",
        T.textMuted)
    card1:AddSeparator()

    enableRow = GUI:CreateToggle(parent, "Enable M+ Auto Playstyle", db.enabled,
        function(v)
            db.enabled = v
            UpdateChildState(v)
            ApplySettings()
        end, "M+ Auto Playstyle")
    card1:AddRow(enableRow, 28)
    card1:AddSeparator()

    -- Build playstyle label list (reads WoW globals if Blizzard_GroupFinder is loaded)
    local playstyleLabels = {}
    local labelToIndex    = {}
    local currentLabel    = "Competitive"
    local AP = SP.AutoPlaystyle
    for i = 1, 4 do
        local lbl = (AP and AP.Labels and AP.Labels[i]) or
            ({ "Learning", "Relaxed", "Competitive", "Carry Offered" })[i]
        -- Prefer the live WoW global string if available
        local g = _G["GROUP_FINDER_GENERAL_PLAYSTYLE" .. i]
        if g and g ~= "" then lbl = g end
        table.insert(playstyleLabels, lbl)
        labelToIndex[lbl] = i
        if i == (db.playstyle or 3) then currentLabel = lbl end
    end

    local playstyleRow = GUI:CreateDropdown(parent, "Playstyle",
        playstyleLabels,
        currentLabel,
        function(v)
            db.playstyle = labelToIndex[v] or 3
        end)
    card1:AddRow(playstyleRow, 44)
    table.insert(childRows, playstyleRow)

    y = y + card1:GetTotalHeight() + T.paddingSmall

    UpdateChildState(db.enabled)

    parent:SetHeight(y)
end)
-- ============================================================
-- Death Alert page
-- ============================================================
GUI:RegisterContent("deathalert", function(parent)
    local T  = SP.Theme
    local db = SP.GetDB().deathAlert

    local function ApplySettings()
        if SP.DeathAlert then SP.DeathAlert.Refresh() end
    end

    -- Shared editbox helper
    local function MakeEditRow(lbl, initialText, maxLen, onConfirm)
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(44)
        local fs = row:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
        ApplyFont(fs, 11)
        fs:SetText(lbl)
        fs:SetTextColor(T.textSecondary[1], T.textSecondary[2], T.textSecondary[3], 1)
        local box = CreateFrame("EditBox", nil, row, "BackdropTemplate")
        box:SetSize(150, 22)
        box:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -18)
        box:SetAutoFocus(false)
        box:SetMaxLetters(maxLen or 128)
        box:SetBackdrop({ bgFile = BLANK, edgeFile = BLANK, edgeSize = 1 })
        box:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
        box:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
        box:SetTextInsets(6, 6, 0, 0)
        ApplyFont(box, 11)
        box:SetText(initialText or "")
        box:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        box:SetScript("OnEnterPressed", function(self) self:ClearFocus(); onConfirm(self:GetText()) end)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:SetText(initialText or "") end)
        function row:SetEnabled(en)
            self:SetAlpha(en and 1 or 0.4)
            box:SetEnabled(en)
        end
        row._box = box
        return row
    end

    local y = 0
    local daChildRows  = {}
    local daChildCards = {}
    local enableRow    -- forward-declared; used in UpdateDAChildState closure
    local card1        -- forward-declared for UpdateDAChildState closure
    local function UpdateDAChildState(en)
        card1:GrayContent(en, enableRow)
        for _, r in ipairs(daChildRows)  do r:SetEnabled(en) end
        for _, c in ipairs(daChildCards) do c:SetAlpha(en and 1 or 0.4) end
    end

    -- ── Card 1: General ───────────────────────────────────────
    card1 = GUI:CreateCard(parent, "Death Alert", y)
    card1:AddLabel(
        "Displays a large on-screen message when a party or raid member dies. Shows the player's name in their class colour.",
        T.textMuted)
    card1:AddSeparator()

    enableRow = GUI:CreateToggle(parent, "Enable Death Alert", db.enabled,
        function(v)
            db.enabled = v
            UpdateDAChildState(v)
            ApplySettings()
        end, "Death Alert")
    card1:AddRow(enableRow, 28)
    card1:AddSeparator()

    local selfRow = GUI:CreateToggle(parent, "Show When You Die",
        db.showForSelf ~= false,
        function(v) db.showForSelf = v; ApplySettings() end)
    card1:AddRow(selfRow, 28)
    table.insert(daChildRows, selfRow)

    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- ── Card 2: Display ───────────────────────────────────────
    local card2 = GUI:CreateCard(parent, "Display", y)
    table.insert(daChildCards, card2)
    card2:AddLabel("Customise the on-screen message text and appearance.", T.textMuted)
    card2:AddSeparator()

    local dtRow = MakeEditRow("Message Text", db.displayText or "died", 32,
        function(v) db.displayText = v; ApplySettings() end)
    card2:AddRow(dtRow, 44)
    table.insert(daChildRows, dtRow)
    card2:AddSeparator()

    -- Font picker (LSM)
    do
        local fontDropRow = GUI:CreateFontDropdown(parent, "Font",
            db.fontName or "Expressway",
            function(v) db.fontName = v; ApplySettings() end)
        card2:AddRow(fontDropRow, 44)
        table.insert(daChildRows, fontDropRow)
        card2:AddSeparator()
    end

    -- Font Size + Duration on same row
    local daSzDurHRow = GUI:CreateHRow(parent, 44)
    local fontSzRow = GUI:CreateSlider(parent, "Font Size", 12, 60, 1, db.fontSize or 28,
        function(v) db.fontSize = v; ApplySettings() end)
    local durRow = GUI:CreateSlider(parent, "Duration (s)", 1, 10, 1,
        db.messageDuration or 4,
        function(v) db.messageDuration = v; ApplySettings() end)
    daSzDurHRow:Add(fontSzRow, 0.5)
    daSzDurHRow:Add(durRow, 0.5)
    card2:AddRow(daSzDurHRow, 44)
    table.insert(daChildRows, daSzDurHRow)

    y = y + card2:GetTotalHeight() + T.paddingSmall

    -- ── Card 3: Audio ─────────────────────────────────────────
    local card3 = GUI:CreateCard(parent, "Audio", y)
    table.insert(daChildCards, card3)
    card3:AddLabel(
        "Sound and Text-to-Speech when a death is detected. Both share a 2-second cooldown. Sound takes priority over TTS.",
        T.textMuted)
    card3:AddSeparator()

    -- Sound section
    local audioChildRows = {}
    local function UpdateAudioChildState(soundEn, ttsEn)
        for _, r in ipairs(audioChildRows) do
            if r._isSoundChild then r:SetEnabled(soundEn) end
            if r._isTTSChild   then r:SetEnabled(ttsEn)   end
        end
    end

    local soundToggle = GUI:CreateToggle(parent, "Play Sound", db.playSound,
        function(v)
            db.playSound = v
            UpdateAudioChildState(v, db.playTTS)
            ApplySettings()
        end)
    card3:AddRow(soundToggle, 28)
    table.insert(daChildRows, soundToggle)

    -- Sound dropdown
    local soundLabels     = {}
    local soundLabelToKey = {}
    local currentSoundLbl = db.sound or "readycheck"
    if SP.DeathAlert and SP.DeathAlert.Sounds then
        for _, s in ipairs(SP.DeathAlert.Sounds) do
            table.insert(soundLabels, s.label)
            soundLabelToKey[s.label] = s.key
            if s.key == (db.sound or "readycheck") then
                currentSoundLbl = s.label
            end
        end
    end
    -- Fallback labels when the module hasn't yet built the list (before PLAYER_LOGIN)
    if #soundLabels == 0 then
        soundLabels = { "Ready Check", "Decline", "Close", "Quest Abandon", "Error" }
        soundLabelToKey = {
            ["Ready Check"]  = "readycheck",
            ["Decline"]      = "decline",
            ["Close"]        = "close",
            ["Quest Abandon"] = "abandon",
            ["Error"]        = "error",
        }
        currentSoundLbl = soundLabelToKey[currentSoundLbl] and currentSoundLbl or "Ready Check"
    end

    local soundDropRow = GUI:CreateDropdown(parent, "Sound", soundLabels, currentSoundLbl,
        function(v)
            db.sound = soundLabelToKey[v] or "readycheck"
            ApplySettings()
        end)
    card3:AddRow(soundDropRow, 44)
    soundDropRow._isSoundChild = true
    table.insert(daChildRows, soundDropRow)
    table.insert(audioChildRows, soundDropRow)

    -- Sound preview button
    local sndPreviewWrap = CreateFrame("Frame", nil, parent)
    sndPreviewWrap:SetHeight(28)
    function sndPreviewWrap:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end
    local sndPreviewBtn = GUI:CreateButton(sndPreviewWrap, "Preview Sound", function()
        local key = db.sound or "readycheck"
        local kit
        if SP.DeathAlert and SP.DeathAlert.Sounds then
            for _, s in ipairs(SP.DeathAlert.Sounds) do
                if s.key == key then kit = s.kit; break end
            end
        end
        if kit then PlaySound(kit, "Master") end
    end, 140, 28)
    sndPreviewBtn:SetPoint("LEFT", sndPreviewWrap, "LEFT", 0, 0)
    card3:AddRow(sndPreviewWrap, 28)
    sndPreviewWrap._isSoundChild = true
    table.insert(daChildRows, sndPreviewWrap)
    table.insert(audioChildRows, sndPreviewWrap)

    card3:AddSeparator()

    -- TTS section
    local ttsToggle = GUI:CreateToggle(parent, "Text to Speech", db.playTTS,
        function(v)
            db.playTTS = v
            UpdateAudioChildState(db.playSound, v)
            ApplySettings()
        end)
    card3:AddRow(ttsToggle, 28)
    table.insert(daChildRows, ttsToggle)

    local ttsTextRow = MakeEditRow("TTS Text", db.ttsText or "{name} died", 80,
        function(v) db.ttsText = v; ApplySettings() end)
    card3:AddRow(ttsTextRow, 44)
    ttsTextRow._isTTSChild = true
    table.insert(daChildRows, ttsTextRow)
    table.insert(audioChildRows, ttsTextRow)
    card3:AddLabel("Use {name} as a placeholder for the player's name.", T.textMuted)

    local ttsVolRow = GUI:CreateSlider(parent, "TTS Volume", 0, 100, 5, db.ttsVolume or 50,
        function(v) db.ttsVolume = v; ApplySettings() end)
    card3:AddRow(ttsVolRow, 44)
    ttsVolRow._isTTSChild = true
    table.insert(daChildRows, ttsVolRow)
    table.insert(audioChildRows, ttsVolRow)

    y = y + card3:GetTotalHeight() + T.paddingSmall

    -- ── Card 4: Role Overrides (raid only) ────────────────────
    local card5 = GUI:CreateCard(parent, "Role Overrides", y)
    table.insert(daChildCards, card5)
    card5:AddLabel(
        "Per-role display and sound overrides, active only inside raids. These settings do not apply in parties.",
        T.textMuted)
    card5:AddSeparator()

    local ROLES = {
        { key = "TANK",    label = "Tank"   },
        { key = "HEALER",  label = "Healer" },
        { key = "DAMAGER", label = "DPS"    },
    }

    for _, roleInfo in ipairs(ROLES) do
        local rKey   = roleInfo.key
        local rLabel = roleInfo.label
        local byRole = db.byRole and db.byRole[rKey]
            or { showText = true, playSound = true }

        -- Ensure the subtable exists in db
        if db.byRole then
            db.byRole[rKey] = db.byRole[rKey] or { showText = true, playSound = true }
        end

        -- Role header label row
        local headerRow = CreateFrame("Frame", nil, parent)
        headerRow:SetHeight(20)
        local hLbl = headerRow:CreateFontString(nil, "OVERLAY")
        hLbl:SetPoint("LEFT", headerRow, "LEFT", 0, 0)
        ApplyFont(hLbl, 11)
        hLbl:SetText(rLabel)
        hLbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        function headerRow:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end
        card5:AddRow(headerRow, 20)
        table.insert(daChildRows, headerRow)

        local showToggle = GUI:CreateToggle(parent, "  " .. "Show Text",
            byRole.showText ~= false,
            function(v)
                if db.byRole and db.byRole[rKey] then
                    db.byRole[rKey].showText = v
                end
            end)
        card5:AddRow(showToggle, 28)
        table.insert(daChildRows, showToggle)

        local soundToggleRole = GUI:CreateToggle(parent, "  " .. "Play Sound",
            byRole.playSound ~= false,
            function(v)
                if db.byRole and db.byRole[rKey] then
                    db.byRole[rKey].playSound = v
                end
            end)
        card5:AddRow(soundToggleRole, 28)
        table.insert(daChildRows, soundToggleRole)

        if rKey ~= "DAMAGER" then card5:AddSeparator() end
    end

    y = y + card5:GetTotalHeight() + T.paddingSmall

    -- ── Card 6: Position ──────────────────────────────────────
    local card6 = GUI:CreateCard(parent, "Position", y)
    table.insert(daChildCards, card6)
    card6:AddLabel(
        "Click Preview to test the current look. Click Drag to Move to drag the frame anywhere on screen, then Lock Position when done. Fine-tune with the sliders below.",
        T.textMuted)
    card6:AddSeparator()

    -- Shared button style helper (border is handled separately via AnimateBorderFocus)
    local function StyleActionBtn(btn, isActive)
        if isActive then
            btn:SetBackdropColor(T.accent[1], T.accent[2], T.accent[3], 0.25)
            btn.lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        else
            btn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
            btn.lbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        end
    end

    -- ── Preview button (one-shot: fires the fade-in/out animation once, no toggle) ──
    local previewWrap = CreateFrame("Frame", nil, parent)
    previewWrap:SetHeight(28)
    function previewWrap:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end
    local previewBtn = GUI:CreateButton(previewWrap, "Preview Death Alert", nil, 140, 28)
    previewBtn:SetPoint("LEFT", previewWrap, "LEFT", 0, 0)
    previewBtn:SetScript("OnClick", function()
        if SP.DeathAlert then
            SP.DeathAlert.Preview()   -- fires the fade-in/out animation once; self-completing
        end
    end)
    -- ── Anchor + Strata ──────────────────────────────────────
    local daAnchorRow, daAnchorRowH = GUI:CreateAnchorRow(parent, db, ApplySettings,
        { default = "HIGH", onChange = function() ApplySettings() end })
    card6:AddRow(daAnchorRow, daAnchorRowH)
    table.insert(daChildRows, daAnchorRow)
    card6:AddSeparator()

    -- ── X / Y offsets — side by side ─────────────────────────
    local daXYHRow = GUI:CreateHRow(parent, 44)
    local xRow = GUI:CreateSlider(parent, "X Offset", -2000, 2000, 1, db.x or 0,
        function(v) db.x = v; ApplySettings() end)
    local yRow = GUI:CreateSlider(parent, "Y Offset", -2000, 2000, 1, db.y or 200,
        function(v) db.y = v; ApplySettings() end)
    daXYHRow:Add(xRow, 0.5)
    daXYHRow:Add(yRow, 0.5)
    card6:AddRow(daXYHRow, 44)
    table.insert(daChildRows, daXYHRow)

    -- Sync sliders when position is updated via drag
    if SP.DeathAlert then
        SP.DeathAlert._syncSliders = function(nx, ny)
            if xRow and xRow.SetValue then xRow.SetValue(nx) end
            if yRow and yRow.SetValue then yRow.SetValue(ny) end
        end
    end

    card6:AddSeparator()

    -- ── Preview + Drag to Move (below the anchor square) ─────
    card6:AddRow(previewWrap, 28)
    table.insert(daChildRows, previewWrap)

    card6:AddSeparator()

    local isDragging = false
    local dragWrap   = CreateFrame("Frame", nil, parent)
    dragWrap:SetHeight(28)
    function dragWrap:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end

    local dragBtn = GUI:CreateButton(dragWrap, "Drag to Move", nil, 140, 28)
    dragBtn:SetPoint("LEFT", dragWrap, "LEFT", 0, 0)

    local function UpdateDragBtn()
        if isDragging then
            dragBtn.lbl:SetText("Lock Position")
            StyleActionBtn(dragBtn, true)
        else
            dragBtn.lbl:SetText("Drag to Move")
            StyleActionBtn(dragBtn, false)
        end
        AnimateBorderFocus(dragBtn, isDragging)
    end

    dragBtn:SetScript("OnLeave", function() UpdateDragBtn() end)
    dragBtn:SetScript("OnClick", function()
        if isDragging then
            isDragging = false
            if SP.DeathAlert then SP.DeathAlert.EndDragMode() end
        else
            isDragging = true
            if SP.DeathAlert then SP.DeathAlert.StartDragMode() end
        end
        UpdateDragBtn()
    end)
    card6:AddRow(dragWrap, 28)
    table.insert(daChildRows, dragWrap)

    y = y + card6:GetTotalHeight() + T.paddingSmall

    -- Initial state
    UpdateDAChildState(db.enabled)
    UpdateAudioChildState(db.playSound, db.playTTS)

    parent:SetHeight(y)
end)


-- ============================================================
-- Group Joined Reminder page
-- ============================================================
GUI:RegisterContent("groupjoinedreminder", function(parent)
    local T  = SP.Theme
    local db = SP.GetDB().groupJoinedReminder

    local function ApplySettings()
        if SP.GroupJoinedReminder then SP.GroupJoinedReminder.Refresh() end
    end

    local y = 0

    local card1 = GUI:CreateCard(parent, "Group Joined Reminder", y)
    card1:AddLabel(
        "Prints a chat message when you join a Mythic or Mythic+ group via the group finder. Helps you know which group you accepted at a glance.",
        T.textMuted)
    card1:AddSeparator()

    local enableRow = GUI:CreateToggle(parent, "Enable Group Joined Reminder", db.enabled,
        function(v)
            db.enabled = v
            ApplySettings()
        end, "Group Joined Reminder")
    card1:AddRow(enableRow, 28)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    parent:SetHeight(y)
end)

GUI:RegisterContent("craftshopper", function(parent)
    local T  = SP.Theme
    local db = SP.GetDB().craftShopper

    local function ApplySettings()
        if SP.CraftShopper then SP.CraftShopper.Refresh() end
    end

    local y = 0

    local card1 = GUI:CreateCard(parent, "CraftShopper", y)
    card1:AddLabel(
        "Tracks your crafting recipe quantities and builds a shopping list of missing reagents. When the Auction House is open, the list appears beside it with per-item Search and Quick-Buy buttons.",
        T.textMuted)
    card1:AddSeparator()

    local enableRow = GUI:CreateToggle(parent, "Enable CraftShopper", db.enabled,
        function(v)
            db.enabled = v
            ApplySettings()
        end, "CraftShopper")
    card1:AddRow(enableRow, 28)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Performance
-- ============================================================
GUI:RegisterContent("performance", function(parent)
    local db = SP.GetDB().performance
    local y  = 0

    local function Refresh()
        if SP.Performance then SP.Performance.Refresh() end
    end

    -- Child cards fade when the module is disabled
    local perfChildCards = {}
    local perfEnableRow  -- forward-declared; used in UpdatePerfState closure
    local card0          -- forward-declared for UpdatePerfState closure
    local function UpdatePerfState(en)
        card0:GrayContent(en, perfEnableRow)
        for _, c in ipairs(perfChildCards) do c:SetAlpha(en and 1 or 0.4) end
    end

    -- ── Card 0: Enable toggle ──────────────────────────────
    card0 = GUI:CreateCard(parent, "Performance", y)
    card0:AddLabel(
        "Quest watch cleaner and auto combat-log clear. Enable the module to activate its sub-features.",
        T.textMuted)
    card0:AddSeparator()
    perfEnableRow = GUI:CreateToggle(parent, "Enable Performance module", db.enabled,
        function(v)
            db.enabled = v
            UpdatePerfState(v)
            Refresh()
        end, "Performance")
    card0:AddRow(perfEnableRow, 28)
    y = y + card0:GetTotalHeight() + T.paddingSmall

    -- ── Card 1: Quest Watch Cleaner ───────────────────────
    local card1 = GUI:CreateCard(parent, "Quest Watch Cleaner", y)
    card1:AddLabel(
        "WoW can silently track quests as phantom watches in the background even when they are hidden from your quest log. These ghost entries consume resources every frame and can noticeably hurt FPS. Click the button below to print all tracked entries to chat and remove every watch in one shot.",
        T.textMuted)
    card1:AddSeparator()

    -- Action button row
    local btnRow = CreateFrame("Frame", nil, parent)
    btnRow:SetHeight(32)

    local btn = GUI:CreateButton(btnRow, "Print & clear quest watches", nil, 200, 26)
    btn:SetPoint("LEFT", btnRow, "LEFT", 0, 0)

    -- Feedback label: appears to the right of the button after click, fades after 3s
    local feedbackLbl = btnRow:CreateFontString(nil, "OVERLAY")
    feedbackLbl:SetPoint("LEFT", btn, "RIGHT", 10, 0)
    ApplyFont(feedbackLbl, 11)
    feedbackLbl:SetAlpha(0)

    local qwFeedbackTimer
    btn:SetScript("OnClick", function()
        if SP.Performance then SP.Performance.ClearQuestWatches() end
        local acHex = string.format("|cff%02x%02x%02x",
            math.floor((T.accent[1] or 0) * 255),
            math.floor((T.accent[2] or 0) * 255),
            math.floor((T.accent[3] or 0) * 255))
        feedbackLbl:SetText(acHex .. "Quest log|r  |cffffffff CLEANED|r")
        feedbackLbl:SetAlpha(1)
        if qwFeedbackTimer then qwFeedbackTimer:Cancel() end
        qwFeedbackTimer = C_Timer.NewTimer(3, function() feedbackLbl:SetAlpha(0) end)
    end)

    card1:AddRow(btnRow, 32)
    table.insert(perfChildCards, card1)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- ── Card 2: Auto Clear Combat Log ─────────────────────
    local card2 = GUI:CreateCard(parent, "Auto Clear Combat Log", y)
    card2:AddLabel(
        "The combat log accumulates entries throughout your session and can weigh on FPS over time. This option calls |cffffffffCombatLogClearEntries()|r automatically on every login so you always start with a clean log.",
        T.textMuted)
    card2:AddSeparator()

    local toggleRow = GUI:CreateToggle(parent, "Clear combat log on login", db.autoClearCombatLog,
        function(v)
            db.autoClearCombatLog = v
            Refresh()
        end)
    card2:AddRow(toggleRow, 28)

    local clearNowWrap = CreateFrame("Frame", nil, parent)
    clearNowWrap:SetHeight(32)
    local clearNowBtn = GUI:CreateButton(clearNowWrap, "Clear Combat Log", nil, 200, 26)
    clearNowBtn:SetPoint("LEFT", clearNowWrap, "LEFT", 0, 0)
    local clFeedbackLbl = clearNowWrap:CreateFontString(nil, "OVERLAY")
    clFeedbackLbl:SetPoint("LEFT", clearNowBtn, "RIGHT", 10, 0)
    ApplyFont(clFeedbackLbl, 11)
    clFeedbackLbl:SetAlpha(0)
    local clFeedbackTimer
    clearNowBtn:SetScript("OnClick", function()
        CombatLogClearEntries()
        local acHex = string.format("|cff%02x%02x%02x",
            math.floor((T.accent[1] or 0) * 255),
            math.floor((T.accent[2] or 0) * 255),
            math.floor((T.accent[3] or 0) * 255))
        clFeedbackLbl:SetText(acHex .. "Combat log|r  |cffffffff CLEARED|r")
        clFeedbackLbl:SetAlpha(1)
        if clFeedbackTimer then clFeedbackTimer:Cancel() end
        clFeedbackTimer = C_Timer.NewTimer(3, function() clFeedbackLbl:SetAlpha(0) end)
    end)
    card2:AddRow(clearNowWrap, 32)

    table.insert(perfChildCards, card2)
    y = y + card2:GetTotalHeight() + T.paddingSmall

    -- Apply initial state
    UpdatePerfState(db.enabled)

    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Enhanced Objective Text
-- ============================================================
GUI:RegisterContent("enhancedobjectivetext", function(parent)
    local db = SP.GetDB().enhancedObjectiveText
    local y  = 0

    local function Refresh()
        if SP.EnhancedObjectiveText then SP.EnhancedObjectiveText.Refresh() end
    end

    local eotChildCards = {}
    local eotEnableRow   -- forward-declared; used in UpdateEOTState closure
    local card1          -- forward-declared for UpdateEOTState closure
    local function UpdateEOTState(en)
        card1:GrayContent(en, eotEnableRow)
        for _, c in ipairs(eotChildCards) do c:SetAlpha(en and 1 or 0.4) end
    end

    card1 = GUI:CreateCard(parent, "Enhanced Objective & Error Text", y)
    card1:AddLabel(
        "Replaces WoW's default small stacked error/objective messages with a single large centred line. Spell errors, objective completions and system notices are easier to read at a glance during combat.",
        T.textMuted)
    card1:AddSeparator()
    eotEnableRow = GUI:CreateToggle(parent, "Enable Enhanced Objective Text", db.enabled,
        function(v)
            db.enabled = v
            UpdateEOTState(v)
            Refresh()
        end, "Enhanced Objective Text")
    card1:AddRow(eotEnableRow, 28)

    card1:AddSeparator()

    local previewWrap = CreateFrame("Frame", nil, parent)
    previewWrap:SetHeight(28)
    local previewBtn = GUI:CreateButton(previewWrap, "Preview", nil, 140, 28)
    previewBtn:SetPoint("LEFT", previewWrap, "LEFT", 0, 0)
    previewBtn:SetScript("OnClick", function()
        if SP.EnhancedObjectiveText then SP.EnhancedObjectiveText.Preview() end
    end)
    card1:AddRow(previewWrap, 28)

    y = y + card1:GetTotalHeight() + T.paddingSmall

    local card2 = GUI:CreateCard(parent, "Appearance", y)
    card2:AddLabel("Adjust the font size and vertical position of the on-screen text.", T.textMuted)
    card2:AddSeparator()
    local eotSizeRow = GUI:CreateSlider(parent, "Font Size", 14, 40, 1, db.fontSize or 22,
        function(v)
            db.fontSize = v
            Refresh()
        end)
    card2:AddRow(eotSizeRow, 36)
    local eotYRow = GUI:CreateSlider(parent, "Vertical Position", -400, 400, 1, db.y or 0,
        function(v)
            db.y = v
            Refresh()
        end)
    card2:AddRow(eotYRow, 36)
    table.insert(eotChildCards, card2)
    y = y + card2:GetTotalHeight() + T.paddingSmall

    UpdateEOTState(db.enabled)
    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Clean Objective Tracker Header
-- ============================================================
GUI:RegisterContent("cleanobjectivetrackerheader", function(parent)
    local db = SP.GetDB().cleanObjectiveTrackerHeader
    local y  = 0

    local function Refresh()
        if SP.CleanObjectiveTrackerHeader then SP.CleanObjectiveTrackerHeader.Refresh() end
    end

    local card1 = GUI:CreateCard(parent, "Clean Objective Tracker Header", y)
    card1:AddLabel(
        "Hides the \"Objectives\" title line at the top of the quest tracker on the left side of the screen, saving one line of vertical space.",
        T.textMuted)
    card1:AddSeparator()
    card1:AddRow(GUI:CreateToggle(parent, "Hide tracker header", db.enabled,
        function(v)
            db.enabled = v
            Refresh()
        end, "Clean Objective Header"), 28)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    parent:SetHeight(y)
end)

-- ============================================================
-- Silvermoon Map Icons
-- ============================================================
GUI:RegisterContent("silvermoonmapicon", function(parent)
    local T  = SP.Theme
    local db = SP.GetDB().silvermoonMapIcon

    local function ApplySettings()
        if SP.SilvermoonMapIcon then SP.SilvermoonMapIcon.Refresh() end
    end

    local function ApplyPinSettings()
        if SP.SilvermoonMapIcon then SP.SilvermoonMapIcon.RefreshPins() end
    end

    local y = 0

    -- Main toggle card
    local card1 = GUI:CreateCard(parent, "Silvermoon Map Icons", y)
    card1:AddLabel(
        "Adds POI pins to the Silvermoon City world map — profession trainers, Auction House, Bank, Transmogrifier, Catalyst, Crafting Orders and more. Left-click any pin to place a waypoint. Pins are only visible when Silvermoon City is the active map.",
        T.textMuted)
    card1:AddSeparator()

    local enableRow = GUI:CreateToggle(parent, "Enable Map Icons", db.enabled,
        function(v)
            db.enabled = v
            ApplySettings()
        end, "Silvermoon Map Icons")
    card1:AddRow(enableRow, 28)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- Filter card
    local card2 = GUI:CreateCard(parent, "Filter", y)
    card2:AddLabel(
        "When enabled, profession trainer pins are only shown for professions your character has actually learned. Disable to show all trainers.",
        T.textMuted)
    card2:AddSeparator()

    local proOnlyRow = GUI:CreateToggle(parent, "Show only learned professions", db.showOnlyProfessions,
        function(v)
            db.showOnlyProfessions = v
            ApplyPinSettings()
        end, "Filter")
    card2:AddRow(proOnlyRow, 28)
    y = y + card2:GetTotalHeight() + T.paddingSmall

    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Gateway Alert
-- ============================================================
GUI:RegisterContent("gatewayalert", function(parent)
    local db = SP.GetDB().gatewayAlert
    local T  = SP.Theme
    local y  = 0

    local gaChildRows  = {}
    local gaChildCards = {}
    local gaEnRow      -- forward-declared; used in UpdateGAState closure
    local card1        -- forward-declared for UpdateGAState closure

    local function ApplySettings()
        if SP.GatewayAlert then SP.GatewayAlert:ApplySettings() end
        GUI.UpdateSidebarCheckmarks()
    end

    local function UpdateGAState(en)
        card1:GrayContent(en, gaEnRow)
        for _, r in ipairs(gaChildRows)  do r:SetEnabled(en) end
        for _, c in ipairs(gaChildCards) do c:SetAlpha(en and 1 or 0.4) end
    end

    -- ── Card 1: Enable ──────────────────────────────────────
    card1 = GUI:CreateCard(parent, "Gateway Alert", y)
    card1:AddLabel(
        "Displays a flashing text alert when your Demonic Gateway item is ready to use (item 188152).",
        T.textMuted)
    card1:AddSeparator()

    gaEnRow = GUI:CreateToggle(parent, "Enable Gateway Alert",
        db.enabled or false,
        function(v)
            db.enabled = v
            UpdateGAState(v)
            ApplySettings()
            if SP.GatewayAlert then SP.GatewayAlert.Refresh() end
            local ac  = SP.Theme.accent
            local hex = string.format("%02X%02X%02X",
                math.floor(ac[1]*255+0.5), math.floor(ac[2]*255+0.5), math.floor(ac[3]*255+0.5))
            SP.ShowNotification("|cff"..hex.."Gateway Alert :|r " .. (v and "On" or "Off"))
        end)
    card1:AddRow(gaEnRow, 28)

    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- ── Card 2: Appearance ──────────────────────────────────
    local card2 = GUI:CreateCard(parent, "Appearance", y)
    card2:AddLabel("Customise the font, size, and colour of the gateway alert text.", T.textMuted)
    card2:AddSeparator()
    table.insert(gaChildCards, card2)

    -- Font Face (full width)
    local gaFontFaceRow = GUI:CreateFontDropdown(parent, "Font Face",
        db.fontFace or "Expressway",
        function(v) db.fontFace = v; ApplySettings() end)
    card2:AddRow(gaFontFaceRow, 44)
    table.insert(gaChildRows, gaFontFaceRow)
    card2:AddSeparator()

    -- Font Size + Outline on same row
    local gaFontHRow = GUI:CreateHRow(parent, 44)
    local gaFontSzRow = GUI:CreateSlider(parent, "Font Size", 8, 32, 1, db.fontSize or 16,
        function(v) db.fontSize = v; ApplySettings() end)
    local gaOutlineRow = GUI:CreateDropdown(parent, "Outline",
        { "NONE", "OUTLINE", "THICKOUTLINE" },
        db.fontOutline or "OUTLINE",
        function(v) db.fontOutline = v; ApplySettings() end)
    gaFontHRow:Add(gaFontSzRow, 0.55)
    gaFontHRow:Add(gaOutlineRow, 0.45)
    card2:AddRow(gaFontHRow, 44)
    table.insert(gaChildRows, gaFontHRow)

    -- Text Color with source dropdown
    card2:AddSeparator()
    local gaColorSrcRow, gaColorSwRow = GUI:CreateColorWithSource(
        parent, "Text Color", db, "colorSource", "color", { 0.3, 1.0, 0.4 },
        function() ApplySettings() end)
    card2:AddRow(gaColorSrcRow, 44)
    table.insert(gaChildRows, gaColorSrcRow)
    card2:AddSeparator()
    card2:AddRow(gaColorSwRow, 52)
    table.insert(gaChildRows, gaColorSwRow)

    y = y + card2:GetTotalHeight() + T.paddingSmall

    -- ── Card 3: Position ────────────────────────────────────
    local card3 = GUI:CreateCard(parent, "Position", y)
    table.insert(gaChildCards, card3)

    local gaAnchorRow, gaAnchorRowH = GUI:CreateAnchorRow(parent, db, ApplySettings,
        { default = "HIGH", onChange = function() ApplySettings() end })
    card3:AddRow(gaAnchorRow, gaAnchorRowH)
    table.insert(gaChildRows, gaAnchorRow)
    card3:AddSeparator()

    local gaXYHRow = GUI:CreateHRow(parent, 44)
    local gaXRow = GUI:CreateSlider(parent, "X Offset", -2000, 2000, 1, db.x or 0,
        function(v) db.x = v; ApplySettings() end)
    local gaYRow = GUI:CreateSlider(parent, "Y Offset", -2000, 2000, 1, db.y or -100,
        function(v) db.y = v; ApplySettings() end)
    gaXYHRow:Add(gaXRow, 0.5)
    gaXYHRow:Add(gaYRow, 0.5)
    card3:AddRow(gaXYHRow, 44)
    table.insert(gaChildRows, gaXYHRow)
    card3:AddSeparator()

    -- Preview + Drag buttons
    local function StyleGABtn(btn, isActive)
        if isActive then
            btn:SetBackdropColor(T.accent[1], T.accent[2], T.accent[3], 0.25)
            btn.lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        else
            btn:SetBackdropColor(T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)
            btn.lbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        end
    end

    local gaPreviewActive = false
    local gaPrevWrap = CreateFrame("Frame", nil, parent)
    gaPrevWrap:SetHeight(28)
    function gaPrevWrap:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end

    local gaPrevBtn = GUI:CreateButton(gaPrevWrap, "Preview", nil, 140, 28)
    gaPrevBtn:SetPoint("LEFT", gaPrevWrap, "LEFT", 0, 0)

    local function UpdateGAPrevBtn()
        StyleGABtn(gaPrevBtn, gaPreviewActive)
        gaPrevBtn.lbl:SetText(gaPreviewActive and "Stop Preview" or "Preview")
        AnimateBorderFocus(gaPrevBtn, gaPreviewActive)
    end

    gaPrevBtn:SetScript("OnLeave", function() UpdateGAPrevBtn() end)
    gaPrevBtn:SetScript("OnClick", function()
        gaPreviewActive = not gaPreviewActive
        if gaPreviewActive then
            if SP.GatewayAlert then SP.GatewayAlert:ShowPreview() end
        else
            if SP.GatewayAlert then SP.GatewayAlert:HidePreview() end
        end
        UpdateGAPrevBtn()
    end)
    card3:AddRow(gaPrevWrap, 28)
    table.insert(gaChildRows, gaPrevWrap)
    card3:AddSeparator()

    local gaDragActive = false
    local gaDragWrap = CreateFrame("Frame", nil, parent)
    gaDragWrap:SetHeight(28)
    function gaDragWrap:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end

    local gaDragBtn = GUI:CreateButton(gaDragWrap, "Drag to Move", nil, 140, 28)
    gaDragBtn:SetPoint("LEFT", gaDragWrap, "LEFT", 0, 0)

    if SP.GatewayAlert then
        SP.GatewayAlert._syncSliders = function(nx, ny)
            if gaXRow.SetValue then gaXRow:SetValue(nx) end
            if gaYRow.SetValue then gaYRow:SetValue(ny) end
            db.x = nx; db.y = ny
        end
    end

    local function UpdateGADragBtn()
        StyleGABtn(gaDragBtn, gaDragActive)
        gaDragBtn.lbl:SetText(gaDragActive and "Stop Moving" or "Drag to Move")
        AnimateBorderFocus(gaDragBtn, gaDragActive)
    end

    gaDragBtn:SetScript("OnLeave", function() UpdateGADragBtn() end)
    gaDragBtn:SetScript("OnClick", function()
        gaDragActive = not gaDragActive
        if gaDragActive then
            if SP.GatewayAlert then SP.GatewayAlert:StartDragMode() end
        else
            if SP.GatewayAlert then SP.GatewayAlert:EndDragMode() end
        end
        UpdateGADragBtn()
    end)
    card3:AddRow(gaDragWrap, 28)
    table.insert(gaChildRows, gaDragWrap)

    y = y + card3:GetTotalHeight() + T.paddingSmall

    -- Apply initial grey state
    UpdateGAState(db.enabled)

    -- Cleanup preview/drag when navigating away (GatewayAlert.frame is parented to
    -- UIParent, so hiding the page container does NOT hide it automatically).
    parent:HookScript("OnHide", function()
        if gaPreviewActive then
            gaPreviewActive = false
            if SP.GatewayAlert then SP.GatewayAlert:HidePreview() end
            UpdateGAPrevBtn()
        end
        if gaDragActive then
            gaDragActive = false
            if SP.GatewayAlert then SP.GatewayAlert:EndDragMode() end
            UpdateGADragBtn()
        end
    end)

    parent:SetHeight(y)
end)

-- ============================================================
-- Page: Whisper Alert
-- ============================================================
GUI:RegisterContent("whisperalert", function(parent)
    local db = SP.GetDB().whisperAlert
    local T  = SP.Theme
    local y  = 0

    local waChildRows  = {}
    local waChildCards = {}
    local enableRow    -- forward-declared; used in UpdateWAState closure
    local card1        -- forward-declared for UpdateWAState closure

    local function ApplySettings()
        if SP.WhisperAlert then SP.WhisperAlert.Refresh() end
        GUI.UpdateSidebarCheckmarks()
    end

    local function UpdateWAState(en)
        card1:GrayContent(en, enableRow)
        for _, r in ipairs(waChildRows)  do r:SetEnabled(en) end
        for _, c in ipairs(waChildCards) do c:SetAlpha(en and 1 or 0.4) end
    end

    -- Build sorted LSM sound list with "None" first
    local soundNames = {}
    do
        local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
        if lsm then
            for name in pairs(lsm:HashTable("sound")) do
                table.insert(soundNames, name)
            end
            table.sort(soundNames)
        end
        for i, v in ipairs(soundNames) do
            if v == "None" then table.remove(soundNames, i); break end
        end
        table.insert(soundNames, 1, "None")
    end

    -- Helper: create an inline "▶ Preview" button and attach it to a dropdown row.
    -- Also overrides the row's SetEnabled to keep the button in sync.
    local function AttachPreviewBtn(dropRow, soundKey)
        local btn = CreateFrame("Button", nil, dropRow, "BackdropTemplate")
        btn:SetSize(52, 22)
        btn:SetPoint("TOPLEFT", dropRow, "TOPLEFT", 208, -16)
        SetBackdrop(btn, T.bgMedium[1], T.bgMedium[2], T.bgMedium[3], 1)

        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetAllPoints(); ApplyFont(lbl, 11)
        lbl:SetText("Preview")
        lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)

        btn:SetScript("OnEnter", function()
            if not btn:IsMouseEnabled() then return end
            AnimateBorderFocus(btn, true)
        end)
        btn:SetScript("OnLeave", function() AnimateBorderFocus(btn, false) end)
        btn:SetScript("OnClick", function()
            local soundName = db[soundKey]
            if not soundName or soundName == "None" then return end
            local lsm  = LibStub and LibStub("LibSharedMedia-3.0", true)
            local file = lsm and lsm:Fetch("sound", soundName)
            if file then PlaySoundFile(file, db.channel or "Master") end
        end)

        -- Override the dropdown row's SetEnabled to keep preview btn in sync
        local _orig = dropRow.SetEnabled
        function dropRow:SetEnabled(en)
            _orig(self, en)
            btn:EnableMouse(en)
            btn:SetAlpha(en and 1 or 0.4)
        end

        return btn
    end

    -- ── Card 1: Enable ──────────────────────────────────────
    card1 = GUI:CreateCard(parent, "Whisper Alert", y)
    card1:AddLabel("Plays a sound when you receive a whisper or a Battle.net message.", T.textMuted)
    card1:AddSeparator()

    enableRow = GUI:CreateToggle(parent, "Enable Whisper Alert",
        db.enabled or false,
        function(v)
            db.enabled = v
            ApplySettings()
            UpdateWAState(v)
            local ac  = SP.Theme.accent
            local hex = string.format("%02X%02X%02X",
                math.floor(ac[1]*255+0.5), math.floor(ac[2]*255+0.5), math.floor(ac[3]*255+0.5))
            SP.ShowNotification("|cff"..hex.."Whisper Alert :|r " .. (v and "On" or "Off"))
        end)
    card1:AddRow(enableRow, 28)

    local muteRow = GUI:CreateToggle(parent, "Mute while in combat",
        db.muteInCombat or false,
        function(v) db.muteInCombat = v end)
    card1:AddRow(muteRow, 28)
    table.insert(waChildRows, muteRow)
    card1:AddLabel("Suppresses the alert while actively in combat.", T.textMuted)

    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- ── Card 2: Sound Selection ──────────────────────────────
    local card2 = GUI:CreateCard(parent, "Sound Selection", y)
    card2:AddLabel("Choose which sounds play on incoming whispers and Battle.net messages.", T.textMuted)
    card2:AddSeparator()
    table.insert(waChildCards, card2)

    -- Whisper Sound dropdown + inline preview button
    local wSoundRow = GUI:CreateDropdown(parent, "Whisper Sound",
        soundNames, db.sound or "None",
        function(v) db.sound = v end)
    card2:AddRow(wSoundRow, 44)
    table.insert(waChildRows, wSoundRow)
    AttachPreviewBtn(wSoundRow, "sound")

    card2:AddSeparator()

    -- Battle.net Sound dropdown + inline preview button
    local bSoundRow = GUI:CreateDropdown(parent, "Battle.net Sound",
        soundNames, db.bnetSound or "None",
        function(v) db.bnetSound = v end)
    card2:AddRow(bSoundRow, 44)
    table.insert(waChildRows, bSoundRow)
    AttachPreviewBtn(bSoundRow, "bnetSound")

    card2:AddSeparator()

    -- Audio Channel dropdown
    local chLabels = { "Master", "Music", "SFX", "Ambience", "Dialog" }
    local chRow = GUI:CreateDropdown(parent, "Audio Channel",
        chLabels, db.channel or "Master",
        function(v) db.channel = v end)
    card2:AddRow(chRow, 44)
    table.insert(waChildRows, chRow)
    card2:AddLabel("Both sounds play through the same channel.", T.textMuted)

    y = y + card2:GetTotalHeight() + T.paddingSmall

    -- Apply initial greyed state
    UpdateWAState(db.enabled)

    parent:SetHeight(y)
end)

-- ============================================================
-- Auto Buy page
-- ============================================================
GUI:RegisterContent("autobuy", function(parent)
    local T  = SP.Theme
    local db = SP.GetCharDB().autoBuy

    -- Expressway via LSM, bundled path as fallback
    local FONT = SP.GetFontPath("Expressway")
              or "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"

    local function ApplySettings()
        if SP.AutoBuy then SP.AutoBuy.Refresh() end
    end

    local y = 0
    local childRows = {}
    local enableRow -- forward-declared; used in UpdateChildState closure
    local card1     -- forward-declared for UpdateChildState closure
    local function UpdateChildState(en)
        card1:GrayContent(en, enableRow)
        for _, r in ipairs(childRows) do r:SetEnabled(en) end
    end

    -- ── Helpers ───────────────────────────────────────────────

    -- Small checkbox (22x22) accent-filled when checked
    local function MakeCheckbox(parentFrame, initial, onChange)
        local btn = CreateFrame("Button", nil, parentFrame, "BackdropTemplate")
        btn:SetSize(22, 22)
        btn:EnableMouse(true)
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        local checked = initial
        -- Use WoW's built-in checkbox texture (font-independent)
        local checkTex = btn:CreateTexture(nil, "OVERLAY")
        checkTex:SetPoint("TOPLEFT",     btn, "TOPLEFT",     2, -2)
        checkTex:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2,  2)
        checkTex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        checkTex:SetVertexColor(T.accent[1], T.accent[2], T.accent[3], 1)
        local isHovered = false
        local function Refresh()
            if checked then
                btn:SetBackdropColor(
                    T.accent[1]*(isHovered and 0.6 or 0.4),
                    T.accent[2]*(isHovered and 0.6 or 0.4),
                    T.accent[3]*(isHovered and 0.6 or 0.4), 1)
                btn:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1)
                checkTex:Show()
            else
                btn:SetBackdropColor(isHovered and 0.18 or T.bgDark[1],
                                     isHovered and 0.18 or T.bgDark[2],
                                     isHovered and 0.18 or T.bgDark[3], 1)
                btn:SetBackdropBorderColor(
                    T.border[1]+(isHovered and 0.15 or 0),
                    T.border[2]+(isHovered and 0.15 or 0),
                    T.border[3]+(isHovered and 0.15 or 0), 1)
                checkTex:Hide()
            end
        end
        Refresh()
        btn:SetScript("OnClick", function()
            checked = not checked
            onChange(checked)
            Refresh()
        end)
        btn:SetScript("OnEnter", function()
            isHovered = true
            Refresh()
        end)
        btn:SetScript("OnLeave", function()
            isHovered = false
            Refresh()
        end)
        return btn
    end

    -- Item icon frame (34x34) with async load via GET_ITEM_INFO_RECEIVED
    local function MakeItemIcon(parentFrame, itemId)
        local border = CreateFrame("Frame", nil, parentFrame, "BackdropTemplate")
        border:SetSize(34, 34)
        border:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        border:SetBackdropColor(0.05, 0.05, 0.05, 1)
        border:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.8)
        local tex = border:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT",     border, "TOPLEFT",     2, -2)
        tex:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -2, 2)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local function TrySetIcon()
            local _, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
            if icon then tex:SetTexture(icon); return true end
            return false
        end
        if not TrySetIcon() then
            tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            C_Item.RequestLoadItemDataByID(itemId)
            border:RegisterEvent("GET_ITEM_INFO_RECEIVED")
            border:SetScript("OnEvent", function(self, _, id)
                if id == itemId and TrySetIcon() then
                    self:UnregisterAllEvents()
                    self:SetScript("OnEvent", nil)
                end
            end)
        end
        -- Tooltip on hover
        border:EnableMouse(true)
        border:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(itemId)
            GameTooltip:Show()
        end)
        border:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        return border
    end

    -- Numeric editbox
    local function MakeNumBox(parentFrame, w, value, minV, maxV, onSet)
        local box = CreateFrame("EditBox", nil, parentFrame, "BackdropTemplate")
        box:SetSize(w, 22)
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetMaxLetters(5)
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        box:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 1)
        box:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 1)
        box:SetTextInsets(4, 4, 0, 0)
        box:SetFont(FONT, 11, "")
        box:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        box:SetJustifyH("CENTER")
        box:SetText(tostring(value))
        box:SetScript("OnEnterPressed", function(self)
            local v = math.max(minV, math.min(maxV, tonumber(self:GetText()) or value))
            self:SetText(tostring(v))
            self:ClearFocus()
            onSet(v)
        end)
        box:SetScript("OnEscapePressed", function(self)
            self:SetText(tostring(value))
            self:ClearFocus()
        end)
        return box
    end

    -- Quality toggle: two adjacent icon buttons, Q1 = 1-star, Q2 = 5-star chat quality icons.
    -- Selected button sits "above" (larger, fully opaque, bright border).
    -- Unselected button is dimmed and slightly smaller.
    -- onChanged(q) fires after the active quality changes.
    local function MakeQualityToggle(parentFrame, entry, preset, onChanged)
        if not preset or not preset.q2 then return nil end

        -- Left (q=1) = 1-star (Tier1) → quality=1 (Q1 buy)
        -- Right (q=2) = 5-star (Tier5) → quality=2 (Q2 buy)
        -- Default quality=2 → right button active (big gold)
        local IDS = { [1] = preset.id, [2] = preset.q2 }
        local ATLASES = {
            [1] = "Professions-Chaticon-Quality-Tier1",
            [2] = "Professions-Chaticon-Quality-Tier5",
        }

        -- Container is wide enough for two buttons with a 2px gap
        local BTN_W, BTN_H = 22, 22
        local container = CreateFrame("Frame", nil, parentFrame)
        container:SetSize(BTN_W * 2 + 2, BTN_H)

        -- Returns which button index (1=left, 2=right) should be highlighted.
        local function ActiveBtnIdx()
            return (entry.quality == 2) and 2 or 1
        end

        local function Refresh(activeQ, hoveredQ)
            for q = 1, 2 do
                local btn = container["btn"..q]
                local isActive  = (q == activeQ)
                local isHovered = (q == hoveredQ)

                if isActive then
                    -- Selected: raised frame level, full-size button, gold border
                    btn:SetFrameLevel(container:GetFrameLevel() + 3)
                    btn:SetSize(BTN_W, BTN_H)
                    btn:SetBackdropColor(0.14, 0.11, 0.03, 1)
                    btn:SetBackdropBorderColor(0.95, 0.80, 0.25, 1)
                    btn._icon:SetVertexColor(1, 1, 1, 1)
                    btn._icon:SetAlpha(1)
                    btn._icon:SetSize(18, 18)
                elseif isHovered then
                    -- Hovered inactive: slightly lifted, partial gold
                    btn:SetFrameLevel(container:GetFrameLevel() + 2)
                    btn:SetSize(BTN_W, BTN_H)
                    btn:SetBackdropColor(0.12, 0.10, 0.04, 1)
                    btn:SetBackdropBorderColor(0.95, 0.80, 0.25, 0.55)
                    btn._icon:SetVertexColor(1, 1, 1, 1)
                    btn._icon:SetAlpha(0.80)
                    btn._icon:SetSize(16, 16)
                else
                    -- Inactive: base level, dimmed
                    btn:SetFrameLevel(container:GetFrameLevel() + 1)
                    btn:SetSize(BTN_W - 2, BTN_H - 2)
                    btn:SetBackdropColor(T.bgDark[1], T.bgDark[2], T.bgDark[3], 1)
                    btn:SetBackdropBorderColor(T.border[1], T.border[2], T.border[3], 0.35)
                    btn._icon:SetVertexColor(0.5, 0.5, 0.5, 1)
                    btn._icon:SetAlpha(0.45)
                    btn._icon:SetSize(13, 13)
                end
            end
        end

        for q = 1, 2 do
            local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
            btn:SetSize(BTN_W, BTN_H)
            btn:SetBackdrop({ bgFile   = "Interface\\Buttons\\WHITE8X8",
                              edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            btn:SetPoint(
                q == 1 and "LEFT"  or "RIGHT",
                container,
                q == 1 and "LEFT"  or "RIGHT",
                0, 0)

            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
            icon:SetAtlas(ATLASES[q], false)
            btn._icon = icon

            btn:SetScript("OnEnter", function()
                Refresh(ActiveBtnIdx(), q)
                GameTooltip:SetOwner(btn, "ANCHOR_TOP")
                GameTooltip:SetItemByID(IDS[q])
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function()
                Refresh(ActiveBtnIdx(), nil)
                GameTooltip:Hide()
            end)
            btn:SetScript("OnClick", function()
                -- Left (q=1) → quality=1,  Right (q=2) → quality=2
                entry.quality = q
                Refresh(q, nil)
                if onChanged then onChanged(q) end
            end)

            container["btn"..q] = btn
        end

        Refresh(ActiveBtnIdx(), nil)
        return container
    end

    -- Item row: [Icon 34] [Name / ID subtext] ... [Q toggle 62?] [BUY QTY 50] [MIN QTY 50] [cb 22] ([X 22])
    local ITEM_ROW_H = 42
    local function MakeItemRow(itemId, itemName, entry, defaultQty, onRemove, preset)
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(ITEM_ROW_H)
        function row:SetEnabled(en) self:SetAlpha(en and 1 or 0.4) end

        -- Icon
        local iconF = MakeItemIcon(row, itemId)
        iconF:SetPoint("LEFT", row, "LEFT", 0, 0)

        -- Optional remove button (far right, custom items only)
        local rmBtn
        if onRemove then
            rmBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
            rmBtn:SetSize(22, 22)
            rmBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            rmBtn:EnableMouse(true)
            rmBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            rmBtn:SetBackdropColor(0.45, 0.08, 0.08, 1)
            rmBtn:SetBackdropBorderColor(0.75, 0.18, 0.18, 1)
            -- Use WoW's close/X texture (font-independent)
            local rmTex = rmBtn:CreateTexture(nil, "OVERLAY")
            rmTex:SetPoint("TOPLEFT",     rmBtn, "TOPLEFT",     3, -3)
            rmTex:SetPoint("BOTTOMRIGHT", rmBtn, "BOTTOMRIGHT", -3,  3)
            rmTex:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
            rmTex:SetVertexColor(1, 0.45, 0.45, 1)
            rmBtn:SetScript("OnEnter", function(self)
                self:SetBackdropColor(0.65, 0.12, 0.12, 1)
                self:SetBackdropBorderColor(1, 0.3, 0.3, 1)
                rmTex:SetVertexColor(1, 0.8, 0.8, 1)
            end)
            rmBtn:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0.45, 0.08, 0.08, 1)
                self:SetBackdropBorderColor(0.75, 0.18, 0.18, 1)
                rmTex:SetVertexColor(1, 0.45, 0.45, 1)
            end)
            rmBtn:SetScript("OnClick", function()
                onRemove()
                row:Hide()
            end)
        end

        -- Forward declare visuals so RefreshRowVisual can close over them
        -- even though they're assigned after the checkbox.
        local nameTxtRef, idTxtRef, qualToggleRef

        local function RefreshRowVisual(en)
            iconF:SetAlpha(en and 1 or 0.30)
            if nameTxtRef then
                if en then
                    nameTxtRef:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
                else
                    nameTxtRef:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.45)
                end
            end
            if idTxtRef then
                idTxtRef:SetAlpha(en and 1 or 0.30)
            end
            if qualToggleRef then
                qualToggleRef:SetAlpha(en and 1 or 0.30)
            end
        end

        -- Checkbox: RIGHT of row:RIGHT (preset) or LEFT of rmBtn (custom)
        local cb = MakeCheckbox(row, entry.enabled, function(v)
            entry.enabled = v
            RefreshRowVisual(v)
        end)
        if rmBtn then
            cb:SetPoint("RIGHT", rmBtn, "LEFT", -4, 0)
        else
            cb:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        end

        -- MIN QTY editbox (trigger threshold — left of checkbox)
        local qtyBox = MakeNumBox(row, 32, entry.quantity or defaultQty, 0, 9999,
            function(v) entry.quantity = v end)
        qtyBox:SetPoint("RIGHT", cb, "LEFT", -6, 0)

        -- "MIN QTY" caption above qty box
        local qtyLbl = row:CreateFontString(nil, "OVERLAY")
        qtyLbl:SetFont(FONT, 9, "")
        qtyLbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
        qtyLbl:SetText("MIN QTY")
        qtyLbl:SetJustifyH("CENTER")
        qtyLbl:SetPoint("BOTTOM", qtyBox, "TOP", 0, 2)

        -- BUY QTY editbox (purchase amount — left of MIN QTY box)
        local buyQtyBox = MakeNumBox(row, 32, entry.buyQty or defaultQty, 1, 9999,
            function(v) entry.buyQty = v end)
        buyQtyBox:SetPoint("RIGHT", qtyBox, "LEFT", -6, 0)

        -- "BUY QTY" caption above buy qty box
        local buyQtyLbl = row:CreateFontString(nil, "OVERLAY")
        buyQtyLbl:SetFont(FONT, 9, "")
        buyQtyLbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
        buyQtyLbl:SetText("BUY QTY")
        buyQtyLbl:SetJustifyH("CENTER")
        buyQtyLbl:SetPoint("BOTTOM", buyQtyBox, "TOP", 0, 2)

        -- Item ID sub-label and RefreshIDLabel must be declared before MakeQualityToggle
        -- so the callback can reference them at toggle-click time.

        -- Item ID sub-label (right anchor patched after qualToggle is known)
        local idTxt = row:CreateFontString(nil, "OVERLAY")
        idTxt:SetFont(FONT, 9, "")
        idTxt:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 0.7)
        idTxt:SetJustifyH("LEFT")
        idTxtRef = idTxt

        local function RefreshIDLabel()
            if preset and preset.q2 then
                local q   = entry.quality or 2
                local rid = (q == 2) and preset.q2 or preset.id
                idTxt:SetText("ID: "..rid.."  (Q"..q..")")
            else
                idTxt:SetText("ID: "..itemId)
            end
        end

        -- Quality toggle (only for preset items with a Q2 variant)
        -- Pass RefreshIDLabel as onChanged so the toggle updates the ID sub-label directly.
        local qualToggle = MakeQualityToggle(row, entry, preset, RefreshIDLabel)
        qualToggleRef = qualToggle  -- allow RefreshRowVisual to grey it out
        if qualToggle then
            qualToggle:SetPoint("RIGHT", buyQtyBox, "LEFT", -8, 0)
            -- "QUALITY" caption above toggle
            local qualLbl = row:CreateFontString(nil, "OVERLAY")
            qualLbl:SetFont(FONT, 9, "")
            qualLbl:SetTextColor(T.textMuted[1], T.textMuted[2], T.textMuted[3], 1)
            qualLbl:SetText("QUALITY")
            qualLbl:SetJustifyH("CENTER")
            qualLbl:SetPoint("BOTTOM", qualToggle, "TOP", 0, 2)
        end

        -- Right anchor for name/ID text: stop at qualToggle if present, else buyQtyBox
        local nameRightAnchor = qualToggle or buyQtyBox
        local nameRightOff    = qualToggle and -8 or -10

        -- Item name
        local nameTxt = row:CreateFontString(nil, "OVERLAY")
        nameTxt:SetPoint("LEFT",  iconF,           "RIGHT", 8,             5)
        nameTxt:SetPoint("RIGHT", nameRightAnchor, "LEFT",  nameRightOff,  0)
        nameTxt:SetFont(FONT, 12, "")
        nameTxt:SetText(itemName)
        nameTxt:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        nameTxt:SetJustifyH("LEFT")
        nameTxt:SetWordWrap(false)
        nameTxtRef = nameTxt

        -- Anchor the ID sub-label now that we know nameRightAnchor
        idTxt:SetPoint("LEFT",  iconF,           "RIGHT", 8,            -8)
        idTxt:SetPoint("RIGHT", nameRightAnchor, "LEFT",  nameRightOff,  0)
        RefreshIDLabel()

        -- Invisible hover zone covering just the name+ID text for item tooltip.
        -- FontStrings have LEFT+RIGHT anchors so their frame spans the full row width —
        -- anchoring to their right edge would inherit that. Use a fixed size instead.
        -- 170 px width covers typical item names; 26 px height spans both text lines.
        local nameHover = CreateFrame("Button", nil, row)
        nameHover:SetPoint("TOPLEFT", nameTxt, "TOPLEFT", -2, 4)
        nameHover:SetSize(170, 26)
        nameHover:EnableMouse(true)
        nameHover:SetScript("OnEnter", function()
            GameTooltip:SetOwner(nameHover, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(itemId)
            GameTooltip:Show()
        end)
        nameHover:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Apply initial disabled visual state
        RefreshRowVisual(entry.enabled)

        return row, ITEM_ROW_H
    end

    -- ── Card 1: Enable ────────────────────────────────────────
    card1 = GUI:CreateCard(parent, "Auto Buy", y)
    card1:AddLabel(
        "When you open a vendor window, automatically buys configured items up to the set quantity — filling only what's missing from your bags.",
        T.textMuted)
    card1:AddSeparator()
    enableRow = GUI:CreateToggle(parent, "Enable Auto Buy", db.enabled,
        function(v) db.enabled = v; UpdateChildState(v); ApplySettings() end, "Auto Buy")
    card1:AddRow(enableRow, 28)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- ── Card 2: Preset Items (collapsible categories) ─────────
    local CAT_ORDER  = { "flask", "healthpotion", "combatpotion", "food", "oil", "rune" }
    local CAT_LABELS = {
        flask        = "Flasks",
        healthpotion = "Health/Mana Potions",
        combatpotion = "Combat Potions",
        rune         = "Runes",
        oil          = "Weapon Oils",
        food         = "Food & Feasts",
    }

    -- Group PresetItems by cat
    local catItems = {}
    for _, cat in ipairs(CAT_ORDER) do catItems[cat] = {} end
    for _, item in ipairs(SP.AutoBuy and SP.AutoBuy.PresetItems or {}) do
        if catItems[item.cat] then table.insert(catItems[item.cat], item) end
    end

    -- ── Card 2: Preset Items (2-column static grid) ───────────
    -- Static layout: no collapsing, no dynamic relayout, no position bugs.
    -- Categories are arranged in pairs (left/right columns), each row shows
    -- two categories side by side.
    local card2 = GUI:CreateCard(parent, "Preset Items", y)
    card2:AddLabel("Toggle each consumable and set the quantity to keep stocked.", T.textMuted)
    card2:AddSeparator()

    -- Collect non-empty categories in order
    local activeCats = {}
    for _, cat in ipairs(CAT_ORDER) do
        if catItems[cat] and #catItems[cat] > 0 then
            table.insert(activeCats, cat)
        end
    end

    -- COL_GAP: horizontal gap between the two side-by-side columns
    local COL_GAP   = T.paddingSmall * 2
    -- CAT_LBL_H: height of the category title label above each item list
    local CAT_LBL_H = 20
    -- ROW_GAP: vertical gap between category-pair rows
    local ROW_GAP   = T.paddingSmall * 2

    -- Returns the total pixel height needed to render one category column
    local function colHeight(cat)
        local h = CAT_LBL_H + T.paddingSmall
        for _ in ipairs(catItems[cat]) do
            h = h + ITEM_ROW_H + T.paddingSmall
        end
        return h
    end

    -- Fills colFrame with a category label and its item rows (all permanently visible)
    local function buildCol(colFrame, cat)
        -- Category title
        local lbl = colFrame:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(FONT, 11, "OUTLINE")
        lbl:SetPoint("TOPLEFT", colFrame, "TOPLEFT", 4, -3)
        lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        lbl:SetText(CAT_LABELS[cat])

        -- Item rows stacked below the title
        local iy = CAT_LBL_H + T.paddingSmall
        for _, item in ipairs(catItems[cat]) do
            if db.items then
                local entry = db.items[item.id]
                    or { enabled = false, quantity = item.buy, buyQty = item.buy, quality = item.q2 and 2 or 1 }
                if entry.quality == nil then entry.quality = item.q2 and 2 or 1 end
                if entry.buyQty  == nil then entry.buyQty  = item.buy end
                db.items[item.id] = entry
                local row, rowH = MakeItemRow(item.id, item.name or ("Item "..item.id),
                    entry, item.buy, nil, item)
                row:SetParent(colFrame)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",  colFrame, "TOPLEFT",  0, -iy)
                row:SetPoint("TOPRIGHT", colFrame, "TOPRIGHT", 0, -iy)
                iy = iy + rowH + T.paddingSmall
                table.insert(childRows, row)
            end
        end
    end

    -- Place categories in pairs: left column | right column, stacked as rows
    local colY = card2.currentY
    local i = 1
    while i <= #activeCats do
        local catL = activeCats[i]
        local catR = activeCats[i + 1]     -- may be nil if odd number of categories
        local hL   = colHeight(catL)
        local hR   = catR and colHeight(catR) or 0
        local pairH = math.max(hL, hR)

        -- Left column: left edge → center of card (minus half the gap)
        local colL = CreateFrame("Frame", nil, card2.content)
        colL:SetPoint("TOPLEFT",  card2.content, "TOPLEFT", 0,          -colY)
        colL:SetPoint("TOPRIGHT", card2.content, "TOP",     -COL_GAP/2, -colY)
        colL:SetHeight(pairH)
        buildCol(colL, catL)

        -- Right column: center of card (plus half the gap) → right edge
        if catR then
            local colR = CreateFrame("Frame", nil, card2.content)
            colR:SetPoint("TOPLEFT",  card2.content, "TOP",      COL_GAP/2, -colY)
            colR:SetPoint("TOPRIGHT", card2.content, "TOPRIGHT", 0,         -colY)
            colR:SetHeight(pairH)
            buildCol(colR, catR)
        end

        colY = colY + pairH + ROW_GAP
        i = i + 2
    end

    card2.currentY = colY
    card2.content:SetHeight(colY)
    card2:_UpdateHeight()
    y = y + card2:GetTotalHeight() + T.paddingSmall

    UpdateChildState(db.enabled)
    parent:SetHeight(y)
end)
-- ============================================================
-- ============================================================
-- Spell Effect Alpha page
-- ============================================================
GUI:RegisterContent("spelleffectalpha", function(parent)
    local T  = SP.Theme
    local db = SP.GetDB().spellEffectAlpha

    local function ApplySettings()
        if SP.SpellEffectAlpha then SP.SpellEffectAlpha.Refresh() end
    end

    local y = 0
    local childRows = {}
    local enableRow -- forward-declared; used in UpdateChildState closure
    local card1     -- forward-declared for UpdateChildState closure
    local function UpdateChildState(en)
        card1:GrayContent(en, enableRow)
        for _, r in ipairs(childRows) do r:SetEnabled(en) end
    end

    -- Card 1: Enable
    card1 = GUI:CreateCard(parent, "Spell Effect Alpha", y)
    card1:AddLabel(
        "Controls the opacity of spell activation overlays (the glowing highlights around action bar buttons when a proc fires). Set to 0 to fully hide them, 100 for default visibility.",
        T.textMuted)
    card1:AddSeparator()

    enableRow = GUI:CreateToggle(parent, "Enable Spell Effect Alpha", db.enabled,
        function(v)
            db.enabled = v
            UpdateChildState(v)
            ApplySettings()
        end, "Spell Effect Alpha")
    card1:AddRow(enableRow, 28)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- Card 2: Global default
    local card2 = GUI:CreateCard(parent, "Global Default", y)
    card2:AddLabel("Applied for any specialization that doesn't have a specific override set below.", T.textMuted)

    local globalRow = GUI:CreateSlider(parent, "Default Opacity (%)", 0, 100, 1, db.globalDefault,
        function(v)
            db.globalDefault = v
            ApplySettings()
        end)
    card2:AddRow(globalRow, 44)
    table.insert(childRows, globalRow)
    y = y + card2:GetTotalHeight() + T.paddingSmall

    -- Card 3: Per-spec overrides
    local card3 = GUI:CreateCard(parent, "Per-Specialization Overrides", y)
    card3:AddLabel("Set a custom opacity for your current specialization. Leave at the global default if no override is needed.", T.textMuted)
    card3:AddSeparator()

    db.specs = db.specs or {}
    local specNames  = SP.SpellEffectAlpha and SP.SpellEffectAlpha.SpecNames  or {}
    local specIcons  = SP.SpellEffectAlpha and SP.SpellEffectAlpha.SpecIcons  or {}

    -- Grouped by class; number of specs per row = number of specs in the class
    local CLASS_GROUPS = {
        { name = "Death Knight",  specs = {250, 251, 252} },
        { name = "Demon Hunter",  specs = {577, 581, 1480} },
        { name = "Druid",         specs = {102, 103, 104, 105} },
        { name = "Evoker",        specs = {1467, 1468, 1473} },
        { name = "Hunter",        specs = {253, 254, 255} },
        { name = "Mage",          specs = {62, 63, 64} },
        { name = "Monk",          specs = {268, 269, 270} },
        { name = "Paladin",       specs = {65, 66, 70} },
        { name = "Priest",        specs = {256, 257, 258} },
        { name = "Rogue",         specs = {259, 260, 261} },
        { name = "Shaman",        specs = {262, 263, 264} },
        { name = "Warlock",       specs = {265, 266, 267} },
        { name = "Warrior",       specs = {71, 72, 73} },
    }

    for i, group in ipairs(CLASS_GROUPS) do
        if i > 1 then card3:AddSeparator() end
        local n = #group.specs
        local hrow = GUI:CreateHRow(parent, 44)
        for _, specID in ipairs(group.specs) do
            local name  = specNames[specID] or ("Spec "..specID)
            local iconID = specIcons[specID]
            local labelText = iconID
                and ("|T"..iconID..":14:14:0:0|t "..name)
                or  name
            local current = db.specs[specID] or db.globalDefault or 100
            local row = GUI:CreateSlider(parent, labelText, 0, 100, 1, current,
                function(v)
                    db.specs[specID] = v
                    -- Mirror ExwindTools: only apply the CVar immediately if this
                    -- slider's spec is the one currently active. Other specs are
                    -- saved silently and applied on PLAYER_SPECIALIZATION_CHANGED.
                    local si = GetSpecialization and GetSpecialization() or 0
                    local curSpec = (si > 0 and GetSpecializationInfo)
                        and GetSpecializationInfo(si) or 0
                    if curSpec == specID then
                        ApplySettings()
                    end
                end)
            hrow:Add(row, 1/n)
        end
        card3:AddRow(hrow, 44)
        table.insert(childRows, hrow)
    end

    y = y + card3:GetTotalHeight() + T.paddingSmall

    UpdateChildState(db.enabled)
    parent:SetHeight(y)
end)

-- ============================================================
-- Combat Cross
-- ============================================================
GUI:RegisterContent("combatcross", function(parent)
    local T  = SP.Theme
    local db = SP.GetDB().combatCross

    local function GetCC() return SP.CombatCross end
    local function ApplySettings()
        local cc = GetCC()
        if cc and cc.ApplySettings then cc:ApplySettings() end
    end

    local y = 0

    local childRows  = {}
    local childCards = {}
    local enableRow  -- forward-declared; used in UpdateChildState closure
    local card1      -- forward-declared for UpdateChildState closure
    local function UpdateChildState(en)
        card1:GrayContent(en, enableRow)
        for _, r in ipairs(childRows)  do r:SetEnabled(en) end
        for _, c in ipairs(childCards) do c:SetAlpha(en and 1 or 0.4) end
    end

    -- ── Card 1: General ────────────────────────────────────
    card1 = GUI:CreateCard(parent, "Combat Cross", y)
    card1:AddLabel(
        "Displays a \"+\" crosshair on screen during combat. The cross turns red when your target is out of range.",
        T.textMuted)
    card1:AddSeparator()
    enableRow = GUI:CreateToggle(parent, "Enable Combat Cross", db.enabled,
        function(v)
            db.enabled = v
            UpdateChildState(v)
            local cc = GetCC()
            if cc then
                if v then cc:Activate() else cc:Deactivate() end
            end
        end, "Combat Cross")
    card1:AddRow(enableRow, 28)
    y = y + card1:GetTotalHeight() + T.paddingSmall

    -- ── Card 2: Appearance ─────────────────────────────────
    local card2 = GUI:CreateCard(parent, "Appearance", y)
    card2:AddLabel("Customise the size, outline, and colour of the cross.", T.textMuted)
    card2:AddSeparator()
    table.insert(childCards, card2)

    local thickRow = GUI:CreateSlider(parent, "Thickness", 4, 40, 1, db.thickness or 14,
        function(v) db.thickness = v; ApplySettings() end)
    card2:AddRow(thickRow, 44)
    table.insert(childRows, thickRow)
    card2:AddSeparator()

    local outlineRow = GUI:CreateToggle(parent, "Outline",
        db.outline ~= false,
        function(v) db.outline = v; ApplySettings() end)
    card2:AddRow(outlineRow, 28)
    table.insert(childRows, outlineRow)
    card2:AddSeparator()

    -- Color Source (left) + Cross Color swatch (right) on the same line
    local ccSrcRow, ccSwRow = GUI:CreateColorWithSource(
        parent, "Cross Color", db, "colorSource", "color", { 1, 1, 1 },
        function() ApplySettings() end)
    local ccColorHRow = GUI:CreateHRow(parent, 52)
    ccColorHRow:Add(ccSrcRow, 0.55)
    ccColorHRow:Add(ccSwRow, 0.45)
    card2:AddRow(ccColorHRow, 52)
    table.insert(childRows, ccColorHRow)

    y = y + card2:GetTotalHeight() + T.paddingSmall

    -- ── Card 3: Range Color ────────────────────────────────
    local card3 = GUI:CreateCard(parent, "Range Color", y)
    card3:AddLabel(
        "Change the cross to the out-of-range colour when your target is beyond the range of your spec's main ability.",
        T.textMuted)
    card3:AddSeparator()
    table.insert(childCards, card3)

    local meleeRow = GUI:CreateToggle(parent, "Enable for Melee Specs",
        db.rangeColorMeleeEnabled or false,
        function(v) db.rangeColorMeleeEnabled = v end)
    card3:AddRow(meleeRow, 28)
    table.insert(childRows, meleeRow)

    local rangedRow = GUI:CreateToggle(parent, "Enable for Ranged Specs",
        db.rangeColorRangedEnabled or false,
        function(v) db.rangeColorRangedEnabled = v end)
    card3:AddRow(rangedRow, 28)
    table.insert(childRows, rangedRow)
    card3:AddSeparator()

    -- Out-of-range color: label on top, swatch on the left
    local oorColor = db.outOfRangeColor or { 1, 0, 0, 1 }
    local oorRow = GUI:CreateStackedColorSwatch(parent, "Out-of-Range Color",
        oorColor[1], oorColor[2], oorColor[3],
        function(r, g, b)
            db.outOfRangeColor = { r, g, b, 1 }
        end)
    card3:AddRow(oorRow, 52)
    table.insert(childRows, oorRow)

    y = y + card3:GetTotalHeight() + T.paddingSmall

    -- ── Card 4: Position & Anchor ──────────────────────────
    local card4 = GUI:CreateCard(parent, "Position", y)
    card4:AddLabel("Set where the cross appears on screen.", T.textMuted)
    card4:AddSeparator()
    table.insert(childCards, card4)

    -- Anchor rows (includes Frame Strata + anchor from/to grids)
    local ccAnchorRow, ccAnchorRowH = GUI:CreateAnchorRow(parent, db, ApplySettings,
        { default = "HIGH", onChange = function() ApplySettings() end })
    card4:AddRow(ccAnchorRow, ccAnchorRowH)
    table.insert(childRows, ccAnchorRow)
    card4:AddSeparator()

    -- X / Y offsets side by side
    local ccXYHRow = GUI:CreateHRow(parent, 44)
    local xRow = GUI:CreateSlider(parent, "X Offset", -2000, 2000, 1, db.x or 0,
        function(v) db.x = v; ApplySettings() end)
    local yRow = GUI:CreateSlider(parent, "Y Offset", -2000, 2000, 1, db.y or 0,
        function(v) db.y = v; ApplySettings() end)
    ccXYHRow:Add(xRow, 0.5)
    ccXYHRow:Add(yRow, 0.5)
    card4:AddRow(ccXYHRow, 44)
    table.insert(childRows, ccXYHRow)
    card4:AddSeparator()

    -- Preview button
    local previewActive = false
    local previewWrap = CreateFrame("Frame", nil, parent)
    previewWrap:SetHeight(28)
    local previewBtn = GUI:CreateButton(previewWrap, "Preview", nil, 140, 28)
    previewBtn:SetPoint("LEFT", previewWrap, "LEFT", 0, 0)
    previewBtn:SetScript("OnLeave", function()
        AnimateBorderFocus(previewBtn, previewActive)
        previewBtn.lbl:SetTextColor(
            previewActive and T.accent[1] or T.textPrimary[1],
            previewActive and T.accent[2] or T.textPrimary[2],
            previewActive and T.accent[3] or T.textPrimary[3], 1)
    end)
    previewBtn:SetScript("OnClick", function()
        local cc = GetCC()
        if not cc then return end
        previewActive = not previewActive
        if previewActive then
            cc:ShowPreview()
            previewBtn.lbl:SetText("Stop Preview")
            previewBtn.lbl:SetTextColor(T.accent[1], T.accent[2], T.accent[3], 1)
        else
            cc:HidePreview()
            previewBtn.lbl:SetText("Preview")
            previewBtn.lbl:SetTextColor(T.textPrimary[1], T.textPrimary[2], T.textPrimary[3], 1)
        end
    end)
    card4:AddRow(previewWrap, 28)

    y = y + card4:GetTotalHeight() + T.paddingSmall

    UpdateChildState(db.enabled)
    parent:SetHeight(y)
end)

