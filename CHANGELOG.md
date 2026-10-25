# SuspicionsPack — Changelog

> Ce fichier sert de mémoire de session. Chaque modification notable est tracée ici avec sa date, le fichier concerné et la raison du changement.

---

## 2026-10-23 — Tiroir : un onglet plus clair

Retour de Cruzz (capture) : l'onglet est très foncé. À 6 px d'épaisseur,
l'art « repos » du bouton de Plumber (corps vers 70,30,13, fait pour porter
un texte crème) donnait 60-72,20-27,2-5 à l'écran. Trois rendus montrés hors
jeu ; Cruzz a pris le B, repos et survol inversés.
- **`Drawer.lua`** : l'onglet prend toujours les lignes « survol » de
  Plumber (576-640, cuivre plus chaud) ; au repos, les mêmes tranches sont
  ajoutées par-dessus en `ADD` à 35 % (plus clair) ; au survol, l'art seul.
  La teinte rouge d'erreur s'applique aux deux couches.
- `test_drawer` : Forever 19/19 (lignes 576, couche ajoutée à 35 % au même
  endroit, teinte d'erreur sur les deux), retail 2/2. Le passage au survol
  n'est pas testé (il faut des boutons dans le tiroir). Copié dans l'install
  Forever. Pas vu en jeu.

---

## 2026-10-23 — Tiroir de la minicarte au style Forever

Demandes de Cruzz (capture du bouton « Return to List » de Plumber) : sur
Forever, l'onglet du tiroir prend la texture de ce bouton, au repos et au
survol, et l'intérieur du tiroir passe au style Forever. Aperçus hors jeu
montrés avant d'écrire le code ; Cruzz a choisi la boîte sombre de Plumber
pour l'intérieur, et l'épaisseur réglée (Tab width, 6 par défaut) pour
l'onglet.
- Le bouton est le `CreateRedButton` de Plumber
  (`ExpansionLandingPage/Basic.lua`) : trois tranches de
  `ExpansionBorder_TWW.tga` (le même fichier que le pack publie déjà dans
  `Media/Plumber`), lignes 448-512 au repos, 576-640 au survol, x 768-800 |
  800-972 | 972-1004, bouts de 16 dépassant de 2,5, le tout 32 d'épais pour
  un bouton de 24.
- **`Modules/Drawer/Drawer.lua`** (Forever seulement, `Skin.FOREVER`) :
  l'onglet est ce bouton, mis à l'échelle de son épaisseur et debout sur les
  côtés gauche et droit de la minicarte (quart de tour par `SetTexCoord` à
  huit valeurs), couché en haut et en bas. Survol : l'état survol de
  Plumber ; erreur Lua attrapée : teinté rouge. Le tiroir ouvert est
  `Skin.PlumberBox`. `Refresh` ne repose plus les fonds plats de retail.
  Retail inchangé.
- **`Pages/Drawer.lua`** : sur Forever, « Tab border », « Tab colour »,
  « Panel border » et « Border colour » sont retirés (le bouton et la boîte
  ont leurs propres couleurs), avec une note à la place.
- **Tests** : `tests/test_drawer.lua` (`--drawer`), lancé pour les deux
  clients : retail garde la barre plate et le fond ; Forever a les trois
  tranches, leurs tailles, le quart de tour, la teinte d'erreur, le passage
  couché en haut. `wowstub` enregistre maintenant `SetTexCoord`. Drawer
  retail 2/2, Forever 17/17 ; GUI retail 139/139, Forever 40/40 ; les autres
  suites vertes. Copié dans l'install Forever. Pas vu en jeu.

---

## 2026-10-23 — essayé puis retiré : couper le bout du côté sur les coins d'Ornated

Essayé à la demande de Cruzz (sur l'aperçu de « Top and sides ») : couper le
petit trait bronze au-dessus du triangle cuivre (le début de la seconde barre
du liseré du côté), en retirant les 4 lignes source du bout intérieur d'un
coin dont le côté est retiré (`cornerTrim`). Cruzz a préféré avant : le
code, les tests et l'install Forever sont revenus à l'état de l'entrée
« Top and sides » (Datatexts 87/87, Forever 40/40). Le coin reste entier.

---

## 2026-10-23 — Datatexts : « Top and sides » et « Bottom and sides »

Demande de Cruzz (capture, Ornated bord haut ouvert) : un rendu sans les
côtés ni le haut, sans couper les triangles cuivre du bas.
- **`Skins.lua`** : deux choix de plus dans « Open edge » : **Top and sides**
  (seul le liseré du bas) et **Bottom and sides** (seul celui du haut).
  `FitLines` lit un ensemble de côtés ouverts (`OPEN`) : une ligne du haut
  ou du bas n'est rentrée à un bout que si un côté l'y rejoint, sinon elle
  court sur toute la largeur, ombre extérieure de Forever comprise. Un coin
  suit son bord haut ou bas et reste entier sans les côtés (son petit
  montant fait partie de l'ornement). Marche pour Forever et Ornated.
- **`Datatexts.lua`** : la clé est passée telle quelle (une clé inconnue
  dessine le bord entier).
- Rendu hors jeu à la taille de la barre. Datatexts 87/87, GUI retail
  139/139, Forever 40/40. Copié dans l'install Forever. Pas vu en jeu.

---

## 2026-10-23 — Datatexts : 100 % d'opacité est vraiment opaque

Retour de Cruzz (capture) : à 100 %, le fond restait transparent. Le fond de
Forever et de Text only gardait l'alpha 0,9 de la boîte de Plumber, et le
curseur le multipliait : 100 % donnait 0,9.
- **`Skins.lua`** : le fond de Forever (et de Text only) est opaque ; le
  curseur est son alpha. La ligne sombre intérieure de Forever passe aussi à
  1 (elle était à 0,96).
- **Page** : la description dit « 100% hides what is behind the bar ».
- **Test** : l'opacité vérifiée composée (alpha de la couleur × alpha de la
  texture) ; avec l'ancien fond à 0,9, le test sort rouge. Datatexts 78/78,
  GUI retail 139/139, Forever 40/40. Copié dans l'install Forever. Leçon
  ajoutée.

---

## 2026-10-23 — Datatexts : opacité du fond

Demande de Cruzz : pouvoir choisir l'opacité du fond.
- **Page** : « Background opacity » par barre, 0 à 100 %.
- **`Skins.lua`** : `Skins.Apply` reçoit l'opacité et la pose sur le fond du
  skin seul (`SetAlpha`, qui se multiplie à l'alpha propre du fond : 90 %
  pour Forever et Text only) ; liseré, ombre et coins restent entiers.
- **`Datatexts.lua`** : champ `bgOpacity` (100 par défaut) ; une barre
  enregistrée avant (celles de Cruzz) n'en a pas et se lit à 100 %.
- Datatexts 75/75 (les trois skins, le fond seul, la valeur absente),
  GUI retail 139/139, Forever 40/40. Copié dans l'install Forever.

---

## 2026-10-23 — Datatexts : une seule barre par défaut, au centre

Demande de Cruzz : garder ses réglages, mais un nouvel utilisateur reçoit une
seule barre au milieu de l'écran, sans les noms Chat / Details / Minimap.
- **`Datatexts.lua`** : `DEFAULT_BARS` = « Bar 1 », 360 × 22, au centre,
  Durability, Gold, Time. Le semis ne tourne qu'une fois par profil
  (`_seeded`) : le profil de Cruzz (vérifié dans son
  `SavedVariables\SuspicionsPack.lua` Forever : Chat, Details, Minimap,
  `_seeded = true`) garde ses trois barres.
- **Page** : « Restore default bars » remet cette barre unique (texte mis à
  jour).
- Tests : le défaut vérifié (une barre, au centre), le semis jamais rejoué ;
  les tests de l'éditeur se bâtissent leurs trois barres. Datatexts 66/66,
  GUI retail 139/139, Forever 40/40. Copié dans l'install Forever.

---

## 2026-10-23 — Forever : la couleur « thème » devient l'or du jeu

Demande de Cruzz : le thème du pack étant Forever, l'accent doit être la
couleur de Forever. En 2.8.0 l'accent de `SP.Theme` était resté rouge sur
Forever exprès (seule la fenêtre d'options avait sa palette or) ; c'est cet
accent que lisent la source de couleur « Theme » des modules et la teinte de
l'icône de minicarte.
- **`Core.lua`** : `SP.ThemePresets.Forever` = la palette Suspicion avec
  l'or du jeu (FFD100, 1 / 0,82 / 0) pour `accent`, `accentHover`,
  `accentDim`, `selectedBg`, `selectedText` (alphas gardés).
  `SP.ActiveThemePreset(name)` le choisit sur Forever et le préréglage
  enregistré ailleurs ; `SP.Theme` à sa création, `OnInitialize` et
  `RefreshTheme` passent par lui. Rien n'est enregistré : le profil garde
  « Suspicion », retail reste rouge. Vérifié en évaluant le bloc de
  `Core.lua` dans les deux cas (retail 0,898 / 0,063 / 0,224 ; Forever
  1 / 0,82 / 0).
- **`Core/Theme.lua`** (options) : le commentaire qui disait l'accent des
  modules « rouge sur tous les clients » est corrigé.
- Suites vertes (GUI retail 139, Forever 40, datatexts 64). Copié dans
  l'install Forever. Pas vu en jeu.

---

## 2026-10-23 — Datatexts : Text only a un fond, plus de séparateurs

Demande de Cruzz : Text only doit avoir un fond, et sans les séparateurs.
- **`Skins.lua`** : Text only = le fond de Forever (14,13,9 à 90 %) seul,
  sans liseré, ombre ni séparateurs. Le séparateur de Plumber debout
  (`DIV_*`, `Fit.text`) est retiré.
- **Page** : la description d'« Open edge » dit que Text only n'a pas de bord.
- `test_datatexts` 64/64, GUI retail 139/139, Forever 40/40. Copié dans
  l'install Forever. Pas vu en jeu.

---

## 2026-10-23 — Datatexts : skins Forever et Ornated, bouts carrés, X et Y

Demandes de Cruzz : renommer les skins, des bouts gauche et droit carrés pour
la boîte (ses coins chanfreinés de 8 px se rejoignent sur une barre de 24 et
pointent les deux bouts), et des réglages X / Y par barre.
- **`Skins.lua`** : « Plumber box » devient **Forever**, « Leather and
  bronze » devient **Ornated** ; les clés enregistrées (`box`, `frame`) ne
  changent pas, aucune barre à migrer. Les deux skins bordés passent par un
  même constructeur de lignes d'un pixel physique (lignes dedans, halo
  dehors, fond dessous, coins dessus pour Ornated). Forever reprend la boîte
  des listes déroulantes à pleine échelle, mesurée dans
  `ExpansionBorder_TWW.tga` : liseré bronze de 2 px (182,153,129 puis
  85,71,60), une ligne sombre, fond 14,13,9 à 90 %, ombre extérieure de 3 px
  (0,73 / 0,39 / 0,1), en onglets carrés. Rendu hors jeu avant.
- **`Core/Skin.lua`** : `PlumberBoxOpen` retiré (plus aucun appelant), la
  boîte chanfreinée reste pour les listes, l'infobulle et le roster.
- **Page** : « X offset » et « Y offset » (−2000 à 2000), décalages depuis
  l'ancre de la barre ; un glisser les met à jour (`GUI.RefreshAll` à la fin
  du glisser). La note sur le rebord de 8 px de la boîte est retirée.
- `test_datatexts` 62/62, GUI retail 139/139, Forever 40/40. Copié dans
  l'install Forever. Pas vu en jeu.

---

## 2026-10-23 — Datatexts : le cuir et bronze redessiné à la demi-échelle de Plumber

Retour de Cruzz (capture) : les côtés gauche et droit du skin cuir et bronze
étaient bizarres. Mesuré sur sa capture : côtés en brun très sombre
(29,22,14) sur 2-3 px, bas avec une ligne bronze nette, coins en diagonale
floue. Cause : le cadre fin de Plumber (`SettingsPanel.png`) est dessiné pour
environ deux fois la hauteur d'une barre ; réduit cinq fois, son liseré de
12 px (deux barres bronze autour d'un canal cuivre sombre) et ses coins
cuivre se brouillaient, et chaque côté crénelait à sa façon. Le fond « cuir »
est noir sur la capture parce que l'image l'est presque (moyenne 16,10,7) :
pas un défaut.

- **`Skins.lua`** : le liseré est redessiné à la demi-échelle de Plumber,
  celle où il dessine lui-même son art : six lignes d'un pixel physique, aux
  couleurs de son profil de 12 px moyennées deux à deux, puis quatre lignes
  de son ombre intérieure. La ligne k est rentrée de k pixels aux deux bouts :
  les côtés se rejoignent en onglets nets. Coins cuivre découpés sur 26 px à
  partir de la ligne extérieure et dessinés à 13 px physiques (moins sur une
  barre trop basse pour deux). Un bord ouvert retire ses lignes et ses coins.
  Rendu hors jeu avant d'écrire le code (aperçu ffmpeg à la taille réelle).
- **`Datatexts.lua`** : `UI_SCALE_CHANGED` / `DISPLAY_SIZE_CHANGED` refont la
  mise en page (les lignes sont en pixels physiques), plus seulement le bouton
  sécurisé.
- `test_datatexts` 59/59, GUI retail 139/139, Forever 38/38. Copié dans
  l'install Forever. Pas vu en jeu.

---

## 2026-10-23 — Datatexts : un bord ouvert

Retour de Cruzz (capture, skin cuir et bronze sous le chat) : pouvoir enlever
le bord du haut.
- **Option par barre « Open edge »** (None / Top / Bottom) : le bord choisi
  et ses deux coins disparaissent, les côtés et le fond vont jusqu'au bord de
  la barre. Pour une barre collée sous le chat (Top) ou sous la minicarte
  (Bottom). Sans effet sur Text only.
- **`Core/Skin.lua`** : le placement des neuf pièces de `PlumberBox` sort
  dans `Skin.PlumberBoxOpen(f, open)` ; `PlumberBox` l'appelle sans bord
  ouvert, donc les autres boîtes (listes, infobulle, roster, dialogue de
  profil) sont placées comme avant.
- **`Skins.lua`** : le cuir et bronze se place dans `Fit.frame` à chaque
  passe, selon le bord ouvert ; le cuir monte (ou descend) jusqu'au bord.
- **`Datatexts.lua`** : champ `openEdge` des barres. **`Pages/Datatexts.lua`** :
  la ligne « Open edge ».
- `test_datatexts` : 54/54 (les deux skins, les deux bords, aucune frame
  créée en changeant de bord). GUI retail 139/139, Forever 38/38. Copié dans
  l'install Forever. Pas vu en jeu.

---

## 2026-10-23 — Datatexts (Forever), phase 1 : le socle et les 8 de Cruzz

Demande de Cruzz : une version du pack de Simple DataTexts (SDT, Cilraaz),
pour Forever, à notre style Forever. SDT est sous GPL-3 : lu comme référence
fonctionnelle seulement, aucun code, police ni texture copiés (les pièces
coin du jeu, `GetCoinTextureString`). Les skins réutilisent l'art de Plumber
déjà publié dans `Media/Plumber` : aucun nouveau fichier publié.

Chaque datatext de SDT a été vérifié sur la branche `forever` de
Gethe/wow-ui-source (la feuille de personnage de Forever sert de guide).
Gardés ou à corriger en phase 2 : stats, Bags, Currency, Date, Coordinates,
Zone, Quests, Mail, Combat timer, Experience, Item level, Speed, LDB. Ajouts
prévus (feuille de Forever) : Stamina, Spirit, Hit, Defense, Résistances,
Mana regen, Dual spec. Écartés (pas de contenu sur Forever) : Avoidance,
Leech, Versatility, Mastery, Stagger, Collapsing Star, clé M+, spé, spé de
butin, changement de spé.

- **`Modules/Datatexts/Datatexts.lua`** (nouveau) : registre, barres
  (jusqu'à 8 cases), un fournisseur par datatext affiché (une frame
  d'événements, un ticker ; texte calculé une fois et poussé à toutes les
  cases qui le montrent ; une rafale d'événements = une mise à jour). Style
  (polices, couleurs) appliqué tout de suite ; géométrie, affectations et
  bouton sécurisé reportés hors combat (`RequestLayout`). Le bouton sécurisé
  de la pierre de foyer est sur UIParent, posé par coordonnées absolues sur
  sa case : les barres ne deviennent jamais protégées. Barres de Cruzz par
  défaut (Chat, Details, Minimap, relevées dans son profil SDT).
- **`Skins.lua`** (nouveau) : boîte Plumber, cuir et bronze (le cadre fin à
  coins cuivre de `SettingsPanel.png`, mesuré dans le fichier), texte seul
  (le séparateur de Plumber debout). Choisi par barre.
- **`Tooltip.lua`** (nouveau) : GameTooltip privé, NineSlice à alpha 0
  (Blizzard le ré-affiche à chaque masquage), boîte Plumber dessus.
- **`Roster.lua`** (nouveau) : panneau Guilde / Amis cliquable (clic :
  chuchoter ; Alt+clic : inviter), `C_BattleNet` et non l'ancien
  `BNGetFriendInfo`.
- **`Texts/`** (nouveau) : Hearthstone (choix de la pierre ou d'un jouet au
  clic droit), Durability, Gold (persos du royaume en compte, jeton si le
  royaume en a), System, Volume, Time (sans Encounter Journal, absent de
  Forever), Guild, Friends.
- **`Pages/Datatexts.lua`** (nouveau, catégorie Interface) : réglages
  généraux, éditeur de barres (lignes construites une fois, masquées selon la
  barre choisie ; hors de « Reset page »), options par datatext.
- **`Core.lua`** : défauts `datatexts`, section `global` et
  `SP.GetGlobalDB()`. **`Core/Skin.lua`** : `PlumberBox` rend ses pièces et
  ne les recrée pas. **`Pages/Home.lua`** : un import qui porte des barres
  les remplace au lieu de les mêler entrée par entrée.
- **Tests** (locaux) : le chargeur de `test_gui.lua` honore les directives
  `[AllowLoadGameType …]` (il plantait depuis la 2.7.1) ; passe Forever
  (`--forever`) ; `test_datatexts.lua` (`--datatexts`). Chaque nouvelle
  assertion a été vue rouge en cassant le code exprès.

**Relecture contre le client (branche `forever`), corrigé avant l'essai :**
- Les cases recevaient du texte avant d'avoir une police : le client lève
  « Font not set » et tout `Layout()` s'arrêtait. Police posée à la création
  (`GetSlot`). `wowstub` lève maintenant la même erreur (FontString jamais
  dotée d'une police), et `spstub` a un vrai `SetFontSafe`.
- `GetCoinTextureString` global n'existe pas sur ce moteur (seulement
  `C_CurrencyInfo.`) : le coût de réparation passe par notre `Money`.
- Guilde : la demande de roster au login partait avant que `IsInGuild()` soit
  vrai et consommait l'attente de 10 s. L'attente ne démarre qu'à une vraie
  demande ; nouvelle demande sur `PLAYER_GUILD_UPDATE` et sur
  `GUILD_ROSTER_UPDATE` quand son argument `canRequestRosterUpdate` est vrai.
- Pierre de foyer : `*type1` / `*item1` / `*toy1`, pour qu'un clic avec
  Maj, Ctrl ou Alt l'utilise aussi.
- Bouton sécurisé replacé aussi à l'image suivante (rectangle lu trop tôt), à
  `UI_SCALE_CHANGED` et `DISPLAY_SIZE_CHANGED`, et jusqu'à 5 essais au login.
- Infobulle : un rebâti déclenché pendant son propre bâti (prix du jeton) est
  ignoré, sinon ses lignes doublaient.
- Le panneau de roster s'ouvre aussi en combat (il se ferme à l'entrée en
  combat).

Copié dans l'install Forever beta (identique au projet). Pas encore vu en
jeu. Le module est coupé par défaut ; SDT encore actif dessinerait ses barres
aux mêmes endroits.

---

## 2026-10-21 — les barres de Merfin dans le pack

Demande de Cruzz : avoir les textures de barre de MerfinPlus sans dépendre de
l'addon. Sa licence est « All Rights Reserved » et interdit explicitement de
copier ou redistribuer ses fichiers ; Cruzz l'a su avant la copie et a choisi de
les publier quand même. Seules les 8 barres sont prises (pas les anneaux,
flèches, polices, sons ni l'art de ses options).
- **`Media/Merfin/`** : les 8 fichiers de `MerfinPlus/Media/statusbar`, copiés à
  l'identique (`MerfinFlatt.tga`, qu'il n'inscrit nulle part, est laissé).
- **`Core.lua`** : inscription dans LibSharedMedia au chargement, sous les mêmes
  noms que MerfinPlus (« MerfinMain », « Flatt »…). Un choix fait par nom dans
  n'importe quel addon tient donc sans MerfinPlus ; avec lui, LSM garde la
  première inscription et les menus n'ont pas de doublon. Vérifié hors jeu avec
  la vraie LibSharedMedia (sans MerfinPlus, chargé avant, chargé après) ; pas
  encore vu en jeu.

---

## 2026-10-21 — essayé puis retiré : les titres en Goodmountain (Forever)

Essayé à la demande de Cruzz : les titres (nom de la fenêtre, titres de page,
catégories, popups, bannière de Home) dans la police Goodmountain
(Hermann-S-Designs/Goodmountain, licence compatible si `LICENSE.md` est joint et
le fichier ni modifié ni renommé). Même réduits d'environ un tiers, Cruzz ne
l'a pas aimé : tout est revenu à l'état de la 2.8.1, fichiers de police
compris. Rien n'a été publié.

---

## 2026-10-21 — v2.8.1 : export, import et sélecteur de couleur au-dessus des options

Retour de Cruzz : la fenêtre d'export / import et le sélecteur de couleur
s'ouvraient sous la fenêtre d'options. Celle-ci est en `FULLSCREEN_DIALOG`
(choisi pour passer au-dessus des barres des autres addons) ; le dialogue de
profil était en `DIALOG`, et le `ColorPickerFrame` de Blizzard a sa propre
strate, plus basse.
- **`Core/Theme.lua`** : `GUI.OVER_WINDOW = 300`, le niveau au-dessus de tout
  ce que la fenêtre utilise (son cadre à +20, les listes à 220).
- **`Pages/Home.lua`** : le dialogue de profil passe en `FULLSCREEN_DIALOG`,
  niveau `GUI.OVER_WINDOW`.
- **`Core/ColorWidgets.lua`** : `ShowPickerOverWindow` monte le sélecteur dans
  la même strate le temps qu'une de nos pastilles l'a ouvert, et le remet à sa
  strate et son niveau d'origine à sa fermeture (accroché à son `OnHide`), pour
  les autres addons. L'origine est notée après l'appel à
  `SetupColorPickerAndShow`, qui peut cacher puis réafficher un sélecteur déjà
  ouvert.

**Suite : la demande de rechargement aussi.** `SP.CreateReloadPrompt` est un
`StaticPopup` de Blizzard, que `StaticPopup_Show` place en `DIALOG`
(`StaticPopup_SetUpPosition`, branche `forever`), sous la fenêtre.
- **`Core.lua`** : la définition du popup gagne `OnShow` / `OnHide`
  (`RaiseReloadPrompt`, `LowerReloadPrompt`) : `FULLSCREEN_DIALOG` au niveau
  `SP.OVER_OPTIONS` tant qu'il est affiché, puis retour à sa strate et son
  niveau, car les cadres de popup de Blizzard sont partagés. `OnShow` passe
  après le placement, donc la montée tient ; on remonte aussi le cadre que
  rend `StaticPopup_Show`, pour un popup redemandé alors qu'il est déjà
  affiché (pas de second `OnShow`).
- `SP.OVER_OPTIONS = 300` vit dans l'addon parent ; `GUI.OVER_WINDOW` le lit.

**Suite : la fenêtre d'export / import à la Plumber (Forever).**
- **`Pages/Home.lua`** : cadre, cuir et bouton de fermeture de Plumber
  (`Skin.PlumberFrame`), œil de démon devant le titre, séparateurs de Plumber
  sous l'en-tête et au-dessus du pied, texte dans sa boîte sombre à liseré
  bronze, défilement par le `MinimalScrollBar` du jeu (une `ScrollFrame` nue,
  `ScrollUtil` gère la molette), bouton du jeu à 22 de haut. Retail inchangé.
- **`Core/Skin.lua`** : la boîte sombre des listes déroulantes devient
  `Skin.PlumberBox`, partagée avec `Widgets.lua`.

Pas relu en jeu.

---

## 2026-10-21 — v2.8.0 : la fenêtre d'options au style Forever

Demande de Cruzz : la fenêtre d'options doit avoir le style Forever, comme
NeedRoll et Keep or Toss. Lu avant : le skin « native » de NeedRoll v0.15.2,
Keep or Toss: Forever 1.3.0, et le FrameXML de la branche `forever`
(`Camelot`) de Gethe/wow-ui-source. Les deux addons bâtissent leur fenêtre avec
les modèles du jeu, que le client Forever dessine avec son propre art.

Retail ne change pas : tout est derrière `GUI.FOREVER` (même test que les
`IS_FOREVER` des modules). Aucune page touchée.

**`Core/Theme.lua`** :
- Palette propre à la fenêtre sur Forever, celle de NeedRoll : or `FFD100`,
  blanc, gris `A0A0A0`, fonds noirs. Une copie de `SP.Theme`, pas une
  réécriture : la couleur « thème » des modules reste rouge. Bordures opaques
  (or assombri), parce que plusieurs survols et remises à zéro écrivent la
  bordure à alpha 1.
- Police du jeu (`STANDARD_TEXT_FONT`) au lieu d'Expressway.
- `Backdrop` et `Tex` multiplient l'alpha de la palette (cartes translucides
  sur le marbre). Sans effet sur retail : ses couleurs sont toutes opaques.
- `GUI.POPUP_LEVEL` : 700 sur Forever, 220 ailleurs. Le portrait (400), le
  titre et la croix (510) du modèle passeraient sinon au-dessus des listes.

**`Core/Shell.lua`** :
- Fenêtre `ButtonFrameTemplate` : cadre métal, titre « Suspicion's Pack », croix
  du jeu. Le logo, en rouge, dans l'anneau du portrait sur un disque noir ; un
  clic ramène à Home comme avant.
- Catégorie › page et version dans la bande sous le titre.
- Liste et page dans deux `InsetFrameTemplate`, liste élargie à 200 (la police
  du jeu est plus large).
- Recherche en `SearchBoxTemplate`, nos scripts accrochés après les siens.
  L'ancienne recherche passe telle quelle dans `BuildFlatSearch`.
- Catégories : bouton +/− et nom en or. Pages : survol
  `UI-QuestTitleHighlight`, sélection `UI-QuestLogTitleHighlight` teintée bleu
  (NeedRoll). Barre de défilement fine, piste blanche pâle, curseur gris.
- En bas : profil, Changelog et Reset page en boutons du jeu, poignée
  `UI-ChatIM-SizeGrabber`.

**`Core/Layout.lua`** : titre de carte en or sur un bandeau or en dégradé avec
un trait à gauche (Keep or Toss) ; titre de page en or 16.

**`Core/Widgets.lua`** :
- Interrupteur → case `UICheckButtonTemplate` 24. La ligne entière reste
  cliquable ; le survol allume la case.
- Slider → `MinimalSliderTemplate`, sans remplissage, grisé à la main quand il
  est désactivé.
- Valeur du slider et champs texte → `InputBoxTemplate` (`NewInputBox`).
- Boutons → `UIPanelButtonTemplate`, élargis au texte à chaque `SetText` ;
  « actif » = `LockHighlight`.
- Les deux dessins de l'interrupteur sont sortis de `W.Toggle`
  (`BuildSwitch`, `BuildCheck`) ; clic, état et binding restent partagés.

Vérifié : les quatre fichiers se lisent en Lua 5.1 (luaparse) et ne lisent
aucune globale inattendue. Les modèles et atlas utilisés existent dans le
FrameXML `forever`. Pas relu en jeu ; suite hors ligne impossible ici (ni
Python ni Lua). Hors champ : le popup du changelog (addon parent).

**Suite, même jour, après le premier essai de Cruzz :**
- **`Pages/Home.lua`** : la ligne d'aide « Search the box at the top of the
  sidebar… Reset page… » est retirée, sur tous les clients.
- **`Core/Shell.lua`** : sur Forever, le logo de la fenêtre devient l'œil de
  démon de la guilde, l'emblème de tabard du jeu
  (`Interface\GuildFrame\GuildEmblemsLG_01`, 16 × 16 cases de 64, colonne 7,
  ligne 6), en gris clair comme sur le tabard. Repéré en aplatissant la
  planche de Gethe/wow-ui-textures sur fond noir ; la même planche existe dans
  les textures Classic et retail. Retail garde le logo rouge.

**Suite, deuxième essai :** l'œil était petit et décentré (42 de côté, centré
sur le masque, 2 plus haut que le portrait).
- L'œil couvre maintenant tout le rectangle du portrait, là où Blizzard pose
  ses propres icônes de portrait, et sa case est rognée de 4 de chaque côté.
- Sons de NeedRoll sur Forever : `IG_SPELLBOOK_OPEN` à l'ouverture,
  `UI_PROFESSIONS_WINDOW_CLOSE` à la fermeture. Alt+Z ne joue rien (même garde
  que NeedRoll : `IsShown` reste vrai, et un drapeau pour le retour).
- Barre de défilement de la page sur Forever : le `MinimalScrollBar` du jeu
  (celui du volet de statistiques), branché par
  `ScrollUtil.InitScrollFrameWithScrollBar` ; 80 par cran de molette au lieu
  des 30 de Blizzard, cachée quand la page tient. Retail garde sa barre fine,
  même largeur de page qu'avant. La barre des listes déroulantes reste fine.

**Suite, troisième essai :**
- **Sons dans la fenêtre (Forever)**, `GUI.Sound` dans `Core/Theme.lua` : ceux
  des menus du jeu sur la branche `forever` (`MenuVariants`) — option « on »
  pour un bouton, l'ouverture d'une liste et un choix dedans, « off » pour une
  liste refermée sans choix (re-clic ou clic à côté) ; onglet de personnage
  (comme les onglets de NeedRoll) pour changer de page depuis la liste, le
  logo ou Entrée dans la recherche ; on/off pour déplier/replier une
  catégorie. Les cases jouaient déjà leur son. Retail reste muet comme avant.
- **Marqueur on/off de la liste (Forever)** : le losange de WaypointUI (sa
  punaise de minicarte, cellule 1,1 de `Art/MapPinFrame/MapPinFrame.blp`,
  BLP non compressé décodé et recoupé en PNG 64) au lieu du point, teinté
  vert (activé) ou gris (coupé), sans la flèche. Nouveau fichier
  `SuspicionsPack/Media/GUITextures/diamond.png`. WaypointUI n'a pas de
  licence dans son dossier : l'art reste à son auteur, à revoir si le pack
  devient public.

**Suite, quatrième essai :** Cruzz veut le cadre du losange couleur Forever et
le vert à l'intérieur.
- Cadre teinté or cuivré (0.90, 0.72, 0.36), plus chaud que le `FFD100` du
  texte ; à 60 % quand le module est coupé.
- Nouveau `SuspicionsPack/Media/GUITextures/diamond-fill.png` : un losange
  plein à nous (rayon 14 autour du centre 31.5 de l'art, le centre noir en
  fait 18), ombré du haut-gauche au bas-droit, lissé 4 × 4. Teinté vert et
  affiché seulement quand le module est activé.
- `it:SetState(on)` remplace les deux copies du coloriage du point
  (`RefreshSidebar` et `UpdateDots`) ; retail garde son point, mêmes
  couleurs.

**Suite, cinquième essai : l'habillage de Plumber sur Forever.** Cruzz préfère
le cadre et le fond du panneau de réglages de Plumber, ses séparateurs, son
bouton de fermeture et ses couleurs de texte ; notre barre de défilement
reste. Relevé dans `Modules/ControlCenter/SettingsPanelNew.lua` de Plumber
(Raenore, Peterodox), copié dans `SuspicionsPack/Media/Plumber/` :
`SettingsPanel.png`, `SettingsPanelBackground.jpg`, `ExpansionBorder_TWW.tga`.
Pas de licence dans le dossier de Plumber : l'art reste à ses auteurs, à
revoir si le pack devient public.
- **`Core/Theme.lua`** : `GUI.PLUMBER` (les trois fichiers) et
  `GUI.PlumberRect` (un rectangle en pixels de ces fichiers 1024). Palette :
  texte crème 215,192,163, blanc au survol (`textHover`), notes 163,157,147,
  titres de section 148,124,102 (`heading`). Bande du haut 52, du bas 30,
  panneau latéral 230. `GUI.POPUP_LEVEL` retiré : sans le modèle de Blizzard,
  rien ne monte plus à 400-510, les listes reviennent à 220.
- **`Core/Shell.lua`** : fenêtre nue au lieu de `ButtonFrameTemplate`.
  `BuildPlumberChrome` : fond en cuir étiré à droite du panneau, les six
  pièces du panneau latéral (bord bronze de 40 centré sur sa limite), le cadre
  en huit pièces autour d'une boîte 24 à l'intérieur (coins 64), le coin
  haut-droit à logement et son bouton de fermeture cuivre (24, éclairé en ADD
  à 50 %). L'œil (recoupé à 48 × 22, sa vraie forme) et « Suspicion's Pack »
  ouvrent la bande du haut ; fil d'Ariane et version au-dessus de la page.
  Liste sous la recherche et le séparateur de Plumber. Changelog et Reset page
  deviennent ses onglets en cuir sous la fenêtre (`BuildPlumberTab`, 40 de
  haut, 7 d'écart, texte crème puis blanc). Profil et modifications restent
  dans la bande du bas. Liste : blanc au survol et sur la page ouverte.
- **`Core/Layout.lua`** : sur Forever les cartes n'ont plus de boîte ; leur
  titre devient l'en-tête de section de Plumber (losange 20, ligne bronze
  étirée jusqu'au bord droit, nom en `heading` au-dessus).

**Même jour, page Home (tous clients)** : Support et Notice avaient une ligne
vide sous leur texte, la dernière note de Profiles débordait du bas de sa
carte.
- `Card:Layout` : une carte sans ligne visible (seulement sa description)
  n'ajoute plus les deux marges qui encadrent les lignes ; `DESC_BOT` suffit.
- `W.Label` se remesure une image plus tard : au changement de largeur, le
  retour à la ligne n'était pas encore compté (une ligne au lieu de deux).

**Retouche :** la poignée de redimensionnement flottait à 14 du coin. Mesuré
dans le coin bas-droit du cadre (pixels 384-512 du TGA) : le bronze commence à
1 du bord de la fenêtre, son ombre à 4. Poignée à 2 du bord, contre le métal.

**Retouche (tous clients) :** « Search settings » restait affiché tant que la
recherche était vide, curseur dedans ou pas. Il disparaît dès que la case a le
focus et revient si on la quitte vide. Forever : accroché après les scripts de
`SearchBoxTemplate`, qui le réaffichent à chaque texte vide.

**Retouche (Forever) :** les cases de valeur des sliders, le champ du jeu à sa
taille d'origine (44 × 20, bouts de 8), paraissaient trop grosses. 38 × 16,
bouts ramenés à 6 et hauteur de l'art à 16, police 10 ; « -2000 » y tient
encore. Les champs texte (`W.EditBox`) gardent leur taille.

**Retouche (Forever) : les menus déroulants à la Plumber.** Ils gardaient la
boîte arrondie noire à bord or, la barre or et le texte or du premier essai.
Relevé dans `Modules/ExpansionLandingPage/Basic.lua` de Plumber (son
`CreateDropdownButton` et son menu) ; nouveau fichier
`SuspicionsPack/Media/Plumber/DropdownMenu.tga` (512).
- Bouton : trois tranches de `ExpansionBorder_TWW` (518-754 × 256-320, bouts
  20 et 32, 32 de haut, 2,5 au-delà des bords), les mêmes en ADD à 25 % au
  survol, carré-flèche cuivre 32 à 13,5 du bord droit (764-828), enfoncé
  (828-892) tant que la liste est ouverte, sa lueur au survol. Texte crème
  12, blanc au survol, de 8 à 32 du bord droit. Grisé : désaturé à 50 %.
- Liste : boîte noire à liseré bronze en neuf pièces (512-768 × 320-576,
  coins 16 centrés sur ses coins), lignes de 24 à 6 du haut et du bas,
  pastille radio 16 à 8 (`DropdownMenu.tga` 0-64 × 0-32) devant chaque ligne,
  texte crème puis blanc sur la barre brune en ADD (368-512 × 0-48, teinte
  119,96,74). 6 entre le bouton et la liste. Barre de défilement fine en blanc
  pâle et gris.
- `GUI.PlumberRect` prend une taille de fichier (512 pour ce dernier).

**Retouche des menus déroulants (Forever) :** trop hauts, et la barre de la
liste détonnait.
- L'art du bouton est dessiné aux trois quarts de Plumber (`DD_ART`) : 24 de
  haut autour de nos 22 au lieu de 32, carré-flèche 24. Lignes de la liste à
  20 au lieu de 24.
- La liste défile avec le `MinimalScrollBar` du jeu, branché comme celui de la
  page (`ScrollUtil.InitScrollFrameWithScrollBar`, 2 lignes par cran), caché
  quand tout tient.
- Tous clients : une entrée de liste reste sur une ligne
  (`SetWordWrap(false)`) ; un long nom de police dans sa propre fonte passait
  à la ligne et débordait sur la suivante.

**Retouches (Forever) :**
- La valeur d'un slider n'était pas centrée : `InputBoxTemplate` accroche son
  bout gauche 5 en dehors de la case, l'art était donc décalé à gauche du
  texte. Le bout gauche est ramené au bord de la case ; le slider s'arrête de
  nouveau à 10 de la case (`INPUT_ART_LEFT` retiré).
- Panneau latéral de 230 à 210 : la liste était à moitié vide. Le plus long
  nom de page tient encore (« Enhanced objective text », environ 135 sur 138).
- Poignée de redimensionnement : à 2 du bord, la pointe de ses hachures
  restait à distance du bronze (l'art garde une marge dans sa texture). Le
  coin de la texture passe à 1 au-delà du coin de la fenêtre. Teintée de l'or
  cuivré des losanges (`MARKER_GOLD`) au lieu du gris de la fenêtre de chat.

**Correctif (tous clients) :** la barre de défilement d'une liste déroulante
apparaissait pendant l'ouverture, même pour quatre entrées. Sa visibilité
suivait la plage de défilement réelle, et pendant le glissement la boîte est
plus courte que ses lignes. Elle suit maintenant `pop:Overflows()` : plus de
lignes que la boîte n'en montre à pleine hauteur (10).

**Le popup « What's new » à la Plumber (Forever).** Il restait au style plat.
Il vit dans l'addon parent (affiché à la connexion, avant l'addon d'options),
donc les pièces de Plumber y descendent :
- **`Core/Skin.lua`** : `Skin.FOREVER`, `Skin.PLUMBER` (les fichiers),
  `Skin.FOREVER_TEXT` (or, crème, lisible, titres), `Skin.DEMON_EYE`,
  `Skin.PlumberRect`, `Skin.PlumberFrame` (fond, cadre, bouton de fermeture),
  `Skin.PlumberHeader` (losange et ligne sous un libellé),
  `Skin.PlumberDivider`. Les options s'en servent au lieu de leurs copies
  (`Theme.lua`, `Shell.lua`, `Layout.lua`).
- **`Core.lua`, `SP.ShowChangelogPopup`** : sur Forever, cadre et cuir de
  Plumber, œil et « What's new » en or, police du jeu, séparateurs de Plumber
  sous l'en-tête et au-dessus du pied, un en-tête de section par version (la
  dernière en or, les autres en brun), texte en couleur lisible (badges
  inchangés), `MinimalScrollBar` et bouton « Got it » du jeu. Retail
  identique ; la tranche lue par `tests/test_gui.lua` ne touche aux noms
  propres à Forever que derrière `Skin.FOREVER`.

---

## 2026-10-21 — v2.8.0 : skin Details TWW en Expressway

Demande de Cruzz : la police du skin TWW passe en Expressway.

**`DetailsSkin.lua`** :
- Les trois polices du skin (texte des barres, titre de la fenêtre, micro
  frames) passent de Friz Quadrata / Accidental Presidency à Expressway.
  Details les résout par nom LibSharedMedia ; « Expressway » est enregistré
  par DeathAlert, chargé avant. Tailles inchangées.
- `ApplyToAll` force l'application complète. `ChangeSkin` ne recopie les
  réglages du skin (polices comprises) que quand la fenêtre change de skin :
  sur une fenêtre déjà en TWW, le bouton ne faisait rien et l'ancienne police
  restait. Le nom du skin est vidé avant, comme un choix depuis la liste de
  Details ; position, échelle et strata sont gardées, les autres retouches de
  la fenêtre repartent aux valeurs du skin.

**`Pages/DetailsSkin.lua`** : la description du bouton le dit.

Pas relu en jeu. Copié dans l'install Forever beta. À vérifier : « Apply to
all Details windows » met Expressway sur une fenêtre déjà en TWW.

---

## 2026-10-21 — v2.8.0 : le portrait ne bouge plus quand on dégaine

Retour de Cruzz : le portrait animé bouge un peu quand il dégaine ou rengaine.
Cause : `ToggleSheath` déclenche `UNIT_MODEL_CHANGED` (warcraft.wiki.gg,
« Triggers events »), et le module recharge le modèle sur cet événement
(`SetUnit` à nouveau) : l'animation d'attente repart de sa première image et
la caméra est reposée avant puis après le chargement.

**`AnimatedPortraits.lua`** :
- `UNIT_MODEL_CHANGED` sur le joueur compare `GetSheathState()`,
  `GetShapeshiftFormID()` et `IsMounted()` à leur valeur au changement
  précédent. Seul le fourreau a changé : pas de rechargement. Sinon (stuff,
  forme, monture, transmo) : rechargement comme avant.
- Une seule décision par image : l'événement arrive une fois par jeton qui
  vous désigne (`player`, `target` si on se cible…), le premier décide pour
  les suivants.
- Valeur secrète : pas de comparaison, rechargement.
- Les autres unités (groupe, cible) se rechargent toujours : leur fourreau
  ne se lit pas.
- Limite : le modèle garde les armes d'avant jusqu'au prochain rechargement
  (invisible au zoom visage, visible en plan large).
- Trace sous `SuspicionsPack.DEBUG` : ancien → nouvel état, « kept » ou
  « reloaded ».

Pas relu en jeu. À vérifier : un seul « kept » par dégainage, et « reloaded »
pour une forme, une monture et un changement de stuff.

**Suite, même jour : le stuff ne se mettait pas à jour.** Trace de Cruzz en
changeant d'épaulières : « sheath 1 -> 1 … reloaded » à l'équipement et au
retrait, un seul événement par changement, mais le portrait gardait les
anciennes. Le rechargement avait bien lieu : `SetUnit` sur l'unité que le
modèle a déjà ne reprend pas son apparence. Bug antérieur à l'entrée
ci-dessus. L'inspection de Blizzard répond à `UNIT_MODEL_CHANGED` par
`InspectModelFrame:RefreshUnit()` (`InspectPaperDollFrame.lua`, branche
`live` de Gethe/wow-ui-source ; `RefreshUnit` existe aussi sur `forever`).
- Même unité déjà à l'écran (stuff, forme, cadre réaffiché) : `RefreshUnit`.
  Nouvelle unité : `ClearModel` + `SetUnit` comme avant.
- Pas de test `IsUnitModelReadyForUI` (la garde-robe et la transmo de
  Blizzard l'utilisent avant `RefreshUnit`) : la trace ne montre qu'un
  événement par changement, il n'y aurait pas de second essai. À ajouter si
  le portrait reste en retard d'un changement.

Pas relu en jeu.

---

## 2026-10-21 — v2.8.0 : PlayerDragon sur les cadres EllesmereUI

Retour de Cruzz après le premier essai sur Forever : « doesn't work ». Le module
tournait (`playerDragon.enabled = true` dans les SavedVariables, aucune erreur
dans BugGrabber), mais dessinait sur le `PlayerFrame` de Blizzard, caché :
le cadre à l'écran est celui d'EllesmereUIUnitFrames (9.6.1), style « WoW
Forever ». Son propre « Player Frame Dragon » ne s'affiche pas sous un style
stock (`ns.UF_ApplyPortraitDragon` exige `not ns.UF_Blizz()`), il n'y avait
donc rien à activer de leur côté.

**Lu dans EllesmereUI, sans le modifier** (`EUI_UnitFrames_StockStyles.lua`,
`EUI_UnitFrames_Portrait.lua`, `EllesmereUI_RetailAtlas.lua`) :
- Cadre `EllesmereUIUnitFrames_Player`, portrait `frame.Portrait.backdrop`.
  Kit Forever : portrait joueur `TOPLEFT 24,-19`, 60 px, comme Blizzard. Leur
  dragon de cible reprend exactement nos décalages Forever.
- Niveaux : portrait à `_barClip − 2`, cadre d'art (`_blizzArtFrame`) à
  `_barClip − 1`, barres à `_barClip`, badge de niveau à `_barClip + 12`. Leur
  dragon de cible est une texture du cadre d'art, `BACKGROUND` 2, au-dessus
  de l'art (`BACKGROUND` 0) et sous les barres.
- Un cadre complet n'est jamais retourné : portrait à droite = la géométrie de
  la cible (`_blizzGeom.portrait.point == "TOPRIGHT"`).
- `SetAtlas` puis `SetTexCoord` lit les coordonnées DANS la boîte de l'atlas :
  un dessin retourné passe par le fichier de l'atlas et ses coordonnées
  inversées (`C_Texture.GetAtlasInfo`).

**`PlayerDragon.lua`** :
- Un dragon par cadre joueur : celui de Blizzard (inchangé) et celui
  d'EllesmereUI sous un kit stock (art en chaîne, donc pas le kit Classic).
  Chacun disparaît avec son cadre.
- Côté EllesmereUI, la texture va sur leur cadre d'art, `BACKGROUND` 2, comme
  leur dragon de cible : au-dessus de l'anneau, sous les barres et le badge de
  niveau. Un cadre à nous ne trouve pas cette place : au niveau du cadre d'art
  il est à égalité (ordre non garanti, leur propre commentaire le dit), au
  niveau des barres ou au-dessus il couvre leurs extrémités, ce que le dragon
  de la cible ne fait pas.
- Posé à chaque `SetPoint` du portrait (`hooksecurefunc`, un hook par
  portrait) : leur passe de mise en page se termine par là, après la création
  du cadre d'art, à la connexion, à chaque réglage et au changement de côté.
  `PLAYER_ENTERING_WORLD` couvre le cas où leurs cadres naissent après notre
  `Activate`.
- Kit Forever (seul à avoir `badge`) : art Forever. Sinon art retail, lu par
  `EllesmereUI.StockAtlasInfo`, qui rend les planches retail du style
  « Blizzard Style » sur le client Forever.
- Le miroir passe partout par fichier + coordonnées inversées (au lieu de
  `SetAtlas` + `GetTexCoord`, de l'entrée précédente).
- Style EllesmereUI sans kit stock (« eui ») et kit « Classic WoW UI » : rien
  n'est dessiné. Le premier a son propre Player Frame Dragon ; le second
  dessine les cadres vanilla, sans l'anneau moderne.

**Page** : la description dit sur quels cadres le dragon s'affiche ; mot-clé
« ellesmereui ». Pas de changement de `.toc`.

Pas relu en jeu ; suite hors ligne toujours impossible (ni Python ni Lua).

---

## 2026-10-21 — v2.8.0 : nouveau module, le dragon autour du portrait joueur

Demande de Cruzz, capture à l'appui (Forever, cadres Blizzard par défaut) : le
dragon doré d'un élite (Overlord Runthak) autour du portrait de la cible, voulu
autour du portrait du joueur, en argent comme pour un monstre rare.

**L'art, relevé dans le code Blizzard** (Gethe/wow-ui-source, `live` 12.1.5
70448 et `forever` 1.60.1 70450) et dans `UiTextureAtlasMember` (wago.tools,
builds 12.1.5.70448 et 1.60.1.70245) :
- Retail : en dur dans `TargetFrame.lua`, `CheckClassification`. Argent
  `ui-hud-unitframe-target-portraiton-boss-rare-silver` (80×79, rare élite
  seulement), or `UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold` (80×79), boss
  `…-Boss-Gold-Winged` (99×81). `TOPRIGHT` à −11,−8 (boss 8,−8).
- Forever : `Camelot/TargetFrameUtils.lua`, `GetBossPortraitFrameData`, chargé à
  la place de celui de Mainline. Mêmes noms, mais un art propre (membres
  `-c60`), et un dragon argent ailé que retail n'a pas :
  `UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Silver-Winged` (110×89), montré
  pour rare ET rare élite, à 8,−7. Or 100×100 à 0,1, boss 110×90 à 11,−4.

**Le module.** `Modules/PlayerDragon/PlayerDragon.lua` (`SP:NewSPModule`,
`Activate`/`Deactivate`).
- Une texture sur `PlayerFrame.PlayerFrameContainer`, là où la cible porte son
  `BossPortraitFrameTexture`. Badge de niveau, icônes repos et combat, coin
  décoratif et badge de prestige sont sur `PlayerFrameContent`, un niveau
  au-dessus : ils restent dessinés par-dessus le dragon, comme sur la cible.
  Couche OVERLAY 1, au-dessus du flash de combat (OVERLAY 0), comme le dragon de
  la cible au-dessus de son flash.
- Une table par client (`IS_FOREVER`), recopiée des sources ci-dessus. Le
  décalage de la cible est pris depuis le centre de son portrait (58 px à
  −26,−19), puis reporté en miroir à gauche du centre du portrait joueur.
- Miroir horizontal : `GetTexCoord` relu après `SetAtlas`, gauche et droite
  échangées dans ce rectangle (jamais 0..1, cf. leçon du 2026-10-20), et
  seulement s'il se lit encore de gauche à droite : remettre le même atlas
  peut garder notre rectangle retourné.
- Atlas inconnu du client (`C_Texture.GetAtlasInfo` nil) : rien ne s'affiche.
- Caché tant que le cadre véhicule est affiché : `hooksecurefunc` sur
  `PlayerFrame_ToVehicleArt` et `PlayerFrame_ToPlayerArt` (présentes sur les
  deux clients), qui relisent `VehicleFrameTexture:IsShown()`.
- `AnimatedPortraits` glisse ses modèles une strate sous le cadre
  (`STRATA_BELOW`) : le dragon passe au-dessus sans rien régler.
- Le dragon se pose sur l'anneau, il ne le remplace pas : l'anneau fait partie
  de `FrameTexture`, qui porte aussi le cadre des barres. La cible fait pareil.

**Réglages.** `Core.lua` : `playerDragon = { enabled = false, style = "silver" }`.
Page `Pages/PlayerDragon.lua` (« Player dragon », catégorie Interface) :
l'interrupteur et une liste « Dragon » : Silver (rare), Gold (elite), Gold
winged (boss). Les deux `.toc` listent les fichiers sans condition.

Pas relu en jeu. `python3 tests/run.py --syntax` n'a pas pu tourner (ni Python
ni Lua sur cette machine) ; seul un comptage grossier des blocs et des
parenthèses (Node) est passé sur les deux nouveaux fichiers.

---

## 2026-10-21 — v2.8.0 : CleanObjectiveTrackerHeader, le bouton de repli

Demande de Cruzz, capture à l'appui (Forever) : le module masquait le titre
« Objectives » et son fond, mais laissait le bouton rouge « tout replier » seul
à droite, au-dessus de « Quests ».

**Le bouton.** `ObjectiveTrackerFrame.Header.MinimizeButton`, atlas
`ui-questtrackerbutton-collapse-all`. Vérifié dans le code Blizzard des branches
`forever` et `live` de Gethe/wow-ui-source : même cadre, même nom, même
`IsCollapsed()` sur les deux clients.

**L'option.** Nouvelle clé `hideMinimizeButton` (« Hide collapse button »),
activée par défaut, dans la carte General de la page.
- `CleanObjectiveTrackerHeader.lua` : `UpdateMinimizeButton` masque le bouton
  quand le module et l'option sont actifs, et ne le réaffiche que s'il l'a
  lui-même masqué (`buttonHidden`). Appelé à l'activation, dans le hook
  existant sur `Header:Show` (le traqueur le rappelle à chaque mise à jour,
  repli et dépli compris) et sur `OnShow` du bouton, car Forever le réaffiche
  en quittant le mode manette (`UninitializeGamepad`).
- Le bouton reste visible tant que le traqueur est replié : sans le titre,
  c'est le seul moyen de le rouvrir. L'état replié n'est pas sauvegardé
  (`OnLoad` repart déplié), mais activer l'option traqueur replié l'aurait
  laissé fermé jusqu'au prochain `/reload`.
- `Core.lua` : défaut `hideMinimizeButton = true`. Ceux qui ont déjà le
  module actif perdent le bouton à la mise à jour, c'est le but du module.
- `Pages/CleanObjectiveHeader.lua` : le toggle et les mots-clés de recherche.

Pas relu en jeu ; la suite hors ligne n'a pas tourné (ni Python ni Lua sur
cette machine).

---

## 2026-10-20 — v2.7.3 : nouveau module, portraits animés

Des modèles 3D vivants à la place des portraits plats : cadres d'unité,
groupe, PNJ à qui l'on parle, fenêtres qui affichent un personnage. Coupé par
défaut, catégorie Interface. Chargé sur Midnight et sur Forever, sans gate.

**Le principe.** Le jeu dessine chaque portrait par
`SetPortraitTexture(texture, unit)`, qui est accroché ; chaque texture reçoit
son propre `PlayerModel` posé dessus, et l'image plate devient invisible tant
que le modèle s'affiche. Un disque derrière et un fondu sur les bords masquent
les coins carrés du modèle sur les portraits ronds ; sur un cadre d'unité, les
trois cadres passent une strate en dessous pour que l'anneau et le badge de
niveau restent dessus. La texture de fondu est générée pour le pack
(`Media/Portraits/fade.tga`, profil radial).

**Ce qui est amélioré.**
- Intégré au cycle de vie du pack (`Activate` idempotent, `Deactivate` remet
  toutes les images plates), à sa page d'options et à `/spack debug portraits`.
  Plus de fenêtre, de slash, de bouton minimap ni de locales à part.
- Un interrupteur par cadre au lieu de trois catégories : joueur, cible,
  focus, familier, cible de la cible, groupe, boss et arène, autres cadres,
  fenêtres de PNJ, fenêtres de personnage. Un portrait du joueur dans la
  fenêtre de personnage compte comme fenêtre, plus comme « joueur ».
- Cadrage : taille du visage 60 à 130 % (l'original bridait à 70-85), zoom de
  portrait, rotation, visages tournés l'un vers l'autre, décalages, opacité
  du modèle.
- Anneau noir entre le modèle et le cadre doré (capture de Cruzz) : le carré
  du modèle était bloqué à 80 % du cercle, `min(taille du visage, 0.80)`, et le
  disque sombre se voyait dans l'écart. Deux réglages séparés désormais :
  `frameFill` (« Reach the frame », 70 à 100 %, 90 par défaut) fixe jusqu'où
  le carré s'étend vers l'anneau, et `size` ne bouge plus que la caméra. Sur
  un portrait de 58 px, l'écart passe d'environ 6 px à 3 px par côté à 90 %, et
  à 0 à 100 %. Au-delà d'environ 90 %, les coins du carré peuvent dépasser de
  l'anneau en diagonale, là où se trouvent souvent les barres et le badge de
  niveau. Les fenêtres gardent 70 %, car aucun anneau ne cache leurs coins.
- « Faces look at each other » (clé `mirrorTargetSide`, gardée) : la première
  version inversait seulement le signe de la rotation, donc à la rotation par
  défaut de 0 elle ne faisait rien — signalé par Cruzz. Chaque côté tourne
  désormais vers l'intérieur de `faceTurn` degrés (25 par défaut) : joueur,
  familier et groupe vers la droite, cible, focus et boss vers la gauche, en
  miroir de la rotation choisie. Le sens suppose qu'un `SetFacing` positif
  tourne le visage vers la droite de l'écran ; une valeur négative du curseur
  inverse si ce client tourne dans l'autre sens.
- Fond : disque et fondu séparables, couleur sombre, de la classe de l'unité,
  du thème ou personnalisée, avec opacité.
- Animation : animer ou figer, animation choisie, PNJ qui parlent pendant le
  dialogue, immobiles en combat. Le gel passe par `SetPaused`, avec repli sur
  `FreezeAnimation` si ce type de modèle ne l'a pas.
- Comportement : garder l'image du jeu pour un mort, un fantôme, une unité
  prise ou hors ligne, ou garder le modèle ; images plates en combat ; taille
  minimale réglable.
- À l'activation, les portraits déjà à l'écran sont redemandés au jeu (hors
  combat), au lieu d'attendre son prochain redessin.
- Activer le module depuis sa page affiche l'invite de rechargement du pack
  (`SP.CreateReloadPrompt`, jusqu'ici jamais appelée) : Cruzz a constaté qu'il
  faut un `/reload` pour que les portraits changent. Branchée en enveloppant
  le `onToggle` de l'interrupteur principal, comme le fait `Page:Gate`.

Toutes les valeurs lues sur une unité passent par `issecretvalue` avant toute
comparaison, comme dans l'original.

**Non testé en jeu**, ni sur Forever ni sur Midnight. Points à regarder :
l'existence de `SetPaused`, `SetFacing` et `FreezeAnimation` sur un
`PlayerModel` de ce client, les identifiants d'animation (0 debout, 60 parler,
69 danser, 4 marcher, 5 courir), et les chemins des portraits de la passe
d'activation.

Fichiers : `SuspicionsPack/Modules/AnimatedPortraits/AnimatedPortraits.lua`,
`SuspicionsPack_Config/Pages/AnimatedPortraits.lua`,
`SuspicionsPack/Media/Portraits/fade.tga`, `SuspicionsPack/Core.lua`
(défauts `animatedPortraits`, sous-commande `/spack debug portraits`), les deux
`.toc`.

---

## 2026-10-20 — v2.7.3 : MicroMenuSkin, la planche entière dans chaque bouton

Rapport de Cruzz après la 2.7.2, capture à l'appui : au survol ou au clic,
chaque bouton du micro-menu affiche « plein de petites icônes ». C'est la
planche d'atlas de Blizzard tout entière, réduite dans un bouton.

**La cause.** `ZoomTexture` recadrait l'icône en remplaçant l'atlas par son
fichier, puis retenait le nom de l'atlas pour retrouver le sous-rectangle aux
passes suivantes. Quand `GetAtlas()` ne renvoyait rien et qu'aucun nom n'était
retenu, la fonction tombait dans sa dernière branche : un recadrage relatif à
0..1, c'est-à-dire à la planche entière. Le commentaire du code décrivait déjà
ce risque ; le chemin restait ouvert.

**Le correctif.** Le recadrage se fait désormais DANS le rectangle que la
texture affiche réellement, relu par `GetTexCoord`, et le fichier n'est plus
jamais changé. Le rectangle d'origine est retenu par texture (`_spUV`), et
`_spOut` garde le dernier rectangle posé par le skin : si la texture montre
encore exactement celui-là, l'origine est celle déjà retenue ; sinon Blizzard a
réécrit l'art et ce qu'elle montre est la nouvelle origine. Plus aucun nom
d'atlas, plus de `GetAtlasInfo`, plus de cache. La restauration remet le
rectangle d'origine, et seulement si Blizzard n'a pas réécrit l'art entre-temps.

Vérifié par une transcription ligne à ligne en JavaScript sur une texture
simulée (huit scénarios : première passe, passes répétées, art réinitialisé,
changement d'atlas, zoom à 0, deux cas de restauration, 50 passes mêlées) :
l'icône ne dépasse jamais la largeur d'une icône. **Non testé en jeu.**

En plus : `OnEnter`, `OnMouseDown` et `OnMouseUp` réappliquent l'icône après
Blizzard, et avec `SP.DEBUG` chaque événement imprime l'état du bouton (état,
atlas, texture, alpha et coordonnées de l'icône, surbrillance).

**Les boutons tressaillaient au clic** (rapport de Cruzz). Trois sauts d'un
pixel, tous voulus par Blizzard pour son bouton en relief :
- l'état enfoncé affiche l'atlas `-Down`, la même icône dessinée enfoncée et
  décalée. Il affiche maintenant l'atlas `-Up` du bouton (nom tiré de
  `button.textureName`, existence vérifiée une fois), teinté comme avant —
  le choix d'ElvUI ;
- `CharacterMicroButtonMixin:SetPushed/SetNormal` déplace le portrait, et le
  skin le remettait en place une image plus tard via `QueueApply` : c'était
  le saut visible. Remis en place dans la même image (`PinPressArt`) ;
- `GuildMicroButtonMixin` déplace l'emblème de guilde de la même façon ; il
  est épinglé à sa position de repos.
`QueueApply` et son drapeau n'avaient plus d'appelant et sont retirés.

**Ça tressaillait encore** (deuxième rapport). En suivant tout ce qu'un clic
déclenche : un clic qui ouvre une fenêtre fait appeler `UpdateMicroButtons`,
et le skin repasse sur toute la barre (`ApplySkin`) alors que le curseur est
toujours sur le bouton. Cette passe défaisait l'état de survol :
- la bordure était repeinte avec la couleur de repos : l'accent de survol
  s'éteignait au clic, **avec les réglages par défaut** ;
- `ApplyAlpha(false)` faisait retomber toute la barre à son opacité estompée
  sous le curseur, avec « Full opacity on mouseover » ;
- l'icône redevenait grise sous le curseur, avec « Desaturate icons ».
La passe lit maintenant le survol (`IsHovered`, `MicroMenu:IsMouseOver()`) et
peint la même chose que les gestionnaires de survol.

Aussi : `SetPushed` passe la surbrillance en additif à 50 %, `SetNormal` la
remet en normal à 100 %, d'où une pulsation de la lueur à chaque clic.
`PinPressArt` est désormais posé sur tous les boutons et la garde constante.
Enfin, les réapplications ajoutées au survol et au clic (avant de trouver la
vraie cause des petites icônes) refaisaient tout le skin et remettaient le
gris sous le curseur : elles ne font plus que tracer en mode debug.

**Troisième rapport, avec traces.** Sur `TalentMicroButton` (état PUSHED,
fenêtre ouverte), l'enfoncement et le relâchement montrent un état identique :
atlas `UI-HUD-MicroMenu-SpecTalents-Up`, fichier `8200846` partagé avec le
grimoire, UV `0.080..0.920`, alpha 1, surbrillance BLEND à 1. Deux faits :
l'icône elle-même ne bouge pas, et sur ce client les UV d'un atlas lus par
`GetTexCoord` sont relatifs au sous-rectangle (0..1), ce qui confirme le
nouveau `ZoomTexture`. Les traces ne montraient ni taille, ni position, ni
l'image enfoncée : elles ajoutent maintenant le rectangle du bouton, de
l'icône, de l'image enfoncée et de la barre, et une ligne à chaque
redimensionnement (`resize`) ou re-disposition (`relayout`) faite par le skin.

**La cause, enfin (captures avant/pendant le clic).** C'est le bouton
personnage : au clic, son portrait se réduit dans le coin et laisse voir
l'icône dessous. `CharacterMicroButtonMixin:SetPushed/SetNormal` ré-ancrent
le portrait avec des marges FIXES de 7 px (`TOPLEFT 7,-7`, `BOTTOMRIGHT -6,5`
enfoncé, `-7,7` au repos), prévues pour le bouton de 32 × 40 de Blizzard ; sur
un bouton skinné plus petit, ça donne un timbre. Le post-hook sur `SetPushed`
ne tenait pas sur ce client. Le portrait est désormais épinglé à la source :
`hooksecurefunc(portrait, "SetPoint", …)` le remet en place à chaque
déplacement, quel que soit le chemin, avec un garde `pinning` contre la
récursion. Même traitement pour l'emblème de guilde. Les traces affichent en
plus le rectangle du portrait et de l'emblème.

**Pas seulement le portrait** : Cruzz précise que tous les boutons
tressaillent quand on clique dessus. Le portrait était un cas visible, pas la
cause commune. Pendant le clic, le bouton affiche son image enfoncée, que les
traces ne mesuraient pas avant ce jour. En attendant les traces de cette
image, l'icône est réappliquée juste après l'enfoncement et le relâchement,
dans la même image : ça tient si le changement d'état réinitialise l'image
enfoncée. C'est sans risque maintenant que `ApplyNormal` lit le survol. Les
traces notent l'état avant cette réapplication. **Cause non confirmée.**

**Traces avec positions (bouton Quêtes).** Au repos, l'icône occupe tout le
bouton, 23,2 × 29 ; juste après un clic, elle est rentrée de 3 px de chaque
côté, 17,2 × 23 — la marge d'icône de Cruzz. Le tressaillement est ce
va-et-vient. Le skin applique toujours la marge et n'ancre jamais ces
textures sur tout le bouton : quelque chose côté Blizzard les ré-ancre entre
deux passes, sans passer par les setters surveillés. Correctif sur le modèle
du portrait : les textures normale, enfoncée, désactivée et de surbrillance
sont épinglées à leur propre `SetPoint`/`SetAllPoints`. Le garde `pinning`
vit désormais avec `SetInside`, pour que les placements du skin ne soient
jamais pris pour ceux de Blizzard. En mode debug, chaque ré-ancrage imprime
l'appelant (`debugstack`). Si l'icône reste pleine taille au repos sans
qu'aucune ligne « re-anchored by » n'apparaisse, le ré-ancrage vient du moteur
et non du Lua. À noter aussi : les deux tests précédents de Cruzz tournaient
sur une copie installée antérieure aux correctifs.

**Confirmé en jeu par Cruzz sur la bêta Forever (2026-10-20) : les boutons
ne tressaillent plus.**

Fichier : `SuspicionsPack/Modules/MicroMenuSkin/MicroMenuSkin.lua`.

---

## 2026-10-19 — v2.7.2 : Forever, trois retraits et le micro-menu

### Retirés sur Forever

- **CombatCross** regaté `[AllowLoadGameType standard]`, module et page : son
  sort de portée est choisi par spécialisation.
- **Automation** : « Auto accept decor prompt » et « Auto switch to flight
  form » sont ignorés sur Forever (pas de logement, pas de vol) et leurs
  interrupteurs n'apparaissent pas. Le module reste chargé, les autres
  automatismes aussi. Drapeau `Automation.IS_FOREVER`, même test en deux temps
  que MovementAlert.

### MicroMenuSkin sur Forever

Le skin parcourait une liste figée de noms de boutons. Sur Forever, Blizzard
construit la barre depuis `MicroMenuMixin:GenerateButtonInfos()`, qui diffère :
un bouton Legacy en plus, absent de notre liste, et Achievement en moins. Les
boutons écartés existent quand même en global, donc le skin redimensionnait des
cadres hors de la barre et ratait celui qui y était.

Le skin lit maintenant les enfants de `MicroMenu` qui ont un `layoutIndex`,
c'est-à-dire ceux que `AddButton` a réellement gardés, triés dans cet ordre. La
liste figée ne sert plus que de repli. Le résultat est mis en cache et
reconstruit à chaque `Activate`, puisque `ApplySkin` tourne sur presque chaque
`UpdateMicroButtons`.

Forever dessine aussi le cadre de barre d'action autour du micro-menu
(`MicroMenu.BorderArt` et `.BackgroundArt`, dans
`Camelot\MainMenuBarMicroMenu.xml`). Ils passent à alpha 0 avec le skin et
reviennent avec lui ; sans effet sur retail, qui n'a pas ces textures.

**Non testé en jeu.** Avec `SP.DEBUG`, l'activation imprime la liste des
boutons trouvés, ce qui dira tout de suite si la lecture de la barre tient sur
le client Forever.

Fichiers : `SuspicionsPack/Modules/MicroMenuSkin/MicroMenuSkin.lua`,
`SuspicionsPack/Modules/Automation/Automation.lua`,
`SuspicionsPack_Config/Pages/Automation.lua`, les deux `.toc`.

---

## 2026-10-19 — v2.7.1 : MovementAlert et InterruptAlert sur WoW: Forever

### Une branche par classe, à côté de la branche par spécialisation

Les deux modules indexaient leurs sorts par specID et n'avaient que des IDs
Midnight ; Forever n'a pas de spécialisation, donc ils y restaient gated. Chacun
porte maintenant une table jumelle indexée par le jeton de classe d'`UnitClass`
(`FOREVER_MOVEMENT_ABILITIES`, `FOREVER_INTERRUPTS`), lue seulement quand
`WOW_PROJECT_CAMELOT ~= nil and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT`. La
constante est `nil` sur retail, d'où le test en deux temps : `WOW_PROJECT_ID ==
nil` serait simplement faux et passerait sans bruit. La branche retail ne touche
ni aux tables ni au flux existant.

**Les rangs.** En Vanilla chaque rang est un sort distinct, et
`UNIT_SPELLCAST_SUCCEEDED` porte l'ID du rang lancé. InterruptAlert met donc
TOUS les rangs dans l'ensemble de la classe. MovementAlert liste une capacité
comme une liste de rangs : le rang 1 est la clé stable (`disabledSpells`,
`spellOverrides`, nom et icône dans la page), et le dernier rang connu
(`IsPlayerSpell`) est l'ID dont la recharge est lue -- c'est celui sur la barre
d'action. La CVar `ShowAllSpellRanks` (défaut 0) ne cache les rangs inférieurs
que du grimoire.

**Les IDs.** Chacun est vérifié sur la branche Forever de Wowhead
(`https://www.wowhead.com/forever/spell=<ID>`, bêta, 2026-10-19), URL en
commentaire à côté de chaque entrée. Forever n'a PAS gardé tous les IDs de
Classic Era : Charge sauvage est renumérotée (`1238122`, lançable en félin et en
ours ; la variante Ours `16979` de Vanilla existe toujours). Tout le reste est
identique à Classic Era (Charge 100/6178/11578, Interception 20252/20616/20617,
Sprint 2983/8696/11305, Transfert 1953, Course 1850/9821 ; Volée de coups
6552/6554, Coup de bouclier 72/1671/1672, Coup de pied 1766-1769, Contresort
2139, Horion de terre 8042/8044/8045/8046/10412/10413/10414, Silence 15487,
Sonner 5211/6798/8983, Marteau de la justice 853/5588/5589/10308, Verrouillage
de sort 19244/19647).

**Choix de périmètre.** Déplacement : guerrier (Charge et Interception, deux
recharges séparées, désactivables une à une dans la page), voleur (Sprint), mage
(Transfert), druide (Course, Charge sauvage). Aspect du guépard, Loup fantôme et
Forme de voyage sont des bascules sans recharge ; paladin, prêtre et démoniste
n'ont rien. Interruptions : les sorts à effet « Interrupt Cast », plus deux
étourdissements -- Sonner et Marteau de la justice -- parce qu'ils sont les seuls
outils du druide ours et du paladin pour arrêter une incantation, et qu'un
étourdissement posé sur un lanceur lève bien `UNIT_SPELLCAST_INTERRUPTED`. Le
chasseur n'a aucune interruption en Vanilla ; la page le dit.

**Événements.** Sur Forever, MovementAlert ne s'abonne plus aux trois
événements de spé/talent ni aux deux de glow (pas de Time Spiral en Vanilla), et
écoute `SPELLS_CHANGED` à la place : c'est un rang appris qui change la liste.
InterruptAlert n'enregistre pas `PLAYER_SPECIALIZATION_CHANGED`. Sur retail, les
abonnements sont strictement les mêmes qu'avant.

**Gates levées.** Les quatre lignes `[AllowLoadGameType standard]` (deux
modules, deux pages) sont retirées des deux .toc, avec un commentaire qui dit
pourquoi ces deux-là sont bi-flavor.

**Non vérifié en jeu sur la bêta Forever** -- le test est à la charge de Cruzz.
Points à regarder en premier : (1) `C_Spell.GetSpellCooldown` sur un rang de
Charge rend-il `isOnGCD == false` et `timeUntilEndOfStartRecovery` pendant la
recharge, comme sur retail ; (2) `IsPlayerSpell` rend-il bien vrai pour un rang
inférieur appris ; (3) l'ID de la variante Félin de Charge sauvage, absent du
wiki et de Wowhead -- si le client la substitue au talent,
`C_Spell.GetOverrideSpell(1238122)` la résoudra, sinon il faudra l'ajouter ;
(4) `/run SuspicionsPack.DEBUG = true` imprime la charge utile réelle de
`UNIT_SPELLCAST_INTERRUPTED`, qui n'a pas été relue sur ce client.

Fichiers : `SuspicionsPack/Modules/MovementAlert/MovementAlert.lua`,
`SuspicionsPack/Modules/InterruptAlert/InterruptAlert.lua`,
`SuspicionsPack_Config/Pages/MovementAlert.lua`,
`SuspicionsPack_Config/Pages/InterruptAlert.lua`, `SuspicionsPack/Core.lua`
(ligne de changelog en jeu), les deux .toc, `tasks/wow-api-notes.md` (section
Forever).

---

## 2026-10-19 — v2.7.1 : .toc 12.1.5 et WoW: Forever, skin Details

### Interface : 120105 et 16001 dans les trois .toc

Midnight 12.1.5 est live depuis le 13 octobre et sa valeur `120105` manquait :
les trois addons étaient marqués obsolètes. Ajouté `120105` et `16001` (WoW:
Forever, bêta) à `SuspicionsPack.toc`, `SuspicionsPack_Config.toc` et
`SuspicionsPackClassIcons.toc`.

### Single TOC + gating par ligne, pas de fichiers suffixés

La recommandation du wiki (page TOC format, 17 octobre) et la pratique
d'ElvUI / LuckyoneUI / DBM / BigWigs depuis le 18 septembre : UN seul
`Addon.toc`, une ligne `## Interface:` multi-versions, et des conditions
`[AllowLoadGameType …]` en fin de ligne. Le pack était déjà en single TOC,
donc aucun renommage, et aucun redémarrage client imposé aux utilisateurs.

Forever (type de jeu `camelot`, famille Mainline, moteur 12.1.5, contenu
Vanilla niveau 60) n'a ni spécialisations, ni M+, ni Bloodlust, ni Silvermoon,
ni commandes d'artisanat, ni outil LFG, et sa liste de boss PvE est celle de Midnight.
Les 13 modules qui en dépendent
portent `[AllowLoadGameType standard]` dans `SuspicionsPack.toc`, et leurs
pages d'options le même marqueur dans `SuspicionsPack_Config.toc` (une page
s'enregistre elle-même, donc une page non chargée n'apparaît pas) :
AutoBuy, FilterExpansionOnly, AutoPlaystyle, GroupJoinedReminder,
BloodlustAlert, GatewayAlert, TankMD, FocusTargetMarker, SpellEffectAlpha,
ReapPredict, PotionAlert, SilvermoonMapIcon, AutoRelease.

MovementAlert et InterruptAlert l'ont porté le temps d'une session : leurs tables
de sorts étaient indexées par spécialisation et ne connaissaient que les IDs
Midnight. Ils ont depuis une branche par classe, voir l'entrée du même jour
ci-dessus.

Pourquoi `standard` seul suffit ici : si aucun type listé n'est reconnu par
le client, la condition est satisfaite — donc un vieux 12.0.x charge tout
comme avant. Le piège inverse (une ligne « Forever seulement ») exigerait
`[AllowLoadGameType camelot][ExcludeLoadGameType standard, classic]` ; le pack
n'en a pas.

**Non vérifié en jeu sur la bêta Forever.** Les 17 modules restants
(Automation, Cursor, Drawer, CopyTooltip, FastLoot, CVars, CombatTimer,
AutoInvite, DeathAlert, WhisperAlert, Performance,
EnhancedObjectiveText, CleanObjectiveTrackerHeader, MicroMenuSkin, Durability,
CraftShopper, CombatCross — ces deux derniers gardés sur Forever à la
demande de Cruzz, bien que leurs tables soient Midnight : sort de portée par
spécialisation, commandes d'artisanat)
sont chargés sur Forever sans avoir été testés ; MicroMenuSkin est le plus
exposé (boutons du micro-menu différents). La valeur d'Interface de la
version de sortie du 4 novembre n'est pas publiée : revérifier `16001` ce
jour-là. Notes complètes : `tasks/wow-api-notes.md`, section TOC.

### Nouveau (Forever seulement) : skin Details! « The War Within »

Port du skin de Karl-Heinz Schneider (MIT), déposé par Cruzz dans `details_tww/`
à la racine, en module `DetailsSkin` chargé **uniquement sur Forever** :

```
Modules\DetailsSkin\DetailsSkin.lua [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic]
```

Les deux directives sont nécessaires : retail ne reconnaît pas `camelot`, et une
liste non reconnue compte comme satisfaite (voir la règle plus haut). La page
d'options porte la même condition ; catégorie Customise, bouton « Apply to all
Details windows ».

Ce qui change par rapport à l'original : textures sous `Media\DetailsSkin`
(header, bar, background, ClassIconsTWW) avec des noms LibSharedMedia préfixés
`SuspicionsPack TWW …` ; icônes de spé coupées (`use_spec_icons = false`, atlas
`specs.blp` non embarqué) ; recoloration de la barre d'Augmentation retirée (pas
d'Évocateur) ; pas d'Ace3 propre, pas de `/tww`, et **pas de profil par défaut** :
la chaîne d'export encode en dur les chemins `Details_TWW\Textures`, on ne peut
pas la re-router sans la décoder, donc elle n'est pas livrée cassée.

Details n'a pas d'« UninstallSkin » : couper le module n'enlève le skin qu'au
prochain login, une fenêtre qui l'utilise le garde jusqu'à ce qu'on en choisisse
un autre dans Details. Activé par défaut : installer un skin n'ajoute qu'une
entrée à la liste de Details, rien ne change tant qu'il n'est pas choisi.

Details n'étant pas une dépendance déclarée, le module attend son `ADDON_LOADED`
s'il n'est pas encore là, puis `Details.IsLoaded()` à la frame suivante, comme
l'original. **Non testé en jeu** (pas de client Forever ici) : à vérifier sur la
bêta, en particulier `instance:ChangeSkin()` et le rendu des textures `.blp`.

Fichiers : `SuspicionsPack/Modules/DetailsSkin/DetailsSkin.lua`,
`SuspicionsPack_Config/Pages/DetailsSkin.lua`, `SuspicionsPack/Media/DetailsSkin/`,
`SuspicionsPack/Core.lua` (defaults `detailsSkin`), les deux `.toc`.

Fichiers : `SuspicionsPack/SuspicionsPack.toc`,
`SuspicionsPack_Config/SuspicionsPack_Config.toc`,
`SuspicionsPackClassIcons/SuspicionsPackClassIcons.toc`, `tasks/wow-api-notes.md`.

---

## 2026-08-15 — v2.7.0

### Nouveau : alerte d'interruption

« Interrompu [icône] Frappe de l'ombre » à l'écran quand **tu** kickes. Le kick
de ton familier compte comme le tien. Coupé par défaut, catégorie Combat.

**Le combat log n'existe plus pour ça.** `COMBAT_LOG_EVENT_UNFILTERED` est
protégé depuis la 12.1 et **lève à l'enregistrement** — ce n'est pas un champ qui
devient secret, c'est `RegisterEvent` lui-même qui refuse. L'implémentation
évidente d'un « ai-je kické » est donc simplement indisponible.

À la place, deux événements ordinaires sont corrélés :

1. `UNIT_SPELLCAST_SUCCEEDED`, **filtré à `player`+`pet` au niveau C**, et le
   sort lancé appartient à la table des kicks de ta spé → on arme un drapeau.
2. `UNIT_SPELLCAST_INTERRUPTED` (ou `CHANNEL_STOP`) dans les 0,35 s → c'était toi.

`CHANNEL_STOP` est là parce que kicker un sort **canalisé** ne lève pas
`INTERRUPTED`. Le prix est réel et assumé : un canalisé qui se termine
normalement pendant la fenêtre peut être pris pour ton kick.

Trois détails qui font la différence entre « ça marche » et « c'est utilisable » :

- **`C_Spell.GetSpellInfo` est `AllowedWhenTainted`** : il accepte un spellID
  **secret** et répond proprement. C'est ce qui rend possible de *nommer* le sort
  kické en contenu restreint, là où tout le reste de la charge utile est
  illisible.
- **L'icône est insérée recadrée** (`5:59` sur 64), pas en `|Tid:taille|t` nu :
  une icône de sort porte sa bordure gravée dans l'art, et à la taille du texte
  cette bordure se lit comme un bloc décalé posé à côté de la ligne.
- **Le test `issecretvalue` vient en premier et seul**, avant même d'utiliser le
  spellID comme clé : indexer une table avec un secret est exactement la même
  comparaison interdite qu'un `==`.

**Ce que je n'ai pas fait : supposer la signature de l'événement.** La signature
documentée de `UNIT_SPELLCAST_INTERRUPTED` est `(unit, castGUID, spellID)` — trois
arguments, aucun auteur. Une implémentation de référence en lit pourtant un
quatrième nommé `interruptedBy`. L'une des deux se trompe, et notre règle maison
est explicite. Donc le module **ne compte pas les arguments** : il balaie la
charge utile et RECONNAÎT un GUID à son préfixe (`Player-`, `Creature-`, `Pet-`,
`Vehicle-`). Si Blizzard en fournit un, où qu'il soit, il sert à écarter le kick
d'un allié ; s'il n'y en a pas — cas normal des interruptions à projectile, et
contenu restreint où il serait secret — le drapeau seul tient. `SP.DEBUG`
imprime la charge utile réelle, qui tranchera en jeu.

Fichiers : `Modules/InterruptAlert/InterruptAlert.lua`,
`SuspicionsPack_Config/Pages/InterruptAlert.lua`.

### Trois défauts trouvés en relisant, avant publication

Aucun n'aurait fait lever une erreur, et c'est ce qui les rend intéressants.

- **Abandon silencieux sur la spé.** `Activate` tourne à `PLAYER_LOGIN`, où les
  API de spécialisation répondent `nil` — donc le cache des kicks restait vide
  pour toute la session si les deux événements de rafraîchissement rataient leur
  coup. **C'est le défaut corrigé dans SpellEffectAlpha à la 2.6.6**, réintroduit
  trois versions plus tard dans du code neuf. La reprise se fait au moment du
  lancer : si tu lances un sort, ta spé est forcément connue, donc pas besoin de
  minuteur. Sur `specKnown`, jamais sur `kickSet == nil` — « cette spé n'a pas
  d'interruption » est une réponse VALIDE, et retenter dessus relancerait la
  résolution à chaque sort lancé par un soigneur.
- **L'aperçu mourait au premier réglage.** Le GUI appelle `Refresh` → `Activate`
  à chaque valeur touchée, et `Activate` masquait le cadre — donc bouger le
  curseur de position faisait disparaître l'aperçu, c'est-à-dire pile quand on le
  regarde pour se repérer.
- **Le `castGUID` pouvait passer pour l'auteur.** `FindActorGUID` balaie la
  charge utile au lieu de compter les positions, donc il croise forcément le
  `castGUID` — une chaîne, comme un GUID d'unité. Sans le test de préfixe, il
  aurait été pris pour l'auteur, n'aurait correspondu ni au joueur ni à son
  familier, et aurait **annulé chaque annonce**. Le module était donc mort-né, et
  aucune assertion ne le voyait.

### Auto Buy : Potion de soin concentrée de Lune-d'Argent

Ajoutée aux préréglages de potions de soin, en tête de section — palier courant
d'abord, version précédente juste dessous.

**Une seule clé, l'ID Qualité 1.** Un préréglage porte deux IDs côte à côte
(`id` = Q1, `q2` = Q2) et le mauvais se lit parfaitement naturellement comme clé
de `DEFAULTS.char.autoBuy.items`. C'est exactement ce qui est arrivé à **quinze
objets** : les valeurs livrées étaient injoignables, l'UI signalait des
modifications fantômes, et AceDB avait déjà écrit les tables mortes dans les
données de chaque personnage — réécrites à chaque déconnexion, indéfiniment.
`prune_autobuy_q2_item_keys_2026_08` les nettoie ; rien n'empêchait d'en
reproduire une.

### Porte `--autobuy`

Trois règles, contre-testées chacune :

| Perturbation | Message |
|---|---|
| Défaut clé par le Q2 | « 271883 is the Q2 id of … key it by 271884 » |
| Préréglage sans défaut livré | « reports a phantom change on an untouched profile » |
| Défaut sans préréglage derrière | « a shipped default with no preset behind it » |

Ce défaut ne fait **rien** échouer : l'addon charge, la page s'affiche, la ligne
apparaît — elle ne retient simplement jamais rien. C'est précisément la classe de
bug pour laquelle une porte existe.

### Porte `--interrupt`

35 assertions. Dans une corrélation, ce qui tourne mal n'est pas « est-ce que ça
annonce » mais « est-ce que ça annonce à tort » : la moitié portent donc sur des
cas où **rien** ne doit sortir — hors fenêtre, sans avoir kické, le kick d'un
allié, le lancer d'un allié, une spé sans interruption, le module coupé.

| Perturbation | Assertions tombées |
|---|---|
| Le drapeau ne se désarme jamais | 1 |
| Pas de filtrage par GUID d'auteur | 1 |
| Un GUID absent fait renoncer (trop strict) | 11 |
| Test de secret retiré, ou placé après l'indexation | 2 / 1 |
| `CHANNEL_STOP` non enregistré | 3 |
| `SUCCEEDED` enregistré sans filtre d'unité | 2 |
| Icône sans bornes de rognage | 1 |
| Masquage automatique retiré | 1 |
| `FindActorGUID` sans test de préfixe | 1 |
| Reprise paresseuse retirée | 1 |
| `Activate` masque pendant l'aperçu | 1 |
| Reprise déclenchée sur `kickSet` au lieu de `specKnown` | 1 |

**Deux assertions décoratives démasquées, et une leçon de stub.**

`CHANNEL_STOP` passait contre un module qui ne l'enregistrait pas, parce que le
test appelait `GetScript("OnEvent")` à la main — ce qui court-circuite
l'enregistrement. `wowstub` a donc gagné `RegisterUnitEvent`, `IsEventRegistered`
et `FireEvent`, qui livre comme le client : rien pour un événement non demandé,
et filtrage par unité. C'est aussi ce qui rend testable le filtre `player`+`pet`,
via le cas qu'il existe pour bloquer — le Contresort d'un autre mage.

*(Au passage : nommer ce répartiteur `Fire` a écrasé le répartiteur de scripts
du stub et cassé les 139 assertions de l'UI en une ligne. D'où `FireEvent`.)*

Le test « un spellID secret ne fait rien lever » était invérifiable : `wowstub`
modélise un secret par une table, et `kickSet[<table>]` rend `nil` sans broncher
— l'assertion passait avec ET sans la garde. Même piège que « ATTEMPT 1 » dans
`test_secret.lua`. Comme la conséquence n'est pas observable hors du vrai client,
elle est devenue une **assertion statique sur la source** : le test de secret
doit apparaître AVANT l'indexation. C'est exactement ce que la règle demande, et
c'est vérifiable.

---

## 2026-08-15 — v2.6.7

### La taille de l'alerte de déplacement : la bonne question n'était pas « quand »

Le contournement de la 2.6.6 — un `Refresh()` différé de deux secondes — **ne
marchait pas non plus**. Cinquième échec. Et c'est précisément cet échec qui
donne la réponse : un `Refresh()` **manuel** fonctionne à n'importe quel moment
ultérieur, alors qu'un `Refresh()` **différé** à deux secondes ne fonctionne pas.
Si le moment n'explique pas la différence, c'est que le problème n'a jamais été
« à quel instant appliquer la police ». C'était **l'hypothèse qu'un instant
suffisant existe**.

Cinq versions ont cherché cet instant : course de police (2.5.1), `ApplyStyles`
qui ne tournerait pas (2.6.3), db nulle au démarrage, `SetFont` de création
échouant en silence (2.6.5), `Refresh` différé (2.6.6).

**EllesmereUI ne fait pas cette hypothèse.** Son propre module d'alerte de
déplacement applique la police depuis `StyleSlot`
(`EllesmereUIQoL_MovementAlert.lua:431`), appelé par `ShowMovementSlot` (:929) et
`ShowBuffActiveSlot` (:1110) — c'est-à-dire **à chaque affichage, à chaque tick
de sondage**, et protégé par une garde de changement pour que la répétition ne
coûte rien (voir le commentaire ligne 459 : *« change-guarded: StyleSlot runs on
every poll tick »*). Il n'y a pas de course au login à perdre parce qu'il n'y a
pas d'instant de vérité unique.

`EnsureStyled()` fait ça pour notre unique `FontString`, appelé juste avant
chacun des cinq `fsText:Show()`. Le contournement de la 2.6.6 est **supprimé** —
il ne marchait pas et ne devait servir de fondation à rien.

**Détail qui n'en est pas un : la garde relit `GetFont()` sur le `FontString`
lui-même, elle ne mémorise pas ce qu'on a demandé en dernier.** Un mémo serait
aveugle exactement là où ça compte : si quelque chose *hors de ce fichier*
réinitialise la police, le mémo répond « inchangé » et la réparation est sautée.
Après cinq diagnostics faux, cette hypothèse-là reste la principale suspecte, et
relire l'état réel la couvre sans avoir à la prouver. Ça rattrape aussi le
`-1566.51` de la trace 2.6.4 — un `FontString` sans police valide du tout.

Fichier : `Modules/MovementAlert/MovementAlert.lua`.

### Porte `--style` (remplace `--login`)

`tests/test_show_style.lua` — 11 assertions, toutes contre-testées :

| Perturbation | Assertions tombées |
|---|---|
| `EnsureStyled` retiré des affichages (état 2.6.6) | 9 |
| Garde par mémo au lieu de relire `GetFont` | 5 |
| Garde absente (SetFont à chaque affichage) | 1 |
| `SetFont` nu au lieu de `SP.SetFontSafe` | 1 |
| Garde ne comparant que la face, pas la taille | 1 |

La ligne « garde par mémo » est celle qui compte : elle ne fait tomber **que**
les assertions sur une réinitialisation venue de l'extérieur, ce qui confirme
qu'elles testent bien ça et rien d'autre.

Le harnais charge le **vrai** bloc police de `Core.lua` : `spstub` répond à
toute clé `SP` capitalisée par un stub universel muet, donc sans ça
`SP.SetFontSafe` écrivait dans le vide et les onze assertions auraient réussi ou
échoué pour des raisons sans rapport avec le module.

---

## 2026-08-14 — v2.6.6

### La taille de l'alerte de déplacement : contournement assumé

**Ceci n'est pas un diagnostic.** La 2.6.5 expliquait le défaut par un `SetFont`
de création qui échouait silencieusement ; corrigé, le symptôme persiste. C'est
la **quatrième** explication réfutée en jeu après la course de police (2.5.1),
`ApplyStyles` qui ne tournerait pas (2.6.3) et la db nulle au démarrage.

Ce que la trace de la 2.6.4 dit vraiment, en la relisant correctement : elle
imprime la taille **avant** le travail d'`ApplyStyles`. Le second passage
affichait `27.999998` — donc **la taille est déjà bonne à la fin du login**, et
pourtant l'affichage ne l'est pas. La taille n'est donc probablement pas le
sujet. `Refresh()` fait strictement plus qu'`ApplyStyles` : il repositionne
aussi le texte (`ResetTSTextPosition`) et l'icône Spirale du temps. Une de ces
deux choses est la piste, et elle n'a jamais été explorée parce que je cherchais
une police depuis le début.

Faute de cause établie, le module rejoue tout seul, **deux secondes après
l'entrée en jeu**, exactement la commande que l'utilisateur tapait à la main :

    MovementAlert:Refresh()

Bornes délibérées, parce qu'un contournement se tient plus court qu'un correctif :

- **Connexion initiale et `/reload` uniquement.** `PLAYER_ENTERING_WORLD` part à
  chaque portail, ascenseur et porte d'instance ; re-dispatcher le module à
  chacun échangerait un défaut cosmétique au login contre un à-coup toute la
  session. Le garde lit `isInitialLogin` / `isReloadingUi`.
- **Annulé par `Deactivate`.** Un minuteur armé avant que l'utilisateur ne coupe
  le module le rallumerait sinon.
- **Ne s'empile pas.** Deux connexions coup sur coup remplacent le minuteur en
  attente au lieu d'en ajouter un.

Fichier : `Modules/MovementAlert/MovementAlert.lua` (`OnEvent`, `Deactivate`).
Si le vrai défaut refait surface un jour avec un symptôme propre, ce bloc se
supprime — il ne sert de fondation à rien.

### Spell effect alpha : appliqué au login, plus seulement au curseur

Symptôme : l'opacité n'était bonne qu'après avoir ouvert les options et bougé un
curseur. Or bouger un curseur appelle **exactement le même `ApplyAlpha`** que le
login — l'écriture n'a donc jamais été cassée, seulement son **moment**. Deux
mécanismes rendent l'appel de login muet, et le symptôme ne les distingue pas :

1. **La spé n'est pas encore connue.** `Activate` tourne à `PLAYER_LOGIN`, où les
   API de spécialisation répondent `nil`. L'ancien code traduisait ça en
   `specID == 0` et **abandonnait en silence**, sans rien pour réessayer : la
   valeur restait non appliquée toute la session.
2. **Le moteur écrase.** Le client rejoue ses propres CVars pendant le login ; une
   valeur écrite juste avant est jetée sans un mot. `Core.lua` porte déjà cette
   connaissance pour `preloadWorldNonCriticalObjects` (« Re-apply CVars that WoW
   resets on every login ») — ce module n'y avait jamais eu droit.

Les deux sont traités :

- **Réessais bornés** (1 s, 2 s, 4 s, 8 s) au lieu d'un abandon muet. Bornés, et
  pas un ticker : si la spé n'est pas résolue quinze secondes après le début de
  session, elle ne le sera pas, et un sondage sans fin serait pire que le défaut
  qu'il couvre.
- **Relecture du CVar** deux secondes après l'écriture. S'il n'a pas pris, on
  réécrit **une fois** — un dernier mot, pas une boucle : un CVar que le client
  refuse obstinément ne doit pas devenir une dispute qui dure la session.
- **`PLAYER_ENTERING_WORLD`** rejoint `PLAYER_SPECIALIZATION_CHANGED`. C'est
  l'événement qui arrive **après** la restauration du moteur.
- **Résolution de spé défensive** : `C_SpecializationInfo` d'abord, les globales
  en repli — comme `FocusTargetMarker`. L'ancien code ne lisait que la globale.

Fichier : `Modules/SpellEffectAlpha/SpellEffectAlpha.lua`.

### Deux portes de plus, et une fidélité de stub rétablie

`tests/test_login_settle.lua` (`python3 tests/run.py --login`) — 7 assertions,
toutes contre-testées en réintroduisant le défaut :

| Perturbation | Assertions tombées |
|---|---|
| Bloc du minuteur retiré | 3 |
| Garde de login retiré (part à chaque zone) | 1 |
| `Deactivate` n'annule plus | 1 |
| Deux connexions s'empilent | 1 |
| `Refresh` appelé en direct au lieu d'être différé | 3 |
| `Refresh` lui-même cassé | 1 |

`wowstub.lua` : **`Timer:Cancel` était un no-op**, donc le stub était incapable
d'échouer sur tout ce qui touche à l'annulation — les deux assertions concernées
passaient contre un code qui n'annulait rien. Un minuteur annulé quitte
désormais réellement la file (vérifié : remettre le no-op fait tomber ces deux
assertions, et elles seules).

`test_login_settle.lua` charge le **vrai** `Core/Module.lua` plutôt qu'un
`ModuleMixin` de substitution : `Refresh` délègue sa dernière étape au mixin, et
la stubber laisserait l'assertion ne tester que la moitié dont personne ne
doutait.

`tests/test_cvar.lua` (`python3 tests/run.py --cvar`) — 17 assertions, mêmes
contre-tests. **Trois d'entre elles étaient décoratives au premier passage** et
ont été réécrites :

- « la relecture ne boucle pas » passait contre une version qui bouclait, parce
  qu'elle était vérifiée contre un client coopératif : la relecture sort tôt
  quand la valeur est déjà bonne, donc une boucle folle restait invisible. Il
  fallait un client qui **refuse toujours**.
- « l'index 0 n'est pas une spé » ne pouvait pas échouer : le stub rendait déjà
  `nil` pour 0. Remplacée par ce qui est réellement porteur — les globales et
  `C_SpecializationInfo` **répondent des spés différentes** dans le stub, si bien
  que le CVar écrit dit quel espace de noms a été lu.
- « les arguments d'événement n'empoisonnent pas le compteur de réessais » ne
  s'exerçait qu'avec une spé connue, c'est-à-dire jamais sur le chemin des
  réessais.

---

## 2026-08-13 — v2.6.5

### La cause, enfin, et ce n'était aucune des trois

La trace de la 2.6.4 a donné la réponse en une ligne :

    [SP trace] OnEnable loggedIn=true | db=true | fontSize=28 | applique=-1566.51 | profil=Default
    [SP trace] ApplyStyles            | db=true | fontSize=28 | applique=-1566.51 | profil=Default
    [SP trace] ApplyStyles            | db=true | fontSize=28 | applique=27.999998 | profil=Default

**`applique = -1566.51`.** Une taille de police négative à quatre chiffres n'est
pas une taille : c'est un `FontString` **sans police valide**. `ApplyStyles`
tournait bien, voyait bien `fontSize=28`, et le profil était le bon — tout ce que
j'avais supposé cassé fonctionnait.

Le coupable est la ligne qui pose la valeur de départ, à la création du
`FontString` :

    fsText:SetFont(SP_FONT, 14, "OUTLINE")

Elle échoue au chargement du fichier, ne change rien — et laisse le texte sans
police du tout, dans un état où `GetFont()` rend n'importe quoi. C'est
exactement le défaut d'API que `SP.SetFontSafe` existe pour couvrir depuis la
2.5.1.

### L'exemption qui a caché le trou pendant quatre versions

Ces deux lignes — MovementAlert et PotionAlert — étaient **explicitement
exemptées** dans la porte `--setfont`, avec ce commentaire :

    Creation-time seed values. These are the "before" state the real call
    overwrites; the module applies the user's size later through SetFontSafe.

Le raisonnement était faux : une valeur de départ qui peut échouer n'est pas une
valeur de départ, c'est un trou. La porte savait poser la bonne question et on
l'avait dispensée d'y répondre. **`ALLOWED` est maintenant vide.**

### Trois hypothèses, trois réfutations

Pour mémoire, et parce que le coût était réel : course au chargement de police
(2.5.1), `ApplyStyles` qui ne tournerait pas (2.6.3), erreur précoce sur une base
nulle. Chacune était plausible, chacune a été réfutée par une mesure, et deux ont
donné lieu à une version publiée pour rien.

La règle du projet le disait déjà : ne jamais supposer, poser un print d'abord.
Elle a été écrite pour les signatures d'événements ; elle vaut pour tout.

---

## 2026-08-13 — v2.6.4 (diagnostic)

Version d'instrumentation, sans correction. Trois explications du symptôme « la
taille vaut 14 au login » ont été proposées et **les trois ont été réfutées par
la mesure** :

- une course au chargement de police — un `Refresh` manuel corrige
  instantanément, ce qu'une police introuvable ne peut pas faire
- `ApplyStyles` qui ne tournerait pas — l'événement EST enregistré, donc
  `Activate` a tourné, donc `Refresh` est allé au bout
- une erreur précoce sur une base nulle — aucune erreur, et `Refresh` a terminé

Ce qui reste : `ApplyStyles` tourne et lit **14**, qui est exactement la valeur
par DÉFAUT de `fontSize`. La même expression renvoie 14 pendant le login et 28
une minute plus tard.

La trace imprime, aux cinq premiers passages, ce que `ApplyStyles` voit
réellement : présence de la base, valeur de `fontSize`, taille appliquée, et nom
du profil courant. Deux points d'observation supplémentaires dans le mixin,
`OnEnable` et `OnSPLogin`, situent le moment.

Deux versions ont été dépensées à corriger sur la foi d'un raisonnement. Celle-ci
ne corrige rien et se contente de regarder.

---

## 2026-08-13 — v2.6.3

### La taille de l'alerte de déplacement, pour de bon cette fois

Ce que la mesure en jeu a établi, au login et avant toute autre action :

    taille en base .... 28
    taille appliquee .. 14
    IsEnabled() ....... true
    IsOn() ............ true
    erreur Lua ........ aucune

`ApplyStyles` n'a donc pas tourné, alors que `OnEnable` a bien eu lieu et que
toutes les branches du mixin y mènent. Le maillon fautif **n'a pas pu être
isolé** : un `/reload` efface la preuve, et l'état d'après login est
indiscernable d'un démarrage propre.

Le style est réappliqué sur `PLAYER_ENTERING_WORLD`, événement que le module
écoute déjà, qui arrive après le login et à chaque zone, à un moment où tout est
prêt par définition. `ApplyStyles` est idempotente : trois `SetFont` par zone.
C'est la forme d'auto-réparation que ReapPredict utilise déjà pour son ancrage.

### Ce que la 2.5.1 avait dit, et pourquoi c'était faux

Elle attribuait ce symptôme à une course au chargement de la police et
introduisait `SP.SetFontSafe`. **`Refresh()` corrige la taille instantanément** —
ce qu'une police introuvable ne peut pas faire. Le diagnostic était donc faux, et
il a coûté une version.

`SetFontSafe` reste : il corrige un vrai défaut de l'API — un `SetFont` qui
échoue ne change rien, pas même la taille — et il ne nuit pas. Mais il ne
soignait pas ce bug-ci.

**Cette correction-ci ne prétend à aucun diagnostic.** Elle est juste quel que
soit le maillon fautif, et c'est écrit tel quel dans le code plutôt que
travesti en explication.

### Les autres modules

CombatTimer, DeathAlert et CombatCross n'écoutent pas `PLAYER_ENTERING_WORLD` et
ne peuvent donc pas recevoir le même traitement en l'état. Ils n'ont pas été
touchés : rien n'indique qu'ils souffrent du même défaut, et le supposer serait
refaire l'erreur de la 2.5.1.

---

## 2026-08-13 — v2.6.2

Aucun changement de code. La v2.6.1 avait été taguée sur le mauvais commit, puis
supprimée et republiée — et un gestionnaire d'addons qui avait déjà vu passer la
première garde son entrée en cache et ne redemande pas. Un numéro qu'il n'a
jamais vu contourne le problème sans rien manipuler côté client.

La leçon est dans la cause : ma commande n'était pas chaînée, le `git tag` s'est
exécuté malgré l'échec du `git commit` qui le précédait, et a posé la 2.6.1 sur
le commit de la 2.6.0. Supprimer une release déjà publiée coûte plus cher que de
la republier sous un nouveau numéro.

---

## 2026-08-12 — v2.6.1

### La piste n'a jamais été une pilule

Le style s'appelait `pill`, le commentaire disait « toggle tracks 16x16 », et le
fichier faisait 24x24. Mesuré : le profil alpha atteint le bord à cinq pixels du
coin, et la forme remplit **90,3 %** de son rectangle englobant là où une capsule
en remplirait **78,5 %**. C'était un rectangle arrondi.

Pire, la marge de découpe valait 8 pour un rayon réel d'environ 5 : chaque coin
prélevé contenait déjà du bord droit. Les extrémités ne pouvaient pas être
rondes.

**Une capsule ne se découpe pas en nine-slice.** Son rayon EST la moitié de sa
hauteur, donc `2 * margin` égale toujours la hauteur entière et il ne reste aucun
bandeau central à étirer. Elle est dessinée en une seule texture, et la source
est en 2:1 (64x32) comme la piste (36x18) pour que l'étirement soit uniforme —
une capsule carrée étirée sur une piste 2:1 aplatirait les extrémités en
ellipses.

Le style `pill` et ses deux textures sont supprimés : plus aucun usage.

### Une porte sur la forme, pas sur le nom

`--textures` vérifie maintenant la capsule **par son aire**. C'est décisif là où
l'oeil et le nom ne le sont pas : une capsule de w x h couvre
`(w-h)*h + pi*(h/2)^2`, un rectangle arrondi couvre mesurablement plus. Elle
contrôle aussi le rapport 2:1.

Contre-testée dans les deux directions : un rectangle arrondi est rejeté à 10,8 %
d'écart, une capsule carrée est rejetée sur son rapport.

C'est exactement le défaut qui a survécu deux ans — parce que personne n'avait
demandé à la forme ce qu'elle était réellement.

---

## 2026-08-12 — v2.6.0

### L'interrupteur passe avant son libellé

La 2.5.6 avait changé la TECHNIQUE de rendu — deux couches, dégradé — mais pas
l'APPARENCE, qui était la demande. Deux écarts restaient.

Les proportions : piste 36x18 avec un pouce de 14, au lieu de 38x16 avec 12. Le
rapport est ce qui se voit — un pouce à 78 % de la hauteur laisse une marge fine
et régulière tout autour, là où 75 % d'une piste plus basse se lit plat. Le
glissement passe à 0,15 s.

Et l'ordre. Toutes les autres lignes sont libellé-à-gauche / contrôle-ensuite, et
c'est `NewRow` qui le construit. L'interrupteur est le seul contrôle qui gagne à
être inversé : il est petit, son état EST l'information, et le mettre devant
donne une colonne d'états à parcourir au lieu d'une chasse en fin de ligne.

Ré-ancré dans le widget et non paramétré dans `NewRow` : celui-ci mesure le
libellé pour placer le contrôle, et tout ce calcul n'a plus de sens une fois
l'ordre inversé. Les curseurs et listes gardent la grille — un curseur ne peut
pas passer avant son libellé.

### Deux régressions attrapées par la suite

**Le contrôle débordait sur sa description.** Ancré par `LEFT`, son milieu
vertical se posait sur l'axe, ce qui descend son bord bas d'une demi-hauteur —
droit à travers la description. `NewRow` ancre par `TOPLEFT` pour cette raison
exacte. L'assertion « aucun contrôle ne chevauche sa description » l'a vu.

**Puis l'assertion d'alignement a échoué, et elle avait tort.** Elle suppose que
libellé et contrôle sont tous deux relatifs à la LIGNE et compare leurs
décalages. Le libellé inversé est ancré au CONTRÔLE : un décalage de 0 y signifie
« même axe », et il était comparé à un -16 exprimé dans l'autre repère — soit un
désalignement de 16 px annoncé sur une ligne parfaitement centrée.

Elle connaît maintenant les deux repères. Vérifié qu'elle n'a pas été affaiblie :
elle échoue toujours sur un libellé désaxé en disposition inversée, sur un
libellé désaxé en disposition classique, et sur le débordement de description.

---

## 2026-08-12 — v2.5.9

### Retrait du Nudge Tool

Il perturbait le mode Édition de Blizzard. Le dossier part dans `Archive/` — il
n'est pas détruit, et l'historique git le garde de toute façon.

Sept endroits tenaient une référence, dont **deux qui auraient fait échouer la
construction de la release** si on les avait oubliés : le workflow zippe les
dossiers par leur nom, et son contrôle de structure attend une liste exacte de
racines. Un `rm` seul aurait produit un tag qui ne construit pas.

Les autres : la ligne de liste blanche du `.gitignore`, la page d'options et son
entrée dans le TOC du module de configuration, et les listes d'addons des portes
`--audio` et `--tocicons`.

Le contrôle de structure du workflow a été rejoué localement avant le tag, sur
une archive construite à trois dossiers.

### Ce qu'une mise à jour ne peut pas faire

Retirer le dossier du paquet ne le supprime pas du disque : un gestionnaire
d'addons remplace ce qu'il livre, il n'efface pas ce qu'il ne livre plus. Le
dossier `SuspicionsPackNudgeTool` doit être supprimé à la main, sinon il continue
de se charger et le mode Édition reste perturbé. C'est écrit dans les notes de
version et dans la fenêtre en jeu.

---

## 2026-08-12 — v2.5.8

### « Pas d'icône » ne s'obtient pas en retirant la ligne

Les trois compagnons affichaient le point d'interrogation du client. La 2.5.3
avait retiré leur `IconTexture` en croyant bien faire — elle pointait vers
`SuspicionsPack\icon.png`, un fichier qui n'existe pas, et le résultat *avait
l'air* voulu puisque rien ne s'affichait.

Les deux états sont pourtant distincts, et c'est exactement l'inverse de
l'intuition :

**Chemin cassé** → rien ne se dessine. Muet, indiscernable d'un choix.
**Ligne absente** → le client dessine SON point d'interrogation.

La 2.5.3 est donc passée du premier au second, c'est-à-dire d'un bug invisible à
un bug visible. « Rien » se déclare : une texture valide de 16x16 dont chaque
pixel est transparent.

Huitième porte, `--tocicons`, qui refuse les deux erreurs — un chemin qui ne
résout pas, et une déclaration manquante. Contre-testée dans les deux sens.

---

## 2026-08-12 — v2.5.7

### « Ça ne marche qu'hors combat »

Signalé en jeu, et c'était exactement ça. `ReadSFStackFromCDM` passait par
`auraInstanceID` puis `GetAuraDataByAuraInstanceID`, que la 12.1 bloque tant que
les auras sont secrètes — donc pendant toute la durée d'un combat. Le compte de
fragments revenait `nil`, et avec lui la barre d'âmes, l'aperçu de MoC, la barre
de fureur des âmes et son aperçu : quatre régions mortes au pull, ressuscitées à
la fin du combat.

Deux régimes maintenant, et la distinction est le fond du correctif :

**Hors verrouillage**, lecture directe. Ne rien trouver est un **zéro véritable**.

**Sous verrouillage**, la seule source qui parle est la copie que le Cooldown
Manager garde sur son propre cadre, lue par `rawget` — un cadre restreint refuse
l'accès ordinaire à ses champs. Un échec y vaut **`nil`, c'est-à-dire « on
garde »**. Dessiner un zéro serait inventer un nombre.

Provisoire par nature : c'est la première chose qui meurt si le Cooldown Manager
est verrouillé à son tour. Rien ici ne le traite comme faisant autorité.

### Deux affichages qui mentaient

`ApplyToBar` faisait tomber un `nil` dans `or 0`. Chaque lecture refusée vidait
donc la barre — un zéro assuré, tiré de rien. `nil` **garde** désormais le
dernier remplissage : périmé, pas inventé.

`SetBarLabel` formatait une valeur secrète avec `"%d"`. Ça ne lève pas et
n'imprime pas le nombre : le formateur C++ rend un secret comme un **0
littéral**. La barre était donc correctement remplie au-delà du seuil avec un
« 0 » écrit à côté. Un secret conserve son texte : un chiffre en retard d'un
instant est un mensonge bien plus petit, et la barre reste exacte puisque
`SetValue` accepte le secret lui-même.

### `SP.AurasSecret`

Hissé dans Core et partagé. Deux modules posent la même question pour la même
raison : BloodlustAlert pour distinguer un débuff supprimé d'un débuff absent,
ReapPredict pour savoir si un compte manquant est un zéro ou un « je ne sais
pas ». Et ce n'est pas `InCombatLockdown` seul — la confidentialité survit au
combat en Mythique+.

### Couverture

Ces trois correctifs ne sont **pas couverts par une porte** : `ApplyToBar` et
`SetBarLabel` sont des locales de ReapPredict, et charger ce module dans le
harnais demanderait d'y modéliser toute sa surface. C'est écrit ici plutôt que
passé sous silence.

---

## 2026-08-12 — v2.5.6

### Le compteur de Métamorphose mentait d'un tiers

`VM_THRESHOLD` était écrit en dur à 50 et utilisé à huit endroits, dont
`growthBar:SetMinMaxValues` et `PX_PER_STACK_BUILD`. Glouton d'âmes (1247534)
retire 15 âmes : la Métamorphose se déclenche à 35. Relevé en jeu, `VM stack
apps: 26` s'affichait à **52 %** alors que la vraie progression était **74 %**,
et la Métamorphose partait aux deux tiers de la barre.

Le module ne se taisait pas, il mentait — et il avait raison sur une build sans
ce talent, d'où l'impression que l'arbre héroïque était en cause.

Le seuil devient une valeur calculée en tête de `RecomputeDerived`. Rien d'autre
n'a bougé : la chaîne `TRAIT_CONFIG_UPDATED -> Refresh -> ApplySize ->
RecomputeDerived` existait déjà, et `ApplyPhaseMode` refixe l'échelle depuis le
seuil. Les huit usages en aval suivent sans y toucher.

La réduction est dans une table plutôt qu'un `if`, parce que c'est typiquement
la valeur qu'un équilibrage déplace : un futur talent est une ligne, une valeur
changée est un chiffre à côté de l'ID qui l'identifie.

`DumpState` affiche désormais le seuil, la base et les talents détectés. L'ancien
n'imprimait que le seuil, donc un mauvais ressemblait exactement à un bon.

### Les interrupteurs

Le fond était un lerp d'UNE texture entre le fond et l'accent : à l'arrêt un
rectangle gris, et chaque image intermédiaire un mélange de deux couleurs sans
rapport. Deux couches maintenant — la piste sombre reste visible en permanence,
l'accent se fond par-dessus en dégradé horizontal.

L'alpha est **dans les couleurs du dégradé**, jamais posé avec `SetAlpha` : un
dégradé impose son propre alpha de vertex, donc fondre la texture par la méthode
évidente ne fait strictement rien.

Deux correctifs de comportement :

Le clic écrivait un état local et le croyait. Un setter qui refuse ou corrige la
valeur laissait l'interrupteur afficher une chose et le profil en contenir une
autre — et c'est l'interrupteur qu'on croit. La valeur est relue à la source
après écriture.

Et `StdSetEnabled` ne grisait que le libellé, donc un interrupteur verrouillé
gardait son accent plein et se lisait « allumé et fonctionnel ». L'accent
disparaît maintenant à la désactivation.

Plus le son de case à cocher de Blizzard au clic.

### Trois assertions décoratives, trouvées par le contre-test

Celle du setter ne cliquait jamais : le `OnClick` est sur le bouton de survol,
pas sur la ligne, donc lire le script sur la ligne ne trouvait rien et
l'assertion passait sans avoir rien basculé.

Celle de l'alpha testait à l'état allumé, où un alpha intégré et un `SetAlpha`
sont indiscernables — les deux finissent opaques. Elle teste à l'état éteint, le
seul point où ils divergent.

Et un cas du contre-test lui-même était mal écrit : il insérait un appel désactivé
sans retirer le vrai. Le stub sait maintenant enregistrer `SetGradient`, sans quoi
tout l'état allumé restait intestable.

139 assertions, cinq comportements contre-testés au rouge.

---

## 2026-08-12 — v2.5.5

### Ce que la 12.1 interdit vraiment

La 2.5.4 partait d'une lecture trop pessimiste de la restriction. Deux
corrections :

**Lire `updateInfo.isFullUpdate` est permis.** Le plantage d'origine ne venait
pas de la lecture du champ mais du `not` appliqué à la valeur secrète qu'il
renvoie. `issecretvalue` est l'inspecteur autorisé et ne lève jamais, donc une
garde avant le branchement suffit — supprimer le chemin était plus brutal que
nécessaire :

    local full = updateInfo.isFullUpdate
    if _issecretvalue(full) then return false end
    return full and true or false

**Et la détection fonctionne en combat.** Interroger un spell ID CONNU renvoie
l'aura même quand ses champs seraient secrets : ce qui est verrouillé, c'est le
contenu de l'événement, pas la question posée sur un sort qu'on nomme soi-même.
La conclusion « aveugle en raid » de la 2.5.4 généralisait à tort une remarque
qui ne valait que pour des sorts placés sur liste blanche.

### Deux fausses alertes fermées

Le champ récupéré sert précisément à cela : **un rafraîchissement complet n'est
pas un lust**. Zoner ou se connecter renvoie toutes les auras d'un coup, ce qui,
pour un détecteur de front, est indiscernable d'un débuff qui vient de tomber.

Quand le drapeau est secret, une **fenêtre de grâce de 1,5 s** après
`PLAYER_ENTERING_WORLD` prend le relais. Un épuisement déjà porté en sortant
d'un donjon ne se ré-annonce donc plus.

Dans les deux cas l'état est enregistré et seule l'annonce est supprimée :
sauter aussi l'affectation laisserait le front armé, et l'alerte partirait sur
l'événement ordinaire suivant.

### Le modèle de test, troisième version

Le stub interdisait tout accès à `updateInfo`. C'était **plus strict que le
client** et cela aurait rejeté le correctif correct — une porte qui interdit la
bonne solution n'est pas une porte, c'est un obstacle. Le champ est maintenant
lisible et renvoie un secret marqué que `issecretvalue` reconnaît.

`--secret` passe à 19 assertions. Les cinq comportements sont contre-testés :
bug d'origine, garde de rafraîchissement, fenêtre de zone, sonde `C_Secrets`,
adoption après un passage aveugle. Tous rouges quand on les retire.

---

## 2026-08-12 — v2.5.4

### L'alerte Bloodlust cassée par la 12.1

Erreur signalée en jeu, environ 1400 fois dans un seul combat :

    BloodlustAlert.lua:173: attempt to perform boolean test on field
    'isFullUpdate' (a secret boolean value, while execution tainted by
    'SuspicionsPack')

La 12.1 rend le payload de `UNIT_AURA` **entièrement secret** : `isFullUpdate`,
`addedAuras` et `removedAuraInstanceIDs` sont des valeurs secrètes, et le simple
fait de brancher dessus lève. Le chemin rapide qui les lisait n'était qu'une
optimisation ; il est supprimé, il n'y a pas moyen de le garder.

Le chemin lent n'était pas sûr non plus. Il calculait l'instant d'application à
partir de `expirationTime` et `duration`, des champs d'un `AuraData` que le
patch peut refuser de livrer. Il est remplacé par une **détection de front** :
l'épuisement était absent au dernier passage et il est présent maintenant, donc
il vient d'être appliqué. Aucune valeur de champ nécessaire, seulement la
présence.

`ExhaustionPresent()` renvoie `true`, `false` ou **`nil`**, ce dernier signifiant
« le client refuse de répondre ». Ne pas confondre `nil` et `false` est le coeur
de la correction : les fondre ferait déclencher le détecteur de front à l'instant
où le client recommence à répondre, sur un débuff présent depuis le début.

ReapPredict lisait le même payload dans son bloc de debug. Retiré : son seul but
était d'inspecter des valeurs que le client ne donne plus.

### Pourquoi la suite était verte pendant que l'addon cassait

`wowstub.lua` définissait `issecretvalue()` retournant toujours `false`, **sous**
la vraie implémentation, qu'elle écrasait donc silencieusement. Toutes les gardes
`_issecretvalue` du pack répondaient « pas secret » dans tous les tests : aucune
assertion n'a jamais exercé le chemin des valeurs secrètes. Un stub qui dit
toujours non est pire que pas de stub, parce qu'il fait passer la garde pour
testée.

Huitième porte : `tests/run.py --secret`, 11 assertions, contre-testées en
remettant le chemin rapide.

**Le premier modèle de valeur secrète était faux et le contre-test l'a prouvé.**
Une table portant des champs secrets laissait passer le bug d'origine : en Lua
`not` n'est pas surchargeable — il n'existe pas de métaméthode `__not` — donc
`not updateInfo.isFullUpdate` valait tranquillement `false` au lieu de lever. Le
modèle rend maintenant l'accès au champ lui-même impossible, ce qui est plus
strict que le client mais impose la règle qui compte : ne pas toucher à
`updateInfo`.

---

## 2026-08-11 — v2.5.3

### Patch 12.1.0

Les TOC déclaraient `120001, 120005, 120007`. La 12.1.0 est `120100`, absent de
la liste : les quatre addons seraient sortis marqués obsolètes et désactivés par
défaut. Ajouté partout.

Le TOC n'est que le portier, donc la surface a été croisée avec ce que le patch
retire. `SecureAuraHeaderTemplate`, `AddAuraFrame` et la création directe
d'`AuraButton` disparaissent de Mainline : **aucun des quatre addons ne les
utilise**. Le pack est déjà sur les APIs d'aura modernes.

Ce qui reste exposé, c'est BloodlustAlert. La 12.1 filtre les auras pour réduire
les informations de combat qui remontent aux addons, et la détection du debuff
d'épuisement repose entièrement sur `C_UnitAuras.GetPlayerAuraBySpellID`. Les
gardes `issecretvalue` protègent d'une erreur Lua, pas d'une donnée qui n'est
plus fournie. Si l'alerte ne part plus, la cause sera là et non chez nous.

### Liste des addons

Le panneau d'options s'appelait « SuspicionPack Options » quand les deux autres
plugins ont un tiret cadratin. Aligné, et sa description reprend le format des
autres.

Class Icons et Nudge Tool n'avaient pas « pas d'icône » : ils déclaraient
`Interface\AddOns\SuspicionsPack\icon.png`, un fichier qui n'existe pas — le
vrai est dans `Media\Icons\`. Les deux lignes mortes sont retirées et l'icône ne
reste que sur l'addon parent, seul endroit où le chemin est juste.

---

## 2026-08-09 — v2.5.2

### La musique du lust qui s'arrête au bout de quelques secondes

Les sept sons durent 40 s et sont tous à 192 kb/s en 44,1 kHz — sauf un.
`hotnigga.mp3`, **le son par défaut**, était le seul à 48 kHz. C'est la seule
différence mesurable entre le fichier signalé et les six autres, et rien de tout
cela n'est visible depuis le Lua : les minuteurs sont justes, `StopSound` n'est
pas appelé en avance, le fichier a la bonne longueur. Réencodé en 44,1 kHz,
l'original est conservé dans `Archive/audio-originaux/`.

Septième porte : `tests/run.py --audio` sonde chaque son livré et refuse ce qui
n'est pas en 44,1 ou 22,05 kHz. La liste de sons s'allonge régulièrement, chaque
fichier arrivant au format de sa source, et ce mode de panne est silencieux.
Contre-testée en remettant l'original 48 kHz : rouge.

**Réserve, la même que pour la police.** Le fait que ça meure pendant un lust —
le moment le plus bruyant du jeu — se lit aussi comme une éviction du son par le
moteur, quand le budget de voix simultanées est saturé. Un problème de format
échouerait à l'identique dans une fenêtre d'options silencieuse ; une éviction ne
se produit que sous charge. Le bouton d'écoute des options sépare les deux. Si le
problème persiste, le canal `Music` — déjà proposé dans la liste — est le suivant
sur la liste.

### Empaquetage

La v2.5.1 portait **deux** archives : celle du workflow, correcte, et une
seconde construite à la main qui contenait un dossier enveloppe. Extraite par
WowUp, la seconde installait un unique dossier au lieu des quatre addons, et rien
ne se chargeait. L'archive fautive est retirée.

La cause tient en une ligne du workflow : il ne posait pas les notes de version,
donc chaque publication demandait une reprise à la main — et c'est cette reprise
qui a déposé le mauvais zip. Les notes viennent maintenant de
`.github/RELEASE_NOTES.md`, il n'y a plus rien à faire à la main.

Et la construction vérifie désormais la structure de l'archive : quatre dossiers
à la racine, chacun avec son `.toc`. Sans quoi elle échoue au lieu de publier.

---

## 2026-08-09 — v2.5.1

### La taille de police qui « saute » au login

Signalé sur MovementAlert : le texte sort minuscule à la connexion et reprend sa
taille à la seconde où la fenêtre d'options est ouverte. Intermittent — un login
à chaud passe, un démarrage à froid échoue.

Le réglage n'est jamais perdu : mesuré en jeu, il vaut 28 avant comme après.
C'est l'application qui rate. `SetFont` est tout ou rien — quand l'asset n'est
pas chargeable il renvoie `false` et **ne change rien du tout**, pas même la
taille. Le FontString reste donc sur le `SetFont(SP_FONT, 14, "OUTLINE")` posé à
sa création. Ouvrir les options ne « répare » rien : ça rejoue simplement le même
appel plus tard, quand le fichier se charge.

Deux correctifs, dans `Core.lua` :

- **`SP.SetFontSafe`** vérifie ce que `SetFont` renvoie au lieu de le supposer.
  En cas d'échec il applique une police que le client fournit toujours **à la
  bonne taille**, puis remet la police voulue dès qu'elle se charge. Une taille
  juste dans la mauvaise police est un problème bien plus petit qu'un texte à
  moitié taille. Le réessai est gardé : il ne s'applique que si rien n'a changé
  entre-temps, sinon un réglage modifié pendant le délai serait écrasé.
- **`IsFontPathValid` ne mémorise plus que les succès.** Un échec tôt au login
  n'est pas la preuve d'un fichier manquant, et mettre ce `false` en cache
  transformait un raté passager en panne définitive pour toute la session.

Cinquième porte : `tests/run.py --fonts`, 14 assertions. Le stub sait maintenant
faire échouer `SetFont` — sans quoi le bug n'était pas modélisable. Toutes
contre-testées ; le contre-test a d'ailleurs montré que chacune des deux moitiés
du correctif de cache suffit seule à empêcher le bug.

Propagé à tous les appels qui posent une taille réglée par l'utilisateur. Le
plus utile tient en une ligne : `SP.CreateAlertFrame`, la fabrique partagée par
huit modules. Puis CombatTimer, DeathAlert, Durability, GatewayAlert,
PotionAlert, BloodlustAlert, et CombatCross — dont l'épaisseur EST la taille de
police, donc la croix sortait à la mauvaise taille pour la même raison.

Les onze libellés de CraftShopper gardent un `SetFont` direct : leurs tailles
sont fixes et décoratives, un raté ne se voit pas. Ils sont exclus par fichier
dans la porte, pas oubliés.

Sixième porte : `tests/run.py --setfont` échoue si un `SetFont` direct
réapparaît sur une police d'addon. C'est exactement le correctif qu'on défait
sans y penser, parce que `fs:SetFont(path, size, flags)` a l'air juste.
Contre-testée dans les deux sens : rouge sur une vraie régression, et
insensible à une mention en commentaire — le piège qui avait rendu la porte
« orphelins » fausse au premier essai.

---

## 2026-08-07 — v2.5.0

### Des réglages qui existaient sans être atteignables

Quatre fonctionnalités écrites, fonctionnelles et impossibles à configurer.

`MovementAlert` lisait **`spellOverrides`** depuis toujours — un texte
personnalisé par sort, avec son repli complet sur le nom du sort — et aucune page
ne l'écrivait jamais. Il y a maintenant un champ « Shown as » sous chaque sort
suivi. Vider le champ retire l'enregistrement au lieu d'y stocker une chaîne
vide, sans quoi le compte à rebours s'afficherait sans nom. Ses trois clés de
mise en forme — alignement, force de l'ombre, niveau de cadre — sont exposées
aussi.

`CopyTooltip` gérait cinq combinaisons de modificateurs et n'importe quelle
lettre. La page n'exposait rien : le raccourci était Ctrl+C pour tout le monde,
quoi que le module sache faire. La lettre est nettoyée à l'écriture — une seule,
en majuscule — parce que le module compare aux noms de touches de WoW et qu'un
chiffre ou deux caractères ne correspondraient jamais.

### Quatrième porte : les réglages orphelins

`tests/run.py --orphans` extrait toutes les clés lues sous la forme `db.xxx` dans
les 30 modules, toutes celles exposées par les 33 pages, et signale la
différence. Le module est correct, la page est correcte, et le défaut est *entre
les deux* — aucune assertion portant sur l'un ou sur l'autre ne pouvait le voir.

La porte était fausse au premier essai : elle dépouille maintenant les
commentaires avant d'analyser, parce qu'un commentaire mentionnant `db.modifier`
suffisait à faire passer le réglage pour exposé. Trouvé en contre-testant la
porte, qui restait verte quand on cassait la vraie ligne.

---

## 2026-08-07 — v2.4.0

### Traînée indépendante de la fréquence d'images

Le fondu était sur l'horloge mais **l'échantillonnage était par image** : un
point maximum par tick, quel que soit le chemin parcouru. À 144 fps le curseur
avance de 2 px entre deux ticks et on pose un point tous les 2,4 px ; à 30 fps il
avance de 10 px et on pose toujours un seul point. La traînée perdait quatre
cinquièmes de ses points exactement quand le jeu ramait déjà.

Les points sont maintenant posés **le long du segment**, un par espacement, avec
des horodatages étalés pour qu'ils expirent dans l'ordre ; le reste est reporté
au tick suivant, ce qui garde l'espacement régulier. Au-delà d'une longueur de
traînée complète, le curseur est considéré comme téléporté et l'interpolation est
sautée — sans quoi un retour d'alt-tab peindrait une traînée en travers de
l'écran.

Une implémentation de référence a le même défaut d'échantillonnage. Elle le masque en plafonnant sa propre
cadence à 40 Hz : la traînée est déjà maigre à 144 fps, donc elle maigrit moins
en tombant à 30. Le plafond est repris ici, mais il n'est sans danger **que**
parce que l'échantillonnage suit le chemin : un tick plus lent devient un segment
plus long à parcourir, pas un point de moins. Les positions sont aussi arrondies
au pixel entier — arrondies à l'écriture et non sur la source, pour que la
quantification ne se propage pas à l'espacement.

### Libellés et contrôles sur la même ligne

Le libellé pendait du haut de la ligne à un décalage fixe pendant que le contrôle
était centré dans la bande de 32 px. La hauteur d'une `FontString` dépend de sa
police, donc les deux centres tombaient à quelques pixels d'écart et chaque
interrupteur était visiblement bas par rapport à son propre texte. Un seul nombre
est calculé et les deux s'y ancrent — le libellé par son point `LEFT`, qui est son
milieu vertical — ce qui rend le décalage impossible à représenter plutôt que
simplement corrigé. Même correction sur les deux libellés des lignes de couleur.

---

## 2026-08-07 — v2.3.0

### Cursor circle — traînée

Des copies de l'anneau laissées derrière le curseur, qui s'effacent.

Trois points ne sont pas devinables et viennent tous de la lecture d'une
implémentation qui tourne, après une première
version qui les avait ratés :

- **Le fondu est sur une horloge, pas sur la position dans l'anneau.** Un fondu
  indexé n'avance que quand le curseur bouge : s'arrêter laisse toute la traînée
  peinte à l'écran jusqu'au mouvement suivant. Chaque échantillon porte l'heure
  à laquelle il a été pris et expire tout seul.
- **Les échantillons sont espacés par la distance.** Enregistrer à chaque pixel
  tasse l'anneau entier sur quelques pixels pendant un déplacement lent, et la
  traînée devient une tache. Un nouvel échantillon n'est pris qu'une fois le
  curseur déplacé d'une fraction de la taille du segment.
- **Fusion additive.** Des cercles plats empilés ressemblent à des cercles
  empilés ; en additif ils font une lueur, ce qui est tout l'intérêt.

Le pool est alloué une fois à 60 textures et le curseur de longueur décide
seulement combien sont en jeu — une texture n'est pas plus récupérable qu'un
cadre, donc l'agrandir depuis un réglage fuirait à chaque glissement.

---

## 2026-08-07 — v2.2.0

### Release and rez — nouveau module

Une seule page pour la question « qu'est-ce qui se passe quand je meurs ».

**Auto accept resurrection — jamais un battle rez**, et le test tient en une
ligne parce que le jeu encode déjà la réponse : une résurrection utilisable hors
combat est **incastable en combat**. Donc un lanceur qui est en combat lance un
battle rez, et un lanceur qui ne l'est pas, non. `RESURRECT_REQUEST` passe le nom
du lanceur, et un nom de joueur est un token d'unité valide — `UnitAffectingCombat`
répond directement.

Deux détails relevés sur une implémentation éprouvée, qu'il
aurait fallu lire avant d'inventer : `AcceptResurrect()` ne ferme pas la boîte de
dialogue, il faut `StaticPopup_Hide("RESURRECT_NO_TIMER")` derrière ; et les rez
d'objets (Pylône de détection des échecs, Brasero de l'Éveil) sont des battle rez
qu'il faut exclure. L'approche connue les liste par nom dans dix langues ; `UnitExists` sur
le lanceur donne la même réponse dans toutes, parce qu'un objet n'est pas une
unité.

Une première version lisait le journal de combat et comparait des IDs de sorts.
Plus de code, plus de façons d'être fausse, et elle ne marchait pas.

**Auto release, boss par boss.** Pas un interrupteur global : la plupart des
rencontres attendent un brez, quelques-unes se courent. La liste est composée de
paires zone/sous-zone que l'utilisateur remplit lui-même. Elle est livrée
**vide** volontairement — un ID subtilement faux ne lève aucune erreur, il ne
correspond simplement jamais, et la fonctionnalité paraît cassée sans moyen de le
voir. Une liste vide avec un bouton qui marche est honnête ; un ID deviné ne
l'est pas.

**Le lecteur de zone.** C'est ce qui rend la liste maintenable : une carte qui
affiche l'endroit exact où on se tient avec ses deux IDs, et un bouton qui
l'ajoute. Sans ça, remplir la liste veut dire chercher sur un site externe, et
une liste comme ça ne se remplit jamais. Doublé de `/spack debug zoneid` pour le
cas que la carte ne peut pas couvrir : être devant le boss sans ouvrir une
fenêtre d'options par-dessus la rencontre.

**Le délai n'est pas cosmétique.** Un battle rez qui arrive pendant qu'on est au
sol est précisément ce qu'on veut garder, donc le release est différé puis
re-vérifié : si une résurrection est en attente à l'échéance, il est annulé.

### Barre latérale triée

Les pages étaient listées dans l'ordre du TOC, c'est-à-dire dans l'ordre de
chargement — un détail de build, pas un menu. Elles sont maintenant insérées par
ordre alphabétique dans leur catégorie, en minuscules pour la comparaison :
l'ordre des octets place toutes les majuscules avant toutes les minuscules, ce
qui éparpillerait la liste au premier nom capitalisé différemment.

### Micro menu — opacité

Un curseur d'opacité pour la barre, et une option qui la ramène à 100 % au
survol. L'alpha est posé sur `MicroMenu` plutôt que sur chaque bouton, donc il
couvre aussi les fonds et les bordures et reste correct quand Blizzard ajoute un
bouton. Le survol est ré-évalué avec une frame de décalage : passer d'un bouton
au suivant déclenche le `OnLeave` **avant** le `OnEnter` du suivant, et agir sur
le seul `OnLeave` fait clignoter la barre à chaque intervalle.

### Micro menu — icônes par ligne

`MicroMenu` est une `GridLayoutFrame`, et le `stride` d'une grille **est** son
nombre d'enfants par ligne : envelopper la barre sur deux ou trois lignes tient
en une affectation plus le même relayout que l'espacement déclenche déjà. Aucun
ré-ancrage, ce qui garde la boîte de sélection d'Edit Mode, le QueueStatusButton
et le bouton de ticket MJ attachés. 0 rend la main à Blizzard, ce qui compte :
les barres de véhicule, de contrôle et de combat de mascottes posent leur propre
stride quand elles prennent le relais.

### Tests

116 assertions. `SuspicionsPack/Modules/AutoRelease/AutoRelease.lua` est chargé
pour de vrai par la suite — le stub d'API gagne un état de monde réglable
(instance, zone, sous-zone, rencontre en cours, combat du groupe) et
`NewSPModule` devient un vrai constructeur, donc la logique d'un module peut
enfin être testée au lieu d'être seulement analysée syntaxiquement. Les cinq
nouveaux cas de `tests/counter.py` remettent chacun leur bug en place pour
prouver que l'assertion le rattrape, dont celle qui compte le plus : une entrée
de release qui ne déclare rien ne doit correspondre **nulle part**.

---

## 2026-08-07 — v2.1.1

### Options UI rebuilt

The options window was one 9286-line file, 43% of the addon's source. It is now a
widget layer, a layout engine, a window shell and 33 one-page files — 7845 lines
across 39 files, with four structural faults fixed along the way.

#### Switching theme no longer leaks the window
`SP.RefreshTheme` used to call `GUI:Rebuild()`, which detached the whole window
and dropped the page cache. WoW cannot free a frame, so every preset click
abandoned between 120 and 1800 frames depending on how many pages had been
opened, grew a duplicate `SP_GUIMainFrame` entry in `UISpecialFrames`, and left
the anchor picker and the profile dialog painted in the old colours forever.
Every frame now registers a painter (`Core/Theme.lua`) and a preset change walks
that registry: **verified at zero frames created across fifteen consecutive
switches with all 33 pages built.** The window also stops blinking shut and
reopening.

#### Controls re-read their settings
No widget used to re-read the database. After a profile import or a colour reset
the window kept showing the old values until it was closed and reopened. Every
widget now binds to `db` + `key` and re-reads on demand, so a page is current
whenever it is shown.

#### Disabled now means disabled
The old cascade fell back to a 40% fade for any row that did not implement its
own disable, and `EnableMouse` does not cascade to child buttons in WoW. Greyed
buttons, anchor grids and item rows all still fired. Every widget now blocks
input, and a card whose settings are all off gets a mouse blocker over it.

#### New in the window
- **Search** across every setting on every page, not just page names — typing
  "threshold" finds Repair warning.
- **Change tracking**: "N settings changed" and "Reset page" in the footer,
  updated live as you edit.
- **State dots** in the sidebar showing which modules are on.
- **Descriptions** under the labels instead of hover-only tooltips.
- Breadcrumb in the header, profile name in the footer, window position and size
  now persist across reloads.

#### Module bugs fixed along the way
- **Micro menu skin** had a master switch and 13 sub-settings with no cascade at
  all — nothing greyed, nothing disabled.
- **Death alert**'s master switch re-enabled the text-to-speech rows its own
  sub-switch had just disabled.
- **Potion alert** leaked a permanently registered voice-list listener on every
  theme change, and applied its sub-state before its master state.
- **Auto buy**: 15 of the 25 shipped item defaults were stored under the wrong
  item ID and could never be read. Rekeyed.
- **ReapPredict** settings were silently discarded by profile import, because
  `SP.DEFAULTS` — which import filters against — held only `enabled` for it. All
  50 layout and colour keys added.
- **Copy anything** and **Auto buy** wrote to your saved settings merely by
  having their page opened.
- **Enhanced objective text**'s Preview fired while the module was off, leaving
  Blizzard's error frame permanently resized.
- **Repair warning**, **Combat timer**, **Gateway alert**, **Bloodlust alert**,
  **Movement alert**, **Combat cross** and **Cursor** were missing defaults for
  settings their modules read, so those settings could not be reset and were
  dropped on profile import.

#### Visual pass

Reworked against the approved design after three rounds of side-by-side review:

- **Rows are one line** — label and description on the left, control on the
  right. They were stacked full-width, which doubled the height of every card
  and made the rest of the spacing meaningless.
- **Page header** — each module page opens with its name, a one-line
  explanation, and its master switch on the right, outside the cards. Card
  titles are quiet uppercase group labels rather than accent headings.
- **Rounded corners** — `SetBackdrop` cannot draw a radius, so the window and
  the cards use nine-sliced textures. Buttons, fields and dropdowns are square
  with a visible frame.
- **Palette** — `border` was pure black against a near-black background, so no
  card edge or hairline was ever visible. The whole Suspicion palette is
  realigned; it is now the only theme, and the theme picker is gone.
- **Disabled means recoloured, not faded.** A 40% alpha let the card show
  through a disabled slider and read as a rendering fault.
- Dropdowns regained their chevron and its open/close animation; the close
  button is a drawn X; the accent bar across the top of the window is gone;
  per-row modified pips and revert arrows are gone (the footer counts changes
  and offers "Reset page").
- **Spell effect alpha** packed four sliders onto one line, which left ~150px
  each once rows became label-left/control-right — the labels vanished
  entirely. It is one card per class now.

#### Changelog popup

Rebuilt. It looked up `SP.Changelog[SP.VERSION]` and rendered an empty box when
the running version had no entry — which is what every fresh release looks like
— and it only ever showed one version, leaving the other 34 unread in the table.
It now lists every release newest-first in a scrollable panel, with the `NEW` /
`FIX` badge each entry already carried but never displayed.

The rounded-surface primitives moved to `SuspicionsPack/Core/Skin.lua` so the
popup and the options window share one implementation: the popup is shown at
login, when the load-on-demand options addon is not loaded.

#### Parent addon (`SuspicionsPack/`)

- **The popup above could never appear.** Only its BODY was rewritten;
  `SP.CheckChangelog` still returned early unless `SP.Changelog[SP.VERSION]`
  existed, and 2.1.1 had no entry. The guard is gone — `lastSeenVersion` is the
  correct gate, and gating on "does this exact version have notes" reintroduces
  the bug on every release whose notes lag the toc bump. `SP.Changelog["2.1.1"]`
  written.
- **`change` and `remove` entries wore a FIX badge.** The popup tested
  `e.type == "new"` and fell through to `"FIX"`, so "Removed AutoPI and
  AutoInnervate modules" read as a fix. `TAG_LABEL` / `TAG_COLOR` — already in
  the file, orphaned — now drive all four types.
- **15 dead AutoBuy tables per character.** `DEFAULTS.char.autoBuy.items` was
  rekeyed from Quality-2 to Quality-1 item IDs, but AceDB had already rawset the
  Q2 tables into every character's saved data and `SP.RunMigrations` had no
  `char` scope at all. Scope added; migration registered. No user data is
  affected — every write has always landed on the Q1 key.
- **A profile naming a removed theme preset** ("Dracula") kept that string
  forever with no UI left to clear it. Normalised by migration.
- **Minimap button border** is hardcoded black again. It is the one element in
  the pack drawn against the game world rather than a dark panel, so the theme's
  `#25252C` hairline — right everywhere else — is wrong here.
- **The slice audit** retained a table per skinned surface for the session
  (1415 after building every page) to serve one debug helper, in the file
  deliberately on the login path. Now behind `Skin.audit`, off by default, on in
  the tests.
- Dead code removed from the login path (`SP_CL_*`, `CL_AnimateBorderFocus`,
  `SP.ThemePresetOrder`); `%\d` → `%d` in the version sort; `SP.ShowChangelogPopup`
  guards `SP.Skin`; the `Cursor` and `Drawer` fallbacks that disagreed with
  `SP.DEFAULTS` aligned to it, now that the options UI resets against `DEFAULTS`.

#### Found by independent review, after the suite was already green

Three reviewers went over the core layer, all 32 pages against the old builders,
and the parent addon. **No DB key was renamed anywhere** and the 76 added
defaults all match the fallback their module actually uses — but the suite's 47
assertions had missed four things that stop the window doing its job. Each of the
fixes below now carries an assertion, and each assertion was counter-tested by
putting the bug back once.

- **Lists longer than ten entries could not be scrolled.** The popup clips to ten
  rows and had no wheel handler, so a font list — 20 to 100 entries with ElvUI or
  WeakAuras installed — simply had no eleventh entry. It is a real `ScrollFrame`
  now, the same primitive the sidebar and the page canvas use, with a scrollbar
  on the right so it is visible that the list continues, and it opens on the
  current value rather than at the top.
- **The on/off toast is back.** 32 module switches announced themselves in the
  middle of the screen before the rebuild; the migration dropped it in favour of
  the sidebar dot, which only helps if you are looking at the sidebar — and you
  are looking at the switch you just clicked. It reads the accent live, so it
  follows the theme.
- **The bottom of a page could not be reached** whenever a description wrapped to
  two lines. `Page:Restack` resizes the container; the scroll range comes from the
  scroll child, which was only ever set at build time. It corrected itself if you
  left the page and came back, which is why it survived testing.
- **A repaint un-greyed the whole window.** Painters write the enabled colour
  unconditionally, so after a profile import every disabled control read as
  enabled while still refusing clicks. A profile change also never re-evaluated
  the master switches. Both paths re-apply the gates now.
- **Combat timer's Format list stored values the module does not understand**, so
  the milliseconds format was unreachable and two of three options did nothing.
- Custom rows (the Auto buy grid, the cursor texture pickers, the macro rows)
  left their child buttons clickable while greyed — `EnableMouse` does not
  cascade, and the card's blocker only appears once every row in the card is off.
- Gates were resolved in one pass over registration order, so a nested gate's
  outcome depended on which toggle the page happened to declare first.
- Auto buy reported all 25 rows as modified on an untouched profile, and "Reset
  page" then wrote 25 records that were not the defaults.
- The colour picker dropped the stored opacity on any swatch without an opacity
  slider, so that row counted as changed for ever after.
- Two rows on Group invitations were invisible to both the change count and
  "Reset page"; the Random-sound lock on Bloodlust alert came undone on every
  return to the page; "Test voice" spoke the previous text; Combat timer left a
  stale time on screen; the Getting-started text pointed at the deleted Themes
  page. TankMD's copy-a-macro rows and Performance's two cleanup buttons, both
  usable with the module off before, are usable again.
- Typing a value into a slider suffixed `s` silently reverted, because the suffix
  was interpolated into a Lua pattern and `%s` is the whitespace class.
- The slice audit was skipping 632 of 1409 surfaces in silence and measuring
  textures against their parent frame. It now reports what it could not judge,
  and the suite holds a ceiling on that number.

#### Tests

`tests/` runs the whole options UI against a stubbed WoW API in real Lua 5.1:
89 assertions, a Lua 5.1 parse gate over all 75 files, and a texture gate that
checks the nine-slice margins against the shipped PNGs. The changelog popup, its
caller and the migration runner are sliced out of the parent addon and run for
real rather than stubbed. The stub now models `SetAllPoints` and fires
`OnSizeChanged`, without which a third of the surfaces the audit checks were
unmeasurable and the scroll-range bug above was invisible.

#### Files
- Added `SuspicionsPack_Config/Core/{Theme,Widgets,ColorWidgets,AnchorWidgets,Layout,Shell}.lua`
- Added `SuspicionsPack_Config/Pages/` — 33 pages plus `Categories.lua`
- Added `SuspicionsPack_Config/README.md` — the page-authoring contract
- Removed `SuspicionsPack_Config/GUI.lua`
- `SuspicionsPack/Core.lua` — `SP.RefreshTheme` repaints instead of rebuilding;
  `DEFAULTS` completed for eight modules

---

## 2026-05-27 — v1.8.4

### Nettoyage global — suppression des attributions et corrections de style

#### Tous les modules (.lua)
- Suppression de toutes les mentions d'attribution externe dans les headers et commentaires.
- Correction du pattern dot notation → colon notation sur toutes les fonctions `Module.Refresh()` qui utilisaient `mod = SP.ModuleName` en dur. Modules corrigés : WhisperAlert, Durability, AutoInvite, GroupJoinedReminder, AutoPlaystyle, FilterExpansionOnly, AutoBuy, CraftShopper, SpellEffectAlpha, CleanObjectiveTrackerHeader, EnhancedObjectiveText, Performance, SilvermoonMapIcon, CopyTooltip.
- Suppression des commentaires `-- Called by GUI toggle` et variantes.

#### Core.lua / GUI/GUI.lua
- Suppression des mentions externes dans les commentaires (theme presets, CreateMessagePopup, CreateReloadPrompt, PreviewManager, widget styles, etc.).
- Suppression du header d'attribution dans GUI.lua.
- Suppression des mentions externes (raid marker coords, CVar apply).

#### Modules supprimés
- **CombatLog** : retiré du .toc, Core.lua (DB defaults), GUI.lua (sidebar, IsModuleEnabled, page). Fichier physique à supprimer manuellement.
- **MeterReset** : idem — .toc, Core.lua, GUI.lua nettoyés.
- **PetStatus** : entrée sidebar retirée de GUI.lua.

#### TankMD/TankMD.lua
- Suppression de la ligne 281 corrompue (2562 null bytes `0x00`) qui causait un `LUA_WARNING: unexpected symbol`.

#### SuspicionsPackNudgeTool/NudgeTool.lua
- Suppression du header d'attribution en tête du fichier.

#### Automation/Automation.lua
- Suppression de `local ADDON_NAME, NS = ...` (inutilisé).
- Nettoyage des mentions externes dans les commentaires.

---

## 2026-05-10 — v1.8.0

### New modules
- **PotionAlert**: text alert when combat potion comes off cooldown. Supports Tempered Potion, Draught of Rampant Abandon, Light's Potential, Potion of Recklessness, Fleeting Potion of Recklessness. Active in M+ and raids only.
- **PetStatus**: text alert for PET MISSING / PET DEAD / PET PASSIVE. Supports Hunter, Warlock, Unholy DK.

### Fixes
- `BloodlustAlert/BloodlustAlert.lua`: `HideTimerPreview` — added `isTimerPreview` flag; tightened restore condition to `active and blStartTime` (prevents lingering timer when timer display is disabled but module is enabled and BL was recently active).
- `Core.lua` PreviewManager: fixed `dbSubKey` logic — `timerEnabled = false` now correctly suppresses the BL timer preview instead of falling back to `mdb.enabled`.
- `PotionAlert/PotionAlert.lua`: added Potion of Recklessness (241288) and Fleeting Potion of Recklessness (245902) to tracked IDs.
- `PetStatus/PetStatus.lua`: removed Arcane Mage from `PET_CLASSES`.

### Removals
- `GUI/GUI.lua`: removed Drag to Move buttons and position sliders from all 9 positioned-module pages — position is set via anchor grid only.

---

## 2026-05-10 (session 2)

### Drag-to-Move refactor — all movable modules
**Problem**: `ShowPreview()` was incorrectly enabling mouse drag and showing the MOVABLE label. The MOVABLE label was appearing during the auto-preview when the GUI opens (via PreviewManager), not just when the user explicitly clicks "Drag to Move".

**Fix applied across all modules**: Separated preview from drag. `ShowPreview()` now only shows the frame/text for position reference (no mouse, no MOVABLE). `StartDragMode()` / `EndDragMode()` exclusively manage mouse + MOVABLE label. GUI pages each have a "Drag to Move" toggle button that calls Start/EndDragMode, with `parent:HookScript("OnHide", ...)` to auto-stop drag when navigating away.

#### Modules/PetStatus/PetStatus.lua
- `ShowPreview()`: removed `frame:EnableMouse(true)` and `frame:RegisterForDrag("LeftButton")` (were incorrectly there from initial implementation).

#### Modules/CombatTimer/CombatTimer.lua
- `ShowPreview()`: removed drag enabling and `movableLbl:Show()`.
- `HidePreview()`: removed `EnableMouse(false)` / `SetMouseClickEnabled(false)`.
- Added `StartDragMode()` / `EndDragMode()` methods.
- `CreateTimerFrame` OnDragStop: added `CT._syncSliders` callback call.

#### Modules/MovementAlert/MovementAlert.lua
- `ShowPreview()`: removed drag enabling, `movableLbl:Show()`, and 5s auto-cancel timer entirely.
- `HidePreview()`: removed mouse disable; simplified.
- Added `StartDragMode()` / `EndDragMode()` methods.

#### Modules/BloodlustAlert/BloodlustAlert.lua
- `ShowTimerPreview()`: removed `timerFrame.movableLbl:Show()`.
- `BuildTimerFrame` OnDragStop: added `BLAlert._syncTimerSliders` callback call.
- Added `StartTimerDragMode()` / `EndTimerDragMode()` methods.

#### Modules/CombatCross/CombatCross.lua
- `CreateCrossFrame()`: added movableLbl FontString, `f:SetMovable(true)`, OnDragStart/OnDragStop scripts with db.x/db.y save and `CC._syncSliders` call.
- Added `StartDragMode()` / `EndDragMode()` methods (reuse previewActive flag for frame visibility).

#### GUI/GUI.lua — Drag buttons added to 4 pages
- **CombatTimer** Position card: added `_syncSliders` wiring, separator, "Drag to Move" toggle button, `parent:HookScript("OnHide")` cleanup.
- **MovementAlert** Position card: corrected `_syncSliders` colon-call syntax, added "Drag to Move" toggle button + cleanup hook.
- **BloodlustAlert** Timer Display card: added `_syncTimerSliders` wiring, separator, "Drag to Move" toggle button + cleanup hook.
- **CombatCross** Position card: added `_syncSliders` wiring, "Drag to Move" toggle button + cleanup hook.

---

## 2026-05-10

### Modules/PetStatus/PetStatus.lua — New module
- Nouveau module de textes d'état du familier, écrit aux conventions du pack.
- Detects pet state: **Missing** (no pet unit exists), **Dead** (pet HP = 0 or death-tracked), **Passive** (PET_MODE_PASSIVE stance active).
- Supports Hunter, Warlock, Unholy DK, and Arcane Mage. Suppresses for MM Hunter with Unbreakable Bond talent.
- Positioned FontString with configurable text + color per state, font/size/outline, and drag-to-move.
- `ShowPreview()` / `HidePreview()`: auto-previews when GUI opens via PreviewManager.
- `StartDragMode()` / `EndDragMode()`: drag-to-move support wired from the GUI panel.

### SuspicionsPack.toc — PetStatus registration
- Added `Modules\PetStatus\PetStatus.lua` after PotionAlert.

### Core.lua — PetStatus defaults + PreviewManager
- Added `petStatus` defaults block: enabled, text/color per state (missing #FFD100, dead #FF3333, passive #4DB3FF), font, fontSize 25, fontOutline SOFTOUTLINE, position.
- Added `PetStatus` entry to `PREVIEW_MODULES` in `SP.PreviewManager`.

### GUI/GUI.lua — PetStatus panel
- Added `{ id = "petstatus", text = "Pet Status" }` NAV_ITEM in COMBAT section.
- Added `petStatus.enabled` branch in `ItemEnabledState()`.
- Added `RegisterContent("petstatus", ...)`: Enable card, State Settings card (text editbox + color swatch for Missing/Dead/Passive), Font Settings card (font/size/outline), Position Settings card (anchor grid, XY sliders, Drag to Move).

### Modules/PotionAlert/PotionAlert.lua — New module
- Created new module: monitors combat potion cooldown and displays a positioned text alert when the potion becomes ready.
- Tracks SPELL_UPDATE_COOLDOWN + COMBAT_LOG_EVENT_UNFILTERED to detect when the potion (ID 300714) comes off cooldown during an encounter.
- `ShowPreview()` / `HidePreview()`: preview support for auto-preview system.
- **TTS**: `C_VoiceChat.SpeakText()` fires when `db.playTTS` is enabled, with configurable text and volume.
- **Auto-hide timer**: `db.displayDuration` (seconds; 0 = stay forever). Uses `C_Timer.NewTimer()` with a cancellable handle (`displayTimer`). Timer is cancelled on cooldown start, encounter start, and `OnDisable`.

### SuspicionsPack.toc — PotionAlert registration
- Added `Modules\PotionAlert\PotionAlert.lua` after BloodlustAlert.

### Core.lua — PotionAlert defaults + PreviewManager
- Added `potionAlert` defaults: enabled, dungeon/raid flags, display text, color, font, position, sound, `displayDuration`, TTS fields.
- Added `SP.PreviewManager` with `Start()` / `Stop()` methods and a `PREVIEW_MODULES` table covering 7 modules (Durability, CombatTimer, MovementAlert, GatewayAlert, CombatCross, PotionAlert, BloodlustAlert). Uses optional `dbSubKey` to handle BloodlustAlert's `timerEnabled` flag.

### GUI/GUI.lua — PotionAlert panel + PreviewManager wiring + preview button removal
- Added `potionalert` NAV_ITEM to COMBAT section (between movementalert and reapmeter).
- Added `potionAlert.enabled` branch in `ItemEnabledState()`.
- Added full `RegisterContent("potionalert", ...)`: Enable card (toggle + M+/Raid ctx), Display card (text, font, size, outline, color-with-source, duration slider), Position card (anchor, XY, drag), TTS card (toggle, text, volume).
- `GUI.Show()`: calls `SP.PreviewManager:Start()` so all enabled positioned-frame modules auto-preview when the GUI opens.
- `mainFrame:OnHide`: calls `SP.PreviewManager:Stop()` to clean up all previews on GUI close.
- **Removed all 9 per-module preview buttons**: footer "Preview All" (+ timer), Durability, CombatTimer, MovementAlert, BloodlustAlert timer preview, DeathAlert one-shot preview, GatewayAlert, CombatCross, PotionAlert. Drag-to-move buttons preserved.

### Modules/ReapPredict/ReapPredict.lua — Texture picker + Consume color opacity
- Added `GetBarTexturePath()` + `ApplyBarTexture()`: applies a saved LSM statusbar texture to all status bars (soul bar + fury bar). Defaults to `BAR_TEXTURE` (solid white) when `L.barTexture` is nil.
- `Enable()`: calls `ApplyBarTexture()` after frame creation so a saved texture is restored on load.
- Exposed `ReapPredict.ApplyBarTexture` as a GUI-callable module method.

### GUI/GUI.lua — Texture picker + Consume color opacity
- `MakeCheckerSwatch:Refresh(r,g,b,a)`: extended to accept alpha so the swatch preview reflects the current opacity.
- `GUI:CreateStackedColorSwatch`: added optional 7th arg `a0` (initial alpha). When provided, the color picker opens with an opacity slider, `onChanged` receives `(r,g,b,a)`, and the swatch preview shows the alpha via the checkerboard layer.
- `MakeSwatchWithAlpha(label, key)`: new local helper in the reapmeter RegisterContent closure — builds a swatch with opacity support, saves all 4 channels to `db.colors[key]`.
- Card 4 (Shared): added **Bar Texture** dropdown (LSM statusbar list, prepended with "Solid"). Calls `ReapPredict.ApplyBarTexture` on change.
- Card 6 (Colors — Fury Bar): added **Consume predict** swatch with opacity slider for `furyConsume`, placed between Fury fill row and Soul projection row.

---

## 2026-04-25

### Modules/ReapMeter/ReapMeter.lua — Bug fixes from code review
- `PositionSFBar()`: added early return if `currentPxPerStack` is nil or 0, preventing a nil arithmetic error when the function is called before `ApplyPhaseMode`/`RecomputeDerived` has run.
- `ApplyFuryLayout()`: added early return if `GetPlayerFuryMax()` returns nil or 0, preventing division-by-zero on `W / furyMax`.

### Modules/ReapMeter/ReapMeter.lua — Visual fixes (earlier in session)
- `PositionSFBar()`: clamped `mocPreview` width mathematically so the yellow preview bar never overflows the right edge of the frame.
- `ApplyPhaseMode()`: in build phase, reanchored `growthLabel` and `sfLabel` to frame-relative `RIGHT` points (instead of `thresholdLine`-relative), preventing them from rendering outside the frame when the threshold line sits at the far right.
- `MakeLabel()`: removed drop shadow (`SetShadowOffset(0,0)`) — the `OUTLINE` flag alone handles readability.
- Build phase label gap: shifted `growthLabel` 2 px left and `sfLabel` 2 px left to visually close the gap between the two counters when no separator is present.

### GUI/GUI.lua — Removed unused cards
- Removed REAP Alert card (card 8): feature cancelled — CDM `auraInstanceID` is secret in-combat, making it impossible to reliably read soul count from outside the addon.
- Removed Soul Cap Counter card: feature cancelled after multiple failed iterations.

---

## 2026-04-10 — v1.6.0

- Added 6 new color themes: Catppuccin, Rosé Pine, Tokyo Night, Nord, Dracula, Gruvbox
- Removed AutoPI and AutoInnervate modules
- Fixed auto-fill delete confirmation using the correct localized text (French clients now see "EFFACER" instead of "DELETE")
- Various bug fixes

## 2026-04-09 — v1.5.9

### Modules/AutoPI/AutoPI.lua — Bug fixes: slash conflict + secret values + ACK toast
- Fixed `/pi` and `/picast` slash command keys to match standalone AutoPI (`PIREQ`/`PICAST` instead of `SPPI`/`SPPICAST`). When both standalone AutoPI and SuspicionsPack are loaded, SuspicionsPack now wins (it loads later alphabetically), ensuring the proactive ACK is always sent via `/picast`.
- Added `issecretvalue` guard to `OnAddonMsg` — per lessons.md, CHAT_MSG_* handlers must protect against secret string values to avoid silent crashes from `msg:match()`.
- ACK notification now shows a mini toast (same as CD/RDY notifications) instead of just a chat print — more visible mid-raid.

## 2026-04-08 — v1.5.9

### Modules/AutoPI/AutoPI.lua — Proactive PI notification + /picast fix
- `/picast` now also works when no popup is showing: ACKs the priest's current target, so the DPS gets notified even when PI was cast proactively (without a `/pi` request).
- Reverted cross-realm UnitName changes back to match the original standalone AutoPI behavior.

### Modules/AutoPlaystyle/AutoPlaystyle.lua — Remove auto-select Mythic+ feature
- Removed `SelectDefaultMythicPlusGroup` and `FindMythicPlusGroupID` (feature removed on request).
- Hooks restored to original state.

### Modules/CombatTimer/CombatTimer.lua — Always-shown mode restored
- `showLastDuration` toggle re-added: off = timer only during combat, on = always visible.
- Fixed missing `frame:Show()` in `OnEnterCombat` (timer was never appearing).

### Modules/Automation/Automation.lua — Localized delete confirmation
- Auto-fill delete now uses `_G["DELETE"]` (WoW localized global) instead of hardcoded `"DELETE"` — French clients get "EFFACER" automatically.

### Core.lua / GUI.lua — Cleanup
- Removed `autoPlaystyle.defaultMythicPlus` DB field.
- Removed "Auto-select Mythic+" GUI toggle.

### All .toc / Core.lua — v1.5.8 → v1.5.9

---

## 2026-04-06 — v1.5.8

### Modules/AutoPlaystyle/AutoPlaystyle.lua — Auto-select Mythic+ group
- Added `SelectDefaultMythicPlusGroup`: when the listing creation dialog opens, automatically selects the Mythic+ group (instead of defaulting to Mythic). Uses `C_LFGList.GetAvailableActivityGroups` / `GetAvailableActivities` to locate the M+ groupID in the dialog's category, then calls `LFGListEntryCreation_Select` deferred by one frame to let the dialog finish initialising.
- Updated `LFGListEntryCreation_Show` hook to pass `activityID` arg for category derivation.
- Includes the debug prints required for arg/field verification.

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

### Modules/MovementAlert/MovementAlert.lua — Refonte détection (sans charge tracking)
- **Suppression complète du charge tracking manuel** : `cachedChargeCount`, `chargeRechargeStart`, `rechargeTimers`, `lastChargeDecrement`, `StartRechargeTimer`, `StopRechargeTimer`, `UpdateCachedCharges` — source des désynchronisations.
- **Nouvelle logique de détection** : `GetSpellCooldown` direct dans `CheckMovementCooldown`. Condition : `cdInfo.timeUntilEndOfStartRecovery` truthy + `isOnGCD == false` + `isOnGCD ~= nil`. Exception WARLOCK : `isOnGCD == nil` autorisé (Demonic Circle quirk).
- **`SPELLS_WITH_OWN_GCD`** : remplace l'ancien mécanisme `OWN_GCD_SPELLS`. Pour DH Shift (1234796), `UNIT_SPELLCAST_SENT` pose `ignoreMovementCd = true` pendant 0.8 s (durée GCD) pour éviter le faux positif isOnGCD=false du DH. CheckMovementCooldown est rappelé à l'expiration.
- **`UNIT_SPELLCAST_SENT` sorti du bloc `if db.showTimeSpiral`** : `ignoreMovementCd` doit fonctionner même quand Time Spiral est désactivé.
- **Suppression du système d'alias** (`SPELL_ALIAS_GROUPS`, `SPELL_ALIAS_MAP`, `SPELL_CATEGORY_DURATION`, `GetKnownCategoryDuration`, `RebuildTrackedSpellSet`, `trackedSpellSet`) — uniquement utile pour le charge tracking supprimé.
- **Suppression de `IsSecret`**, `SafeGetChargeInfo`, `SafeGetBaseDuration` — plus utilisés.
- **Events retirés** : `SPELL_UPDATE_CHARGES`, `UNIT_SPELLCAST_SUCCEEDED`, `PLAYER_REGEN_ENABLED`.
- **`BuildMovementSpellList` simplifié** : entrées sans `isChargeSpell`/`maxCharges`/`rechargeDuration`/`baseDuration`.

### tasks/lessons.md — Nouvelle règle

### Modules/MovementAlert/MovementAlert.lua — Time Spiral icon + LSM sound
- Ajout de l'icône de sort pour la Time Spiral : frame lazy-créé avec texture de sort, spiral de cooldown (`CooldownFrameTemplate`) et glow natif (`ActionButton_ShowOverlayGlow`).
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

### Modules/FocusTargetMarker/ — Nouveau module
- **Nouveau fichier** : `SuspicionsPack/Modules/FocusTargetMarker/FocusTargetMarker.lua`
- Écrit aux conventions du pack.
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

### GUI/GUI.lua — Animation de hover sur tous les widgets interactifs

#### Objectif
Style de hover du pack : fond foncé (`bgMedium`) permanent, border qui anime en douceur vers la couleur accent au hover et revient à `T.border` au leave. Animation de 0.15 s avec easing ease-out quadratique.

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

**Fix** :
- Suppression de `_healthMonitor` + `local function UpdateAlpha(btn)`.
- Ajout de `function REC:UpdateAlpha(event, unit)` (méthode module, filtre UNIT_HEALTH par unit).
- Dans `Activate()` : enregistrement des événements via **AceEvent-3.0** (`self:RegisterEvent(..., "UpdateAlpha")`). AceEvent utilise son propre frame interne dans un contexte propre.
- Garde pcall autour de `cur / max * 100` pour les contextes résiduelment tainter.
- `HidePreview()` et `EndDragMode()` appellent `self:UpdateAlpha()` à la place de l'ancienne fonction locale.

---

## 1.9.0 — 2026-08-05

### Nouveau module : Micro Menu Skin

`SuspicionsPack/Modules/MicroMenuSkin/MicroMenuSkin.lua` (nouveau)

Reskin du micromenu Blizzard dans le style ElvUI. **Skin visuel uniquement** — aucun reparent, aucun déplacement de bouton, donc zéro taint et safe en combat. Le placement reste géré par Blizzard / Edit Mode.

**Ce que fait le module** :
- Backdrop plat + bordure fine dessinés en textures `BACKGROUND` sublevel -8/-7 sur le bouton lui-même (garanti derrière le glyphe, pas de bagarre de frame level).
- Strip du chrome Blizzard : `Background`, `PushedBackground`, `PushedShadow`, `Flash`, `FlashContent`, `PortraitMask`. Liste reprise d'ElvUI `MicroBar.lua`.
- Crop des icônes atlas via `C_Texture.GetAtlasInfo` → `SetTexture(file)` + `SetTexCoord` dans les UV de l'atlas (un `SetTexCoord` direct après `SetAtlas` afficherait la planche entière).
- Bordure accent au survol, highlight blanc plat, pushed teinté accent.
- Option desaturate (icônes N&B, recolorées au survol), masquage de la perf bar via alpha+scale (pas `:Hide()`, qui peut tainter) — non optionnel.
- Sliders **taille de bouton** et **écart**. On resize les boutons puis on pilote la grille native de Blizzard (`MicroMenu.childXPadding/childYPadding` + `oldGridSettings = nil` + `MicroMenuContainer:Layout()`) au lieu de ré-ancrer les boutons nous-mêmes.
- **Clignotement du bouton menu de jeu (cause racine).** `MainMenuMicroButtonMixin:OnUpdate` réécrit `SetNormalAtlas` + `SetPushedAtlas` + `SetDisabledAtlas` + `SetHighlightAtlas` **toutes les secondes** (`PERFORMANCE_BAR_UPDATE_INTERVAL = 1`) pour piloter l'indicateur de streaming. Chaque appel efface notre crop. On ne hookait que `SetHighlightAtlas`, et en différé d'une frame via `C_Timer.After(0)` → une frame d'icône Blizzard brute affichée chaque seconde. Corrigé : les 4 setters sont hookés et le re-crop est **synchrone** (`ReskinIcon`, ~12 appels texture). `hooksecurefunc` s'exécute dans la même frame que l'appel Blizzard et avant le rendu, donc l'écart est invisible.
- Le hook `UpdateMicroButtons` passe aussi en synchrone (`ApplyNow`) pour la même raison. Le chemin différé/coalescé ne sert plus qu'aux setters du portrait de personnage.
- Filet de sécurité `KillStrayFlashes()` : parcourt les enfants réels de `MicroMenu` plus `HelpOpenWebTicketButton` (le "?" de ticket MJ, qui vit hors de `MicroMenu`), pour couper le flash de tout bouton absent de la liste statique.
- Suppression du clignotement : `MicroButtonPulseStop()` **avant** de blanker les textures (`UIFrameFlashStop` remet alpha=1 et Show, donc l'ordre inverse serait annulé), puis kill de `FlashBorder`, `FlashContent` et `Flash`. Hook sur `MicroButtonPulse` pour tuer à la source.

**Pièges WoW gérés** :
- `hooksecurefunc("UpdateMicroButtons")` obligatoire : Blizzard réécrit les textures à chaque changement d'état (sac, sort, quête, regen). Sans le hook le skin saute.
- `Refresh()` passe par `Activate()` et non `ApplySkin()` : AceAddon a `defaultModuleState = true`, donc `IsEnabled()` est déjà vrai au login et `OnEnable` ne se rejoue jamais. Appeler `ApplySkin()` directement n'installerait jamais le hook → skin effacé au premier `UpdateMicroButtons`.
- Résolution atlas re-sondée à chaque passe : `GetAtlas()` renvoie l'atlas vivant quand Blizzard vient d'en poser un (indicateur de maj du menu principal, portrait), et `nil` juste après notre `SetTexture()`. Le cache `_spAtlas` sert de repli. `false` = "sondé, pas d'atlas" et est retraité comme `nil` pour rattraper les textures peuplées tardivement.
- Coalescing `QueueApply()` derrière un flag + `C_Timer.After(0)` : une passe complète = ~400 appels texture, et `UpdateMicroButtons` part en rafale.
- **Layout via la grille native, pas de ré-ancrage manuel.** Chaîner les boutons LEFT→RIGHT soi-même casse trois choses : le layout empilé 2 rangées (véhicule / override bar / pet battle, où `MicroMenu` reçoit un `stride` de `numButtons/2`) est aplati en une seule ligne ; `MicroMenu` garde une taille périmée donc la boîte Edit Mode, `QueueStatusButton`, `FramerateFrame` et le bouton de ticket GM restent mal ancrés ; et trier par `GetLeft()` donne des ex æquo que `table.sort` (quicksort, instable) peut ordonner différemment d'une passe à l'autre.
- Pas de garde combat sur le layout : les micro boutons sont de simples `Button` non protégés et les méthodes `LayoutFrame` ne le sont pas non plus.
- Cache `GetAtlasInfo` par nom d'atlas (la fonction alloue une table par appel).
- `ipairs` sur `{ normal, pushed, disabled }` évité dans `RemoveSkin` — un `nil` en tête stoppe l'itération.
- `hooksecurefunc` global gardé par `type(_G.UpdateMicroButtons) == "function"`.
- Hooks `SetHighlightAtlas` / `SetPushed` / `SetNormal` par bouton : Blizzard les repose hors de `UpdateMicroButtons`.
- `normal:SetAlpha(1)` au survol : une fois skinné, le normal n'est plus intégré au highlight (workaround ElvUI).

**Perf (audit avant release, chiffres mesurés contre la source Blizzard)** :
- `UpdateMicroButtons()` n'est câblé à **aucun** événement de sac, cooldown, sort, loot ou combat sur retail — le seul chemin chaud est `QUEST_LOG_UPDATE` via `LFDMicroButtonMixin:OnEvent`. En raid/M+ le module coûte ~0. Le régime permanent, c'est le `OnUpdate` 1 Hz de `MainMenuMicroButton` : ~120 appels C/s, 0 octet alloué.
- **Amplification 33× corrigée.** Un seul `UpdateMicroButtons()` produit ~33 `SetHighlightAtlas` (`StoreMicroButton` et `MainMenuMicroButton` relancent chacun le sweep complet `EnableMicroButtons()`, et chaque `SetNormal`/`SetPushed` appelle aussi `SetHighlightAtlas`). Avec un handler partagé ça faisait 33 re-skins 4 textures par passe. Un handler **par setter** (`SETTER_HOOKS`) : `SetHighlightAtlas` ne refait plus que le highlight, 5 appels au lieu de 30.
- `KillStrayFlashes()` sorti d'`ApplySkin` → appelé une fois à l'activation. Il retuait à chaque passe exactement les boutons que `SkinButton` venait de traiter : ~195 appels C dupliqués + une table allouée pour la liste d'enfants.
- Passe complète : **~2175 → ~1155 appels C** (~0,9 ms → ~0,47 ms), zéro changement visuel.
- `atlasInfoCache` (cache de `GetAtlasInfo` par nom d'atlas) évite ~138 tables allouées par passe, soit ~620 Ko/s en pointe. À ne pas régresser.
- Aucun `OnUpdate`, aucun ticker répétitif dans le module.

**Fichiers touchés** :
- `Core.lua` — defaults `microMenuSkin`, entrée changelog, version 1.9.0
- `SuspicionsPack.toc` — chargement du module
- `GUI/GUI.lua` — item sidebar (section INTERFACE), `IsModuleEnabled`, page de config (couleurs backdrop/bordure/hover, sliders épaisseur/inset/zoom/highlight, override taille + écart, toggle desaturate)

---

## 2.0.0 — Architecture rebuild

The foundations of the addon were rewritten. No feature was removed: what changed is
everything running underneath.

### What was rebuilt

**One lifecycle for all 30 modules.** Three competing activation conventions had grown
side by side and contradicted each other — one "disabled" module kept working, another
stayed dead until a `/reload`. They now share a single contract: your setting is the
only source of truth, and a module you switch off registers nothing at startup.

**A shared clock.** Every module that animated something ran its own loop, started on
activation and never stopped. They now go through one driver that shuts down completely
when nobody needs it.

**On-demand options window.** It accounted for 43% of the code read at every login while
only being needed when you open it. It is now a companion addon loaded on demand.

**Settings migration.** The addon had no mechanism for updating its own stored data:
every setting ever introduced stayed in your file forever, including those of features
removed long ago. A versioned migration system cleans that up on first launch, and
profile import can no longer re-inject dead settings.

**Deduplication.** Fonts, anchoring, alert frames and shared textures were copy-pasted
into every module and had drifted apart — some fonts no longer resolved correctly. One
source for each.

### Performance

At rest, the addon now costs nothing. The three permanent loops that ran for the whole
session — in town, out of combat, with nothing to display — now stop as soon as they
have no work left.

- **ReapPredict** no longer registers its eight combat events, two of them the noisiest
  in the game, on characters that are not a Devourer Demon Hunter.
- **Combat Timer** only appeared to run 4 times a second: it was called 60 times and
  discarded 56 of them. It now runs only in combat.
- **Movement Alert** scanned cooldowns 10 times a second permanently. It now only runs
  while a countdown is on screen.
- **ReapPredict**'s polling no longer costs any CPU between measurements.
- Disabled modules no longer cost any processing at startup.

### Fixes

Several dozen, including: settings that only applied after a `/reload`, options pages
that stacked on top of each other, modules that overwrote Blizzard settings without
restoring them, and memory leaks when repeatedly opening the window.

---

## À venir / connu

- Rien de connu pour l'instant.
