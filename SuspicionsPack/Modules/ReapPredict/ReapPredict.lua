-- SuspicionsPack — ReapPredict Module
-- Devourer DH dual-phase meter. Tracks when Reap will trigger the next
-- phase ability (Void Metamorphosis or Collapsing Star).
-- Activates automatically for Devourer DH only.
local SP = SuspicionsPack

local ReapPredict = SP:NewSPModule("ReapPredict", "reapMeter")
SP.ReapPredict = ReapPredict

-- ============================================================
-- DB accessor
-- ============================================================
local function GetDB()
    return SP.GetDB().reapMeter
end

-- ============================================================
-- Constants
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

local COLOR_VERSION = 9

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
    furyConsume    = { 0.45, 0.38, 0.78, 1.00 },
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

local SCYTHES_EMBRACE_SPELLID  = 1246558
local CELESTIAL_ECHOES_SPELLID = 1253415
local REAP_CAST_FURY           = 10
local REAP_SOUL_FURY           = 4
local VOID_RAY_COST            = 100
local CONSUME_BASE_FURY        = 8
local CONSUME_CELESTIAL_MOD    = 2
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
-- pcall does NOT contain taint: a `not aura` truthiness test or an `aura ~= nil`
-- comparison on a secret value taints execution just the same, and here the
-- results drive SetShown/SetValue calls, so the taint reaches Blizzard frames.
-- Same class as the isOnGCD bug (see lessons.md).
local function ReadAuraApplications(spellID)
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok then return nil end
    if issecretvalue(aura) then return nil end
    if not aura then return nil end
    return aura.applications
end

local function ReadCSApplications() return ReadAuraApplications(CS_SPELLID) end
local function ReadVMStacks()       return ReadAuraApplications(VM_STACK_SPELLID) end

local function IsInVMPhase()
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, VM_FORM_SPELLID)
    if not ok or issecretvalue(aura) then return false end
    return aura ~= nil
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

-- WoW native ExponentialEaseOut smooth — no per-frame lerp, no taint issues,
-- visually identical to Ellesmere bar speed.
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

-- Snap-to-external-bar helpers. Declared here (and filled in further down)
-- because UpdateFuryBar sits above the implementation and a closure cannot
-- reach a `local function` defined later in the file.
--
-- Grouped into one table rather than six file-scope locals: this file is close
-- to Lua's hard limit of 200 locals per chunk, and six more tipped it over.
local Snap = { barName = "ERB_PrimaryBar" }   -- EllesmereUI's primary (power) bar

local scythesEmbraceKnown   = false
local celestialEchoesKnown  = false
local consumeGain           = 0   -- fury predicted during an active Consume cast (0 = not casting)

local function RefreshCelestialEchoes()
    celestialEchoesKnown = false
    if IsPlayerSpell then
        local ok, known = pcall(IsPlayerSpell, CELESTIAL_ECHOES_SPELLID)
        if ok and known then celestialEchoesKnown = true; return end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, CELESTIAL_ECHOES_SPELLID)
        if ok and known then celestialEchoesKnown = true end
    end
end

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
-- Called on phase change and resize.
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
    -- Self-healing: the bar we snap to belongs to another addon and may be
    -- created after us, or rebuilt on a spec change, so retry until it takes.
    -- Throttled to 1 Hz because the retry runs a full ApplyFuryLayout -- with
    -- the toggle on but EllesmereUI absent it would otherwise never stop.
    if Snap.Wanted() and not furyFrame._snapped then
        local now = GetTime()
        if now - (furyFrame._snapRetryAt or 0) >= 1 then
            furyFrame._snapRetryAt = now
            ApplyFuryLayout()
        end
    end
    local fury = UnitPower("player", FURY_POWER_TYPE)
    ApplyToBar(furyFrame.furyFillBar,     fury)
    ApplyToBar(furyFrame.consumeBar,      consumeGain)
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

    local consumeMax = CONSUME_BASE_FURY + CONSUME_CELESTIAL_MOD
    local consumeBar = CreateFrame("StatusBar", nil, furyFrame)
    consumeBar:SetFrameStrata("MEDIUM")
    consumeBar:SetPoint("LEFT", furyFillBar:GetStatusBarTexture(), "RIGHT", 0, 0)
    consumeBar:SetSize(consumeMax * pxPerFury, H)
    consumeBar:SetStatusBarTexture(BAR_TEXTURE)
    consumeBar:SetStatusBarColor(C("furyConsume"))
    consumeBar:SetMinMaxValues(0, consumeMax)
    consumeBar:SetValue(0)

    local flatBar = CreateFrame("StatusBar", nil, furyFrame)
    flatBar:SetFrameStrata("MEDIUM")
    flatBar:SetPoint("LEFT", consumeBar:GetStatusBarTexture(), "RIGHT", 0, 0)
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
    -- Frame edge, NOT the fill texture: this preview's value domain starts at
    -- REAP_CAP_BASE, so its left edge must sit at the position of that stack
    -- count (soulFuryBar's full width), not wherever the fill happens to be.
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
    furyFrame.consumeBar      = consumeBar
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

-- ============================================================
-- Snap-to-external-bar
--
-- Glues the prediction chain to the fill edge of another addon's resource bar
-- (EllesmereUI's ERB_PrimaryBar by default) so there is never a gap between
-- where their fill ends and where our prediction starts.
--
-- The whole trick is that we anchor to the external bar's STATUS BAR TEXTURE,
-- not to its frame. The texture's right edge *is* the fill edge, and because
-- it is a real anchor the engine re-resolves it every frame -- including
-- during the external bar's own smooth-fill interpolation. No polling, no
-- arithmetic, no timing skew: the gap is impossible by construction.
--
-- Overflow is handled the same way. Reparenting our bars onto the external
-- StatusBar means its SetClipsChildren(true) cuts us off exactly at its right
-- edge, so the prediction can never spill outside the frame at high fury.
-- ============================================================

-- Resolves a bar reference to { container, statusBar, fillTexture }.
-- Accepts either an EllesmereUI-style wrapper (outer Frame + inner `_sb`) or a
-- plain StatusBar, so this works with bars from other addons too.
function Snap.Resolve(name)
    if not name or name == "" then return nil end
    local f = _G[name]
    if not f or type(f) ~= "table" or not f.GetObjectType then return nil end

    -- EllesmereUI wraps its bars: the named global is a Frame holding the
    -- border, and the real StatusBar (which clips the fill) is on `_sb`.
    local sb = f._sb
    if not (sb and sb.GetStatusBarTexture) then
        if f.GetStatusBarTexture then sb = f else return nil end
    end

    local tex = sb:GetStatusBarTexture()
    if not tex then return nil end
    return f, sb, tex
end

function Snap.Name()
    local db = GetDB()
    local L  = db and db.layout
    local n  = L and L.snapBarName
    if n == nil or n == "" then return Snap.barName end
    return n
end

function Snap.Wanted()
    local db = GetDB()
    local L  = db and db.layout
    return (L and L.snapToBar) and true or false
end

-- Width + max of the external bar, so ApplyFuryLayout can compute px/fury in
-- the external bar's own scale. Returns nil when snapping is off or the bar is
-- not (yet) available, and callers fall back to our own geometry.
function Snap.Geometry()
    if not Snap.Wanted() then return nil end
    local _, sb = Snap.Resolve(Snap.Name())
    if not sb then return nil end

    if sb.IsRectValid and not sb:IsRectValid() then return nil end
    local w = sb:GetWidth()
    if not w or w <= 0 then return nil end

    -- Max always comes from the game, never from the external bar's
    -- GetMinMaxValues. Reading theirs looked appealing but buys nothing (they
    -- set it from UnitPowerMax too) and introduces a race: on a spec or talent
    -- change our handler can run before theirs, so we would bake px/fury from
    -- the stale max and never recompute. It would also mean doing arithmetic on
    -- another addon's widget values without an issecretvalue guard.
    local max = GetPlayerFuryMax()
    if not max or max <= 0 then return nil end

    return w, max
end

-- Points the head of the prediction chain at the right place and reparents the
-- chain so clipping applies. Safe to call repeatedly.
function Snap.ApplyAnchor()
    if not furyFrame then return end
    local head = furyFrame.consumeBar
    if not head then return end

    local chain = {
        furyFrame.consumeBar,
        furyFrame.flatBar,
        furyFrame.soulFuryBar,
        furyFrame.soulFuryPreview,
    }

    -- Remember the original frame levels once, so un-snapping restores them
    -- exactly instead of recomputing a value that collides with `overlay`.
    if not furyFrame._chainLevels then
        local lv = {}
        for i = 1, #chain do lv[i] = chain[i]:GetFrameLevel() end
        furyFrame._chainLevels = lv
    end

    local _, sb, tex
    if Snap.Wanted() then
        _, sb, tex = Snap.Resolve(Snap.Name())
    end

    -- Require the geometry too, not just the frames. Latching _snapped on the
    -- anchor alone would disarm the retry while px/fury had silently fallen
    -- back to our own scale -- glued in the right place at the wrong size.
    local geomOK = sb and tex and Snap.Geometry() ~= nil

    if geomOK then
        for _, bar in ipairs(chain) do
            if bar:GetParent() ~= sb then
                bar:SetParent(sb)
            end
            -- Strata is NOT inherited once explicitly set, and EllesmereUI lets
            -- the user pick one. Without this the prediction can render behind
            -- their opaque background.
            bar:SetFrameStrata(sb:GetFrameStrata())
            bar:SetFrameLevel(sb:GetFrameLevel() + 2)
        end
        head:ClearAllPoints()
        head:SetPoint("LEFT", tex, "RIGHT", 0, 0)

        -- Their bar draws the fury; ours would be a second, independently
        -- animated fill edge right next to the chain -- i.e. the gap again.
        furyFrame.furyFillBar:Hide()
        furyFrame._snapped = true

        -- EllesmereUI resizes its bar on every profile switch, option edit and
        -- unlock-mode drag. Without this our px/fury would keep the width it
        -- had when we first snapped. Hooked once per target frame.
        if furyFrame._sizeHookOn ~= sb then
            furyFrame._sizeHookOn = sb
            sb:HookScript("OnSizeChanged", function()
                if furyFrame and furyFrame._snapped then ApplyFuryLayout() end
            end)
        end
    else
        -- Standalone: chain head follows our own fury fill again.
        for i, bar in ipairs(chain) do
            if bar:GetParent() ~= furyFrame then
                bar:SetParent(furyFrame)
            end
            bar:SetFrameStrata(furyFrame:GetFrameStrata())
            bar:SetFrameLevel(furyFrame._chainLevels[i])
        end
        head:ClearAllPoints()
        head:SetPoint("LEFT", furyFrame.furyFillBar:GetStatusBarTexture(), "RIGHT", 0, 0)
        furyFrame.furyFillBar:Show()
        furyFrame._snapped = false
    end
end

-- Show/hide and alpha have to reach the chain explicitly: while snapped the
-- four bars are children of the external StatusBar, so furyFrame:SetShown /
-- SetAlpha no longer touch them and they would stay frozen on screen after the
-- module is disabled or the player swaps spec.
function Snap.PropagateShown(shown)
    if not (furyFrame and furyFrame._snapped) then return end
    furyFrame.consumeBar:SetShown(shown)
    furyFrame.flatBar:SetShown(shown)
    furyFrame.soulFuryBar:SetShown(shown)
    if not shown then furyFrame.soulFuryPreview:Hide() end
end

function Snap.PropagateAlpha(a)
    if not (furyFrame and furyFrame._snapped) then return end
    furyFrame.consumeBar:SetAlpha(a)
    furyFrame.flatBar:SetAlpha(a)
    furyFrame.soulFuryBar:SetAlpha(a)
    furyFrame.soulFuryPreview:SetAlpha(a)
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

    -- In snap mode the whole prediction chain must speak the external bar's
    -- pixel scale, not ours: a px/fury derived from our own width would make
    -- every segment the wrong length even once the chain head is glued in the
    -- right place.
    local snapW, snapMax = Snap.Geometry()
    local pxPerFury = (snapW and snapMax and snapMax > 0)
        and (snapW / snapMax)
        or  (W / furyMax)

    furyFrame._pxPerFury = pxPerFury
    furyFrame._height    = H

    Snap.ApplyAnchor()

    local fillBar = furyFrame.furyFillBar
    fillBar:SetSize(W, H)
    fillBar:SetMinMaxValues(0, furyMax)

    furyFrame.consumeBar:SetSize((CONSUME_BASE_FURY + CONSUME_CELESTIAL_MOD) * pxPerFury, H)
    furyFrame.flatBar:SetSize(REAP_CAST_FURY * pxPerFury, H)
    furyFrame.soulFuryPreview:SetSize((REAP_CAP_MOC - REAP_CAP_BASE) * REAP_SOUL_FURY * pxPerFury, H)
    furyFrame.soulFuryPreview:SetMinMaxValues(REAP_CAP_BASE, REAP_CAP_MOC)

    -- 100-fury tick.
    --
    -- The offset is computed in the pixel scale we just chose, so it has to be
    -- measured from the origin that scale belongs to. While snapped, px/fury
    -- comes from the external bar but the tick was still anchored to our own
    -- frame's TOPLEFT -- two different origins and two different widths, so the
    -- mark landed nowhere near 100 fury.
    local tickX   = VOID_RAY_COST * pxPerFury
    local tickRef = furyFrame
    if furyFrame._snapped then
        local _, sb = Snap.Resolve(Snap.Name())
        if sb then tickRef = sb end
    end

    furyFrame.tick:ClearAllPoints()
    furyFrame.tick:SetPoint("TOP",    tickRef, "TOPLEFT",    tickX, 0)
    furyFrame.tick:SetPoint("BOTTOM", tickRef, "BOTTOMLEFT", tickX, 0)

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
    furyFrame.consumeBar:SetStatusBarColor(C("furyConsume"))
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
-- Bar texture
-- ============================================================
local function GetBarTexturePath()
    local db   = GetDB()
    local L    = db and db.layout
    local name = L and L.barTexture
    if not name then return BAR_TEXTURE end
    return SP.GetStatusBarPath(name) or BAR_TEXTURE
end

local function ApplyBarTexture()
    local path = GetBarTexturePath()
    if frame then
        if frame.growthBar   then frame.growthBar:SetStatusBarTexture(path) end
        if frame.sfBar       then frame.sfBar:SetStatusBarTexture(path) end
        if frame.mocPreview  then frame.mocPreview:SetStatusBarTexture(path) end
        if frame.mocRail     then frame.mocRail:SetStatusBarTexture(path) end
    end
    if furyFrame then
        if furyFrame.furyFillBar     then furyFrame.furyFillBar:SetStatusBarTexture(path) end
        if furyFrame.consumeBar      then furyFrame.consumeBar:SetStatusBarTexture(path) end
        if furyFrame.flatBar         then furyFrame.flatBar:SetStatusBarTexture(path) end
        if furyFrame.soulFuryBar     then furyFrame.soulFuryBar:SetStatusBarTexture(path) end
        if furyFrame.soulFuryPreview then furyFrame.soulFuryPreview:SetStatusBarTexture(path) end
    end
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
    local furyShown = ShowFuryBarPref()
    furyFrame:SetShown(furyShown)
    Snap.PropagateShown(furyShown)
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
-- 10 Hz meter refresh.
--
-- A fixed-rate anim ticker rather than an OnUpdate with an accumulator: the C
-- engine sleeps between fires, so this costs ZERO Lua at frame rate. The old
-- version paid a dispatch 60 times a second to throw away 5 of every 6 calls,
-- and it ran for the entire session on any Devourer DH -- in a city, out of
-- combat, with nothing happening.
local function EnsurePollFrame()
    if pollFrame then return end
    pollFrame = SP.Tick.NewAnimTicker(function()
        UpdateMeter()
        return true   -- keep ticking until Stop() is called
    end, 0.1)
end

-- ============================================================
-- Activate / Deactivate
--
-- Colon methods on the module table rather than file-scope locals: this is the
-- SP.ModuleMixin contract (Core/Module.lua), and it also gives back three of
-- the four remaining local slots in this chunk.
-- NOT named Enable/Disable -- those are AceAddon's own mixin methods and a
-- module field with either name silently shadows the addon lifecycle.
-- ============================================================
function ReapPredict:Activate()
    -- Only registers the eight raw unit events once we know this character is
    -- actually a Devourer DH with the module turned on.
    ReapPredict:EnsureUnitEvents()

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
    ApplyBarTexture()   -- restore saved texture (no-op when using default Solid)

    EnsurePollFrame()
    pollFrame.Start()
    UpdateMeter()

    -- CDM width sync: install hook and snap immediately if enabled
    EnsureCDMSyncHook()
    local _syncDB = GetDB(); local _syncL = _syncDB and _syncDB.layout
    if _syncL and _syncL.syncToCDM then SyncToCDMNow() end

    -- Fading: activate or deactivate based on current DB setting
    if FadeRefresh then FadeRefresh() end
end

function ReapPredict:Deactivate()
    if FadeDeactivate then FadeDeactivate() end   -- restore alpha before hiding
    if pollFrame      then pollFrame.Stop()      end
    if frame          then frame:Hide()          end
    if furyFrame then furyFrame:Hide(); Snap.PropagateShown(false) end

    -- Drop the raw unit events too. Hiding the frames stopped the drawing but
    -- left UNIT_AURA and UNIT_POWER_FREQUENT dispatching for the whole session.
    if ReapPredict._eventsFrame then
        ReapPredict._eventsFrame:UnregisterAllEvents()
    end
end

-- Kept instead of ModuleMixin:Refresh, which only knows about db.enabled: this
-- one also re-reads the spec and talent caches and gates on Devourer DH.
--
-- A DOT function on purpose. The GUI's enable toggle calls mod.Refresh() with
-- no arguments, while ModuleMixin calls self:Refresh(); ignoring the argument
-- entirely is the only shape that is correct on both paths.
function ReapPredict.Refresh()
    -- The sweep may have Ace-disabled this module at login, in which case
    -- OnEnable -- and therefore LoadSizesFromDB() -- never ran, leaving the
    -- pixel constants nil. Enabling routes back here through the mixin once
    -- they exist. Mirrors ModuleMixin:Refresh; needed because this is a DOT
    -- override that the mixin's re-Enable branch cannot reach.
    local _db = GetDB()
    if _db and _db.enabled and ReapPredict.IsEnabled and not ReapPredict:IsEnabled() then
        ReapPredict:Enable()
        return
    end
    local db = GetDB()
    if not (db and db.enabled) then
        -- These three used to be registered once in OnEnable and never
        -- dropped. They exist only to notice that this character has BECOME a
        -- Devourer DH, which is meaningless while the module is switched off.
        ReapPredict:UnregisterEvent("PLAYER_ENTERING_WORLD")
        ReapPredict:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        ReapPredict:UnregisterEvent("TRAIT_CONFIG_UPDATED")
        ReapPredict:Deactivate()
        return
    end

    -- Deliberately NOT in Activate(): Activate only runs for a Devourer DH, so
    -- registering there would mean a DH sitting in another spec never hears
    -- about the spec change that should switch the meter on.
    ReapPredict:RegisterEvent("PLAYER_ENTERING_WORLD",         "OnPlayerEnteringWorld")
    ReapPredict:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnRefreshEvent")
    ReapPredict:RegisterEvent("TRAIT_CONFIG_UPDATED",          "OnRefreshEvent")

    RefreshSpecCache()
    RefreshScythesEmbrace()
    RefreshCelestialEchoes()
    if IsDDH() then ReapPredict:Activate() else ReapPredict:Deactivate() end
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
-- Fading system
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
    if furyFrame then furyFrame:SetAlpha(a); Snap.PropagateAlpha(a) end
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
-- Blizzard Settings panel
-- ============================================================
local DumpState
local DumpCDMViewer

-- ============================================================
-- Module lifecycle
--
-- OnEnable is kept rather than taken from SP.ModuleMixin because
-- LoadSizesFromDB() has to run before anything reads CONTAINER_W / the colour
-- table, and the CDM setup prompt is scheduled from here. OnDisable does come
-- from the mixin: UnregisterAllEvents + Deactivate, which is exactly what the
-- hand-written one did.
-- ============================================================
function ReapPredict:OnEnable()
    LoadSizesFromDB()

    -- Refresh registers/unregisters the three "did this character become a
    -- Devourer DH?" events itself, so they are gone while the module is off.
    ReapPredict.Refresh()

    if C_Timer and C_Timer.After then
        C_Timer.After(3.0, CheckCDMSetup)
    end
end

-- Raw unit event frame (AceEvent doesn't support RegisterUnitEvent).
--
-- Built lazily from Activate(), NOT from OnEnable: these are eight unit events
-- including UNIT_AURA and UNIT_POWER_FREQUENT -- the noisiest pair in the game
-- -- and registering them in OnEnable meant every player paid the dispatch
-- regardless of class and regardless of db.enabled, with nothing ever
-- unregistering them (OnDisable's UnregisterAllEvents is the AceEvent mixin and
-- does not reach a raw frame).
--
-- Activate() only runs for a Devourer Demon Hunter with the module on, so on
-- any other character these are never registered at all.
function ReapPredict:EnsureUnitEvents()
    if ReapPredict._eventsFrame then
        -- Re-arm after a Deactivate() unregistered them. Unconditional:
        -- RegisterUnitEvent is idempotent, and probing a single event would
        -- silently skip the other seven if anything ever unregisters one alone.
        local e = ReapPredict._eventsFrame
        do
            e:RegisterUnitEvent("UNIT_SPELLCAST_START",          "player")
            e:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED",      "player")
            e:RegisterUnitEvent("UNIT_SPELLCAST_FAILED",         "player")
            e:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED",    "player")
            e:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP",   "player")
            e:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START",  "player")
            e:RegisterUnitEvent("UNIT_AURA",                     "player")
            e:RegisterUnitEvent("UNIT_POWER_FREQUENT",           "player")
        end
        return
    end

    do
        local events = CreateFrame("Frame")
        events:RegisterUnitEvent("UNIT_SPELLCAST_START",          "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED",     "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED",        "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED",   "player")
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

            if event == "UNIT_SPELLCAST_START" then
                local spellID = arg2
                if spellID == CONSUME_SPELLID then
                    consumeGain = celestialEchoesKnown
                        and (CONSUME_BASE_FURY + CONSUME_CELESTIAL_MOD)
                        or  CONSUME_BASE_FURY
                    if furyFrame and furyFrame:IsShown() then
                        ApplyToBar(furyFrame.consumeBar, consumeGain)
                    end
                    dbg("Consume START — consumeGain=%d (celestialEchoes=%s)",
                        consumeGain, tostring(celestialEchoesKnown))
                end
                return
            end

            if event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
                local spellID = arg2
                if spellID == CONSUME_SPELLID and consumeGain ~= 0 then
                    consumeGain = 0
                    if furyFrame and furyFrame:IsShown() then
                        ApplyToBar(furyFrame.consumeBar, 0)
                    end
                    dbg("Consume %s — prediction cleared", event)
                end
                return
            end

            if event == "UNIT_SPELLCAST_SUCCEEDED" then
                local spellID = arg2
                if spellID == CONSUME_SPELLID then
                    -- Fury will arrive via UNIT_POWER_FREQUENT; clear prediction now.
                    consumeGain = 0
                    if furyFrame and furyFrame:IsShown() then
                        ApplyToBar(furyFrame.consumeBar, 0)
                    end
                end
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
            -- The UNIT_AURA branch that used to live here dumped the event's
            -- payload: counts of addedAuras and removedAuraInstanceIDs, each
            -- aura's spellId and name, and isFullUpdate. Patch 12.1 made that
            -- payload FULLY secret, so every one of those reads now throws --
            -- the same error that hit BloodlustAlert about 1400 times in one
            -- fight, waiting behind `/spack` debug rather than firing for
            -- everyone. It is removed rather than guarded: its only purpose was
            -- inspecting values the client no longer hands out, so there is
            -- nothing left for it to print.
            end
        end)
        ReapPredict._eventsFrame = events
    end
end

function ReapPredict:OnPlayerEnteringWorld()
    ReapPredict.Refresh()
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
        -- FadeRefresh() inside Activate() fires too early.
        C_Timer.After(0.5, function()
            if FadeRefresh then FadeRefresh() end
        end)
    end
end

function ReapPredict:OnRefreshEvent()
    ReapPredict.Refresh()
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
    local cdID = FindCDMCooldownIDForSpells({ 1238495, 1238488 })
    print(("  MoC cdID=%s; cdmBackup=%s"):format(
        tostring(cdID),
        db and (db.cdmBackup and "saved" or "missing") or "no DB"))
end

-- ============================================================
-- Public API
--
-- ReapPredict.Refresh is defined further up, next to Activate/Deactivate --
-- the GUI still calls it as mod.Refresh().
-- ============================================================

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
ReapPredict.ApplyBarTexture    = ApplyBarTexture
ReapPredict.ApplyLock          = ApplyLock
ReapPredict.ApplyFuryLock      = ApplyFuryLock
ReapPredict.ApplySavedPosition = ApplySavedPosition

-- DumpState prints, among other things, whether the aura reads come back as
-- numbers or as SECRET. That is the one fact that decides whether this module
-- still has its stack refinements on a given patch -- and it was a file-local,
-- so the only way to see it was to edit the file. Exposed:
--   /run SuspicionsPack.ReapPredict.DumpState()
ReapPredict.DumpState = DumpState
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

-- ============================================================
-- Ellesmere width picker
-- Click-catcher: when active the user clicks any on-screen bar;
-- GetMouseFoci returns all frames at that point including the one
-- under the catcher, so we pick the widest non-catcher frame.
-- ============================================================
local erbPickFrame    = nil
local erbPickCallback = nil

local function ExitERBPick()
    if erbPickFrame then
        erbPickFrame:SetScript("OnMouseDown", nil)
        erbPickFrame:SetScript("OnKeyDown",   nil)
        erbPickFrame:Hide()
        erbPickFrame = nil
    end
    erbPickCallback = nil
end

local function StartERBPick(callback)
    ExitERBPick()
    erbPickCallback = callback

    erbPickFrame = CreateFrame("Frame", "SP_ERBWidthPicker", UIParent)
    erbPickFrame:SetAllPoints(UIParent)
    erbPickFrame:SetFrameStrata("TOOLTIP")
    erbPickFrame:EnableMouse(true)
    erbPickFrame:SetPropagateKeyboardInput(true)

    erbPickFrame:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            ExitERBPick()
            if callback then callback(nil) end
        end
    end)

    erbPickFrame:SetScript("OnMouseDown", function(self, btn)
        if btn == "RightButton" then
            ExitERBPick()
            if callback then callback(nil) end
            return
        end
        -- Collect all frames at cursor; skip our own catcher.
        -- We report both the width and the frame's global NAME: snapping needs
        -- a name it can re-resolve every session, since frame handles don't
        -- survive a reload and the target addon may load after us.
        local foci = GetMouseFoci and { GetMouseFoci() } or {}
        local bestW, bestName = 0, nil
        for _, f in ipairs(foci) do
            if f and f ~= self and f.GetWidth then
                local w = math.floor(f:GetWidth() + 0.5)
                if w > bestW and w < 3000 then
                    bestW = w
                    -- Walk up until we find something with a global name: the
                    -- clickable region is often an unnamed inner StatusBar.
                    local node, name = f, nil
                    for _ = 1, 4 do
                        if not node or not node.GetName then break end
                        local n = node:GetName()
                        if n and _G[n] == node then name = n break end
                        node = node.GetParent and node:GetParent() or nil
                    end
                    bestName = name
                end
            end
        end
        ExitERBPick()
        if callback then callback(bestW > 0 and bestW or nil, bestName) end
    end)

    erbPickFrame:Show()
end

-- Public: start the pick mode. onDone(width) called with the chosen pixel
-- width, or nil if cancelled. Automatically applies to both bars + DB.
function ReapPredict.StartERBWidthPick(onDone)
    StartERBPick(function(w)
        if w and w > 0 then
            local db = GetDB()
            local L  = db and db.layout
            if L then
                CONTAINER_W = w
                L.width     = w
                L.furyWidth = w
                ApplySize()
                ApplyFurySize()
            end
        end
        if onDone then onDone(w) end
    end)
end

-- Candidate bars to snap to, for the GUI dropdown.
--
-- Deliberately NOT a click-picker: EllesmereUI calls EnableMouse(false) on its
-- resource bars on purpose (a mouse-enabled bar would steal mouseover focus),
-- and GetMouseFoci only ever returns mouse-enabled regions -- so a picker can
-- never select them. It would silently land on WorldFrame instead.
function ReapPredict.GetSnapBarChoices()
    local out = {}
    local known = {
        { key = "ERB_PrimaryBar",   label = "EllesmereUI \226\128\148 power bar (fury)" },
        { key = "ERB_SecondaryBar", label = "EllesmereUI \226\128\148 class resource" },
        { key = "ERB_HealthBar",    label = "EllesmereUI \226\128\148 health bar" },
    }
    for _, e in ipairs(known) do
        if Snap.Resolve(e.key) then
            out[#out + 1] = { key = e.key, label = e.label }
        end
    end
    return out
end

-- Public: set the snap target by name. Rejects anything that doesn't resolve to
-- a usable status bar, so the retry loop can never be armed against a target
-- that will never appear. Returns true on success.
function ReapPredict.SetSnapBar(name)
    if not Snap.Resolve(name) then return false end
    local db = GetDB()
    local L  = db and db.layout
    if not L then return false end
    L.snapBarName = name
    ApplyFurySize()
    return true
end

-- Public: the resolved snap target, for the GUI to show what it is following.
function ReapPredict.GetSnapStatus()
    local name  = Snap.Name()
    local found = Snap.Resolve(name) ~= nil
    return Snap.Wanted(), name, found
end
