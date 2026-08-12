## L'alerte Bloodlust sur le patch 12.1

Le patch a rendu secret le contenu de l'événement d'auras : l'addon n'a plus le
droit de lire ce qui vient d'être appliqué. Le module s'en servait, et cela
provoquait une erreur à chaque buff ou débuff gagné — environ 1400 pendant un
seul combat.

La détection repose désormais sur la présence du débuff d'épuisement, sans lire
aucune valeur interdite. Si une prochaine restriction ferme aussi cet accès, le
module se taira au lieu de générer des erreurs.

Un contrôle de ReapPredict qui lisait les mêmes données a été retiré. Il était
derrière le mode debug et aurait produit la même erreur si vous l'aviez activé.
