-- SuspicionsPack — Macro Action Bar (WoW: Forever only, see the .toc gate)
--
-- A fork of Macro Action Bar 1.2.1 by NotStraws (MIT: LICENSE in this folder, and Data/LICENSE for the
-- trainer data). A spellbook tab of one-click macros for your class's spells, each with a right-click menu
-- (where it casts, lines before and after the cast, modifier keys, sequences, variants), the same menu on
-- the action bars, and the macro's text in the bars' tooltip while Alt is held.
--
-- The other files in this folder are the original's, changed as little as possible so its later fixes can
-- be carried over: UPSTREAM.md lists every change. They share the table below as their `smb`, where the
-- original used its addon namespace; the pack's namespace is shared by every file and already holds Perf.
-- The pack adds Spells.lua and Locale.lua, for clients in other languages.
--
-- Nothing of it runs while the module is off. Each file hands its setup (frames, events, hooks, the
-- spellbook tab) to smb.onInstall, and this file runs it once, at login. It can only be done then and never
-- undone: the spellbook tab has no way back out of LibSpellBookTabs, and the action buttons' secure wraps
-- and the tooltip hook stay for the session. So switching the module on or off later asks for a reload.

local SP = SuspicionsPack

local MAB = SP:NewSPModule("MacroActionBar", "macroActionBar")
SP.MacroActionBar = MAB

local smb = {}
SP.MAB = smb

smb.TITLE = "Macro Action Bar"           -- in chat and error messages, where the original printed its name
smb.ID = "SuspicionsPack_MacroActionBar" -- the spellbook tab's id, and the base of the scan tooltip's name

local ORIGINAL = "MacroActionBar"        -- the original addon's folder

local installs = {}
local installed = false
local blocked = false                    -- the original addon is loaded too

-- Called by each file as it loads, in .toc order, which is the order the original set itself up in.
function smb.onInstall(fn)
    installs[#installs + 1] = fn
end

-- The original's saved variables, kept in the pack's: MacroActionBarDB (the account's) is smb.accountDB,
-- MacroActionBarCharDB (this character's) is smb.charDB.
local function bindSaved()
    smb.accountDB = SP.GetGlobalDB().macroActionBar
    smb.charDB = SP.GetCharDB().macroActionBar
end

-- The module runs from PLAYER_LOGIN; the login is over once the world has been entered.
local loginOver = false
local loginWatch = CreateFrame("Frame")
loginWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
loginWatch:SetScript("OnEvent", SP.Perf.WrapEvent("MacroActionBar", function(self)
    self:UnregisterAllEvents()
    loginOver = true
end))

local function originalLoaded()
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return isLoaded ~= nil and isLoaded(ORIGINAL) and true or false
end

-- Whether the original Macro Action Bar addon kept this module from starting. Both would edit the same
-- WoW macros, found by name, and the spellbook would get two tabs.
function MAB.IsBlocked()
    return blocked
end

function MAB.IsInstalled()
    return installed
end

-- Asked once per switch: Activate runs again on every change on the page.
local asked -- true or false: the switch the last prompt was about
local function askReload(on)
    if asked == on then return end
    asked = on
    SP.CreateReloadPrompt(on and "Macro Action Bar starts after a reload."
        or "Macro Action Bar stays until you reload.")
end

-- Runs again on every settings change.
function MAB:Activate()
    if installed or blocked then
        asked = nil -- switched back on before reloading: nothing left to ask
        return
    end
    if loginOver then
        askReload(true)
        return
    end
    if originalLoaded() then
        blocked = true
        print("SuspicionsPack: Macro Action Bar is off while the Macro Action Bar addon is loaded."
            .. " Disable that addon to use the pack's.")
        return
    end
    installed = true
    bindSaved()
    for _, install in ipairs(installs) do install() end
end

function MAB:Deactivate()
    if installed then
        askReload(false)
    else
        asked = nil -- switched back off before reloading
    end
end

-- /spack macros: opens the spellbook on the page, or closes it.
function MAB.OpenPage()
    if installed then
        smb.openPage()
    elseif blocked then
        print("SuspicionsPack: Macro Action Bar is off while the Macro Action Bar addon is loaded.")
    elseif MAB:IsOn() then
        print("SuspicionsPack: Macro Action Bar starts after a reload.")
    else
        print("SuspicionsPack: Macro Action Bar is off. Turn it on in /spack, Interface.")
    end
end
