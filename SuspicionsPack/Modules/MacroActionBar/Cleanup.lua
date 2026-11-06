local smb = SuspicionsPack.MAB
local addonName = smb.TITLE -- in messages; the original printed its folder name

-- Keeps the addon's general macros from piling up in every character's General tab: while playing, it records
-- the ones on this character's action bars, and a fresh login (not a /reload) that finds the General tab full
-- clears them all and puts this character's back (Macros.lua). Also owns the "macros full" popup.

-- The popup: built on first use, a plain dialog so it can carry a "Don't show this again" box.
local popup

-- The pack's setting (Interface > Macro Action Bar), which the box below turns off.
local function hidesPopup()
    local db = SuspicionsPack.GetDB().macroActionBar
    return db ~= nil and db.macrosFullPopup == false
end

-- In the pack's Forever style: Plumber's frame and leather, the game's font with Plumber's colours, the
-- game's check box and button (Core.lua, SP.ShowChangelogPopup). 20 in, clear of the frame's inward shadow.
local function buildPopup()
    local SP = SuspicionsPack
    local Skin, FT = SP.Skin, SP.Skin.FOREVER_TEXT
    local PAD = 20
    local function Font(fs, size, color)
        SP.SetFontSafe(fs, STANDARD_TEXT_FONT, size, "")
        fs:SetShadowColor(0, 0, 0, 0.9)
        fs:SetShadowOffset(1, -1)
        fs:SetTextColor(color[1], color[2], color[3], 1)
    end

    local frame = CreateFrame("Frame", "SuspicionsPackMABMacrosFullPopup", UIParent)
    frame:SetSize(360, 156)
    frame:SetPoint("TOP", 0, -135)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    Skin.PlumberFrame(frame, 0, function() frame:Hide() end)
    tinsert(UISpecialFrames, frame:GetName()) -- Escape closes it

    local title = frame:CreateFontString(nil, "OVERLAY")
    Font(title, 14, FT.gold)
    title:SetPoint("TOPLEFT", PAD, -PAD - 2)
    title:SetText(addonName)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    Font(frame.text, 12, FT.readable)
    frame.text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    frame.text:SetWidth(360 - 2 * PAD)
    frame.text:SetJustifyH("LEFT")

    local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("BOTTOMLEFT", PAD - 4, 14)
    check:SetScript("OnClick", function(self)
        local db = SP.GetDB().macroActionBar
        if db then db.macrosFullPopup = not self:GetChecked() end
    end)
    local label = frame:CreateFontString(nil, "OVERLAY")
    Font(label, 12, FT.cream)
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText("Don't show this again")
    frame.check = check

    local okay = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    okay:SetSize(96, 22)
    okay:SetPoint("BOTTOMRIGHT", -PAD, 14)
    okay:SetText(OKAY)
    okay:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        frame:Hide()
    end)
    return frame
end

-- Shows the popup telling the player there is no free macro slot, unless they ticked "Don't show this again".
-- Equipment macros only fit in General, so for them only that tab is full.
function smb.showMacrosFull(equipment)
    if hidesPopup() then return end
    popup = popup or buildPopup()
    popup.text:SetText((equipment and "The General macro tab is full."
        or "Both macro tabs are full.") .. " Delete some macros to make room.")
    popup.check:SetChecked(false)
    popup:Show()
end

local frame = CreateFrame("Frame")

-- Re-records the bars once per burst of changes (placing a macro fires several events).
local recordPending = false
local function scheduleRecord()
    if recordPending then return end
    recordPending = true
    C_Timer.After(0, function()
        recordPending = false
        smb.recordGeneralMacros()
    end)
end

-- Starts keeping the record up to date. Only after the login reset: before it, the bars still hold the
-- last session's macros (or none yet), and recording them would overwrite the record the reset restores from.
local function startRecording()
    frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    frame:RegisterEvent("UPDATE_MACROS")
    scheduleRecord()
end

local RESTORE_DELAY = 1 -- seconds; a just created macro may not be ready to pick up at once
local RESTORE_TRIES = 5

-- Macros can't be deleted, created or placed in combat, so a step that finds combat waits for it to end.
local afterCombat
local function outOfCombat(step)
    if InCombatLockdown() then
        afterCombat = step
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end
    return true
end

-- Puts the recreated macros back on the bars, retrying until every slot holds its macro.
local tries = 0
local function restore()
    if not outOfCombat(restore) then return end
    tries = tries + 1
    if smb.restoreGeneralMacroSlots() or tries >= RESTORE_TRIES then
        smb.charDB.restorePending = nil
        startRecording() -- the bars are this session's now
    else
        C_Timer.After(RESTORE_DELAY, restore)
    end
end

local function reset()
    if not outOfCombat(reset) then return end
    smb.resetGeneralMacros()
    C_Timer.After(RESTORE_DELAY, restore)
end

local function onEvent(self, event, isInitialLogin, isReloadingUi)
    if event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_MACROS" then
        scheduleRecord()
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        local step = afterCombat
        afterCombat = nil
        if step then step() end
    else
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- the flag stays saved until the macros are back on the bars, so a /reload before then (in combat, or
        -- during the retries) runs the cleanup again instead of recording the bars without them. It is not
        -- checked for a full tab again: the cleanup's deletes have already freed slots.
        smb.charDB = smb.charDB or {}
        if smb.charDB.restorePending then
            C_Timer.After(0, reset)
        elseif isInitialLogin and not isReloadingUi then
            C_Timer.After(0, function() -- once the macros and action bars have loaded
                if smb.isGeneralFull() then
                    smb.charDB.restorePending = true
                    reset()
                else
                    startRecording() -- room left: nothing to clean
                end
            end)
        else
            startRecording() -- a /reload: nothing to clean, the bars are this session's
        end
    end
end

-- The pack sets the module up at PLAYER_LOGIN, before PLAYER_ENTERING_WORLD.
smb.onInstall(function()
    local Perf = SuspicionsPack.Perf
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", Perf.WrapEvent("MacroActionBar", onEvent))
end)
