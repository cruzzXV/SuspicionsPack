-- SuspicionsPack Options — Auto release
--
-- The interesting part of this page is the reader card. Releasing is decided
-- boss by boss, so the feature is only as good as the list -- and a list you
-- have to fill by hunting IDs on a website is a list nobody fills. Reading the
-- current spot and adding it in one click turns it into something you do while
-- standing on the platform, between two pulls.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

local ROW_H = 26

-- Human-readable summary of one saved entry, used as its row label.
local function Describe(e)
    local bits = {}
    if e.subZone and e.subZone ~= "" then bits[#bits + 1] = e.subZone end
    if e.instanceID then bits[#bits + 1] = "instance " .. e.instanceID end
    if e.uiMapID    then bits[#bits + 1] = "map " .. e.uiMapID end
    return table.concat(bits, "  ·  ")
end

-- The entry list changes SHAPE, not just values, so the page is rebuilt rather
-- than refreshed. Through GUI:RebuildPage and not by clearing the cache here:
-- dropping a container that is still shown leaves it painted over every page
-- opened afterwards, which is exactly what happened the first time this was
-- three lines written by hand.
local function Rebuild()
    GUI:RebuildPage("autorelease")
end

-- One saved entry: its name, what it matches on, and a way to delete it.
local function EntryRow(parent, db, index)
    local e = db.zones[index]

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)

    local name = GUI.Text(row, 12, "textPrimary")
    name:SetPoint("LEFT", row, "LEFT", 14, 6)
    name:SetText(e.name and e.name ~= "" and e.name or "Unnamed spot")
    name:SetJustifyH("LEFT")

    local detail = GUI.Text(row, 10, "textMuted")
    detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    detail:SetText(Describe(e))
    detail:SetJustifyH("LEFT")

    local del = GUI.W.Button(row, {
        text  = "Remove",
        width = 78,
        onClick = function()
            table.remove(db.zones, index)
            Rebuild()
        end,
    })
    del:SetPoint("RIGHT", row, "RIGHT", -14, 0)

    return row
end

GUI.RegisterPage{
    id       = "autorelease",
    name     = "Release and rez",
    category = "combat",
    dbKey    = "autoRelease",
    keywords = "auto release resurrection rez accept corpse spirit graveyard run back death died pvp battleground " ..
               "arena raid boss zone subzone instance id tindral",
    build = function(parent)
        local page, db, c1 = GUI.ModulePage(parent, "autoRelease", "AutoRelease",
            "Release and rez",
            "Accepting resurrections, and releasing your spirit.",
            nil, "Resurrection")

        db.zones = db.zones or {}

        -- Two rows and not one, because the second IS the safety argument.
        local rezOn = c1:Toggle{
            key   = "acceptRez",
            label = "Auto accept resurrection",
            desc  = "Accepts a resurrection offer for you. Battle rezzes are left alone.",
        }
        c1:GateBelow(rezOn)
        c1:Toggle{
            key   = "onlyWhenFightOver",
            label = "Ignore anyone still fighting",
            desc  = "Normal resurrections cannot be cast in combat, so a caster who is " ..
                    "fighting is casting a battle rez. This is what separates the two.",
        }
        c1:EndGate()

        local cR = page:Card("Releasing")
        cR:Toggle{
            key   = "inPvP",
            label = "Release in battlegrounds and arenas",
            desc  = "Applies to all PvP instances, with no saved spot needed.",
        }
        cR:Slider{
            key = "delay", label = "Wait before releasing",
            min = 0, max = 10, step = 0.5, suffix = "s",
            desc = "If a resurrection arrives during the wait, the release is cancelled.",
        }

        -- ---- the reader ----------------------------------------------------
        local c2 = page:Card("Where you are standing",
            "The current zone and the IDs a saved spot matches on. " ..
            "Also available as /spack debug zoneid.")

        local read = CreateFrame("Frame", nil, c2.content)
        read:SetHeight(52)

        local line1 = GUI.Text(read, 12, "textPrimary")
        line1:SetPoint("TOPLEFT", read, "TOPLEFT", 14, -2)
        line1:SetJustifyH("LEFT")
        local line2 = GUI.Text(read, 10, "textMuted")
        line2:SetPoint("TOPLEFT", line1, "BOTTOMLEFT", 0, -3)
        line2:SetJustifyH("LEFT")

        local function ReadNow()
            local mod = SP.AutoRelease
            -- The RESULT is what has to be checked, not just the function. The
            -- module is load-order dependent and, when the pack is disabled,
            -- Describe can be present and still hand back nothing.
            local h = mod and mod.Describe and mod.Describe()
            if type(h) ~= "table" then
                line1:SetText("Location unavailable")
                line2:SetText("The auto release module is not running.")
                return nil
            end
            h.zone    = h.zone    or ""
            h.subZone = h.subZone or ""
            local where = h.subZone ~= "" and (h.zone .. " — " .. h.subZone) or h.zone
            line1:SetText(where ~= "" and where or "Unknown")
            line2:SetText(("instanceID %s   ·   uiMapID %s   ·   %s")
                :format(tostring(h.instanceID), tostring(h.uiMapID), h.instanceType))
            return h
        end
        ReadNow()
        c2:Custom(read, 52)

        c2:ButtonRow{
            text = "Add this spot",
            desc = "Saves the current zone, subzone and IDs to the list below.",
            width = 120,
            onClick = function()
                local h = ReadNow()
                if not h then return end
                -- An entry with nothing to match on would fire everywhere,
                -- including mid-encounter. The module refuses those; refuse to
                -- create one in the first place.
                if not (h.instanceID or h.uiMapID or (h.subZone or "") ~= "") then return end
                db.zones[#db.zones + 1] = {
                    name       = (h.subZone ~= "" and h.subZone) or h.zone or "Spot",
                    instanceID = h.instanceID,
                    uiMapID    = h.uiMapID,
                    subZone    = h.subZone ~= "" and h.subZone or nil,
                    enabled    = true,
                }
                Rebuild()
            end,
        }
        c2:ButtonRow{
            text = "Refresh",
            width = 120,
            onClick = function() ReadNow() end,
        }

        -- Re-read whenever the page is shown: you walked somewhere between
        -- opening the window last time and now.
        parent._onPageShow = ReadNow

        -- ---- the list ------------------------------------------------------
        local c3 = page:Card("Release at these spots",
            #db.zones > 0 and "Checked in order. A spot saved without a subzone covers the whole raid."
                          or nil)
        if #db.zones == 0 then
            c3:Note("No spots saved. Stand somewhere releasing is preferable to waiting " ..
                    "— Tindral's platform, for instance — and press Add this spot.")
        else
            for i = 1, #db.zones do
                c3:Custom(EntryRow(c3.content, db, i), ROW_H)
            end
        end

        page:Finish()
    end,
}
