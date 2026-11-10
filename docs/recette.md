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

## Itération 1 — détections en arrière-plan

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] La fenêtre s'affiche immédiatement ; « Détection du poste… » dans l'en-tête, « Détection en cours… » dans les sections 2, 4, 9 et 10.
- [ ] Pendant la détection, la fenêtre reste réactive : on peut cocher, faire défiler, saisir un nom d'hôte ; la pastille de connexion passe au vert.
- [ ] Lancer reste grisé « détection du poste en cours » jusqu'à la fin du relevé.
- [ ] Une card constructeur cliquée pendant la détection reste sélectionnée après le relevé (pas d'écrasement par la présélection).
- [ ] À la fin du relevé, toutes les sections sont remplies comme à l'itération 0 ; aucune ligne `[ERREUR]` dans le journal.
- [ ] Fermer la fenêtre pendant la détection : l'outil se ferme sans message d'erreur.

## Itération 2 — plan d'exécution unique (simulation)

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] Lancer : chaque action cochée apparaît avec le préfixe `[ETAPE nn/13 · section s]`, dans l'ordre du cahier (2 → 13), quel que soit l'ordre de saisie.
- [ ] Office Click-to-Run + MSI cochés : une seule ligne ODT de suppression, suivie du XML (`Remove All`, `RemoveMSI`).
- [ ] « Outlook classique » seul (Office décoché) : avertissement `[ATTN]`, aucune action.
- [ ] Désinstallations : silencieuses d'abord, assistants en dernier, en `[ATTN]`.
- [ ] Carte réseau dont IPv6 est déjà désactivé cochée : aucune action pour elle.
- [ ] Pendant l'exécution : colonnes grisées, « Exécution en cours… » ; à la fin, formulaire de nouveau utilisable.
- [ ] Rapport final : nombre d'actions, emplacement de l'inventaire et du journal, rappels manuels.

## Itération 3 — premier mode réel (poste de test uniquement)

> À dérouler sur un **poste de test réinitialisé**, jamais sur un poste en service.

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] `Lancer.cmd -Real` : bandeau rouge « MODE RÉEL — le poste sera modifié ».
- [ ] Lancer : boîte de confirmation avec le nombre d'actions et le nombre d'actions ignorées (étapes pas encore disponibles en réel) ; « Non » n'exécute rien.
- [ ] Alimentation : après exécution, `powercfg /query` montre 5 min (écran) et 15 min (veille), sur secteur et sur batterie.
- [ ] IPv6 : désactivé sur les cartes cochées (`Get-NetAdapterBinding -ComponentID ms_tcpip6`), inchangé sur les autres.
- [ ] Adobe Acrobat Reader installé (64 bits) ; relancer : ligne « déjà installé », pas d'erreur.
- [ ] winget absent (désinstaller le « Programme d'installation d'application » sur un poste de test) : réenregistrement, sinon installation depuis `packages\`.
- [ ] Nom d'hôte : appliqué après redémarrage manuel ; ligne « Redémarrage nécessaire » dans le rapport final ; aucun redémarrage automatique.
- [ ] Actions des étapes non disponibles : lignes `[ATTN] … ignorée`, rien de modifié (Office, Teams, OneDrive toujours présents).
- [ ] Une action en échec (ex. carte réseau débranchée puis renommée) : ligne rouge, les actions suivantes s'exécutent.
- [ ] Noter les codes de sortie de winget observés (journal, lignes `[DEBUG]`).
