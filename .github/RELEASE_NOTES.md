## Reap Predict en combat

La barre d'âmes, l'aperçu de Reap et la prédiction de fureur ne fonctionnaient
qu'en dehors des combats. Elles lisaient le compte de fragments par un chemin que
le patch 12.1 bloque dès que les auras deviennent secrètes — c'est-à-dire
pendant toute la durée d'un combat. Elles passent désormais par la donnée que le
Cooldown Manager conserve lui-même, qui reste lisible.

## Deux affichages qui mentaient

Une lecture que le client refuse **conserve sa dernière valeur** au lieu de
retomber à zéro. Un zéro affiché avec assurance à côté d'une barre visiblement
pleine est pire qu'un chiffre en retard d'un instant.

Pour la même raison, le nombre de fureur n'écrit plus « 0 » quand le client
refuse de donner la valeur : il garde le dernier chiffre connu, et la barre
elle-même reste exacte.
