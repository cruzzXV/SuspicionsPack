-- SuspicionsPack - CopyTooltip.lua
-- Press Ctrl+C while hovering any tooltip to copy its SpellID / ItemID /
-- AuraID / MacroID or unit name into a popup dialog ready to paste.
-- Adapted from NorskenUI's CopyAnything.lua.

local SP = SuspicionsPack

local CopyTooltip = SP:NewModule("CopyTooltip", "AceEvent-3.0")
SP.CopyTooltip = CopyTooltip

-- ============================================================
-- Locals
-- ============================================================
local IsControlKeyDown      = IsControlKeyDown
local IsShiftKeyDown        = IsShiftKeyDown
local InCombatLockdown      = InCombatLockdown
local StaticPopupDialogs    = StaticPopupDialogs
local StaticPopup_Show      = StaticPopup_Show
local CreateFrame           = CreateFrame
local select                = select
local strsplit              = strsplit
local tostring              = tostring

-- ============================================================
-- DB helper
-- ============================================================
local function GetDB()
    return SP.GetDB().copyTooltip
end

-- ============================================================
-- Static popup — shown once and reused
-- ============================================================
local DIALOG_NAME     = "SP_COPY_TOOLTIP_DIALOG"
local dialogCreated   = false

local function EnsureDialog()
    if dialogCreated then return end
    dialogCreated = true

    StaticPopupDialogs[DIALOG_NAME] = {
        text    = "Ctrl+C  —  %s",
        button1 = CLOSE,

        OnShow = function(dialog, data)
            local function Close() dialog:Hide() end
            dialog.EditBox:SetScript("OnEscapePressed", Close)
            dialog.EditBox:SetScript("OnEnterPressed",  Close)
            dialog.EditBox:SetScript("OnKeyUp", function(_, key)
                if IsControlKeyDown() and key == "C" then Close() end
            end)
            dialog.EditBox:SetMaxLetters(0)
            dialog.EditBox:SetText(data or "")
            dialog.EditBox:HighlightText()
        end,

        hasEditBox    = true,
        EditBoxWidth  = 260,
        timeout       = 0,
        whileDead     = true,
        hideOnEscape  = true,
        preferredIndex = 3,
    }
end

-- ============================================================
-- ID extraction — mirrors NorskenUI logic, SP-namespaced
-- ============================================================
local function GetNPCIDFromGUID(guid)
    if not guid then return end
    return select(6, strsplit("-", guid))
end

-- Safe wrapper: returns value(s) unless WoW marks them as secret in this context.
-- Checks ALL returned values (not just the first): GetSpell() returns
-- (spellName, spellId) — the ID itself can be secret independently of the name.
local function SafeGet(fn)
    local ok, a, b, c = pcall(fn)
    if not ok then return end
    if issecretvalue then
        if issecretvalue(a) or issecretvalue(b) or issecretvalue(c) then return end
    end
    return a, b, c
end

-- Returns copyName (label for the popup title), copyId (text to paste) or nil, nil
local function ExtractTooltipData()
    local copyName, copyId

    -- 1. Spell
    local spellName, spellId = SafeGet(function() return GameTooltip:GetSpell() end)
    if spellId then
        copyName, copyId = spellName, spellId
    end

    -- 2. Item
    if not copyId then
        local itemName, _, itemId = SafeGet(function() return GameTooltip:GetItem() end)
        if itemId then
            copyName, copyId = itemName, itemId
        end
    end

    -- 3. Unit / NPC / Player
    if not copyId then
        local unitName, _, unitGUID = SafeGet(function() return GameTooltip:GetUnit() end)
        if unitName then
            local npcId = GetNPCIDFromGUID(unitGUID)
            if npcId then
                copyName, copyId = unitName, npcId
            else
                copyName, copyId = "Player Name", unitName
            end
        end
    end

    -- 4. Aura / generic tooltip data
    if not copyId then
        local data = SafeGet(function() return GameTooltip:GetTooltipData() end)
        if data and data.id then
            if GameTooltip:IsTooltipType(7) then   -- Aura type
                local info = C_Spell and C_Spell.GetSpellInfo(data.id)
                copyName = (info and info.name) or "Aura"
            else
                copyName = "ID"
            end
            copyId = data.id
        end
    end

    -- 5. Macro on action bar
    if not copyId then
        local ok, isMacro = pcall(function() return GameTooltip:IsTooltipType(25) end)
        if ok and isMacro then
            local info = GameTooltip:GetPrimaryTooltipInfo()
            if info and info.getterArgs then
                local macroName = GetActionText and GetActionText(info.getterArgs[1])
                if macroName then
                    local idx     = GetMacroIndexByName and GetMacroIndexByName(macroName)
                    local spellId = idx and GetMacroSpell and GetMacroSpell(idx)
                    local _, link = idx and GetMacroItem and GetMacroItem(idx) or nil, nil
                    if spellId then
                        local si = C_Spell and C_Spell.GetSpellInfo(spellId)
                        if si then copyName, copyId = si.name, spellId end
                    elseif link then
                        local itemId = tonumber(link:match("item:(%d+)"))
                        if itemId then
                            local n = C_Item and C_Item.GetItemInfo(itemId)
                            if n then copyName, copyId = n, itemId end
                        end
                    end
                end
            end
        end
    end

    return copyName, copyId
end

-- ============================================================
-- Modifier check helper
-- ============================================================
local function CheckModifier(mod)
    mod = mod or "ctrl"
    if mod == "ctrl"       then return IsControlKeyDown() and not IsShiftKeyDown() and not IsAltKeyDown() end
    if mod == "shift"      then return IsShiftKeyDown()   and not IsControlKeyDown() and not IsAltKeyDown() end
    if mod == "alt"        then return IsAltKeyDown()     and not IsControlKeyDown() and not IsShiftKeyDown() end
    if mod == "ctrl+shift" then return IsControlKeyDown() and IsShiftKeyDown() end
    if mod == "ctrl+alt"   then return IsControlKeyDown() and IsAltKeyDown() end
    return false
end

-- ============================================================
-- Key handler
-- ============================================================
-- Timestamp of the last time we opened the copy dialog.
-- Used to swallow OS/WoW key-repeat events: OnKeyDown fires repeatedly
-- (~every 30 ms) while a key is held, which would open a second dialog
-- before the user has even released the key.
local _lastCopyTime = 0

function CopyTooltip:OnKeyDown(key)
    local db = GetDB()
    if not db or not db.enabled then return end
    local cfgKey = strupper(db.key or "C")
    if strupper(key) ~= cfgKey then return end
    if not CheckModifier(db.modifier or "ctrl") then return end
    -- Block in combat and in Mythic+ (consistent with NorskenUI)
    if InCombatLockdown() then return end
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive() then return end
    if not GameTooltip:IsShown() then return end

    -- Throttle: ignore key-repeat events within 0.5 s of the last trigger
    local now = GetTime()
    if now - _lastCopyTime < 0.5 then return end
    _lastCopyTime = now

    local copyName, copyId = ExtractTooltipData()
    if copyId then
        EnsureDialog()
        StaticPopup_Show(DIALOG_NAME, copyName or "?", nil, tostring(copyId))
    end
end

-- ============================================================
-- AceAddon Module lifecycle
-- ============================================================
function CopyTooltip:OnEnable()
    if IsLoggedIn() then
        self:OnLogin()
    else
        self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
    end
end

function CopyTooltip:OnDisable()
    self:UnregisterAllEvents()
    if self.keyFrame then
        self.keyFrame:EnableKeyboard(false)
    end
end

function CopyTooltip:OnLogin()
    local db = GetDB()
    if not db or not db.enabled then return end
    self:Activate()
end

function CopyTooltip:Activate()
    EnsureDialog()
    if not self.keyFrame then
        local f = CreateFrame("Frame", "SP_CopyTooltipFrame", UIParent)
        f:SetSize(0, 0)               -- explicitly 0×0 — must never intercept mouse
        f:SetPropagateKeyboardInput(true)
        f:EnableMouse(false)          -- belt-and-suspenders: block all mouse events
        f:SetScript("OnKeyDown", function(_, key)
            CopyTooltip:OnKeyDown(key)
        end)
        self.keyFrame = f
    end
    self.keyFrame:EnableKeyboard(true)
end

function CopyTooltip:Deactivate()
    if self.keyFrame then
        self.keyFrame:EnableKeyboard(false)
    end
end

-- Called from GUI toggle
function CopyTooltip.Refresh()
    local db = GetDB()
    if db and db.enabled then
        CopyTooltip:Activate()
    else
        CopyTooltip:Deactivate()
    end
end
