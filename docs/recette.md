# Recette manuelle — sur poste réel

L'interface WPF et les effets sur le système ne se testent qu'à la main. Cette liste est déroulée
à la fin de chaque itération sur un poste de test, puis complétée par l'itération suivante.
Cocher, dater, noter le modèle de poste et joindre le journal (`logs\Journal_*.log`).

## Itération 0 — parité avec le prototype (simulation)

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

### Démarrage
- [ ] `Lancer.cmd` demande l'élévation, puis la fenêtre s'ouvre (taille et charte identiques à la maquette validée).
- [ ] Lancé sans droits administrateur (`Preparation.ps1` directement) : message « Cet outil doit être lancé en administrateur ».
- [ ] `config.json` invalide (ex. retirer `Power.ApplyOnBattery`) : message qui cite la clé, l'outil ne s'ouvre pas.
- [ ] `Lancer.cmd -Real` : message « mode réel pas encore disponible ».
- [ ] Bandeau « MODE SIMULATION » visible.
- [ ] Clé en lecture seule : journal écrit dans `%TEMP%\FastPrepare`, ligne `[ATTN]` qui le signale.

### Section 0 — connexion
- [ ] Pastille rouge puis verte en quelques secondes ; une seule ligne « Connexion internet validée ».
- [ ] Câble/Wi-Fi coupé : pastille rouge, Lancer grisé « connexion internet non validée » ; rétabli : vert.

### Sections 1 à 10
- [ ] 1 : champ grisé si décoché ; `123`, `PC_1`, 16 caractères → motif en rouge sous le champ, Lancer grisé ; `PC-01` → Lancer actif.
- [ ] 2 : même liste que le Panneau de configuration ; colonne « Silencieux » ; « Tout cocher » coche/décoche tout.
- [ ] 3 : « Dossier OneDrive » grisé quand OneDrive est décoché ; nombre de fichiers affiché.
- [ ] 4 : comptes supprimables listés ; exclus d'office : Administrateur, Invité, DefaultAccount, WDAGUtilityAccount, compte connecté.
- [ ] 5 : quatre cards (logos si présents dans `logos\`) ; la marque du poste est présélectionnée ; une seule card à la fois ; re-clic = désélection ; ligne `[SIMU] Utilitaire sélectionné` au clic.
- [ ] 6 : quatre cards ; pastilles Avec / Sans Teams seulement pour 365 ; « Inclure » grisé sans édition ; texte d'information (ID produit, exclusions) à jour.
- [ ] 7 : « MàJ utilitaire » grisée sans card en section 5, cochée d'elle-même quand une card est choisie.
- [ ] 8 : Adobe Acrobat Reader coché par défaut.
- [ ] 9 : une case par carte physique, décochée si IPv6 est déjà désactivé ; libellé alimentation conforme à `config.json`.
- [ ] 10 : N/S et MAC affichés ; « Copier » remplit le presse-papiers ; fichier `Inventaire_<N/S>_<horodatage>.txt` présent.

### Lancer (simulation)
- [ ] Les actions cochées apparaissent dans l'ordre du cahier (1 → 14), silencieuses avant assistants.
- [ ] XML ODT affiché pour l'édition choisie ; ID `O365BusinessEEANoTeamsRetail` si « Sans Teams ».
- [ ] Rappel final des actions manuelles = liste du mémo.
- [ ] Aucune modification du poste (nom, logiciels, comptes, IPv6, alimentation inchangés).
