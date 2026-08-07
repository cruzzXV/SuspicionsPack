-- SuspicionsPack — EnhancedObjectiveText Module
-- Displays quest objective / error messages in a larger format.
local SP = SuspicionsPack

local EOT = SP:NewSPModule("EnhancedObjectiveText", "enhancedObjectiveText")
SP.EnhancedObjectiveText = EOT

-- ============================================================
-- DB helper
-- Kept as a file local: Apply() is a file-scope function with no `self`, and
-- it is also reached from the dot-called EOT.Preview().
-- ============================================================
local function GetDB()
    return SP.GetDB().enhancedObjectiveText
end

-- ============================================================
-- State — original values cached once, restored on Deactivate
-- ============================================================
local _origFontSize  = nil
local _origFontFlags = nil
local _origWidth     = nil
local _origHeight    = nil
local _origPoint     = nil  -- { point, relativeTo, relativePoint, x, y }

-- ============================================================
-- Apply / Restore
-- ============================================================
local function Apply()
    local f = UIErrorsFrame
    if not f then return end
    local font, size, flags = f:GetFont()
    -- Cache originals only the first time
    _origFontSize  = _origFontSize  or size
    _origFontFlags = _origFontFlags or flags
    _origWidth     = _origWidth     or f:GetWidth()
    _origHeight    = _origHeight    or f:GetHeight()
    if not _origPoint then
        local point, relativeTo, relPoint, ox, oy = f:GetPoint(1)
        _origPoint = { point, relativeTo, relPoint, ox, oy }
    end
    local db       = GetDB()
    local fontSize = (db and db.fontSize) or 22
    local yOffset  = (db and db.y) or 0
    f:SetFont(font, fontSize, "OUTLINE")
    f:SetWidth(800)
    f:SetHeight(120)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, yOffset)
end

local function Restore()
    local f = UIErrorsFrame
    if not (f and _origFontSize and _origFontFlags and _origWidth and _origHeight) then
        return
    end
    local font = select(1, f:GetFont())
    f:SetFont(font, _origFontSize, _origFontFlags)
    f:SetWidth(_origWidth)
    f:SetHeight(_origHeight)
    if _origPoint then
        f:ClearAllPoints()
        f:SetPoint(_origPoint[1], _origPoint[2], _origPoint[3], _origPoint[4], _origPoint[5])
    end
end

-- ============================================================
-- Activate / Deactivate
-- Everything else (Refresh / OnEnable / OnDisable) comes from SP.ModuleMixin.
-- ============================================================
function EOT:Activate()
    C_Timer.After(0.5, function()
        -- C_Timer.After cannot be cancelled, so re-read the setting instead:
        -- the user may have switched the module off inside this half-second
        -- window, and Apply() would otherwise resize UIErrorsFrame after
        -- Deactivate() had already restored it.
        if self:IsOn() then Apply() end
    end)
end

function EOT:Deactivate()
    Restore()
end

function EOT.Preview()
    local f = UIErrorsFrame
    if not f then return end
    Apply()
    f:AddExternalWarningMessage("Quest completed: Defeat the Lich King")
end
