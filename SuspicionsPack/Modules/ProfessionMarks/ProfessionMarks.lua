-- SuspicionsPack — ProfessionMarks (WoW: Forever only, see the .toc gate)
--
-- An item one of this character's professions wants gets that profession's icon in
-- its corner, so it does not get sold, and the tooltip says who wants it.
--
-- What counts: a reagent of any of the profession's recipes, learned or not; a tool
-- it needs in the bags; a recipe item not learned yet. It leans towards keeping: a
-- wrong mark costs a bag slot, a wrong sale costs the item.
--
-- Each item is judged once and the answer kept until the character's professions
-- change or a recipe is learned, so repainting a bag window asks the client nothing.

local SP = SuspicionsPack
local hooksecurefunc = SP.Perf.HookFunc("ProfessionMarks")

local PM = SP:NewSPModule("ProfessionMarks", "professionMarks")
SP.ProfessionMarks = PM

local Data = SP.ProfessionItems

local _issecretvalue = issecretvalue or function() return false end

-- Rogues' Poisons is a skill GetProfessions does not list. Ask for its child line too:
-- the game files bandages under First Aid's child line, not First Aid itself.
local UNLISTED_LINES = { 40, 2988 }

local TOOL, RECIPE = "tool", "recipe"

local OWN_COLOR   = { 0.35, 0.85, 0.45 }
local OTHER_COLOR = { 0.5, 0.5, 0.5 }

local active = false

-- ============================================================
-- This character's professions
-- ============================================================
local myLines = {}    -- [skill line] = its rank among them: main professions first
local myKey   = nil   -- the same as text, to tell when they changed
local verdicts = {}   -- [itemID] = file IDs of its marks, or false for none

local function HasSkill(line)
    local info = C_SkillInfo.GetSkillLineInfoByID(line)
    if _issecretvalue(info) or not info then return false end
    local rank = info.rank
    return not _issecretvalue(rank) and type(rank) == "number" and rank > 0
end

-- Reads them; answers whether they differ from what was known.
local function ReadProfessions()
    local lines, count, key = {}, 0, ""
    local function Add(line)
        if _issecretvalue(line) then return end
        line = Data.parents[line] or line
        if Data.atlases[line] then
            count = count + 1
            lines[line] = count
            key = key .. line .. ","
        end
    end
    local function AddIndex(index)
        if not _issecretvalue(index) and index then Add((select(7, GetProfessionInfo(index)))) end
    end
    local prof1, prof2, firstAid, fishing, cooking = GetProfessions()
    AddIndex(prof1)
    AddIndex(prof2)
    AddIndex(cooking)
    AddIndex(firstAid)
    AddIndex(fishing)
    for _, line in ipairs(UNLISTED_LINES) do
        if HasSkill(line) then Add(line) end
    end
    if key == myKey then return false end
    myLines, myKey = lines, key
    SP:Debug("ProfessionMarks", "lines:", key)
    return true
end

-- ============================================================
-- What an item is for
-- ============================================================
-- Everything the game says wants it: [skill line] = recipes using it, TOOL or RECIPE.
local function Uses(itemID)
    local uses
    local function Note(line, what)
        uses = uses or {}
        if uses[line] == nil then uses[line] = what end
    end
    local reagents = Data.reagents[itemID]
    if reagents then
        for line, recipes in pairs(reagents) do Note(line, recipes) end
    end
    local tools = Data.tools[itemID]
    if tools then
        for _, line in ipairs(tools) do Note(line, TOOL) end
    end
    local recipeLine = Data.recipes[itemID]
    if recipeLine then Note(recipeLine, RECIPE) end
    return uses
end

-- Whether a recipe item's tooltip says "Already known": the sentence the player reads,
-- true however the recipe was learned. Nil while the item's data is not loaded: its
-- tooltip is then only the "Retrieving item information" placeholder.
local function RecipeKnown(itemID)
    if not C_Item.IsItemDataCachedByID(itemID) then
        C_Item.RequestLoadItemDataByID(itemID)
        return nil
    end
    local info = C_TooltipInfo.GetItemByID(itemID)
    local lines = info and info.lines
    if not lines or #lines == 0 then return nil end
    for _, line in ipairs(lines) do
        local text = line.leftText
        if not _issecretvalue(text) and text == ITEM_SPELL_KNOWN then return true end
    end
    return false
end

local function ByRank(a, b) return myLines[a] < myLines[b] end

local function MarksFor(itemID)
    local verdict = verdicts[itemID]
    if verdict ~= nil then return verdict end

    local wanted, settled = nil, true
    local uses = Uses(itemID)
    if uses then
        for line, what in pairs(uses) do
            if myLines[line] then
                local keep = true
                if what == RECIPE then
                    local known = RecipeKnown(itemID)
                    -- Not loaded: keep the mark for now and ask again at the next paint.
                    if known == nil then settled = false end
                    keep = not known
                end
                if keep then
                    wanted = wanted or {}
                    wanted[#wanted + 1] = line
                end
            end
        end
    end

    local marks = false
    if wanted then
        table.sort(wanted, ByRank)
        marks = {}
        for i, line in ipairs(wanted) do marks[i] = Data.atlases[line] end
    end
    if settled then verdicts[itemID] = marks end
    return marks
end

-- ============================================================
-- The glyphs on a slot
-- ============================================================
-- Kept here and not on the button: EllesmereUI's are secure item buttons.
local slots = {}   -- [button] = { { icon, atlas }, ... }

-- A slot has room for two glyphs, in its top two quarters; the tooltip lists them all.
-- Quarters rather than a size in pixels, so a glyph fits a grid slot and a list row's
-- smaller icon alike. Below 6 on the OVERLAY layer: EllesmereUI's Quick Actions draws
-- its shade and spell icon at 6 and 7, and those are meant to win.
local function MakeMark(host, corner, inner)
    local icon = host:CreateTexture(nil, "OVERLAY", nil, 5)
    icon:SetPoint(corner, host, corner, corner == "TOPRIGHT" and -1 or 1, -1)
    icon:Hide()
    return { icon = icon, host = host, inner = inner }
end

-- Pixels a glyph grows towards the middle of the slot, set by eye: First Aid's solid
-- cross fills its whole box and looks heavy, Cooking's has empty space around it.
local GLYPH_GROWTH = {
    ["worldquest-icon-firstaid"] = -3,
    ["worldquest-icon-cooking"]  = 3,
}

-- Anchoring the same point again replaces the anchor, so a reused slot keeps no old size.
local function SizeMark(mark, atlas)
    local grow = GLYPH_GROWTH[atlas] or 0
    mark.icon:SetPoint(mark.inner, mark.host, "CENTER", mark.inner == "BOTTOMLEFT" and -grow or grow, -grow)
end

local function ShowMarks(slot, marks)
    for i, mark in ipairs(slot) do
        local atlas = marks and marks[i] or nil
        if mark.atlas ~= atlas then
            mark.atlas = atlas
            if atlas then
                mark.icon:SetAtlas(atlas)
                SizeMark(mark, atlas)
            end
            mark.icon:SetShown(atlas ~= nil)
        end
    end
end

-- A slot's two glyphs on `host`, empty. Public with ShowMarks: the setup tour's
-- example bag draws with them, so it shows the marks exactly as the bags do.
function PM.NewMarks(host)
    return { MakeMark(host, "TOPRIGHT", "BOTTOMLEFT"), MakeMark(host, "TOPLEFT", "BOTTOMRIGHT") }
end
PM.ShowMarks = ShowMarks

local function PaintSlot(button, host, itemID)
    -- Before the truthiness test: `itemID and` already branches on the value.
    if _issecretvalue(itemID) then itemID = nil end
    local marks = itemID and MarksFor(itemID)
    local slot = slots[button]
    if not slot then
        if not marks then return end
        slot = PM.NewMarks(host)
        slots[button] = slot
    end
    ShowMarks(slot, marks)
end

-- ============================================================
-- Bag windows
-- ============================================================
-- Wrapped by hand: EllesmereUI calls it through securecallfunction, which the game's
-- profiler does not count, and this is the path that runs for every slot.
local PaintEllesmereSlot = SP.Perf.Wrap("ProfessionMarks", "PaintEllesmereSlot", function(button, data)
    local info = data.info
    PaintSlot(button, button._textOverlay or button, info and info.itemID)
end)

local function PaintBlizzardBag(frame)
    if not active then return end
    for _, button in frame:EnumerateValidItems() do
        PaintSlot(button, button, C_Container.GetContainerItemID(button:GetBagID(), button:GetID()))
    end
end

local blizzardBags   -- the game's bag windows, once their redraws are followed

local function FollowBlizzardBags()
    if blizzardBags then return end
    blizzardBags = {}
    local function Follow(frame)
        if frame and frame.UpdateItems then
            blizzardBags[#blizzardBags + 1] = frame
            hooksecurefunc(frame, "UpdateItems", PaintBlizzardBag)
        end
    end
    Follow(ContainerFrameCombinedBags)
    local index = 1
    while _G["ContainerFrame" .. index] do
        Follow(_G["ContainerFrame" .. index])
        index = index + 1
    end
end

-- Only the windows on screen: EllesmereUI's refreshes skip a hidden one, and each paints
-- everything the next time it opens. Its bags, reagent bag and bank each refresh apart.
local function Repaint()
    if EUI_Bags and EUI_Bags.RefreshInventory then EUI_Bags:RefreshInventory() end
    if EUI_BagsReagent and EUI_BagsReagent.RefreshInventory then EUI_BagsReagent:RefreshInventory() end
    if EUI_BankFrame and EUI_BankFrame.RefreshBank then EUI_BankFrame:RefreshBank() end
    for _, frame in ipairs(blizzardBags or {}) do
        if frame:IsShown() then PaintBlizzardBag(frame) end
    end
end

-- ============================================================
-- The tooltip
-- ============================================================
local names = {}   -- [skill line] = the profession's name in the client's language

local function NameOf(line)
    local name = names[line]
    if not name then
        name = C_TradeSkillUI.GetTradeSkillDisplayName(line)
        if not name or name == "" then name = UNKNOWN end
        names[line] = name
    end
    return name
end

-- What the tooltip says about one of this character's professions, and in which colour.
local function DescribeUse(itemID, what)
    if what == TOOL then return "tool", OWN_COLOR end
    if what == RECIPE then
        if RecipeKnown(itemID) then return "recipe already known", OTHER_COLOR end
        return "recipe to learn", OWN_COLOR
    end
    return what == 1 and "1 recipe" or (what .. " recipes"), OWN_COLOR
end

local function OnItemTooltip(tooltip, data)
    if not active or (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) then return end
    local db = PM:GetDB()
    if not (db and db.tooltip) then return end
    local itemID = data and data.id
    if _issecretvalue(itemID) then return end
    local uses = Uses(itemID)
    if not uses then return end

    local mine, others = {}, {}
    for line in pairs(uses) do
        if myLines[line] then mine[#mine + 1] = line
        else others[#others + 1] = NameOf(line) end
    end
    table.sort(mine, ByRank)
    table.sort(others)

    for _, line in ipairs(mine) do
        local text, color = DescribeUse(itemID, uses[line])
        tooltip:AddLine(("|A:%s:14:14|a %s: %s"):format(Data.atlases[line], NameOf(line), text),
            color[1], color[2], color[3])
    end
    if #others > 0 then
        tooltip:AddLine("Not your profession: " .. table.concat(others, ", "),
            OTHER_COLOR[1], OTHER_COLOR[2], OTHER_COLOR[3], true)
    end
    -- No Show() here: the game calls it right after the post-calls, and sizes the tooltip.
end

local tooltipHooked = false

local function HookTooltip()
    if tooltipHooked then return end
    tooltipHooked = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end

-- ============================================================
-- Lifecycle
-- ============================================================
function PM:OnSkillLinesChanged()
    -- A weapon skill-up can fire this mid-fight. Professions never change in combat.
    if InCombatLockdown() then return end
    if ReadProfessions() then
        wipe(verdicts)
        Repaint()
    end
end

function PM:OnRecipeLearned()
    wipe(verdicts)
    Repaint()
end

function PM:Activate()
    active = true
    self:RegisterEvent("SKILL_LINES_CHANGED", "OnSkillLinesChanged")
    self:RegisterEvent("NEW_RECIPE_LEARNED", "OnRecipeLearned")
    HookTooltip()
    FollowBlizzardBags()
    if EUI_Bags and EUI_Bags.RegisterItemOverlayIcon then
        EUI_Bags.RegisterItemOverlayIcon("SuspicionsPack_ProfessionMarks", PaintEllesmereSlot)
    end
    ReadProfessions()
    wipe(verdicts)
    Repaint()
end

function PM:Deactivate()
    active = false
    if EUI_Bags and EUI_Bags.UnregisterItemOverlayIcon then
        EUI_Bags.UnregisterItemOverlayIcon("SuspicionsPack_ProfessionMarks")
    end
    for _, slot in pairs(slots) do ShowMarks(slot, nil) end
end
