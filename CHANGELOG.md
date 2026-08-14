# SuspicionsPack — Changelog

> Ce fichier sert de mémoire de session. Chaque modification notable est tracée ici avec sa date, le fichier concerné et la raison du changement.

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
