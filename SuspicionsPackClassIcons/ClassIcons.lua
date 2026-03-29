-- Suspicion's Pack — Class Icons Plugin
-- Registers custom class icon packs into Details! damage meter.
-- Ported from ElvUI_JiberishIcons (Details.lua) by Cruzz.
local ADDON_NAME = ...

local BASE = [[Interface\AddOns\SuspicionsPackClassIcons\Media\ClassIcons\]]

-- Preview texCoord: MAGE position in Jiberish 8-per-row atlas
local PREVIEW_JIBERISH = { 0.125, 0, 0.125, 0.125, 0.25, 0, 0.25, 0.125 }

local STYLES = {
    { key = "fabledpixels",   name = "Fabled Pixels",    preview = PREVIEW_JIBERISH },
    { key = "fabledpixelsv2", name = "Fabled Pixels v2", preview = PREVIEW_JIBERISH },
}

-- ============================================================
-- Register all packs into Details!
-- Guard flag ensures we only register once even if both
-- ADDON_LOADED events (ours + Details') fire.
-- ============================================================
local registered = false
local function RegisterInDetails()
    if registered then return end
    local Details = _G.Details
    if not Details or not Details.AddCustomIconSet then return end
    registered = true

    for _, style in ipairs(STYLES) do
        local path = BASE .. style.key
        Details:AddCustomIconSet(
            path,               -- unique key / texture path
            style.name,         -- display name in Details settings
            false,              -- not the default set
            path,               -- texture path (same as key)
            style.preview,      -- texCoords for the picker thumbnail
            { 16, 16 }          -- icon display size
        )
    end
end

-- ============================================================
-- Initialise on ADDON_LOADED — same timing as Jiberish.
-- We listen for both our own addon AND "Details" loading,
-- whichever fires last will be the one that registers.
-- ============================================================
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, addon)
    if addon == ADDON_NAME or addon == "Details" then
        RegisterInDetails()
    end
end)
