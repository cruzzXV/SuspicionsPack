-- SuspicionsPack — Profiler
--
-- /spack perf start [engine] [name] | stop | report
--
-- Measures what the pack costs in a real scenario, so optimisation follows the
-- numbers instead of a read of the code. Two sources, because neither is
-- enough on its own:
--
--   * the engine's own counters (C_AddOnProfiler). Exact, always on, but blind
--     to most of this addon. The engine bills an OnEvent script to the addon
--     that CREATED the frame, and every AceEvent handler runs from one shared
--     frame, AceEvent30Frame, created by whichever addon loaded AceEvent
--     first. So "SuspicionsPack" in the engine either misses all our AceEvent
--     work, or carries every Ace addon's if we happened to load first. A code
--     path that starts in secure Blizzard code is not tracked at all, which is
--     every hooksecurefunc on a Blizzard function. Mouse scripts neither.
--     (warcraft.wiki.gg, API_C_AddOnProfiler.GetAddOnMetric.)
--
--   * our own timing around every entry point where the game calls into the
--     pack: AceEvent handlers, the Ticker, our frames' OnEvent / OnUpdate,
--     hooksecurefunc and HookScript. Self time (nested measured calls are
--     subtracted, so the rows add up), the slowest single call, and a lower
--     bound on what each one allocates.
--
-- Every wrapper stays in place for the whole session. Outside a capture it is
-- one boolean test and a tail call, so there is nothing to install or remove
-- and nothing to restore if a capture ends badly. Inside a capture it costs
-- two debugprofilestop and two collectgarbage("count") per call; that cost is
-- measured at start and printed with the report.
--
-- Loaded before Core.lua (it needs only the addon namespace), so even the
-- frames Core.lua creates at file scope can be wrapped. Core.lua publishes it
-- as SP.Perf.
--
-- Never call debugprofilestart: it resets the one clock every addon shares.

local _, NS = ...

local Perf = {}
NS.Perf = Perf

local debugprofilestop = debugprofilestop
local collectgarbage   = collectgarbage
local select, type, pairs, ipairs = select, type, pairs, ipairs
local format = string.format

local REPORTS_KEPT = 10
local SAMPLE_EVERY = 0.5   -- seconds between engine samples
local TOP_PRINTED  = 12    -- handler rows printed to chat; all of them are saved

-- ============================================================
-- Timing
-- ============================================================
local on      = false   -- a capture with handler timing is running
local stats   = {}      -- [mod][label] = { n, self, max, kb }
local calls   = 0
-- Time and memory measured by calls nested inside the one being measured.
-- A call that errors leaves these as they were at its entry; only the call
-- around it, if any, is skewed, and a top-level call never reads them.
local childT, childKB = 0, 0

local function Bucket(mod, label)
    local m = stats[mod]
    if not m then m = {}; stats[mod] = m end
    local b = m[label]
    if not b then
        b = { n = 0, self = 0, max = 0, kb = 0 }
        m[label] = b
    end
    return b
end

-- Only the first return value survives: no wrapped caller uses more, and the
-- AnimTicker needs exactly that one (truthy keeps ticking).
local function Measure(mod, label, fn, ...)
    local pT, pKB = childT, childKB
    childT, childKB = 0, 0
    local kb0 = collectgarbage("count")
    local t0  = debugprofilestop()
    local r   = fn(...)
    local dt  = debugprofilestop() - t0
    local dkb = collectgarbage("count") - kb0
    local b = Bucket(mod, label)
    b.n    = b.n + 1
    b.self = b.self + (dt - childT)
    if dt > b.max then b.max = dt end
    -- A GC step that runs during the call frees other objects and pulls the
    -- delta down, so this can only under-count. Negative is noise, not credit.
    local own = dkb - childKB
    if own > 0 then b.kb = b.kb + own end
    childT, childKB = pT + dt, pKB + dkb
    calls = calls + 1
    return r
end

-- ============================================================
-- Wrappers
-- ============================================================

-- Any handler: a hook, a non-event script, a callback.
function Perf.Wrap(mod, label, fn)
    if type(fn) ~= "function" then return fn end
    return function(...)
        if not on then return fn(...) end
        return Measure(mod, label, fn, ...)
    end
end

-- An OnEvent script: one row per event the frame receives.
function Perf.WrapEvent(mod, fn)
    if type(fn) ~= "function" then return fn end
    return function(frame, event, ...)
        if not on then return fn(frame, event, ...) end
        return Measure(mod, event, fn, frame, event, ...)
    end
end

-- Same signature as hooksecurefunc, the hooked function's name as the label.
-- A file shadows the global with it:
--     local hooksecurefunc = SP.Perf.HookFunc("MyModule")
-- The global is looked up at each call, not cached here: installing a hook is
-- rare, and a test double installed after this file loads must still be used.
function Perf.HookFunc(mod)
    return function(a, b, c)
        if c ~= nil then return hooksecurefunc(a, b, Perf.Wrap(mod, b, c)) end
        return hooksecurefunc(a, Perf.Wrap(mod, a, b))
    end
end

-- AceEvent: rebuild the handler the way CallbackHandler would (method name
-- resolved on self at fire time, optional fixed arg before the payload) and
-- hand AceEvent a plain function instead. Same arguments reach the handler.
local function AceHandler(self, mod, event, method, ...)
    local hasArg, arg = select("#", ...) >= 1, ...
    if type(method) == "string" then
        if hasArg then
            return function(...)
                if not on then return self[method](self, arg, ...) end
                return Measure(mod, event, self[method], self, arg, ...)
            end
        end
        return function(...)
            if not on then return self[method](self, ...) end
            return Measure(mod, event, self[method], self, ...)
        end
    end
    if hasArg then
        return function(...)
            if not on then return method(arg, ...) end
            return Measure(mod, event, method, arg, ...)
        end
    end
    return function(...)
        if not on then return method(...) end
        return Measure(mod, event, method, ...)
    end
end

-- Called on every module at creation, and on the addon object itself. Only
-- replaces AceEvent's own Register* methods: an object that carries anything
-- else (a test double, a future library) keeps it untouched.
function Perf.InstrumentAce(target, mod)
    local AceEvent = LibStub and LibStub("AceEvent-3.0", true)
    if not AceEvent or type(target) ~= "table" then return end
    for _, name in ipairs({ "RegisterEvent", "RegisterMessage" }) do
        local orig = target[name]
        if orig ~= nil and orig == AceEvent[name] then
            target[name] = function(self, event, method, ...)
                method = method or event
                local t = type(method)
                if type(event) ~= "string" or (t ~= "string" and t ~= "function")
                   or (t == "string" and (type(self) ~= "table" or type(self[method]) ~= "function")) then
                    -- Malformed: let AceEvent raise its own usage error.
                    return orig(self, event, method, ...)
                end
                return orig(self, event, AceHandler(self, mod, event, method, ...))
            end
        end
    end
end

-- ============================================================
-- Engine counters
-- ============================================================
local COUNTS = {   -- report key, metric name
    { "over1",   "CountTimeOver1Ms"   },
    { "over5",   "CountTimeOver5Ms"   },
    { "over10",  "CountTimeOver10Ms"  },
    { "over50",  "CountTimeOver50Ms"  },
    { "over100", "CountTimeOver100Ms" },
}

local function Profiler()
    local P, E = C_AddOnProfiler, Enum and Enum.AddOnProfilerMetric
    if not (P and E and P.GetAddOnMetric) then return nil end
    return P, E
end

-- source: an addon name, "overall" (every addon) or "app" (the whole client).
-- pcall: the metric of an addon that is not loaded is not documented.
local function Metric(source, metricName)
    local P, E = Profiler()
    if not P then return nil end
    local m = E[metricName]
    if m == nil then return nil end
    local ok, v
    if source == "overall" then ok, v = pcall(P.GetOverallMetric, m)
    elseif source == "app" then ok, v = pcall(P.GetApplicationMetric, m)
    else ok, v = pcall(P.GetAddOnMetric, source, m) end
    if ok and type(v) == "number" then return v end
    return nil
end

local SOURCES = { "SuspicionsPack", "SuspicionsPack_Config", "overall", "app" }

local function Snapshot()
    local s = {}
    for _, src in ipairs(SOURCES) do
        local t = {
            peak    = Metric(src, "PeakTime"),
            session = Metric(src, "SessionAverageTime"),
        }
        for _, c in ipairs(COUNTS) do t[c[1]] = Metric(src, c[2]) end
        s[src] = t
    end
    return s
end

-- ============================================================
-- Capture
-- ============================================================
local cap          -- the running capture, nil when idle
local lastReport   -- the last finished one, for `report`
local sampler      -- C_Timer ticker while capturing
local encFrame = CreateFrame("Frame")

local function Print(msg)
    print("|cffe51039SP perf|r " .. msg)
end

-- Each sample stands for the time since the previous one: the engine's
-- RecentAverageTime covers the last 60 frames, about that long. Weighting by
-- that time keeps the sample taken at stop, which may close only a sliver of
-- an interval, from counting as much as a full one.
local function Sample()
    local now = GetTime()
    local dt  = now - cap.lastSample
    local fps = GetFramerate and GetFramerate() or 0
    cap.frames = cap.frames + fps * dt
    cap.weight = cap.weight + dt
    cap.lastSample = now
    cap.samples = cap.samples + 1
    for _, src in ipairs(SOURCES) do
        local v = Metric(src, "RecentAverageTime")
        if v then cap.recent[src] = (cap.recent[src] or 0) + v * dt end
    end
end

-- A secret (12.x) or a table cannot go into a saved report as is.
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    local t = type(v)
    if t == "number" or t == "boolean" or t == "string" or v == nil then return v end
    return tostring(v)
end

-- Payload per EncounterInfoDocumentation (12.1.5 and 1.60.1): encounterID,
-- encounterName, difficultyID, groupSize, success, encounterUnitStatus. Kept
-- raw all the same, so the first report from a real pull confirms it.
encFrame:SetScript("OnEvent", function(_, event, ...)
    if not cap then return end
    local args = {}
    for i = 1, select("#", ...) do args[i] = Plain((select(i, ...))) end
    cap.encounters[#cap.encounters + 1] = {
        args = args,
        sp      = Metric("SuspicionsPack", "EncounterAverageTime"),
        overall = Metric("overall", "EncounterAverageTime"),
        app     = Metric("app", "EncounterAverageTime"),
    }
end)

local function AceFrameSource()
    local f = _G.AceEvent30Frame
    if not (f and f.GetSourceLocation) then return nil end
    local ok, loc = pcall(f.GetSourceLocation, f)
    if not ok then return nil end
    return Plain(loc)
end

local function ThrottleLimits()
    if type(GetScriptBucketThrottleLimits) ~= "function" then return nil end
    local ok, t = pcall(GetScriptBucketThrottleLimits)
    if not (ok and type(t) == "table") then return nil end
    local out = {}
    for k, v in pairs(t) do out[k] = Plain(v) end
    return out
end

-- Memory the engine attributes to the pack. UpdateAddOnMemoryUsage walks every
-- addon and can hitch for tens of ms, so never in combat.
local function OwnMemoryKB()
    if InCombatLockdown() then return nil end
    local update = (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage) or UpdateAddOnMemoryUsage
    local get    = (C_AddOns and C_AddOns.GetAddOnMemoryUsage) or GetAddOnMemoryUsage
    if not (update and get) then return nil end
    update()
    local ok, kb = pcall(get, "SuspicionsPack")
    return ok and kb or nil
end

-- What one Measure costs on top of the call it wraps.
local function Calibrate()
    local function noop() end
    local N = 2000
    local t0 = debugprofilestop()
    for _ = 1, N do noop() end
    local bare = debugprofilestop() - t0
    t0 = debugprofilestop()
    for _ = 1, N do Measure("Perf", "calibration", noop) end
    local wrapped = debugprofilestop() - t0
    stats.Perf = nil
    calls = 0
    return math.max(0, (wrapped - bare) / N)
end

local function Start(mode, name)
    if cap then
        Print("already capturing \"" .. cap.name .. "\". /spack perf stop first.")
        return
    end
    for k in pairs(stats) do stats[k] = nil end
    calls, childT, childKB = 0, 0, 0
    local perCall = 0
    if mode == "full" then perCall = Calibrate() end

    local now = GetTime()
    cap = {
        name = name, mode = mode,
        t0 = now, lastSample = now,
        frames = 0, samples = 0, weight = 0, recent = {},
        before = Snapshot(),
        heapKB = collectgarbage("count"),
        ownKB  = OwnMemoryKB(),
        perCall = perCall,
        encounters = {},
        started = date and date("%Y-%m-%d %H:%M:%S") or nil,
    }
    encFrame:RegisterEvent("ENCOUNTER_END")
    sampler = C_Timer.NewTicker(SAMPLE_EVERY, Perf.Wrap("Perf", "sampler", Sample))
    if mode == "full" then
        on = true
        -- The Ticker's dispatch loop calls the probe in place of each
        -- subscriber: per-key rows, and nothing allocated per frame.
        local Tick = SuspicionsPack and SuspicionsPack.Tick
        if Tick then Tick.probe = Measure end
    end

    local P = Profiler()
    Print(format("capturing \"%s\" (%s). /spack perf stop when done.", name,
        mode == "full" and "engine + handlers" or "engine only"))
    if not P then Print("C_AddOnProfiler is missing: handler timing only.")
    elseif P.IsEnabled and not P.IsEnabled() then Print("C_AddOnProfiler reports disabled.") end
end

-- Time-weighted mean of the per-frame samples, and the differences since the
-- start.
local function EngineBlock(before, after, recentSum, weight)
    local out = {}
    for _, src in ipairs(SOURCES) do
        local b, a = before[src] or {}, after[src] or {}
        local t = {}
        if weight > 0 and recentSum[src] then t.avg = recentSum[src] / weight end
        for _, c in ipairs(COUNTS) do
            local k = c[1]
            if a[k] and b[k] then t[k] = a[k] - b[k] end
        end
        t.peak    = a.peak
        t.newPeak = (a.peak and b.peak and a.peak > b.peak) or false
        t.session = a.session
        out[src] = t
    end
    return out
end

local function HandlerRows()
    local rows = {}
    for mod, labels in pairs(stats) do
        for label, b in pairs(labels) do
            rows[#rows + 1] = { mod = mod, label = tostring(label), n = b.n,
                                self = b.self, max = b.max, kb = b.kb }
        end
    end
    table.sort(rows, function(x, y) return x.self > y.self end)
    return rows
end

local function BuildReport()
    local now = GetTime()
    local version, build, toc
    if GetBuildInfo then
        local v, b, _, t = GetBuildInfo()   -- never assign the global _
        version, build, toc = v, b, t
    end
    local forever = WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
    local zone, instType = GetInstanceInfo()
    local r = {
        name = cap.name, mode = cap.mode, started = cap.started,
        addon = SuspicionsPack and SuspicionsPack.VERSION,
        client = { flavor = forever and "forever" or "retail",
                   version = version, build = build, toc = toc },
        where = { zone = Plain(zone), type = Plain(instType),
                  group = GetNumGroupMembers and GetNumGroupMembers() or 0,
                  combatAtStop = InCombatLockdown() and true or false },
        seconds = now - cap.t0,
        frames  = cap.frames,
        samples = cap.samples,
        engine  = EngineBlock(cap.before, Snapshot(), cap.recent, cap.weight),
        encounters = cap.encounters,
        aceEventFrame = AceFrameSource(),
        throttle = ThrottleLimits(),
        heapKB = { start = cap.heapKB, stop = collectgarbage("count") },
        ownKB  = { start = cap.ownKB, stop = OwnMemoryKB() },
        calls = calls,
        perCallMs = cap.perCall,
        handlers = HandlerRows(),
    }
    return r
end

local function Num(v, fmt) return v and format(fmt or "%.3f", v) or "?" end

local function PrintReport(r, interim)
    local e = r.engine and r.engine.SuspicionsPack or {}
    local all, app = r.engine and r.engine.overall or {}, r.engine and r.engine.app or {}
    local cfg = r.engine and r.engine.SuspicionsPack_Config or {}
    Print(format("%s\"%s\": %.0f s, ~%.0f frames, %d samples (%s %s, pack %s)",
        interim and "so far, " or "", r.name, r.seconds, r.frames, r.samples,
        r.client.flavor, tostring(r.client.version), tostring(r.addon)))
    Print(format("engine, SuspicionsPack: %s ms/frame, frames >1ms %s, >5ms %s, >10ms %s, >50ms %s, peak %s ms%s",
        Num(e.avg), Num(e.over1, "%d"), Num(e.over5, "%d"), Num(e.over10, "%d"), Num(e.over50, "%d"),
        Num(e.peak, "%.2f"), e.newPeak and " (new)" or ""))
    Print(format("engine, Config %s, all addons %s, whole client %s ms/frame",
        Num(cfg.avg), Num(all.avg), Num(app.avg)))
    for _, enc in ipairs(r.encounters or {}) do
        Print(format("encounter %s: pack %s, all addons %s ms/frame",
            tostring(enc.args and enc.args[2]), Num(enc.sp), Num(enc.overall)))
    end
    if r.mode == "full" then
        local total = 0
        for _, row in ipairs(r.handlers) do total = total + row.self end
        local perFrame = r.frames > 0 and total / r.frames or nil
        Print(format("timed handlers: %.1f ms self over %d calls (%s ms/frame), measuring cost ~%.1f ms",
            total, r.calls, Num(perFrame), r.calls * (r.perCallMs or 0)))
        for i = 1, math.min(TOP_PRINTED, #r.handlers) do
            local row = r.handlers[i]
            Print(format("  %8.2f ms  %6dx  max %.3f  %s KB  %s %s",
                row.self, row.n, row.max, Num(row.kb, "%.0f"), row.mod, row.label))
        end
    end
    if r.aceEventFrame then
        Print("AceEvent30Frame was created at " .. tostring(r.aceEventFrame)
              .. ": the engine bills every AceEvent handler to that addon.")
    end
    local lim = r.throttle
    if lim then
        Print(format("client script budget: %s ms/s (%s restricted), burst %s ms (%s restricted)",
            tostring(lim.luaScriptBucketThrottleMaxMsPerSecondNormal),
            tostring(lim.luaScriptBucketThrottleMaxMsPerSecondRestricted),
            tostring(lim.luaScriptBucketThrottleMaxMsBurstNormal),
            tostring(lim.luaScriptBucketThrottleMaxMsBurstRestricted)))
    end
    Print("not timed: C_Timer callbacks (the engine counts them), mouse scripts.")
end

local function Stop()
    if not cap then Print("nothing is being captured.") return end
    on = false
    local Tick = SuspicionsPack and SuspicionsPack.Tick
    if Tick then Tick.probe = nil end
    if sampler then sampler:Cancel(); sampler = nil end
    encFrame:UnregisterEvent("ENCOUNTER_END")
    Sample()   -- close the last partial interval

    local r = BuildReport()
    cap = nil
    lastReport = r

    local db = SuspicionsPack and SuspicionsPack.GetGlobalDB and SuspicionsPack.GetGlobalDB()
    local n
    if db then
        db.perfReports = db.perfReports or {}
        local list = db.perfReports
        list[#list + 1] = r
        while #list > REPORTS_KEPT do table.remove(list, 1) end
        n = #list
    end
    PrintReport(r)
    if n then Print(format("saved as report %d/%d. /reload writes it to SavedVariables.", n, REPORTS_KEPT)) end
end

local function Report()
    if cap then
        Sample()
        PrintReport(BuildReport(), true)
        return
    end
    if lastReport then PrintReport(lastReport) return end
    Print("no capture yet. /spack perf start [name]")
end

-- input: everything after "perf", already lower-cased and trimmed.
function Perf.Command(input)
    local words = {}
    for w in (input or ""):gmatch("%S+") do words[#words + 1] = w end
    local verb = words[1]
    if verb == "start" then
        local mode, first = "full", 2
        if words[2] == "engine" then mode, first = "engine", 3 end
        local name = table.concat(words, " ", first)
        Start(mode, name ~= "" and name or "capture")
    elseif verb == "stop" then
        Stop()
    elseif verb == "report" then
        Report()
    else
        Print("/spack perf start [engine] [name] | stop | report")
    end
end

-- For tests and for other files that need to know.
function Perf.IsCapturing() return cap ~= nil end
function Perf._Stats() return stats end
Perf._Measure = Measure
