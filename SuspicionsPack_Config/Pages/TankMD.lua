-- SuspicionsPack Options — Auto misdirection
--
-- The click-to-copy macro rows are not settings, so they go in through
-- Custom(). Two notes on how they behave:
--
--   * The StaticPopup was registered inside the old builder, so opening the page
--     rewrote a WoW global every time. It is registered once, at file scope.
--   * Custom() rows get a SetEnabled that BLOCKS THE CLICK rather than merely
--     dimming, which is what the old page lacked. These two are deliberately
--     exempted from the page gate (`_manualEnable`): copying a macro is useful
--     BEFORE the module is switched on, and the old page's rows -- never added
--     to any gated set -- stayed clickable for exactly that reason.

local ADDON, ns = ...
local GUI = ns.GUI

local MACRO_DIALOG = "SP_TANKMD_MACRO_COPY"

StaticPopupDialogs[MACRO_DIALOG] = {
    text           = "Press  |cffffffffCtrl+C|r  to copy.",
    button1        = CLOSE or "Close",
    hasEditBox     = true,
    EditBoxWidth   = 320,
    timeout        = 0,
    whileDead      = true,
    hideOnEscape   = true,
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

local MACRO_ROW_H = 28

-- A link-style row: caption on top, the macro text underneath, "copy" on the
-- right. Clicking opens the dialog above with the text selected.
local function MacroRow(parent, caption, snippet)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    -- Border at full alpha, not the old page's invisible one: HoverBorder
    -- restores the theme border on leave, so a 0-alpha resting state only stayed
    -- invisible until the first mouse-over.
    GUI.Backdrop(row, "bgDark", 1, "border", 1)

    local cap = GUI.Text(row, 9, "textMuted")
    cap:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -3)
    cap:SetJustifyH("LEFT")
    cap:SetText(caption)

    local val = GUI.Text(row, 10, "accent")
    val:SetPoint("TOPLEFT",  row, "TOPLEFT",  8, -14)
    val:SetPoint("TOPRIGHT", row, "TOPRIGHT", -40, -14)
    val:SetJustifyH("LEFT")
    val:SetText(snippet)

    local hint = GUI.Text(row, 9, "textPrimary")
    hint:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    hint:SetText("copy")
    hint:Hide()

    row:SetScript("OnEnter", function() if not row._disabled then hint:Show() end end)
    row:SetScript("OnLeave", function() hint:Hide() end)
    row:SetScript("OnClick", function()
        if row._disabled then return end
        StaticPopup_Show(MACRO_DIALOG, nil, nil, snippet)
    end)
    GUI.HoverBorder(row)

    row.searchText = string.lower(caption .. " " .. snippet .. " macro copy")
    function row:SetEnabled(en)
        self._disabled = not en
        self:SetAlpha(en and 1 or 0.72)
        self:EnableMouse(en)
        if not en then hint:Hide() end
    end
    return row
end

GUI.RegisterPage{
    id       = "tankmd",
    name     = "Auto misdirection",
    category = "combat",
    dbKey    = "tankMD",
    keywords = "misdirection tricks of the trade rescue tank macro hunter rogue druid tankmd button",
    build = function(parent)
        local page = GUI.ModulePage(parent, "tankMD", "TankMD",
            "Auto misdirection",
            "Creates hidden macro buttons (TankMDButton1-5) that always target the " ..
            "current tanks, or the healers for Druids. Click one from any macro and " ..
            "it fires on the right person without you updating targets. " ..
            "Hunter, Rogue and Druid.",
            "Enable auto misdirection")

        local c2 = page:Card("Options", "Which group members count as a misdirection target.")
        c2:Dropdown{
            key   = "selectionMethod",
            label = "Selection method",
            desc  = "Main tanks are the ones flagged MAINTANK in the raid roster.",
            options = {
                { key = "tankRoleOnly",        label = "Tank role only" },
                { key = "tanksAndMainTanks",   label = "Tanks + main tanks" },
                { key = "prioritizeMainTanks", label = "Prioritise main tanks" },
                { key = "mainTanksOnly",       label = "Main tanks only" },
            },
        }

        local c3 = page:Card("Macro usage")
        c3:Note("Put this in a macro for your misdirection, tricks or rescue spell. " ..
                "The buttons update themselves when the roster changes. " ..
                "Type /tankmd in chat to see the current assignments.")
        -- _manualEnable keeps these out of the page's enable cascade. They copy
        -- text to the clipboard and touch nothing else, so there is no reason to
        -- make the user switch the module on before they can read the macro --
        -- and every reason to let them set the macro up first.
        local m1 = c3:Custom(MacroRow(parent, "Button 1 (primary target)",
            "#showtooltip [Your spell]  /click TankMDButton1"), MACRO_ROW_H)
        local m2 = c3:Custom(MacroRow(parent, "Button 2 (secondary target)",
            "#showtooltip [Your spell]  /click TankMDButton2"), MACRO_ROW_H)
        m1._manualEnable = true
        m2._manualEnable = true

        page:Finish()
    end,
}
