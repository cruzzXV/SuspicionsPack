-- SuspicionsPack Options — Focus target marker
--
-- The marker dropdown is bound to a numeric key (1-8), with the raid icon drawn
-- inline in each entry. Picking one goes through the page's standard onChange,
-- which reaches FocusTargetMarker:Refresh -> Activate -> rewrite the macro; the
-- old page called Activate() by hand from inside the dropdown callback.

local ADDON, ns = ...
local GUI = ns.GUI

local MARKER_TEX = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"

-- Texture coordinates of each raid marker in the 4x4 sheet.
local MARKER_COORDS = {
    [1] = { 0.00, 0.25, 0.00, 0.25 },  -- Star
    [2] = { 0.25, 0.50, 0.00, 0.25 },  -- Circle
    [3] = { 0.50, 0.75, 0.00, 0.25 },  -- Diamond
    [4] = { 0.75, 1.00, 0.00, 0.25 },  -- Triangle
    [5] = { 0.00, 0.25, 0.25, 0.50 },  -- Moon
    [6] = { 0.25, 0.50, 0.25, 0.50 },  -- Square
    [7] = { 0.50, 0.75, 0.25, 0.50 },  -- Cross
    [8] = { 0.75, 1.00, 0.25, 0.50 },  -- Skull
}

local function MarkerLabel(i)
    local t = MARKER_COORDS[i] or MARKER_COORDS[5]
    return string.format("|T%s:16:16:0:0:256:256:%d:%d:%d:%d|t %s",
        MARKER_TEX, t[1] * 256, t[2] * 256, t[3] * 256, t[4] * 256,
        _G["RAID_TARGET_" .. i] or ("Marker " .. i))
end

-- Built on every refresh: the RAID_TARGET_* globals are localised strings.
local function MarkerOptions()
    local out = {}
    for i = 1, 8 do out[i] = { key = i, label = MarkerLabel(i) } end
    return out
end

GUI.RegisterPage{
    id       = "focustargetmarker",
    name     = "Focus target marker",
    category = "mythic",
    dbKey    = "focusTargetMarker",
    keywords = "focus marker raid target kick interrupt macro mouseover skull moon",
    build = function(parent)
        local page = GUI.ModulePage(parent, "focusTargetMarker", "FocusTargetMarker",
            "Focus target marker",
            "Creates a macro named \"FocusTargetMarker\" that focuses your " ..
            "mouseover, or your target if there is none, and puts the chosen raid " ..
            "marker on it. The macro is rewritten on login and on every ready check.",
            "Enable focus target marker")

        local c2 = page:Card("Options")
        c2:Toggle{
            key   = "announce",
            label = "Announce on ready check",
            desc  = "Says your kick marker in party chat when a ready check starts. " ..
                    "Healer specs are skipped.",
        }
        c2:Dropdown{
            key     = "marker",
            label   = "Raid marker",
            desc    = "The marker the macro applies. Changing it rewrites the macro now.",
            options = MarkerOptions(),
        }

        local c3 = page:Card("Macro usage")
        c3:Note("Bind the macro to a key, or call it from another macro with " ..
                "/click. The marker index is written into the macro body, so it " ..
                "works even when you have no focus.")

        page:Finish()
    end,
}
