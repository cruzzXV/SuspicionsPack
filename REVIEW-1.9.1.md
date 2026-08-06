# Review complète de SuspicionsPack — août 2026

Périmètre : 33 fichiers, ~23 000 lignes (30 modules + `Core.lua` + `GUI.lua`).
Référence de comparaison : la suite **EllesmereUI** (19 addons, 424 000 lignes).

**Rollback** : tag git `pre-review-v1.9.0` (poussé sur GitHub) + copie complète dans
`_backup_pre-review_1.9.0/`.

---

## Le verdict en une phrase

L'addon n'est **pas** du spaghetti. L'architecture est saine — le cache de pages du GUI,
le système de cartes, le pool de lignes de CraftShopper, l'arm/disarm de CombatCross sont
du bon travail. Ce qu'il y a, c'est une **convention d'appel qui a dérivé** et qui cassait
la moitié des pages de réglages, et une **classe de bug taint** qui n'avait été corrigée
qu'à un seul endroit sur six.

---

# PARTIE 1 — Corrigé dans 1.9.1

## Le bug qui cassait la moitié de l'addon

**21 appels `Refresh()` avec un point au lieu de deux-points.** 16 modules définissent
`function Mod:Refresh()` et déréférencent `self`, mais `GUI.lua` les appelait avec un
point → `self` vaut nil → erreur Lua à **chaque changement de réglage** sur ces pages.

Le réglage était écrit en base avant l'erreur, donc ça « marchait après un /reload » —
c'est exactement ce symptôme.

Pages concernées : Copy Anything, Filter Expansion Only, Durability, Performance (×2),
Auto Invite, Auto Playstyle, Death Alert, Group Joined Reminder, CraftShopper,
Enhanced Objective Text, Clean Objective Header, Silvermoon Map Icons (×2), Gateway Alert,
Whisper Alert, AutoBuy, Spell Effect Alpha. Plus 2 appels `Cursor.Refresh()` sans préfixe
`SP.` → variable globale nil.

La convention était déjà correcte pour Automation, BloodlustAlert, TankMD,
FocusTargetMarker et MicroMenuSkin — elle a juste dérivé au fil des ajouts.

## Fuites de taint

C'est la classe de bug qui avait déjà cassé `Blizzard_CooldownViewer` (voir `lessons.md`,
28/04/2026). Le correctif livré à l'époque s'était arrêté au call site signalé ; il en
restait cinq.

| Fichier | Problème |
|---|---|
| `CombatCross` | `C_Spell.IsSpellInRange` comparé 3× sans garde, **10 fois par seconde en combat**. EllesmereUI documente cette API comme renvoyant une secret value en contenu instancié et la garde à chaque appel. |
| `MovementAlert` | `C_Spell.GetOverrideSpell` comparé sans garde. `pcall` **ne bloque pas** la propagation du taint. |
| `ReapPredict` | `ReadAuraApplications` et `IsInVMPhase` testaient l'aura brute ; leurs résultats pilotent des `SetShown`/`SetValue`, donc le taint atteignait les frames Blizzard. |
| `BloodlustAlert` | Arithmétique sur `expirationTime`/`duration` non gardée. |
| `PotionAlert` | `GetItemCooldown` comparé sans garde. |

Point important trouvé à la relecture de mes propres correctifs : **l'ordre compte**.
`if oid ~= nil and not issecretvalue(oid)` ne sert à rien — Lua évalue de gauche à droite,
donc la comparaison a déjà eu lieu. La garde doit venir en premier.

## Bugs fonctionnels

- **`Performance`** — `for i = 1, 200000 do C_QuestLog.RemoveQuestWatch(i) end` : 200 000
  appels API en une frame, gel du client de plusieurs secondes, déclenchable depuis un
  bouton du GUI. Plus 30 à 60 lignes de `print` de debug oubliées. Réécrit pour parcourir
  la vraie liste de suivi.
- **`AutoBuy`** — lisait le 7ᵉ retour de `GetMerchantItemInfo` (un booléen) comme la taille
  de pile → `math.min()` levait une erreur et interrompait tout l'achat auto. Et si la
  valeur avait été 0, `math.min(0, need)` empêchait `need` de décroître → **boucle infinie**.
  Ajouté aussi le plafond `GetMerchantItemMaxStack` : sans lui on émettait un appel serveur
  par item (buyQty va jusqu'à 9999 dans le GUI).
- **`PotionAlert`** — `FindTrackedPotion` testait le retour `enable` de `GetItemCooldown`,
  vrai pour n'importe quel item. Il renvoyait donc **toujours** la première potion de la
  liste, possédée ou non — et pour un item non possédé `start = 0` = « prête », d'où
  l'alerte affichée en permanence en donjon.
- **`SilvermoonMapIcon`** — `ipairs({p1, p2, fish, cook})` : `GetProfessions()` renvoie nil
  pour les slots non appris, et `ipairs` s'arrête au premier trou. Un perso sans pêche
  n'enregistrait jamais la cuisine ; un perso sans métier principal n'enregistrait rien.
- **`CopyTooltip`** — `local _, link = idx and GetMacroItem(idx) or nil, nil` parse comme
  `(expr), nil` : `link` valait toujours nil et toute la branche macro-objet était morte.
- **`CraftShopper`** — `CancelCommoditiesPurchase` sans garde HV, alors que `wow-api-notes.md`
  documente explicitement que ça plante si l'HV est fermée. Le timer de 15 s marchait dedans
  automatiquement.
- **`CombatCross`** — trois IDs de sort faux : Gardien avait Férocité (finisher Chat, nil en
  Ours), Vengeance avait Fracture (20 m, étiqueté « Shear » 5 m), Prot Paladin avait Frappe
  du Croisé qui est remplacée pour cette spé. Ajouté `FindSpellOverrideByID` pour résoudre
  les talents.
- **`Core.lua`** — ternaire `a and b or c` cassé dans le PreviewManager : quand le terme du
  milieu vaut `false`, l'idiome retombe sur `or c` et renvoie `true`, l'inverse de ce que
  le commentaire juste au-dessus décrit.
- **`Core.lua`** — 2 séquences d'échappement `\/` invalides. WoW les tolère, mais **aucun
  vérificateur de syntaxe externe ne pouvait valider Core.lua** — le fichier que `lessons.md`
  dit avoir été tronqué silencieusement deux fois. Le garde-fou est rétabli.
- **`MovementAlert`** — le résolveur de police ignorait LibSharedMedia : toutes les polices
  du dropdown autres que les 8 en dur retombaient silencieusement sur Expressway.

Tous les fichiers passent maintenant un parseur Lua 5.1. Aucun `goto`, aucun opérateur 5.2+.

---

# PARTIE 2 — Ce qui demande ton arbitrage

Rien de tout ça n'est appliqué. Classé par valeur.

## A. Corrections fonctionnelles (à faire, mais nécessitent un test en jeu)

| Module | Problème | Effort |
|---|---|---|
| **`Automation`** | Le toggle maître **ment** : `Refresh()` ne lit jamais `db.enabled`. Sept fonctions sur neuf (auto-vente, role check, talking head, barre de sacs, skip cinématique, forme de vol…) continuent après extinction. Le role check continue même après extinction de sa propre option, parce que ses hooks ne reconsultent pas la base. | 1 h |
| **`TankMD`** | Activer le module dans le GUI ne crée aucun bouton et n'enregistre aucun événement jusqu'au `/reload`. AceAddon a `defaultModuleState = true`, donc `if not self:IsEnabled() then self:Enable() end` ne redéclenche jamais `OnEnable`. | 30 min |
| **`AutoBuy`** | `id`/`q2` sont **inversés pour 15 presets sur 24**. Les flacons/potions mettent l'ID haut en `id`, les huiles l'inverse. Choisir « Qualité 2 » sur un flacon achète donc probablement le **rang 1** — de l'or dépensé sur le mauvais palier. À vérifier en jeu avant de toucher. | 1 h |
| **`Drawer`** | Aucune garde `InCombatLockdown()` sur les chemins de capture/reparent, et remplacement de méthodes (`SetPoint = noop`) sur des frames arbitraires ramassées par un balayage de `UIParent` — si une frame protégée est prise, taint garanti. EllesmereUIMinimap résout exactement ça avec `hooksecurefunc`. `Disable()` laisse aussi les boutons « masqués » invisibles jusqu'au reload. | 2 h |
| **`CVars`** | Aucune restauration à la désactivation, aucun snapshot de la valeur d'origine. Et 2 noms de CVar non vérifiables sur 12.x — un nom faux échoue **silencieusement** (le toggle a l'air de marcher). À tester avec `/dump C_CVar.GetCVar("...")`. | 1 h |
| **`FastLoot`** | Force `autoLootDefault = 0` à la désactivation, en éteignant le réglage Blizzard du joueur que l'addon n'a jamais possédé. | 20 min |
| **`DeathAlert`** | Aucun throttle sur le texte : un wipe fait défiler 20 noms dans une seconde, seul le dernier est lisible. | 30 min |
| **`GroupJoinedReminder`** | `ipairs(entryData.activityIDs)` non gardé → erreur si le champ est absent (il était singulier avant 10.2.7). | 15 min |
| **`FocusTargetMarker`** | `/tm` en dur dans la macro → cassé sur tout client non anglais. EllesmereUI documente ce piège et utilise `SLASH_TARGET_MARKER1`. | 20 min |

## B. Performance

**Aucun problème critique en combat** — c'est le point rassurant. Mais trois `OnUpdate`
tournent en permanence pour rien :

| Module | Coût | Correctif |
|---|---|---|
| **`MovementAlert`** | Armé à l'activation, **jamais désarmé**. 10 scans `GetSpellCooldown` par seconde pour toute la session, en ville, hors combat, sans rien à afficher. | Armer seulement quand un décompte est affiché. |
| **`CombatTimer`** | Un texte à 4 Hz piloté par un `OnUpdate` par frame — 56 appels sur 60 ne font rien. Avec « afficher la dernière durée » il tourne pour toujours hors combat. | `C_Timer.NewTicker` armé sur `PLAYER_REGEN_DISABLED`, exactement ce que BloodlustAlert fait déjà. |
| **`ReapPredict`** | Poll 10 Hz dès qu'un Chasseur de démons Dévoreur est connecté, plus `UNIT_POWER_FREQUENT` qui déclenche un `UpdateMeter` complet (scan CDM avec pcall) à la fréquence d'affichage. | Passer en événementiel, garder le poll comme filet lent en combat. |

**`ReapPredict` enregistre 8 événements bruts** (dont `UNIT_AURA` et `UNIT_POWER_FREQUENT`)
dans `OnEnable`, **quelle que soit la classe et quel que soit `db.enabled`**, et ne les
désenregistre jamais (`OnDisable` ne touche que le côté AceEvent). Tout joueur non-DH paie
le dispatch du jeu d'événements le plus bruyant de l'addon. **C'est le meilleur rapport
gain/effort de toute la review : 30 minutes.**

**`SpellEffectAlpha` et `Performance` écrivent des CVars au login même désactivés** — un
module éteint écrase silencieusement les réglages Blizzard du joueur à chaque session.

**`GUI:Rebuild()` détruit toute l'interface à chaque changement de thème** : `SetParent(nil)`
+ `PageCache = nil`. WoW ne libère jamais les frames. La page Thèmes a 13 presets — les
comparer tous fuit ~2 000 frames. EllesmereUI recolore sur place via un registre
`_accentElements`.

## C. Architecture (le vrai sujet de fond)

1. **Pas de ticker partagé.** 9 `OnUpdate` indépendants, 5 désarmements seulement.
   `EllesmereUI_Ticker.lua` est la référence : quand le compteur d'abonnés tombe à zéro, le
   frame se `Hide()` — coût nul au repos, ce que l'addon n'a nulle part aujourd'hui.
   Leur fichier documente aussi une règle non triviale : **le moteur facture le CPU d'un
   handler à l'addon dont le contexte a créé le frame**, pas à celui qui a posé le script.

2. **Pas de migration de SavedVariables.** Aucun `dbVersion`, aucun élagage. Les modules
   supprimés (AutoPI, AutoInnervate, CombatLog, PetStatus) sont encore dans la base de tous
   les utilisateurs. Pire : l'import de profil fait un deep-merge d'une chaîne arbitraire
   dans le profil vivant, sans version ni liste blanche — importer un vieux profil
   réinjecte les clés mortes définitivement. **À faire avant le prochain changement cassant,
   pas après.**

3. **111 clés mortes dans les defaults.** `interruptTracker` (51) et `mythicCast` (60) ne
   sont lus par personne. AceDB les écrit dans le fichier SavedVariables de chaque profil
   à chaque déconnexion. À supprimer — mais avec une migration, sinon elles survivent.

4. **33 clés lues sans être déclarées.** Chaque défaut existe alors en double (module + GUI)
   et une paire a déjà divergé : `bloodlustAlert.frameStrata` vaut « TOOLTIP » dans le
   dropdown et « HIGH » dans le module. Le dropdown ment sur un profil neuf.

5. **~660 lignes dupliquées** (5,5 % de `Modules/`). Les pires : 6 tables `FONT_FACES` qui
   **masquent** `SP.GetFontPath` (déjà branché sur LSM), 29 `GetDB()` identiques, 19 blocs
   `IsLoggedIn() / PLAYER_LOGIN`, 8 constructeurs de frame d'alerte quasi identiques.

6. **Trois contrats de cycle de vie coexistent** sur 30 modules (AceAddon `Enable/Disable`,
   `Activate/Deactivate` maison, `Refresh` ad-hoc). `Automation` et `MovementAlert` n'ont
   **aucun** `OnDisable`.

7. **`GUI.lua` = 43 % du code source, chargé à chaque login.** Le découpage naturel est un
   addon compagnon `## LoadOnDemand` — le pattern standard (`Blizzard_*`, `ElvUI_Options`).

8. **`Core.lua` devrait être découpé** — pas par esthétique, mais parce que 1 563 lignes de
   sept sujets sans rapport dans le fichier le plus édité, c'est exactement la forme qui
   s'est fait tronquer deux fois. Découpage : `Core/Defaults.lua`, `Core/Changelog.lua`,
   `Core/Theme.lua`, `Core/Pixel.lua` → il reste ~250 lignes de vrai bootstrap.

## D. Code mort à supprimer

- `ReapPredict` : `activeColorSwatches`, `DumpState`, `RegisterSettings` (vide), le
  pré-calcul de `CreateFuryBar` intégralement écrasé par `ApplyFuryLayout`, la couleur
  `beyondBuild` (texture de largeur zéro, invisible par construction), et
  `UnsetupAll`/`RestoreCDMLayout` — exposés mais appelés nulle part, alors que le module
  réécrit la disposition du Cooldown Manager du joueur sans offrir d'annulation. **~150 lignes.**
- `GUI` : `CreateColorSwatch` (60 lignes, zéro appel), la branche `rmBtn` de `MakeItemRow`
  (31 lignes inatteignables).
- `Core` : `SP.ChangelogOrder` (lu par personne, et désynchronisé), `NS.SP`, `SP.C`,
  `Px.SetBackgroundColor`.
- `DeathAlert` : `Preview`/`StopPreview` (28 lignes, boutons retirés depuis).
- `Drawer` : `LooksLikeButton` + `HasClickHandler` (20 lignes).
- `CombatTimer` : `Refresh()` mort.

---

## Ordre recommandé

**Vague 1 — sûr, ~4 h, aucun changement de comportement**
`ReapPredict` : événements dans `Enable()` + garde de classe · gate CVar sur
`SpellEffectAlpha`/`Performance` · supprimer les 6 `FONT_FACES` au profit de
`SP.GetFontPath` · `SP.BLANK` / `SP.ApplyAnchor` / `SP.ModuleDB` · supprimer le code mort.

**Vague 2 — le ticker, ~6 h**
Porter `EllesmereUI_Ticker` dans `Core.lua`, migrer CombatTimer, MovementAlert et le poll
de ReapPredict.

**Vague 3 — architecture, ~8 h**
Mixin de cycle de vie · `SP.CreateAlertFrame` · migration DB versionnée · découpage
`SuspicionsPack_Config` en LoadOnDemand.
