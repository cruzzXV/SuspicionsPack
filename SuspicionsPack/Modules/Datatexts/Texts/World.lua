-- SuspicionsPack — Datatexts: Time

local SP = SuspicionsPack
local DT = SP.Datatexts

-- ============================================================
-- Time: the clock, resets and raid lockouts in the tooltip
--
-- No Encounter Journal calls: Forever has no Encounter Journal
-- (Blizzard_EncounterJournal does not load on `camelot`).
-- ============================================================
local function FormatClock(h, m, use24)
    if use24 then return string.format("%02d:%02d", h, m) end
    local suffix = h >= 12 and " PM" or " AM"
    h = h % 12
    if h == 0 then h = 12 end
    return string.format("%d:%02d", h, m) .. suffix
end

local function LocalClock(use24)
    local t = date("*t")
    return FormatClock(t.hour, t.min, use24)
end

local function RealmClock(use24)
    local h, m = GetGameTime()
    return FormatClock(h or 0, m or 0, use24)
end

local redrawing = false

local function Duration(seconds)
    if SecondsToTime then return SecondsToTime(seconds, true) end
    return DT.Clock(seconds)
end

DT.Register("time", {
    name     = "Time",
    group    = "World",
    events   = { "UPDATE_INSTANCE_INFO" },
    interval = 1,
    options  = {
        { kind = "toggle", key = "use24", label = "24-hour clock", default = true },
        { kind = "toggle", key = "realmTime", label = "Show the realm's time", default = false },
    },
    OnEvent = function(o, event)
        -- The lockouts arrive after the request made on hover. Redrawn without
        -- asking again: the request itself fires this event.
        local owner = DT.TooltipOwner and DT.TooltipOwner()
        if event == "UPDATE_INSTANCE_INFO" and owner and owner.id == "time" then
            redrawing = true
            DT.SlotEnter(owner)
            redrawing = false
        end
    end,
    Text = function(o)
        if o.realmTime then return RealmClock(o.use24) end
        return LocalClock(o.use24)
    end,
    Tooltip = function(o, tt)
        if RequestRaidInfo and not redrawing then RequestRaidInfo() end
        DT.TipHeader(tt, date("%A %d %B"))
        DT.TipLine(tt, "Local time", LocalClock(o.use24))
        DT.TipLine(tt, "Realm time", RealmClock(o.use24))
        local dt = C_DateAndTime
        if dt and dt.GetSecondsUntilDailyReset then
            DT.TipLine(tt, "Daily reset", Duration(dt.GetSecondsUntilDailyReset()))
        end
        if dt and dt.GetSecondsUntilWeeklyReset then
            DT.TipLine(tt, "Weekly reset", Duration(dt.GetSecondsUntilWeeklyReset()))
        end

        local n = GetNumSavedInstances and GetNumSavedInstances() or 0
        local shown = false
        for i = 1, n do
            local name, _, reset, _, locked, extended, _, _, _, difficultyName, numEncounters, progress =
                GetSavedInstanceInfo(i)
            if name and (locked or extended) then
                if not shown then
                    DT.TipSpace(tt)
                    DT.TipHeader(tt, "Saved instances")
                    shown = true
                end
                local left = name
                if difficultyName and difficultyName ~= "" then left = left .. " |cff999999(" .. difficultyName .. ")|r" end
                if numEncounters and numEncounters > 0 then
                    left = left .. " " .. (progress or 0) .. "/" .. numEncounters
                end
                DT.TipLine(tt, left, Duration(reset or 0))
            end
        end

        DT.TipSpace(tt)
        DT.TipNote(tt, "Click: calendar    Right-click: stopwatch and alarm")
    end,
    Click = function(o, slot, button)
        if InCombatLockdown() then return end
        if button == "LeftButton" then
            if GameTimeFrame and GameTimeFrame.Click then GameTimeFrame:Click() end
        elseif button == "RightButton" then
            local AddOns = C_AddOns
            if AddOns and AddOns.IsAddOnLoaded and not AddOns.IsAddOnLoaded("Blizzard_TimeManager") then
                AddOns.LoadAddOn("Blizzard_TimeManager")
            end
            if TimeManager_Toggle then TimeManager_Toggle() end
        end
    end,
})
