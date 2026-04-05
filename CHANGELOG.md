# SuspicionsPack — Changelog

> Ce fichier sert de mémoire de session. Chaque modification notable est tracée ici avec sa date, le fichier concerné et la raison du changement.

---

## 2026-04-06 — v1.5.8

### Modules/AutoPlaystyle/AutoPlaystyle.lua — Auto-select Mythic+ group
- Added `SelectDefaultMythicPlusGroup`: when the listing creation dialog opens, automatically selects the Mythic+ group (instead of defaulting to Mythic). Uses `C_LFGList.GetAvailableActivityGroups` / `GetAvailableActivities` to locate the M+ groupID in the dialog's category, then calls `LFGListEntryCreation_Select` deferred by one frame to let the dialog finish initialising.
- Updated `LFGListEntryCreation_Show` hook to pass `activityID` arg for category derivation.
- Includes CLAUDE.md-required debug prints for arg/field verification.

### Core.lua — New DB field
- Added `autoPlaystyle.defaultMythicPlus = false` to default DB.

### GUI/GUI.lua — AutoPlaystyle panel
- Added "Auto-select Mythic+" toggle (gated behind the main Enable toggle) with descriptive label.

### All .toc / Core.lua — v1.5.7 → v1.5.8

---

## 2026-04-06 — v1.5.7

### Modules/AutoPI/AutoPI.lua — Fix prefix & registration
- Changed `ADDON_PREFIX` from `"SPPI"` → `"AutoPI"` to match the standalone AutoPI addon and allow cross-addon interoperability.
- Moved `C_ChatInfo.RegisterAddonMessagePrefix()` to file load time (outside `OnInitialize` DB guard), mirroring the standalone. Previously, if `SP.db` wasn't initialized before `OnInitialize` ran, the prefix was never registered and WoW silently dropped all incoming addon messages.

### Modules/AutoInnervate/AutoInnervate.lua — Fix prefix registration
- Same fix: moved `C_ChatInfo.RegisterAddonMessagePrefix()` to file load time, outside the DB guard in `OnInitialize`.

### All .toc / Core.lua — v1.5.6 → v1.5.7

---

## 2026-04-04 — v1.5.6

### GUI/GUI.lua — Preview button fix
- Replaced inline onClick closure with `nil` + `SetScript("OnClick", ...)` pattern, and added custom `OnLeave` to restore accent color on hover-out. Matches the working pattern used by other modules.

### GUI/GUI.lua — Module descriptions
- Auto PI: two lines explaining `/pi` goes at end of DPS macro, `/picast` at end of PI cast macro.
- Auto Innervate: same clarification for `/innerv` and `/innervcast`.

### All .toc / Core.lua — v1.5.5 → v1.5.6

---

## 2026-04-04 — v1.5.5

### Modules/AutoPI/AutoPI.lua — Nouveau module (fork de l'addon standalone AutoPI)
- Module `SP:NewModule("AutoPI")` — coordination PI entre DPS et Prêtres via addon messages (`SPPI`).
- Popup draggable avec bordure accent, mini-toast CD/Ready, positions sauvegardées par X/Y.
- Slash commands `/pi` (demander) et `/picast` (confirmer le cast).
- `SetPreview(on)` exposé pour le bouton Preview du GUI.

### Modules/AutoInnervate/AutoInnervate.lua — Nouveau module (miroir AutoPI pour Innervate)
- Même structure qu'AutoPI, adapté pour Innervate (sort ID 29166, CD 180s, classe DRUID).
- Préfixe addon `SPINV`, slash commands `/innerv` et `/innervcast`.
- Popup teinté vert foncé, texte nom en vert.
- `SetPreview(on)` exposé pour le bouton Preview du GUI.

### GUI/GUI.lua — Panneau Auto PI & Auto Innervate
- Ajout des entrées de navigation dans la section **COMBAT** (ordre alphabétique : Auto Innervate → Auto Misdirection → Auto PI).
- Card 2 restructurée en deux colonnes : gauche = input cible + toggle notify, droite = input accepter + liste de noms dynamique. Fix ancrage CENTER→OnSizeChanged pour alignement correct des colonnes.
- Liste de noms responsive : card3 (Alert Positions) ancrée sur le BOTTOMLEFT de card2, hauteur parent mise à jour dynamiquement.
- Noms de la liste colorés en accent.
- Bouton "Preview" remplace "Drag to Move" — affiche les alertes en prévisualisation, texte bascule "Stop Preview".
- Texte affiché : "Auto PI" et "Auto Innervate" (espace ajouté).
- Description AutoInnervate : "between healers and Druids".

### SuspicionsPack.toc / Core.lua / ClassIcons.toc / NudgeTool.toc
- Version bumped : 1.5.4 → **1.5.5**

---

## 2026-04-03

### Modules/MovementAlert/MovementAlert.lua — Refonte détection (approche Itrulia, sans charge tracking)
- **Suppression complète du charge tracking manuel** : `cachedChargeCount`, `chargeRechargeStart`, `rechargeTimers`, `lastChargeDecrement`, `StartRechargeTimer`, `StopRechargeTimer`, `UpdateCachedCharges` — source des désynchronisations.
- **Nouvelle logique de détection (identique à ItruliaQoL)** : `GetSpellCooldown` direct dans `CheckMovementCooldown`. Condition : `cdInfo.timeUntilEndOfStartRecovery` truthy + `isOnGCD == false` + `isOnGCD ~= nil`. Exception WARLOCK : `isOnGCD == nil` autorisé (Demonic Circle quirk).
- **`SPELLS_WITH_OWN_GCD`** : remplace l'ancien mécanisme `OWN_GCD_SPELLS`. Pour DH Shift (1234796), `UNIT_SPELLCAST_SENT` pose `ignoreMovementCd = true` pendant 0.8 s (durée GCD) pour éviter le faux positif isOnGCD=false du DH. CheckMovementCooldown est rappelé à l'expiration.
- **`UNIT_SPELLCAST_SENT` sorti du bloc `if db.showTimeSpiral`** : `ignoreMovementCd` doit fonctionner même quand Time Spiral est désactivé.
- **Suppression du système d'alias** (`SPELL_ALIAS_GROUPS`, `SPELL_ALIAS_MAP`, `SPELL_CATEGORY_DURATION`, `GetKnownCategoryDuration`, `RebuildTrackedSpellSet`, `trackedSpellSet`) — uniquement utile pour le charge tracking supprimé.
- **Suppression de `IsSecret`**, `SafeGetChargeInfo`, `SafeGetBaseDuration` — plus utilisés.
- **Events retirés** : `SPELL_UPDATE_CHARGES`, `UNIT_SPELLCAST_SUCCEEDED`, `PLAYER_REGEN_ENABLED`.
- **`BuildMovementSpellList` simplifié** : entrées sans `isChargeSpell`/`maxCharges`/`rechargeDuration`/`baseDuration`.

### tasks/lessons.md — Nouvelle règle

### Modules/MovementAlert/MovementAlert.lua — Time Spiral icon + LSM sound
- Ajout de l'icône de sort NorskenUI-style pour la Time Spiral : frame lazy-créé avec texture de sort, spiral de cooldown (`CooldownFrameTemplate`) et glow natif (`ActionButton_ShowOverlayGlow`).
- `ShowTSIcon(spellId)` appelé dans le handler `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW` (à côté de `timeSpiralOn = GetTime()`).
- `HideTSIcon()` appelé dans `GLOW_HIDE`, quand le timer expire dans OnUpdate, et dans `HideTimeSpiralPreview()`.
- `ShowTimeSpiralPreview()` appelle maintenant `ShowTSIcon(nil)` (icône fallback Time Spiral).
- `ApplyTSIconPosition()` appelé dans `Refresh()` pour repositionner l'icône lors d'un changement de settings.
- Son Time Spiral : remplacé `PlaySoundFile(db.timeSpiralSound)` par `LSM:Fetch("sound", db.timeSpiralSound)` (LibSharedMedia).
- `local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)` ajouté en haut du fichier.

### GUI/GUI.lua — Time Spiral Card 4 : LSM sounds + icon settings
- Section son remplacée : abandon de la liste BloodlustAlert, utilisation de `lsm:HashTable("sound")` (même pattern que WhisperAlert). `db.timeSpiralSound` stocke désormais directement le nom LSM (string), ou `nil` pour "None".
- Bouton "Listen" mis à jour : utilise `lsm:Fetch("sound", soundName)` pour le preview.
- Ajout d'une section "Icon display" dans Card 4 : toggle Show Spell Icon, slider Icon Size, sliders X/Y Offset. Chaque changement appelle `ma:Refresh()` pour repositionner l'icône à la volée.

### Modules/MovementAlert/MovementAlert.lua + GUI/GUI.lua — Time Spiral anchors, text position, custom glow
- **TS text position indépendante** : ajout de `ApplyTSTextPosition()` / `ResetTSTextPosition()`. Pendant une proc TS, `fsText` est réancré sur `UIParent` à `db.timeSpiralTextX/Y`. Après, retour au centre du frame `f`. Flag `f_tsTextPositioned` évite les `ClearAllPoints()` inutiles chaque tick.
- **Wiring complet** : `ApplyTSTextPosition` dans `ShowTimeSpiralPreview` + timer auto-cancel ; `ResetTSTextPosition` dans `HideTimeSpiralPreview`, GLOW_HIDE (TS abilities), else-branch OnEvent, et `Refresh()`.
- **Custom glow coloré** : frame `f_tsGlow` enfant de `f_tsIcon`, texture `IconAlert`, `AnimationGroup` BOUNCE (alpha 0.25→1.0, 0.65 s IN_OUT). Activé si `db.timeSpiralIconGlowEnabled`. Couleur via `SP.GetColorFromSource(db.timeSpiralIconGlowColorSource, db.timeSpiralIconGlowColor)`. Sinon : `ActionButton_ShowOverlayGlow` natif.
- **GUI Card 4** : Icon X/Y sur une seule ligne (HRow 0.5/0.5) ; ajout dropdown "Anchor Frame" (UIParent/PlayerFrame/TargetFrame/FocusFrame) ; nouveau HRow Text X/Y pour positionner le texte TS ; toggle "Custom Glow on Icon" + `CreateColorWithSource` "Glow Color".
- **Core.lua** : ajout de `timeSpiralIconGlowColorSource = "custom"` dans les defaults movementAlert.

## 2026-04-02 — v1.5.0

### Modules/FocusTargetMarker/FocusTargetMarker.lua — Fix events jamais enregistrés
- `Activate()` n'enregistrait jamais `PLAYER_ENTERING_WORLD` ni `READY_CHECK` → `OnWorldEnter` et `OnReadyCheck` n'étaient jamais appelés.
- Fix : ajout de `RegisterEvent("PLAYER_ENTERING_WORLD", "OnWorldEnter")` et `RegisterEvent("READY_CHECK", "OnReadyCheck")` dans `Activate()`.
- `Deactivate()` appelle désormais `UnregisterAllEvents()` avant `Disable()`.

### Modules/MovementAlert/MovementAlert.lua — Refonte détection (no-lag, no false-positive)
- Suppression de `OWN_GCD_SPELLS` et du mécanisme `ignoreMovementCd` (introduisait 0,5 s de délai).
- Ajout des événements `SPELL_UPDATE_COOLDOWN`, `SPELL_UPDATE_CHARGES`, `UNIT_AURA` (player), `UNIT_SPELLCAST_SUCCEEDED` (player) pour déclencher `CheckMovementCooldown()` immédiatement.
- Logique de détection divisée en fonction locale `CheckMovementCooldown()` appelée depuis OnUpdate et OnEvent.
- Multi-charge spells (`maxCharges > 1`) : affichage uniquement si `currentCharges == 0` (élimine le flash à 1 charge restante et le texte GCD-long sur DH Transfer).
- Spells normaux : `isOnGCD == false or (isOnGCD == nil and not chargeInfo)`.

### Modules/FilterExpansionOnly/ — Renommage + support commandes d'artisanat
- Module renommé de `AuctionHouseFilter` → `FilterExpansionOnly` (DB key `ahFilter` → `filterExpansionOnly`).
- Ajout de `ApplyCraftOrdersFilter()` : applique le filtre "extension actuelle uniquement" sur `ProfessionsCustomerOrdersFrame`, déclenché par l'événement `CRAFTINGORDERS_SHOW_CUSTOMER`.
- Mise à jour de `Core.lua`, `SuspicionsPack.toc` et `GUI/GUI.lua` en conséquence.

### Modules/AutoBuy/AutoBuy.lua — Fix inversion qualité bouton
- Les champs `id` / `q2` étaient inversés pour tous les items 241xxx (flacons, potions de soin, potions de combat).
- Fix : `id` = Q1 (qualité inférieure, ID plus élevé), `q2` = Q2 (qualité supérieure, ID plus bas) pour les 241xxx.
- Les huiles (243xxx) étaient déjà correctes, non modifiées.

### GUI/GUI.lua — Page Repair Warning (Durabilité)
- Ajout de `GUI:RegisterContent("durability", ...)` — la page affichait "No settings available." faute de contenu enregistré.
- 3 cartes : General (toggle + seuil % + texte d'alerte), Appearance (police, taille, outline, couleur avec source), Position (ancre, X/Y, preview, drag-to-move).
- `SP.Durability._syncSliders` branché sur les sliders X/Y.

### GUI/GUI.lua — Fusion card "Color Source" dans "Cursor Circle"
- La carte "Color Source" (dropdown source + swatch couleur custom) fusionnée dans la carte "Cursor Circle".
- Suppression de la carte `card3` séparée ; les contrôles couleur sont désormais dans `card2` après le dot size slider.

### GUI/GUI.lua — Suppression de la carte "Links" (home)
- La carte "Links" (T-Sheet, Raidbots, TeamSpeak) retirée de la page d'accueil.
- Suppression du `StaticPopupDialogs` associé et du helper `MakeLink`.

### SuspicionsPack.toc — Version bump 1.4.0 → 1.5.0

---

## 2026-03-28

### Modules/FocusTargetMarker/ — Nouveau module (fork ItruliaQoL)
- **Nouveau fichier** : `SuspicionsPack/Modules/FocusTargetMarker/FocusTargetMarker.lua`
- Forké depuis `ItruliaQoL/src/focus-target-marker/` (Itrulia).
- Crée/met à jour un macro `FocusTargetMarker` : `/focus [@mouseover,harm,nodead][]` + `/tm [@mouseover,harm,nodead][] <marker>`.
- Événements via AceEvent-3.0 (`PLAYER_ENTERING_WORLD`, `READY_CHECK`).
- Option announce : envoie le marker en party chat sur ready check (instances seulement).
- **Core.lua** : ajout du bloc `focusTargetMarker` dans les defaults AceDB.
- **SuspicionsPack.toc** : ajout de l'entrée `Modules\FocusTargetMarker\FocusTargetMarker.lua`.
- **GUI/GUI.lua** : nav item sous COMBAT, `ItemEnabledState`, et page contenu complète avec dropdown marker (icônes atlas) + toggle announce + carte Macro Usage.

### Modules/Recuperate/Recuperate.lua — Fix taint C_Timer.After(0)
- `self:UpdateAlpha()` appelé directement après `RegisterStateDriver()` héritait du thread tainte → `UnitHealth()` retournait une "secret number".
- Fix : les 3 appels directs (`Activate`, `HidePreview`, `EndDragMode`) remplacés par `C_Timer.After(0, function() if REC.button then REC:UpdateAlpha() end end)`.
- Combiné avec le fix pcall `SetAlpha(0)` et la migration AceEvent-3.0 du tour précédent, le bouton devrait maintenant se cacher/s'afficher correctement.

---

## 2026-03-27

### GUI/GUI.lua — Unification du style des boutons
- **`GUI:CreateButton`** : Remplacé le style `bgLight` + barre accent 2px par le style "preview" : fond `bgMedium`, remplissage `T.accent` complet au hover, texte blanc au hover.
- Supprimé la texture de barre accent gauche (2px).
- Supprimé tous les overrides post-création sur les call sites (CombatTimer, BLTimer, BL Listen, DeathAlert, Performance, EOT, Recuperate, Durability, GatewayAlert).
- Boutons toggle-état (Preview/Drag) : seul le `OnLeave` est surchargé pour gérer la couleur du texte selon l'état actif.

### Modules/Drawer/Drawer.lua — Détection d'erreur Lua
- **Problème** : Depuis un patch TWW, le drawer ne devenait plus rouge en cas d'erreur Lua.
- **Cause** : `ScriptErrorsFrame` est créé lazily par `Blizzard_DebugTools` et peut être nil au moment de `Drawer.Create()`.
- **Fix** : Remplacé `ScriptErrorsFrame:HookScript("OnShow")` par `hooksecurefunc("ScriptErrors_Display", OnErrorCaught)` avec fallback `ADDON_LOADED`.

### Modules/AutoBuy/AutoBuy.lua — Refonte du flux d'achat HV

#### Crashes et popup gelée
- **Problème** : La popup "Fetching price from server..." restait gelée indéfiniment.
- **Cause 1** : `SetBtnEnabled(buyBtn, false)` appelée dans `ShowBuyPopup` alors que `SetBtnEnabled` est une `local` définie *après* `ShowBuyPopup` → nil → crash silencieux → bouton Buy cassé.
- **Fix** : Revenu à `buyBtn:Disable()` / `buyBtn:Enable()` (API WoW standard).
- **Cause 2** : `COMMODITY_PRICE_UPDATED` se déclenche avec `total = nil` si l'item n'est pas listé → `GetMoney() < nil` → erreur Lua → popup gelée.
- **Fix** : Ajout d'un `pcall` autour de `pendingBuy.OnPrice(arg1, arg2)` dans `GetAux`. En cas d'erreur, `OnFail` est appelé.

#### Signature de l'event COMMODITY_PRICE_UPDATED
- **Découverte** (via debug) : L'event fire comme `(unitPrice, totalPrice)`, pas `(itemID, totalPrice)`.
- `arg1` = prix unitaire (ignoré), `arg2` = prix total → `OnPrice = function(_, total)` est correct.
- Ajout d'une garde `if not total or total == 0` pour afficher "Not listed on AH" proprement.

#### qty=0 — items qui ne déclenchaient jamais l'event
- **Problème** : Pour certains items (huile, potion de soins), `capturedItem.need = 0` → `StartCommoditiesPurchase(itemID, 0)` invalide → `COMMODITY_PRICE_UPDATED` ne fire jamais.
- **Cause** : `entry.buyQty = 0` configuré dans le GUI. En Lua, `0 or default` retourne `0` (0 est truthy) donc le fallback ne s'appliquait pas.
- **Fix** : Dans `BuildBuyList`, si `buyQty == 0`, on calcule le déficit : `buyQty = minQty - have` (acheter exactement ce qu'il manque pour atteindre le seuil).

#### Stabilité générale
- `cancelBtn` : ajout d'une garde AH (`if AuctionHouseFrame and AuctionHouseFrame:IsShown()`) avant `CancelCommoditiesPurchase()` pour éviter un crash si l'HV se ferme pendant l'annulation.
- `pendingBuy` expose `Cleanup` pour que `OnAuctionHouseClosed` puisse fermer la popup proprement (annule le ticker, évite un crash Lua différé).
- `OnAuctionHouseClosed` : appelle `pendingBuy.Cleanup()` avant de tout effacer.

---

## 2026-03-28

### GUI/GUI.lua — Animation de hover NorskenUI sur tous les widgets interactifs

#### Objectif
Porter le style de hover de NorskenUI dans SuspicionsPack : fond foncé (`bgMedium`) permanent, border qui anime en douceur vers la couleur accent au hover et revient à `T.border` au leave. Animation de 0.15 s avec easing ease-out quadratique.

#### `AnimateBorderFocus` — amélioration
- La fonction partait auparavant d'une couleur de départ fixe (`T.border` ou `T.accent`), ce qui provoquait un flash si l'animation était interrompue à mi-chemin.
- Désormais lit la couleur courante via `frame:GetBackdropBorderColor()` comme point de départ, rendant les inversions (hover rapide enter → leave) parfaitement fluides.

#### `GUI:CreateButton`
- Suppression du `SetBackdropColor(T.accent, …)` au hover (fond qui se remplissait complètement).
- OnEnter / OnLeave remplacés par `AnimateBorderFocus(btn, true/false)` — seule la border anime.

#### `CreateDropdown` (inline compact)
- OnEnter / OnLeave remplacés par `AnimateBorderFocus` à la place du `SetBackdropBorderColor` instantané.

#### `GUI:CreateDropdown` (dropdown plein)
- Suppression du `SetBackdropColor(T.bgHover, …)` au hover.
- OnEnter / OnLeave remplacés par `AnimateBorderFocus`.

#### `CreateAnchorSelector` (grille 3×3)
- OnEnter : anime uniquement les boutons non-sélectionnés (`AnimateBorderFocus(btn, true)`).
- OnLeave : cancelle proprement le ticker en cours (`btn._borderTicker:Cancel()`), puis `RefreshBtns()` pose la couleur d'état finale sans conflit.
- OnClick : même cancel du ticker avant `RefreshBtns()`.

#### Boutons de module spécifiques
- `previewAllBtn` (Cursor) : OnEnter/OnLeave utilisent `AnimateBorderFocus` + changement de couleur texte conservé.
- Bouton "Listen" (Sound) : remplacé le fill accent complet par `AnimateBorderFocus` uniquement.
- Boutons "Preview" audio : idem.
- Boutons Preview stateful (CombatTimer, BloodlustAlert, CombatCross) : OnLeave utilise `AnimateBorderFocus(btn, previewActive)` pour animer vers l'état courant (accent si actif, border si inactif).

---

## 2026-03-28 (suite)

### GUI/GUI.lua — Border animation sur les boutons Preview / Drag to Move

Les helpers `StyleActionBtn`, `StyleRecBtn`, `StyleDurBtn`, `StyleGABtn` fixaient la couleur de border directement via `SetBackdropBorderColor`, court-circuitant l'animation.

- **Fix** : Suppression de `SetBackdropBorderColor` dans tous les helpers `StyleXxx`.
- Chaque `UpdateXxxBtn()` (Death Alert, Recuperate, Durability, Gateway Alert) appelle désormais `AnimateBorderFocus(btn, isActive)` pour animer la border vers `T.accent` (actif) ou `T.border` (inactif).

### Modules/Recuperate/Recuperate.lua — Refonte du health monitor (fix taint)

**Symptômes** : `attempt to perform arithmetic on local 'cur' (a secret number value tainted by 'SuspicionsPack')` × 6 ; bouton affiché en permanence (UpdateAlpha échouait avant SetAlpha(0)).

**Cause** : La frame `_healthMonitor` (plain Frame) héritait d'un contexte d'exécution contaminé par l'interaction avec `SP_RecuperateButton` (SecureActionButtonTemplate), ce qui rendait la valeur retournée par `UnitHealth()` non utilisable en arithmétique.

**Fix — miroir de NorskenUI** :
- Suppression de `_healthMonitor` + `local function UpdateAlpha(btn)`.
- Ajout de `function REC:UpdateAlpha(event, unit)` (méthode module, filtre UNIT_HEALTH par unit).
- Dans `Activate()` : enregistrement des événements via **AceEvent-3.0** (`self:RegisterEvent(..., "UpdateAlpha")`), comme NorskenUI dans son `OnEnable()`. AceEvent utilise son propre frame interne dans un contexte propre.
- Garde pcall autour de `cur / max * 100` pour les contextes résiduelment tainter.
- `HidePreview()` et `EndDragMode()` appellent `self:UpdateAlpha()` à la place de l'ancienne fonction locale.

---

## À venir / connu

- Rien de connu pour l'instant.
