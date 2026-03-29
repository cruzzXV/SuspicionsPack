-- SuspicionsPack — SilvermoonMapIcon Module
-- Source data (coords, atlas icons, profession logic) from Sakuria.
-- World map only — no minimap pins.
local SP = SuspicionsPack

local SMI = SP:NewModule("SilvermoonMapIcon", "AceEvent-3.0")
SP.SilvermoonMapIcon = SMI

-- ============================================================
-- Constants
-- ============================================================
local SILVERMOON_MAP_ID = 2393
local WORLD_SCALE       = 0.65  -- multiplier on top of each pin's own scale value

-- ============================================================
-- DB
-- ============================================================
local function GetDB()
    return SP.GetDB().silvermoonMapIcon
end

local function IsEnabled()
    local db = GetDB()
    return db and db.enabled
end

-- ============================================================
-- Profession detection (verbatim from Sakuria / HandyNotes)
-- ============================================================
local professionToSkillLine = {
    ["Fishing"]        = 356,
    ["Cooking"]        = 185,
    ["Mining"]         = 186,
    ["Engineering"]    = 202,
    ["Leatherworking"] = 165,
    ["Blacksmithing"]  = 164,
    ["Tailoring"]      = 197,
    ["Herbalism"]      = 182,
    ["Inscription"]    = 773,
    ["Jewelcrafting"]  = 755,
    ["Enchanting"]     = 333,
    ["Alchemy"]        = 171,
    ["Skinning"]       = 393,
}

local playerProfessions = {}

local function UpdatePlayerProfessions()
    wipe(playerProfessions)
    local p1, p2, _, fish, cook = GetProfessions()
    for _, prof in ipairs({ p1, p2, fish, cook }) do
        if prof then
            local name, _, _, _, _, _, skillLine = GetProfessionInfo(prof)
            playerProfessions[skillLine] = name
        end
    end
end

-- ============================================================
-- Source POI data — verbatim from Sakuria, never mutated
-- ============================================================
local SOURCE_DB = {
    [2393] = {
        { x = 0.363, y = 0.846, atlas = "CrossedFlags",                      title = "Training Dummies",               scale = 3   },
        { x = 0.400, y = 0.837, atlas = "CrossedFlags",                      title = "Training Dummies",               scale = 3   },
        { x = 0.426, y = 0.787, atlas = "Barbershop-32x32",                  title = "Barbershop",                     scale = 3   },
        { x = 0.509, y = 0.759, atlas = "Auctioneer",                        title = "Auction House",                  scale = 3   },
        { x = 0.507, y = 0.652, atlas = "Banker",                            title = "Bank",                           scale = 3   },
        { x = 0.536, y = 0.446, atlas = "StableMaster",                      title = "Stable Master",                  scale = 3   },
        { x = 0.527, y = 0.575, atlas = "poi-transmogrifier",                title = "Transmogrifier",                 scale = 2   },
        { x = 0.486, y = 0.618, atlas = "UpgradeItem-32x32",                 title = "Item Upgrades & Crest Exchange", scale = 3   },
        { x = 0.562, y = 0.701, atlas = "Innkeeper",                         title = "Innkeeper",                      scale = 3   },
        { x = 0.404, y = 0.648, atlas = "CreationCatalyst-32x32",            title = "Catalyst",                       scale = 3   },
        { x = 0.423, y = 0.582, atlas = "ChromieTime-32x32",                 title = "Timeways Portals",               scale = 3   },
        { x = 0.451, y = 0.556, atlas = "Professions-Crafting-Orders-Icon",  title = "Crafting Orders",                scale = 2.5 },
        { x = 0.521, y = 0.743, atlas = "dragon-rostrum",                    title = "Rostrum",                        scale = 3   },
        -- Profession trainers
        { x = 0.447, y = 0.603, atlas = "Professions_Tracking_Fish",         title = "Fishing",        scale = 2,   type = "Fishing"        },
        { x = 0.562, y = 0.701, atlas = "Food",                              title = "Cooking",        scale = 2,   type = "Cooking"        },
        { x = 0.426, y = 0.529, atlas = "worldquest-icon-mining",            title = "Mining",         scale = 4,   type = "Mining"         },
        { x = 0.436, y = 0.538, atlas = "worldquest-icon-engineering",       title = "Engineering",    scale = 4,   type = "Engineering"    },
        { x = 0.432, y = 0.557, atlas = "worldquest-icon-leatherworking",    title = "Leatherworking", scale = 4,   type = "Leatherworking" },
        { x = 0.438, y = 0.518, atlas = "worldquest-icon-blacksmithing",     title = "Blacksmith",     scale = 4,   type = "Blacksmithing"  },
        { x = 0.480, y = 0.542, atlas = "worldquest-icon-tailoring",         title = "Tailoring",      scale = 4,   type = "Tailoring"      },
        { x = 0.481, y = 0.515, atlas = "worldquest-icon-herbalism",         title = "Herbalism",      scale = 4,   type = "Herbalism"      },
        { x = 0.466, y = 0.515, atlas = "worldquest-icon-inscription",       title = "Inscription",    scale = 4,   type = "Inscription"    },
        { x = 0.480, y = 0.549, atlas = "worldquest-icon-jewelcrafting",     title = "Jewelcrafting",  scale = 4,   type = "Jewelcrafting"  },
        { x = 0.478, y = 0.536, atlas = "worldquest-icon-enchanting",        title = "Enchanting",     scale = 4,   type = "Enchanting"     },
        { x = 0.470, y = 0.521, atlas = "worldquest-icon-alchemy",           title = "Alchemy",        scale = 4,   type = "Alchemy"        },
        { x = 0.432, y = 0.557, atlas = "worldquest-icon-skinning",          title = "Skinning",       scale = 4,   type = "Skinning"       },
        { x = 0.524, y = 0.780, atlas = "poi-islands-table",                 title = "Delves",         scale = 3                           },
        { x = 0.342, y = 0.811, atlas = "honorsystem-icon-prestige-9",       title = "PvP Vendor",     scale = 0.8                         },
    },
}

-- ============================================================
-- Shared filter — returns the list of source entries to show
-- ============================================================
local function GetVisibleSources()
    local points  = SOURCE_DB[SILVERMOON_MAP_ID]
    local db      = GetDB()
    local proOnly = db and db.showOnlyProfessions
    local result  = {}
    for _, src in ipairs(points) do
        local hide = false
        if proOnly and src.type then
            local skill = professionToSkillLine[src.type]
            if skill and not playerProfessions[skill] then
                hide = true
            end
        end
        if not hide then
            table.insert(result, src)
        end
    end
    return result
end

-- ============================================================
-- Anti-overlap — shallow copies, SOURCE_DB never mutated
-- ============================================================
local function BuildAdjustedPoints(sourceList)
    local pts = {}
    for i, src in ipairs(sourceList) do
        pts[i] = { x = src.x, y = src.y, _src = src }
    end
    local minDist = 0.015
    for _ = 1, 6 do
        for i = 1, #pts do
            for j = i + 1, #pts do
                local p1, p2 = pts[i], pts[j]
                local dx   = p1.x - p2.x
                local dy   = p1.y - p2.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < minDist then
                    local angle = math.atan2(dy, dx)
                    if angle ~= angle then angle = math.random() * math.pi * 2 end
                    local push = (minDist - dist) * 0.5
                    p1.x = math.min(math.max(p1.x + math.cos(angle) * push, 0.01), 0.99)
                    p1.y = math.min(math.max(p1.y + math.sin(angle) * push, 0.01), 0.99)
                    p2.x = math.min(math.max(p2.x - math.cos(angle) * push, 0.01), 0.99)
                    p2.y = math.min(math.max(p2.y - math.sin(angle) * push, 0.01), 0.99)
                end
            end
        end
    end
    return pts
end

-- ============================================================
-- World Map — MapCanvasPinMixin pins (from Sakuria)
-- WORLD_SCALE applied on top of each pin's own scale value.
-- ============================================================
local function CreateWorldPin(map, src)
    local pin = CreateFrame("Frame", nil, map)
    Mixin(pin, MapCanvasPinMixin)
    if pin.OnLoad then pin:OnLoad() end

    pin.owningMap = map
    pin:EnableMouse(true)
    pin:SetMouseClickEnabled(true)
    pin:SetMouseMotionEnabled(true)
    pin:UseFrameLevelType("PIN_FRAME_LEVEL_MAP_PIN")

    pin:SetScript("OnEnter", function()
        GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
        GameTooltip:SetText(src.title)
        GameTooltip:Show()
    end)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)

    pin:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        local mapID = map:GetMapID()
        if mapID ~= SILVERMOON_MAP_ID then return end
        local wp = UiMapPoint.CreateFromCoordinates(mapID, src.x, src.y)
        C_Map.SetUserWaypoint(wp)
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end)

    local info = src.atlas and src.atlas ~= "" and C_Texture.GetAtlasInfo(src.atlas)
    if info then
        pin:SetSize(info.width, info.height)
    else
        pin:SetSize(24, 24)
    end

    pin.tex = pin:CreateTexture(nil, "ARTWORK")
    pin.tex:SetAllPoints()
    if src.atlas and src.atlas ~= "" then
        pin.tex:SetAtlas(src.atlas)
    end

    pin:SetScale((src.scale or 1) * WORLD_SCALE)

    src.pin = pin
    return pin
end

local function UpdateWorldMap(map)
    local uiMapID = map:GetMapID()
    local points  = SOURCE_DB[uiMapID]
    if not points then return end

    UpdatePlayerProfessions()

    for _, src in ipairs(points) do
        if src.pin then src.pin:Hide() end
    end

    local visible  = GetVisibleSources()
    local adjusted = BuildAdjustedPoints(visible)
    for _, pt in ipairs(adjusted) do
        local src = pt._src
        local pin = src.pin or CreateWorldPin(map, src)
        pin:SetPosition(pt.x, pt.y)
        pin:Show()
    end
end

local function SetupWorldMap(map)
    if map.SP_SilvermoonMapIconsProvider then return end

    local Provider = CreateFromMixins(MapCanvasDataProviderMixin)

    function Provider:RemoveAllData()
        for _, points in pairs(SOURCE_DB) do
            for _, src in ipairs(points) do
                if src.pin then src.pin:Hide() end
            end
        end
    end

    function Provider:RefreshAllData()
        self:RemoveAllData()
        if not IsEnabled() then return end
        UpdateWorldMap(self:GetMap())
    end

    map:AddDataProvider(Provider)
    map.SP_SilvermoonMapIconsProvider = Provider
    SMI._provider = Provider
end

-- ============================================================
-- Module lifecycle
-- ============================================================
function SMI:OnEnable()
    if IsLoggedIn() then
        self:OnLogin()
    else
        self:RegisterEvent("PLAYER_LOGIN", "OnLogin")
    end
end

function SMI:OnDisable()
    self:UnregisterAllEvents()
    if self._provider then self._provider:RefreshAllData() end
end

function SMI:OnLogin()
    self:UnregisterEvent("PLAYER_LOGIN")

    -- World map data provider (idempotent)
    if WorldMapFrame then SetupWorldMap(WorldMapFrame) end

    -- Refresh profession filter when player learns/drops a profession
    self:RegisterEvent("SKILL_LINES_CHANGED", "OnSkillLinesChanged")
end

-- SKILL_LINES_CHANGED fires when you learn or drop a profession.
-- Refresh the world map so trainer pins appear/disappear correctly.
function SMI:OnSkillLinesChanged()
    UpdatePlayerProfessions()
    if self._provider then self._provider:RefreshAllData() end
end

-- ============================================================
-- Public API — called by GUI toggles
-- ============================================================
function SMI.Refresh()
    local db  = GetDB()
    local mod = SP.SilvermoonMapIcon
    if db and db.enabled then
        if not mod:IsEnabled() then mod:Enable() end
    else
        if mod:IsEnabled() then mod:Disable() end
    end
    if mod._provider then mod._provider:RefreshAllData() end
end

function SMI.RefreshPins()
    local mod = SP.SilvermoonMapIcon
    if mod._provider then mod._provider:RefreshAllData() end
end
