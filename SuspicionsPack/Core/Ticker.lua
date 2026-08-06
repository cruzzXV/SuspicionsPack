-- SuspicionsPack — Shared Ticker
--
-- A self-disarming per-frame driver. The driver frame only *runs* while at
-- least one subscriber is registered, so an idle addon executes no per-frame
-- Lua at all.
--
-- Before this existed, three modules each owned a permanent OnUpdate that was
-- armed on enable and never disarmed: CombatTimer redrew a 4 Hz text label from
-- a 60 fps handler for the whole session, MovementAlert ran ten
-- GetSpellCooldown scans a second while standing in a city with nothing on
-- screen, and ReapPredict polled at 10 Hz whenever its bar existed. None of
-- that work was needed when the thing it drives is not visible.
--
-- Modelled on EllesmereUI/EllesmereUI_Ticker.lua. Their version carries a
-- NewDriver() factory because the engine bills a script handler's entire call
-- tree to the addon whose execution context created the frame, so a suite of
-- addons needs one driver per addon to get honest CPU attribution.
-- SuspicionsPack is a single addon, so one shared driver created here is both
-- correct and simpler.
--
-- Contract:
--   * Add is idempotent -- calling it again with the same key replaces the
--     function instead of duplicating the entry, so a handler can arm
--     unconditionally without first checking whether it already did. That is
--     deliberate: a missed re-arm freezes a bar, so always arm rather than
--     trying to be clever about it.
--   * A subscriber MUST remove itself once its work has settled (combat ended,
--     countdown finished, animation reached its target). Removing from inside
--     your own tick is safe and is the normal way to do it.
--   * Remove on an unregistered key is a no-op, so pairing every start with a
--     stop is always safe.
--   * dt is real elapsed time since the previous dispatch, so animation speed
--     matches a hand-rolled per-frame OnUpdate exactly.

local SP = SuspicionsPack

local Tick = {}
SP.Tick = Tick

-- ============================================================
-- Driver
-- ============================================================
local reg    = {}   -- dense array of keys
local regFn  = {}   -- parallel array of tick functions
local index  = {}   -- key -> position in reg
local count  = 0

local frame = CreateFrame("Frame")
frame:Hide()

-- Reused across frames so dispatch allocates nothing.
local scratch = {}

frame:SetScript("OnUpdate", function(self, elapsed)
    -- Snapshot the keys, then dispatch by looking each one up again.
    --
    -- Walking the live array by index looks cheaper but is wrong in two ways,
    -- both reproduced: if a subscriber removes a key sitting BEFORE it, the
    -- swap-remove moves the tail entry into an already-visited slot and that
    -- entry is skipped for the whole frame; and if a subscriber removes then
    -- re-adds itself, it lands at the new tail and gets dispatched twice in the
    -- same frame. The liveness re-check below means a key removed mid-frame is
    -- simply not called, and one added mid-frame waits until the next frame.
    local n = count
    for i = 1, n do
        scratch[i] = reg[i]
    end
    for i = 1, n do
        local key = scratch[i]
        scratch[i] = nil
        local pos = index[key]
        if pos then
            local fn = regFn[pos]
            if fn then fn(elapsed) end
        end
    end

    if count == 0 then
        self:Hide()
    end
end)

-- Register (or replace) the tick function for a key. Arms the driver on the
-- 0 -> 1 transition.
function Tick.Add(key, fn)
    if not key or type(fn) ~= "function" then return end
    local i = index[key]
    if i then
        regFn[i] = fn
        return
    end
    count        = count + 1
    reg[count]   = key
    regFn[count] = fn
    index[key]   = count
    if count == 1 then frame:Show() end
end

-- Unregister a key. Swap-removes so churn stays O(1). Hides the driver once the
-- last subscriber leaves, which is what makes idle actually free.
function Tick.Remove(key)
    local i = index[key]
    if not i then return end
    local lastKey = reg[count]
    reg[i]        = lastKey
    regFn[i]      = regFn[count]
    index[lastKey] = i
    reg[count]    = nil
    regFn[count]  = nil
    count         = count - 1
    index[key]    = nil
    if count == 0 then frame:Hide() end
end

function Tick.Has(key)
    return index[key] ~= nil
end

-- Live subscriber count. Zero means no per-frame code is running.
function Tick.Count()
    return count
end

-- ============================================================
-- Fixed-rate ticker
--
-- For work that is genuinely time-based but does not need frame-rate
-- resolution -- a countdown label, a 10 Hz poll. A looping Animation fires
-- OnLoop at the interval and the C engine sleeps in between, so this costs zero
-- Lua per frame, unlike an OnUpdate that throttles itself with an accumulator
-- (which still pays the dispatch 60 times a second to do nothing 56 of them).
--
-- fn returns truthy to keep ticking, falsy to stop (self-disarm).
-- Start() on an already-playing ticker is one IsPlaying check, so arming can
-- stay indiscriminate.
-- ============================================================
function Tick.NewAnimTicker(fn, interval)
    local host = CreateFrame("Frame")
    local ag   = host:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local anim = ag:CreateAnimation("Animation")
    anim:SetDuration(interval or 0.05)

    ag:SetScript("OnLoop", function()
        if not fn() then ag:Stop() end
    end)

    local t = {}
    function t.Start(newInterval)
        if not ag:IsPlaying() then
            if newInterval then anim:SetDuration(newInterval) end
            ag:Play()
        end
    end
    function t.Stop()      ag:Stop()        end
    function t.IsPlaying() return ag:IsPlaying() end
    function t.SetInterval(v)
        anim:SetDuration(v)
        if ag:IsPlaying() then ag:Stop(); ag:Play() end
    end
    return t
end

-- ============================================================
-- Eased value animation
--
-- Intended to replace the hand-rolled `C_Timer.NewTicker(0.016, ...)` lerp
-- copy-pasted eleven times across Core and the GUI, each allocating its own
-- timer object and closure per burst. Those call sites are NOT migrated yet --
-- this has no callers today.
--
-- ease(t) maps 0..1 -> 0..1; defaults to quadratic ease-out.
-- Returns the key, so the caller can Tick.Remove() it to cancel.
-- ============================================================
local animSerial = 0

local function EaseOutQuad(t) return 1 - (1 - t) * (1 - t) end

function Tick.Animate(from, to, duration, apply, ease, onDone)
    if type(apply) ~= "function" then return end
    duration = duration or 0.15
    ease     = ease or EaseOutQuad

    -- Degenerate duration: apply the end state now rather than dividing by zero.
    if duration <= 0 then
        apply(to)
        if onDone then onDone() end
        return
    end

    animSerial = animSerial + 1
    local key  = "anim" .. animSerial
    local t    = 0

    Tick.Add(key, function(dt)
        t = t + dt
        if t >= duration then
            apply(to)
            Tick.Remove(key)
            if onDone then onDone() end
            return
        end
        apply(from + (to - from) * ease(t / duration))
    end)

    return key
end
