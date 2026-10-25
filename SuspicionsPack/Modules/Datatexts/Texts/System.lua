-- SuspicionsPack — Datatexts: System, Volume

local SP = SuspicionsPack
local DT = SP.Datatexts

local floor = math.floor

-- ============================================================
-- System: framerate and latency, addon memory in the tooltip
--
-- Forever has the global UpdateAddOnMemoryUsage / GetAddOnMemoryUsage but not
-- their C_AddOns versions (checked on the `forever` branch).
-- ============================================================
local GREEN, YELLOW, ORANGE, RED = "|cff2fd82f", "|cffe8da0f", "|cffff9000", "|cffd80909"

local function FpsColor(fps)
    if fps >= 60 then return GREEN elseif fps >= 30 then return YELLOW elseif fps >= 15 then return ORANGE end
    return RED
end

local function MsColor(ms)
    if ms < 100 then return GREEN elseif ms < 200 then return YELLOW elseif ms < 300 then return ORANGE end
    return RED
end

local AddOns = C_AddOns or {}
local NumAddOns    = AddOns.GetNumAddOns or GetNumAddOns
local AddOnInfo    = AddOns.GetAddOnInfo or GetAddOnInfo
local AddOnLoaded  = AddOns.IsAddOnLoaded or IsAddOnLoaded

local function Memory(kb)
    if kb >= 1024 then return string.format("%.1f MB", kb / 1024) end
    return string.format("%.0f KB", kb)
end

-- The memory scan walks every addon; at most every two seconds.
local memCache, memTotal, memAt = {}, 0, 0
local function ScanMemory()
    if GetTime() - memAt < 2 then return memCache, memTotal end
    memAt = GetTime()
    wipe(memCache)
    memTotal = 0
    if not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage and NumAddOns) then return memCache, memTotal end
    UpdateAddOnMemoryUsage()
    for i = 1, NumAddOns() do
        if AddOnLoaded and AddOnLoaded(i) then
            local kb = GetAddOnMemoryUsage(i) or 0
            local _, title = AddOnInfo(i)
            memCache[#memCache + 1] = { name = title or ("AddOn " .. i), kb = kb }
            memTotal = memTotal + kb
        end
    end
    table.sort(memCache, function(a, b) return a.kb > b.kb end)
    return memCache, memTotal
end

DT.Register("system", {
    name     = "System",
    group    = "System",
    interval = 1,
    options  = {
        { kind = "slider", key = "topAddons", label = "AddOns listed in the tooltip", min = 0, max = 30, step = 1, default = 10 },
    },
    Text = function()
        local fps = floor(GetFramerate() + 0.5)
        local _, _, home, world = GetNetStats()
        local ms = world and world > 0 and world or home or 0
        return FpsColor(fps) .. fps .. "|r fps  " .. MsColor(ms) .. ms .. "|r ms"
    end,
    Tooltip = function(o, tt)
        local _, _, home, world = GetNetStats()
        local fps = floor(GetFramerate() + 0.5)
        DT.TipHeader(tt, "System")
        DT.TipLine(tt, "Framerate", FpsColor(fps) .. fps .. " fps|r")
        DT.TipLine(tt, "Home latency", MsColor(home or 0) .. (home or 0) .. " ms|r")
        DT.TipLine(tt, "World latency", MsColor(world or 0) .. (world or 0) .. " ms|r")
        local n = o.topAddons or 0
        if n > 0 then
            local list, total = ScanMemory()
            DT.TipSpace(tt)
            DT.TipHeader(tt, "AddOn memory", Memory(total))
            for i = 1, math.min(n, #list) do
                DT.TipLine(tt, list[i].name, Memory(list[i].kb))
            end
        end
        DT.TipSpace(tt)
        DT.TipNote(tt, "Shift+click: collect garbage")
    end,
    Click = function(o, slot, button)
        if button == "LeftButton" and IsShiftKeyDown() then
            local before = collectgarbage("count")
            collectgarbage("collect")
            memAt = 0
            print("|cffe51039Suspicion's Pack|r: freed " .. Memory(before - collectgarbage("count")) .. ".")
        end
    end,
})

-- ============================================================
-- Volume: one sound stream, changed with the mouse wheel
-- ============================================================
local STREAMS = {
    { key = "master",   label = "Master",   volume = "Sound_MasterVolume",   enable = "Sound_EnableAllSound" },
    { key = "sfx",      label = "Effects",  volume = "Sound_SFXVolume",      enable = "Sound_EnableSFX" },
    { key = "music",    label = "Music",    volume = "Sound_MusicVolume",    enable = "Sound_EnableMusic" },
    { key = "ambience", label = "Ambience", volume = "Sound_AmbienceVolume", enable = "Sound_EnableAmbience" },
    { key = "dialog",   label = "Dialog",   volume = "Sound_DialogVolume",   enable = "Sound_EnableDialog" },
}
local STREAM_BY_KEY = {}
for _, s in ipairs(STREAMS) do STREAM_BY_KEY[s.key] = s end

local function GetCVarValue(name)
    local v = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name) or (GetCVar and GetCVar(name))
    return v
end

local function SetCVarValue(name, value)
    if C_CVar and C_CVar.SetCVar then C_CVar.SetCVar(name, value) elseif SetCVar then SetCVar(name, value) end
end

local function Stream(o) return STREAM_BY_KEY[o.stream] or STREAMS[1] end

local function Percent(s) return floor((tonumber(GetCVarValue(s.volume)) or 0) * 100 + 0.5) end
local function IsOn(s) return GetCVarValue(s.enable) ~= "0" end

local function StreamText(s)
    if not IsOn(s) then return "|cffff3333off|r" end
    return Percent(s) .. "%"
end

local function SetStream(key)
    DT.SetOption("volume", "stream", key)
    DT.Update("volume")
end

DT.Register("volume", {
    name   = "Volume",
    group  = "System",
    label  = "Volume",
    events = { "CVAR_UPDATE" },
    options = {
        { kind = "dropdown", key = "stream", label = "Sound stream", default = "master",
          options = (function()
              local list = {}
              for _, s in ipairs(STREAMS) do list[#list + 1] = { key = s.key, label = s.label } end
              return list
          end)() },
        { kind = "slider", key = "step", label = "Step per wheel notch", suffix = "%", min = 1, max = 20, step = 1, default = 5 },
    },
    Text = function(o)
        local s = Stream(o)
        local label = s.key == "master" and "Volume" or s.label
        return StreamText(s), label
    end,
    Tooltip = function(o, tt)
        DT.TipHeader(tt, "Volume")
        local cur = Stream(o)
        for _, s in ipairs(STREAMS) do
            local name = s == cur and ("> " .. s.label) or s.label
            DT.TipLine(tt, name, StreamText(s))
        end
        DT.TipSpace(tt)
        DT.TipNote(tt, "Wheel: change (Shift: 1%)    Click: stream    Middle-click: mute    Right-click: sound settings")
    end,
    Wheel = function(o, slot, delta)
        local s = Stream(o)
        local step = IsShiftKeyDown() and 1 or (o.step or 5)
        local v = Percent(s) + (delta > 0 and step or -step)
        if v < 0 then v = 0 elseif v > 100 then v = 100 end
        SetCVarValue(s.volume, v / 100)
    end,
    Click = function(o, slot, button)
        if button == "MiddleButton" then
            local master = STREAMS[1]
            SetCVarValue(master.enable, IsOn(master) and "0" or "1")
        elseif button == "RightButton" then
            if not InCombatLockdown() and Settings and Settings.OpenToCategory and Settings.AUDIO_CATEGORY_ID then
                Settings.OpenToCategory(Settings.AUDIO_CATEGORY_ID)
            end
        elseif button == "LeftButton" and MenuUtil then
            MenuUtil.CreateContextMenu(slot, function(_, root)
                root:CreateTitle("Sound stream")
                local function Is(key) return Stream(o).key == key end
                for _, s in ipairs(STREAMS) do root:CreateRadio(s.label, Is, SetStream, s.key) end
            end)
        end
    end,
})
