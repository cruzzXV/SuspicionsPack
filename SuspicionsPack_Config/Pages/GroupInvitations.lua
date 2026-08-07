-- SuspicionsPack Options — Group invitations
--
-- Two modules on one page: the keyword-driven auto invite (autoInvite) and the
-- three auto-accept switches that belong to Automation. Only the first card
-- follows the master toggle, which is why this page is built by hand instead of
-- through GUI.ModulePage -- GateAll would drag the Automation card off with it.

local ADDON, ns = ...
local GUI = ns.GUI
local SP  = SuspicionsPack

-- The keyword list is stored as an array of words; the edit box shows it as one
-- comma-separated line. Both halves of that marshalling live here so the widget
-- can be a plain get/set binding.
local function KeywordsToStr(kws)
    return table.concat(kws or {}, ", ")
end

local function StrToKeywords(str)
    local kws = {}
    for part in (str or ""):gmatch("[^,]+") do
        local kw = part:match("^%s*(.-)%s*$")
        if kw ~= "" then kws[#kws + 1] = kw end
    end
    return kws
end

GUI.RegisterPage{
    id       = "invitationgroupe",
    name     = "Group invitations",
    category = "social",
    dbKey    = "autoInvite",
    keywords = "invite invitation group party keyword whisper guild friends role check auto accept leader",
    build = function(parent)
        local db    = SP.GetDB().autoInvite
        local dbAut = SP.GetDB().automation
        local page  = GUI.NewPage(parent, db, GUI.Applier("AutoInvite"), "autoInvite")

        -- Built by hand rather than through GUI.ModulePage, because ModulePage
        -- calls GateAll and the auto-accept switches further down belong to the
        -- Automation module, not to this one. The header still carries the
        -- master switch, so the page looks like every other module page.
        local _, master = page:Header("Group invitations",
            "Invites anyone who whispers you one of your keywords. Only fires " ..
            "while you are the group leader or on your own.", {
                key      = "enabled",
                db       = db,
                default  = page.defaults and page.defaults.enabled,
                onChange = GUI.Applier("AutoInvite"),
                onToggle = function(v) GUI.UpdateDots(); GUI.Toast("Group invitations", v) end,
            })

        local c1 = page:Card("Auto invite")
        c1:GateBelow(master)

        -- Stored as `inviteAll`, shown inverted. A gate follows a toggle that is
        -- ON, and the friends/guild switches only matter while "invite anyone" is
        -- OFF, so the row that owns the gate is the inverse of the stored flag.
        --
        -- get/set means Fill cannot look the default up from SP.DEFAULTS, and a
        -- binding with no default reports IsDefault() == true for ever: the row
        -- was invisible to the footer's change count and to "Reset page". The
        -- default is stated here, inverted the same way the value is.
        local restrict = c1:Toggle{
            label   = "Restrict who gets invited",
            desc    = "Off invites anyone who whispers a keyword.",
            default = not (page.defaults and page.defaults.inviteAll),
            get     = function() return not db.inviteAll end,
            set     = function(v) db.inviteAll = not v end,
        }

        c1:GateBelow(restrict)
        c1:Toggle{ key = "inviteFriends", label = "Invite friends" }
        c1:Toggle{ key = "inviteGuild",   label = "Invite guild members" }

        c1:GateBelow(master)
        -- Same story as the row above: the array lives behind get/set, so the
        -- default has to be marshalled to the same shape the widget sees.
        c1:EditBox{
            label   = "Keywords",
            desc    = "Comma-separated. Exact match, case-insensitive.",
            default = KeywordsToStr(page.defaults and page.defaults.keywords),
            get     = function() return KeywordsToStr(db.keywords) end,
            set     = function(v) db.keywords = StrToKeywords(v) end,
            maxLen  = 200,
        }
        c1:EndGate()

        -- These three write to the Automation profile section, so the card points
        -- its default lookup there too.
        local autoDefaults = SP.DEFAULTS and SP.DEFAULTS.profile and SP.DEFAULTS.profile.automation
        local applyAut     = GUI.Applier("Automation")

        local c2 = page:Card("Auto accept",
            "Answers invitation and role popups for you. These belong to the " ..
            "Automation module and are not affected by the switch above.",
            autoDefaults)

        c2:Toggle{
            db = dbAut, key = "autoRoleCheck",
            label = "Auto role check",
            desc  = "Accepts LFD and LFG role check popups the moment they appear.",
            onChange = function(v)
                applyAut()
                -- The accept runs off a permanent hook, so switching it back off
                -- only takes full effect after a reload.
                if not v then
                    SP.CreateReloadPrompt("Disabling Auto Role Check requires a reload to take full effect.")
                end
            end,
        }
        c2:Toggle{
            db = dbAut, key = "autoGuildInvite",
            label = "Auto guild invite",
            desc  = "Accepts group invitations from your guildmates.",
            onChange = applyAut,
        }
        c2:Toggle{
            db = dbAut, key = "autoFriendInvite",
            label = "Auto friend invite",
            desc  = "Accepts group invitations from your friends.",
            onChange = applyAut,
        }

        page:Finish()
    end,
}
