-- SuspicionsPackNudgeTool - NudgeTool.lua
-- Standalone plugin for SuspicionsPack.
-- Forked from NephUI Cooldown Manager's Utils/Nudge.lua.
-- Integrates with Blizzard's native Edit Mode to allow pixel-nudging of
-- any Edit Mode system frame (PlayerFrame, Minimap, cast bars, etc.).
--
-- Enable / disable via the WoW addon list — no in-game toggle needed.

local ADDON_NAME = "SuspicionsPack"
local SP = SuspicionsPack
local LibEditModeOverride = LibStub("LibEditModeOverride-1.0", true)
local strtrim = strtrim

-- Advanced positioning state
local advanced = {
    point       = "CENTER",
    attachPoint = "CENTER",
    attachFrame = UIParent,
    xOffset     = 0,
    yOffset     = 0,
    scale       = 1,
}

local advancedUI = {}
local NudgeFrame

local function toActualPixel(value)
    return math.floor(value / advanced.scale + 0.5)
end

local function toRoundedNumber(text)
    local num = tonumber(text)
    if num == nil then
        return nil
    else
        return math.floor(num + 0.5)
    end
end

local function updateScale()
    local _, height = GetPhysicalScreenSize()
    local uiScale = UIParent:GetScale()
    advanced.scale = 768 / uiScale / height
end

-- Store the currently selected frame
local currentSelectedFrame     = nil
local currentSelectedFrameName = nil
local lastUpdatedFrame         = nil

-- Click detector frame
local clickDetector = CreateFrame("Frame")
clickDetector:Hide()
local lastMouseOverFrame = nil

-- Walk up frame hierarchy to find a frame with systemInfo (Edit Mode system frame)
local function FindSystemFrame(frame)
    if not frame then return nil end

    local rootFrames = {
        UIParent   = true,
        WorldFrame = true,
        GlueParent = true,
    }

    local currentFrame = frame
    local maxDepth     = 20
    local depth        = 0
    local bestFrame    = nil

    while currentFrame and depth < maxDepth do
        local frameName = currentFrame:GetName()

        if frameName and rootFrames[frameName] then
            break
        end

        if currentFrame.systemInfo then
            bestFrame = currentFrame
        end

        local parent = currentFrame:GetParent()
        if not parent or parent == currentFrame then
            break
        end
        currentFrame = parent
        depth        = depth + 1
    end

    return bestFrame
end

-- Select a frame for nudging
local function SelectFrame(frame)
    if not frame then return end

    local frameName       = frame:GetName()
    local nudgeFrameName  = ADDON_NAME .. "NudgeFrame"
    if frameName == nudgeFrameName or
       frameName == "EditModeManagerFrame" or
       (NudgeFrame and frame == NudgeFrame) or
       (EditModeManagerFrame and frame == EditModeManagerFrame) then
        return
    end

    local systemFrame = FindSystemFrame(frame)

    if systemFrame then
        currentSelectedFrame     = systemFrame
        currentSelectedFrameName = systemFrame:GetName() or "Anonymous Frame"
    else
        currentSelectedFrame     = nil
        currentSelectedFrameName = nil
    end
end

-- Scan all frames for isSelected = true (Blizzard's selection flag)
local function ScanForSelectedFrame()
    if not EditModeManagerFrame or not EditModeManagerFrame.editModeActive then
        return nil
    end

    local selectedFrame = nil
    local frame = EnumerateFrames()

    while frame do
        ---@diagnostic disable-next-line: undefined-field
        if frame.isSelected == true then
            selectedFrame = FindSystemFrame(frame)
            if selectedFrame then break end
            selectedFrame = frame
            break
        end
        frame = EnumerateFrames(frame)
    end

    return selectedFrame
end

-- Enable click detection when Edit Mode is active
local function EnableClickDetection()
    if not EditModeManagerFrame or not EditModeManagerFrame.editModeActive then
        return
    end

    clickDetector:Show()
    clickDetector:SetScript("OnUpdate", function(self, elapsed)
        local editModeSelected = ScanForSelectedFrame()
        local nudgeFrame = _G[ADDON_NAME .. "NudgeFrame"] or SP.nudgeFrame

        if editModeSelected then
            if currentSelectedFrame ~= editModeSelected then
                currentSelectedFrame     = editModeSelected
                currentSelectedFrameName = editModeSelected:GetName() or "Anonymous Frame"
                if nudgeFrame then
                    nudgeFrame:UpdateVisibility()
                end
            end
        else
            if currentSelectedFrame then
                currentSelectedFrame     = nil
                currentSelectedFrameName = nil
                if nudgeFrame then
                    nudgeFrame:UpdateVisibility()
                end
            end

            if IsMouseButtonDown("LeftButton") then
                local frames = GetMouseFoci()
                if frames and #frames > 0 then
                    local f = frames[1]
                    if f and f ~= WorldFrame and f ~= lastMouseOverFrame then
                        lastMouseOverFrame = f
                        SelectFrame(f)
                        if nudgeFrame then
                            nudgeFrame:UpdateVisibility()
                        end
                    end
                end
            else
                lastMouseOverFrame = nil
            end
        end
    end)
end

-- Disable click detection when Edit Mode exits
local function DisableClickDetection()
    clickDetector:Hide()
    clickDetector:SetScript("OnUpdate", nil)
    lastMouseOverFrame       = nil
    currentSelectedFrame     = nil
    currentSelectedFrameName = nil
end

local function GetSelectedEditModeFrame()
    return currentSelectedFrame, currentSelectedFrameName
end

local function GetFrameDisplayName(frame, frameName)
    if not frame then return "No frame selected" end

    frameName = frameName or frame:GetName()
    if not frameName or frameName == "Anonymous Frame" then
        return "Selected Frame"
    end

    if frameName == "PlayerFrame" then
        return "Player"
    elseif frameName == "TargetFrame" then
        return "Target"
    elseif frameName == "FocusFrame" then
        return "Focus"
    elseif frameName == "PetFrame" then
        return "Pet"
    else
        return frameName:gsub("CooldownViewer", ""):gsub("Icon", " Icon")
    end
end

-- Helpers for advanced UI
local function setupLabel(label)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
end

local function setupEditBox(editBox)
    editBox:SetAutoFocus(false)
    editBox:EnableKeyboard(true)
    editBox:SetPropagateKeyboardInput(false)

    editBox:SetScript("OnEditFocusGained", function(self)
        advanced.oldText = self:GetText()
    end)
    editBox:HookScript("OnEscapePressed", function(self)
        self:SetText(advanced.oldText)
        self:ClearFocus()
    end)
end

local function setupPointDropdown(dropdown)
    local function isSelected(index)
        if advanced.point == "CENTER"      then return index == 0
        elseif advanced.point == "TOP"     then return index == 1
        elseif advanced.point == "BOTTOM"  then return index == 2
        elseif advanced.point == "LEFT"    then return index == 3
        elseif advanced.point == "RIGHT"   then return index == 4
        elseif advanced.point == "TOPLEFT" then return index == 5
        elseif advanced.point == "TOPRIGHT" then return index == 6
        elseif advanced.point == "BOTTOMLEFT" then return index == 7
        elseif advanced.point == "BOTTOMRIGHT" then return index == 8
        end
    end

    local function SetSelected(index)
        local points = { [0]="CENTER","TOP","BOTTOM","LEFT","RIGHT","TOPLEFT","TOPRIGHT","BOTTOMLEFT","BOTTOMRIGHT" }
        advanced.point = points[index] or "CENTER"
        SP:ApplyAdvancedNudgeSettings()
    end

    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:CreateRadio("CENTER",      isSelected, SetSelected, 0)
        rootDescription:CreateRadio("TOP",         isSelected, SetSelected, 1)
        rootDescription:CreateRadio("BOTTOM",      isSelected, SetSelected, 2)
        rootDescription:CreateRadio("LEFT",        isSelected, SetSelected, 3)
        rootDescription:CreateRadio("RIGHT",       isSelected, SetSelected, 4)
        rootDescription:CreateRadio("TOPLEFT",     isSelected, SetSelected, 5)
        rootDescription:CreateRadio("TOPRIGHT",    isSelected, SetSelected, 6)
        rootDescription:CreateRadio("BOTTOMLEFT",  isSelected, SetSelected, 7)
        rootDescription:CreateRadio("BOTTOMRIGHT", isSelected, SetSelected, 8)
    end)
end

local function setupRelativePointDropdown(dropdown)
    local function isSelected(index)
        if advanced.attachPoint == "CENTER"      then return index == 0
        elseif advanced.attachPoint == "TOP"     then return index == 1
        elseif advanced.attachPoint == "BOTTOM"  then return index == 2
        elseif advanced.attachPoint == "LEFT"    then return index == 3
        elseif advanced.attachPoint == "RIGHT"   then return index == 4
        elseif advanced.attachPoint == "TOPLEFT" then return index == 5
        elseif advanced.attachPoint == "TOPRIGHT" then return index == 6
        elseif advanced.attachPoint == "BOTTOMLEFT" then return index == 7
        elseif advanced.attachPoint == "BOTTOMRIGHT" then return index == 8
        end
    end

    local function SetSelected(index)
        local points = { [0]="CENTER","TOP","BOTTOM","LEFT","RIGHT","TOPLEFT","TOPRIGHT","BOTTOMLEFT","BOTTOMRIGHT" }
        advanced.attachPoint = points[index] or "CENTER"
        SP:ApplyAdvancedNudgeSettings()
    end

    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:CreateRadio("CENTER",      isSelected, SetSelected, 0)
        rootDescription:CreateRadio("TOP",         isSelected, SetSelected, 1)
        rootDescription:CreateRadio("BOTTOM",      isSelected, SetSelected, 2)
        rootDescription:CreateRadio("LEFT",        isSelected, SetSelected, 3)
        rootDescription:CreateRadio("RIGHT",       isSelected, SetSelected, 4)
        rootDescription:CreateRadio("TOPLEFT",     isSelected, SetSelected, 5)
        rootDescription:CreateRadio("TOPRIGHT",    isSelected, SetSelected, 6)
        rootDescription:CreateRadio("BOTTOMLEFT",  isSelected, SetSelected, 7)
        rootDescription:CreateRadio("BOTTOMRIGHT", isSelected, SetSelected, 8)
    end)
end

local function setAdvancedEnabled(enabled)
    if not advancedUI then return end
    local method = enabled and "Enable" or "Disable"
    if advancedUI.pointDropdown       then advancedUI.pointDropdown[method](advancedUI.pointDropdown) end
    if advancedUI.attachFrameEditBox  then advancedUI.attachFrameEditBox[method](advancedUI.attachFrameEditBox) end
    if advancedUI.attachPointDropdown then advancedUI.attachPointDropdown[method](advancedUI.attachPointDropdown) end
    if advancedUI.frameNameEditBox    then advancedUI.frameNameEditBox[method](advancedUI.frameNameEditBox) end
end

local function resolveFrame(frameOrName)
    if type(frameOrName) == "string" then
        return _G[frameOrName]
    end
    return frameOrName
end

function SP:ApplyAdvancedNudgeSettings()
    local selectedFrame = currentSelectedFrame
    if not selectedFrame or not selectedFrame.systemInfo then return end

    if selectedFrame.CanBeMoved and not selectedFrame:CanBeMoved() then
        return
    end

    if selectedFrame.isManagedFrame and selectedFrame:IsInDefaultPosition() then
        if selectedFrame.BreakFromFrameManager then
            selectedFrame:BreakFromFrameManager()
        end
    end

    if selectedFrame.ClearFrameSnap then selectedFrame:ClearFrameSnap() end
    if selectedFrame.StopMovingOrSizing then selectedFrame:StopMovingOrSizing() end

    local attachFrameObj = resolveFrame(advanced.attachFrame) or UIParent
    advanced.attachFrame = attachFrameObj

    local anchor = selectedFrame.systemInfo.anchorInfo or {}
    anchor.point       = advanced.point
    anchor.relativePoint = advanced.attachPoint
    anchor.relativeTo  = attachFrameObj:GetName() or attachFrameObj
    anchor.offsetX     = advanced.xOffset
    anchor.offsetY     = advanced.yOffset
    selectedFrame.systemInfo.anchorInfo = anchor

    selectedFrame.hasActiveChanges = true
    if EditModeManagerFrame and EditModeManagerFrame.SetHasActiveChanges then
        EditModeManagerFrame:SetHasActiveChanges(true)
    end

    selectedFrame:ClearAllPoints()
    selectedFrame:SetPoint(advanced.point, attachFrameObj, advanced.attachPoint, advanced.xOffset, advanced.yOffset)

    if selectedFrame.OnSystemPositionChange then
        selectedFrame:OnSystemPositionChange()
    elseif EditModeManagerFrame and EditModeManagerFrame.OnSystemPositionChange then
        EditModeManagerFrame:OnSystemPositionChange(selectedFrame)
    end

    if SP.nudgeFrame and SP.nudgeFrame:IsShown() then
        SP.nudgeFrame:UpdateInfo()
        SP.nudgeFrame:UpdatePosition()
    end
end

local function updateAdvancedFromSelection()
    if not advancedUI or not advancedUI.pointDropdown then return end
    local selectedFrame = currentSelectedFrame
    if not selectedFrame then
        setAdvancedEnabled(false)
        if advancedUI.frameNameEditBox   then advancedUI.frameNameEditBox:SetText("") end
        if advancedUI.attachFrameEditBox then advancedUI.attachFrameEditBox:SetText("") end
        if advancedUI.pointDropdown      then advancedUI.pointDropdown:GenerateMenu() end
        if advancedUI.attachPointDropdown then advancedUI.attachPointDropdown:GenerateMenu() end
        return
    end

    setAdvancedEnabled(true)
    updateScale()

    local anchor = selectedFrame.systemInfo and selectedFrame.systemInfo.anchorInfo or {}
    local point, relativeTo, relativePoint, xOfs, yOfs = selectedFrame:GetPoint(1)

    advanced.point       = anchor.point        or point        or "CENTER"
    advanced.attachPoint = anchor.relativePoint or relativePoint or advanced.point
    advanced.attachFrame = resolveFrame(anchor.relativeTo or relativeTo or UIParent) or UIParent
    advanced.xOffset     = anchor.offsetX or xOfs or 0
    advanced.yOffset     = anchor.offsetY or yOfs or 0

    advancedUI.pointDropdown:GenerateMenu()
    advancedUI.attachPointDropdown:GenerateMenu()
    advancedUI.attachFrameEditBox:SetText(advanced.attachFrame:GetName() or "UIParent")
    advancedUI.frameNameEditBox:SetText(selectedFrame:GetName() or "Frame")
end

local function createAdvancedControls(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT",  parent, "TOPLEFT",  10, -168)
    frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -168)
    frame:SetHeight(110)

    -- Self Point
    local pointContainer = CreateFrame("Frame", nil, frame)
    pointContainer:SetPoint("TOPLEFT",  frame, "TOPLEFT",  0, 0)
    pointContainer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    pointContainer:SetHeight(26)

    local pointLabel = pointContainer:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    setupLabel(pointLabel)
    pointLabel:SetText("Self Point")
    pointLabel:SetPoint("TOPLEFT", pointContainer, "TOPLEFT", 0, 0)
    pointLabel:SetSize(90, 24)

    local pointDropdown = CreateFrame("DropdownButton", nil, pointContainer, "WowStyle1DropdownTemplate")
    setupPointDropdown(pointDropdown)
    pointDropdown:SetPoint("LEFT", pointLabel, "RIGHT", 4, 0)
    pointDropdown:SetSize(210, 22)

    -- Anchor to
    local attachFrameContainer = CreateFrame("Frame", nil, frame)
    attachFrameContainer:SetPoint("TOPLEFT",  pointContainer, "BOTTOMLEFT",  0, -6)
    attachFrameContainer:SetPoint("TOPRIGHT", pointContainer, "BOTTOMRIGHT", 0, -6)
    attachFrameContainer:SetHeight(26)

    local attachFrameLabel = attachFrameContainer:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    setupLabel(attachFrameLabel)
    attachFrameLabel:SetText("Anchor to")
    attachFrameLabel:SetPoint("TOPLEFT", attachFrameContainer, "TOPLEFT", 0, 0)
    attachFrameLabel:SetSize(90, 24)

    local attachFrameEditBox = CreateFrame("EditBox", nil, attachFrameContainer, "InputBoxTemplate")
    setupEditBox(attachFrameEditBox)
    attachFrameEditBox:SetPoint("LEFT", attachFrameLabel, "RIGHT", 6, 0)
    attachFrameEditBox:SetSize(210, 22)
    attachFrameEditBox:SetScript("OnEnterPressed", function(self)
        local frameName = strtrim(self:GetText() or "")
        local target    = frameName == "UIParent" and UIParent or _G[frameName]

        local isFrame = target ~= nil
            and type(target) == "table"
            and ((C_Widget and C_Widget.IsFrameWidget and C_Widget.IsFrameWidget(target)) or target.GetObjectType)

        if isFrame then
            advanced.attachFrame = target
            SP:ApplyAdvancedNudgeSettings()
        else
            self:SetText(advanced.oldText)
        end
        self:ClearFocus()
    end)

    -- Anchor Point
    local attachPointContainer = CreateFrame("Frame", nil, frame)
    attachPointContainer:SetPoint("TOPLEFT",  attachFrameContainer, "BOTTOMLEFT",  0, -6)
    attachPointContainer:SetPoint("TOPRIGHT", attachFrameContainer, "BOTTOMRIGHT", 0, -6)
    attachPointContainer:SetHeight(26)

    local attachPointLabel = attachPointContainer:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    setupLabel(attachPointLabel)
    attachPointLabel:SetText("Anchor Point")
    attachPointLabel:SetPoint("TOPLEFT", attachPointContainer, "TOPLEFT", 0, 0)
    attachPointLabel:SetSize(90, 24)

    local attachPointDropdown = CreateFrame("DropdownButton", nil, attachPointContainer, "WowStyle1DropdownTemplate")
    setupRelativePointDropdown(attachPointDropdown)
    attachPointDropdown:SetPoint("LEFT", attachPointLabel, "RIGHT", 4, 0)
    attachPointDropdown:SetSize(210, 22)

    -- Frame Name (read-only display)
    local frameNameContainer = CreateFrame("Frame", nil, frame)
    frameNameContainer:SetPoint("TOPLEFT",  attachPointContainer, "BOTTOMLEFT",  0, -6)
    frameNameContainer:SetPoint("TOPRIGHT", attachPointContainer, "BOTTOMRIGHT", 0, -6)
    frameNameContainer:SetHeight(26)

    local frameNameLabel = frameNameContainer:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    setupLabel(frameNameLabel)
    frameNameLabel:SetText("Frame Name")
    frameNameLabel:SetPoint("TOPLEFT", frameNameContainer, "TOPLEFT", 0, 0)
    frameNameLabel:SetSize(90, 24)

    local frameNameEditBox = CreateFrame("EditBox", nil, frameNameContainer, "InputBoxTemplate")
    setupEditBox(frameNameEditBox)
    frameNameEditBox:SetPoint("LEFT", frameNameLabel, "RIGHT", 6, 0)
    frameNameEditBox:SetSize(210, 22)
    frameNameEditBox:SetScript("OnEnterPressed", function(self)
        self:SetText(advanced.oldText)
        self:ClearFocus()
    end)

    advancedUI.pointDropdown       = pointDropdown
    advancedUI.attachFrameEditBox  = attachFrameEditBox
    advancedUI.attachPointDropdown = attachPointDropdown
    advancedUI.frameNameEditBox    = frameNameEditBox

    setAdvancedEnabled(false)
end

-- ============================================================
-- Layout: embed nudge frame into EditModeSystemSettingsDialog
-- ============================================================
local function UpdateSettingsDialogLayout()
    if not NudgeFrame or not EditModeSystemSettingsDialog then return end

    NudgeFrame:SetParent(EditModeSystemSettingsDialog)
    NudgeFrame:SetFrameStrata(EditModeSystemSettingsDialog:GetFrameStrata())
    NudgeFrame:SetFrameLevel(EditModeSystemSettingsDialog:GetFrameLevel())

    NudgeFrame:ClearAllPoints()
    local anchor = EditModeSystemSettingsDialog.Buttons or EditModeSystemSettingsDialog
    NudgeFrame:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, -2)
    NudgeFrame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)

    if EditModeSystemSettingsDialog:GetTop() and NudgeFrame:GetBottom() then
        EditModeSystemSettingsDialog:SetHeight(EditModeSystemSettingsDialog:GetTop() - NudgeFrame:GetBottom() + 20)
    end
end

local function HookSettingsDialog()
    if not EditModeSystemSettingsDialog or (NudgeFrame and NudgeFrame._settingsHooked) then
        return
    end

    NudgeFrame._settingsHooked = true

    EditModeSystemSettingsDialog:HookScript("OnShow", function()
        UpdateSettingsDialogLayout()
        NudgeFrame:UpdateVisibility()
    end)

    EditModeSystemSettingsDialog:HookScript("OnHide", function()
        NudgeFrame:Hide()
    end)

    hooksecurefunc(EditModeSystemSettingsDialog, "UpdateDialog", function()
        UpdateSettingsDialogLayout()
        NudgeFrame:UpdateVisibility()
    end)
end

-- ============================================================
-- Create the NudgeFrame
-- ============================================================
local nudgeParent = EditModeSystemSettingsDialog or UIParent
NudgeFrame = CreateFrame("Frame", ADDON_NAME .. "NudgeFrame", nudgeParent, "BackdropTemplate")
SP.nudgeFrame = NudgeFrame

NudgeFrame:SetHeight(300)
NudgeFrame:SetFrameStrata("DIALOG")
NudgeFrame:EnableMouse(true)
NudgeFrame:Hide()

function NudgeFrame:UpdatePosition()
    if EditModeSystemSettingsDialog then
        UpdateSettingsDialogLayout()
    else
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local title = NudgeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -8)
title:SetText("Nudge Frame")

local infoText = NudgeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
infoText:Hide()
NudgeFrame.infoText = infoText

-- Coordinate edit boxes (X / Y)
local coordsContainer = CreateFrame("Frame", nil, NudgeFrame)
coordsContainer:SetPoint("TOP", title, "BOTTOM", 0, -10)
coordsContainer:SetSize(240, 28)
NudgeFrame.coordsContainer = coordsContainer

local xLabel = coordsContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
xLabel:SetPoint("LEFT", coordsContainer, "LEFT", 0, 0)
xLabel:SetWidth(14)
xLabel:SetJustifyH("LEFT")
xLabel:SetText("X")

local xEditBox = CreateFrame("EditBox", nil, coordsContainer, "InputBoxTemplate")
setupEditBox(xEditBox)
xEditBox:SetPoint("LEFT", xLabel, "RIGHT", 4, 0)
xEditBox:SetSize(80, 24)
xEditBox:SetScript("OnEnterPressed", function(self)
    local val = toRoundedNumber(self:GetText())
    if val == nil then
        self:SetText(advanced.oldText or "")
    else
        advanced.xOffset = val
        SP:ApplyAdvancedNudgeSettings()
    end
    self:ClearFocus()
end)
NudgeFrame.xEditBox = xEditBox

local yLabel = coordsContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
yLabel:SetPoint("LEFT", xEditBox, "RIGHT", 12, 0)
yLabel:SetWidth(14)
yLabel:SetJustifyH("LEFT")
yLabel:SetText("Y")

local yEditBox = CreateFrame("EditBox", nil, coordsContainer, "InputBoxTemplate")
setupEditBox(yEditBox)
yEditBox:SetPoint("LEFT", yLabel, "RIGHT", 4, 0)
yEditBox:SetSize(80, 24)
yEditBox:SetScript("OnEnterPressed", function(self)
    local val = toRoundedNumber(self:GetText())
    if val == nil then
        self:SetText(advanced.oldText or "")
    else
        advanced.yOffset = val
        SP:ApplyAdvancedNudgeSettings()
    end
    self:ClearFocus()
end)
NudgeFrame.yEditBox = yEditBox

-- Arrow buttons (D-pad)
local function CreateArrowButton(parent, direction, anchorFrame, x, yOffset)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(28, 28)
    if anchorFrame then
        button:SetPoint("TOP", anchorFrame, "BOTTOM", x, yOffset or -10)
    else
        button:SetPoint("TOP", parent, "TOP", x, yOffset or -10)
    end

    button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

    local texture = button:GetNormalTexture()
    if direction == "UP" then
        texture:SetRotation(math.rad(90))
        button:GetPushedTexture():SetRotation(math.rad(90))
    elseif direction == "DOWN" then
        texture:SetRotation(math.rad(270))
        button:GetPushedTexture():SetRotation(math.rad(270))
    elseif direction == "LEFT" then
        texture:SetRotation(math.rad(180))
        button:GetPushedTexture():SetRotation(math.rad(180))
    elseif direction == "RIGHT" then
        texture:SetRotation(math.rad(0))
        button:GetPushedTexture():SetRotation(math.rad(0))
    end

    button:SetScript("OnClick", function()
        SP:NudgeSelectedFrame(direction)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Nudge " .. direction:lower())
        GameTooltip:AddLine("Move selected frame 1 pixel " .. direction:lower(), 1, 1, 1)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return button
end

local arrowAnchor = coordsContainer
NudgeFrame.upButton    = CreateArrowButton(NudgeFrame, "UP",    arrowAnchor,  0,  -10)
NudgeFrame.downButton  = CreateArrowButton(NudgeFrame, "DOWN",  arrowAnchor,  0,  -58)
NudgeFrame.leftButton  = CreateArrowButton(NudgeFrame, "LEFT",  arrowAnchor, -24, -34)
NudgeFrame.rightButton = CreateArrowButton(NudgeFrame, "RIGHT", arrowAnchor,  24, -34)

-- Advanced controls (Self Point / Anchor To / Anchor Point / Frame Name)
createAdvancedControls(NudgeFrame)

-- ============================================================
-- NudgeFrame methods
-- ============================================================
function NudgeFrame:UpdateInfo()
    local selectedFrame, frameName = GetSelectedEditModeFrame()

    if selectedFrame then
        local xOfs, yOfs
        if selectedFrame.systemInfo and selectedFrame.systemInfo.anchorInfo then
            local anchor = selectedFrame.systemInfo.anchorInfo
            xOfs = anchor.offsetX or 0
            yOfs = anchor.offsetY or 0
        else
            local point, _, _, x, y = selectedFrame:GetPoint(1)
            xOfs = x or 0
            yOfs = y or 0
        end

        advanced.xOffset = xOfs
        advanced.yOffset = yOfs

        if self.xEditBox then
            self.xEditBox:SetText(string.format("%.1f", xOfs))
            self.xEditBox:Enable()
        end
        if self.yEditBox then
            self.yEditBox:SetText(string.format("%.1f", yOfs))
            self.yEditBox:Enable()
        end

        self.upButton:Enable()
        self.downButton:Enable()
        self.leftButton:Enable()
        self.rightButton:Enable()

        if lastUpdatedFrame ~= selectedFrame then
            lastUpdatedFrame = selectedFrame
            updateAdvancedFromSelection()
        end
    else
        if self.xEditBox then self.xEditBox:SetText(""); self.xEditBox:Disable() end
        if self.yEditBox then self.yEditBox:SetText(""); self.yEditBox:Disable() end

        self.upButton:Disable()
        self.downButton:Disable()
        self.leftButton:Disable()
        self.rightButton:Disable()

        if lastUpdatedFrame ~= nil then
            lastUpdatedFrame = nil
            updateAdvancedFromSelection()
        end
    end
end

function NudgeFrame:UpdateVisibility()
    if not EditModeManagerFrame or not EditModeManagerFrame.editModeActive then
        self:Hide()
        return
    end

    if EditModeSystemSettingsDialog and EditModeSystemSettingsDialog:IsShown() then
        self:UpdatePosition()
        self:Show()
        self:UpdateInfo()
    else
        self:Hide()
    end
end

NudgeFrame:SetScript("OnShow", function(self)
    self:UpdatePosition()
    self:UpdateInfo()
end)

-- ============================================================
-- SP:NudgeSelectedFrame — pixel nudge
-- ============================================================
function SP:NudgeSelectedFrame(direction)
    local selectedFrame, frameName = GetSelectedEditModeFrame()
    if not selectedFrame then return false end

    if not EditModeManagerFrame or not EditModeManagerFrame.editModeActive then
        return false
    end

    local amount = 1

    local systemFrame = selectedFrame
    if not systemFrame.systemInfo then return false end

    local systemInfo = systemFrame.systemInfo
    local anchor     = systemInfo.anchorInfo or {}

    local xOffset = anchor.offsetX or 0
    local yOffset = anchor.offsetY or 0

    if direction == "UP"    then yOffset = yOffset + amount
    elseif direction == "DOWN"  then yOffset = yOffset - amount
    elseif direction == "LEFT"  then xOffset = xOffset - amount
    elseif direction == "RIGHT" then xOffset = xOffset + amount
    end

    anchor.offsetX       = xOffset
    anchor.offsetY       = yOffset
    systemInfo.anchorInfo = anchor
    systemFrame.systemInfo = systemInfo

    systemFrame.hasActiveChanges = true
    if EditModeManagerFrame.SetHasActiveChanges then
        EditModeManagerFrame:SetHasActiveChanges(true)
    end

    local numPoints = systemFrame:GetNumPoints()
    if numPoints > 0 then
        local point, relativeTo, relativePoint = systemFrame:GetPoint(1)

        local anchorPoint    = anchor.point        or point        or "CENTER"
        local relativeFrame  = anchor.relativeTo   or relativeTo   or UIParent
        local relativeAnchor = anchor.relativePoint or relativePoint or "CENTER"

        systemFrame:ClearAllPoints()
        systemFrame:SetPoint(anchorPoint, relativeFrame, relativeAnchor, xOffset, yOffset)
    end

    if SP.nudgeFrame and SP.nudgeFrame:IsShown() then
        SP.nudgeFrame:UpdateInfo()
        SP.nudgeFrame:UpdatePosition()
    end

    return true
end

-- ============================================================
-- Hook into Blizzard's Edit Mode enter / exit
-- ============================================================
local function SetupEditModeHooks()
    if not EditModeManagerFrame then return end
    HookSettingsDialog()

    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        if LibEditModeOverride and LibEditModeOverride:IsReady() then
            if not LibEditModeOverride:AreLayoutsLoaded() then
                LibEditModeOverride:LoadLayouts()
            end
        end

        EnableClickDetection()
        NudgeFrame:UpdateVisibility()
    end)

    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        DisableClickDetection()
        NudgeFrame:Hide()
        currentSelectedFrame     = nil
        currentSelectedFrameName = nil
        lastUpdatedFrame         = nil
    end)
end

if EditModeManagerFrame then
    SetupEditModeHooks()
else
    local waitFrame = CreateFrame("Frame")
    waitFrame:RegisterEvent("ADDON_LOADED")
    waitFrame:SetScript("OnEvent", function(self, event, addon)
        if EditModeManagerFrame then
            SetupEditModeHooks()
            self:UnregisterAllEvents()
        end
    end)
end
