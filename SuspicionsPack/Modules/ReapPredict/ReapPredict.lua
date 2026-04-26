-- SuspicionsPack — ReapPredict Module
-- Devourer DH dual-phase meter. Forked from ReapPredict by Tom Herbert.
-- Tracks when Reap will trigger the next phase ability (Void Metamorphosis
-- or Collapsing Star). Activates automatically for Devourer DH only.
--
-- Ported changes vs. original:
--   - ReapMeterDB → SP.GetDB().reapMeter (AceDB, shared profile)
--   - Standalone boot frame → SP:NewModule lifecycle
--   - All other logic is verbatim.
local SP = SuspicionsPack

local ReapPredict = SP:NewModule("ReapPredict", "AceEvent-3.0")
SP.ReapPredict = ReapPredict

-- ============================================================
-- DB accessor
-- ============================================================
local function GetDB()
    return SP.GetDB().reapMeter
end

-- ============================================================
-- Verbatim constants / locals from ReapPredict.lua
-- ============================================================
local issecretvalue = _G.issecretvalue or function() return false end

local CS_SPELLID       = 1227702
local VM_FORM_SPELLID  = 1217607
local VM_STACK_SPELLID = 1225789

local SF_SPELLID_SET = {}
do local ids = { 1245577, 1245584, 203981, 210788 }
   for _, id in ipairs(ids) do SF_SPELLID_SET[id] = true end end

local MOC_SPELLID_SET = {}
do local ids = { 1238495, 1238488 }
   for _, id in ipairs(ids) do MOC_SPELLID_SET[id] = true end end

local CS_THRESHOLD  = 30
local CS_AURA_MAX   = 40
local VM_THRESHOLD  = 50
local REAP_CAP_BASE = 4
local REAP_CAP_MOC  = 10

local CONTAINER_W   = 360
local CONTAINER_H   = 22
local PX_PER_STACK_VM
local PX_PER_STACK_BUILD

local DEFAULT_WIDTH    = 360
local DEFAULT_HEIGHT   = 22
local DEFAULT_FONT     = 13
local DEFAULT_LOCKED   = false

local FONTS = {
    { key = "ARIALN",   path = "Fonts\\ARIALN.TTF",   name = "Arial Narrow"  },
    { key = "FRIZQT",   path = "Fonts\\FRIZQT__.TTF", name = "Friz Quadrata" },
    { key = "MORPHEUS", path = "Fonts\\MORPHEUS.TTF", name = "Morpheus"      },
    { key = "SKURRI",   path = "Fonts\\SKURRI.TTF",   name = "Skurri"        },
}
local DEFAULT_FONT_KEY = "Arial Narrow"   -- LSM name; FONTS table kept for backward compat

local function FontPath(key)
    if not key then return FONTS[1].path end
    -- Try LSM first (covers any shared font name picked via SP GUI)
    local lsmPath = SP.GetFontPath and SP.GetFontPath(key)
    if lsmPath then return lsmPath end
    -- Fall back to legacy short-key table ("ARIALN", "FRIZQT", …)
    for _, f in ipairs(FONTS) do
        if f.key == key then return f.path end
    end
    return FONTS[1].path
end

local DDH_CLASS_ID   = 12
local DDH_SPEC_INDEX = 3

local BAR_TEXTURE       = "Interface\\BUTTONS\\WHITE8X8"
local NUMBER_FONT       = "Fonts\\ARIALN.TTF"
local NUMBER_FONT_SIZE  = 13

local COLOR_VERSION = 8

local DEFAULT_COLORS = {
    bg             = { 0.05, 0.04, 0.08, 0.90 },
    edge           = { 0.02, 0.02, 0.04, 1.00 },
    growthBuild    = { 0.30, 0.46, 0.88, 1.00 },
    beyondBuild    = { 0.05, 0.04, 0.08, 0.90 },
    growthVM       = { 0.18, 0.30, 0.62, 1.00 },
    beyondVM       = { 0.05, 0.04, 0.08, 0.90 },
    sfBase         = { 0.92, 0.62, 0.22, 1.00 },
    sfMoc          = { 1.00, 0.76, 0.32, 1.00 },
    mocRailFill    = { 1.00, 0.88, 0.55, 1.00 },
    mocRailTrack   = { 0.28, 0.16, 0.06, 0.80 },
    numberLabel    = { 0.98, 0.95, 0.88, 1.00 },
    sfNumberLabel  = { 1.00, 0.86, 0.52, 1.00 },
    thresholdBuild = { 0.96, 0.92, 0.78, 0.90 },
    thresholdVM    = { 0.96, 0.92, 0.78, 0.90 },
    furyTick       = { 0.96, 0.92, 0.78, 0.90 },
    furyFill       = { 0.32, 0.28, 0.62, 1.00 },
    furyFlat       = { 0.58, 0.50, 0.82, 1.00 },
    furySoul       = { 0.68, 0.62, 0.90, 1.00 },
    furyLabel      = { 0.98, 0.95, 0.88, 1.00 },
}

local function C(key)
    local db  = GetDB()
    local col = db and db.colors and db.colors[key] or DEFAULT_COLORS[key]
    return col[1], col[2], col[3], col[4] or 1
end

local function CopyColor(c)
    return { c[1], c[2], c[3], c[4] or 1 }
end

local MOC_PREVIEW_ALPHA  = 0.30
local FURY_PREVIEW_ALPHA_DEFAULT = 0.18

local CS_CAST_SPELL_SET = {
    [1221167] = true,
    [1221150] = true,
}
local csCastCount = 0

local MOC_DURATION_SEC = 8
local MOC_RAIL_HEIGHT  = 3

local CDM_VIEWERS = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffBarCooldownViewer",
    "BuffIconCooldownViewer",
}

local VOID_RAY_SPELLID  = 473728
local REAP_SPELLID      = 1226019
local ERADICATE_SPELLID = 1225826
local CULL_SPELLID      = 1245453
local CONSUME_SPELLID   = 473662

local SCYTHES_EMBRACE_SPELLID = 1246558
local REAP_CAST_FURY          = 10
local REAP_SOUL_FURY          = 4
local VOID_RAY_COST           = 100
local FURY_POWER_TYPE         = (Enum and Enum.PowerType and Enum.PowerType.Fury) or 17

local FURY_DEFAULT_WIDTH  = 360
local FURY_DEFAULT_HEIGHT = 14

local CONSUME_PAUSE_SEC = 0.25

local frame
local furyFrame
local debugOn = false

local function dbg(fmt, ...)
    if not debugOn then return end
    print(("|cff88ddff[RM]|r " .. fmt):format(...))
end

local function secretSafeStr(v)
    if issecretvalue(v) then return "SECRET" end
    if v == nil then return "nil" end
    return tostring(v)
end

local function classify(v)
    if issecretvalue(v) then return "secret" end
    if v == nil then return "nil" end
    return "plain"
end

local function fmtState(kind, plainVal)
    if kind == "plain" then return tostring(plainVal) end
    return kind == "secret" and "SECRET" or "nil"
end

-- ============================================================
-- Aura reads
-- ============================================================
local function ReadAuraApplications(spellID)
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok or not aura then return nil end
    return aura.applications
end

local function ReadCSApplications() return ReadAuraApplications(CS_SPELLID) end
local function ReadVMStacks()       return ReadAuraApplications(VM_STACK_SPELLID) end

local function IsInVMPhase()
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, VM_FORM_SPELLID)
    return ok and aura ~= nil
end

-- ============================================================
-- CDM piggyback
-- ============================================================
local function CDMInfoMatchesSet(info, spellIdSet)
    if not info then return false end
    if spellIdSet[info.spellID]
       or spellIdSet[info.overrideSpellID]
       or spellIdSet[info.overrideTooltipSpellID] then
        return true
    end
    if info.linkedSpellIDs then
        for _, id in ipairs(info.linkedSpellIDs) do
            if spellIdSet[id] then return true end
        end
    end
    return false
end

local function CDMFrameMatchesSpellSet(cdmFrame, spellIdSet)
    if not cdmFrame.GetCooldownID or not C_CooldownViewer then return false end
    local ok, cdID = pcall(cdmFrame.GetCooldownID, cdmFrame)
    if not ok or not cdID then return false end
    local ok2, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
    if not ok2 then return false end
    return CDMInfoMatchesSet(info, spellIdSet)
end

local function FindCDMFrameForSpellSet(cached, spellIdSet, label)
    if cached and CDMFrameMatchesSpellSet(cached, spellIdSet) then
        return cached
    end
    for _, viewerName in ipairs(CDM_VIEWERS) do
        local viewer = _G[viewerName]
        if viewer and viewer.itemFramePool then
            for itemFrame in viewer.itemFramePool:EnumerateActive() do
                if CDMFrameMatchesSpellSet(itemFrame, spellIdSet) then
                    dbg("acquired %s CDM frame in %s", label, viewerName)
                    return itemFrame
                end
            end
        end
    end
    return nil
end

local cdmSFFrame, cdmMoCFrame

local function FindSFCDMFrame()
    cdmSFFrame = FindCDMFrameForSpellSet(cdmSFFrame, SF_SPELLID_SET, "SF")
    return cdmSFFrame
end

local function FindMoCCDMFrame()
    cdmMoCFrame = FindCDMFrameForSpellSet(cdmMoCFrame, MOC_SPELLID_SET, "MoC")
    return cdmMoCFrame
end

local function ReadCDMAuraData(findFn)
    local cdm = findFn()
    if not cdm then return nil end
    local iid = cdm.auraInstanceID
    if issecretvalue(iid) or not iid then return nil end
    local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", iid)
    return ok and data or nil
end

local function ReadSFStackFromCDM()
    local data = ReadCDMAuraData(FindSFCDMFrame)
    return data and data.applications
end

local function ReadMoCActive()
    return ReadCDMAuraData(FindMoCCDMFrame) ~= nil
end

local SB_SMOOTH = (Enum and Enum.StatusBarInterpolation
                   and Enum.StatusBarInterpolation.ExponentialEaseOut) or 1

local function ApplyToBar(bar, value)
    if issecretvalue(value) then
        bar._lastNum = nil
        bar:SetValue(value, SB_SMOOTH)
        return
    end
    local v = (type(value) == "number") and value or 0
    if bar._lastNum == v then return end
    bar._lastNum = v
    bar:SetValue(v, SB_SMOOTH)
end

local function SetBarLabel(label, value)
    if issecretvalue(value) then
        label._lastNum = nil
        label:SetFormattedText("%d", value)
        return
    end
    if label._lastNum == value then return end
    label._lastNum = value
    if type(value) == "number" then
        label:SetFormattedText("%d", value)
    else
        label:SetText("")
    end
end

local lastMoCActive   = nil
local lastVMPhase     = nil
local lastFuryMax     = nil
local pauseUntil      = 0
local mocStartTime    = 0
local lastCSKind, lastCSPlain = "nil", nil
local lastSFKind, lastSFPlain = "nil", nil
local lastVMKind, lastVMPlain = "nil", nil

local function logIfChanged(label, lastKind, lastPlain, curr)
    local kind = classify(curr)
    local changed
    if kind ~= lastKind then
        changed = true
    elseif kind == "plain" then
        changed = (lastPlain ~= curr)
    else
        changed = false
    end
    if changed then
        dbg("%s: %s -> %s", label, fmtState(lastKind, lastPlain), fmtState(kind, curr))
    end
    return kind, (kind == "plain") and curr or nil
end

local currentPxPerStack
local lastGrowthPx    = 0   -- last known fill width in px; used by PositionSFBar
local FadeRefresh     -- forward-declared; defined in the Fading section below
local FadeDeactivate  -- forward-declared; defined in the Fading section below

local function SetCSCount(n)
    csCastCount = n
    if frame and frame.csCounterLabel then
        frame.csCounterLabel:SetFormattedText("x%d", n)
    end
end

local function LayoutFlag(key, default)
    local db = GetDB()
    local L  = db and db.layout
    if L == nil or L[key] == nil then return default end
    return L[key] ~= false
end
local function ShowMoCPreviewPref()      return LayoutFlag("showMocPreview",     true) end
local function ShowFuryBarPref()         return LayoutFlag("showFuryBar",        true) end
local function ShowFuryMocPreviewPref()  return LayoutFlag("showFuryMocPreview", false) end
local function ShowSoulBarPref()         return LayoutFlag("showSoulBar",        true) end

local function GetPlayerFuryMax()
    local max = UnitPowerMax("player", FURY_POWER_TYPE)
    if type(max) ~= "number" or issecretvalue(max) or max <= 0 then
        return 120
    end
    return max
end

local ApplyFurySoulCap
local ApplyFuryColors
local ApplyFuryLayout
local UpdateFuryVisibility
local RecomputeDerived
local RebuildCellSeparators
local EnsureCDMSyncHook
local SyncToCDMNow

local scythesEmbraceKnown = false
local function RefreshScythesEmbrace()
    scythesEmbraceKnown = false
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, SCYTHES_EMBRACE_SPELLID)
    if ok and not issecretvalue(aura) and aura ~= nil then
        scythesEmbraceKnown = true
        return
    end
    if IsPlayerSpell then
        local ok2, known = pcall(IsPlayerSpell, SCYTHES_EMBRACE_SPELLID)
        if ok2 and known then scythesEmbraceKnown = true; return end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok2, known = pcall(C_SpellBook.IsSpellKnown, SCYTHES_EMBRACE_SPELLID)
        if ok2 and known then scythesEmbraceKnown = true end
    end
end

-- Clamp sfBar so its right edge never exceeds the frame right.
-- Also clamp mocPreview width so it never overflows frame right either.
local function PositionSFBar()
    if not (frame and frame.sfBar) then return end
    if not currentPxPerStack or currentPxPerStack == 0 then return end
    local cap    = (lastMoCActive == true) and REAP_CAP_MOC or REAP_CAP_BASE
    local capPx  = cap * currentPxPerStack
    local sfLeft = math.max(0, math.min(lastGrowthPx, CONTAINER_W - capPx))
    frame.sfBar:ClearAllPoints()
    frame.sfBar:SetPoint("TOPLEFT", frame, "TOPLEFT", sfLeft, 0)

    -- mocPreview sits right of sfBar; clamp its width so it never exits the frame
    local preview = frame.mocPreview
    if preview then
        local fullPreviewPx = (REAP_CAP_MOC - REAP_CAP_BASE) * currentPxPerStack
        local available     = math.max(0, CONTAINER_W - (sfLeft + capPx))
        preview:SetSize(math.max(1, math.min(fullPreviewPx, available)), CONTAINER_H)
    end
end

local function ApplySFCap(mocActive)
    if not frame then return end
    local sfBar = frame.sfBar
    local cap = mocActive and REAP_CAP_MOC or REAP_CAP_BASE
    sfBar:SetSize(cap * currentPxPerStack, CONTAINER_H)
    sfBar:SetMinMaxValues(0, cap)
    sfBar:SetStatusBarColor(C(mocActive and "sfMoc" or "sfBase"))

    local preview = frame.mocPreview
    preview:SetSize((REAP_CAP_MOC - REAP_CAP_BASE) * currentPxPerStack, CONTAINER_H)
    preview:SetMinMaxValues(REAP_CAP_BASE, REAP_CAP_MOC)
    preview:SetShown(not mocActive and ShowMoCPreviewPref())

    frame.mocRail:SetShown(mocActive)
    PositionSFBar()   -- cap width changed, recompute clamped position
end

local function ApplyPhaseMode(inVM)
    if not frame then return end
    local growthBar     = frame.growthBar
    local beyondBg      = frame.beyondBg
    local thresholdLine = frame.thresholdLine

    local growthMax, growthKey, beyondKey, threshKey, growthW, thresholdX
    if inVM then
        currentPxPerStack = PX_PER_STACK_VM
        growthMax  = CS_AURA_MAX
        growthKey  = "growthVM"
        beyondKey  = "beyondVM"
        threshKey  = "thresholdVM"
        growthW    = CS_AURA_MAX  * currentPxPerStack
        thresholdX = CS_THRESHOLD * currentPxPerStack
    else
        currentPxPerStack = PX_PER_STACK_BUILD
        growthMax  = VM_THRESHOLD
        growthKey  = "growthBuild"
        beyondKey  = "beyondBuild"
        threshKey  = "thresholdBuild"
        growthW    = VM_THRESHOLD * currentPxPerStack
        thresholdX = growthW
    end

    growthBar:SetSize(growthW, CONTAINER_H)
    growthBar:SetMinMaxValues(0, growthMax)
    growthBar:SetStatusBarColor(C(growthKey))

    beyondBg:ClearAllPoints()
    beyondBg:SetPoint("TOPLEFT",     frame, "TOPLEFT",     thresholdX, 0)
    beyondBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    beyondBg:SetColorTexture(C(beyondKey))

    thresholdLine:SetShown(inVM)
    thresholdLine:ClearAllPoints()
    thresholdLine:SetPoint("TOP",    frame, "TOPLEFT",    thresholdX, 0)
    thresholdLine:SetPoint("BOTTOM", frame, "BOTTOMLEFT", thresholdX, 0)
    thresholdLine:SetColorTexture(C(threshKey))

    frame.mocRail:SetSize(REAP_CAP_MOC * currentPxPerStack, MOC_RAIL_HEIGHT)

    -- Reanchor labels: in build phase thresholdLine is at frame right edge,
    -- so sfLabel would overflow. Tuck both inside the frame instead.
    local gl = frame.growthLabel
    local sl = frame.sfLabel
    if inVM then
        -- Meta: labels flank the visible threshold line
        gl:ClearAllPoints()
        gl:SetPoint("RIGHT", thresholdLine, "LEFT", -4, 0)
        sl:ClearAllPoints()
        sl:SetJustifyH("LEFT")
        sl:SetPoint("LEFT", thresholdLine, "RIGHT", 4, 0)
    else
        -- Build: both inside, growthLabel a bit left of sfLabel
        gl:ClearAllPoints()
        gl:SetPoint("RIGHT", frame, "RIGHT", -22, 0)
        sl:ClearAllPoints()
        sl:SetJustifyH("RIGHT")
        sl:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    end

    ApplySFCap(lastMoCActive == true)   -- also calls PositionSFBar internally
    RebuildCellSeparators()
end

-- Draw 1-px separator lines at every Reap-stack boundary across the full bar.
-- Mirrors the Ayije CDM soul-bar cell style. Called on phase change and resize.
RebuildCellSeparators = function()
    if not frame or not frame.overlay then return end
    local db  = GetDB()
    local L   = db and db.layout
    frame.cellSeparators = frame.cellSeparators or {}
    local seps = frame.cellSeparators

    if not (L and L.cellMode) then
        for _, s in ipairs(seps) do s:Hide() end
        return
    end

    local inVM    = lastVMPhase == true
    local pxPer   = inVM and PX_PER_STACK_VM or PX_PER_STACK_BUILD
    local nStacks = inVM and CS_AURA_MAX or VM_THRESHOLD   -- SF overlay not part of growth axis
    -- One separator between every pair of adjacent stacks
    local nSeps = nStacks - 1

    for i = 1, nSeps do
        local s = seps[i]
        if not s then
            s = frame.overlay:CreateTexture(nil, "OVERLAY", nil, 7)
            seps[i] = s
        end
        s:SetSize(1, CONTAINER_H)
        s:SetColorTexture(C("edge"))
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", frame, "TOPLEFT", i * pxPer, 0)
        s:Show()
    end
    -- Hide leftover separators from a previous (wider) phase
    for i = nSeps + 1, #seps do seps[i]:Hide() end
end

local function UpdateFuryBar(sfStacks)
    if not furyFrame or not furyFrame:IsShown() then return end
    local furyMax = GetPlayerFuryMax()
    if furyMax ~= lastFuryMax then
        lastFuryMax = furyMax
        ApplyFuryLayout()
    end
    local fury = UnitPower("player", FURY_POWER_TYPE)
    ApplyToBar(furyFrame.furyFillBar,     fury)
    ApplyToBar(furyFrame.flatBar,         scythesEmbraceKnown and REAP_CAST_FURY or 0)
    ApplyToBar(furyFrame.soulFuryBar,     sfStacks)
    ApplyToBar(furyFrame.soulFuryPreview, sfStacks)
    SetBarLabel(furyFrame.furyLabel,      fury)
end

local function UpdateMeter()
    if not frame then return end

    local mocActive = ReadMoCActive()
    if mocActive ~= lastMoCActive then
        if mocActive then mocStartTime = GetTime() end
        ApplySFCap(mocActive)
        ApplyFurySoulCap(mocActive)
        if lastMoCActive ~= nil then
            dbg("MoC %s -> %s (Reap cap now %d)",
                tostring(lastMoCActive), tostring(mocActive),
                mocActive and REAP_CAP_MOC or REAP_CAP_BASE)
        end
        lastMoCActive = mocActive
    end

    if mocActive then
        local remaining = MOC_DURATION_SEC - (GetTime() - mocStartTime)
        if remaining < 0 then remaining = 0 end
        frame.mocRail:SetValue(remaining)
    end

    local inVM = IsInVMPhase()
    if inVM ~= lastVMPhase then
        ApplyPhaseMode(inVM)
        if lastVMPhase == true and inVM == false then
            SetCSCount(0)
        end
        if lastVMPhase ~= nil then
            dbg("phase %s -> %s",
                lastVMPhase and "VM" or "build",
                inVM and "VM" or "build")
        end
        lastVMPhase = inVM
        UpdateFuryVisibility()
    end

    local csApps   = ReadCSApplications()
    local vmStacks = ReadVMStacks()
    local sfStacks = ReadSFStackFromCDM()

    lastCSKind, lastCSPlain = logIfChanged("CS apps",   lastCSKind, lastCSPlain, csApps)
    lastSFKind, lastSFPlain = logIfChanged("SF stacks", lastSFKind, lastSFPlain, sfStacks)
    lastVMKind, lastVMPlain = logIfChanged("VM stacks", lastVMKind, lastVMPlain, vmStacks)

    if GetTime() < pauseUntil then return end

    local growthValue
    if inVM and (issecretvalue(csApps) or csApps) then
        growthValue = csApps
    else
        growthValue = vmStacks
    end
    -- Track fill position for clamped sfBar placement
    if type(growthValue) == "number" and not issecretvalue(growthValue) then
        lastGrowthPx = growthValue * currentPxPerStack
    end
    ApplyToBar(frame.growthBar, growthValue)
    PositionSFBar()
    ApplyToBar(frame.sfBar, sfStacks)
    ApplyToBar(frame.mocPreview, sfStacks)
    SetBarLabel(frame.growthLabel, growthValue)
    SetBarLabel(frame.sfLabel, sfStacks)
    UpdateFuryBar(sfStacks)
end

-- ============================================================
-- Spec check
-- ============================================================
local isDDH = false
local function RefreshSpecCache()
    local _, _, classID = UnitClass("player")
    if classID ~= DDH_CLASS_ID then isDDH = false; return end
    local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
    isDDH = specIndex == DDH_SPEC_INDEX
end

local function IsDDH() return isDDH end

-- ============================================================
-- Frame position
-- ============================================================
local function ApplySavedPosition()
    if not frame then return end
    frame:ClearAllPoints()
    local db  = GetDB()
    local L   = db and db.layout
    -- When synced to CDM, anchor directly to the CDM Essential container so
    -- the bar follows the CDM when it moves or resizes.
    if L and L.syncToCDM then
        local CDM = _G["Ayije_CDM"]
        local container = CDM and CDM.anchorContainers
            and CDM.anchorContainers["EssentialCooldownViewer"]
        if container then
            frame:SetPoint("TOPLEFT", container, "BOTTOMLEFT",
                L.cdmOffsetX or 0, L.cdmOffsetY or -4)
            return
        end
    end
    local pos = db and db.framePos
    if type(pos) == "table" and pos.x and pos.y then
        local point    = pos.point or "CENTER"
        local relPoint = pos.relativePoint or "CENTER"
        frame:SetPoint(point, UIParent, relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
end

local function SaveCurrentPosition()
    local db = GetDB()
    if not frame or type(db) ~= "table" then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    db.framePos = {
        point         = point,
        relativePoint = relPoint,
        x             = x,
        y             = y,
    }
end

local EDGE_SIDES = {
    top    = { "TOPLEFT",    "TOPRIGHT",    nil, 1   },
    bottom = { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1   },
    left   = { "TOPLEFT",    "BOTTOMLEFT",  1,   nil },
    right  = { "TOPRIGHT",   "BOTTOMRIGHT", 1,   nil },
}

local function BuildEdges(overlay, sides)
    local out = {}
    for _, name in ipairs(sides) do
        local spec = EDGE_SIDES[name]
        local t = overlay:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetPoint(spec[1]); t:SetPoint(spec[2])
        if spec[3] then t:SetWidth(spec[3])  end
        if spec[4] then t:SetHeight(spec[4]) end
        t:SetColorTexture(C("edge"))
        out[#out + 1] = t
    end
    return out
end

local function MakeLabel(parent, colorKey, justify, fontSize)
    local s = parent:CreateFontString(nil, "OVERLAY")
    s:SetFont(NUMBER_FONT, fontSize or NUMBER_FONT_SIZE, "OUTLINE")
    s:SetJustifyH(justify)
    s:SetTextColor(C(colorKey))
    s:SetShadowOffset(0, 0)
    s._colorKey = colorKey
    return s
end

local function WireDragHandlers(f, saveFn)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if self:IsMovable() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveFn(self)
    end)
end

local function ApplyFrameLock(f, lockedKey)
    if not f then return end
    local db     = GetDB()
    local L      = db and db.layout
    local locked = L and L[lockedKey]
    f:SetMovable(not locked)
    -- Locked = no drag needed → disable mouse so right-click reaches the world.
    -- Unlocked = drag mode → mouse must be active.
    f:EnableMouse(not locked)
end
local function ApplyLock()     ApplyFrameLock(frame,     "locked")     end
local function ApplyFuryLock() ApplyFrameLock(furyFrame, "furyLocked") end

-- ============================================================
-- Create soul bar
-- ============================================================
local function CreateMeter()
    if frame then return frame end

    frame = CreateFrame("Frame", "SP_ReapPredictFrame", UIParent)
    frame:SetSize(CONTAINER_W, CONTAINER_H)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    WireDragHandlers(frame, SaveCurrentPosition)

    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    bg:SetAllPoints()
    bg:SetColorTexture(C("bg"))

    local initialGrowthW = VM_THRESHOLD * PX_PER_STACK_BUILD

    local beyondBg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    beyondBg:SetPoint("TOPLEFT", frame, "TOPLEFT", initialGrowthW, 0)
    beyondBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    beyondBg:SetColorTexture(C("beyondBuild"))

    local growthBar = CreateFrame("StatusBar", nil, frame)
    growthBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    growthBar:SetSize(initialGrowthW, CONTAINER_H)
    growthBar:SetStatusBarTexture(BAR_TEXTURE)
    growthBar:SetStatusBarColor(C("growthBuild"))
    growthBar:SetMinMaxValues(0, VM_THRESHOLD)
    growthBar:SetValue(0)

    -- CDM soul bar (pip bar) sits at level ~3 (UIParent→resourceContainer(2)→bar(3)).
    -- Its separatorOverlay (cell lines) is at bar:GetFrameLevel()+5 = ~8.
    -- sfBar/mocPreview at level 5: above CDM fill (3), below CDM cells (8).
    -- overlay at level 9: above CDM cells (8) so our labels remain readable.
    local SF_LEVEL      = 5   -- above CDM soul bar fill, below CDM cell separators
    local OVERLAY_LEVEL = 9   -- above CDM cell separators

    local sfBar = CreateFrame("StatusBar", nil, frame)
    sfBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)   -- initial; PositionSFBar() repositions each tick
    sfBar:SetSize(REAP_CAP_BASE * PX_PER_STACK_BUILD, CONTAINER_H)
    sfBar:SetStatusBarTexture(BAR_TEXTURE)
    sfBar:SetStatusBarColor(C("sfBase"))
    sfBar:SetMinMaxValues(0, REAP_CAP_BASE)
    sfBar:SetValue(0)
    sfBar:SetFrameLevel(SF_LEVEL)

    local mocPreview = CreateFrame("StatusBar", nil, frame)
    mocPreview:SetPoint("TOPLEFT", sfBar, "TOPRIGHT", 0, 0)   -- immediately right of sfBar zone
    mocPreview:SetSize((REAP_CAP_MOC - REAP_CAP_BASE) * PX_PER_STACK_BUILD, CONTAINER_H)
    mocPreview:SetStatusBarTexture(BAR_TEXTURE)
    mocPreview:SetStatusBarColor(C("sfBase"))
    mocPreview:SetMinMaxValues(REAP_CAP_BASE, REAP_CAP_MOC)
    mocPreview:SetValue(REAP_CAP_BASE)
    mocPreview:SetAlpha(MOC_PREVIEW_ALPHA)
    mocPreview:SetFrameLevel(SF_LEVEL)

    local mocRail = CreateFrame("StatusBar", nil, frame)
    mocRail:SetPoint("BOTTOMLEFT", sfBar, "BOTTOMLEFT", 0, 1)
    mocRail:SetSize(REAP_CAP_MOC * PX_PER_STACK_BUILD, MOC_RAIL_HEIGHT)
    mocRail:SetStatusBarTexture(BAR_TEXTURE)
    mocRail:SetStatusBarColor(C("mocRailFill"))
    mocRail:SetMinMaxValues(0, MOC_DURATION_SEC)
    mocRail:SetValue(0)
    mocRail:SetFrameLevel(SF_LEVEL + 2)   -- = 7, below CDM cells (8)
    mocRail:Hide()

    local railTrack = mocRail:CreateTexture(nil, "BACKGROUND")
    railTrack:SetAllPoints()
    railTrack:SetColorTexture(C("mocRailTrack"))

    local overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(OVERLAY_LEVEL)   -- = 9, above CDM cells (8)

    local edgeTextures = BuildEdges(overlay, { "top", "bottom", "left", "right" })

    local thresholdLine = overlay:CreateTexture(nil, "OVERLAY", nil, 5)
    thresholdLine:SetPoint("TOP",    frame, "TOPLEFT",    initialGrowthW, 0)
    thresholdLine:SetPoint("BOTTOM", frame, "BOTTOMLEFT", initialGrowthW, 0)
    thresholdLine:SetWidth(2)
    thresholdLine:SetColorTexture(C("thresholdBuild"))

    local growthLabel = MakeLabel(overlay, "numberLabel", "RIGHT")
    growthLabel:SetPoint("RIGHT", thresholdLine, "LEFT", -4, 0)

    local sfLabel = MakeLabel(overlay, "sfNumberLabel", "LEFT")
    sfLabel:SetPoint("LEFT", thresholdLine, "RIGHT", 4, 0)

    local csCounterLabel = MakeLabel(overlay, "numberLabel", "LEFT")
    csCounterLabel:SetPoint("LEFT", frame, "RIGHT", 4, 0)
    csCounterLabel:SetFormattedText("x%d", csCastCount)
    local db = GetDB()
    local showCS = not (db and db.layout and db.layout.showCsCounter == false)
    csCounterLabel:SetShown(showCS)

    frame.bgTexture      = bg
    frame.beyondBg       = beyondBg
    frame.growthBar      = growthBar
    frame.sfBar          = sfBar
    frame.mocPreview     = mocPreview
    frame.mocRail        = mocRail
    frame.mocRailTrack   = railTrack
    frame.edgeTextures   = edgeTextures
    frame.thresholdLine  = thresholdLine
    frame.growthLabel    = growthLabel
    frame.sfLabel        = sfLabel
    frame.csCounterLabel = csCounterLabel
    frame.numberLabels   = { growthLabel, sfLabel, csCounterLabel }
    frame.overlay        = overlay        -- needed by RebuildCellSeparators
    frame.cellSeparators = {}

    ApplySavedPosition()
    return frame
end

-- ============================================================
-- Fury bar
-- ============================================================
local function ApplyFuryPosition()
    if not furyFrame then return end
    furyFrame:ClearAllPoints()
    local db  = GetDB()
    local L   = db and db.layout
    local ox  = (L and L.furyOffsetX) or 0
    local oy  = (L and L.furyOffsetY) or 0
    -- When synced to CDM, stack the fury bar directly below the soul bar.
    -- The soul bar is already anchored to the CDM container, so both bars
    -- follow CDM movement automatically via WoW's native anchor chain.
    if L and L.syncToCDM and frame then
        furyFrame:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", ox, -4 + oy)
        return
    end
    local pos = db and db.furyPos
    if type(pos) == "table" and pos.x and pos.y then
        local point    = pos.point or "CENTER"
        local relPoint = pos.relativePoint or "CENTER"
        furyFrame:SetPoint(point, UIParent, relPoint, pos.x + ox, pos.y + oy)
    elseif frame then
        furyFrame:SetPoint("TOP", frame, "BOTTOM", ox, -4 + oy)
    else
        furyFrame:SetPoint("CENTER", UIParent, "CENTER", ox, 170 + oy)
    end
end

local function SaveFuryPosition()
    local db = GetDB()
    if not furyFrame or type(db) ~= "table" then return end
    local point, _, relPoint, x, y = furyFrame:GetPoint(1)
    db.furyPos = {
        point         = point,
        relativePoint = relPoint,
        x             = x,
        y             = y,
    }
end

local function ApplyMoCRailPosition()
    if not (frame and frame.mocRail and frame.sfBar) then return end
    local db = GetDB(); local L = db and db.layout
    local ox = (L and L.mocRailOffsetX) or 0
    local oy = (L and L.mocRailOffsetY) or 0
    frame.mocRail:ClearAllPoints()
    frame.mocRail:SetPoint("BOTTOMLEFT", frame.sfBar, "BOTTOMLEFT", ox, 1 + oy)
end

local function CreateFuryBar()
    if furyFrame then return furyFrame end
    local db = GetDB()
    local L  = (db and db.layout) or {}
    local W  = L.furyWidth  or FURY_DEFAULT_WIDTH
    local H  = L.furyHeight or FURY_DEFAULT_HEIGHT

    furyFrame = CreateFrame("Frame", "SP_ReapPredictFuryFrame", UIParent)
    furyFrame:SetSize(W, H)
    -- Sit just above Ayije CDM's resource bar but below its value text.
    -- CDM resource container is MEDIUM/level ~10; CDM text overlay is bar+4 (~14).
    -- We target level 12 (above bar, below text). Query CDM container if available.
    furyFrame:SetFrameStrata("MEDIUM")
    local _cdmBase = _G["Ayije_CDM_ResourcesContainer"]
    furyFrame:SetFrameLevel(_cdmBase and (_cdmBase:GetFrameLevel() + 2) or 12)
    furyFrame:SetClampedToScreen(true)
    if furyFrame.SetClipsChildren then furyFrame:SetClipsChildren(true) end
    WireDragHandlers(furyFrame, SaveFuryPosition)

    local bg = furyFrame:CreateTexture(nil, "BACKGROUND", nil, -2)
    bg:SetAllPoints()
    bg:SetColorTexture(C("bg"))

    local pxPerFury = W / (GetPlayerFuryMax() + REAP_CAST_FURY
                           + REAP_CAP_MOC * REAP_SOUL_FURY)

    local furyFillBar = CreateFrame("StatusBar", nil, furyFrame)
    furyFillBar:SetFrameStrata("MEDIUM")
    furyFillBar:SetPoint("TOPLEFT", furyFrame, "TOPLEFT", 0, 0)
    furyFillBar:SetSize(VOID_RAY_COST * pxPerFury, H)
    furyFillBar:SetStatusBarTexture(BAR_TEXTURE)
    furyFillBar:SetStatusBarColor(C("furyFill"))
    furyFillBar:SetMinMaxValues(0, VOID_RAY_COST)
    furyFillBar:SetValue(0)

    local flatBar = CreateFrame("StatusBar", nil, furyFrame)
    flatBar:SetFrameStrata("MEDIUM")
    flatBar:SetPoint("LEFT", furyFillBar:GetStatusBarTexture(), "RIGHT", 0, 0)
    flatBar:SetSize(REAP_CAST_FURY * pxPerFury, H)
    flatBar:SetStatusBarTexture(BAR_TEXTURE)
    flatBar:SetStatusBarColor(C("furyFlat"))
    flatBar:SetMinMaxValues(0, REAP_CAST_FURY)
    flatBar:SetValue(0)

    local soulFuryBar = CreateFrame("StatusBar", nil, furyFrame)
    soulFuryBar:SetFrameStrata("MEDIUM")
    soulFuryBar:SetPoint("LEFT", flatBar:GetStatusBarTexture(), "RIGHT", 0, 0)
    soulFuryBar:SetSize(REAP_CAP_BASE * REAP_SOUL_FURY * pxPerFury, H)
    soulFuryBar:SetStatusBarTexture(BAR_TEXTURE)
    soulFuryBar:SetStatusBarColor(C("furySoul"))
    soulFuryBar:SetMinMaxValues(0, REAP_CAP_BASE)
    soulFuryBar:SetValue(0)

    local soulFuryPreview = CreateFrame("StatusBar", nil, furyFrame)
    soulFuryPreview:SetFrameStrata("MEDIUM")
    soulFuryPreview:SetPoint("LEFT", soulFuryBar, "RIGHT", 0, 0)
    soulFuryPreview:SetSize((REAP_CAP_MOC - REAP_CAP_BASE) * REAP_SOUL_FURY * pxPerFury, H)
    soulFuryPreview:SetStatusBarTexture(BAR_TEXTURE)
    do  -- apply preview alpha immediately so it's correct if the option is already on at load
        local _db = GetDB(); local _L = _db and _db.layout
        local _r, _g, _b = C("furySoul")
        local _a = (_L and _L.furyPreviewAlpha) or FURY_PREVIEW_ALPHA_DEFAULT
        soulFuryPreview:SetStatusBarColor(_r, _g, _b, _a)
    end
    soulFuryPreview:SetMinMaxValues(REAP_CAP_BASE, REAP_CAP_MOC)
    soulFuryPreview:SetValue(REAP_CAP_BASE)

    local overlay = CreateFrame("Frame", nil, furyFrame)
    overlay:SetFrameStrata("MEDIUM")
    overlay:SetAllPoints()
    overlay:SetFrameLevel(soulFuryBar:GetFrameLevel() + 1)

    local edgeTextures = BuildEdges(overlay, { "top", "bottom", "left" })

    local tickX = VOID_RAY_COST * pxPerFury
    local tick = overlay:CreateTexture(nil, "OVERLAY", nil, 5)
    tick:SetPoint("TOP",    furyFrame, "TOPLEFT",    tickX, 0)
    tick:SetPoint("BOTTOM", furyFrame, "BOTTOMLEFT", tickX, 0)
    tick:SetWidth(2)
    tick:SetColorTexture(C("furyTick"))

    local furyLabel = MakeLabel(overlay, "furyLabel", "CENTER", L.furyFont or DEFAULT_FONT)
    furyLabel:SetPoint("CENTER", furyFrame, "CENTER", 0, 0)

    furyFrame.bgTexture       = bg
    furyFrame.furyFillBar     = furyFillBar
    furyFrame.flatBar         = flatBar
    furyFrame.soulFuryBar     = soulFuryBar
    furyFrame.soulFuryPreview = soulFuryPreview
    furyFrame.edgeTextures    = edgeTextures
    furyFrame.tick            = tick
    furyFrame.furyLabel       = furyLabel

    ApplyFuryPosition()
    ApplyFuryLayout()
    return furyFrame
end

function ApplyFuryLayout()
    if not furyFrame then return end
    local db = GetDB()
    local L  = (db and db.layout) or {}
    local W    = L.furyWidth  or FURY_DEFAULT_WIDTH
    local H    = L.furyHeight or FURY_DEFAULT_HEIGHT
    local font = L.furyFont   or DEFAULT_FONT

    furyFrame:SetSize(W, H)

    local furyMax = GetPlayerFuryMax()
    if not furyMax or furyMax == 0 then return end
    local pxPerFury = W / furyMax
    furyFrame._pxPerFury = pxPerFury
    furyFrame._height    = H

    local fillBar = furyFrame.furyFillBar
    fillBar:SetSize(W, H)
    fillBar:SetMinMaxValues(0, furyMax)

    furyFrame.flatBar:SetSize(REAP_CAST_FURY * pxPerFury, H)
    furyFrame.soulFuryPreview:SetSize((REAP_CAP_MOC - REAP_CAP_BASE) * REAP_SOUL_FURY * pxPerFury, H)
    furyFrame.soulFuryPreview:SetMinMaxValues(REAP_CAP_BASE, REAP_CAP_MOC)

    local tickX = VOID_RAY_COST * pxPerFury
    furyFrame.tick:ClearAllPoints()
    furyFrame.tick:SetPoint("TOP",    furyFrame, "TOPLEFT",    tickX, 0)
    furyFrame.tick:SetPoint("BOTTOM", furyFrame, "BOTTOMLEFT", tickX, 0)

    furyFrame.furyLabel:SetFont(NUMBER_FONT, font, "OUTLINE")

    ApplyFurySoulCap(lastMoCActive == true)
end

function ApplyFurySoulCap(mocActive)
    if not furyFrame or not furyFrame._pxPerFury then return end
    local cap = mocActive and REAP_CAP_MOC or REAP_CAP_BASE
    local active = furyFrame.soulFuryBar
    active:SetSize(cap * REAP_SOUL_FURY * furyFrame._pxPerFury, furyFrame._height)
    active:SetMinMaxValues(0, cap)

    furyFrame.soulFuryPreview:SetShown(
        not mocActive and ShowFuryMocPreviewPref() and lastVMPhase ~= true
    )
end

local function ApplyFurySize()
    ApplyFuryLayout()
    ApplyFuryLock()
end

function ApplyFuryColors()
    if not furyFrame then return end
    furyFrame.bgTexture:SetColorTexture(C("bg"))
    for _, t in ipairs(furyFrame.edgeTextures) do
        t:SetColorTexture(C("edge"))
    end
    furyFrame.furyFillBar:SetStatusBarColor(C("furyFill"))
    furyFrame.flatBar:SetStatusBarColor(C("furyFlat"))
    furyFrame.soulFuryBar:SetStatusBarColor(C("furySoul"))
    do
        local r, g, b = C("furySoul")
        local db = GetDB(); local L = db and db.layout
        local a = (L and L.furyPreviewAlpha) or FURY_PREVIEW_ALPHA_DEFAULT
        furyFrame.soulFuryPreview:SetStatusBarColor(r, g, b, a)
    end
    furyFrame.tick:SetColorTexture(C("furyTick"))
    furyFrame.furyLabel:SetTextColor(C("furyLabel"))
end

-- ============================================================
-- Sizing
-- ============================================================
function RecomputeDerived()
    -- Bar width = exact growth cap (50 build / 40 meta).
    -- SF prediction zone overlays the right end of the bar, so no extra units.
    PX_PER_STACK_VM     = CONTAINER_W / CS_AURA_MAX
    PX_PER_STACK_BUILD  = CONTAINER_W / VM_THRESHOLD
    MOC_RAIL_HEIGHT     = math.max(2, math.floor(CONTAINER_H / 6))
    if currentPxPerStack == nil then currentPxPerStack = PX_PER_STACK_BUILD end
end

local function LoadSizesFromDB()
    local db = GetDB()
    if type(db) ~= "table" then return end
    db.layout = db.layout or {}
    local L = db.layout
    if type(L.width)          ~= "number"  then L.width          = DEFAULT_WIDTH    end
    if type(L.height)         ~= "number"  then L.height         = DEFAULT_HEIGHT   end
    if type(L.font)           ~= "number"  then L.font           = DEFAULT_FONT     end
    if type(L.locked)         ~= "boolean" then L.locked         = DEFAULT_LOCKED   end
    if type(L.fontKey)        ~= "string"  then L.fontKey        = DEFAULT_FONT_KEY end
    if type(L.showSoulBar)    ~= "boolean" then L.showSoulBar    = true             end
    if type(L.showMocPreview) ~= "boolean" then L.showMocPreview = true             end
    if type(L.showCsCounter)  ~= "boolean" then L.showCsCounter  = true             end
    if type(L.showFuryBar)    ~= "boolean" then L.showFuryBar    = true             end
    if type(L.showFuryMocPreview) ~= "boolean" then L.showFuryMocPreview = false    end
    if type(L.furyWidth)      ~= "number"  then L.furyWidth      = FURY_DEFAULT_WIDTH  end
    if type(L.furyHeight)     ~= "number"  then L.furyHeight     = FURY_DEFAULT_HEIGHT end
    if type(L.furyFont)       ~= "number"  then L.furyFont       = DEFAULT_FONT     end
    if type(L.furyLocked)     ~= "boolean" then L.furyLocked     = false            end
    if type(L.furyOffsetX)      ~= "number"  then L.furyOffsetX      = 0                          end
    if type(L.furyOffsetY)      ~= "number"  then L.furyOffsetY      = 0                          end
    if type(L.furyPreviewAlpha) ~= "number"  then L.furyPreviewAlpha = FURY_PREVIEW_ALPHA_DEFAULT  end
    if type(L.mocRailOffsetX)   ~= "number"  then L.mocRailOffsetX   = 0                          end
    if type(L.mocRailOffsetY)   ~= "number"  then L.mocRailOffsetY   = 0                          end
    if type(L.syncToCDM)     ~= "boolean" then L.syncToCDM     = false            end
    if type(L.cdmOffsetX)   ~= "number"  then L.cdmOffsetX   = 0                 end
    if type(L.cdmOffsetY)   ~= "number"  then L.cdmOffsetY   = -4                end
    if type(L.cellMode)              ~= "boolean" then L.cellMode              = false end
    if type(L.fadingEnabled)         ~= "boolean" then L.fadingEnabled         = false end
    if type(L.fadingOpacity)         ~= "number"  then L.fadingOpacity         = 0     end
    if type(L.fadingTriggerNoTarget) ~= "boolean" then L.fadingTriggerNoTarget = true  end
    if type(L.fadingTriggerOOC)      ~= "boolean" then L.fadingTriggerOOC      = false end
    if type(L.fadingTriggerMounted)  ~= "boolean" then L.fadingTriggerMounted  = false end
    L.showVoidRayTick = nil
    if type(db.debug) ~= "boolean" then db.debug = false end

    if (db.colorVersion or 0) < COLOR_VERSION then
        db.colors = {}
        db.colorVersion = COLOR_VERSION
    end
    db.colors = db.colors or {}
    for key, def in pairs(DEFAULT_COLORS) do
        if type(db.colors[key]) ~= "table" then
            db.colors[key] = CopyColor(def)
        end
    end

    CONTAINER_W      = L.width
    CONTAINER_H      = L.height
    NUMBER_FONT_SIZE = L.font
    NUMBER_FONT      = FontPath(L.fontKey)
    debugOn          = db.debug
    RecomputeDerived()

end

local function ApplySize()
    RecomputeDerived()
    if not frame then return end
    frame:SetSize(CONTAINER_W, CONTAINER_H)
    for _, label in ipairs(frame.numberLabels) do
        label:SetFont(NUMBER_FONT, NUMBER_FONT_SIZE, "OUTLINE")
    end
    if lastVMPhase   ~= nil then ApplyPhaseMode(lastVMPhase == true) end
    if lastMoCActive ~= nil then ApplySFCap(lastMoCActive == true) end
    PositionSFBar()
    RebuildCellSeparators()
    ApplyLock()
end

local activeColorSwatches = {}

local function ApplyColors()
    if not frame then return end
    frame.bgTexture:SetColorTexture(C("bg"))
    for _, t in ipairs(frame.edgeTextures) do
        t:SetColorTexture(C("edge"))
    end
    frame.mocRail:SetStatusBarColor(C("mocRailFill"))
    frame.mocRailTrack:SetColorTexture(C("mocRailTrack"))
    frame.mocPreview:SetStatusBarColor(C("sfBase"))
    for _, lbl in ipairs(frame.numberLabels) do
        lbl:SetTextColor(C(lbl._colorKey))
    end

    local inVM = lastVMPhase == true
    frame.growthBar:SetStatusBarColor(C(inVM and "growthVM" or "growthBuild"))
    frame.beyondBg:SetColorTexture(C(inVM and "beyondVM" or "beyondBuild"))
    frame.thresholdLine:SetColorTexture(C(inVM and "thresholdVM" or "thresholdBuild"))

    local moc = lastMoCActive == true
    frame.sfBar:SetStatusBarColor(C(moc and "sfMoc" or "sfBase"))

    ApplyFuryColors()

    for sw, key in pairs(activeColorSwatches) do
        sw:SetColorTexture(C(key))
    end
    -- Refresh cell separator colors (use edge color)
    if frame and frame.cellSeparators then
        for _, s in ipairs(frame.cellSeparators) do
            if s:IsShown() then s:SetColorTexture(C("edge")) end
        end
    end
end

function UpdateFuryVisibility()
    if not furyFrame then return end
    furyFrame:SetShown(ShowFuryBarPref())
    local hideProjection = lastVMPhase == true
    furyFrame.flatBar:SetShown(not hideProjection)
    furyFrame.soulFuryBar:SetShown(not hideProjection)
    furyFrame.tick:SetShown(not hideProjection)
    ApplyFurySoulCap(lastMoCActive == true)
end

local function UpdateSoulBarVisibility()
    if not frame then return end
    frame:SetShown(ShowSoulBarPref())
end

-- ============================================================
-- Poll frame (raw — OnUpdate only works when frame is shown)
-- ============================================================
local pollFrame
local function EnsurePollFrame()
    if pollFrame then return end
    pollFrame = CreateFrame("Frame")
    local accum = 0
    pollFrame:SetScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if accum < 0.1 then return end
        accum = 0
        UpdateMeter()
    end)
end

local function Enable()
    if not frame then CreateMeter() end
    frame:SetShown(ShowSoulBarPref())
    ApplyLock()

    if not furyFrame then CreateFuryBar() end
    -- Raise soul-bar overlay above the fury bar so growthLabel/sfLabel
    -- remain readable when the two bars overlap in MEDIUM strata.
    if frame and frame.overlay then
        frame.overlay:SetFrameLevel(furyFrame:GetFrameLevel() + 1)
    end
    UpdateFuryVisibility()
    ApplyFuryLock()

    EnsurePollFrame()
    pollFrame:Show()
    UpdateMeter()

    -- CDM width sync: install hook and snap immediately if enabled
    EnsureCDMSyncHook()
    local _syncDB = GetDB(); local _syncL = _syncDB and _syncDB.layout
    if _syncL and _syncL.syncToCDM then SyncToCDMNow() end

    -- Fading: activate or deactivate based on current DB setting
    if FadeRefresh then FadeRefresh() end
end

local function Disable()
    if FadeDeactivate then FadeDeactivate() end   -- restore alpha before hiding
    if pollFrame      then pollFrame:Hide()      end
    if frame          then frame:Hide()          end
    if furyFrame then furyFrame:Hide() end
end

local function Refresh()
    local db = GetDB()
    if not (db and db.enabled) then Disable(); return end
    RefreshSpecCache()
    RefreshScythesEmbrace()
    if IsDDH() then Enable() else Disable() end
end

-- ============================================================
-- CDM width sync  (optional: "Sync width to CDM" toggle)
-- ============================================================
-- Hook CDM's EssentialCooldownViewer container OnSizeChanged.
-- We install the hook once; the callback is a no-op when syncToCDM is off.
local cdmSyncHooked = false

EnsureCDMSyncHook = function()
    if cdmSyncHooked then return end
    local CDM = _G["Ayije_CDM"]
    if not CDM then return end
    local container = CDM.anchorContainers
        and CDM.anchorContainers["EssentialCooldownViewer"]
    if not container then return end

    container:HookScript("OnSizeChanged", function(self)
        local db = GetDB()
        local L  = db and db.layout
        if not (L and L.syncToCDM) then return end
        local w = math.floor(self:GetWidth() + 0.5)
        if w <= 0 then return end
        -- Propagate to module-locals + DB so sliders stay consistent
        CONTAINER_W = w
        L.width     = w
        L.furyWidth = w
        ApplySize()
        ApplyFuryLayout()
    end)
    cdmSyncHooked = true
end

-- Called immediately when the toggle is enabled, or at boot if it was already on.
SyncToCDMNow = function()
    local CDM = _G["Ayije_CDM"]
    if not CDM then return end
    local container = CDM.anchorContainers
        and CDM.anchorContainers["EssentialCooldownViewer"]
    if not container then return end
    EnsureCDMSyncHook()
    local w = math.floor(container:GetWidth() + 0.5)
    if w <= 0 then return end
    local db = GetDB()
    local L  = db and db.layout
    if not L then return end
    CONTAINER_W = w
    L.width     = w
    L.furyWidth = w
    ApplySize()
    ApplyFuryLayout()
    ApplySavedPosition()
    ApplyFuryPosition()
end

-- ============================================================
-- Fading system  (mirrors Ayije CDM Fading.lua)
-- Triggers: no target / out of combat / mounted.
-- 0.3 s linear alpha animation on both frame and furyFrame.
-- ============================================================
local FADE_DURATION    = 0.3
local DRUID_TRAVEL_IDS = { [3]=true, [4]=true, [27]=true, [29]=true }

local fadeAlpha     = 1.0
local fadeTarget    = 1.0
local fadeAnimStart = 0
local fadeAnimFrom  = 1.0
local fadeAnimating = false
local fadeActive    = false   -- fading system enabled
local fadeCombat    = InCombatLockdown() and true or false
local fadeMountd    = IsMounted() and true or false

local fadeAnimFrame  = CreateFrame("Frame")
local fadeEventFrame = CreateFrame("Frame")

local function FadeApply(a)
    if frame     then frame:SetAlpha(a)     end
    if furyFrame then furyFrame:SetAlpha(a) end
end

local function FadeStop()
    fadeAnimating = false
    fadeAnimFrame:SetScript("OnUpdate", nil)
end

local function FadeShowImmediate()
    FadeStop()
    fadeAlpha  = 1.0
    fadeTarget = 1.0
    FadeApply(1.0)
end

local function FadeBeginOut()
    local db  = GetDB()
    local L   = db and db.layout
    local raw = L and tonumber(L.fadingOpacity) or 0
    if raw < 0 then raw = 0 elseif raw > 100 then raw = 100 end
    fadeTarget = raw / 100

    if fadeAlpha <= fadeTarget then
        FadeStop(); fadeAlpha = fadeTarget; FadeApply(fadeAlpha); return
    end

    fadeAnimStart = GetTime()
    fadeAnimFrom  = fadeAlpha
    if not fadeAnimating then
        fadeAnimating = true
        fadeAnimFrame:SetScript("OnUpdate", function()
            local t = (GetTime() - fadeAnimStart) / FADE_DURATION
            if t >= 1.0 then t = 1.0; FadeStop() end
            fadeAlpha = fadeAnimFrom + (fadeTarget - fadeAnimFrom) * t
            FadeApply(fadeAlpha)
        end)
    end
end

local function FadeEvaluate()
    if not fadeActive then return end
    local db = GetDB()
    local L  = db and db.layout
    if not L then return end

    local shouldFade = false
    if L.fadingTriggerNoTarget ~= false and not UnitExists("target") then
        shouldFade = true
    elseif L.fadingTriggerOOC and not fadeCombat then
        shouldFade = true
    elseif L.fadingTriggerMounted and fadeMountd then
        shouldFade = true
    end

    if shouldFade then FadeBeginOut() else FadeShowImmediate() end
end

fadeEventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_TARGET_CHANGED" then
        FadeEvaluate()
    elseif event == "PLAYER_REGEN_ENABLED" then
        fadeCombat = false; FadeEvaluate()
    elseif event == "PLAYER_REGEN_DISABLED" then
        fadeCombat = true;  FadeEvaluate()
    elseif event == "PLAYER_MOUNT_DISPLAY_CHANGED"
        or event == "UPDATE_SHAPESHIFT_FORM" then
        fadeMountd = IsMounted()
            or (DRUID_TRAVEL_IDS[GetShapeshiftFormID()] and true or false)
        FadeEvaluate()
    end
end)

local function FadeActivate()
    if fadeActive then return end
    fadeActive = true
    fadeCombat = InCombatLockdown() and true or false
    fadeMountd = IsMounted()
        or (DRUID_TRAVEL_IDS[GetShapeshiftFormID()] and true or false)
    fadeEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    fadeEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    fadeEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    fadeEventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    fadeEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    FadeEvaluate()
end

FadeDeactivate = function()
    if not fadeActive then return end
    fadeActive = false
    fadeEventFrame:UnregisterAllEvents()
    if fadeAlpha < 1.0 or fadeAnimating then FadeShowImmediate() end
end

FadeRefresh = function()
    local db = GetDB()
    local L  = db and db.layout
    if L and L.fadingEnabled then
        FadeActivate(); FadeEvaluate()
    else
        FadeDeactivate()
    end
end

-- ============================================================
-- CDM setup
-- ============================================================
local cdmSetupChecked = false

local function FindCDMCooldownIDForSpells(targetSpellIds)
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
        return nil
    end
    local targetSet = {}
    for _, sid in ipairs(targetSpellIds) do targetSet[sid] = true end

    local foundID
    for _, cat in ipairs({
        Enum.CooldownViewerCategory.Essential,
        Enum.CooldownViewerCategory.Utility,
        Enum.CooldownViewerCategory.TrackedBuff,
        Enum.CooldownViewerCategory.TrackedBar,
    }) do
        local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, true)
        if ok and ids then
            for _, id in ipairs(ids) do
                local ok2, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
                if ok2 and CDMInfoMatchesSet(info, targetSet) then
                    foundID = id
                    break
                end
            end
        end
        if foundID then break end
    end
    if not foundID then return nil end

    local currentCat
    if CooldownViewerSettings and CooldownViewerSettings.GetDataProvider then
        local okp, provider = pcall(CooldownViewerSettings.GetDataProvider,
                                    CooldownViewerSettings)
        if okp and provider and provider.GetCooldownInfoForID then
            local oki, info = pcall(provider.GetCooldownInfoForID, provider, foundID)
            if oki and info then currentCat = info.category end
        end
    end
    return foundID, currentCat
end

local CATEGORY_NAMES = {}
local function CategoryName(cat)
    if not next(CATEGORY_NAMES) and Enum and Enum.CooldownViewerCategory then
        for k, v in pairs(Enum.CooldownViewerCategory) do
            CATEGORY_NAMES[v] = k
        end
    end
    return CATEGORY_NAMES[cat] or tostring(cat)
end

local function CaptureCDMSnapshot()
    if not C_CooldownViewer or not C_CooldownViewer.GetLayoutData then return end
    local db = GetDB()
    if type(db) ~= "table" then return end
    if type(db.cdmBackup) == "string" and db.cdmBackup ~= "" then return end
    local ok, data = pcall(C_CooldownViewer.GetLayoutData)
    if ok and type(data) == "string" and data ~= "" then
        db.cdmBackup = data
    end
end

local function HasCDMSnapshot()
    local db = GetDB()
    return type(db) == "table"
        and type(db.cdmBackup) == "string"
        and db.cdmBackup ~= ""
end

local TRACKED_SPELLS = {
    { label = "Collapsing Star",    spellIDs = { CS_SPELLID } },
    { label = "Void Metamorphosis", spellIDs = { VM_STACK_SPELLID } },
    { label = "Moment of Craving",  spellIDs = { 1238495, 1238488 } },
}

local function IsVisibleCategory(cat)
    return cat == Enum.CooldownViewerCategory.TrackedBuff
        or cat == Enum.CooldownViewerCategory.TrackedBar
        or cat == Enum.CooldownViewerCategory.Essential
        or cat == Enum.CooldownViewerCategory.Utility
end

local function IsHiddenCategory(cat)
    return cat == Enum.CooldownViewerCategory.HiddenSpell
        or cat == Enum.CooldownViewerCategory.HiddenAura
end

local function ApplyBatchAndReload(moves, summary)
    if InCombatLockdown and InCombatLockdown() then
        print("|cffffcc00[ReapPredict]|r Cannot modify CDM in combat, try out of combat.")
        return false
    end
    if #moves == 0 then
        print("|cff88ddff[ReapPredict]|r " .. summary .. ", nothing to change.")
        return true
    end
    if not (CooldownViewerSettings and CooldownViewerSettings.GetDataProvider) then
        print("|cffffcc00[ReapPredict]|r CooldownViewerSettings missing.")
        return false
    end
    CaptureCDMSnapshot()
    local provider = CooldownViewerSettings:GetDataProvider()
    if not provider or not provider.SetCooldownToCategory then
        print("|cffffcc00[ReapPredict]|r CDM data provider missing SetCooldownToCategory.")
        return false
    end
    for _, m in ipairs(moves) do
        pcall(securecall, provider.SetCooldownToCategory, provider, m.cdID, m.targetCat)
    end
    if provider.MarkDirty then
        pcall(securecall, provider.MarkDirty, provider)
    end
    local lm = provider.GetLayoutManager and provider:GetLayoutManager()
    if lm and lm.SaveLayouts then
        pcall(securecall, lm.SaveLayouts, lm)
    end
    print(("|cff88ddff[ReapPredict]|r %s, reloading UI..."):format(summary))
    ReloadUI()
    return true
end

local function CollectMoves(targetCat, alreadyOK)
    local moves = {}
    for _, entry in ipairs(TRACKED_SPELLS) do
        local cdID, currentCat = FindCDMCooldownIDForSpells(entry.spellIDs)
        if not cdID then
            print(("|cffffcc00[ReapPredict]|r Couldn't find %s in CDM's known cooldowns."):format(entry.label))
        elseif alreadyOK(currentCat) then
            dbg("%s (cdID=%d) already in %s.", entry.label, cdID, CategoryName(currentCat))
        else
            table.insert(moves, { cdID = cdID, targetCat = targetCat, label = entry.label })
            dbg("queued %s (cdID=%d): %s -> %s", entry.label, cdID, CategoryName(currentCat), CategoryName(targetCat))
        end
    end
    return moves
end

local function SetupAll()
    local moves = CollectMoves(Enum.CooldownViewerCategory.TrackedBuff, IsVisibleCategory)
    return ApplyBatchAndReload(moves,
        ("setup: moving %d spell(s) to CDM Tracked Buffs"):format(#moves))
end

local function UnsetupAll()
    local moves = CollectMoves(Enum.CooldownViewerCategory.HiddenAura, IsHiddenCategory)
    return ApplyBatchAndReload(moves,
        ("unsetup: moving %d spell(s) out of CDM"):format(#moves))
end

local function RestoreCDMLayout()
    if not HasCDMSnapshot() then
        print("|cffffcc00[ReapPredict]|r No CDM snapshot stored. Nothing to restore.")
        return false
    end
    if not (C_CooldownViewer and C_CooldownViewer.SetLayoutData) then
        print("|cffffcc00[ReapPredict]|r C_CooldownViewer.SetLayoutData missing.")
        return false
    end
    print("|cff88ddff[ReapPredict]|r Restoring CDM layout snapshot, reloading UI...")
    local db = GetDB()
    pcall(C_CooldownViewer.SetLayoutData, db.cdmBackup)
    ReloadUI()
    return true
end

local setupDialog
local function ShowSetupDialog(missing)
    if not setupDialog then
        local d = CreateFrame("Frame", "SP_ReapPredictSetupDialog", UIParent, "BackdropTemplate")
        d:SetSize(420, 180)
        d:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        d:SetFrameStrata("HIGH")
        d:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        d:SetMovable(true)
        d:EnableMouse(true)
        d:RegisterForDrag("LeftButton")
        d:SetScript("OnDragStart", d.StartMoving)
        d:SetScript("OnDragStop",  d.StopMovingOrSizing)
        d:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then self:Hide() end
        end)
        d:SetPropagateKeyboardInput(true)

        local title = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", d, "TOP", 0, -16)
        title:SetText("Reaper")

        local body = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT",  d, "TOPLEFT",  20,  -42)
        body:SetPoint("TOPRIGHT", d, "TOPRIGHT", -20, -42)
        body:SetJustifyH("LEFT")
        body:SetJustifyV("TOP")
        d.bodyText = body

        local accept = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
        accept:SetSize(140, 24)
        accept:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -6, 14)
        accept:SetText("Add to CDM")
        accept:SetScript("OnClick", function()
            d:Hide()
            SetupAll()
        end)

        local cancel = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
        cancel:SetSize(140, 24)
        cancel:SetPoint("BOTTOMLEFT", d, "BOTTOM", 6, 14)
        cancel:SetText("Not now")
        cancel:SetScript("OnClick", function() d:Hide() end)

        setupDialog = d
    end
    local lines = {}
    for _, label in ipairs(missing) do
        table.insert(lines, "  - " .. label)
    end
    setupDialog.bodyText:SetText(
        "Reaper needs these spells in the Cooldown Manager:\n\n" ..
        table.concat(lines, "\n") ..
        "\n\nAdd them automatically? This will reload your UI.")
    setupDialog:Show()
end

local function CheckCDMSetup()
    if cdmSetupChecked then return end
    if not IsDDH() then return end
    local missing = {}
    for _, entry in ipairs(TRACKED_SPELLS) do
        local cdID, currentCat = FindCDMCooldownIDForSpells(entry.spellIDs)
        if cdID and not IsVisibleCategory(currentCat) then
            table.insert(missing, entry.label)
        end
    end
    if #missing == 0 then return end
    if InCombatLockdown and InCombatLockdown() then
        if C_Timer and C_Timer.After then
            C_Timer.After(5.0, CheckCDMSetup)
        end
        return
    end
    cdmSetupChecked = true
    ShowSetupDialog(missing)
end

-- ============================================================
-- Blizzard Settings panel (verbatim)
-- ============================================================
local DumpState
local DumpCDMViewer

local settingsCategory
local function RegisterSettings()
    -- Settings have moved to the SuspicionsPack GUI (/spack → Reap Meter).
    do return end
    --[[ kept for reference only — dead code below
    if settingsCategory or not Settings or not Settings.RegisterAddOnCategory then return end
    local db = GetDB()
    if type(db) ~= "table" or type(db.layout) ~= "table" then return end

    local category, layout = Settings.RegisterVerticalLayoutCategory("Reaper")

    local function registerSetting(key, varType, db_, label)
        return Settings.RegisterAddOnSetting(
            category, "RM_" .. key, key, db_, varType, label, db_[key])
    end
    local function addSlider(label, key, minVal, maxVal, step, onChange, tooltip)
        local setting = registerSetting(key, Settings.VarType.Number, db.layout, label)
        setting:SetValueChangedCallback(function(_, value) onChange(value); ApplySize() end)
        local options = Settings.CreateSliderOptions(minVal, maxVal, step)
        if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        end
        Settings.CreateSlider(category, setting, options, tooltip)
    end
    local function addCheckbox(label, key, db_, tooltip, onChange)
        local setting = registerSetting(key, Settings.VarType.Boolean, db_, label)
        setting:SetValueChangedCallback(function(_, value) onChange(value) end)
        Settings.CreateCheckbox(category, setting, tooltip)
    end
    local function addButton(left, right, fn, tooltip)
        layout:AddInitializer(CreateSettingsButtonInitializer(left, right, fn, tooltip, true))
    end
    local function addSection(name)
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(name))
    end

    addSection("Soul bar")
    addCheckbox("Show soul bar", "showSoulBar", db.layout,
        "Primary bar tracking VM/CS stacks and Soul Fragments toward the next phase ability.",
        UpdateSoulBarVisibility)
    addSlider("Bar width",  "width",  100, 1200, 1, function(v) CONTAINER_W      = v end, "Soul bar width in pixels.")
    addSlider("Bar height", "height",  10,  100, 1, function(v) CONTAINER_H      = v end, "Soul bar height in pixels.")
    addSlider("Font size",  "font",     6,   32, 1, function(v) NUMBER_FONT_SIZE = v end, "Pixel size of the growth and SF numeric labels.")

    local fontSetting = registerSetting("fontKey", Settings.VarType.String, db.layout, "Font")
    fontSetting:SetValueChangedCallback(function(_, value)
        NUMBER_FONT = FontPath(value)
        ApplySize()
        ApplyFurySize()
    end)
    Settings.CreateDropdown(category, fontSetting, function()
        local container = Settings.CreateControlTextContainer()
        for _, f in ipairs(FONTS) do container:Add(f.key, f.name) end
        return container:GetData()
    end, "Font face for all numeric labels on both bars.")

    addCheckbox("Lock soul bar position", "locked", db.layout,
        "Prevent dragging the soul bar.", ApplyLock)
    addCheckbox("Show MoC capacity preview", "showMocPreview", db.layout,
        "Show the dim Moment of Craving capacity estimate on the SF region when MoC isn't up.",
        function() if frame then ApplySFCap(lastMoCActive == true) end end)
    addCheckbox("Show Collapsing Star cast counter", "showCsCounter", db.layout,
        "Show the CS cast count to the right of the soul bar.",
        function()
            if frame and frame.csCounterLabel then
                frame.csCounterLabel:SetShown(db.layout.showCsCounter ~= false)
            end
        end)
    addButton("Soul bar position", "Reset", function()
        db.framePos = nil
        ApplySavedPosition()
    end, "Reset the soul bar to its default centered position.")

    addSection("Fury bar")
    addCheckbox("Show fury bar", "showFuryBar", db.layout,
        "Secondary bar showing current fury plus Reap's projected gain against the Void Ray threshold.",
        UpdateFuryVisibility)

    local function addFurySlider(label, key, minVal, maxVal, step, tooltip)
        local setting = registerSetting(key, Settings.VarType.Number, db.layout, label)
        setting:SetValueChangedCallback(function(_, value)
            db.layout[key] = value
            ApplyFurySize()
        end)
        local options = Settings.CreateSliderOptions(minVal, maxVal, step)
        if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        end
        Settings.CreateSlider(category, setting, options, tooltip)
    end

    addFurySlider("Bar width",       "furyWidth",  100, 1200, 1, "Fury bar width in pixels.")
    addFurySlider("Bar height",      "furyHeight",   8,   60, 1, "Fury bar height in pixels.")
    addFurySlider("Fury value font", "furyFont",     6,   32, 1, "Pixel size of the centered fury value.")
    addCheckbox("Show MoC capacity preview (fury)", "showFuryMocPreview", db.layout,
        "Show the dim MoC capacity estimate on the fury bar.",
        function() if furyFrame then ApplyFurySoulCap(lastMoCActive == true) end end)
    addCheckbox("Lock fury bar position", "furyLocked", db.layout,
        "Prevent dragging the fury bar.", ApplyFuryLock)
    addButton("Fury bar position", "Reset", function()
        db.furyPos = nil
        ApplyFuryPosition()
    end, "Reset the fury bar to its default position.")

    addSection("Colors")

    local function attachSwatch(row, key)
        local sw = row._rmColorSwatch
        if not sw then
            local border = row:CreateTexture(nil, "OVERLAY", nil, 5)
            border:SetColorTexture(0, 0, 0, 1)
            local inner = row:CreateTexture(nil, "OVERLAY", nil, 6)
            inner:SetPoint("TOPLEFT",     border, "TOPLEFT",     1, -1)
            inner:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -1, 1)
            row._rmColorSwatch = inner
            row._rmColorBorder = border
            sw = inner
        end
        local anchor = row.Button or row.Control or row
        local relPoint = (anchor == row) and "RIGHT" or "LEFT"
        local xOff = (anchor == row) and -160 or -8
        row._rmColorBorder:ClearAllPoints()
        row._rmColorBorder:SetPoint("RIGHT", anchor, relPoint, xOff, 0)
        row._rmColorBorder:SetSize(22, 16)
        row._rmColorBorder:Show()
        sw:SetColorTexture(C(key))
        sw:Show()
        activeColorSwatches[sw] = key
    end

    local function detachSwatch(row)
        local sw = row._rmColorSwatch
        if not sw then return end
        activeColorSwatches[sw] = nil
        sw:Hide()
        if row._rmColorBorder then row._rmColorBorder:Hide() end
    end

    local function addColorPicker(label, key, tooltip)
        local function openPicker()
            local snapshot = CopyColor(db.colors[key] or DEFAULT_COLORS[key])
            local function onChange()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                local na = ColorPickerFrame.GetColorAlpha
                    and ColorPickerFrame:GetColorAlpha()
                    or snapshot[4]
                db.colors[key] = { nr, ng, nb, na }
                ApplyColors()
            end
            local function onCancel()
                db.colors[key] = snapshot
                ApplyColors()
            end
            if ColorPickerFrame.SetupColorPickerAndShow then
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = snapshot[1], g = snapshot[2], b = snapshot[3],
                    opacity = snapshot[4], hasOpacity = true,
                    swatchFunc  = onChange,
                    opacityFunc = onChange,
                    cancelFunc  = onCancel,
                })
            end
        end

        local init = CreateSettingsButtonInitializer(label, "Choose...", openPicker, tooltip, true)
        local origInit, origReset = init.InitFrame, init.Resetter
        init.InitFrame = function(self, row)
            if origInit then origInit(self, row) end
            attachSwatch(row, key)
        end
        init.Resetter = function(self, row)
            if origReset then origReset(self, row) end
            detachSwatch(row)
        end
        layout:AddInitializer(init)
    end

    addSection("Colors - Shared")
    addColorPicker("Background",                     "bg",             "Frame background color.")
    addColorPicker("Outer edge",                     "edge",           "1px outer border color.")
    addSection("Colors - Soul bar")
    addColorPicker("Growth bar (build phase)",       "growthBuild",    "Fill color charging Void Metamorphosis.")
    addColorPicker("Threshold tick (build phase)",   "thresholdBuild", "Vertical tick at 50 VM stacks.")
    addColorPicker("Beyond threshold (build phase)", "beyondBuild",    "Dim backdrop of overflow region (build).")
    addColorPicker("Growth bar (VM phase)",          "growthVM",       "Fill color charging Collapsing Star.")
    addColorPicker("Threshold tick (VM phase)",      "thresholdVM",    "Vertical tick at 30 CS stacks.")
    addColorPicker("Beyond threshold (VM phase)",    "beyondVM",       "Dim backdrop of overflow region (VM).")
    addColorPicker("Soul Fragments (MoC inactive)",  "sfBase",         "SF bar color without MoC.")
    addColorPicker("Soul Fragments (MoC active)",    "sfMoc",          "SF bar color with MoC up.")
    addColorPicker("MoC duration bar (fill)",        "mocRailFill",    "MoC duration sub-rail fill.")
    addColorPicker("MoC duration bar (track)",       "mocRailTrack",   "MoC duration sub-rail track.")
    addColorPicker("Growth number text",             "numberLabel",    "Growth / CS-counter label color.")
    addColorPicker("SF number text",                 "sfNumberLabel",  "Soul Fragments count color.")
    addSection("Colors - Fury bar")
    addColorPicker("Current fury fill",              "furyFill",       "Main fury fill segment.")
    addColorPicker("Scythes Embrace flat",           "furyFlat",       "Reap flat 10-fury bonus segment.")
    addColorPicker("Soul projection",                "furySoul",       "Reap per-soul fury gain segment.")
    addColorPicker("100-fury tick",                  "furyTick",       "Vertical tick at Void Ray cost.")
    addColorPicker("Fury value text",                "furyLabel",      "Centered fury number color.")
    addButton("All colors", "Reset to defaults", function()
        db.colors = {}
        for k, v in pairs(DEFAULT_COLORS) do
            db.colors[k] = CopyColor(v)
        end
        ApplyColors()
    end, "Reset every color to its default value.")

    addSection("CDM Tracking")
    addButton("Tracked spells", "Add to CDM",          SetupAll,         "Add CS, VM, and MoC to CDM Tracked Buffs.")
    addButton("",               "Remove from CDM",     UnsetupAll,       "Move tracked spells back to CDM Hidden.")
    addButton("",               "Restore CDM snapshot",RestoreCDMLayout, "Revert CDM to pre-Reaper snapshot.")

    addSection("Debug")
    addCheckbox("Debug Logging", "debug", db,
        "Print state changes to chat.",
        function(v) debugOn = v end)
    addButton("Diagnostics", "Dump State",
        function() if DumpState then DumpState() end end,
        "Print the addon's full state to chat.")
    addButton("", "Dump CDM Frames", function()
        if not DumpCDMViewer then return end
        for _, v in ipairs(CDM_VIEWERS) do DumpCDMViewer(v, true) end
    end, "Print every CDM frame's state to chat.")

    Settings.RegisterAddOnCategory(category)
    settingsCategory = category
    --]] -- end dead-code block
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function ReapPredict:OnEnable()
    LoadSizesFromDB()
    RegisterSettings()

    self:RegisterEvent("PLAYER_ENTERING_WORLD",          "OnPlayerEnteringWorld")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED",  "OnRefreshEvent")
    self:RegisterEvent("TRAIT_CONFIG_UPDATED",           "OnRefreshEvent")

    Refresh()

    if C_Timer and C_Timer.After then
        C_Timer.After(3.0, CheckCDMSetup)
    end

    -- Raw unit event frame (AceEvent doesn't support RegisterUnitEvent)
    if not ReapPredict._eventsFrame then
        local events = CreateFrame("Frame")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED",     "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP",  "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        events:RegisterUnitEvent("UNIT_AURA",                    "player")
        events:RegisterUnitEvent("UNIT_POWER_FREQUENT",          "player")

        local CONSUMING_SPELLS = {
            [REAP_SPELLID]      = true,
            [ERADICATE_SPELLID] = true,
            [CULL_SPELLID]      = true,
        }
        local DEBUG_LOGGED_CASTS = {
            [VOID_RAY_SPELLID]  = true,
            [REAP_SPELLID]      = true,
            [ERADICATE_SPELLID] = true,
            [CONSUME_SPELLID]   = true,
        }

        events:SetScript("OnEvent", function(_, event, unit, arg1, arg2)
            if not IsDDH() then return end

            if event == "UNIT_POWER_FREQUENT" then
                -- arg1 = powerToken (e.g. "FURY") — only update for fury changes
                if arg1 == "FURY" then UpdateMeter() end
                return
            end

            if event == "UNIT_SPELLCAST_SUCCEEDED" then
                local spellID = arg2
                if CONSUMING_SPELLS[spellID] then
                    pauseUntil = GetTime() + CONSUME_PAUSE_SEC
                end
                if CS_CAST_SPELL_SET[spellID] then
                    SetCSCount(csCastCount + 1)
                end
                if debugOn and DEBUG_LOGGED_CASTS[spellID] then
                    dbg("CAST_SUCCESS sid=%s", tostring(spellID))
                end
                return
            end

            if not debugOn then return end

            if event == "UNIT_SPELLCAST_CHANNEL_START" then
                if arg2 == VOID_RAY_SPELLID then dbg("VoidRay channel START") end
            elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
                if arg2 == VOID_RAY_SPELLID then
                    dbg("VoidRay channel STOP, dumping CDM in 0.2s")
                    C_Timer.After(0.2, function()
                        if not debugOn then return end
                        for _, v in ipairs(CDM_VIEWERS) do DumpCDMViewer(v, false) end
                        local moc = FindMoCCDMFrame()
                        local sf  = FindSFCDMFrame()
                        dbg("post-VoidRay: MoC frame=%s, SF frame=%s", tostring(moc), tostring(sf))
                        if moc then
                            dbg("  MoC auraInstanceID=%s", secretSafeStr(rawget(moc, "auraInstanceID")))
                        end
                    end)
                end
            elseif event == "UNIT_AURA" then
                local updateInfo = type(arg1) == "table" and arg1
                                or type(arg2) == "table" and arg2
                if not updateInfo then return end
                local addedN   = updateInfo.addedAuras             and #updateInfo.addedAuras             or 0
                local removedN = updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs or 0
                local updatedN = updateInfo.updatedAuraInstanceIDs and #updateInfo.updatedAuraInstanceIDs or 0
                if addedN > 0 or removedN > 0 then
                    dbg("UNIT_AURA added=%d removed=%d updated=%d full=%s",
                        addedN, removedN, updatedN, tostring(updateInfo.isFullUpdate))
                end
                if updateInfo.addedAuras then
                    for _, a in ipairs(updateInfo.addedAuras) do
                        dbg("  AURA+ iid=%s sid=%s name=%s helpful=%s",
                            tostring(a.auraInstanceID), secretSafeStr(a.spellId),
                            secretSafeStr(a.name), tostring(a.isHelpful))
                    end
                end
                if updateInfo.removedAuraInstanceIDs then
                    for _, iid in ipairs(updateInfo.removedAuraInstanceIDs) do
                        local cachedSFIID  = cdmSFFrame  and rawget(cdmSFFrame,  "auraInstanceID")
                        local cachedMoCIID = cdmMoCFrame and rawget(cdmMoCFrame, "auraInstanceID")
                        if iid == cachedMoCIID then
                            dbg("  AURA- iid=%s (was MoC)", tostring(iid))
                        elseif iid == cachedSFIID then
                            dbg("  AURA- iid=%s (was SF)", tostring(iid))
                        end
                    end
                end
            end
        end)
        ReapPredict._eventsFrame = events
    end
end

function ReapPredict:OnDisable()
    self:UnregisterAllEvents()
    Disable()
end

function ReapPredict:OnPlayerEnteringWorld()
    Refresh()
    if C_Timer and C_Timer.After then
        C_Timer.After(3.0, CheckCDMSetup)
        -- Retry CDM sync hook: Ayije_CDM may not have built anchorContainers yet at OnEnable
        C_Timer.After(1.0, function()
            EnsureCDMSyncHook()
            local db = GetDB(); local L = db and db.layout
            if L and L.syncToCDM then SyncToCDMNow() end
        end)
        -- Re-evaluate fading after the world finishes loading. WoW can reset
        -- frame alpha during the loading-screen transition, so the initial
        -- FadeRefresh() inside Enable() fires too early.
        C_Timer.After(0.5, function()
            if FadeRefresh then FadeRefresh() end
        end)
    end
end

function ReapPredict:OnRefreshEvent()
    Refresh()
end

-- ============================================================
-- Diagnostics
-- ============================================================
local function DumpCDMFrameDetails(itemFrame)
    local sections = {}
    for _, field in ipairs({ "auraInstanceID", "stackCount", "charges", "applications" }) do
        local v = rawget(itemFrame, field)
        if v ~= nil then
            sections[#sections + 1] = ("%s=%s"):format(field, secretSafeStr(v))
        end
    end
    if #sections > 0 then
        print(("    details: %s"):format(table.concat(sections, "; ")))
    end
end

function DumpCDMViewer(viewerName, detailed)
    local viewer = _G[viewerName]
    if not viewer then
        print(("|cff88ddff[RM]|r %s viewer: missing"):format(viewerName))
        return
    end
    if not viewer.itemFramePool then
        print(("|cff88ddff[RM]|r %s: no itemFramePool"):format(viewerName))
        return
    end
    print(("|cff88ddff[RM]|r %s active frames:"):format(viewerName))
    local n = 0
    for itemFrame in viewer.itemFramePool:EnumerateActive() do
        n = n + 1
        local cdID
        if itemFrame.GetCooldownID then
            local ok, id = pcall(itemFrame.GetCooldownID, itemFrame)
            if ok then cdID = id end
        end
        local sid, linked
        if cdID and C_CooldownViewer then
            local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
            if ok and info then
                sid = info.spellID or info.overrideSpellID or info.overrideTooltipSpellID
                linked = info.linkedSpellIDs
            end
        end
        local linkedStr = ""
        if linked then
            local parts = {}
            for _, id in ipairs(linked) do parts[#parts+1] = tostring(id) end
            linkedStr = (", linked={%s}"):format(table.concat(parts, ","))
        end
        print(("  #%d shown=%s cdID=%s sid=%s%s"):format(
            n, tostring(itemFrame:IsShown()), tostring(cdID), tostring(sid), linkedStr))
        if detailed then DumpCDMFrameDetails(itemFrame) end
    end
    if n == 0 then print("  (no active frames)") end
end

function DumpState()
    local db = GetDB()
    local mocActive = ReadMoCActive()
    local inVM = IsInVMPhase()
    print(("|cff88ddff[RM]|r DDH=%s inCombat=%s debug=%s"):format(
        tostring(IsDDH()),
        tostring(UnitAffectingCombat and UnitAffectingCombat("player")),
        tostring(debugOn)))
    print(("  phase: %s (Reap -> %s, threshold %d, growth max %d)"):format(
        inVM and "VM" or "build",
        inVM and "Collapsing Star" or "Void Metamorphosis",
        inVM and CS_THRESHOLD or VM_THRESHOLD,
        inVM and CS_AURA_MAX  or VM_THRESHOLD))
    print(("  CS aura apps: %s"):format(secretSafeStr(ReadCSApplications())))
    print(("  VM stack apps: %s"):format(secretSafeStr(ReadVMStacks())))
    print(("  SF CDM stacks: %s"):format(secretSafeStr(ReadSFStackFromCDM())))
    print(("  MoC active: %s (Reap cap = %d)"):format(
        tostring(mocActive), mocActive and REAP_CAP_MOC or REAP_CAP_BASE))
    print(("  cached frames: SF=%s, MoC=%s"):format(tostring(cdmSFFrame), tostring(cdmMoCFrame)))
    local ok, fury = pcall(UnitPower, "player", FURY_POWER_TYPE)
    local flat = scythesEmbraceKnown and REAP_CAST_FURY or 0
    print(("  fury: %s / %d   ScythesEmbrace=%s   Reap fury=%d+%d*souls"):format(
        ok and secretSafeStr(fury) or "error", VOID_RAY_COST,
        tostring(scythesEmbraceKnown), flat, REAP_SOUL_FURY))
    local cdID = FindCDMCooldownIDForSpells(MOC_SPELLIDS)
    print(("  MoC cdID=%s; cdmBackup=%s"):format(
        tostring(cdID),
        db and (db.cdmBackup and "saved" or "missing") or "no DB"))
end

-- ============================================================
-- Public API
-- ============================================================
function ReapPredict.Refresh()
    Refresh()
end

-- GUI-callable wrappers (closures over module-local state)
ReapPredict.DEFAULT_COLORS     = DEFAULT_COLORS
ReapPredict.FONTS              = FONTS
-- ApplySize reads CONTAINER_W/H/NUMBER_FONT* from module-local vars, not the DB.
-- This wrapper syncs those vars from the DB first so GUI sliders take effect.
ReapPredict.ApplySize = function()
    local db = GetDB()
    local L  = db and db.layout
    if L then
        if L.width   then CONTAINER_W      = L.width   end
        if L.height  then CONTAINER_H      = L.height  end
        if L.font    then NUMBER_FONT_SIZE = L.font    end
        if L.fontKey then NUMBER_FONT      = FontPath(L.fontKey) end
    end
    ApplySize()
end
ReapPredict.ApplyFurySize      = ApplyFurySize   -- already reads layout from DB internally
ReapPredict.ApplyColors        = ApplyColors
ReapPredict.ApplyLock          = ApplyLock
ReapPredict.ApplyFuryLock      = ApplyFuryLock
ReapPredict.ApplySavedPosition = ApplySavedPosition
ReapPredict.ApplyFuryPosition  = ApplyFuryPosition
ReapPredict.UpdateSoulBarVisibility = UpdateSoulBarVisibility
ReapPredict.UpdateFuryVisibility    = UpdateFuryVisibility

ReapPredict.ApplyMoCRailPosition = ApplyMoCRailPosition

ReapPredict.ApplyMoCPreview = function()
    if not (frame and frame.mocPreview) then return end
    local moc = lastMoCActive == true
    -- preview is only meaningful when MoC is not active
    frame.mocPreview:SetShown(not moc and ShowMoCPreviewPref())
end
ReapPredict.ApplyFuryMoCPreview = function()
    if not (furyFrame and furyFrame.soulFuryPreview) then return end
    local moc = lastMoCActive == true
    furyFrame.soulFuryPreview:SetShown(not moc and ShowFuryMocPreviewPref())
    local db = GetDB(); local L = db and db.layout
    local r, g, b = C("furySoul")
    local a = (L and L.furyPreviewAlpha) or FURY_PREVIEW_ALPHA_DEFAULT
    furyFrame.soulFuryPreview:SetStatusBarColor(r, g, b, a)
end
ReapPredict.ApplyCsCounter = function()
    if not (frame and frame.csCounterLabel) then return end
    local db = GetDB()
    local L  = db and db.layout
    -- default is shown; only hide when explicitly set to false
    frame.csCounterLabel:SetShown(L == nil or L.showCsCounter ~= false)
end
ReapPredict.SyncToCDMNow          = SyncToCDMNow
ReapPredict.RebuildCellSeparators  = RebuildCellSeparators
ReapPredict.FadeRefresh            = FadeRefresh
ReapPredict.SetupAll         = SetupAll
ReapPredict.UnsetupAll       = UnsetupAll
ReapPredict.RestoreCDMLayout = RestoreCDMLayout
ReapPredict.ResetColors      = function()
    local db = GetDB()
    if not db then return end
    db.colors = {}
    for k, v in pairs(DEFAULT_COLORS) do
        db.colors[k] = CopyColor(v)
    end
    ApplyColors()
end
