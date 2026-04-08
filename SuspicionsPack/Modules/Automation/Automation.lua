-- Suspicion's Pack — Automation Module
-- Auto-accepts various dialogs and popups
local ADDON_NAME, NS = ...
local SP = SuspicionsPack

local function StripRealm(name)
    return name and (name:match("^([^%-]+)")) or name
end

local Automation = SP:NewModule("Automation", "AceEvent-3.0")
SP.Automation = Automation

-- ============================================================
-- Local hook guards — module-level so they survive reloads
-- Each frame tracked individually: if one frame doesn't exist yet when
-- Refresh() first runs, subsequent calls can still hook it once it appears.
-- Using a single shared flag would permanently skip hooks if the frame
-- wasn't available on the very first call.
-- ============================================================
local deleteHooked      = false
local lfdHooked         = false   -- LFDRoleCheckPopup
local lfgHooked         = false   -- LFGInvitePopup
local talkingHeadHooked = false   -- TalkingHeadFrame
local decorVendorHooked = false   -- StaticPopup_Show (decor item purchase)
local bagsBarHooked     = false   -- BagsBar / MainMenuBarBackpackButton

-- ============================================================
-- Hook: Auto Fill Delete
-- Uses hooksecurefunc (additive, safe) — NorskenUI pattern
-- ============================================================
local function SetupAutoFillDelete()
    if deleteHooked then return end
    if not (StaticPopupDialogs and StaticPopupDialogs["DELETE_GOOD_ITEM"]) then return end
    deleteHooked = true
    hooksecurefunc(StaticPopupDialogs["DELETE_GOOD_ITEM"], "OnShow", function(self)
        local eb = self.EditBox or self.editBox
        if eb then eb:SetText(_G["DELETE"] or "DELETE") end
    end)
end

-- ============================================================
-- Hook: Auto Role Check
-- Uses CompleteLFGRoleCheck(true) — the official WoW API to accept a role
-- check programmatically (same call used by AutoQue and similar addons).
--
-- To prevent the popup from being visible at all:
--   • LFG_ROLE_CHECK_SHOW event fires BEFORE the popup renders → call
--     CompleteLFGRoleCheck(true) immediately there (no defer needed).
--   • OnShow hooks run as the frame appears → SetAlpha(0) to make it
--     invisible instantly, accept on next frame, restore alpha after.
-- ============================================================
local function TryClickRoleCheckAccept()
    -- Official API — most reliable, no button-hunting needed.
    if CompleteLFGRoleCheck then
        pcall(CompleteLFGRoleCheck, true)
        return
    end
    -- Fallback: click the LFD accept button by its global name.
    local btn = _G["LFDRoleCheckPopupAcceptButton"]
    if btn and btn:IsShown() and btn:IsEnabled() then btn:Click(); return end
    -- Fallback: LFGInvitePopup (M+, raids, other activity types).
    local btn2 = _G["LFGInvitePopupAcceptButton"]
    if btn2 and btn2:IsShown() and btn2:IsEnabled() then btn2:Click() end
end

local function HideAndAccept(frame)
    if frame then frame:SetAlpha(0) end
    C_Timer.After(0, function()
        TryClickRoleCheckAccept()
        if frame then frame:SetAlpha(1) end
    end)
end

local function SetupAutoRoleCheck()
    if LFDRoleCheckPopup and not lfdHooked then
        lfdHooked = true
        LFDRoleCheckPopup:HookScript("OnShow", function()
            HideAndAccept(LFDRoleCheckPopup)
        end)
    end

    if LFGInvitePopup and not lfgHooked then
        lfgHooked = true
        LFGInvitePopup:HookScript("OnShow", function()
            HideAndAccept(LFGInvitePopup)
        end)
    end
end

-- ============================================================
-- Hook: Hide Talking Head
-- TalkingHeadFrame is lazy-loaded, so we hook TalkingHead_LoadUI
-- as a fallback if the frame isn't available yet.
-- ============================================================
local function SetupHideTalkingHead()
    if talkingHeadHooked then return end
    talkingHeadHooked = true

    local function HideHead(frame)
        local db = SP.GetDB().automation
        if db and db.hideTalkingHead and frame then frame:Hide() end
    end

    if _G.TalkingHeadFrame then
        hooksecurefunc(_G.TalkingHeadFrame, "PlayCurrent", HideHead)
    else
        hooksecurefunc("TalkingHead_LoadUI", function()
            if _G.TalkingHeadFrame then
                hooksecurefunc(_G.TalkingHeadFrame, "PlayCurrent", HideHead)
            end
        end)
    end
end

-- ============================================================
-- Hook: Auto Accept Decor Vendor Prompt  (ported from WilduTools)
-- Hooks StaticPopup_Show once and auto-clicks confirm whenever the
-- item being purchased is a decoration (C_Item.IsDecorItem).
-- ============================================================
local DECOR_POPUPS = {
    CONFIRM_PURCHASE_TOKEN_ITEM       = true,
    CONFIRM_HIGH_COST_ITEM            = true,
    CONFIRM_PURCHASE_NONREFUNDABLE_ITEM = true,
}

local function SetupAutoDecorVendor()
    if decorVendorHooked then return end
    if not (C_Item and C_Item.IsDecorItem) then return end
    decorVendorHooked = true

    hooksecurefunc("StaticPopup_Show", function(which)
        local db = SP.GetDB().automation
        if not (db and db.autoDecorVendor) then return end
        if not DECOR_POPUPS[which] then return end

        local popupFrame = StaticPopup_FindVisible(which)
        if not popupFrame then return end

        -- Extract item link: prefer the structured field, fall back to text parse
        local itemLink = popupFrame.ItemFrame and popupFrame.ItemFrame.link
        if not itemLink then
            local textFrame = popupFrame.Text
            local text = textFrame and textFrame.GetText and textFrame:GetText()
            if text then
                itemLink = text:match("|c.+|h|r")
            end
        end
        if not itemLink then return end

        if C_Item.IsDecorItem(itemLink) then
            -- Click synchronously — StaticPopup_Show has fully returned by the time
            -- hooksecurefunc fires, so the frame is set up but not yet rendered to screen.
            -- A deferred C_Timer.After(0) would let the frame paint once (visible flash);
            -- clicking here avoids that entirely.
            local btn = (popupFrame.GetButton1 and popupFrame:GetButton1())
                     or popupFrame.button1
            if btn and btn:IsShown() and btn:IsEnabled() then
                btn:Click()
            end
        end
    end)
end

-- ============================================================
-- Druid: Auto Switch to Flight Form  (ported from WilduTools)
-- Watches MOUNT_JOURNAL_USABILITY_CHANGED, PLAYER_REGEN_ENABLED,
-- and PLAYER_ENTERING_WORLD.  When the player is in ground Travel
-- Form (form 3) in a flyable area, CancelShapeshiftForm() is
-- called so they can immediately take off.  A 5-second cooldown
-- prevents rapid re-evaluation loops.
-- ============================================================
local flightFormLastCancel = 0
local flightFormTimer      = nil

local function EvaluateFlightForm()
    local db = SP.GetDB().automation
    if not (db and db.autoSwitchFlight) then return end

    local _, cls = UnitClass("player")
    if cls ~= "DRUID" then return end

    local now = GetTime()

    -- 5-second cooldown between cancels: if we just cancelled, schedule a
    -- retry for when the cooldown expires rather than bailing immediately.
    if flightFormLastCancel + 5 > now then
        if flightFormTimer then flightFormTimer:Cancel() end
        local delay = flightFormLastCancel + 5 - now
        flightFormTimer = C_Timer.NewTimer(delay, function()
            flightFormTimer = nil
            EvaluateFlightForm()
        end)
        return
    end

    if  not UnitAffectingCombat("player")
    and not (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
             and C_ChallengeMode.IsChallengeModeActive())
    and not IsInInstance()
    and IsFlyableArea()
    and (GetShapeshiftFormID() == 3)   -- 3 = ground Travel Form
    and not IsFlying()
    and not IsSubmerged()
    then
        flightFormLastCancel = now
        CancelShapeshiftForm()
    end
end

function Automation:OnFlightFormEvent()
    EvaluateFlightForm()
end

function Automation:OnFlightFormRegenEnabled()
    -- Match WilduTools: small delay so combat state fully settles first
    C_Timer.After(0.2, EvaluateFlightForm)
end

-- ============================================================
-- Event: Auto Sell Junk + Auto Repair (both on MERCHANT_SHOW)
-- ============================================================
function Automation:OnMerchantShow()
    local db = SP.GetDB().automation
    if not (db and db.enabled) then return end

    -- Sell all grey quality items
    if db.autoSellJunk then
        for bagID = 0, 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bagID) do
                local link = C_Container.GetContainerItemLink(bagID, slot)
                if link then
                    local _, _, quality, _, _, _, _, _, _, _, sellPrice = C_Item.GetItemInfo(link)
                    if quality == 0 and sellPrice and sellPrice > 0 then
                        C_Container.UseContainerItem(bagID, slot)
                    end
                end
            end
        end
    end

    -- Repair all gear
    if db.autoRepair and CanMerchantRepair and CanMerchantRepair() then
        local repairCost, canRepair = GetRepairAllCost()
        if repairCost and canRepair and repairCost > 0 then
            -- Try guild bank first if the player opted in
            if db.useGuildFunds and CanGuildBankRepair and CanGuildBankRepair() then
                local guildFunds = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney()
                if guildFunds and guildFunds >= repairCost then
                    RepairAllItems(true)
                    return
                end
            end
            -- Fall back to personal gold
            if GetMoney() >= repairCost then
                RepairAllItems(false)
            end
        end
    end
end

-- ============================================================
-- Event: Auto Role Check (manual group role check via /rolecheck)
-- ============================================================
function Automation:OnRoleCheckShow()
    -- LFG_ROLE_CHECK_SHOW fires before the popup renders, so calling
    -- immediately here may prevent it from ever appearing on screen.
    TryClickRoleCheckAccept()
    -- Defer + hide as fallback in case the immediate call was too early.
    HideAndAccept(LFDRoleCheckPopup)
end

-- ============================================================
-- Hide Bags Bar  (ported from NephUI Cooldown Manager QOL.lua)
-- Hides BagsBar / BagBar / MainMenuBarBackpackButton and the
-- expand toggle. Hooks Show + SetParent to prevent Blizzard from
-- re-showing the bar. Combat-lockdown safe (defers until regen).
-- ============================================================
local BagsBar = {}   -- namespace for the feature

local function GetBagsBarFrame()
    return _G.BagsBar
        or _G.BagBar
        or (_G.MainMenuBarBackpackButton and _G.MainMenuBarBackpackButton:GetParent())
        or nil
end

local function GetExpandToggleFrame()
    return _G.BagsBarExpandToggle or _G.BagBarExpandToggle
end

function BagsBar:IsEnabled()
    local db = SP.GetDB().automation
    return db and db.hideBagsBar
end

function BagsBar:StoreOriginalParents()
    local bar = GetBagsBarFrame()
    if bar and not self.origBarParent then
        self.origBarParent = bar:GetParent()
    end
    local toggle = GetExpandToggleFrame()
    if toggle and not self.origToggleParent then
        self.origToggleParent = toggle:GetParent()
    end
end

function BagsBar:ApplyHidden()
    if InCombatLockdown() then
        self.pending = true
        self:RegisterCombatWatcher()
        return
    end
    local bar = GetBagsBarFrame()
    if not bar then self:ScheduleRetry(); return end
    if self.applying then return end
    self.applying = true
    self:StoreOriginalParents()
    local hidden = UIParent  -- reparent to UIParent then hide
    if bar.SetParent then bar:SetParent(hidden) end
    if bar.Hide      then bar:Hide()            end
    if bar.SetAlpha  then bar:SetAlpha(0)       end
    local toggle = GetExpandToggleFrame()
    if toggle then
        if toggle.SetParent then toggle:SetParent(hidden) end
        if toggle.Hide      then toggle:Hide()            end
        if toggle.SetAlpha  then toggle:SetAlpha(0)       end
    end
    self.applying = nil
end

function BagsBar:Restore()
    if InCombatLockdown() then
        self.pending = true
        self:RegisterCombatWatcher()
        return
    end
    local bar = GetBagsBarFrame()
    if not bar then self:ScheduleRetry(); return end
    if self.applying then return end
    self.applying = true
    local parent = self.origBarParent or UIParent
    if self.origBarParent and bar.SetParent then bar:SetParent(parent) end
    if bar.SetAlpha then bar:SetAlpha(1) end
    if bar.Show     then bar:Show()      end
    local toggle = GetExpandToggleFrame()
    if toggle then
        if self.origToggleParent and toggle.SetParent then
            toggle:SetParent(self.origToggleParent)
        end
        if toggle.SetAlpha then toggle:SetAlpha(1) end
        if toggle.Show     then toggle:Show()      end
    end
    self.applying = nil
end

function BagsBar:RegisterCombatWatcher()
    if self.combatFrame then return end
    self.combatFrame = CreateFrame("Frame")
    self.combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.combatFrame:SetScript("OnEvent", function()
        if BagsBar.pending then
            BagsBar.pending = nil
            BagsBar:Update()
        end
    end)
end

function BagsBar:ScheduleRetry()
    if self.retryTimer then return end
    self.retryTimer = C_Timer.NewTimer(1, function()
        BagsBar.retryTimer = nil
        BagsBar:Update()
    end)
end

function BagsBar:EnsureHooks()
    if bagsBarHooked then return end
    local bar = GetBagsBarFrame()
    if not bar then self:ScheduleRetry(); return end
    bagsBarHooked = true
    hooksecurefunc(bar, "Show", function()
        if BagsBar:IsEnabled() then BagsBar:ApplyHidden() end
    end)
    hooksecurefunc(bar, "SetParent", function()
        if BagsBar:IsEnabled() then BagsBar:ApplyHidden() end
    end)
    local toggle = GetExpandToggleFrame()
    if toggle then
        hooksecurefunc(toggle, "Show", function()
            if BagsBar:IsEnabled() then
                if toggle.Hide then toggle:Hide() end
            end
        end)
        hooksecurefunc(toggle, "SetParent", function()
            if BagsBar:IsEnabled() then BagsBar:ApplyHidden() end
        end)
    end
end

function BagsBar:Update()
    if InCombatLockdown() then
        self.pending = true
        self:RegisterCombatWatcher()
        return
    end
    if not bagsBarHooked then self:EnsureHooks() end
    if self:IsEnabled() then
        self:ApplyHidden()
    else
        self:Restore()
    end
end

-- ============================================================
-- OnEnable: register event handlers
-- ============================================================
function Automation:OnEnable()
    self:Refresh()
end

-- ============================================================
-- Refresh: apply settings from DB
-- ============================================================
function Automation:Refresh()
    local db = SP.GetDB().automation
    if not db then return end

    -- Hooks are one-time setup (hooksecurefunc cannot be reversed)
    if db.autoFillDelete then
        SetupAutoFillDelete()
    end

    if db.autoRoleCheck then
        SetupAutoRoleCheck()
        self:RegisterEvent("LFG_ROLE_CHECK_SHOW", "OnRoleCheckShow")
    else
        self:UnregisterEvent("LFG_ROLE_CHECK_SHOW")
    end

    if db.hideTalkingHead then
        SetupHideTalkingHead()
    end

    BagsBar:Update()

    if db.autoDecorVendor then
        SetupAutoDecorVendor()
    end

    -- Events can be toggled on/off freely
    if db.autoGuildInvite or db.autoFriendInvite then
        self:RegisterEvent("PARTY_INVITE_REQUEST", "OnPartyInvite")
    else
        self:UnregisterEvent("PARTY_INVITE_REQUEST")
    end

    if db.skipCinematics then
        self:RegisterEvent("CINEMATIC_START", "OnCinematicStart")
        self:RegisterEvent("PLAY_MOVIE",      "OnPlayMovie")
    else
        self:UnregisterEvent("CINEMATIC_START")
        self:UnregisterEvent("PLAY_MOVIE")
    end

    if db.autoSellJunk or db.autoRepair then
        self:RegisterEvent("MERCHANT_SHOW", "OnMerchantShow")
    else
        self:UnregisterEvent("MERCHANT_SHOW")
    end

    -- Druid: auto switch to flight form
    if db.autoSwitchFlight then
        self:RegisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED", "OnFlightFormEvent")
        self:RegisterEvent("PLAYER_REGEN_ENABLED",            "OnFlightFormRegenEnabled")
        self:RegisterEvent("PLAYER_ENTERING_WORLD",           "OnFlightFormEvent")
        EvaluateFlightForm()
    else
        self:UnregisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED")
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if flightFormTimer then flightFormTimer:Cancel(); flightFormTimer = nil end
    end
end

-- ============================================================
-- Event: Auto-accept party invite from guildmate or friend
-- PARTY_INVITE_REQUEST fires when someone invites you to a group.
-- arg1 = inviterName (may include realm), arg2 = inviterRealm (separate)
-- ============================================================
local function HideInvitePopups()
    StaticPopup_Hide("PARTY_INVITE")
    StaticPopup_Hide("PARTY_INVITE_BY_BATTLETAG_FRIEND")
    StaticPopup_Hide("PARTY_INVITE_BY_REAL_ID_FRIEND")
end

function Automation:OnPartyInvite(event, inviterName)
    local db = SP.GetDB().automation
    if not (db and db.enabled) then return end

    local shortInviter = StripRealm(inviterName):lower()

    local function DoAccept()
        C_Timer.After(0, function()
            if not InCombatLockdown() then
                AcceptGroup()
                HideInvitePopups()
            end
        end)
    end

    if db.autoGuildInvite then
        for i = 1, GetNumGuildMembers() do
            local name = GetGuildRosterInfo(i)
            if name and StripRealm(name):lower() == shortInviter then
                DoAccept()
                return
            end
        end
    end

    if db.autoFriendInvite then
        local numFriends = C_FriendList.GetNumFriends()
        for i = 1, numFriends do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info and info.name and StripRealm(info.name):lower() == shortInviter then
                DoAccept()
                return
            end
        end
    end
end

-- ============================================================
-- Event: Skip Cinematics
-- ============================================================
function Automation:OnCinematicStart(event)
    local db = SP.GetDB().automation
    if db and db.skipCinematics then
        C_Timer.After(1.0, function()
            if CinematicFrame_CancelCinematic then
                CinematicFrame_CancelCinematic()
            end
        end)
    end
end

function Automation:OnPlayMovie(event)
    local db = SP.GetDB().automation
    if db and db.skipCinematics then
        C_Timer.After(1.0, function()
            pcall(GameMovieFinished)
        end)
    end
end
