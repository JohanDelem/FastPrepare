# Recette manuelle — sur poste réel

L'interface WPF et les effets sur le système ne se testent qu'à la main. Cette liste est déroulée
à la fin de chaque itération sur un poste de test, puis complétée par l'itération suivante.
Cocher, dater, noter le modèle de poste et joindre le journal (`logs\Journal_*.log`).

> **Numérotation.** Les listes des itérations 0 à 12 sont conservées telles qu'elles ont été
> déroulées : elles citent les sections 1 à 11 et les étapes 1 à 14 du cahier des charges, la
> « clé » et `Build-Usb.ps1`. Depuis l'itération 13, l'outil ne suppose plus de clé USB et
> numérote dans l'ordre d'exécution. Correspondance pour rejouer une ancienne liste :
>
> | Ancienne section | Section actuelle | Ancienne étape | Étape actuelle |
> |---|---|---|---|
> | 1 Nom d'hôte | 8 | 13 | 11 |
> | 2 Logiciels installés | 4 | 5 | 5 |
> | 3 Programmes Microsoft | 3 | 3 et 4 | 3 et 4 |
> | 4 Sessions locales | 2 | 2 | 2 |
> | 5 Utilitaire constructeur | 5 Installations | 6 | 6 |
> | 6 Office | 5 Installations | 7 | 6 |
> | 7 Mises à jour | 7 | 11 et 12 | 9 et 10 |
> | 8 Logiciels | 5 Installations | 8 | 6 |
> | 9 Paramètres système | 6 | 9 et 10 | 7 et 8 |
> | 10 N/S et MAC | 1 | 1 | 1 |
> | 11 Créer une session | 9 | 14 | 12 |
>
> « Clé en lecture seule » se lit « dossier de sortie inaccessible » ; `VERSION.txt` se lit
> « version affichée dans le titre de la fenêtre » ; `C:\ODT` se lit `%ProgramData%\FastPrepare\odt`.

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

## Itération 4 — désinstallations réelles (poste de test uniquement)

> **Actions destructives.** Poste de test réinitialisé, sans aucune donnée à conserver.
> Préparer : Office Click-to-Run, Office MSI 2016, Teams classique (Machine-Wide Installer) et nouveau Teams,
> nouvel Outlook, OneDrive avec des fichiers synchronisés, deux comptes locaux supplémentaires
> (dont un avec une session ouverte), un logiciel MSI, un logiciel Inno Setup, un logiciel NSIS, un logiciel à assistant.

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] Sessions locales : compte et dossier de profil supprimés ; le compte à session ouverte est refusé (« profil chargé »), les autres actions continuent.
- [ ] Office : un seul passage ODT ; Click-to-Run et MSI désinstallés ; XML présent dans `C:\ODT` et dans le journal.
- [ ] Nouvel Outlook, OneNote (Store), nouveau Teams, Teams personnel : absents pour tous les utilisateurs **et** pour un nouveau profil créé ensuite (paquets provisionnés retirés).
- [ ] Teams classique : Machine-Wide Installer désinstallé, dossier `%LocalAppData%\Microsoft\Teams` du compte connecté supprimé.
- [ ] OneDrive : désinstallé ; un nouveau profil ne le réinstalle pas (clé `Run` du profil Default retirée).
- [ ] Dossier OneDrive : supprimé seulement si sa case est cochée ; jamais le profil entier.
- [ ] Logiciels : silencieux d'abord (MSI, Inno, NSIS : plus listés à la fin), assistant ensuite (l'outil attend sa fermeture) ; assistant **annulé** : action en échec « toujours présent ».
- [ ] Relancer l'outil sur le même poste : tout est « déjà absent », aucune erreur.

## Itération 5 — utilitaire constructeur (poste de test de chaque marque)

> Renseigner d'abord le lien de Thin Installer dans `config.json` (`Utilities.lenovo.Install[1].Url`, et si possible `Sha256`).

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] Mode réel : la card de la marque est présélectionnée ; sous les cards, « préchargement en cours… » puis « préchargé » (Dell, Lenovo) ou « installation par winget à l'exécution » (HP, Fujitsu).
- [ ] Simulation : aucun dossier `%ProgramData%\FastPrepare` créé.
- [ ] Dell, DCU 5.7.0 : runtime .NET Desktop 8.0.25 installé avant DCU (si aucun 8.0.8–8.0.25 présent) ; DCU démarre.
- [ ] Dell, DCU 5.7.1 (quand winget la propose) : runtime .NET 10 (≥ 10.0.8).
- [ ] Dell avec un .NET 8 plus récent que 8.0.25 déjà présent : avertissement dans le journal.
- [ ] Lenovo : Commercial Vantage installé depuis le Store ; Thin Installer installé silencieusement depuis le fichier préchargé (ligne « Fichier préchargé utilisé ») ; signature Lenovo acceptée.
- [ ] HP, Fujitsu : outil installé par winget.
- [ ] MàJ utilitaire (section 7) : outil trouvé, mise à jour lancée sans redémarrage automatique ; **noter le code de sortie** (journal, `[DEBUG]`) avec et sans mise à jour disponible, pour confirmer `SuccessExitCodes` / `RebootExitCodes` (QO4).
- [ ] Noter le chemin réel de `HPImageAssistant.exe` et `ducmd.exe` après installation par winget.

## Itération 6 — installation d'Office (poste de test)

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] 365 Apps for Business « Avec Teams » : installé (`O365BusinessRetail`), Teams présent, langue du système, 64 bits.
- [ ] 365 « Sans Teams (EEE) » : `O365BusinessEEANoTeamsRetail`, Teams absent.
- [ ] LTSC Pro Plus 2024, Standard 2019, Pro Plus 2019 : installés (`ProPlus2024Volume`, `Standard2019Volume`, `ProPlus2019Volume`) ; activation à faire à la main.
- [ ] Cases « Inclure » décochées : application absente (nouvel Outlook, Outlook classique, OneDrive).
- [ ] Suppression (section 3) et installation (section 6) dans la même exécution : suppression d'abord, puis installation, aucune erreur.
- [ ] Le XML de l'installation figure dans le journal et dans `C:\ODT\configuration-installation-*.xml`.

## Itération 7 — Windows Update, journal, avancement, clé

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] Windows Update : mises à jour (dont pilotes) téléchargées et installées sans fenêtre ; chaque titre et son résultat dans le journal ; « redémarrage nécessaire » dans le rapport ; aucun redémarrage automatique.
- [ ] Mises à jour restantes après la passe : ligne `[ATTN] … encore disponible(s)`.
- [ ] Pendant l'exécution : barre d'avancement et « Action n / N : … » sous le bouton Lancer.
- [ ] Clé protégée en écriture au démarrage, déprotégée avant la fin : journal et inventaire recopiés sur la clé (ligne « copiés sur la clé ») ; restée protégée : consigne de copie manuelle.
- [ ] `tools\Build-Usb.ps1 -Destination E:\FastPrepare` : avertissements de `config.json` affichés ; la clé ne contient que `Lancer.cmd`, `Preparation.ps1`, `config.json`, `src\`, `logos\`, `packages\`, `logs\`, `VERSION.txt` ; les anciens journaux de la clé sont conservés.

## Itération 8 — création d'une session locale (poste de test uniquement)

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

Mot de passe d'essai à choisir pour la recette, **jamais** celui d'un vrai utilisateur.

- [ ] Section 11 décochée au démarrage ; cochée sans saisie : Lancer grisé (« nom de session vide »).
- [ ] Nom d'une session existante, nom du poste (actuel ou futur nom de la section 1), nom de 21 caractères, nom avec `/` ou `@`, nom terminé par un point : refusés avec leur motif sous le formulaire et sous Lancer.
- [ ] Nom d'une session cochée en section 4 : accepté (elle est supprimée avant d'être recréée).
- [ ] Confirmation différente : Lancer grisé ; identique : Lancer actif.
- [ ] « N'expire jamais » et « Changer à la première ouverture » ne peuvent pas être cochés ensemble.
- [ ] Simulation : ligne `[SIMU] [ETAPE 14/14 · section 11] Session locale : New-LocalUser '<nom>' …` ; le mot de passe n'apparaît **nulle part** dans le fichier journal (recherche du texte saisi).
- [ ] Réel, utilisateur standard : session créée, membre du groupe Utilisateurs seulement (`net localgroup Utilisateurs`), ouverture de session possible avec le mot de passe saisi.
- [ ] Réel, administrateur + « changer à la première ouverture » : membre de Utilisateurs et Administrateurs ; Windows demande un nouveau mot de passe à la première ouverture.
- [ ] Mot de passe refusé par la stratégie du poste (ex. trop court si une longueur minimale est imposée) : action en rouge avec le motif de Windows, **aucune** session créée.
- [ ] Deuxième exécution avec la même saisie, sans relancer l'outil : action en échec « existe déjà », la session existante n'est pas modifiée.
- [ ] Le mot de passe n'apparaît pas dans le journal de l'exécution réelle.

## Itération 9 — catalogue des logiciels (onglet Réglages)

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] Onglet Réglages : la liste reprend `software.json` ; le chemin du fichier sur la clé est affiché.
- [ ] Nouveau logiciel winget (ex. 7-Zip, `7zip.7zip`) : identifiant interne déduit du libellé, commande affichée ; **Tester** → « Paquet trouvé : nom, version » ; rien n'apparaît dans « Applications installées » du poste.
- [ ] Identifiant winget inexistant → « introuvable dans la source » ; source `msstore` (ex. `9NR5B8GVVM13`) → paquet trouvé.
- [ ] Lien direct vers un installateur → « Lien valide : fichier de … Mo » ; lien vers une page web → refusé « page web » ; lien `http://` ou éditeur vide → Enregistrer grisé avec le motif.
- [ ] Modifier un champ après un test réussi → « Formulaire modifié depuis le dernier test » ; Enregistrer sans test → demande de confirmation.
- [ ] Enregistrer : la case apparaît aussitôt en section 8 (onglet Préparation), les cases déjà cochées gardent leur état ; `software.json` mis à jour, ancienne version dans `software.json.bak` ; ligne `[OK] Catalogue des logiciels : … ajouté` dans le journal.
- [ ] Retirer : confirmation, la case disparaît de la section 8.
- [ ] Clé protégée en écriture : « Catalogue non enregistré : la clé … est protégée en écriture », catalogue inchangé.
- [ ] Pendant une exécution : l'onglet Réglages est grisé.
- [ ] Exécution réelle sur poste de test : un logiciel winget et un logiciel par lien direct ajoutés depuis l'onglet sont installés ; lien direct avec un mauvais éditeur attendu → action en rouge « signature », rien n'est lancé.
- [ ] Relancer l'outil : les logiciels ajoutés sont toujours là ; `software.json` modifié à la main avec une erreur → refus au démarrage avec l'entrée fautive.
- [ ] `tools\Build-Usb.ps1` sur une clé déjà préparée : catalogue de la clé conservé (message) ; avec `-ReplaceSoftwareCatalog` : remplacé.

## Itération 10 — source winget (outil lancé avec un autre compte administrateur)

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] Lancer `Lancer.cmd` en donnant les identifiants d'un **autre** compte administrateur que la session ouverte : au démarrage, ligne `[OK] Source winget accessible`, ou bien `[ATTN] Installations winget impossibles en l'état : …` avec le nom du compte et les commandes de réparation.
- [ ] Source inutilisable réparée par la mise à jour : lignes `[ATTN] Source winget inutilisable … mise à jour des sources` puis `[OK] Source winget réparée par la mise à jour`.
- [ ] Source irréparable automatiquement : le test d'un logiciel winget (onglet Réglages) affiche le message lisible (compte, `winget source reset --force`, `winget source update`), jamais « code de sortie -1978335217 » ; après ces deux commandes lancées à la main dans une invite administrateur de ce compte, puis redémarrage de l'outil : `[OK] Source winget accessible` et test réussi.
- [ ] L'outil ne lance jamais `winget source reset` de lui-même (journal, niveau `DEBUG` : seules des commandes `source update`).

## Itération 11 — réparation de la source winget sans intervention

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

Reproduire le défaut constaté : dans une invite administrateur ouverte avec le compte qui lancera l'outil,
`powershell -NoProfile -Command "Get-AppxPackage -Name Microsoft.Winget.Source | Remove-AppxPackage"`,
puis vérifier que `winget show --id Microsoft.VisualStudioCode --exact --source winget` échoue (`0x8a15000f`).

- [ ] Lancer l'outil avec ce compte : au démarrage, `[ATTN] Source winget inutilisable …`, `[ATTN] Installation du paquet de données de la source winget (… signature « CN=Microsoft Corporation » vérifiée …)`, puis `[OK] Source winget réparée par l'installation de son paquet de données` et `[OK] Source winget accessible`. Aucune commande tapée.
- [ ] Test d'un logiciel winget dans l'onglet Réglages : réussi.
- [ ] `Get-AppxPackage -Name Microsoft.Winget.Source` : présent ; `%ProgramData%\FastPrepare\cache\winget-source` ne contient plus `source.msix`.
- [ ] Sans réseau au démarrage : message « malgré la mise à jour des sources (installation de son paquet de données : …) », aucune erreur bloquante.

## Itération 12 — portée d'installation winget

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] Onglet Réglages, nouveau logiciel winget : portée « Pour tous les utilisateurs (machine) » proposée par défaut ; la commande affichée contient `--scope machine`.
- [ ] Tester Visual Studio Code en « machine » : « Installateur pour tous les utilisateurs (machine) : VSCodeSetup-x64-… » ; en « user » : `VSCodeUserSetup-x64-…`.
- [ ] Tester Adobe Acrobat Reader en « user » : échec « winget ne propose aucun installateur … choisissez une autre portée ».
- [ ] Entrée sans portée (« Choix de winget ») : test réussi avec l'avertissement « Portée non précisée ».
- [ ] Exécution réelle sur poste de test, outil lancé avec un compte administrateur différent de l'utilisateur final : Visual Studio Code (« machine ») installé dans `C:\Program Files\Microsoft VS Code` et visible depuis la session de l'utilisateur final.

## Itération 13 — outil indépendant du support, installations unifiées

Poste : ____________________ · Constructeur : ____________ · Date : __________ · Version (titre de la fenêtre) : __________

### Lancement, quel que soit le support
- [ ] Titre de la fenêtre : « FastPrepare 1.13.0 — Préparation de poste » ; première ligne du journal : version et dossier de l'outil.
- [ ] Dossier **téléchargé** (archive `FastPrepare-1.13.0.zip` extraite dans `Téléchargements`) : `Lancer.cmd` demande l'élévation, la fenêtre s'ouvre.
- [ ] `Lancer.cmd` double-cliqué **dans l'archive non extraite** : message « Preparation.ps1 est introuvable… extrayez-la entièrement », rien d'autre.
- [ ] Dossier dont le chemin contient une apostrophe, des espaces et des parenthèses (ex. `C:\Outils\l'essai (1)\FastPrepare`) : la fenêtre s'ouvre.
- [ ] Depuis un **partage réseau** ouvert par son chemin `\\serveur\partage\FastPrepare` : la fenêtre s'ouvre.
- [ ] Depuis un **lecteur réseau mappé** (`Z:\FastPrepare`) : la fenêtre s'ouvre (le lecteur n'existe pas dans la session élevée : le lanceur passe par le chemin réseau).
- [ ] Depuis un **support amovible** : la fenêtre s'ouvre ; journal dans `logs\` sur le support.
- [ ] `config.json` d'une version précédente (`ConfigVersion` 3) : refus au démarrage avec la consigne de migration (`Output`, `Execution.WorkFolder`, `Utilities`).

### Dossier de sortie
- [ ] `Output.Folder` = `"logs"` : journal et inventaire dans `logs\` du dossier de l'outil.
- [ ] `Output.Folder` = chemin absolu (`D:\Preparations`) : journal et inventaire à cet endroit, rien dans le dossier de l'outil.
- [ ] `Output.Folder` = partage réseau accessible : journal et inventaire sur le partage.
- [ ] Partage **injoignable** au démarrage : ligne `[ATTN] Dossier de sortie … non accessible en écriture : journal et inventaire écrits dans C:\ProgramData\FastPrepare\sortie` ; partage rétabli avant la fin : ligne « copiés dans le dossier de sortie » ; resté injoignable : consigne « copiez-les à la main » avec le chemin.
- [ ] Dossier de l'outil en **lecture seule** et `Output.Folder` = `"logs"` : même repli ; l'onglet Réglages refuse d'enregistrer avec « le dossier … est protégé en écriture ».

### Section Installations — outil du constructeur détecté
- [ ] Poste **Dell** : « Constructeur détecté : Dell Inc. — outil proposé : Dell Command Update » ; seule cette case constructeur est affichée, cochée ; aucune case HP, Lenovo, Fujitsu.
- [ ] Poste **HP** : HP Image Assistant seulement. Poste **Lenovo** : Commercial Vantage et Thin Installer. Poste **Fujitsu** : DeskUpdate.
- [ ] **Machine virtuelle** ou constructeur inconnu : « aucun outil constructeur au catalogue pour cette marque » ; les logiciels sans constructeur restent proposés.
- [ ] Les neuf sections sont numérotées 1 à 9 dans l'ordre du README ; Office est dans la section 5, sous le catalogue.
- [ ] Section 7 : « Mettre à jour les pilotes et le BIOS (Dell Command Update) » visible et cochée ; outil constructeur décoché en section 5 → la case disparaît ; recoché → elle revient, cochée.
- [ ] Onglet Réglages : **toutes** les entrées du catalogue, quel que soit le poste, avec « constructeur : … » ; entrée Dell : ligne « Conservés tels quels… dépendance .NET… mise à jour des pilotes ».
- [ ] Onglet Réglages : nouveau logiciel avec « Constructeur » = marque du poste → la case apparaît en section 5 ; avec une autre marque → elle n'apparaît pas ; motif invalide (`HP(`) → Enregistrer grisé.
- [ ] Modifier le libellé de l'entrée Dell et enregistrer : `software.json` garde ses blocs `DotNet` et `Update`.

### Exécution
- [ ] Simulation, outil constructeur + un logiciel + Office cochés : les trois sous `[ETAPE 06/12]`, dans l'ordre catalogue puis Office ; `[ETAPE 09/12] Pilotes et BIOS (…)` ; `[ETAPE 10/12] Windows Update`.
- [ ] Réel (poste de test de chaque marque) : outil du constructeur installé, puis mise à jour des pilotes et du BIOS lancée par lui ; aucun redémarrage automatique.
- [ ] Réel, poste **Lenovo** : Thin Installer installé par winget (`Lenovo.ThinInstaller`), présent dans `C:\Program Files (x86)\Lenovo\ThinInstaller`, puis mise à jour lancée. *À confirmer : chemin d'installation du paquet winget.*
- [ ] Réel, exécution sans échec : en fin de rapport « Fichiers de travail supprimés » ; `C:\ProgramData\FastPrepare\cache` et `…\odt` n'existent plus ; pas de `C:\ODT`.
- [ ] Réel, une installation en échec (ex. identifiant winget faux ajouté pour l'essai) : « Fichiers de travail conservés pour le diagnostic » ; les dossiers existent encore.

### Livraison
- [ ] `tools\Build-Release.ps1 -Destination D:\Livraisons -Zip` : dossier `FastPrepare-1.13.0` (ni tests, ni documentation), `BUILD.txt` (version, commit, empreinte), archive `FastPrepare-1.13.0.zip` sans aucun fichier `.log`.
- [ ] Relancé sur le même dossier après un ajout au catalogue depuis l'onglet Réglages : catalogue conservé (message) ; avec `-ReplaceSoftwareCatalog` : remplacé.

## Recette complète avant passage en mode réel par défaut (DEC6)

Dérouler, sur un poste de test réinitialisé de **chaque marque**, une exécution réelle **complète** (toutes les sections utiles cochées), puis :

- [ ] Rapport final sans échec inattendu ; échecs attendus compris et documentés.
- [ ] Après redémarrage manuel : nom d'hôte appliqué, Office installé et non activé, outil du constructeur présent, aucune application Microsoft retirée ne revient pour un nouveau profil ; aucun fichier de l'outil hors du dossier de sortie.
- [ ] Deuxième exécution sur le même poste : tout est « déjà fait / déjà absent », aucune erreur.
- [ ] Valeurs provisoires confirmées ou corrigées dans `software.json` (blocs `Update`) : codes de sortie des outils constructeurs (QO4), chemins `HPImageAssistant.exe` / `ducmd.exe` / `ThinInstaller.exe`.
- [ ] Alors seulement : `Execution.DefaultMode` = `"Real"` dans `config.json`.
