-- SuspicionsPack — Datatexts: the Guild and Friends roster panel
--
-- What hovering the Guild or Friends datatext opens instead of a tooltip: who
-- is online, in Plumber's box, one row per person. A tooltip's lines cannot
-- be clicked, so this is a panel of its own that stays open while the cursor
-- is on the slot or on it, and closes shortly after it leaves both.
--
--   Click a row        whisper
--   Alt + click a row  invite to the group
--
-- Forever's social APIs, checked on the `forever` branch of Gethe/
-- wow-ui-source: C_FriendList, C_BattleNet (not the old BNGetFriendInfo),
-- GetGuildRosterInfo, C_GuildInfo, C_PartyInfo.InviteUnit, ChatFrameUtil.

local SP   = SuspicionsPack
local DT   = SP.Datatexts
local Skin = SP.Skin
local FT   = Skin.FOREVER_TEXT
local P    = Skin.PLUMBER

local Roster = {}
DT.Roster = Roster

local PAD      = 14
local ROW_H    = 16
local MAX_ROWS = 20
local HEAD_H   = 22
local FONT     = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"

-- Columns per kind: key in the row record, width, justification.
local COLUMNS = {
    guild = {
        { key = "display", w = 150, justify = "LEFT"   },
        { key = "level",   w = 28,  justify = "CENTER" },
        { key = "zone",    w = 150, justify = "LEFT"   },
        { key = "extra",   w = 100, justify = "LEFT"   },
        { key = "note",    w = 120, justify = "LEFT"   },
    },
    friends = {
        { key = "display", w = 190, justify = "LEFT"   },
        { key = "level",   w = 28,  justify = "CENTER" },
        { key = "zone",    w = 170, justify = "LEFT"   },
        { key = "note",    w = 140, justify = "LEFT"   },
    },
}
local GAP = 8

local function ColumnsWidth(cols)
    local w = 0
    for _, c in ipairs(cols) do w = w + c.w end
    return w + GAP * (#cols - 1)
end

-- ---- data -----------------------------------------------------------------
local classByName

-- Friends' info carries the class's localized name; colours want its token.
local function ClassToken(localized)
    if not localized then return nil end
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[localized] then return localized end
    if not classByName then
        classByName = {}
        for token, name in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do classByName[name] = token end
        for token, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do classByName[name] = token end
    end
    return classByName[localized]
end

local function ClassHex(token)
    local c = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if c then return DT.Hex(c.r, c.g, c.b) end
    return DT.Hex(FT.cream[1], FT.cream[2], FT.cream[3])
end

local function StatusTag(afk, dnd)
    if afk then return " |cff999999<AFK>|r" end
    if dnd then return " |cff999999<DND>|r" end
    return ""
end

local function ByName(a, b) return (a.sort or "") < (b.sort or "") end

function Roster.GuildRows()
    local rows = {}
    if not IsInGuild() then return rows end
    for i = 1, GetNumGuildMembers() or 0 do
        local name, rank, _, level, _, zone, note, _, online, status, class = GetGuildRosterInfo(i)
        if name and online then
            local short = Ambiguate(name, "guild")
            rows[#rows + 1] = {
                sort    = short,
                display = ClassHex(class) .. short .. "|r" .. StatusTag(status == 1, status == 2),
                level   = level and tostring(level) or "",
                zone    = zone or "",
                extra   = rank or "",
                note    = note or "",
                whisper = name,
                invite  = name,
            }
        end
    end
    table.sort(rows, ByName)
    return rows
end

function Roster.FriendRows()
    local rows = {}
    for i = 1, (C_FriendList and C_FriendList.GetNumFriends() or 0) do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.connected and info.name then
            rows[#rows + 1] = {
                sort    = info.name,
                display = ClassHex(ClassToken(info.className)) .. info.name .. "|r" .. StatusTag(info.afk, info.dnd),
                level   = info.level and tostring(info.level) or "",
                zone    = info.area or "",
                note    = info.notes or "",
                whisper = info.name,
                invite  = info.name,
            }
        end
    end
    local numBN = BNGetNumFriends and BNGetNumFriends() or 0
    for i = 1, numBN do
        local acc = C_BattleNet and C_BattleNet.GetFriendAccountInfo(i)
        local g   = acc and acc.gameAccountInfo
        if g and g.isOnline then
            local row = {
                sort  = acc.accountName or "",
                note  = acc.note or "",
                bnet  = acc.accountName,
                level = "",
                zone  = g.richPresence or g.clientProgram or "",
            }
            local wow = g.clientProgram == BNET_CLIENT_WOW and g.characterName
            if wow and g.wowProjectID == WOW_PROJECT_ID then
                -- In this very game: a character to show, invite and colour.
                local char = g.characterName
                row.display = ClassHex(ClassToken(g.className)) .. char .. "|r |cff82c5ff("
                    .. (acc.accountName or "") .. ")|r" .. StatusTag(acc.isAFK, acc.isDND)
                row.level  = g.characterLevel and tostring(g.characterLevel) or ""
                row.zone   = g.areaName or ""
                row.invite = g.realmName and (char .. "-" .. g.realmName:gsub("%s", "")) or char
            else
                row.display = "|cff82c5ff" .. (acc.accountName or "?") .. "|r" .. StatusTag(acc.isAFK, acc.isDND)
            end
            rows[#rows + 1] = row
        end
    end
    table.sort(rows, ByName)
    return rows
end

local function Whisper(row)
    if row.bnet then
        local f = (ChatFrameUtil and ChatFrameUtil.SendBNetTell) or ChatFrame_SendBNetTell
        if f then f(row.bnet) end
    elseif row.whisper then
        local f = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
        if f then f(row.whisper) end
    end
end

local function Invite(row)
    if not row.invite then return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(row.invite)
    elseif InviteUnit then
        InviteUnit(row.invite)
    end
end

-- ---- the panel ------------------------------------------------------------
local panel

local function Text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    SP.SetFontSafe(fs, FONT, size, "")
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
    fs:SetTextColor(color[1], color[2], color[3], 1)
    fs:SetWordWrap(false)
    return fs
end

local function RowEnter(row)
    row.fill:Show()
end

local function RowLeave(row)
    row.fill:Hide()
end

local function RowClick(row, button)
    if not row.data or button ~= "LeftButton" then return end
    if IsAltKeyDown() then Invite(row.data) else Whisper(row.data) end
end

local function GetRow(i)
    local row = panel.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, panel.content)
    row:SetHeight(ROW_H)
    row:RegisterForClicks("AnyUp")
    -- The brown bar under the mouse in Plumber's lists (the options window's
    -- dropdowns draw the same).
    row.fill = Skin.PlumberRect(row:CreateTexture(nil, "BACKGROUND"), P.MENU, 368, 512, 0, 48, 512)
    row.fill:SetAllPoints()
    row.fill:SetVertexColor(119 / 255, 96 / 255, 74 / 255)
    row.fill:SetBlendMode("ADD")
    row.fill:Hide()
    row.cells = {}
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    row:SetScript("OnClick", RowClick)
    panel.rows[i] = row
    return row
end

local function LayoutCells(row, cols)
    local x = 0
    for c, col in ipairs(cols) do
        local fs = row.cells[c]
        if not fs then
            fs = Text(row, 11, col.key == "note" and FT.readable or FT.cream)
            row.cells[c] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", row, "LEFT", x, 0)
        fs:SetWidth(col.w)
        fs:SetJustifyH(col.justify)
        fs:SetTextColor(unpack(col.key == "note" and FT.readable or FT.cream))
        fs:Show()
        x = x + col.w + GAP
    end
    for c = #cols + 1, #row.cells do row.cells[c]:Hide() end
end

-- Closes once the cursor has been off both the slot and the panel for a
-- moment; the gap between them is crossed without it closing.
local function AutoHide(self, elapsed)
    local over = self:IsMouseOver() or (self.owner and self.owner:IsMouseOver())
    if over then
        self.away = 0
        return
    end
    self.away = (self.away or 0) + elapsed
    if self.away > 0.3 then self:Hide() end
end

local function Build()
    panel = CreateFrame("Frame", "SP_DatatextRoster", UIParent)
    panel:SetFrameStrata("TOOLTIP")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    Skin.PlumberBox(panel)

    panel.title = Text(panel, 13, FT.gold)
    panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD)
    panel.count = Text(panel, 11, FT.readable)
    panel.count:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -PAD - 1)
    panel.motd = Text(panel, 11, FT.readable)
    panel.motd:SetWordWrap(true)
    panel.motd:SetJustifyH("LEFT")
    panel.motd:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)

    panel.divider = Skin.PlumberDivider(panel)
    panel.divider:SetHeight(24)

    local sf = CreateFrame("ScrollFrame", nil, panel)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    panel.sf, panel.content = sf, content

    -- The game's thin scroll bar, as the options window's lists use, shown
    -- only when there are more rows than fit.
    if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        local bar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
        bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, 0)
        bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 0)
        ScrollUtil.InitScrollFrameWithScrollBar(sf, bar)
        if sf.SetPanExtent then sf:SetPanExtent(ROW_H * 3) end
        panel.bar = bar
    end
    sf:EnableMouseWheel(true)

    panel.empty = Text(panel, 11, FT.readable)
    panel.hint = Text(panel, 10, FT.readable)
    panel.hint:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, PAD - 2)
    panel.hint:SetText("Click: whisper    Alt+click: invite")

    panel.rows = {}
    panel:SetScript("OnUpdate", AutoHide)
end

local function Fill()
    local kind = panel.kind
    local cols = COLUMNS[kind]
    local rows = kind == "guild" and Roster.GuildRows() or Roster.FriendRows()
    local inner = ColumnsWidth(cols)
    local width = inner + PAD * 2 + 12   -- room for the scroll bar

    if kind == "guild" then
        local name = IsInGuild() and GetGuildInfo("player") or "Guild"
        panel.title:SetText(name or "Guild")
        local total = GetNumGuildMembers() or 0
        panel.count:SetText(#rows .. " / " .. total .. " online")
        local motd = (C_GuildInfo and C_GuildInfo.GetMOTD and C_GuildInfo.GetMOTD())
            or (GetGuildRosterMOTD and GetGuildRosterMOTD()) or ""
        panel.motd:SetText(motd)
        panel.motd:SetShown(motd ~= "")
    else
        panel.title:SetText("Friends")
        panel.count:SetText(#rows .. " online")
        panel.motd:SetText("")
        panel.motd:Hide()
    end
    panel.motd:SetWidth(inner)

    local top = PAD + HEAD_H
    if panel.motd:IsShown() then top = top + (panel.motd:GetStringHeight() or 12) + 4 end
    panel.divider:ClearAllPoints()
    panel.divider:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD - 8, -(top - 10))
    panel.divider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(PAD - 8), -(top - 10))
    top = top + 10

    for i, data in ipairs(rows) do
        local row = GetRow(i)
        row.data = data
        LayoutCells(row, cols)
        for c, col in ipairs(cols) do row.cells[c]:SetText(data[col.key] or "") end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetWidth(inner)
        row.fill:Hide()
        row:Show()
    end
    for i = #rows + 1, #panel.rows do
        panel.rows[i].data = nil
        panel.rows[i]:Hide()
    end

    local visible = math.min(math.max(#rows, 1), MAX_ROWS)
    local listH   = visible * ROW_H
    panel.content:SetSize(inner, math.max(1, #rows * ROW_H))
    panel.sf:ClearAllPoints()
    panel.sf:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top)
    panel.sf:SetSize(inner, listH)
    if panel.bar then panel.bar:SetShown(#rows > MAX_ROWS) end

    panel.empty:ClearAllPoints()
    panel.empty:SetPoint("TOPLEFT", panel.sf, "TOPLEFT", 0, 0)
    panel.empty:SetText(kind == "guild" and not IsInGuild() and "Not in a guild." or "Nobody online.")
    panel.empty:SetShown(#rows == 0)

    panel:SetSize(width, top + listH + 8 + 14 + PAD)
end

-- Server requests are throttled by the server itself; asking at most every
-- ten seconds keeps us from spamming it on every hover.
-- The clock starts only once a request is really sent: at login IsInGuild()
-- can still be false until PLAYER_GUILD_UPDATE, and a dropped request must not
-- spend the wait.
local lastRequest = { guild = 0, friends = 0 }
local function RequestData(kind)
    local now = GetTime()
    if now - lastRequest[kind] < 10 then return end
    if kind == "guild" then
        if not (IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster) then return end
        C_GuildInfo.GuildRoster()
    elseif C_FriendList and C_FriendList.ShowFriends then
        C_FriendList.ShowFriends()
    else
        return
    end
    lastRequest[kind] = now
end
Roster.RequestData = RequestData

function Roster.Show(slot, kind)
    if not panel then Build() end
    if DT.HideTooltip then DT.HideTooltip() end
    panel.owner = slot
    panel.kind  = kind
    panel.away  = 0
    RequestData(kind)
    Fill()
    DT.PlaceNear(panel, slot, 12)
    panel:Show()
end

function Roster.Hide()
    if panel then panel:Hide() end
end

-- New data while the panel is open on that list.
function Roster.Refresh(kind)
    if panel and panel:IsShown() and panel.kind == kind then Fill() end
end
