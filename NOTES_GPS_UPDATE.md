# Documentation Technique - Mise à Jour du Moteur GPS & Fluidité (Version Hybride Finale)

## 1. Anti-Téléportation sur les Ronds-Points et Virages
- **Problème initial** : Dans un espace restreint (comme un petit rond-point), le point projeté par le GPS pouvait raccourcir l'itinéraire en "sauts" par dessus le terre-plein central.
- **Solution** :
  - La fenêtre de recherche d'itinéraire (`searchWindowMeters` dans `_getNearestRoutePoint`) a été rendue dynamique. Au lieu d'un 60.0 mètres fixe (qui provoquait des sauts à basse vitesse), elle vaut désormais `math.max(15.0, currentSpeedMps * 2.5)`. Ainsi, à pied, elle ne cherche qu'à 15 mètres (empêchant le saut de l'autre côté de la rue), mais en voiture sur l'autoroute, elle s'étend pour ne pas perdre la trace.
  - La fonction de téléportation d'urgence de la flèche (`simulatedPos = referencePos;`) a été totalement supprimée du `KinematicFilter`. La flèche est désormais obligée de coulisser physiquement le long de la ligne noire.

## 2. Gel du Cap (Anti-retournement) à l'arrêt
- **Problème initial** : Lorsqu'on s'arrêtait à un feu rouge ou à pied, le "bruit" des satellites GPS faisait croire au téléphone qu'il reculait de 1 mètre, puis avançait de 1 mètre. La flèche se mettait à tourner dans tous les sens (flip à 180°).
- **Solution** :
  - Dans `startFluidNavigation()`, une condition bloque l'actualisation du cap (Bearing) si la vitesse réelle (`vehicleSpeedMps`) tombe sous 1 km/h (`< 0.28 m/s`).
  - **Anti-Inversion** : Même à basse vitesse (entre 1 et 3 km/h), si le cap calculé diverge de plus de 100° par rapport à la trajectoire précédente, il est ignoré. L'historique des trajectoires (`_arrowTrail`) est purgé à l'arrêt.

## 3. Lissage Visuel de la Route (Courbes de Bézier)
- **Problème initial** : Les polylines renvoyées par les serveurs OSRM / Google sont constituées de segments droits. Visuellement, les virages étaient "coupés à la hache".
- **Solution** :
  - Implémentation d'un algorithme de "Corner Smoothing" personnalisé (`_smoothRouteCorners`). Il identifie chaque angle de la route, recule légèrement sur les segments adjacents, et insère 3 points intermédiaires pour courber l'angle, simulant une courbe de Bézier/Chaikin.
  - Côté MapLibre, la propriété `lineJoin: "round"` a été ajoutée pour que les textures se raccordent sans pointe.

## 4. Arrêt en douceur (Soft Stop)
- **Problème initial** : Lors d'un arrêt, la flèche stoppe parfois d'un coup sec, ce qui manquait de réalisme.
- **Solution** : Les facteurs de recul et de freinage de la flèche dans `predictNextPosition` ont été réduits (passant de 0.5 à 0.3/0.4) et le `_computeCatchupTime` a été allongé. Cela crée un effet "élastique" où la voiture ralentit progressivement pour venir se caler sur sa position finale.
