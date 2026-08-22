-- SuspicionsPack — InterruptAlert
-- Affiche « Interrompu [icône] Nom du sort » quand TU kickes.
--
-- ============================================================
-- POURQUOI PAS LE COMBAT LOG
--
-- L'implémentation évidente serait COMBAT_LOG_EVENT_UNFILTERED + SPELL_INTERRUPT :
-- une ligne, tout est dans la charge utile, y compris qui a kické quoi.
-- Elle n'existe plus. Cet événement est protégé depuis la 12.1 et LÈVE À
-- L'ENREGISTREMENT -- ce n'est pas un champ qui devient secret, c'est
-- RegisterEvent lui-même qui refuse.
--
-- À la place, deux événements ordinaires sont corrélés :
--
--   1. UNIT_SPELLCAST_SUCCEEDED sur player/pet, et le sort lancé appartient à
--      la table des kicks de ta spé            -> on arme un drapeau
--   2. UNIT_SPELLCAST_INTERRUPTED (ou CHANNEL_STOP) arrive dans la fenêtre
--                                              -> c'était le tien
--
-- CHANNEL_STOP est là parce que kicker un sort CANALISÉ ne lève pas
-- INTERRUPTED mais CHANNEL_STOP. Le prix de ce choix est réel et assumé : un
-- canalisé qui se termine normalement pendant la fenêtre peut être pris pour
-- ton kick. La fenêtre est courte pour cette raison.
--
-- ============================================================
-- ORDRE DES GARDES (12.1)
--
-- Un spellID peut être secret. Il se PASSE de main en main sans problème, mais
-- toute comparaison, indexation ou test de vérité dessus lève. Donc :
-- issecretvalue D'ABORD ET SEUL, avant même de l'utiliser comme clé de table --
-- indexer avec un secret est exactement la même comparaison interdite que `==`.

local SP = SuspicionsPack

local IA = SP:NewSPModule("InterruptAlert", "interruptAlert")
SP.InterruptAlert = IA

local C_Timer          = C_Timer
local C_Spell          = C_Spell
local UnitGUID         = UnitGUID
local CreateFrame      = CreateFrame

-- Localisé avec repli : ce fichier lit l'API à chaque lancer de sort du joueur,
-- donc une globale absente serait une erreur dure plusieurs fois par seconde.
local _issecretvalue = issecretvalue or function() return false end

local SP_FONT = "Interface\\AddOns\\SuspicionsPack\\Media\\Fonts\\Expressway.ttf"

-- ============================================================
-- Fenêtre de corrélation
--
-- Assez longue pour qu'une interruption à PROJECTILE parte et atterrisse
-- (Bouclier du vengeur), assez courte pour que le kick d'un allié tombant dans
-- le même battement soit rarement pris pour le tien. Un Bouclier du vengeur
-- lancé à portée maximale sur une mauvaise connexion peut quand même sortir de
-- la fenêtre : c'est le compromis, et il penche du côté « rater une annonce »
-- plutôt que « s'attribuer le kick d'un autre ».
-- ============================================================
local WINDOW = 0.35

-- ============================================================
-- Quel sort compte comme TON kick, par spé
--
-- Un ENSEMBLE par spé, pas une liste : la recherche tourne à chaque sort que tu
-- lances, donc il faut une seule indexation de hachage et pas un parcours.
-- ============================================================
local function Set(...)
    local t = {}
    for i = 1, select("#", ...) do t[select(i, ...)] = true end
    return t
end

local PUMMEL       = 6552      -- Guerrier
local REBUKE       = 96231     -- Paladin
local AVENGER_1    = 31935     -- Bouclier du vengeur (Protection)
local AVENGER_2    = 375576
local COUNTERSHOT  = 147362    -- Chasseur (BM / Précision)
local MUZZLE       = 187707    -- Chasseur (Survie)
local KICK         = 1766      -- Voleur
local SILENCE      = 15487     -- Prêtre Ombre
local MIND_FREEZE  = 47528     -- Chevalier de la mort
local WIND_SHEAR   = 57994     -- Chaman
local COUNTERSPELL = 2139      -- Mage
local SPEAR_HAND   = 116705    -- Moine
local SKULL_BASH   = 106839    -- Druide (formes de combat)
local SOLAR_BEAM   = 78675     -- Druide Équilibre
local DISRUPT      = 183752    -- Chasseur de démons
local QUELL        = 351338    -- Évocateur

-- Les kicks de familier sont dans l'ensemble du démoniste, pas à part : la
-- Verrouillage de sort d'un chien de Sang ou le Jet de hache d'un gardevil,
-- c'est « est-ce que j'ai kické » du point de vue du joueur. On accepte tout
-- l'ensemble sans chercher quel démon est sorti -- un kick qui n'a pas eu lieu
-- ne peut de toute façon rien interrompre, donc rien ne sera annoncé.
local WARLOCK_PET = Set(19647, 119910, 132409, 89766)

local INTERRUPTS = {
    -- Guerrier
    [71]   = Set(PUMMEL), [72] = Set(PUMMEL), [73] = Set(PUMMEL),
    -- Paladin (Sacré n'a pas de kick)
    [66]   = Set(REBUKE, AVENGER_1, AVENGER_2),
    [70]   = Set(REBUKE),
    -- Chasseur
    [253]  = Set(COUNTERSHOT), [254] = Set(COUNTERSHOT), [255] = Set(MUZZLE),
    -- Voleur
    [259]  = Set(KICK), [260] = Set(KICK), [261] = Set(KICK),
    -- Prêtre (Ombre uniquement)
    [258]  = Set(SILENCE),
    -- Chevalier de la mort
    [250]  = Set(MIND_FREEZE), [251] = Set(MIND_FREEZE), [252] = Set(MIND_FREEZE),
    -- Chaman (les trois : les soigneurs kickent aussi)
    [262]  = Set(WIND_SHEAR), [263] = Set(WIND_SHEAR), [264] = Set(WIND_SHEAR),
    -- Mage
    [62]   = Set(COUNTERSPELL), [63] = Set(COUNTERSPELL), [64] = Set(COUNTERSPELL),
    -- Démoniste (via le familier)
    [265]  = WARLOCK_PET, [266] = WARLOCK_PET, [267] = WARLOCK_PET,
    -- Moine
    [268]  = Set(SPEAR_HAND), [269] = Set(SPEAR_HAND), [270] = Set(SPEAR_HAND),
    -- Druide
    [102]  = Set(SOLAR_BEAM), [103] = Set(SKULL_BASH),
    [104]  = Set(SKULL_BASH), [105] = Set(SKULL_BASH),
    -- Chasseur de démons
    [577]  = Set(DISRUPT), [581] = Set(DISRUPT),
    -- Évocateur
    [1467] = Set(QUELL), [1468] = Set(QUELL), [1473] = Set(QUELL),
}

IA.InterruptSets = INTERRUPTS   -- lu par la page GUI pour dire si ta spé kicke

-- ============================================================
-- État
-- ============================================================
IA.frame     = nil
IA.isPreview = false

local armed        = false
local armedTimer   = nil
local kickSet      = nil     -- l'ensemble de la spé courante, ou nil
local specKnown    = false   -- la spé a répondu, quelle que soit la réponse
local eventFrame   = nil     -- AceEvent-3.0 n'a pas RegisterUnitEvent
local hideTimer    = nil

-- ============================================================
-- Résolution de spé — C_SpecializationInfo d'abord, globales en repli
--
-- Le test de plage est explicite : 0 est VRAI en Lua et c'est exactement ce que
-- ces API rendent quand aucune spé n'est choisie, donc `if index` passerait
-- droit dessus.
-- ============================================================
local function ResolveSpecID()
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
                    or _G.GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo)
                    or _G.GetSpecializationInfo
    if not (getSpec and getInfo) then return nil end

    local index = getSpec()
    if type(index) ~= "number" or index < 1 then return nil end

    local specID = getInfo(index)
    if type(specID) ~= "number" or specID < 1 then return nil end
    return specID
end

function IA:CacheKickSet()
    local specID = ResolveSpecID()
    specKnown = specID ~= nil
    kickSet   = specID and INTERRUPTS[specID] or nil
end

-- ============================================================
-- Cadre
-- ============================================================
function IA:CreateAlertFrame()
    if self.frame then return end
    local db = self:GetDB()

    local f, lbl = SP.CreateAlertFrame("SP_InterruptAlertFrame", db, {
        defaultY       = 172,
        defaultSize    = 20,
        defaultOutline = "OUTLINE",
        defaultColor   = { 0.45, 0.85, 1, 1 },
        width          = 400,
    })
    f.label    = lbl
    self.frame = f
end

function IA:ApplySettings()
    if not self.frame then return end
    local db = self:GetDB()
    self.frame:ClearAllPoints()
    local anchorFrame = _G[db.anchorFrame or "UIParent"] or UIParent
    self.frame:SetPoint(db.anchorFrom or "CENTER", anchorFrame,
                        db.anchorTo or "CENTER", db.x or 0, db.y or 172)
    self.frame:SetFrameStrata(db.frameStrata or "HIGH")
    if self.frame.label then
        local fontPath    = (db.fontFace and SP.GetFontPath and SP.GetFontPath(db.fontFace)) or SP_FONT
        local outlineFlag = (db.fontOutline ~= "NONE" and db.fontOutline) or "OUTLINE"
        SP.SetFontSafe(self.frame.label, fontPath, db.fontSize or 20, outlineFlag)
        local cr, cg, cb = SP.GetColorFromSource(db.colorSource or "custom",
            db.color or { 0.45, 0.85, 1 })
        self.frame.label:SetTextColor(cr, cg, cb, 1)
    end
end

-- ============================================================
-- Affichage
--
-- Le restylage EST ici, juste avant le Show, et pas seulement au login. C'est
-- la leçon de la 2.6.7 sur MovementAlert : chercher l'instant du login où la
-- police « tient » a coûté cinq versions, alors qu'appliquer à l'affichage rend
-- la question sans objet. La garde relit GetFont sur le FontString plutôt que
-- de mémoriser ce qui a été demandé, pour voir aussi ce qui vient d'ailleurs.
-- ============================================================
local function EnsureStyled(self)
    local lbl = self.frame and self.frame.label
    if not lbl then return end
    local db          = self:GetDB()
    local fontPath    = (db.fontFace and SP.GetFontPath and SP.GetFontPath(db.fontFace)) or SP_FONT
    local size        = db.fontSize or 20
    local outlineFlag = (db.fontOutline ~= "NONE" and db.fontOutline) or "OUTLINE"

    local curFace, curSize, curFlags = lbl:GetFont()
    if curFace == fontPath
        and type(curSize) == "number" and math.abs(curSize - size) < 0.5
        and (curFlags or "") == outlineFlag
    then
        return
    end
    SP.SetFontSafe(lbl, fontPath, size, outlineFlag)
end

function IA:ShowMessage(text)
    if not self.frame then self:CreateAlertFrame() end
    local db = self:GetDB()

    EnsureStyled(self)
    self.frame.label:SetText(text)
    self.frame:Show()

    if hideTimer then hideTimer:Cancel() end
    hideTimer = C_Timer.NewTimer(db.duration or 3, function()
        hideTimer = nil
        if not IA.isPreview and IA.frame then IA.frame:Hide() end
    end)
end

-- ============================================================
-- Composition de la ligne
--
-- C_Spell.GetSpellInfo est AllowedWhenTainted : il accepte un spellID SECRET et
-- répond proprement. C'est ce qui rend possible de NOMMER le sort kické en
-- contenu restreint, là où tout le reste de la charge utile est illisible.
--
-- L'icône est insérée RECADRÉE (5..59 sur 64) et pas en |Tid:taille|t nu : une
-- icône de sort porte sa bordure gravée dans l'art, et à la taille du texte
-- cette bordure se lit comme un bloc décalé posé à côté de la ligne plutôt que
-- comme une icône. La largeur est donnée explicitement pour qu'une source non
-- carrée ne puisse pas s'étirer.
--
-- string.format ne reçoit QUE des valeurs propres : name et iconID reviennent
-- déjà résolus d'une API sûre, donc rien de secret n'est concaténé ici.
-- ============================================================
local function ComposeLine(db, spellID)
    local prefix = db.text or "Interrompu"
    local info   = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    if not (info and info.name) then return prefix end

    if db.showIcon ~= false and info.iconID then
        local size = db.fontSize or 20
        return ("%s |T%d:%d:%d:0:0:64:64:5:59:5:59|t %s")
            :format(prefix, info.iconID, size, size, info.name)
    end
    return ("%s %s"):format(prefix, info.name)
end

-- ============================================================
-- 1. Tu lances ton kick -> on arme
-- ============================================================
function IA:OnCast(spellID)
    -- Résolution PARESSEUSE plutôt qu'un abandon silencieux.
    --
    -- Activate tourne à PLAYER_LOGIN, où les API de spécialisation répondent
    -- encore nil. Se contenter du cache posé là laisserait kickSet à nil pour
    -- toute la session si les deux événements de rafraîchissement manquaient
    -- leur coup -- c'est exactement le défaut corrigé dans SpellEffectAlpha en
    -- 2.6.6, et il n'y a aucune raison de le réintroduire ici.
    --
    -- Ré-essayer AU MOMENT DU LANCER est mieux qu'un minuteur de reprise : si tu
    -- lances un sort, ta spé est forcément connue. Une seule résolution, puis le
    -- cache tient jusqu'au prochain changement de spé.
    -- specKnown, et pas `if not kickSet`, parce qu'une spé SANS interruption
    -- (Paladin Sacré, Prêtre Discipline et Sacré) donne légitimement kickSet =
    -- nil. Retenter là-dessus relancerait la résolution à chaque sort lancé par
    -- un soigneur -- une réponse valide n'est pas un échec.
    if not specKnown then
        self:CacheKickSet()
        if not kickSet then return end
    elseif not kickSet then
        return
    end

    local db = self:GetDB()
    if not (db and db.enabled) then return end

    -- Le test de secret est SEUL et EN PREMIER. Indexer kickSet avec un secret
    -- serait la même comparaison interdite qu'un `==` dessus.
    if _issecretvalue(spellID) then return end
    if not kickSet[spellID] then return end

    armed = true
    if armedTimer then armedTimer:Cancel() end
    armedTimer = C_Timer.NewTimer(WINDOW, function()
        armed      = false
        armedTimer = nil
    end)
end

-- ============================================================
-- 2. Quelque chose se fait interrompre -> c'était toi
--
-- Cet événement n'est PAS filtrable par unité, et ne peut pas l'être : l'unité
-- interrompue est ce que tu as kické, qui n'est souvent plus ta cible quand ça
-- arrive. Le test du drapeau est donc la toute première ligne -- une lecture de
-- booléen est le coût complet sur chaque interruption qui n'est pas la tienne.
-- ============================================================
-- Cherche un GUID d'auteur dans la charge utile SANS SUPPOSER SA POSITION.
--
-- La signature documentée de UNIT_SPELLCAST_INTERRUPTED est (unit, castGUID,
-- spellID) -- trois arguments, aucun auteur. atrocityEssentials en lit pourtant
-- un cinquième nommé `interruptedBy`. L'un des deux se trompe, et notre règle
-- maison est explicite : ne jamais supposer la signature d'un événement.
--
-- Donc on ne compte pas les arguments, on RECONNAÎT la valeur : un GUID d'unité
-- est une chaîne préfixée par son type. Si Blizzard en fournit un, où qu'il
-- soit, on l'utilise pour affiner ; s'il n'y en a pas -- ce qui est le cas
-- normal pour les interruptions à projectile, et en contenu restreint où il
-- serait secret -- le drapeau seul tient. Sauter le filtrage n'est pas renoncer
-- à l'annonce, et c'est précisément pour ça que la fenêtre est courte.
--
-- `/run SuspicionsPack.DEBUG = true` imprime la charge utile réelle : c'est ce
-- qui tranchera, en jeu, plutôt qu'une supposition de plus.
local function FindActorGUID(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if not _issecretvalue(v) and type(v) == "string"
            and (v:find("^Player%-") or v:find("^Creature%-") or v:find("^Pet%-")
                 or v:find("^Vehicle%-"))
        then
            return v
        end
    end
    return nil
end

function IA:OnInterrupted(spellID, ...)
    if not armed then return end

    local by = FindActorGUID(...)
    if by then
        local mine = UnitGUID("player")
        local pet  = UnitGUID("pet")
        if not _issecretvalue(mine) and not _issecretvalue(pet)
            and by ~= mine and by ~= pet
        then
            return
        end
    end

    armed = false
    if armedTimer then armedTimer:Cancel(); armedTimer = nil end

    self:ShowMessage(ComposeLine(self:GetDB(), spellID))
end

-- ============================================================
-- Aperçu
-- ============================================================
function IA:ShowPreview()
    if not self.frame then self:CreateAlertFrame() end
    self.isPreview = true
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    self.frame:EnableMouse(true)
    if self.frame.SetMouseClickEnabled then self.frame:SetMouseClickEnabled(true) end
    local db = self:GetDB()
    -- Contresort : un sort que tout le monde reconnaît, et dont l'icône existe
    -- sur tous les clients.
    self:ShowMessage(ComposeLine(db, COUNTERSPELL))
    self:ApplySettings()
end

function IA:HidePreview()
    self.isPreview = false
    if not self.frame then return end
    self.frame:EnableMouse(false)
    if self.frame.SetMouseClickEnabled then self.frame:SetMouseClickEnabled(false) end
    self.frame:Hide()
end

-- ============================================================
-- Cycle de vie
--
-- OnEnable / OnDisable / Refresh viennent de SP.ModuleMixin (Core/Module.lua).
-- ============================================================
local function OnUnitEvent(_, event, unit, castGUID, spellID, ...)
    if SP.DEBUG then
        -- La signature réelle, imprimée plutôt que supposée. Notre règle maison
        -- vient d'une erreur payée plusieurs fois : « NEVER assume an event's
        -- arg signature, always add a debug print first ». Sous SP.DEBUG
        -- uniquement, donc rien dans le chat en jeu normal.
        SP:Debug("InterruptAlert", event, tostring(unit), tostring(castGUID),
                 tostring(spellID), select("#", ...) .. " extra")
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        IA:OnCast(spellID)
    else
        -- castGUID et le reste sont passés tels quels : le chercheur de GUID
        -- reconnaît la valeur au lieu de compter les positions.
        IA:OnInterrupted(spellID, castGUID, ...)
    end
end

function IA:Activate()
    local db = self:GetDB()
    if not (db and db.enabled) then return end

    self:CreateAlertFrame()
    self:ApplySettings()
    -- Pas de Hide pendant un aperçu. Le GUI appelle Refresh -> Activate à CHAQUE
    -- réglage modifié, donc masquer ici ferait disparaître l'aperçu dès que tu
    -- bouges le curseur de position -- c'est-à-dire précisément quand tu
    -- regardes l'aperçu pour te repérer.
    if not self.isPreview then self.frame:Hide() end

    if not eventFrame then
        eventFrame = CreateFrame("Frame", "SP_InterruptAlertEvents")
    end
    eventFrame:SetScript("OnEvent", OnUnitEvent)
    -- SUCCEEDED est filtré à player+pet au niveau C, donc ça ne tourne pas pour
    -- chaque sort du groupe. INTERRUPTED et CHANNEL_STOP ne peuvent pas l'être :
    -- l'unité est celle qui a été kickée.
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "CacheKickSet")
    self:RegisterEvent("PLAYER_ENTERING_WORLD",         "CacheKickSet")
    self:CacheKickSet()
end

function IA:Deactivate()
    self:UnregisterAllEvents()
    if eventFrame then
        eventFrame:SetScript("OnEvent", nil)
        eventFrame:UnregisterAllEvents()
    end
    if armedTimer then armedTimer:Cancel(); armedTimer = nil end
    if hideTimer  then hideTimer:Cancel();  hideTimer  = nil end
    armed          = false
    kickSet        = nil
    specKnown      = false
    self.isPreview = false
    if self.frame then self.frame:Hide() end
end
