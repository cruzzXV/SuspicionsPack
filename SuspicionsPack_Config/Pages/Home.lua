-- SuspicionsPack Options — Home
--
-- The landing page: a hero banner, a few blocks of prose, and the profile
-- export/import engine.
--
-- The serializer, the deep merge and the modal dialog live at FILE SCOPE. The
-- old page rebuilt all three as closures inside the builder, so every visit to
-- Home allocated a fresh copy of the whole engine, and the dialog's colours
-- were captured at that moment and never updated.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack
local W   = GUI.W

local CLOSE_TEX = "Interface\\AddOns\\SuspicionsPack\\Media\\Icons\\cross.png"
local ERR       = "|cffff4444[SuspicionsPack]|r "

-- ============================================================
-- Serialization
--
-- AceSerializer-3.0 + LibDeflate: safe serialization plus compression, so the
-- string is short enough to paste into a chat window.
--
-- Resolved on use rather than at load: this addon is load-on-demand and the
-- libraries are embedded in the parent, so a file-scope LibStub call would be
-- fine today and a silent nil the day the load order changes.
-- ============================================================

local function Libs()
    if not LibStub then return nil, nil end
    return LibStub("AceSerializer-3.0", true), LibStub("LibDeflate", true)
end

local function SP_Export(data)
    local AceSer, LibDefl = Libs()
    if not AceSer or not LibDefl then return nil, "AceSerializer or LibDeflate not loaded" end
    local serialized = AceSer:Serialize(data)
    local compressed = LibDefl:CompressDeflate(serialized, { level = 9 })
    return LibDefl:EncodeForPrint(compressed), nil
end

local function SP_Import(str)
    local AceSer, LibDefl = Libs()
    if not AceSer or not LibDefl then return nil, "AceSerializer or LibDeflate not loaded" end
    if not str or str:match("^%s*$") then return nil, "Empty string" end
    local decoded = LibDefl:DecodeForPrint(str)
    if not decoded then return nil, "Decode failed \226\128\148 not a valid profile string" end
    local decompressed = LibDefl:DecompressDeflate(decoded)
    if not decompressed then return nil, "Decompress failed \226\128\148 string may be corrupted" end
    local ok, result = AceSer:Deserialize(decompressed)
    if not ok then return nil, "Deserialize failed: " .. tostring(result) end
    if type(result) ~= "table" then return nil, "Not a valid profile table" end
    return result, nil
end

-- Merges an imported profile into the live one.
--
-- Two guards, both learned the hard way. The source is an arbitrary string a
-- stranger pasted, so:
--   * only keys the CURRENT defaults declare are copied. Without this, an
--     export taken before a section was deleted re-injects those dead keys
--     permanently -- exactly what the migration runner just cleaned up.
--   * `_migrations` is never copied, or importing an old profile would carry
--     its flags in and convince the runner that migrations already ran on data
--     that has not been migrated.
local function SP_DeepMerge(dest, src, schema)
    -- An EMPTY schema table means "unconstrained map", not "nothing allowed".
    -- Several profile defaults are declared as `{}` because they hold pure user
    -- data with unpredictable keys -- cvars, drawer.buttonRules,
    -- movementAlert.disabledSpells and movementAlert.spellOverrides. Treating
    -- those as an empty whitelist silently dropped every one of the user's
    -- entries on import.
    local unconstrained = (schema == nil) or (next(schema) == nil)

    for k, v in pairs(src) do
        if k ~= "_migrations" and k ~= "_dbVersion" then
            if unconstrained or schema[k] ~= nil then
                -- Explicit lookup, not `schema and schema[k] or nil`: that
                -- idiom collapses a legitimately `false` schema value to nil,
                -- which then reads as "unconstrained" and lets arbitrary keys
                -- through on the next pass.
                local sub
                if type(schema) == "table" then sub = schema[k] end

                if type(v) == "table" and type(dest[k]) == "table" then
                    SP_DeepMerge(dest[k], v, sub)
                elseif sub == nil or type(v) == type(sub) then
                    -- Refuse a type swap: without this, importing a table over
                    -- a boolean default turned that key into a table and every
                    -- later import bypassed the schema under it.
                    dest[k] = v
                end
            end
        end
    end
end

-- ============================================================
-- The export/import dialog
--
-- UIParent-parented so it can be bigger than the options window and dragged
-- clear of it. Built once, on first use, and kept on SP for the session.
--
-- Every colour goes through the paint registry. This frame is one of the two
-- singletons the old theme rebuild could never reach, so it used to stay in
-- whatever theme was active when it was first opened, forever.
-- ============================================================

local function GetProfileDialog()
    if SP._profileDialog then return SP._profileDialog end

    local SB_W = 4   -- scrollbar width; matches the main window's

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
    GUI.Backdrop(dlg, "bgDark", 0.97, "border", 1)
    dlg:Hide()

    -- ---- title bar ----
    local titleBar = CreateFrame("Frame", nil, dlg, "BackdropTemplate")
    titleBar:SetHeight(34)
    titleBar:SetPoint("TOPLEFT",  dlg, "TOPLEFT",  0, 0)
    titleBar:SetPoint("TOPRIGHT", dlg, "TOPRIGHT", 0, 0)
    GUI.Backdrop(titleBar, "bgMedium", 1, "border", 1)

    local accentBar = GUI.Tex(titleBar, "OVERLAY", "accent", 0.9)
    accentBar:SetHeight(2)
    accentBar:SetPoint("BOTTOMLEFT",  titleBar, "BOTTOMLEFT",  0, 0)
    accentBar:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)

    local titleFS = GUI.Text(titleBar, 13, "textPrimary")
    titleFS:SetPoint("LEFT", titleBar, "LEFT", 14, 0)
    dlg._titleFS = titleFS

    -- The same cross the window header uses, rather than a multiplication sign
    -- in a font that has no glyph for it.
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -8, 0)
    local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
    closeTex:SetAllPoints()
    closeTex:SetTexture(CLOSE_TEX)
    closeTex:SetRotation(math.rad(45))
    GUI.Paint(closeTex, function(f, t) f:SetVertexColor(t.textMuted[1], t.textMuted[2], t.textMuted[3], 1) end)
    closeBtn:SetScript("OnEnter", function()
        local t = GUI.T
        closeTex:SetVertexColor(t.accent[1], t.accent[2], t.accent[3], 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        local t = GUI.T
        closeTex:SetVertexColor(t.textMuted[1], t.textMuted[2], t.textMuted[3], 1)
    end)
    closeBtn:SetScript("OnClick", function() dlg:Hide() end)

    local descFS = GUI.Text(dlg, 11, "textMuted")
    descFS:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT", 14, -10)
    descFS:SetPoint("TOPRIGHT", dlg,      "TOPRIGHT",  -14,   0)
    descFS:SetJustifyH("LEFT")
    dlg._descFS = descFS

    -- ---- the text area ----
    local boxBg = CreateFrame("Frame", nil, dlg, "BackdropTemplate")
    boxBg:SetPoint("TOPLEFT",     descFS, "BOTTOMLEFT",  -2, -10)
    boxBg:SetPoint("BOTTOMRIGHT", dlg,    "BOTTOMRIGHT", -14,  52)
    GUI.Backdrop(boxBg, "bgMedium", 1, "border", 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, boxBg, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT",     boxBg, "TOPLEFT",      6,          -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", boxBg, "BOTTOMRIGHT", -(SB_W + 8),  6)

    -- Blizzard's template ships its own chrome: a bordered track, two arrow
    -- buttons and a textured thumb. All of it is suppressed and replaced by the
    -- pack's hairline bar, and each piece gets an OnShow that re-hides it,
    -- because the template shows them again whenever the range changes.
    local sb = scrollFrame.ScrollBar
    if sb then
        sb:ClearAllPoints()
        sb:SetPoint("TOPRIGHT",    boxBg, "TOPRIGHT",    -4, -6)
        sb:SetPoint("BOTTOMRIGHT", boxBg, "BOTTOMRIGHT", -4,  6)
        sb:SetWidth(SB_W)
        for _, k in ipairs({ "Background", "Top", "Middle", "Bottom",
                             "ScrollUpButton", "ScrollDownButton", "trackBG" }) do
            if sb[k] then
                sb[k]:Hide()
                sb[k]:SetScript("OnShow", function(s) s:Hide() end)
            end
        end
        for _, child in ipairs({ sb:GetChildren() }) do
            if child.IsObjectType and child:IsObjectType("Button") then
                child:Hide()
                child:SetScript("OnShow", function(s) s:Hide() end)
            end
        end
        local track = GUI.Tex(sb, "BACKGROUND", "bgDark")
        track:SetAllPoints()
        sb:SetThumbTexture(SP.BLANK)
        local thumb = sb:GetThumbTexture()
        if thumb then
            thumb:SetWidth(SB_W)
            GUI.Paint(thumb, function(f, t) f:SetColorTexture(t.accent[1], t.accent[2], t.accent[3], 0.75) end)
        end
        sb:SetAlpha(0)   -- hidden until the content overflows
    end
    for _, child in ipairs({ scrollFrame:GetChildren() }) do
        if child.IsObjectType and child:IsObjectType("Button") then
            child:Hide()
            child:SetScript("OnShow", function(s) s:Hide() end)
        end
    end

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetMaxLetters(0)
    editBox:SetTextInsets(4, 4, 4, 4)
    editBox:EnableMouse(true)
    editBox:SetWidth(scrollFrame:GetWidth())
    GUI.ApplyFont(editBox, 10)
    GUI.Paint(editBox, function(f, t) f:SetTextColor(t.textPrimary[1], t.textPrimary[2], t.textPrimary[3], 1) end)
    scrollFrame:SetScrollChild(editBox)
    scrollFrame:SetScript("OnSizeChanged", function(sf) editBox:SetWidth(sf:GetWidth()) end)

    local function UpdateScrollbar()
        if not sb then return end
        sb:SetAlpha((editBox:GetHeight() > scrollFrame:GetHeight() + 2) and 1 or 0)
    end
    scrollFrame:HookScript("OnVerticalScroll", UpdateScrollbar)
    editBox:HookScript("OnSizeChanged",       UpdateScrollbar)

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(sf, delta)
        local maxScroll = sf:GetVerticalScrollRange()
        sf:SetVerticalScroll(math.max(0, math.min(sf:GetVerticalScroll() - delta * 60, maxScroll)))
        UpdateScrollbar()
    end)

    editBox:SetScript("OnEscapePressed", function() dlg:Hide() end)
    dlg._editBox = editBox

    local hintFS = GUI.Text(dlg, 10, "textMuted")
    hintFS:SetPoint("BOTTOMLEFT", dlg, "BOTTOMLEFT", 14, 16)
    dlg._hintFS = hintFS

    -- The action button changes what it does between Export and Import. Its
    -- spec table is kept, not its script: W.Button reads spec.onClick at click
    -- time, so swapping the field is enough and the button keeps its theming.
    local actionSpec = {
        text = "Close", width = 120, height = 30,
        onClick = function() dlg:Hide() end,
    }
    local actionBtn = W.Button(dlg, actionSpec)
    actionBtn:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -14, 12)
    dlg._actionBtn  = actionBtn
    dlg._actionSpec = actionSpec

    SP._profileDialog = dlg
    return dlg
end

local function ShowExport()
    if not (SP.db and SP.db.profile) then
        print(ERR .. "Export failed: no profile loaded")
        return
    end
    local str, err = SP_Export(SP.db.profile)
    if not str then
        print(ERR .. "Export failed: " .. (err or "unknown error"))
        return
    end
    local dlg = GetProfileDialog()
    dlg._titleFS:SetText(GUI.AccentHex() .. "Suspicion's Pack|r \226\128\148 Export profile")
    dlg._descFS:SetText("Select all (Ctrl+A) then copy (Ctrl+C). Send this string to your guildmates.")
    dlg._hintFS:SetText("Compressed with LibDeflate  \194\183  " .. #str .. " characters")
    -- Left enabled so the text can be clicked, selected and copied.
    dlg._editBox:SetEnabled(true)
    dlg._editBox:SetText(str)
    dlg._editBox:HighlightText()
    dlg._actionBtn:SetText("Close")
    dlg._actionSpec.onClick = function() dlg:Hide() end
    dlg:Show()
    dlg._editBox:SetFocus()
end

local function ShowImport()
    local dlg = GetProfileDialog()
    dlg._titleFS:SetText(GUI.AccentHex() .. "Suspicion's Pack|r \226\128\148 Import profile")
    dlg._descFS:SetText("Paste the profile string below, then click Apply import.")
    dlg._hintFS:SetText("Deep merge: only overwrites keys present in the string.")
    dlg._editBox:SetEnabled(true)
    dlg._editBox:SetText("")
    dlg._actionBtn:SetText("Apply import")
    dlg._actionSpec.onClick = function()
        local data, err = SP_Import(dlg._editBox:GetText())
        if not data then
            print(ERR .. "Import failed: " .. (err or "unknown error"))
            return
        end
        if not (SP.db and SP.db.profile) then
            print(ERR .. "Import failed: no profile loaded")
            return
        end
        SP_DeepMerge(SP.db.profile, data, SP.DEFAULTS and SP.DEFAULTS.profile or nil)
        if SP.RefreshTheme then SP.RefreshTheme() end
        -- RefreshTheme only repaints. The import rewrote the profile under
        -- every visible control, so they have to re-read it too -- without this
        -- the window keeps showing the pre-import values until it is closed and
        -- reopened.
        if GUI.OnProfileChanged then GUI.OnProfileChanged() end
        dlg:Hide()
        print(GUI.AccentHex() .. "[SuspicionsPack]|r Profile imported. Type /reload for full effect.")
    end
    dlg:Show()
    dlg._editBox:SetFocus()
end

-- ============================================================
-- Page
-- ============================================================

-- The accent colour is baked into these strings, so they have to be rewritten
-- on every preset change: the page is built once and cached now, where the old
-- UI threw the whole window away and got fresh colours for free.
local function AccentNote(card, textFn)
    local row = card:Note(textFn())
    GUI.Paint(row.fs, function(f) f:SetText(textFn()) end)
    return row
end

GUI.RegisterPage{
    id       = "home",
    name     = "Home",
    category = "general",
    -- No dbKey: Home is documentation plus the profile tools, so there is
    -- nothing for the sidebar's on/off dot to report.
    keywords = "home welcome start profile export import share string backup",
    build = function(parent)
        local page = GUI.NewPage(parent)

        -- ---- hero banner ----
        local charName = UnitName("player") or "Adventurer"
        local _, classToken = UnitClass("player")
        local cc = RAID_CLASS_COLORS and classToken and RAID_CLASS_COLORS[classToken]
        local nameHex = cc and string.format("|cff%02x%02x%02x",
            math.floor(cc.r * 255 + 0.5), math.floor(cc.g * 255 + 0.5), math.floor(cc.b * 255 + 0.5))

        local hero   = page:Card()
        local banner = CreateFrame("Frame", nil, parent)

        local welcome = GUI.Text(banner, 11, "textMuted")
        welcome:SetPoint("TOPLEFT", banner, "TOPLEFT", 0, 0)
        welcome:SetText("Welcome to")

        local title = GUI.Text(banner, 22, "accent")
        title:SetPoint("TOPLEFT", welcome, "BOTTOMLEFT", 0, -2)
        title:SetText("Suspicion's Pack")

        local divider = GUI.Tex(banner, "ARTWORK", "border")
        divider:SetHeight(1)
        divider:SetPoint("TOPLEFT",  banner, "TOPLEFT",  0, -46)
        divider:SetPoint("TOPRIGHT", banner, "TOPRIGHT", 0, -46)

        local hello = GUI.Text(banner, 14, "textPrimary")
        hello:SetPoint("TOPLEFT", banner, "TOPLEFT", 0, -54)
        hello:SetText(nameHex
            and ("Hello, " .. nameHex .. charName .. "|r !")
            or  ("Hello, " .. charName .. " !"))

        local ver = GUI.Text(banner, 10, "textMuted")
        ver:SetPoint("TOPLEFT", hello, "BOTTOMLEFT", 0, -4)
        GUI.Paint(ver, function(f)
            f:SetText("v" .. (SP.VERSION or "1.0.0") .. "  \194\183  Author: "
                      .. GUI.AccentHex() .. "cruzz|r")
        end)

        hero:Custom(banner, 88)

        -- ---- getting started ----
        local c1 = page:Card("Getting started",
            "Suspicion's Pack is a lightweight quality-of-life addon. Each feature " ..
            "can be toggled on or off independently from the sidebar.")
        -- "\226\128\186" is a single right angle quote, used as the bullet.
        AccentNote(c1, function()
            local a = GUI.AccentHex()
            return a .. "\226\128\186|r  Use " .. a .. "/spack|r or " .. a ..
                   "/suspicion|r to open this window at any time."
        end)
        AccentNote(c1, function()
            return GUI.AccentHex() .. "\226\128\186|r  " ..
                   "Navigate the sidebar on the left to find each module's settings."
        end)
        AccentNote(c1, function()
            local a = GUI.AccentHex()
            return a .. "\226\128\186|r  Search the box at the top of the sidebar to " ..
                   "jump straight to a setting, and use " .. a .. "Reset page|r " ..
                   "in the footer to put one back the way it shipped."
        end)

        page:Card("Support",
            "If any issue, or LUA error please dm me with the error and a good explanation.")

        page:Card("Notice",
            "This addon is a private guild project and is not intended to be published " ..
            "on any platform. Please do not share it with just anyone.")

        -- ---- profiles ----
        local c2 = page:Card("Profiles",
            "Export your current settings as a compact shareable string. Send it to a " ..
            "guildie so they can import your exact profile.")
        c2:ButtonRow{ text = "Export profile", width = 150, onClick = ShowExport }
        c2:ButtonRow{ text = "Import profile", width = 150, onClick = ShowImport }
        c2:Note("Captures all shared module settings. Strings are compressed, so they " ..
                "are safe to paste in Discord or chat.")

        -- The dialog is parented to UIParent, so hiding the page -- or closing
        -- the whole window -- does not hide it.
        parent:HookScript("OnHide", function()
            if SP._profileDialog then SP._profileDialog:Hide() end
        end)

        page:Finish()
    end,
}
