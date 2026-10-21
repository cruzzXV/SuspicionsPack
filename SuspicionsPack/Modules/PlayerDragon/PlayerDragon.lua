-- SuspicionsPack — PlayerDragon Module
--
-- Draws the dragon the target frame wears for a rare, elite or boss mob
-- around the player's portrait, mirrored so it faces outward on the left side.
--
-- The art and its placement are Blizzard's own, per art set:
--   retail 12.1.5  Blizzard_UnitFrame/Mainline/TargetFrame.lua, CheckClassification
--   Forever 1.60.1 Blizzard_UnitFrame/Camelot/TargetFrameUtils.lua, GetBossPortraitFrameData
-- Forever ships its own art under the same names (the "-c60" atlases) and a
-- winged silver dragon that retail does not have. Each offset is where Blizzard
-- puts the dragon's TOPRIGHT on TargetFrameContainer.
--
-- TWO PLAYER FRAMES
--   Blizzard's PlayerFrame: the texture lives on PlayerFrameContainer, where
--   the target keeps its own dragon (BossPortraitFrameTexture). The level
--   badge, the rest and combat icons are on PlayerFrameContent and stay drawn
--   over it, as they are on the target.
--   EllesmereUI's player frame under its stock looks ("Blizzard Style", "WoW
--   Forever"), which hides Blizzard's: the texture lives on its art frame, at
--   the layer its own target dragon uses (over the frame art, under the bars
--   and the level badge). Its own look and its "Classic WoW UI" one have no
--   such ring, and EllesmereUI has a Player Frame Dragon of its own there.
--   Each frame gets its dragon; one hidden by another addon hides it too.
--
-- AnimatedPortraits slides its models one strata under the frame, so the
-- dragon is over them on both.
local SP = SuspicionsPack

local PD = SP:NewSPModule("PlayerDragon", "playerDragon")
SP.PlayerDragon = PD

local IS_FOREVER = (WOW_PROJECT_CAMELOT ~= nil) and (WOW_PROJECT_ID == WOW_PROJECT_CAMELOT)

-- art set -> style -> { atlas, x, y }
local ART = {
    forever = {
        silver = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged", 8, -7 },
        gold   = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold", 0, 1 },
        boss   = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", 11, -4 },
    },
    retail = {
        silver = { "ui-hud-unitframe-target-portraiton-boss-rare-silver", -11, -8 },
        gold   = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold", -11, -8 },
        boss   = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", 8, -8 },
    },
}

-- Centre of the target portrait from TargetFrameContainer's TOPRIGHT: the
-- 58 px portrait is anchored TOPRIGHT -26, -19 (TargetFrame.xml, both clients,
-- and EllesmereUI's stock kits).
local TARGET_PORTRAIT_X = 26 + 29
local TARGET_PORTRAIT_Y = 19 + 29

local blizzDragon, euiDragon     -- one texture per frame, created on first need
local vehicleHooked = false
local euiHooked = setmetatable({}, { __mode = "k" })   -- [backdrop] = true

-- Paints `tex` with this style's art from `set` round `portrait`: facing
-- outward on the left, or the target's own way when the portrait is on the
-- right. `getInfo` reads the atlas. False, hidden, when the client lacks it.
local function Paint(tex, set, getInfo, portrait, right)
    local art = ART[set][PD:GetDB().style] or ART[set].silver
    local atlas, x, y = art[1], art[2], art[3]
    local info = getInfo(atlas)
    if not info then
        tex:Hide()
        return false
    end
    -- The atlas's file and box, not SetAtlas: on an atlas texture SetTexCoord
    -- reads inside the atlas box, so the reversed box would sample other art.
    tex:SetTexture(info.file or info.filename)
    local l, r = info.leftTexCoord, info.rightTexCoord
    if not right then l, r = r, l end
    tex:SetTexCoord(l, r, info.topTexCoord, info.bottomTexCoord)
    tex:SetSize(info.width, info.height)
    -- The target's offset from its portrait's centre, mirrored on the left.
    tex:ClearAllPoints()
    if right then
        tex:SetPoint("TOPRIGHT", portrait, "CENTER", x + TARGET_PORTRAIT_X, y + TARGET_PORTRAIT_Y)
    else
        tex:SetPoint("TOPLEFT", portrait, "CENTER", -(x + TARGET_PORTRAIT_X), y + TARGET_PORTRAIT_Y)
    end
    return true
end

-- ============================================================
-- Blizzard's PlayerFrame
-- ============================================================
local function UpdateBlizzard()
    if not blizzDragon then return end
    local vehicle = PlayerFrame.PlayerFrameContainer.VehicleFrameTexture
    -- The vehicle frame has a ring of its own; the dragon is not drawn for it.
    if not PD:IsOn() or (vehicle and vehicle:IsShown()) then
        blizzDragon:Hide()
        return
    end
    blizzDragon:Show()
end

local function ApplyBlizzard()
    local container = PlayerFrame and PlayerFrame.PlayerFrameContainer
    local portrait = container and container.PlayerPortrait
    if not portrait then return end
    if not blizzDragon then
        -- Over the combat glow (OVERLAY 0), as the target's dragon is over its flash.
        blizzDragon = container:CreateTexture(nil, "OVERLAY", nil, 1)
    end
    if not vehicleHooked then
        vehicleHooked = true
        -- Never removed: UpdateBlizzard reads the live setting.
        hooksecurefunc("PlayerFrame_ToVehicleArt", UpdateBlizzard)
        hooksecurefunc("PlayerFrame_ToPlayerArt", UpdateBlizzard)
    end
    if Paint(blizzDragon, IS_FOREVER and "forever" or "retail", C_Texture.GetAtlasInfo,
             portrait, false) then
        UpdateBlizzard()
    end
end

-- ============================================================
-- EllesmereUI's player frame (EllesmereUIUnitFrames 9.6.1, read not run:
-- EUI_UnitFrames_StockStyles.lua). Its stock pass stamps the kit geometry on
-- the frame (_blizzGeom), builds the art frame (_blizzArtFrame, one level
-- under the bars) and then lays the portrait backdrop out. A string art is a
-- stock kit; the Classic kit draws a file. A portrait on the right takes the
-- target's layout: full frames are never mirrored there.
-- ============================================================
local function ApplyEllesmere()
    local f = _G.EllesmereUIUnitFrames_Player
    local bd = f and f.Portrait and f.Portrait.backdrop
    if bd and not euiHooked[bd] then
        euiHooked[bd] = true
        -- Every layout pass ends on the backdrop's SetPoint, after the art
        -- frame exists: login, settings changes, Portrait Side. Never removed.
        hooksecurefunc(bd, "SetPoint", ApplyEllesmere)
    end
    local G, af = f and f._blizzGeom, f and f._blizzArtFrame
    if not (PD:IsOn() and bd and af and G and G.portrait and type(G.art) == "string") then
        if euiDragon then euiDragon:Hide() end
        return
    end
    if not euiDragon or euiDragon:GetParent() ~= af then
        if euiDragon then euiDragon:Hide() end
        -- The layer of EllesmereUI's own target dragon: over its art (BACKGROUND 0).
        euiDragon = af:CreateTexture(nil, "BACKGROUND", nil, 2)
        -- Unsnapped like the art it sits on, so both scale alike.
        euiDragon:SetSnapToPixelGrid(false)
        euiDragon:SetTexelSnappingBias(0)
    end
    -- Only the WoW Forever kit has a level badge. The retail look on the
    -- Forever client draws the retail sheets: EllesmereUI reads those for us.
    local set = G.badge and "forever" or "retail"
    local getInfo = C_Texture.GetAtlasInfo
    if set == "retail" and EllesmereUI and EllesmereUI.StockAtlasInfo then
        getInfo = EllesmereUI.StockAtlasInfo
    end
    if Paint(euiDragon, set, getInfo, bd, G.portrait.point == "TOPRIGHT") then
        euiDragon:Show()
    end
end

-- ============================================================
-- Activate / Deactivate
-- Everything else (Refresh / OnEnable / OnDisable) comes from SP.ModuleMixin.
-- ============================================================
function PD:Activate()
    ApplyBlizzard()
    ApplyEllesmere()
    -- EllesmereUI may build its frames after this ran; the backdrop hook takes
    -- over from the first world entry on.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", ApplyEllesmere)
end

function PD:Deactivate()
    if blizzDragon then blizzDragon:Hide() end
    if euiDragon then euiDragon:Hide() end
end
