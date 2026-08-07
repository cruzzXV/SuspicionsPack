# SuspicionsPack options UI — how to write a page

One file per page in `Pages/`, listed in the `.toc`. A page registers itself:

```lua
local ADDON, ns = ...
local GUI = ns.GUI

GUI.RegisterPage{
    id       = "durability",        -- unique; also the page cache key
    name     = "Repair warning",    -- sidebar label and breadcrumb
    category = "items",             -- general | combat | mythic | items | social | interface | customise
    dbKey    = "durability",        -- profile section; drives the sidebar on/off dot
    charDB   = true,                -- only if the module stores per-character
    keywords = "durability repair gear threshold",   -- extra search terms
    build    = function(parent) ... end,
}
```

## The page skeleton

```lua
build = function(parent)
    local page, db, c1, master = GUI.ModulePage(parent, "durability", "Durability",
        "Repair warning",                                   -- card title
        "Shows a warning when your gear drops below the threshold.",  -- card description
        "Enable repair warning")                            -- master toggle label

    c1:Slider{ key = "threshold", label = "Warning threshold", suffix = "%",
               min = 1, max = 100, step = 1 }

    local c2 = page:Card("Appearance")
    c2:FontDropdown{ key = "fontFace", label = "Font face" }

    page:Finish()
end
```

`GUI.ModulePage` returns `page, db, firstCard, masterToggle`. It puts the page's
name and blurb in a **header block above the cards**, with the master switch on
the right, and calls `page:GateAll(master)` so everything else follows it. The
card it returns is a plain settings group titled "General" — pass a 7th argument
to rename it. Always end with `page:Finish()`.

For a page with no module behind it (documentation, themes), build the page by
hand instead:

```lua
local page = GUI.NewPage(parent, db, applyFn, "dbKey")
```

## Layout

Every row is **one line**: label (and its description) on the left, control on
the right. Widgets size their own control column; a row is 32px, or 47px with a
description. Card titles are quiet uppercase group labels, not headings — the
page's own name lives in the header block.

## Rules

- **Never pass a height.** Widgets declare `row.h`; the card stacks them.
- **Never add a separator.** One is drawn between consecutive rows automatically.
- **Never write `default = ...` for a key that exists in `SP.DEFAULTS`.** The
  default is looked up from `SP.DEFAULTS.profile[dbKey][key]`. Only pass
  `default` explicitly when the key is genuinely missing from `SP.DEFAULTS`.
- **Never build enable cascades by hand.** No `childRows`, no `childCards`, no
  `GrayContent`. Use `page:GateAll(toggle)` and `card:GateBelow(toggle)`.
- **Sentence case for labels.** "Font size", not "Font Size".
- Descriptions (`desc = "..."`) render under the label. Prefer one over a tooltip.

## Widgets

All of these are methods on a card. `db` and `onChange` are filled in from the
page; override them per-row only when the value lives somewhere else.

```lua
c:Toggle{ key=, label=, desc=, onToggle=function(v) end }
c:Slider{ key=, label=, desc=, min=, max=, step=, suffix="%" }
c:Dropdown{ key=, label=, desc=, options={"A","B"} }         -- or {{key=,label=},...}
c:Dropdown{ key=, label=, optionsFn=function() return {...} end }  -- re-read on refresh
c:FontDropdown{ key=, label= }
c:EditBox{ key=, label=, desc=, maxLen=64 }
c:Color{ key=, label=, desc=, alpha=true }
c:ColorSource{ label=, srcKey="colorSource", colorKey="color" }
c:DualColor{ a={ key=, label= }, b={ key=, label= } }
c:AnchorRow{ }                       -- anchorFrom/anchorTo/anchorFrame/frameStrata
c:AnchorRow{ fromKey="timerAnchorFrom", toKey=..., frameKey=..., strata=false }
c:ButtonRow{ text=, desc=, onClick=function() end, width= }
c:Note("Explanatory paragraph.")
c:Custom(frame, height)              -- escape hatch, see below
c:Pair(specA, specB, weightA)        -- two controls on one line
```

`Pair` takes specs with a `kind`:

```lua
c:Pair({ kind = "slider",   key = "fontSize", label = "Font size", min = 8, max = 60 },
       { kind = "dropdown", key = "outline",  label = "Outline", options = GUI.OUTLINES },
       0.55)
```

Shared option lists: `GUI.OUTLINES`, `GUI.CHANNELS`.

## Gating

```lua
page:GateAll(master)      -- everything on the page follows this toggle
card:GateBelow(sub)       -- rows added after this call, in this card, follow `sub`
card:EndGate()            -- stop the GateBelow
```

Gates compose: a row under both a page gate and a sub-gate is enabled only when
both are on. Gating disables input, not just alpha, and a card whose rows are
all disabled gets an invisible mouse blocker over it.

## Nested settings tables

Point the card's DB *and* its default source one level down:

```lua
db.backdrop = db.backdrop or {}
local bdDefaults = SP.DEFAULTS.profile.combatTimer.backdrop
local c = page:Card("Backdrop", "A panel behind the text.", bdDefaults)
c:Slider{ db = db.backdrop, key = "borderSize", label = "Border size", min = 1, max = 10 }
```

## Custom frames

`c:Custom(frame, height)` stacks any frame. It is given no-op `SetEnabled`,
`Refresh`, `IsModified`, `ResetDefault` and `Sync` if it does not define them,
so it participates in gating and reset without crashing. Define the ones that
mean something for your frame.

If your custom frame **starts anything that outlives the page** — a sound, an
on-screen preview, a screen-picking mode, a registered event — clean it up:

```lua
parent:HookScript("OnHide", function() ... end)
```

Only one page in the previous UI did this, and the ones that did not left sound
previews playing and event frames registered forever.

## Widget contract

Every row satisfies:

| member | meaning |
|---|---|
| `row.h` | natural height; the layout reads this |
| `row:SetEnabled(en)` | **blocks input**, not just alpha |
| `row:Refresh()` | re-reads the bound value from the DB |
| `row:IsModified()` | bound value differs from its default |
| `row:ResetDefault()` | |
| `row.searchText` | lowercased label + description, for the search index |

## Theme

Never set a colour directly. Register a painter:

```lua
GUI.Paint(frame, function(f, T)
    f:SetBackdropColor(T.bgLight[1], T.bgLight[2], T.bgLight[3], 0.9)
end)
```

The closure runs immediately and again on every preset change. Read colours from
the `T` argument; capturing `T.accent[1]` into a local defeats the mechanism.

Helpers: `GUI.Text(parent, size, colorKey)`, `GUI.Tex(parent, layer, colorKey, alpha)`,
`GUI.Backdrop(frame, bgKey, bgAlpha, borderKey, borderAlpha, style)`,
`GUI.RoundTex(parent, layer, style, isBorder)`, `GUI.CircleTex(parent, layer)`,
`GUI.HoverBorder(frame)`, `GUI.Tooltip(frame, title, body)`.

## Rounded corners

`SetBackdrop` cannot draw a radius, so `GUI.Backdrop` builds a nine-sliced fill
and outline instead. `style` is one of `square`, `rr4`, `rr6`, `rr10`, `pill`.

Everything in the window is rounded: `rr4` for controls, `rr6` for cards and
inset panels, `rr10` for the window, `pill` for the toggle track. `square` is
kept for anything that has to line up with a Blizzard frame, and is currently
unused.

**The element must be at least twice the style's slice margin in BOTH
dimensions** (`rr4` needs 16x16, `rr6` 24x24, `rr10` 40x40, `pill` 16x16).
Below that WoW has no centre strip left to stretch and draws the texture
*outside* the frame — which is how a 3px rule ended up as a red bar running off
the side of the window. A few-pixel bar cannot be sliced at all; draw it flat
with `GUI.Tex`. `GUI.AuditSlices()` returns every violation and the harness
asserts it is empty.

## Testing a page offline

```
cd /tmp/h && CFG="<path>/SuspicionsPack_Config" python3 run.py dbg.lua
```

Builds every registered page against a stubbed WoW API and prints its height.
A page that reports an error, or a height of 1, is broken.
