-- SuspicionsPack - Cursor.lua
-- Cercle curseur qui suit la souris.

local SP = SuspicionsPack

local Cursor = SP:NewSPModule("Cursor", "cursor")
SP.Cursor = Cursor

-- ============================================================
-- Constants
-- ============================================================
local MEDIA = "Interface\\AddOns\\SuspicionsPack\\Media\\CursorCircles\\"

Cursor.Textures = {
    ["Thin"]   = MEDIA .. "nauraThin.png",
    ["Medium"] = MEDIA .. "nauraMedium.png",
    ["Thick"]  = MEDIA .. "nauraThick.png",
    ["Aura 1"] = MEDIA .. "Aura73.tga",
    ["Aura 2"] = MEDIA .. "Aura103.tga",
    ["Circle"] = MEDIA .. "Circle.tga",
}
Cursor.TextureOrder = { "Thin", "Medium", "Thick", "Aura 1", "Aura 2", "Circle" }

-- THE TRAIL NEEDS A FILLED SHAPE, NOT A RING.
--
-- The first version reused the cursor's own ring art, and it was effectively
-- invisible: a thin outline, shrunk as it fades, at half opacity, in additive
-- blend, leaves almost nothing to see. A trail reads as a trail when each
-- sample is a soft dot -- which is what NaowhQOL defaults to, and why theirs
-- looks like a trail and the first attempt here did not.
Cursor.TrailTextures = {
    ["Dot"]    = MEDIA .. "TrailDot.png",
    ["Circle"] = MEDIA .. "Circle.tga",
    ["Ring"]   = MEDIA .. "nauraThin.png",
}
Cursor.TrailOrder = { "Dot", "Circle", "Ring" }

-- ============================================================
-- DB helpers
-- ============================================================
local function GetDB()
    return SP.GetDB().cursor
end

-- ============================================================
-- Internal state
-- ============================================================
local mainFrame  = nil
local clickFrame = nil   -- second circle, visible only while mouse button held ≥ 150 ms

-- Declared up here, not next to PreviewClickCircle: Deactivate cancels it, and
-- a closure cannot see a `local` declared further down the file.
local _previewClickTimer = nil

-- ============================================================
-- Color helpers
-- ============================================================
local function GetCursorColor()
    local db  = GetDB()
    local src = db.colorSource or "theme"
    local T   = SP.Theme

    if src == "theme" then
        return T.accent[1], T.accent[2], T.accent[3]
    end

    if src == "class" then
        local _, cls = UnitClass("player")
        local c = RAID_CLASS_COLORS and cls and RAID_CLASS_COLORS[cls]
        if c then return c.r, c.g, c.b end
    end

    -- "custom"
    local cc = db.cursorColor or { 1, 1, 1 }
    return cc[1], cc[2], cc[3]
end

local function GetClickColor()
    local db  = GetDB()
    local src = db.clickColorSource or "theme"
    local T   = SP.Theme

    if src == "theme" then
        return T.accent[1], T.accent[2], T.accent[3]
    end

    if src == "class" then
        local _, cls = UnitClass("player")
        local c = RAID_CLASS_COLORS and cls and RAID_CLASS_COLORS[cls]
        if c then return c.r, c.g, c.b end
    end

    local cc = db.clickColor or { 1, 1, 1 }
    return cc[1], cc[2], cc[3]
end

-- ============================================================
-- Frame creation
-- ============================================================
-- ============================================================
-- Opacity, in and out of combat
--
-- One multiplier over the whole cursor display -- ring, click ring and trail --
-- rather than three separate alphas, so the three cannot drift apart.
--
-- BEING IN AN INSTANCE COUNTS AS COMBAT. Copied deliberately from NaowhQOL:
-- inside a dungeon or a raid you are between pulls far more often than you are
-- genuinely idle, and a cursor that brightens and dims on every regen event is
-- worse than one that simply stays put for the whole run.
-- ============================================================
local inCombat, inInstance = false, false

local function RefreshCombatState()
    inCombat = (InCombatLockdown() or UnitAffectingCombat("player")) and true or false
    local isInst, kind = IsInInstance()
    inInstance = (isInst and (kind == "party" or kind == "raid"
                              or kind == "pvp" or kind == "arena")) and true or false
end
Cursor.RefreshCombatState = RefreshCombatState

-- `v == nil` rather than `not v` for the sake of saying what is meant, NOT
-- because 0 needs protecting: in Lua only nil and false are false, so 0 passes
-- through `or` untouched. (Written down because this file previously claimed
-- the opposite three separate times.)
function Cursor.CurrentOpacity()
    local db = GetDB()
    local v
    if inCombat or inInstance then v = db.opacityInCombat else v = db.opacityOutOfCombat end
    if v == nil then v = 100 end
    v = v / 100
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    return v
end

-- ============================================================
-- Trail
--
-- Copies of the ring dropped where the cursor has been, fading out behind it.
--
-- Three things here are not obvious and all three came from reading a working
-- implementation (NaowhQOL's MouseRingDisplay) after a first attempt got them
-- wrong:
--
--   * THE FADE IS ON A CLOCK, not on the segment's position in the ring. A
--     position-based fade only advances when the cursor moves, so stopping
--     leaves the whole trail painted on screen until you move again. Each
--     sample carries the time it was taken and expires on its own.
--   * SAMPLES ARE SPACED BY DISTANCE. Recording on every pixel of movement
--     packs the entire ring into a few pixels during a slow drag, and the trail
--     reads as one smeared blob. A new sample is only taken once the cursor has
--     travelled a fraction of the segment size.
--   * ADD BLEND. Flat circles stacked on top of each other look like stacked
--     circles; additive ones read as a glow, which is the whole point.
--
-- The pool is allocated once at TRAIL_MAX and the length setting only decides
-- how many of those are in play. A texture, like a frame, is never reclaimable,
-- so growing the pool from a slider would leak on every drag of it.
-- ============================================================
local TRAIL_MAX = 60

-- 40 Hz. Above that we are moving textures nobody can tell apart, and the
-- redraw is the expensive half of this module.
--
-- SAFE ONLY BECAUSE SAMPLING WALKS THE PATH. Capping the tick rate on a
-- one-sample-per-tick trail is what makes it thin out -- it is exactly the bug
-- this module had. Now a slower tick just means a longer segment to step along,
-- so the same movement leaves the same trail whether we look 40 times a second
-- or 400. (NaowhQOL caps at the same rate but does not interpolate, which is
-- why theirs also thins out when the frame rate drops -- less visibly, because
-- the cap already held it low.)
local TRAIL_HZ = 1 / 40
local trailClock = 0

-- Half a texel, for the 128px source. Trimmed off each edge because CLAMP
-- smears the outermost row of pixels outwards when the texture is scaled, which
-- leaves a faint square halo around what is supposed to be a round dot.
local TRAIL_TEXEL = 0.5 / 128

local trailFrame
local trailPts   = {}
local trailHead  = 0
local trailLastX, trailLastY = 0, 0
local trailActive = 0

local function TrailLength(db)
    local n = db.trailLength
    if n == nil then n = 20 end
    n = math.floor(n)
    if n < 2 then n = 2 elseif n > TRAIL_MAX then n = TRAIL_MAX end
    return n
end

local function EnsureTrail(db)
    if trailFrame then return end

    trailFrame = CreateFrame("Frame", "SP_CursorTrail", UIParent)
    trailFrame:SetPoint("BOTTOMLEFT")
    trailFrame:SetSize(1, 1)
    trailFrame:SetFrameStrata("MEDIUM")
    -- Under the cursor circle (200) and the click ring (199).
    trailFrame:SetFrameLevel(198)
    trailFrame:EnableMouse(false)
    trailFrame:Hide()

    for i = 1, TRAIL_MAX do
        local t = trailFrame:CreateTexture(nil, "BACKGROUND")
        t:SetBlendMode("ADD")
        t:SetTexCoord(TRAIL_TEXEL, 1 - TRAIL_TEXEL, TRAIL_TEXEL, 1 - TRAIL_TEXEL)
        -- Filtering is not decoration here. A 64px source drawn at 24 and
        -- shrinking to nothing is resampled every single frame; on the default
        -- filter that reads as a hard, crunchy blob instead of a soft one.
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        t:Hide()
        trailPts[i] = { tex = t, x = 0, y = 0, time = 0, active = false }
    end
end

-- Re-applied whenever the shape setting moves, not captured once at creation:
-- the pool outlives every settings change.
local trailTexApplied
local function ApplyTrailTexture(db)
    local shape = db.trailShape or "Dot"
    if shape == trailTexApplied then return end
    trailTexApplied = shape
    local path = Cursor.TrailTextures[shape] or Cursor.TrailTextures["Dot"]
    for i = 1, #trailPts do
        -- CLAMP twice then TRILINEAR: the filter argument only exists on this
        -- call, so re-setting the texture without it silently drops back to the
        -- default filter and the dot goes crunchy again.
        trailPts[i].tex:SetTexture(path, "CLAMP", "CLAMP", "TRILINEAR")
        trailPts[i].tex:SetTexCoord(TRAIL_TEXEL, 1 - TRAIL_TEXEL, TRAIL_TEXEL, 1 - TRAIL_TEXEL)
    end
end

local function ClearTrail()
    for i = 1, #trailPts do
        trailPts[i].active = false
        trailPts[i].tex:Hide()
    end
    trailHead, trailActive = 0, 0
    if trailFrame then trailFrame:Hide() end
end
Cursor.ClearTrail = ClearTrail

-- Pushes the current opacity onto every piece. Called from the tick and from
-- the combat events, so a regen change lands immediately rather than waiting
-- for the next mouse move.
local function ApplyOpacity()
    local a = Cursor.CurrentOpacity()
    if mainFrame  then mainFrame:SetAlpha(a)  end
    if clickFrame then clickFrame:SetAlpha(a) end
    if trailFrame then trailFrame:SetAlpha(a) end
end
Cursor.ApplyOpacity = ApplyOpacity

-- Called on EVERY tick, not only when the cursor moves: expiring the old
-- samples is half the job.
local function UpdateTrail(db, elapsed)
    if not db.trail then
        if trailActive > 0 or (trailFrame and trailFrame:IsShown()) then ClearTrail() end
        return
    end

    -- No `elapsed` means a caller that wants a pass now: the debug command and
    -- the test harness both drive this directly.
    trailClock = trailClock + (elapsed or TRAIL_HZ)
    if trailClock < TRAIL_HZ then return end
    trailClock = 0

    EnsureTrail(db)
    ApplyTrailTexture(db)
    trailFrame:Show()

    local n = TrailLength(db)
    -- Absolute pixels, not a share of the ring: the two are independent, and a
    -- percentage of something the user also tunes is impossible to reason about.
    local size = db.trailSize
    if size == nil then size = 24 end
    local now   = GetTime()
    local scale = UIParent:GetEffectiveScale()

    local x, y = GetCursorPosition()
    x, y = x / scale, y / scale

    -- SAMPLED ALONG THE PATH, NOT ONCE PER TICK.
    --
    -- One sample per frame ties the trail to the frame rate: at 30 fps the
    -- cursor covers several spacings between two ticks, so the trail thins out
    -- to a few scattered dots exactly when the game is already struggling --
    -- alt-tab and it visibly falls apart. Stepping along the segment makes what
    -- you see a function of the path and the clock, which is what it should
    -- have been from the start.
    -- SPACING IS A SETTING, NOT A CONSTANT.
    --
    -- Walking the path fixed the frame-rate dependence but pinned the density at
    -- its maximum: a dot every tenth of the dot's own width, all the way along,
    -- however fast you flick. NaowhQOL drops samples when the cursor moves fast
    -- -- an accident of sampling once per tick -- and the result reads lighter.
    -- Rather than reproduce the accident, the gap between dots is now the
    -- player's to set, and it stays even at any frame rate.
    local spacing = size * ((db.trailSpacing or 50) / 100)
    if spacing < 2 then spacing = 2 end

    local dx, dy = x - trailLastX, y - trailLastY
    local dist   = math.sqrt(dx * dx + dy * dy)

    if dist >= spacing then
        local steps = math.floor(dist / spacing)

        -- A JUMP IS NOT A PATH. Coming back from alt-tab, a screen-edge warp or
        -- a UI-scale change moves the cursor without it having travelled, and
        -- filling that in paints a streak across the screen.
        --
        -- Measured against the SCREEN, not against the trail's own length: with
        -- spacing under the player's control a full trail can be 40px or 900px
        -- long, and a threshold derived from it would call an ordinary flick a
        -- teleport at one setting and miss a real one at another.
        local warp = (UIParent:GetHeight() or 800) * 0.5
        if dist > warp then
            steps = 1
            trailLastX, trailLastY = x, y
            trailHead = (trailHead % n) + 1
            local pt = trailPts[trailHead]
            if not pt.active then trailActive = trailActive + 1 end
            pt.x, pt.y, pt.time, pt.active =
                math.floor(x + 0.5), math.floor(y + 0.5), now, true
        else
            -- More steps than slots would just overwrite the ring several times
            -- over for nothing; the last n are the only ones that survive.
            if steps > n then steps = n end
            local ux, uy = dx / dist, dy / dist
            for i = 1, steps do
                -- Rounded to whole pixels so a dot is not drawn straddling
                -- two of them, which reads as a blurred smear. Rounded HERE and
                -- not on the cursor position: quantising the source would
                -- quantise the spacing too and the trail would clump.
                local px = math.floor(trailLastX + ux * spacing * i + 0.5)
                local py = math.floor(trailLastY + uy * spacing * i + 0.5)
                trailHead = (trailHead % n) + 1
                local pt = trailPts[trailHead]
                if not pt.active then trailActive = trailActive + 1 end
                -- Timestamps spread across the step so they expire in the order
                -- they were laid down rather than all at once.
                pt.x, pt.y, pt.active = px, py, true
                pt.time = now - (steps - i) * 0.008
            end
            -- The remainder stays for the next tick, which is what keeps the
            -- spacing even instead of resetting the phase every frame.
            -- Snapped forward to the cursor when the ring was saturated,
            -- otherwise the leftover distance would be replayed next tick.
            if steps * spacing >= dist - spacing then
                trailLastX = trailLastX + ux * spacing * steps
                trailLastY = trailLastY + uy * spacing * steps
            else
                trailLastX, trailLastY = x, y
            end
        end
    end

    if trailActive == 0 then return end

    -- The nil test on the duration is load-bearing for a different reason than
    -- the usual one: a stored 0 would divide by zero below, so it is clamped to
    -- a floor rather than merely defaulted. The alpha needs no such care --
    -- 0 is true in Lua and survives an `or` perfectly well.
    local a = db.trailAlpha
    if a == nil then a = 50 end
    a = a / 100
    local dur = db.trailDuration
    if dur == nil or dur < 0.1 then dur = 0.6 end

    local r, g, b = GetCursorColor()

    for i = 1, TRAIL_MAX do
        local pt = trailPts[i]
        if pt.active then
            local fade = 1 - (now - pt.time) / dur
            if fade <= 0 then
                pt.active = false
                pt.tex:Hide()
                trailActive = trailActive - 1
            else
                pt.tex:ClearAllPoints()
                pt.tex:SetPoint("CENTER", trailFrame, "BOTTOMLEFT", pt.x, pt.y)
                pt.tex:SetSize(size * fade, size * fade)
                pt.tex:SetVertexColor(r, g, b, a * fade)
                pt.tex:Show()
            end
        end
    end
end

-- Exposed so the ring and the fade are testable without an OnUpdate. The game
-- path still goes through the handler below; nothing else calls this.
Cursor.UpdateTrailForTest = UpdateTrail

-- Reports what the trail is actually doing, because the offline suite can prove
-- the ring maths and prove nothing about whether a pixel reaches the screen.
-- Every value below is one that, if wrong, makes the trail invisible while
-- everything else looks correct.
-- Plants a burst of samples around the cursor so the state is OBSERVABLE rather
-- than caught by luck. Reading the live numbers a second after you stopped
-- moving reports zero actives and tells you nothing: the samples expired, which
-- is correct behaviour and looks identical to never sampling at all.
function Cursor.DebugTrail()
    local db = GetDB()
    local function say(k, v) print(("  %-16s %s"):format(k, tostring(v))) end

    print("|cffE51039SuspicionsPack|r cursor trail:")
    say("module enabled", db.enabled)
    say("trail", db.trail)
    say("driver shown", mainFrame and mainFrame:IsShown())   -- the OnUpdate lives here
    say("frame", trailFrame and "created" or "NEVER CREATED")
    if not trailFrame then return end
    say("frame shown", trailFrame:IsShown())
    say("frame alpha", trailFrame:GetAlpha())
    say("combat/inst", tostring(inCombat) .. " / " .. tostring(inInstance))
    say("opacity now", Cursor.CurrentOpacity())
    say("strata/level", trailFrame:GetFrameStrata() .. " / " .. trailFrame:GetFrameLevel())
    say("pool", #trailPts)
    say("active", trailActive)
    say("length", TrailLength(db))
    say("shape", db.trailShape)
    say("size", db.trailSize)
    say("alpha", db.trailAlpha)
    say("duration", db.trailDuration)

    local shown, sample = 0, nil
    for i = 1, #trailPts do
        if trailPts[i].tex:IsShown() then
            shown = shown + 1
            sample = sample or trailPts[i]
        end
    end
    say("textures shown", shown)
    if sample then
        local w = sample.tex:GetWidth()
        say("first at", ("%.0f, %.0f  size %.1f"):format(sample.x, sample.y, w or -1))
        say("texture file", sample.tex:GetTexture())
    end
    local x, y = GetCursorPosition()
    say("cursor raw", ("%.0f, %.0f  scale %.2f"):format(x, y, UIParent:GetEffectiveScale()))

    -- Force a fan of samples so something is definitely on screen, then report
    -- what came of it. If this shows textures and you still see nothing, the
    -- fault is visual -- texture, blend or colour -- not the sampling.
    if not (db.enabled and db.trail and trailFrame) then return end
    local sc = UIParent:GetEffectiveScale()
    local cx, cy = x / sc, y / sc
    for i = 1, 10 do
        trailLastX, trailLastY = -99999, -99999   -- force the distance test
        UpdateTrail(db)
        trailPts[trailHead].x = cx + i * 18
        trailPts[trailHead].y = cy
    end
    UpdateTrail(db)

    local n2 = 0
    for i = 1, #trailPts do if trailPts[i].tex:IsShown() then n2 = n2 + 1 end end
    print(("  |cff8AE234forced 10 samples -> %d textures shown, active %d|r"):format(n2, trailActive))
    local t = trailPts[trailHead].tex
    print(("  |cff8AE234first: %s  %.0fx%.0f  rgba %.2f %.2f %.2f %.2f|r"):format(
        tostring(t:GetTexture()), t:GetWidth() or -1, t:GetHeight() or -1,
        select(1, t:GetVertexColor()), select(2, t:GetVertexColor()),
        select(3, t:GetVertexColor()), select(4, t:GetVertexColor())))
end

local function CreateCursorFrame()
    if mainFrame then return end

    local db = GetDB()
    local sz = db.size or 50

    local texPath = Cursor.Textures[db.texture or "Thick"] or Cursor.Textures["Thick"]

    local f = CreateFrame("Frame", "SP_CursorCircle", UIParent)
    f:SetSize(sz, sz)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(200)
    f:EnableMouse(false)   -- must never intercept mouse clicks
    f:SetClampedToScreen(false)
    f:Hide()

    f.texture = f:CreateTexture(nil, "BACKGROUND")
    f.texture:SetAllPoints()
    f.texture:SetTexture(texPath)
    local r, g, b = GetCursorColor()
    f.texture:SetVertexColor(r, g, b, 0.9)

    local dotTex = f:CreateTexture(nil, "OVERLAY")
    dotTex:SetTexture(MEDIA .. "Click.tga")
    dotTex:SetPoint("CENTER", f, "CENTER", 0, 0)
    local dotSz = db.dotSize or 6
    dotTex:SetSize(dotSz, dotSz)
    dotTex:SetVertexColor(1, 1, 1, 1)
    if db.showDot then dotTex:Show() else dotTex:Hide() end
    f.dot = dotTex

    local clickSz   = db.clickSize   or 70
    local clickTex  = Cursor.Textures[db.clickTexture or "Thin"] or Cursor.Textures["Thin"]
    local cr, cg, cb = GetClickColor()

    local cf = CreateFrame("Frame", "SP_CursorClickCircle", UIParent)
    cf:SetSize(clickSz, clickSz)
    cf:SetFrameStrata("MEDIUM")
    cf:SetFrameLevel(199)
    cf:EnableMouse(false)
    cf:SetClampedToScreen(false)
    cf:Hide()

    cf.texture = cf:CreateTexture(nil, "BACKGROUND")
    cf.texture:SetAllPoints()
    cf.texture:SetTexture(clickTex)
    cf.texture:SetVertexColor(cr, cg, cb, 0)   -- start transparent

    clickFrame = cf

    local _lastCX, _lastCY = -1, -1
    local mouseHoldTime    = 0
    local updateElapsed    = 0
    f:SetScript("OnUpdate", function(frame, elapsed)
        local cdb0 = GetDB()
        if cdb0.limitUpdateRate then
            updateElapsed = updateElapsed + elapsed
            -- 0.02 is DEFAULTS.cursor.updateInterval, not a second opinion.
            -- AceDB materialises the default, so this fallback is only ever
            -- reached on a table the DB has not filled -- and the options UI now
            -- treats DEFAULTS as the authoritative value for Reset and for
            -- "N settings changed". A disagreeing fallback makes both lie.
            if updateElapsed < (cdb0.updateInterval or 0.02) then return end
            updateElapsed = 0
        end

        local x, y = GetCursorPosition()

        -- Outside the moved-check: samples expire on a clock, so the trail has
        -- to keep being drawn while the cursor sits still or it freezes on
        -- screen at full opacity.
        UpdateTrail(cdb0, elapsed)
        ApplyOpacity()

        if x ~= _lastCX or y ~= _lastCY then
            _lastCX, _lastCY = x, y
            local scale = frame:GetEffectiveScale()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
            if clickFrame and clickFrame:IsShown() then
                local cscale = clickFrame:GetEffectiveScale()
                clickFrame:ClearAllPoints()
                clickFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / cscale, y / cscale)
            end
        end

        -- Click circle / replace logic
        local cdb = GetDB()
        if cdb.showClickCircle then
            local isDown = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
            local clickMode = cdb.clickMode or "overlay"

            if clickMode == "replace" then
                if isDown then
                    if not frame._clickReplacing then
                        frame._clickReplacing = true
                        local nr, ng, nb = GetClickColor()
                        local clickTex = Cursor.Textures[cdb.clickTexture or "Thin"]
                            or Cursor.Textures["Thin"]
                        frame.texture:SetTexture(clickTex)
                        frame.texture:SetVertexColor(nr, ng, nb, 0.9)
                        local clickSz = cdb.clickSize or 70
                        frame:SetSize(clickSz, clickSz)
                    end
                else
                    if frame._clickReplacing then
                        frame._clickReplacing = false
                        local r2, g2, b2 = GetCursorColor()
                        local origTex = Cursor.Textures[cdb.texture or "Thick"]
                            or Cursor.Textures["Thick"]
                        frame.texture:SetTexture(origTex)
                        frame.texture:SetVertexColor(r2, g2, b2, 0.9)
                        local sz = cdb.size or 50
                        frame:SetSize(sz, sz)
                    end
                end
                if clickFrame then clickFrame:Hide() end
            else
                if frame._clickReplacing then
                    frame._clickReplacing = false
                    local r2, g2, b2 = GetCursorColor()
                    local origTex = Cursor.Textures[cdb.texture or "Thick"]
                        or Cursor.Textures["Thick"]
                    frame.texture:SetTexture(origTex)
                    frame.texture:SetVertexColor(r2, g2, b2, 0.9)
                end
                if clickFrame then
                    if isDown then
                        mouseHoldTime = mouseHoldTime + elapsed
                        if mouseHoldTime >= 0.15 then
                            local cscale = clickFrame:GetEffectiveScale()
                            clickFrame:ClearAllPoints()
                            clickFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / cscale, y / cscale)
                            clickFrame:Show()
                            local nr, ng, nb = GetClickColor()
                            clickFrame.texture:SetVertexColor(nr, ng, nb, 0.9)
                        end
                    else
                        mouseHoldTime = 0
                        clickFrame.texture:SetVertexColor(0, 0, 0, 0)
                        clickFrame:Hide()
                    end
                end
            end
        else
            if clickFrame then clickFrame:Hide() end
            if frame._clickReplacing then
                frame._clickReplacing = false
                local cdb2 = GetDB()
                local r2, g2, b2 = GetCursorColor()
                local origTex = Cursor.Textures[cdb2.texture or "Thick"]
                    or Cursor.Textures["Thick"]
                frame.texture:SetTexture(origTex)
                frame.texture:SetVertexColor(r2, g2, b2, 0.9)
            end
        end
    end)

    mainFrame = f
end

-- ============================================================
-- Public API
-- ============================================================
-- Named Activate/Deactivate, NOT Enable/Disable.
-- AceAddon puts its own Enable/Disable mixin on every module table, so a
-- module function with those names SHADOWS the lifecycle: any caller doing
-- mod:Disable() then ran the feature teardown with a stray `self` argument
-- instead of the AceAddon one, never cleared enabledState, and here also
-- wrote to the saved variables.
--
-- Deliberately DOT functions that never touch `self`: the GUI and Core call
-- SP.Cursor.Refresh() while ModuleMixin calls self:Activate()/self:Deactivate(),
-- so the module table arrives as a stray first argument on one of the two
-- paths. Ignoring it entirely is the only shape that is correct for both.
function Cursor.Activate()
    local db = GetDB()
    if not db.enabled then return end
    if not mainFrame then CreateCursorFrame() end
    mainFrame:Show()

    RefreshCombatState()
    ApplyOpacity()
    Cursor:RegisterEvent("PLAYER_REGEN_DISABLED",  "OnCombatState")
    Cursor:RegisterEvent("PLAYER_REGEN_ENABLED",   "OnCombatState")
    Cursor:RegisterEvent("PLAYER_ENTERING_WORLD",  "OnCombatState")
end

function Cursor:OnCombatState()
    RefreshCombatState()
    ApplyOpacity()
end

function Cursor.Deactivate()
    -- The cursor is driven by an OnUpdate on mainFrame, which is parented to
    -- UIParent: hiding it is what actually stops the driver.
    if mainFrame   then mainFrame:Hide()  end
    if clickFrame  then clickFrame:Hide() end
    -- The trail lives on its own UIParent-parented frame, so hiding mainFrame
    -- does not take it with them: it would sit there frozen at the last spot
    -- the cursor happened to be.
    ClearTrail()
    Cursor:UnregisterEvent("PLAYER_REGEN_DISABLED")
    Cursor:UnregisterEvent("PLAYER_REGEN_ENABLED")
    Cursor:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if _previewClickTimer then
        _previewClickTimer:Cancel()
        _previewClickTimer = nil
    end
end

-- Doubles as ModuleMixin:Refresh -- it already dispatches to Activate or
-- Deactivate on db.enabled, so OnEnable/OnDisable come from the mixin.
function Cursor.Refresh()
    local db = GetDB()

    -- Keep AceAddon's flag tracking db.enabled. Without this the feature runs
    -- while the module is flagged disabled, and a later mod:Disable() is a
    -- no-op -- AceAddon returns early and OnDisable/Deactivate never run.
    if db and db.enabled and Cursor.IsEnabled and not Cursor:IsEnabled() then
        Cursor:Enable()
        return
    elseif not (db and db.enabled) and Cursor.IsEnabled and Cursor:IsEnabled() then
        Cursor:Disable()
        return
    end

    if not mainFrame then CreateCursorFrame() end

    if mainFrame then
        mainFrame:EnableMouse(false)
        mainFrame._clickReplacing = false  -- reset replace state on refresh

        local sz = db.size or 50
        mainFrame:SetSize(sz, sz)

        local texPath = Cursor.Textures[db.texture or "Thick"] or Cursor.Textures["Thick"]
        mainFrame.texture:SetTexture(texPath)
        local r, g, b = GetCursorColor()
        mainFrame.texture:SetVertexColor(r, g, b, 0.9)

        if mainFrame.dot then
            local dotSz = db.dotSize or 6
            mainFrame.dot:SetSize(dotSz, dotSz)
            if db.showDot then mainFrame.dot:Show() else mainFrame.dot:Hide() end
        end
    end

    -- Sync click circle settings
    if clickFrame then
        local clickSz  = db.clickSize   or 70
        local clickTex = Cursor.Textures[db.clickTexture or "Thin"] or Cursor.Textures["Thin"]
        clickFrame:SetSize(clickSz, clickSz)
        clickFrame.texture:SetTexture(clickTex)
            local cr, cg, cb = GetClickColor()
        clickFrame.texture:SetVertexColor(cr, cg, cb, 0)
        if not db.showClickCircle then clickFrame:Hide() end
    end

    if db.enabled then
        Cursor.Activate()
    else
        Cursor.Deactivate()
    end
end

function Cursor.PreviewClickCircle()
    local db = GetDB()
    local cr, cg, cb = GetClickColor()
    local clickSz  = db.clickSize   or 70
    local clickTex = Cursor.Textures[db.clickTexture or "Thin"] or Cursor.Textures["Thin"]
    local x, y     = GetCursorPosition()

    if (db.clickMode or "overlay") == "replace" then
        -- Replace mode: morph mainFrame briefly
        if not mainFrame then return end
        mainFrame.texture:SetTexture(clickTex)
        mainFrame.texture:SetVertexColor(cr, cg, cb, 0.9)
        mainFrame:SetSize(clickSz, clickSz)
        local scale = mainFrame:GetEffectiveScale()
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        mainFrame:Show()
        if _previewClickTimer then _previewClickTimer:Cancel() end
        _previewClickTimer = C_Timer.NewTimer(1.2, function()
            _previewClickTimer = nil
            if mainFrame and not mainFrame._clickReplacing then
                local r2, g2, b2 = GetCursorColor()
                local origTex = Cursor.Textures[db.texture or "Thick"] or Cursor.Textures["Thick"]
                mainFrame.texture:SetTexture(origTex)
                mainFrame.texture:SetVertexColor(r2, g2, b2, 0.9)
                local sz = db.size or 50
                mainFrame:SetSize(sz, sz)
                if not db.enabled then mainFrame:Hide() end
            end
        end)
    else
        -- Overlay mode: flash clickFrame
        if not clickFrame then return end
        clickFrame:SetSize(clickSz, clickSz)
        clickFrame.texture:SetTexture(clickTex)
        clickFrame.texture:SetVertexColor(cr, cg, cb, 0.85)
        local scale = clickFrame:GetEffectiveScale()
        clickFrame:ClearAllPoints()
        clickFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        clickFrame:Show()
        if _previewClickTimer then _previewClickTimer:Cancel() end
        _previewClickTimer = C_Timer.NewTimer(1.2, function()
            _previewClickTimer = nil
            if clickFrame then
                clickFrame.texture:SetVertexColor(cr, cg, cb, 0)
                if not db.showClickCircle then clickFrame:Hide() end
            end
        end)
    end
end

-- ============================================================
-- AceAddon Module lifecycle
--
-- Nothing left to write: OnEnable (deferred to PLAYER_LOGIN, then Refresh) and
-- OnDisable (UnregisterAllEvents + Deactivate) both come from SP.ModuleMixin --
-- see Core/Module.lua. Cursor.Refresh above is the mixin's Refresh.
-- ============================================================
