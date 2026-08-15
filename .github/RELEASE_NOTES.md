## La taille de l'alerte de déplacement

Elle est correcte au login et à chaque affichage suivant.

Le contournement de la version précédente ne marchait pas non plus, et c'est cet
échec qui a donné la réponse : le module vérifiait sa police **une fois** au
démarrage, en espérant tomber sur le bon moment. Il la revérifie désormais
**chaque fois que l'alerte s'affiche**, ce qui rend la question du moment sans
objet. Le contournement précédent est retiré.
