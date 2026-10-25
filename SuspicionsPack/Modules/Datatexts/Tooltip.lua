-- SuspicionsPack — Datatexts: the tooltip
--
-- A private GameTooltip, so a LibDataBroker object's OnTooltipShow(tt) and the
-- usual AddLine / AddDoubleLine work as they would anywhere, in Plumber's box.
--
-- THE BACKDROP: Blizzard re-Shows the tooltip's NineSlice on every hide
-- (GameTooltip_OnHide -> SharedTooltip_SetBackdropStyle) and after data-driven
-- shows (TooltipDataHandler), but never touches its alpha -- checked on the
-- `forever` branch of Gethe/wow-ui-source. So the NineSlice is made invisible
-- once with SetAlpha(0), and the box is drawn on the tooltip itself: a child
-- frame would bury its text lines.

local SP   = SuspicionsPack
local DT   = SP.Datatexts
local Skin = SP.Skin
local FT   = Skin.FOREVER_TEXT

local tt

local function Get()
    if tt then return tt end
    tt = CreateFrame("GameTooltip", "SP_DatatextTooltip", UIParent, "GameTooltipTemplate")
    if tt.NineSlice then tt.NineSlice:SetAlpha(0) end
    Skin.PlumberBox(tt)
    return tt
end
DT.GetTooltip = Get

-- True when `owner` sits in the top half of the screen, where a panel opens
-- below it; in the bottom half it opens above.
function DT.IsTopHalf(owner)
    local _, y = owner:GetCenter()
    if not y then return false end
    local screen = UIParent:GetHeight() * UIParent:GetEffectiveScale()
    return y * owner:GetEffectiveScale() > screen / 2
end

-- Puts `frame` under or over `owner`, `gap` away (the Plumber box's rim sits
-- 8 outside its frame, so the gap clears it).
function DT.PlaceNear(frame, owner, gap)
    gap = gap or 12
    frame:ClearAllPoints()
    if DT.IsTopHalf(owner) then
        frame:SetPoint("TOP", owner, "BOTTOM", 0, -gap)
    else
        frame:SetPoint("BOTTOM", owner, "TOP", 0, gap)
    end
end

-- A datatext may redraw its tooltip from an event its own build fires
-- synchronously (Gold asking for the token price): ignored while a build is
-- under way, or the outer build would append its lines a second time.
local building = false

function DT.ShowTooltip(slot, d)
    if building then return end
    building = true
    local t = Get()
    t:SetOwner(slot, "ANCHOR_NONE")
    DT.PlaceNear(t, slot)
    t:ClearLines()
    local ok, err = pcall(d.Tooltip, DT.O(slot.id), t, slot)
    building = false
    if not ok then geterrorhandler()(err) end
    if t:NumLines() > 0 then t:Show() else t:Hide() end
end

function DT.HideTooltip()
    if tt then tt:Hide() end
end

function DT.TooltipOwner()
    return tt and tt:IsShown() and tt:GetOwner() or nil
end

-- ---- lines, in Plumber's colours -------------------------------------------
-- Header in the game's gold, labels cream, values white, notes and hints in
-- Plumber's readable grey.
local CREAM, READ, GOLD = FT.cream, FT.readable, FT.gold

function DT.TipHeader(t, text, right)
    if right then
        t:AddDoubleLine(text, right, GOLD[1], GOLD[2], GOLD[3], READ[1], READ[2], READ[3])
    else
        t:AddLine(text, GOLD[1], GOLD[2], GOLD[3])
    end
end

-- A label / value pair. `r, g, b` colour the value (white when nil).
function DT.TipLine(t, left, right, r, g, b)
    if right == nil then
        t:AddLine(left, CREAM[1], CREAM[2], CREAM[3], true)
    else
        t:AddDoubleLine(left, right, CREAM[1], CREAM[2], CREAM[3], r or 1, g or 1, b or 1)
    end
end

function DT.TipNote(t, text)
    t:AddLine(text, READ[1], READ[2], READ[3], true)
end

function DT.TipSpace(t)
    t:AddLine(" ")
end
