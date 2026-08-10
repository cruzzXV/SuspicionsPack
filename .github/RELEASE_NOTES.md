## La musique du timer de Bloodlust

Elle s'arrêtait au bout de quelques secondes. Le son par défaut était le seul des
sept à être encodé en 48 kHz, là où les six autres sont en 44,1 kHz — le taux que
le client accepte sans discuter. Il est réencodé, sans perte audible.

Une vérification a été ajoutée à la construction : un son ajouté à l'addon dans
un format que WoW risque de refuser est signalé avant publication, et non pendant
un raid.

## Note d'installation

L'archive v2.5.1 portait par erreur un second fichier zip, construit à la main,
qui contenait un dossier enveloppe. Installé via WowUp il donnait un seul dossier
au lieu des quatre addons. Il a été retiré, et la construction refuse désormais
toute archive dont la structure n'est pas la bonne.

Si votre v2.5.1 s'est installée de travers, désinstallez puis réinstallez.
