# Macro Action Bar in SuspicionsPack

This folder is a fork of **Macro Action Bar v1.2.1** by NotStraws (https://github.com/notstraws/MacroActionBar),
MIT licensed: see `LICENSE` here, and `Data/LICENSE` for the trainer data. The spellbook tab library it uses is in
`SuspicionsPack/Libs/LibSpellBookTabs-1.0/`, unchanged (MINOR 7), with the same MIT notice.

It runs on WoW: Forever only, as the pack's "Macro Action Bar" module, off by default (Interface > Macro Action Bar,
or `/spack macros` to open the spellbook on its page).

## What changed from the original

Every file keeps the original's code except for the changes below, so a later upstream fix can be carried over by
diffing upstream against 1.2.1 and applying the same hunks here.

| File | Change |
|---|---|
| `MacroActionBar.lua` | New: the module shell. Makes the shared table (`SuspicionsPack.MAB`), binds the saved data, runs every file's setup once at login, asks for a reload when switched on or off later, stays off while the original addon is loaded. |
| `Spells.lua`, `Locale.lua` | New: clients in other languages. The class files and a few words in `Macros.lua` name spells in English; `Locale.lua` turns them into the client's names through their spell IDs (`Spells.lua`, generated from the game's data by `tests/gen_mab_spells.lua`, not shipped). Nothing changes on an English client. |
| every file | Line 1 `local _, smb = ...` (or `local addonName, smb = ...`) is `local smb = SuspicionsPack.MAB`. |
| `Macros.lua`, `Cleanup.lua` | `addonName` is `smb.TITLE` ("Macro Action Bar"), for messages. The scan tooltip is named after `smb.ID`. |
| `SpellBookTab.lua` | `addonName` is `smb.ID`, the spellbook tab's id. |
| `Macros.lua`, `Cleanup.lua`, `ActionBars.lua`, `Trainer.lua` | `MacroActionBarDB` is `smb.accountDB` (the pack's `global.macroActionBar`), `MacroActionBarCharDB` is `smb.charDB` (the pack's `char.macroActionBar`). |
| `Macros.lua` | The `ADDON_LOADED` loader runs from `smb.onInstall`; a new character is `next(smb.charDB) == nil`, since the pack always keeps a table. "Auto Shot", "Ice Block" and the Warrior stances go through `smb.L`, "(Rank 1)" through `smb.rankOne`, the tooltip's "Requires" through `smb.requiresText`, a summon's pet family through `smb.petFamilyName`. |
| `Trainer.lua`, `Cleanup.lua`, `ActionBars.lua`, `SpellBookTab.lua` | Events, hooks and the tab registration are set up in `smb.onInstall`, not as the file loads. `ActionBars.lua` runs its `PLAYER_LOGIN` step directly, since the pack installs during `PLAYER_LOGIN`. |
| same | `OnEvent` scripts, `hooksecurefunc` and non-mouse `HookScript` go through `SuspicionsPack.Perf` (`/spack perf`). |
| `SpellBookTab.lua` | Closing the spellbook closes the page (`LSBT:Close` on the spellbook's OnHide): LibSpellBookTabs kept it open until a native tab was picked, so the spellbook's key reopened the macros instead of the spells. |
| `SpellBookTab.lua` | Section headers are the pack's Forever header (Plumber's diamond and bronze line, in the parchment's ink) instead of `SpellBookHeaderTemplate`. |
| `ActionBars.lua` | `smb.barMacroTextShown` reads the pack's profile (`macroActionBar.barMacroText`), not the dropped Options panel's key. |
| `Cleanup.lua` | The "macros full" popup is drawn in the pack's Forever style (Plumber's frame, the game's font with Plumber's colours) and its "Don't show this again" box sets the pack's `macroActionBar.macrosFullPopup`. |
| `Minimap.lua` | Not included: no minimap button, no Options > AddOns panel. Its two settings are on the pack's page. |

Known difference: with the module off, `LibSpellBookTabs` still attaches its hidden frames to the spellbook when the
spellbook loads, as it does for any addon that ships it. With no tab registered it shows nothing.

`Config/` and `Data/` are the original's apart from line 1, and the "Buffs & Defence" section, spelled "Buffs &
Defense" as the game writes it. The class files in `Config/` are still the place to
change a class's page (see `Config/Config.lua`): name spells in English there, then run `tests/gen_mab_spells.lua`
again so other languages find them. A change there is overwritten by a pack update.
