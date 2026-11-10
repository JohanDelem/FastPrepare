# FastPrepare — Plan d'architecture cible de l'outil de préparation de poste

- **Version** : 0.3 — itérations 0 et 1 livrées, itérations 2 à 7 à venir
- **Date** : 2026-11-10
- **Portée** : tout le dépôt (`Lancer.cmd`, `Preparation.ps1`, `config.json`, `logos/`, `logs/`)
- **Sources** : [`Preparation.ps1`](../Preparation.ps1) (état « Étape 1 : interface + détections, bouton Lancer en simulation ») · [`config.json`](../config.json) · [`Lancer.cmd`](../Lancer.cmd) · `Cahier_des_charges__Outil_de_preparation_de_poste.pdf` (9 novembre 2026, maquette validée le 10 novembre 2026) · journaux d'exécution réels dans `logs/`

> Ce document est une **vue d'ensemble** : fichiers, responsabilités, noms des fonctions et ce qu'elles font. Il ne contient volontairement **aucun code**. Il décrit une **cible** : l'outil actuel tient dans un seul script de 1017 lignes écrit d'un trait, il doit devenir un ensemble de modules PowerShell à responsabilité unique, testables, et où l'ajout d'une étape, d'une marque ou d'un logiciel se fait sans toucher au reste. Les §2 et §3 décrivent l'existant et ses écarts ; les §4 à §8 la cible ; le §9 l'ordre de livraison ; le §10 les recettes d'extension ; le §11 les décisions.

---

## Sommaire

1. [Principes directeurs](#1-principes-directeurs)
2. [État des lieux de l'existant](#2-état-des-lieux-de-lexistant)
3. [Écarts au cahier des charges et évolution de `config.json`](#3-écarts-au-cahier-des-charges-et-évolution-de-configjson)
4. [Arborescence cible](#4-arborescence-cible)
5. [Détail par fichier](#5-détail-par-fichier)
6. [Où vit chaque règle (source unique)](#6-où-vit-chaque-règle-source-unique)
7. [Sécurité et robustesse](#7-sécurité-et-robustesse)
8. [Journal — contrat de traçabilité](#8-journal--contrat-de-traçabilité)
9. [Ordre de développement — itérations](#9-ordre-de-développement--itérations)
10. [Recettes d'extension — ajouter une fonctionnalité](#10-recettes-dextension--ajouter-une-fonctionnalité)
11. [Décisions](#11-décisions)

---

## 1. Principes directeurs

| Principe | Traduction concrète dans cet outil |
|---|---|
| **KISS** | Uniquement des composants fournis avec Windows 11 (contrainte du cahier) : Windows PowerShell 5.1, WPF, BITS, winget. **Aucun module tiers à l'exécution** sur la clé. Quatre modules PowerShell (`.psm1`) par couche, pas plus. Pas de classes PowerShell (§11, DEC1) : des objets `[pscustomobject]` nommés par `PSTypeName` et fabriqués par une fonction `New-*`. Pas de bus d'événements : une file de messages unique entre le moteur et la fenêtre. |
| **Une responsabilité par fichier** | Un fichier = une règle métier, un adaptateur système, une étape d'exécution ou une section d'interface. Aucun fichier ne mélange XAML, accès système et règle de gestion (c'est exactement le défaut de `Preparation.ps1`). Un fichier dépassant ~250 lignes est un signal de découpage. |
| **DRY** | Chaque règle (nom d'hôte, stratégie de désinstallation, comptes protégés, XML ODT, ordre d'exécution, correspondance DCU → .NET…) a **un seul** fichier propriétaire (§6). La simulation et l'exécution réelle passent **par le même plan** : la simulation n'est pas une deuxième implémentation qui décrit ce que ferait la première. |
| **Données hors du code** | Règle du cahier : « Liens : jamais dans le code. Une version qui change = une ligne à modifier dans `config.json` ». Étendue : marques, éditions Office, logiciels de la section 8, motifs de détection du constructeur, rappels manuels et durées d'alimentation sont des **données** de `config.json`. Les cards de l'interface sont **générées** depuis la configuration, plus écrites en dur dans le XAML. |
| **Indépendant de l'organisation** | L'outil s'applique à n'importe quel parc : aucun nom de client, de domaine, de tenant, de préfixe de nom d'hôte ni de choix propre à une organisation dans le code, l'interface ou les noms de fichiers. Tout ce qui varie d'un parc à l'autre (marques, éditions et licences Office, logiciels, durées d'alimentation, rappels manuels) est une donnée de `config.json` ; adapter l'outil à un nouveau parc = livrer un autre `config.json`, jamais modifier `src/`. `Architecture.Tests` le contrôle (aucune URL ni nom d'organisation dans `src/`). |
| **Cœur pur, bords impurs** | Les décisions (nom d'hôte valide, commande de désinstallation silencieuse, XML ODT, runtime .NET requis, présélection de la marque, ordre des actions) sont des **fonctions pures** de `FastPrepare.Core` : aucune lecture de registre, de WMI, de fichier ni de contrôle WPF. Elles se testent avec Pester sur n'importe quel poste, y compris sans droits administrateur. Les accès au système vivent dans `FastPrepare.Infrastructure`, derrière des fonctions fines que les tests remplacent par des `Mock`. |
| **Sécurisé par défaut** | Mode **simulation par défaut** tant que le moteur réel n'est pas recetté (§11, DEC6). Aucun `Invoke-Expression`. Un processus externe se lance par un point de passage unique, avec chemin d'exécutable et arguments séparés. Tout exécutable téléchargé est vérifié (signature Authenticode, empreinte si connue) avant d'être lancé. Toute suppression de dossier passe une garde de chemin. Jamais de redémarrage automatique (cahier). |
| **Fenêtre toujours réactive** | Exigence du cahier. Le thread de l'interface ne fait **que** de l'affichage. Détections, téléchargements anticipés et exécution du plan tournent dans un *runspace* d'arrière-plan ; ils publient leurs messages dans une file que la fenêtre vide sur un minuteur. |
| **Échec isolé** | Exigence validée du cahier : « Si une étape échoue, l'outil la note en rouge dans le journal et passe à la suivante. » Le moteur capture l'erreur **d'une action**, la journalise et continue ; une étape n'arrête jamais l'exécution des suivantes. Le rapport final récapitule réussites, échecs et actions manuelles. |
| **Observable par le journal** | Le journal est la seule trace laissée au technicien et au support (le poste est ensuite redémarré). Chaque action journalise son début, sa commande effective, son code de sortie et sa durée (§8). |

**Compatibilité** : cible unique Windows 11, Windows PowerShell **5.1** (pas PowerShell 7 : absent d'une installation neuve). Tout le code doit rester compatible 5.1 : pas d'opérateur ternaire, pas de `??`, pas de `ForEach-Object -Parallel`, pas de `Test-Json`.

**Encodage** : tous les `.ps1`, `.psm1`, `.psd1` sont enregistrés en **UTF-8 avec BOM** (sans BOM, PowerShell 5.1 lit le fichier en ANSI et casse les accents des messages ; l'existant respecte déjà cette règle). Les `.cmd` sont en **CRLF** (un `.cmd` en LF peut mal interpréter les étiquettes et les blocs). `.editorconfig` et `.gitattributes` portent ces deux règles ; l'outil de lint les vérifie (§5.9).

**Conventions** : verbes PowerShell approuvés (`Get-Verb`), noms de fonctions au singulier, paramètres nommés explicites, messages utilisateur en français, identifiants de code en anglais. Un test Pester `*.Tests.ps1` par fichier de `Core` et par étape, sous `tests/` en miroir de `src/`.

---

## 2. État des lieux de l'existant

### 2.1 Ce qui est solide et conservé (sur le fond, déplacé sur la forme)

| Élément | Emplacement actuel | Pourquoi on le garde |
|---|---|---|
| Lanceur avec élévation | `Lancer.cmd` | Conforme au cahier : demande les droits administrateur, contourne la politique d'exécution pour le seul processus, force `-STA` requis par WPF. |
| Vérification des droits au démarrage | `Preparation.ps1:16-21` | Échec immédiat et lisible si l'outil est lancé sans élévation. |
| Repli du journal sur `%TEMP%` si la clé est en lecture seule | `Preparation.ps1:32-42` | Bon réflexe ; il manque seulement la mention de ce repli dans le rapport final (§3, E7). |
| Détection de la stratégie de désinstallation | `Get-UninstallPlan`, `Preparation.ps1:484-515` | Couvre exactement le tableau du cahier (QuietUninstallString, MSI par GUID, Inno Setup `unins000.exe`, NSIS par signature « Nullsoft », sinon assistant). Devient une fonction pure de `Core` (la lecture du fichier exécutable reste dans `Infrastructure`). |
| Filtre des logiciels « comme le Panneau de configuration » | `Get-InstalledSoftware`, `:517-543` | Les bons critères (`SystemComponent`, `ParentKeyName`, `ReleaseType`, dédoublonnage nom + version, trois ruches). |
| Comptes exclus d'office | `Get-RemovableLocalUsers`, `:545-564` | RID 500, 501, 503, 504 et compte connecté : correspond mot pour mot au cahier. Repli `Win32_UserAccount` si `Get-LocalUser` est indisponible. |
| Validation du nom d'hôte | `Test-HostName`, `:748-751` | 15 caractères, lettres, chiffres, tiret, pas uniquement des chiffres, pas de tiret en début ou fin. |
| Génération du XML ODT | `Get-OfficePlan`, `:791-814` | Contenu juste (64 bits, `MatchOS`, `ExcludeApp`, aucune ligne Teams, aucune clé). Seul le couplage à l'interface pose problème (D5). |
| Test de connexion non bloquant | `:969-992` | `HttpClient.GetStringAsync` sondé par un `DispatcherTimer` : n'immobilise pas la fenêtre. Le principe est conservé, encapsulé (§5.7). |
| Charte visuelle | XAML `:47-418` | Maquette validée le 10/11/2026 : styles `Section`, `H2`, `Card`, `Pill`, `Primary`, pastilles de couleur. Conservée à l'identique, extraite dans des fichiers XAML. |
| Format du journal et de l'inventaire | `Write-Log`, `:438-460` ; `:686-708` | `HH:mm:ss [NIVEAU] message`, niveaux `INFO/OK/ERREUR/ATTN/SIMU`, fichiers `Journal_<hôte>_<horodatage>.log` et `Inventaire_<N/S>_<horodatage>.txt`. Le format est un contrat (§8). |

### 2.2 Dette à résorber dès l'itération 0

| # | Constat | Emplacement | Correction cible |
|---|---|---|---|
| D1 | **Monolithe** : XAML (370 lignes), détections, règles d'interface, simulation et gestionnaires d'événements dans un seul fichier. Toute évolution touche ce fichier ; aucune partie ne se teste isolément. | `Preparation.ps1` | Découpage en quatre modules (`Core`, `Infrastructure`, `Application`, `UI`) et fichiers XAML séparés (§4). `Preparation.ps1` ne garde que l'ordre de démarrage. |
| D2 | **La simulation est une seconde implémentation** : `Invoke-Simulation` réécrit, sous forme de chaînes, ce que devrait faire le moteur ; l'ordre d'exécution du cahier est codé en dur dans des numéros de message (« 3. », « 5. »…). Le moteur réel devra tout réécrire et les deux divergeront. | `Invoke-Simulation`, `:847-910` | Un **plan d'exécution** unique (liste ordonnée d'actions) construit par les étapes ; le moteur l'exécute en mode `Simulation` (journalise chaque action) ou `Real` (l'exécute). L'ordre vit dans un seul fichier, `StepOrder.ps1`. |
| D3 | **Ajouter une marque = quatre endroits** : ToggleButton en dur dans le XAML, tableau des logos `@('dell','ImgDell')…`, `switch -Regex` de présélection, entrée de `config.json`. | `:299-326`, `:711-724`, `:727-732` | Cards **générées** depuis `config.Utilities` (libellé, sous-titre, logo, motif de constructeur). Ajouter une marque = un bloc dans `config.json` + un logo (§10.2). |
| D4 | **Éditions Office en dur dans le script** (`ProductId`, `Channel`) alors que ce sont des données qui évoluent avec les licences Microsoft ; même chose pour les quatre cards Office du XAML. | `$script:OfficeEditions`, `:741-746` ; XAML `:336-347` | `config.Office.Editions` ; cards générées (§3, C5). |
| D5 | **Règle métier couplée aux contrôles WPF** : `Get-OfficePlan` lit directement `$UI.PillNoTeams.IsChecked` et les cases d'inclusion ; `Update-LaunchState` lit `$UI.ChkHost`. Rien n'est testable sans fenêtre. | `:791-814`, `:753-760` | L'interface produit un objet **Selection** (données pures) ; `Core` en déduit le XML (`New-OdtInstallXml`) et `Application` le plan. |
| D6 | **État global diffus** : une quinzaine de variables `$script:` (`NetOk`, `NetKnown`, `Manufacturer`, `Serial`, `Adapters`, `InventoryText`, `OneDriveFolder`, `AppChecks`…) lues et écrites partout. | tout le fichier | Un objet **Context** (configuration, chemins, mode, journal) et un objet **MachineSnapshot** (résultat des détections) passés explicitement en paramètre. L'état propre à l'interface reste dans le module `UI`. |
| D7 | **Détections sur le thread de l'interface** : lecture complète (jusqu'à 10 Mo) de chaque désinstalleur pour y chercher « Nullsoft », comptage récursif du dossier OneDrive, requêtes WMI. La fenêtre gèle au démarrage et gèlera pendant les installations. Contraire au cahier (« Fenêtre réactive »). | `Test-NsisUninstaller` `:474-482`, `:680`, `Initialize-Detections` | Détections et exécution dans un runspace d'arrière-plan (`BackgroundRunner`) ; la signature NSIS est cherchée dans les 512 premiers Ko seulement (la chaîne figure dans l'en-tête de l'archive). |
| D8 | **Le journal dépend de la fenêtre** : `Write-Log` écrit dans `$UI.RtbLog`. Inutilisable avant la création de la fenêtre et depuis un runspace (le moteur réel ne pourrait pas journaliser). | `Write-Log`, `:438-460` | `Logging` dans `Infrastructure` : écriture fichier + publication dans une file thread-safe ; la vue du journal (`LogView`) vide la file côté interface. |
| D9 | **Commandes constructeur en chaînes shell** : `"%ProgramFiles%\Dell\…\dcu-cli.exe" /applyUpdates -reboot=disable` mêle chemin, variables d'environnement et arguments ; l'exécuter demanderait `cmd /c` ou `Invoke-Expression`. | `config.json` `UpdateCommand` | Configuration structurée `FilePath` + `Arguments` (§3, C3) ; lancement par `Invoke-ExternalProcess` uniquement. |
| D10 | **Erreurs avalées** : `catch { }` sur l'écriture du journal et le chargement des logos ; `$ErrorActionPreference = 'Continue'` global. Un échec silencieux est impossible à diagnostiquer après redémarrage. | `:11`, `:444`, `:722` | `$ErrorActionPreference = 'Stop'` dans chaque module, erreurs capturées **au niveau de l'action** par le moteur et journalisées ; échec d'écriture du journal fichier signalé une fois dans la fenêtre. |
| D11 | **Constantes magiques** : délai de 5 s codé en dur après une erreur de test réseau (alors que l'intervalle est en configuration), délai HTTP de 4 s, plage de RID exclus, largeurs de colonnes. | `:990`, `:970`, `:560` | Délais dans `config.Connectivity` ; RID protégés dans `Core/LocalAccountPolicy.ps1` (règle unique). |
| D12 | **Rappels manuels écrits deux fois**, avec des listes différentes : le mémo de la fenêtre et le message final du journal. | XAML `:410-411`, `:909` | `config.ManualReminders`, lu par le mémo et par le rapport final. |
| D13 | **Mode simulation codé en dur** (`$script:Simulation = $true`), sans moyen de le changer sans éditer le script. | `:9` | Mode porté par le `Context`, issu de `config.Execution.DefaultMode` et surchargé par `Lancer.cmd -Real` (§5.1). |
| D14 | **Ni tests, ni analyse statique, ni procédure de livraison sur clé** : la clé reçoit ce qu'il y a dans le dossier, journaux de test compris. | — | `tests/` (Pester 5, poste de développement uniquement), `tools/Invoke-Lint.ps1` (PSScriptAnalyzer), `tools/Build-Usb.ps1` (copie du seul nécessaire). |
| D15 | **Lanceur dépendant du `PATH`** : `powershell.exe` est résolu par le `PATH` ; aucun argument n'est transmis au script. | `Lancer.cmd` | Chemin absolu `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` ; arguments transmis (`%*`). |

---

## 3. Écarts au cahier des charges et évolution de `config.json`

### 3.1 Écarts fonctionnels

L'existant est volontairement une « étape 1 ». La confrontation au cahier fait apparaître les écarts suivants ; chacun a son itération au §9.

| # | Exigence du cahier | État actuel | Cible |
|---|---|---|---|
| E1 | Moteur d'exécution des 14 étapes. | Simulation textuelle uniquement. | Étapes réelles derrière le même plan (it. 3 à 7). |
| E2 | Winget « vérifié au démarrage, réenregistré si absent (`Add-AppxPackage -RegisterByFamilyName`), sinon installé depuis un paquet `.msixbundle` sur la clé ». | Seulement détecté et journalisé. | `Infrastructure/System/Winget.ps1` : `Assert-Winget` (détection → réenregistrement → paquet hors ligne `packages/`). |
| E3 | Utilitaire constructeur : « Téléchargement lancé dès le clic, dépendances comprises ». | Message « téléchargement anticipé simulé ». | `Application/Prefetch.ps1` : téléchargement en arrière-plan dans le cache, réutilisé par l'étape 06. |
| E4 | « Fenêtre réactive. » | Détections synchrones (D7). | Runspace d'arrière-plan (it. 1). |
| E5 | Dell : runtime .NET **par plage** (« 8.0.8 à 8.0.25 pour la 5.7.0, 10.0.8 ou plus pour la 5.7.1 »). | `config.json` ne porte qu'une `Version` exacte, vide pour la 5.7.1. | `MinVersion` / `MaxVersion` par entrée (C4) ; choix par `Core/DotNetRequirement.ps1`. |
| E6 | Lenovo : **deux** outils — Commercial Vantage (msstore, pour le technicien) **et** Thin Installer (lien direct, MàJ automatique). | Un seul `WingetId` ; `ThinInstallerUrl` vide. | Liste `Install` d'éléments typés (`winget` ou `download`) par marque (C2). |
| E7 | « Journal : affiché en direct dans la fenêtre et copié sur la clé. » | Écrit directement sur la clé, ou dans `%TEMP%` si elle est en lecture seule, sans le dire à la fin. | Rapport final : emplacement du journal ; si repli sur `%TEMP%`, tentative de copie sur la clé en fin d'exécution et avertissement `ATTN`. |
| E8 | Adobe Reader : options silencieuses `-sfx_nu /sAll /rs /msi`. | Absentes. | `Override` dans l'entrée du catalogue logiciel (C6). |
| E9 | Point en attente : alimentation sur secteur **et** batterie, ou secteur seulement ? | Les deux, en dur dans le libellé. | Booléen `Power.ApplyOnBattery` (C7) ; libellé de la case calculé. Décision au §11, DEC9. |
| E10 | « Les téléchargements et installations tournent en arrière-plan. » | Sans objet (rien n'est exécuté). | Le plan entier s'exécute dans le runspace ; la fenêtre affiche la progression (« étape 5/13 »). |

### 3.2 Évolutions de `config.json` (version 2)

Le fichier reste **unique et à la racine** (contrat du cahier, et le technicien sait où le trouver). Il gagne un numéro de version vérifié au démarrage : une configuration d'un autre format est refusée avec un message qui dit quoi corriger, plutôt que d'échouer au milieu d'une exécution.

| # | Changement | Raison |
|---|---|---|
| C1 | `ConfigVersion: 2` en tête ; regroupement de `InternetTest*` sous `Connectivity` (`TestUrl`, `Expected`, `IntervalSeconds`, `TimeoutSeconds`, `RetrySeconds`). | Validation au démarrage (`Assert-AppConfig`) ; fin des constantes magiques (D11). |
| C2 | `Utilities.<clé>` : ajout de `Label`, `Subtitle`, `Logo`, `ManufacturerPattern` (expression régulière sur `Win32_ComputerSystem.Manufacturer`) ; `WingetId`/`WingetSource`/`ThinInstallerUrl` remplacés par une liste **`Install`** d'éléments `{ Type: "winget", Id, Source }` ou `{ Type: "download", Url, Sha256, FileName, Arguments, ExpectedSigner }`. | Cards générées (D3) ; Lenovo à deux outils (E6) ; un téléchargement direct est vérifié avant d'être lancé (§7). |
| C3 | `UpdateCommand` (chaîne) remplacé par **`Update`** `{ FilePath, Arguments, SuccessExitCodes }`. `FilePath` accepte les variables `%ProgramFiles%`, `%ProgramFiles(x86)%`, `%OdtFolder%`, résolues par une fonction unique. | Plus de chaîne shell (D9) ; codes de sortie « succès avec redémarrage requis » propres à chaque outil (DCU renvoie 1 ou 5 selon les cas). |
| C4 | `Utilities.dell.DotNet[]` : `{ DcuVersion, WingetId, MinVersion, MaxVersion }`. | Plages du cahier (E5). |
| C5 | `Office.Editions[]` : `{ Key, Label, ProductId, Channel, NoTeamsProductId? }` ; `Office.Architecture: "64"`, `Office.Language: "MatchOS"`, `Office.OptionalApps[]` : `{ Id: "OutlookForWindows", Label: "Nouvel Outlook" }`, `{ Id: "Outlook", … }`, `{ Id: "OneDrive", … }`. | D4 ; une édition avec choix Teams se reconnaît à la présence de `NoTeamsProductId` (la pastille Avec / Sans Teams n'est affichée que pour elle). |
| C6 | `Adobe` remplacé par un catalogue **`Software[]`** : `{ Id, Label, WingetId, Source, Override, DefaultChecked }`. | Section 8 générée : ajouter un logiciel = une entrée (§10.3). |
| C7 | `Power.ApplyOnBattery` (booléen). | E9. |
| C8 | `ManualReminders[]` (liste de libellés). | D12. |
| C9 | `Execution` : `DefaultMode` (`"Simulation"` ou `"Real"`), `CacheFolder` (`%ProgramData%\FastPrepare\cache`). `Winget` : `FamilyName`, `OfflineBundle` (chemin relatif à la racine de la clé). `Logging` : `Folder` (`logs`). | D13, E2, E3. |

**Ce qui reste hors configuration** : les règles elles-mêmes (comptes protégés, format du nom d'hôte, stratégies de désinstallation, ordre d'exécution). Elles viennent du cahier, pas de l'exploitation ; les rendre configurables multiplierait les cas à tester sans besoin exprimé.

---

## 4. Arborescence cible

Légende : ✅ existant conservé · ♻️ existant à modifier · 🆕 à créer · 🚚 déplacé · 🗑️ à supprimer.
Chaque fichier de `Core` et chaque étape a son `*.Tests.ps1` dans `tests/`, en miroir ; ils ne sont pas répétés dans l'arbre.

```text
📦FastPrepare
 ┣ 📂docs 🆕
 ┃ ┣ 📜architecture_plan.md 🆕 (ce document)
 ┃ ┣ 📜CONTRIBUTING.md 🆕
 ┃ ┣ 📜recette.md 🆕
 ┃ ┗ 📜Cahier_des_charges__Outil_de_preparation_de_poste.pdf (local, non versionné : *.pdf ignoré par Git)
 ┣ 📂src 🆕
 ┃ ┣ 📂FastPrepare.Core                      (pur : ni système, ni WPF)
 ┃ ┃ ┣ 📂Public
 ┃ ┃ ┃ ┣ 📜CommandLine.ps1
 ┃ ┃ ┃ ┣ 📜DotNetRequirement.ps1
 ┃ ┃ ┃ ┣ 📜HostName.ps1
 ┃ ┃ ┃ ┣ 📜Inventory.ps1
 ┃ ┃ ┃ ┣ 📜LocalAccountPolicy.ps1
 ┃ ┃ ┃ ┣ 📜ManufacturerMatch.ps1
 ┃ ┃ ┃ ┣ 📜OdtConfiguration.ps1
 ┃ ┃ ┃ ┣ 📜PathGuard.ps1
 ┃ ┃ ┃ ┣ 📜Selection.ps1
 ┃ ┃ ┃ ┗ 📜UninstallStrategy.ps1
 ┃ ┃ ┣ 📜FastPrepare.Core.psd1
 ┃ ┃ ┗ 📜FastPrepare.Core.psm1
 ┃ ┣ 📂FastPrepare.Infrastructure            (adaptateurs Windows)
 ┃ ┃ ┣ 📂Config
 ┃ ┃ ┃ ┗ 📜AppConfig.ps1
 ┃ ┃ ┣ 📂Logging
 ┃ ┃ ┃ ┗ 📜RunLog.ps1
 ┃ ┃ ┣ 📂Runtime
 ┃ ┃ ┃ ┣ 📜BackgroundRunner.ps1
 ┃ ┃ ┃ ┗ 📜Privilege.ps1
 ┃ ┃ ┣ 📂System
 ┃ ┃ ┃ ┣ 📜Appx.ps1
 ┃ ┃ ┃ ┣ 📜Download.ps1
 ┃ ┃ ┃ ┣ 📜Hardware.ps1
 ┃ ┃ ┃ ┣ 📜InstalledSoftware.ps1
 ┃ ┃ ┃ ┣ 📜LocalAccounts.ps1
 ┃ ┃ ┃ ┣ 📜Network.ps1
 ┃ ┃ ┃ ┣ 📜Odt.ps1
 ┃ ┃ ┃ ┣ 📜OneDrive.ps1
 ┃ ┃ ┃ ┣ 📜Power.ps1
 ┃ ┃ ┃ ┣ 📜Process.ps1
 ┃ ┃ ┃ ┣ 📜Winget.ps1
 ┃ ┃ ┃ ┗ 📜WindowsUpdate.ps1
 ┃ ┃ ┣ 📜FastPrepare.Infrastructure.psd1
 ┃ ┃ ┗ 📜FastPrepare.Infrastructure.psm1
 ┃ ┣ 📂FastPrepare.Application               (cas d'usage : détections, plan, moteur)
 ┃ ┃ ┣ 📂Steps
 ┃ ┃ ┃ ┣ 📜ExportInventory.step.ps1
 ┃ ┃ ┃ ┣ 📜RemoveLocalAccounts.step.ps1
 ┃ ┃ ┃ ┣ 📜RemoveMicrosoftApps.step.ps1
 ┃ ┃ ┃ ┣ 📜RemoveOneDrive.step.ps1
 ┃ ┃ ┃ ┣ 📜UninstallSoftware.step.ps1
 ┃ ┃ ┃ ┣ 📜InstallVendorUtility.step.ps1
 ┃ ┃ ┃ ┣ 📜InstallOffice.step.ps1
 ┃ ┃ ┃ ┣ 📜InstallSoftware.step.ps1
 ┃ ┃ ┃ ┣ 📜DisableIpv6.step.ps1
 ┃ ┃ ┃ ┣ 📜SetPowerPlan.step.ps1
 ┃ ┃ ┃ ┣ 📜UpdateVendorUtility.step.ps1
 ┃ ┃ ┃ ┣ 📜RunWindowsUpdate.step.ps1
 ┃ ┃ ┃ ┗ 📜RenameComputer.step.ps1
 ┃ ┃ ┣ 📜AppContext.ps1
 ┃ ┃ ┣ 📜ExecutionEngine.ps1
 ┃ ┃ ┣ 📜ExecutionPlan.ps1
 ┃ ┃ ┣ 📜FinalReport.ps1
 ┃ ┃ ┣ 📜InventoryExport.ps1 (repris par ExportInventory.step à l'it. 2)
 ┃ ┃ ┣ 📜MachineSnapshot.ps1
 ┃ ┃ ┣ 📜Prefetch.ps1
 ┃ ┃ ┣ 📜SelectionSimulation.ps1 🗑️ (transitoire, supprimé à l'it. 2)
 ┃ ┃ ┣ 📜StepOrder.ps1
 ┃ ┃ ┣ 📜StepRegistry.ps1
 ┃ ┃ ┣ 📜FastPrepare.Application.psd1
 ┃ ┃ ┗ 📜FastPrepare.Application.psm1
 ┃ ┗ 📂FastPrepare.UI                        (WPF uniquement)
 ┃ ┃ ┣ 📂Sections
 ┃ ┃ ┃ ┣ 📜ConnectivitySection.ps1          (0)
 ┃ ┃ ┃ ┣ 📜HostNameSection.ps1              (1)
 ┃ ┃ ┃ ┣ 📜InstalledSoftwareSection.ps1     (2)
 ┃ ┃ ┃ ┣ 📜MicrosoftAppsSection.ps1         (3)
 ┃ ┃ ┃ ┣ 📜LocalAccountsSection.ps1         (4)
 ┃ ┃ ┃ ┣ 📜VendorUtilitySection.ps1         (5)
 ┃ ┃ ┃ ┣ 📜OfficeSection.ps1                (6)
 ┃ ┃ ┃ ┣ 📜UpdatesSection.ps1               (7)
 ┃ ┃ ┃ ┣ 📜SoftwareSection.ps1              (8)
 ┃ ┃ ┃ ┣ 📜SystemSettingsSection.ps1        (9)
 ┃ ┃ ┃ ┗ 📜InventorySection.ps1             (10)
 ┃ ┃ ┣ 📂Xaml
 ┃ ┃ ┃ ┣ 📂Sections
 ┃ ┃ ┃ ┃ ┗ 📜<une par section>.xaml
 ┃ ┃ ┃ ┣ 📜MainWindow.xaml
 ┃ ┃ ┃ ┗ 📜Theme.xaml
 ┃ ┃ ┣ 📜Controls.ps1
 ┃ ┃ ┣ 📜LogView.ps1
 ┃ ┃ ┣ 📜MainWindow.ps1
 ┃ ┃ ┣ 📜SectionRegistry.ps1
 ┃ ┃ ┣ 📜UiPump.ps1
 ┃ ┃ ┣ 📜XamlLoader.ps1
 ┃ ┃ ┣ 📜FastPrepare.UI.psd1
 ┃ ┃ ┗ 📜FastPrepare.UI.psm1
 ┣ 📂tests 🆕
 ┃ ┣ 📂FastPrepare.Core
 ┃ ┣ 📂FastPrepare.Infrastructure
 ┃ ┣ 📂FastPrepare.Application
 ┃ ┣ 📂Fixtures
 ┃ ┃ ┣ 📜config.valid.json
 ┃ ┃ ┣ 📜registry-uninstall-entries.json
 ┃ ┃ ┗ 📜selection.full.json
 ┃ ┣ 📜Architecture.Tests.ps1
 ┃ ┗ 📜TestHelpers.ps1
 ┣ 📂tools 🆕
 ┃ ┣ 📜Build-Usb.ps1
 ┃ ┣ 📜Invoke-Lint.ps1
 ┃ ┣ 📜Invoke-Tests.ps1
 ┃ ┗ 📜PSScriptAnalyzerSettings.psd1
 ┣ 📂packages 🆕 (ignoré par Git — .msixbundle winget hors ligne)
 ┣ 📂logos ✅
 ┃ ┗ 📜LISEZMOI.txt ♻️
 ┣ 📂logs (ignoré par Git)
 ┣ 📜.editorconfig 🆕
 ┣ 📜.gitattributes 🆕
 ┣ 📜.gitignore 🆕
 ┣ 📜config.json ♻️ (version 2)
 ┣ 📜Lancer.cmd ♻️
 ┣ 📜Preparation.ps1 ♻️ (point d'entrée mince)
 ┗ 📜README.md 🆕
```

### 4.1 Graphe de dépendances des modules

Une flèche = « importe / appelle ». **Aucun cycle** ; une couche ne connaît jamais celle du dessus. Le test `tests/Architecture.Tests.ps1` le vérifie (§5.10).

```text
Preparation.ps1 ──► FastPrepare.UI ──► FastPrepare.Application ──► FastPrepare.Infrastructure
                                              │                              │
                                              └──────────► FastPrepare.Core ◄┘ (types et règles pures)

Runspace d'arrière-plan : Application + Infrastructure + Core   (jamais UI)
Thread de l'interface    : UI (+ Application pour construire le plan, lire le snapshot)
```

| Module | Peut appeler | Ne doit jamais |
|---|---|---|
| `Core` | rien | lire le registre, WMI, un fichier, le réseau, une variable `$script:` partagée, un type WPF |
| `Infrastructure` | `Core` | connaître une section d'interface, une étape, la `Selection` |
| `Application` | `Core`, `Infrastructure` | référencer un type WPF (`System.Windows.*`) |
| `UI` | `Application`, `Core` (validation instantanée du nom d'hôte) | appeler `Infrastructure/System/*` directement, lancer un processus, écrire un fichier |

### 4.2 Modèle d'exécution (fils et messages)

```text
┌──────────── Thread UI (STA) ─────────────┐        ┌──────── Runspace d'arrière-plan (MTA) ───────┐
│ MainWindow  ── Selection ──► ExecutionPlan│        │                                               │
│     │                          │          │ Start  │  Get-MachineSnapshot   (au démarrage)         │
│     │                          └──────────┼───────►│  Start-Prefetch        (clic sur une card)    │
│     │                                     │        │  Invoke-ExecutionPlan  (bouton Lancer)        │
│ UiPump (DispatcherTimer 200 ms) ◄─────────┼────────┤  Write-RunLog ─► file ConcurrentQueue          │
│   ├─ LogView.Add-LogLine                  │ file   │                └─► fichier journal (UTF-8)    │
│   ├─ progression « étape n / N »          │        │  résultat final ─► Get-BackgroundResult        │
│   └─ fin de tâche ► callback de section   │        │                                               │
└───────────────────────────────────────────┘        └───────────────────────────────────────────────┘
```

- **Un seul runspace d'exécution à la fois** pour le plan (deux exécutions concurrentes sont impossibles : le bouton Lancer est désactivé pendant l'exécution). Les détections et le téléchargement anticipé utilisent des runspaces distincts, courts, issus du même `BackgroundRunner`.
- Le runspace importe les trois modules non-UI **par chemin** depuis la racine de la clé ; il reçoit le `Context` (sans élément WPF) et la file de messages.
- La fermeture de la fenêtre pendant une exécution demande confirmation ; si elle est confirmée, le runspace est arrêté proprement après l'action en cours et le journal note l'interruption.

---

## 5. Détail par fichier

Format : **fichier** — responsabilité unique, puis ses fonctions publiques. Les fonctions privées utiles à la compréhension sont mentionnées. *Pur* = sans effet de bord, testable sans Windows particulier.

### 5.1 Démarrage

**`Lancer.cmd`** ♻️ — Obtient l'élévation et lance le point d'entrée ; aucune logique métier.
- Vérifie l'élévation (`net session`), sinon se relance par `Start-Process -Verb RunAs` en **transmettant les arguments** (`%*`).
- Lance `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Preparation.ps1" %*` : chemin absolu (pas de résolution par le `PATH`, et jamais `pwsh`).
- `pause` si le code de sortie est non nul, pour que le technicien lise l'erreur.
- Usage : `Lancer.cmd` (mode par défaut de la configuration) ou `Lancer.cmd -Real` / `Lancer.cmd -Simulation`.

**`Preparation.ps1`** ♻️ — Point d'entrée : ne contient que l'ordre de démarrage (~50 lignes).
- `param([switch]$Real, [switch]$Simulation)` — surcharge du mode ; les deux ensemble sont refusés.
- Séquence : `Assert-Administrator` → import des quatre modules par chemin relatif à `$PSScriptRoot` → `Read-AppConfig` → `New-AppContext` (crée le journal) → `Start-MainWindow -Context`. Toute exception non capturée est montrée dans une `MessageBox`, journalisée si le journal existe déjà, puis code de sortie 1.
- Aucune fonction n'y est définie.

**`README.md`** 🆕 — Pour le technicien : préparer la clé (`tools/Build-Usb.ps1`), lancer, lire le journal, modifier une version dans `config.json`. Pour le développeur : renvoi vers `docs/CONTRIBUTING.md` et ce plan.

**`docs/CONTRIBUTING.md`** 🆕 — Conventions du §1 (encodage, compatibilité 5.1, verbes, nommage), lancement des tests et du lint, procédure de revue (une règle touchée = son test mis à jour, cf. §6).

**`docs/recette.md`** 🆕 — Liste de contrôle manuelle sur poste réel, par marque (Dell, HP, Lenovo, Fujitsu) et par édition Office : ce que l'interface doit montrer, ce que le journal doit contenir, état attendu du poste après redémarrage. Seule preuve possible pour l'interface WPF et les effets système réels.

### 5.2 `FastPrepare.Core` — règles pures

**`FastPrepare.Core.psm1` / `.psd1`** 🆕 — Charge `Public/*.ps1` et exporte leurs fonctions ; `PowerShellVersion = '5.1'`, `FunctionsToExport` explicite (pas de `*`). Même modèle pour les trois autres modules.

**`Public/HostName.ps1`** 🆕 — Règle du nom d'hôte (cahier, section 1). *Pur.*
- `Test-HostName -Name` — vrai si 1 à 15 caractères, lettres ASCII, chiffres et tiret, ni tiret en début ni en fin, pas uniquement des chiffres. Reprise de l'existant.
- `Get-HostNameError -Name` — renvoie le motif lisible du refus (« 16 caractères sur 15 maximum », « uniquement des chiffres »…) ou `$null` ; affiché sous le champ au lieu du seul passage au rouge.

**`Public/UninstallStrategy.ps1`** 🆕 — Tableau « Désinstallation silencieuse » du cahier. *Pur* : reçoit l'entrée de registre **et** le résultat de la sonde de fichier, ne lit rien lui-même.
- `Resolve-UninstallStrategy -Entry -ExecutableProbe` — renvoie `{ Silent, Method, FilePath, Arguments, RawCommand }` selon l'ordre : `QuietUninstallString` → MSI (GUID de `PSChildName` ou de la chaîne) → `msiexec.exe /x {GUID} /qn /norestart` → Inno Setup (`unins###.exe`) → `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` → NSIS (`ExecutableProbe.IsNsis`) → `/S` → sinon assistant (`Silent = $false`).
- `Get-UninstallExecutable -UninstallString` — extrait le chemin de l'exécutable (guillemets ou premier `.exe`) ; utilisé par la sonde d'`Infrastructure` pour savoir quel fichier examiner.
- `Get-UninstallOrder -Software` — silencieux d'abord, assistants en dernier, ordre alphabétique stable dans chaque groupe (cahier, ordre d'exécution n° 5).

**`Public/CommandLine.ps1`** 🆕 — Découpe une ligne de commande Windows. *Pur.*
- `Split-CommandLine -CommandLine` — renvoie `{ FilePath, Arguments }` en respectant les guillemets ; échec explicite si la ligne n'est pas analysable (la ligne est alors exécutée par `cmd.exe /c`, journalisée comme telle — §11, DEC8).
- `Expand-ConfigPath -Path -Variables` — remplace `%ProgramFiles%`, `%ProgramFiles(x86)%`, `%OdtFolder%`, `%CacheFolder%` à partir d'une table fournie par l'appelant (pas de lecture de l'environnement ici).

**`Public/LocalAccountPolicy.ps1`** 🆕 — Comptes que l'outil ne supprime jamais (cahier, section 4). *Pur.*
- `Test-ProtectedAccount -Sid -CurrentSid` — vrai pour les RID 500 (Administrateur intégré), 501 (Invité), 503 (DefaultAccount), 504 (WDAGUtilityAccount) et pour le compte connecté.
- `Split-LocalAccount -Account -CurrentSid` — renvoie `{ Removable, Excluded }` ; `Excluded` porte le motif (« connecté », « intégré »).

**`Public/PathGuard.ps1`** 🆕 — Garde avant toute suppression récursive. *Pur.*
- `Test-SafeProfilePath -Path -ProfilesRoot -CurrentProfile` — vrai seulement si le chemin est **strictement sous** le dossier des profils (`C:\Users`), n'est ni ce dossier lui-même, ni `Default`, `Default User`, `Public`, `All Users`, ni le profil connecté. Utilisée pour les profils supprimés (section 4) et pour le dossier OneDrive (section 3).
- `Test-SafeChildPath -Path -Root` — vrai si le chemin normalisé reste sous la racine (pas de `..`) ; utilisée pour le cache et `C:\ODT`.

**`Public/OdtConfiguration.ps1`** 🆕 — Tout le XML ODT, installation et suppression. *Pur.*
- `Get-OfficeProductId -Edition -WithoutTeams` — `ProductId` ou `NoTeamsProductId` de l'édition ; erreur si « sans Teams » est demandé pour une édition qui ne le propose pas.
- `New-OdtInstallXml -Edition -WithoutTeams -ExcludedApps -Architecture -Language` — XML universel du cahier : `OfficeClientEdition`, `Channel`, `Product ID`, `Language ID="MatchOS"`, un `ExcludeApp` par application décochée, `Updates Enabled`, `Display Level="None" AcceptEULA="TRUE"`, `FORCEAPPSHUTDOWN`. **Aucune ligne Teams, aucune clé, aucun nom d'organisation.** Construit par `System.Xml` (échappement garanti), pas par concaténation.
- `New-OdtRemoveXml -RemoveClickToRun -RemoveMsi -Products` — `<Remove All="TRUE"/>` et/ou `<RemoveMSI/>`, ou suppression ciblée d'un produit (OneNote seul).
- `Get-ExcludedOfficeApp -OptionalApp -IncludedId` — liste des `ExcludeApp` à partir des cases cochées.

**`Public/DotNetRequirement.ps1`** 🆕 — Correspondance version DCU → runtime .NET (cahier, « Dell et .NET »). *Pur.*
- `Select-DotNetRequirement -ToolVersion -Requirements` — renvoie l'entrée dont `DcuVersion` correspond (égalité de version, ou plus grande version connue inférieure ou égale si la version exacte est absente, avec avertissement), ou `$null`.
- `Test-VersionInRange -Version -MinVersion -MaxVersion` — bornes incluses, borne vide = ouverte ; comparaison par `[version]`, jamais par chaîne.

**`Public/ManufacturerMatch.ps1`** 🆕 — Présélection de la card constructeur. *Pur.*
- `Resolve-UtilityKey -Manufacturer -Utilities` — première clé dont `ManufacturerPattern` correspond (insensible à la casse) ; `$null` sinon (aucune card présélectionnée).

**`Public/Inventory.ps1`** 🆕 — Format de l'inventaire N/S + MAC (section 10). *Pur.*
- `Format-InventoryText -Serial -Adapters` — bloc aligné affiché dans la fenêtre et copié dans le presse-papiers.
- `Format-InventoryExport -Snapshot -Date` — contenu du fichier exporté (date, nom d'hôte, constructeur, modèle, puis le bloc ci-dessus).
- `ConvertTo-SafeFileName -Value` — caractères hors `[A-Za-z0-9_-]` remplacés par `_` ; valeur vide → `INCONNU`.

**`Public/Selection.ps1`** 🆕 — Schéma de ce que le technicien a coché. *Pur.* C'est **le contrat entre l'interface et le plan**.
- `New-Selection` — objet vide typé `FastPrepare.Selection` avec une propriété par section : `HostName { Enabled, Name }`, `Software { Items[] }`, `MicrosoftApps { OfficeC2R, OfficeMsi, OutlookClassic, OutlookNew, OneNote, Teams, OneDrive, OneDriveFolder }`, `LocalAccounts { Sids[] }`, `VendorUtility { Key, RunUpdate }`, `Office { EditionKey, WithoutTeams, IncludedApps[] }`, `Updates { WindowsUpdate }`, `ExtraSoftware { Ids[] }`, `SystemSettings { Ipv6DisabledAdapters[], Power }`.
- `Test-Selection -Selection -Snapshot` — cohérence : un SID choisi existe et n'est pas protégé, une édition existe, « dossier OneDrive » implique « OneDrive »… ; renvoie la liste des incohérences. Appelée avant de construire le plan (défense en profondeur : l'interface ne devrait pas les permettre).

### 5.3 `FastPrepare.Infrastructure/Config` et `Logging`

**`Config/AppConfig.ps1`** 🆕 — Lecture et validation de `config.json`.
- `Read-AppConfig -Path` — lit en UTF-8, convertit, appelle `Assert-AppConfig` ; erreur claire si le fichier est absent ou n'est pas du JSON valide (message affiché par `Preparation.ps1`).
- `Assert-AppConfig -Config` — vérifie `ConfigVersion = 2`, la présence et le type des clés obligatoires (C1 à C9), les URL en `https://` (sauf `Connectivity.TestUrl`, imposée en `http` par Microsoft), l'unicité des clés de marques, d'éditions et de logiciels ; lève **une** erreur qui liste tous les problèmes, chacun avec son chemin (`Utilities.lenovo.Install[1].Url : vide`).

**`Logging/RunLog.ps1`** 🆕 — Journal d'une exécution, utilisable depuis n'importe quel fil.
- `New-RunLog -Folder -FallbackFolder -HostName -Stamp` — choisit le dossier (sonde d'écriture sur la clé, repli sur `%TEMP%\FastPrepare` comme aujourd'hui), crée le fichier `Journal_<hôte>_<horodatage>.log` en UTF-8 avec BOM et une `ConcurrentQueue` ; renvoie `{ FilePath, Queue, IsFallback }`.
- `Write-RunLog -Log -Message -Level -StepId` — niveaux `INFO`, `OK`, `ERREUR`, `ATTN`, `SIMU`, `DEBUG` (fichier seulement) ; écrit la ligne (§8), la publie dans la file. Un échec d'écriture fichier est publié **une fois** en `ATTN` dans la file, puis l'écriture fichier est suspendue (plus d'échec silencieux).
- `Copy-RunLogToMedia -Log -Destination` — copie finale vers la clé si le journal était en repli (E7).

### 5.4 `FastPrepare.Infrastructure/Runtime`

**`Runtime/Privilege.ps1`** 🆕
- `Assert-Administrator` — lève une erreur explicite si le jeton courant n'est pas administrateur (texte repris de l'existant : « Utilisez Lancer.cmd »).

**`Runtime/BackgroundRunner.ps1`** 🆕 — Seul endroit qui crée des runspaces.
- `Start-BackgroundWork -Name -ScriptBlock -Arguments -ModulePaths -Queue` — runspace MTA avec `InitialSessionState` qui importe les modules donnés, lance le bloc de façon asynchrone, renvoie un descripteur `{ Name, PowerShell, AsyncResult, StartedAt }`.
- `Test-BackgroundWorkCompleted -Work` / `Receive-BackgroundWork -Work` — résultat ou erreur (les erreurs du flux `Error` sont converties en messages `ERREUR` dans la file) ; libère le runspace.
- `Stop-BackgroundWork -Work` — arrêt demandé à la fermeture de la fenêtre.

### 5.5 `FastPrepare.Infrastructure/System` — adaptateurs Windows

Règle commune : chaque fonction fait **une** opération système, renvoie un objet simple, laisse remonter les erreurs (`-ErrorAction Stop`) ; elle ne journalise pas elle-même la décision métier, seulement l'opération technique (commande, code de sortie).

**`System/Process.ps1`** 🆕 — **Point de passage unique** vers un processus externe.
- `Invoke-ExternalProcess -FilePath -Arguments -WorkingDirectory -TimeoutMinutes -SuccessExitCodes -Log -StepId` — `Start-Process -PassThru -Wait` (ou attente bornée), journalise la commande effective en `DEBUG`, le code de sortie et la durée ; renvoie `{ ExitCode, Succeeded, RebootRequired, Duration }`. Codes MSI connus traduits (`0` succès, `3010` succès + redémarrage requis, `1605` produit absent → succès idempotent, `1618` autre installation en cours → erreur explicite).
- `Invoke-CmdLine -CommandLine -Log -StepId` — repli `cmd.exe /c` pour une `UninstallString` non analysable (DEC8) ; journalisé en `ATTN`.

**`System/Download.ps1`** 🆕 — Téléchargements.
- `Save-RemoteFile -Url -Destination -Sha256 -Log` — BITS (`Start-BitsTransfer`, cahier), repli `HttpClient` si BITS échoue ; vérifie l'empreinte SHA-256 si elle est fournie ; fichier écrit sous un nom temporaire puis renommé (pas de fichier partiel réutilisé par erreur).
- `Assert-TrustedExecutable -Path -ExpectedSigner` — `Get-AuthenticodeSignature` : statut `Valid` exigé, sujet du certificat conforme à `ExpectedSigner` si renseigné ; sinon erreur, le fichier n'est pas lancé (§7).

**`System/Winget.ps1`** 🆕 — winget (cahier : vérifié au démarrage, réenregistré, sinon paquet de la clé).
- `Test-Winget` — `winget.exe` résolu et `winget --version` répond.
- `Assert-Winget -FamilyName -OfflineBundle -Log` — si absent : `Add-AppxPackage -RegisterByFamilyName -MainPackage <FamilyName>` ; si toujours absent : `Add-AppxPackage -Path <OfflineBundle>` (dépendances VCLibs/UI.Xaml du dossier `packages/` comprises) ; erreur explicite si rien ne fonctionne.
- `Install-WingetPackage -Id -Source -Version -Override -Log` — `winget install --id <Id> --exact --source <Source> --silent --accept-package-agreements --accept-source-agreements [--version] [--override]` via `Invoke-ExternalProcess` ; code « déjà installé » traité comme un succès.
- `Get-WingetPackageVersion -Id -Source` — version proposée par winget (`winget show --id … --exact`), nécessaire au choix du runtime .NET de Dell ; analyse tolérante à la langue de sortie (recherche de la ligne par motif `Version`/`Version :`).
- `Save-WingetPackage -Id -Source -Destination` — `winget download` vers le cache (téléchargement anticipé ; non disponible pour la source `msstore`, cf. DEC11).

**`System/Hardware.ps1`** 🆕
- `Get-MachineIdentity` — constructeur, modèle (`Win32_ComputerSystem`), numéro de série (`Win32_BIOS`), libellé et `DisplayVersion` de Windows, nom d'hôte actuel.

**`System/InstalledSoftware.ps1`** 🆕
- `Get-UninstallEntry` — lecture des trois ruches avec les filtres existants (`SystemComponent`, `ParentKeyName`, `ReleaseType`, dédoublonnage) ; renvoie les entrées brutes (pas de décision).
- `Get-ExecutableProbe -Path` — `{ Exists, IsNsis }` : `IsNsis` cherche « Nullsoft » dans les **512 premiers Ko** du fichier (et non le fichier entier jusqu'à 10 Mo).
- `Get-MsiProductCodeByName -DisplayNamePattern` — GUID d'un produit MSI par son nom (Teams Machine-Wide Installer).

**`System/LocalAccounts.ps1`** 🆕
- `Get-LocalAccount` — `{ Name, Sid, ProfilePath }` via `Get-LocalUser` + `Win32_UserProfile`, repli `Win32_UserAccount` (existant).
- `Remove-LocalAccountWithProfile -Sid -ProfilePath` — supprime le profil par l'instance `Win32_UserProfile` (`Remove-CimInstance`, qui nettoie aussi la clé `ProfileList`), puis le compte (`Remove-LocalUser`) ; idempotent (compte déjà absent = succès).

**`System/Network.ps1`** 🆕
- `Get-PhysicalAdapter` — `{ Name, Description, Mac, Ipv6Enabled }` (existant).
- `Disable-AdapterIpv6 -Name` — `Disable-NetAdapterBinding -ComponentID ms_tcpip6`.
- `New-ConnectivityProbe -Url -Expected -TimeoutSeconds` / `Start-ConnectivityCheck` / `Read-ConnectivityResult` — encapsulent le `HttpClient` asynchrone existant ; aucun minuteur ici (le minuteur appartient à l'interface).

**`System/Appx.ps1`** 🆕
- `Remove-AppxEverywhere -Name` — `Remove-AppxPackage -AllUsers` puis `Remove-AppxProvisionedPackage -Online` pour le même nom ; renvoie ce qui a été retiré ; rien à retirer = succès.

**`System/Odt.ps1`** 🆕 — Office Deployment Tool, partagé par les étapes 03 et 07.
- `Initialize-OdtFolder -Folder -SetupUrl -Log` — crée `C:\ODT`, télécharge `setup.exe` (une fois par exécution), vérifie la signature Microsoft.
- `Invoke-Odt -Folder -Xml -Log -StepId` — écrit `configuration-<horodatage>.xml` et lance `setup.exe /configure` ; le XML est aussi recopié dans le journal (cahier : traçabilité de ce qui a été installé).

**`System/OneDrive.ps1`** 🆕
- `Get-OneDriveFolderInfo -ProfilePath` — `{ Path, Exists, FileCount }` (comptage en arrière-plan, D7).
- `Uninstall-OneDrive` — `OneDriveSetup.exe /uninstall` (System32 puis SysWOW64), variante `/allusers` si installé pour tous.
- `Remove-DefaultProfileOneDriveRun` — charge la ruche du profil `Default` (`reg load`), retire la valeur `Run\OneDriveSetup`, décharge **toujours** la ruche (bloc `finally`).

**`System/Power.ps1`** 🆕
- `Set-PowerTimeout -MonitorMinutes -StandbyMinutes -IncludeBattery` — `powercfg /change monitor-timeout-ac|dc`, `standby-timeout-ac|dc`.

**`System/WindowsUpdate.ps1`** 🆕
- `Invoke-WindowsUpdatePass -Log` — une passe complète par l'API `Microsoft.Update.Session` (recherche `IsInstalled=0 and IsHidden=0`, téléchargement, installation) ; journalise chaque mise à jour et le drapeau « redémarrage requis » ; **ne redémarre jamais**.

### 5.6 `FastPrepare.Application` — détections, plan et moteur

**`AppContext.ps1`** 🆕 — Remplace les variables `$script:` globales (D6).
- `New-AppContext -Root -Config -Mode` — renvoie `{ Root, Config, Mode ('Simulation'|'Real'), Paths { Logs, Logos, Packages, OdtFolder, Cache }, Log, Stamp, ModulePaths }`. Résout le mode : paramètre de ligne de commande > `Execution.DefaultMode`. Le mode est **lu par le moteur seul** (règle §6).

**`MachineSnapshot.ps1`** 🆕 — Tout ce que la fenêtre affiche sur le poste, calculé une fois en arrière-plan.
- `Get-MachineSnapshot -Context` — assemble `Identity` (`Get-MachineIdentity`), `WingetAvailable`, `Software` (entrées + `Resolve-UninstallStrategy` par entrée), `LocalAccounts` (`Split-LocalAccount`), `Adapters`, `OneDrive` (`Get-OneDriveFolderInfo`), `SuggestedUtilityKey` (`Resolve-UtilityKey`), `InventoryText` ; journalise les mêmes lignes qu'aujourd'hui (« 32 logiciels détectés, dont 11 sans désinstallation silencieuse »). Chaque partie est protégée séparément : un échec WMI ne vide pas la liste des logiciels.

**`StepRegistry.ps1`** 🆕 — Catalogue des étapes.
- `Register-Step -Id -Section -Title -Plan -Invoke` — enregistre un descripteur. **Contrat d'une étape** :
  - `Plan` : bloc `param($Selection, $Snapshot, $Context)` qui renvoie zéro, une ou plusieurs **actions** `{ StepId, Label, Parameters, Interactive }` ; aucun effet de bord ; zéro action = étape non cochée.
  - `Invoke` : bloc `param($Action, $Context)` qui exécute **une** action par les fonctions d'`Infrastructure` ; lève une erreur en cas d'échec ; ne teste jamais le mode simulation.
- `Get-RegisteredStep` — descripteurs dans l'ordre de `StepOrder.ps1`.
- `Assert-StepCatalog` — chaque étape enregistrée figure exactement une fois dans `StepOrder`, et réciproquement ; appelé au chargement du module (une étape oubliée échoue au démarrage, pas en production).

**`StepOrder.ps1`** 🆕 — **Ordre d'exécution du cahier, à un seul endroit.**
- `Get-StepOrder` — liste ordonnée des identifiants : `export-inventory` (1), `remove-local-accounts` (2), `remove-microsoft-apps` (3), `remove-onedrive` (4), `uninstall-software` (5), `install-vendor-utility` (6), `install-office` (7), `install-software` (8), `disable-ipv6` (9), `set-power-plan` (10), `update-vendor-utility` (11), `run-windows-update` (12), `rename-computer` (13). Le rapport final (14) n'est pas une étape : c'est la conclusion du moteur.

**`ExecutionPlan.ps1`** 🆕
- `New-ExecutionPlan -Selection -Snapshot -Context` — `Test-Selection`, puis appelle le `Plan` de chaque étape dans l'ordre, numérote les actions et renvoie `{ Actions[], Warnings[] }`. **Même plan pour la simulation et l'exécution réelle.**
- `Format-ExecutionPlanSummary -Plan` — « 13 actions, dont 2 désinstallations avec assistant » : affiché dans la boîte de confirmation avant une exécution réelle.

**`ExecutionEngine.ps1`** 🆕 — Exécute un plan ; seul fichier qui connaît le mode.
- `Invoke-ExecutionPlan -Plan -Context` — pour chaque action : journalise `[ETAPE n/N]`, puis
  - en **Simulation** : journalise le `Label` de l'action en `SIMU` (ou `ATTN` si `Interactive`) ;
  - en **Real** : appelle le `Invoke` de l'étape dans un `try` ; succès → `OK` avec durée ; erreur → `ERREUR` (message + commande + code de sortie) et **passage à l'action suivante** (cahier).
  Publie la progression ; renvoie les résultats `{ Action, Outcome ('Succeeded'|'Failed'|'Simulated'), Error, RebootRequired, Duration }`.
- `Start-ExecutionPlan -Plan -Context` — lance `Invoke-ExecutionPlan` dans le runspace (`Start-BackgroundWork`) ; appelée par l'interface.

**`FinalReport.ps1`** 🆕 — Étape 14 du cahier.
- `Write-FinalReport -Results -Context` — compte réussites, échecs (rappelés un par un), actions simulées ; signale « redémarrage requis » si une action l'a indiqué ; rappelle `config.ManualReminders` ; donne l'emplacement du journal et de l'inventaire ; appelle `Copy-RunLogToMedia` si le journal était en repli.

**`Prefetch.ps1`** 🆕 — Téléchargement anticipé dès le clic sur une card (E3).
- `Start-Prefetch -UtilityKey -Context` — en arrière-plan : version proposée par winget, runtime .NET correspondant, puis `Save-WingetPackage` / `Save-RemoteFile` de chaque élément `Install` dans `Cache\<clé>` ; un nouveau clic annule le précédent.
- `Get-PrefetchedItem -UtilityKey -ItemIndex -Context` — chemin du fichier en cache s'il est complet et vérifié, sinon `$null` (l'étape 06 installera alors en ligne).

### 5.7 `FastPrepare.Application/Steps` — une étape par fichier

Chaque fichier appelle `Register-Step` une fois. Le tableau donne, pour chacune, ce que `Plan` produit et ce que `Invoke` exécute.

| Fichier | Section | `Plan` (actions produites) | `Invoke` (fonctions appelées) |
|---|---|---|---|
| `ExportInventory.step.ps1` | 10 | Une action si l'inventaire n'a pas déjà été exporté au démarrage. | `Format-InventoryExport` + écriture `Inventaire_<N/S>_<horodatage>.txt` dans le dossier du journal. |
| `RemoveLocalAccounts.step.ps1` | 4 | Une action par SID coché (libellé : nom + chemin du profil). | Revérifie `Test-ProtectedAccount` **et** `Test-SafeProfilePath`, puis `Remove-LocalAccountWithProfile`. |
| `RemoveMicrosoftApps.step.ps1` | 3 | Une action ODT de suppression (C2R et/ou MSI réunis dans un même XML) ; une action par Appx (nouvel Outlook, OneNote, MSTeams, MicrosoftTeams) ; une action Teams classique (MSI Machine-Wide + dossiers locaux). « Outlook classique » seul : action d'information (retiré avec la suite, QO1 au §11). | `Initialize-OdtFolder` + `Invoke-Odt` (`New-OdtRemoveXml`) ; `Remove-AppxEverywhere` ; `Get-MsiProductCodeByName` + `Invoke-ExternalProcess msiexec /x`. |
| `RemoveOneDrive.step.ps1` | 3 | Désinstallation ; retrait de la clé `Run` du profil Default ; suppression du dossier si cochée (libellé : nombre de fichiers). | `Uninstall-OneDrive`, `Remove-DefaultProfileOneDriveRun`, `Test-SafeProfilePath` puis `Remove-Item -Recurse`. |
| `UninstallSoftware.step.ps1` | 2 | Une action par logiciel coché, triées par `Get-UninstallOrder` ; `Interactive = $true` pour les assistants. | `Invoke-ExternalProcess` (silencieux) ; assistant : lancement et attente de sa fermeture, avertissement `ATTN` préalable dans le journal. |
| `InstallVendorUtility.step.ps1` | 5 | Dépendance .NET si requise (`Select-DotNetRequirement` sur la version annoncée par winget), puis un élément par entrée `Install`. | `Assert-Winget` ; `Install-WingetPackage` ; `Get-PrefetchedItem` ou `Save-RemoteFile` + `Assert-TrustedExecutable` + `Invoke-ExternalProcess`. |
| `InstallOffice.step.ps1` | 6 | Une action (libellé : édition, ID produit, exclusions ; XML complet en paramètre). | `Initialize-OdtFolder`, `Invoke-Odt` (`New-OdtInstallXml`). |
| `InstallSoftware.step.ps1` | 8 | Une action par logiciel coché du catalogue `config.Software`. | `Assert-Winget`, `Install-WingetPackage` (avec `Override`). |
| `DisableIpv6.step.ps1` | 9 | Une action par carte cochée **dont IPv6 est encore actif**. | `Disable-AdapterIpv6`. |
| `SetPowerPlan.step.ps1` | 9 | Une action si cochée (libellé calculé depuis `config.Power`). | `Set-PowerTimeout`. |
| `UpdateVendorUtility.step.ps1` | 7 | Une action si une card est choisie et la case cochée. | `Expand-ConfigPath` sur `Update.FilePath`, `Invoke-ExternalProcess` avec `SuccessExitCodes`. |
| `RunWindowsUpdate.step.ps1` | 7 | Une action si cochée. | `Invoke-WindowsUpdatePass`. |
| `RenameComputer.step.ps1` | 1 | Une action si cochée (revalidée par `Test-HostName`). | `Rename-Computer -NewName -Force` **sans** `-Restart` ; marque « redémarrage requis ». |

### 5.8 `FastPrepare.UI` — fenêtre WPF

**`Xaml/Theme.xaml`** 🆕 — `ResourceDictionary` : couleurs nommées (`AccentBrush #005FB8`, `SuccessBrush`, `ErrorBrush`, `WarnBrush`…) et styles `Section`, `H2`, `Sub`, `Hint`, `Tech`, `Card`, `Pill`, `Primary` repris tels quels de l'existant. Les couleurs ne sont plus recopiées en dur dans le code (`Get-Brush '#0F7B0F'` disparaît au profit des ressources nommées).

**`Xaml/MainWindow.xaml`** 🆕 — Coquille : en-tête (pastille de connexion, poste, OS, bandeau SIMULATION), pied (journal + bouton Lancer + progression), deux colonnes `StackPanel` vides (`ColLeft`, `ColRight`), mémo. Aucune section en dur.

**`Xaml/Sections/*.xaml`** 🆕 — Un fragment par section (racine `Border Style="{StaticResource Section}"`). Les listes et cards dynamiques y sont des conteneurs vides (`PnlApps`, `PnlUtilities`, `PnlOfficeEditions`, `PnlSoftware`), remplis par le code.

**`XamlLoader.ps1`** 🆕
- `Initialize-WpfApplication -ThemePath` — crée l'objet `System.Windows.Application` s'il n'existe pas déjà (un seul par processus) et y fusionne `Theme.xaml` : les `StaticResource` des fragments chargés séparément se résolvent ainsi (§11, DEC4).
- `Import-Xaml -Path` — charge un fichier XAML (`XamlReader.Load`) et renvoie `{ Root, Controls }` où `Controls` est la table des éléments nommés (mécanisme `$UI` existant, généralisé à chaque fragment).

**`Controls.ps1`** 🆕 — Fabriques de contrôles générés (remplacent `Add-AppRow`, `New-GridColumn`, les cards en dur).
- `New-SelectableCard -Key -Title -Subtitle -LogoPath` — `ToggleButton` au style `Card`, logo affiché seulement si le fichier existe (échec de chargement journalisé en `DEBUG`, plus avalé).
- `New-SoftwareRow -Software` — ligne Nom / Éditeur / Silencieux avec info-bulle de la commande.
- `New-CheckItem -Content -Tag -IsChecked -IsEnabled` — case simple (sessions, cartes réseau, logiciels de la section 8).
- `Set-ExclusiveSelection -Cards -Source` — une seule card cochée par groupe, re-clic = désélection (comportement existant, écrit une fois au lieu de deux).

**`SectionRegistry.ps1`** 🆕 — Contrat des sections d'interface.
- `Register-UiSection -Id -Number -Column -XamlPath -Initialize -GetSelection -Validate -OnSnapshot` :
  - `Initialize(Controls, Context)` : branche les événements, génère les contrôles issus de la configuration ;
  - `OnSnapshot(Controls, Snapshot)` : remplit les listes quand les détections sont terminées ;
  - `GetSelection(Controls, Selection)` : écrit **sa** partie de la `Selection` ;
  - `Validate(Controls)` : `$null` ou un motif qui bloque Lancer (« nom d'hôte invalide »).
- `Get-UiSection [-Id]` — une section, ou toutes triées par numéro.

**`Sections/*.ps1`** 🆕 — Une section du cahier par fichier, chacun n'appelant que `Register-UiSection` :

| Fichier | Rôle propre |
|---|---|
| `ConnectivitySection.ps1` (0) | Pastille verte / rouge ; sonde `New-ConnectivityProbe` à l'intervalle configuré ; journalise seulement les **changements** d'état ; `Validate` bloque Lancer tant que la connexion n'est pas validée. |
| `HostNameSection.ps1` (1) | Champ grisé si décoché ; `Get-HostNameError` affiché sous le champ ; nom actuel rappelé. |
| `InstalledSoftwareSection.ps1` (2) | Liste générée depuis `Snapshot.Software` ; « Tout cocher » ; légende ⚠. |
| `MicrosoftAppsSection.ps1` (3) | Cases et méthodes affichées ; « Dossier OneDrive » grisé tant que OneDrive est décoché ; nombre de fichiers. |
| `LocalAccountsSection.ps1` (4) | Comptes supprimables et liste des exclus avec motif. |
| `VendorUtilitySection.ps1` (5) | Cards générées depuis `config.Utilities` ; présélection `Snapshot.SuggestedUtilityKey` ; clic → `Start-Prefetch` ; état du téléchargement affiché sous les cards. |
| `OfficeSection.ps1` (6) | Cards générées depuis `config.Office.Editions` ; pastilles Avec / Sans Teams visibles seulement si l'édition a un `NoTeamsProductId` ; cases `OptionalApps`. |
| `UpdatesSection.ps1` (7) | « MàJ utilitaire » grisée sans card choisie (lit l'état de la section 5 par la `Selection`, pas par ses contrôles). |
| `SoftwareSection.ps1` (8) | Cases générées depuis `config.Software`. |
| `SystemSettingsSection.ps1` (9) | Une case par carte réseau ; case alimentation avec libellé calculé (`ApplyOnBattery`). |
| `InventorySection.ps1` (10) | Bloc N/S + MAC ; bouton Copier ; emplacement de l'export. |

**`LogView.ps1`** 🆕
- `Add-LogLine -RichTextBox -Entry` — ajoute la ligne colorée selon le niveau (couleurs du thème), défile en bas ; limite l'affichage aux 5 000 dernières lignes (le fichier, lui, garde tout).

**`UiPump.ps1`** 🆕 — Le seul `DispatcherTimer` de l'application (la sonde réseau de la section 0 s'y enregistre par `Register-UiTickHandler`).
- `Start-UiPump -Context -Handlers` — toutes les 200 ms : vide la file du journal vers `LogView`, met à jour la progression, détecte la fin des travaux d'arrière-plan et appelle leur rappel (`OnSnapshot`, fin de préchargement, fin d'exécution).
- `Stop-UiPump`.

**`MainWindow.ps1`** 🆕 — Assemble la fenêtre ; aucune règle métier.
- `Start-MainWindow -Context` — `Initialize-WpfApplication`, charge la coquille, insère chaque fragment de section dans sa colonne, appelle les `Initialize`, lance `Get-MachineSnapshot` en arrière-plan, démarre la pompe, affiche la fenêtre.
- `Update-LaunchState` — Lancer actif si **toutes** les sections renvoient `Validate = $null` et qu'aucune exécution n'est en cours ; affiche le premier motif bloquant (remplace `Update-LaunchState` qui connaissait chaque contrôle).
- `Invoke-Launch` — construit la `Selection` (chaque `GetSelection`), le plan (`New-ExecutionPlan`) ; en mode réel, boîte de confirmation avec `Format-ExecutionPlanSummary` ; puis `Start-ExecutionPlan`, désactive le formulaire jusqu'à la fin.
- `Confirm-WindowClose` — confirmation si une exécution est en cours.

### 5.9 Outillage (poste de développement, jamais sur la clé)

**`tools/Invoke-Tests.ps1`** 🆕 — Lance Pester 5 sur `tests/` avec couverture de `src/FastPrepare.Core` et `src/FastPrepare.Application` ; échoue si un test échoue. Pester 5 est installé sur le poste de développement uniquement (Windows 11 n'embarque que Pester 3.4) — DEC5.

**`tools/Invoke-Lint.ps1`** 🆕 — PSScriptAnalyzer avec `PSScriptAnalyzerSettings.psd1` (règles par défaut + `PSUseCompatibleSyntax` cible 5.1, `PSAvoidUsingInvokeExpression`, `PSUseApprovedVerbs`, `PSAvoidGlobalVars`) ; vérifie aussi l'encodage (BOM UTF-8 sur `*.ps1|psm1|psd1`, CRLF sur `*.cmd`).

**`tools/Build-Usb.ps1`** 🆕 — `-Destination E:\` : lance tests et lint, puis copie **uniquement** `Lancer.cmd`, `Preparation.ps1`, `config.json`, `src/`, `logos/`, `packages/` et un dossier `logs/` vide ; retire la marque de zone (`Unblock-File`) des scripts copiés ; écrit `VERSION.txt` (date, empreinte de `config.json`).

**`.editorconfig`**, **`.gitattributes`**, **`.gitignore`** 🆕 — Encodage et fins de ligne (§1) ; `logs/`, `packages/`, `*.log` ignorés.

### 5.10 Tests

Tests Pester sous `tests/`, en miroir de `src/`. `Core` est testé **sans mock** (fonctions pures) ; les étapes sont testées avec les fonctions d'`Infrastructure` remplacées par `Mock -ModuleName FastPrepare.Application`.

| Fichier de test | Ce qu'il prouve |
|---|---|
| `Core/HostName.Tests.ps1` | 15 caractères acceptés, 16 refusés ; `123` refusé, `PC-123` accepté ; tiret initial/final refusé ; accents et `_` refusés ; message de `Get-HostNameError` pour chaque cas. |
| `Core/UninstallStrategy.Tests.ps1` | Les quatre lignes du tableau du cahier à partir de `Fixtures/registry-uninstall-entries.json` (QuietUninstallString prioritaire, MSI par `PSChildName` puis par chaîne `/I{GUID}`, `unins000.exe`, NSIS, assistant) ; `Get-UninstallOrder` met les assistants en dernier. |
| `Core/OdtConfiguration.Tests.ps1` | XML valide pour chaque édition de `config.valid.json` ; aucune balise contenant « Teams », « PIDKEY » ou « CompanyName » ; « Sans Teams » → `O365BusinessEEANoTeamsRetail` ; refus de « Sans Teams » pour LTSC ; une `ExcludeApp` par case décochée. |
| `Core/DotNetRequirement.Tests.ps1` | DCU 5.7.0 → .NET 8 dans [8.0.8 ; 8.0.25] ; 5.7.1 → .NET 10 ≥ 10.0.8 ; comparaison numérique (`8.0.9 < 8.0.25`). |
| `Core/LocalAccountPolicy.Tests.ps1` | RID 500/501/503/504 et compte connecté exclus ; RID 1001 supprimable. |
| `Core/PathGuard.Tests.ps1` | `C:\Users`, `C:\Users\Default`, `C:\Users\Public`, le profil connecté, `C:\Users\x\..\..\Windows` refusés ; `C:\Users\ancien` accepté. |
| `Core/ManufacturerMatch.Tests.ps1`, `Inventory.Tests.ps1`, `CommandLine.Tests.ps1`, `Selection.Tests.ps1` | Présélection (`Hewlett-Packard` → hp, `LENOVO` → lenovo, inconnu → aucune) ; format et nom de fichier sûr ; découpe des lignes avec guillemets ; incohérences de sélection détectées. |
| `Infrastructure/AppConfig.Tests.ps1` | `config.valid.json` accepté ; chaque clé obligatoire retirée → erreur qui cite son chemin ; ancienne configuration (sans `ConfigVersion`) refusée avec un message explicite. |
| `Application/StepRegistry.Tests.ps1` | Chaque étape de `Steps/` est dans `StepOrder` et réciproquement ; aucun doublon. |
| `Application/ExecutionPlan.Tests.ps1` | Avec `Fixtures/selection.full.json`, les actions sortent **dans l'ordre du cahier** quelle que soit l'ordre des sections ; sélection vide → plan vide ; carte avec IPv6 déjà désactivé → pas d'action. |
| `Application/ExecutionEngine.Tests.ps1` | Simulation : aucun `Invoke` appelé, une ligne `SIMU` par action. Réel : une action qui lève une erreur est journalisée `ERREUR` et **les suivantes s'exécutent** ; résultats agrégés justes ; « redémarrage requis » propagé au rapport. |
| `Application/Steps/*.Tests.ps1` | Pour chaque étape : `Plan` produit les bonnes actions, `Invoke` appelle les bonnes fonctions d'`Infrastructure` avec les bons arguments (mocks) ; garde de chemin et comptes protégés revérifiés dans `Invoke`. |
| `Architecture.Tests.ps1` | Analyse statique des sources : aucun `System.Windows` hors `FastPrepare.UI` ; aucun `Get-CimInstance`, `Get-ItemProperty HKLM:`, `Start-Process` hors `Infrastructure` ; aucun `Invoke-Expression` ; aucune URL `http(s)://` dans `src/` (règle « liens jamais dans le code ») ; aucun fichier sans BOM. |

---

## 6. Où vit chaque règle (source unique)

Une règle n'est écrite qu'une fois ; les autres fichiers l'**appellent**. Toute revue peut vérifier qu'aucune n'est réimplémentée ailleurs. La colonne **Preuve** dit ce qui démontre que la règle tient ; une règle sans preuve n'est pas considérée comme livrée.

| Règle (référence du cahier) | Propriétaire unique | Appelée par | Preuve |
|---|---|---|---|
| Ordre d'exécution (« Ordre d'exécution », 1 à 13) | `Application/StepOrder.ps1` (`Get-StepOrder`) | `StepRegistry`, `ExecutionPlan` | `ExecutionPlan.Tests` ; `StepRegistry.Tests` |
| Échec d'une étape → journal rouge et suite | `Application/ExecutionEngine.ps1` (`Invoke-ExecutionPlan`) | toutes les étapes | `ExecutionEngine.Tests` (action en échec, suivantes exécutées) |
| Mode simulation | `AppContext` (résolution) + `ExecutionEngine` (seul lecteur) | — | `ExecutionEngine.Tests` ; `Architecture.Tests` (aucune étape ne lit `Context.Mode`) |
| Nom d'hôte valide (section 1) | `Core/HostName.ps1` | `HostNameSection` (affichage), `RenameComputer.step` (revalidation) | `HostName.Tests` |
| Stratégie de désinstallation (tableau « Désinstallation silencieuse ») | `Core/UninstallStrategy.ps1` (`Resolve-UninstallStrategy`) | `MachineSnapshot` | `UninstallStrategy.Tests` |
| Silencieux d'abord, assistants en dernier | `Core/UninstallStrategy.ps1` (`Get-UninstallOrder`) | `UninstallSoftware.step` | `UninstallStrategy.Tests` |
| Comptes exclus d'office (section 4) | `Core/LocalAccountPolicy.ps1` | `MachineSnapshot`, `RemoveLocalAccounts.step` (revalidation) | `LocalAccountPolicy.Tests` |
| Suppression récursive sûre | `Core/PathGuard.ps1` | `RemoveLocalAccounts.step`, `RemoveOneDrive.step` | `PathGuard.Tests` ; tests des deux étapes |
| XML ODT (section 6) et suppression ODT (section 3) | `Core/OdtConfiguration.ps1` | `InstallOffice.step`, `RemoveMicrosoftApps.step`, `OfficeSection` (résumé) | `OdtConfiguration.Tests` |
| ID produit avec / sans Teams | `Core/OdtConfiguration.ps1` (`Get-OfficeProductId`) + données `config.Office.Editions` | `New-OdtInstallXml` | `OdtConfiguration.Tests` |
| Runtime .NET selon la version de DCU | `Core/DotNetRequirement.ps1` + données `Utilities.dell.DotNet` | `InstallVendorUtility.step`, `Prefetch` | `DotNetRequirement.Tests` |
| Présélection de la marque (section 5) | `Core/ManufacturerMatch.ps1` + `ManufacturerPattern` | `MachineSnapshot` | `ManufacturerMatch.Tests` |
| Une seule card par groupe | `UI/Controls.ps1` (`Set-ExclusiveSelection`) | `VendorUtilitySection`, `OfficeSection` | recette manuelle |
| Conditions d'activation de Lancer | `UI/MainWindow.ps1` (`Update-LaunchState`) à partir des `Validate` de section | toutes les sections | recette manuelle |
| Liens, versions, identifiants winget | `config.json` | étapes, `Prefetch` | `Architecture.Tests` (aucune URL dans `src/`) ; `AppConfig.Tests` |
| Validité de la configuration | `Infrastructure/Config/AppConfig.ps1` (`Assert-AppConfig`) | `Preparation.ps1` | `AppConfig.Tests` |
| Lancement d'un processus externe | `Infrastructure/System/Process.ps1` | toutes les étapes | `Architecture.Tests` (aucun `Start-Process` ailleurs) |
| Codes de sortie MSI / outils constructeur | `Process.ps1` (MSI) + `Update.SuccessExitCodes` (outils) | étapes | `Process.Tests` |
| Téléchargement et vérification | `Infrastructure/System/Download.ps1` | `Odt`, `InstallVendorUtility.step`, `Prefetch` | `Download.Tests` (empreinte fausse → refus ; signature invalide → refus) |
| winget présent (contraintes du cahier) | `Infrastructure/System/Winget.ps1` (`Assert-Winget`) | étapes 06 et 08, `Prefetch` | `Winget.Tests` (mocks des trois cas) ; recette sur poste sans winget |
| Format du journal | `Infrastructure/Logging/RunLog.ps1` | tous | `RunLog.Tests` |
| Format et nom de l'inventaire | `Core/Inventory.ps1` | `MachineSnapshot`, `ExportInventory.step`, `InventorySection` | `Inventory.Tests` |
| Rappels des actions manuelles | `config.ManualReminders` | mémo de la fenêtre, `FinalReport` | `FinalReport.Tests` |
| Jamais de redémarrage automatique | aucun appel à `Restart-Computer`, aucun `-Restart`, ODT et outils lancés avec leurs options « sans redémarrage » | — | `Architecture.Tests` (motifs interdits) ; recette |
| Création d'un runspace | `Infrastructure/Runtime/BackgroundRunner.ps1` | `MainWindow`, `Prefetch`, `ExecutionEngine` | `Architecture.Tests` |

---

## 7. Sécurité et robustesse

L'outil s'exécute **en administrateur** sur un poste qui sera remis à un utilisateur ; une erreur se paie en données perdues (profils, OneDrive) ou en poste compromis (exécutable piégé). Les mesures ci-dessous sont proportionnées à ce contexte.

### 7.1 Exécution de code

| Risque | Mesure | Fichier |
|---|---|---|
| Interprétation d'une chaîne comme du code | Aucun `Invoke-Expression`, aucun `cmd /c` sauf repli tracé pour une `UninstallString` non analysable ; exécutable et arguments toujours séparés. | `Process.ps1`, `CommandLine.ps1` ; `Architecture.Tests` |
| Exécutable téléchargé falsifié (lien direct Thin Installer, `setup.exe` ODT) | HTTPS imposé par `Assert-AppConfig` ; `Assert-TrustedExecutable` (signature Authenticode `Valid` + éditeur attendu) ; empreinte SHA-256 si renseignée. | `Download.ps1`, `AppConfig.ps1` |
| Paquet winget usurpé | `--exact --source <source>` toujours précisés ; identifiants dans la configuration, relus à chaque changement de version (le cahier demande de les revérifier au moment de coder). | `Winget.ps1` |
| Résolution d'un mauvais `powershell.exe` | Chemin absolu dans `Lancer.cmd`. | `Lancer.cmd` |
| Politique d'exécution | `-ExecutionPolicy Bypass` limité au processus (aucune modification de la politique du poste). `Build-Usb` débloque les fichiers copiés. | `Lancer.cmd`, `Build-Usb.ps1` |
| Module chargé depuis un emplacement inattendu | Modules importés **par chemin absolu** calculé depuis `$PSScriptRoot`, jamais par nom (pas de recherche dans `PSModulePath`). | `Preparation.ps1`, `BackgroundRunner.ps1` |

### 7.2 Actions destructives

| Risque | Mesure | Fichier |
|---|---|---|
| Suppression du mauvais compte | Comptes protégés exclus à l'affichage **et** revérifiés juste avant suppression ; SID (et non nom) comme identifiant. | `LocalAccountPolicy.ps1`, `RemoveLocalAccounts.step.ps1` |
| Suppression récursive hors cible (`C:\Users`, profil connecté) | `Test-SafeProfilePath` avant tout `Remove-Item -Recurse`. | `PathGuard.ps1` |
| Ruche du profil Default restée chargée | Déchargement en `finally`. | `OneDrive.ps1` |
| Exécution réelle déclenchée par erreur | Mode simulation par défaut ; en mode réel, boîte de confirmation avec le résumé du plan ; bandeau permanent indiquant le mode. | `AppContext.ps1`, `MainWindow.ps1` |
| Deux exécutions simultanées | Bouton Lancer et formulaire désactivés pendant l'exécution. | `MainWindow.ps1` |

### 7.3 Données et traces

- Le journal ne contient **aucun secret** : le XML ODT n'a ni clé ni nom d'organisation (cahier), aucun mot de passe n'est saisi. Il contient des données d'inventaire (N/S, MAC, noms de comptes locaux supprimés) : la clé USB doit être traitée comme un support interne.
- Idempotence : relancer l'outil sur un poste déjà préparé ne doit rien casser (produit MSI absent `1605`, Appx absent, compte absent = succès).
- Une configuration invalide est refusée **au démarrage**, jamais découverte au milieu d'une exécution.

---

## 8. Journal — contrat de traçabilité

### 8.1 Contrat existant, conservé

| Élément | Valeur |
|---|---|
| Dossier | `logs\` à côté de `Preparation.ps1` ; repli `%TEMP%\FastPrepare` si la clé est en lecture seule (le dossier de repli actuel, `PreparationPoste`, est renommé). |
| Fichiers | `Journal_<NOM-HÔTE>_<yyyyMMdd-HHmmss>.log` ; `Inventaire_<N/S>_<yyyyMMdd-HHmmss>.txt` (même horodatage). |
| Encodage | UTF-8 avec BOM. |
| Ligne | `HH:mm:ss [NIVEAU] message` |
| Niveaux | `INFO` (gris), `OK` (vert), `ERREUR` (rouge), `ATTN` (jaune), `SIMU` (bleu). |

### 8.2 Ajouts

- Niveau **`DEBUG`**, écrit dans le fichier seulement : commandes effectives, codes de sortie, durées, sorties techniques utiles au support. La fenêtre reste lisible pour le technicien.
- Lignes d'étape : `HH:mm:ss [INFO] [ETAPE 5/13 · section 2] Désinstallation silencieuse (MSI) : <logiciel>` puis `[OK] … (12 s)` ou `[ERREUR] … : code de sortie 1603`. Le numéro d'étape (ordre du cahier) et le numéro de section (interface) sont distincts : les deux figurent, la confusion actuelle (« 3. » dans le journal pour la section 3 **et** pour l'étape 3) disparaît.
- En-tête du journal : version de l'outil (`VERSION.txt`), mode (`Simulation` / `Real`), empreinte de `config.json`, poste (constructeur, modèle, N/S, Windows).
- Rapport final (étape 14) : nombre d'actions réussies / échouées / simulées, rappel de chaque échec, « redémarrage requis », rappels manuels, emplacement du journal.

---

## 9. Ordre de développement — itérations

L'ordre suit les dépendances (§4.1) et le risque : on **restructure d'abord à comportement constant**, puis on ajoute le moteur réel en commençant par les actions réversibles et en finissant par les plus longues. Chaque itération est utilisable sur une clé et se termine par `tools/Invoke-Tests.ps1`, `tools/Invoke-Lint.ps1` verts et la partie concernée de `docs/recette.md` déroulée sur un poste réel.

### Itération 0 — Fondations, parité avec l'existant

- `git init`, `.editorconfig`, `.gitattributes`, `.gitignore`, `README.md`, `docs/CONTRIBUTING.md`, outillage `tools/`.
- Quatre modules et leurs manifestes ; `Preparation.ps1` réduit au démarrage ; `Lancer.cmd` (chemin absolu, arguments).
- `config.json` version 2 (C1 à C9) et `Assert-AppConfig`.
- `AppContext`, `RunLog` (fichier + file), `LogView`, `UiPump`.
- XAML extrait : `Theme.xaml`, `MainWindow.xaml`, un fragment par section ; `SectionRegistry` et les onze fichiers de section **à comportement identique** ; cards constructeur, Office et logiciels générées depuis la configuration.
- `tests/Architecture.Tests.ps1`.
- **Sortie** : la fenêtre est visuellement identique à la maquette validée ; aucune règle métier n'a changé.

**État : ✅ livrée le 2026-11-10** (branche `iteration-0`). Écarts avec le contenu prévu, tous assumés :

- **Règles déplacées dès cette itération** : `Core` contient déjà `HostName`, `UninstallStrategy`, `LocalAccountPolicy`, `OdtConfiguration`, `ManufacturerMatch`, `Inventory`, `Selection` et leurs tests. Les sections ne pouvaient pas garder les règles du prototype sans les recopier dans l'interface, ce qui aurait contredit le §1. Restent pour l'itération 1 : `CommandLine`, `PathGuard`, `DotNetRequirement` (sans utilisateur avant les itérations 4 et 5).
- **Fichiers transitoires dans `Application`** : `SelectionSimulation.ps1` (`Invoke-SelectionSimulation`) reproduit la simulation du prototype à partir de la `Selection` seule, sans contrôle WPF ; il disparaît à l'itération 2 au profit du plan unique. `InventoryExport.ps1` (`Export-MachineInventory`) sera repris par l'étape `ExportInventory.step.ps1`.
- **Relevé du poste encore synchrone** : `Get-MachineSnapshot` tourne sur le fil de l'interface, après l'affichage de la fenêtre (même ressenti que le prototype). Passage en arrière-plan : itération 1.
- **Noms au singulier** (convention du §1) : `Get-LocalAccount`, `Split-LocalAccount`, `Get-PhysicalAdapter`, `Get-UninstallEntry`, `Get-ExcludedOfficeApp`, `Get-UninstallOrder` (le verbe `Sort` n'est pas approuvé).
- **`Selection`** : `LocalAccounts.Items` et `Software.Items` portent les objets du relevé (pas seulement les SID) ; la case « MàJ utilitaire » est `Updates.VendorUtility`.
- **Contrat de section** : en plus de ceux du §5.8, deux rappels facultatifs, `Refresh` (réagir à la `Selection`, ex. section 7 qui suit la section 5) et `Dispose` (libérer la sonde réseau). Les gestionnaires d'événements retrouvent leur section par `Get-UiSection -Id` plutôt que par une fermeture (`GetNewClosure` perd l'accès aux fonctions privées du module) ; ils passent tous par `Invoke-UiAction`, qui journalise une erreur au lieu de fermer la fenêtre.
- **Mode réel** refusé au démarrage avec un message clair (`New-AppContext`) tant que le moteur n'existe pas.
- **Pester 5** : `tools/Invoke-Tests.ps1 -PesterPath` permet de l'utiliser sans l'installer (paquet extrait de la PowerShell Gallery).
- **`Architecture.Tests.ps1`** analyse les commandes réellement appelées (arbre syntaxique) et non le texte : les messages de simulation qui citent `Remove-LocalUser` ne sont pas des appels.
- **Vérifié** : 334 tests Pester verts, PSScriptAnalyzer sans avertissement ; fenêtre lancée sur un poste réel (Lenovo 20NR) avec clics simulés : présélection, sélection exclusive, licence sans Teams, blocage de Lancer par un nom d'hôte invalide, simulation dans l'ordre du cahier.

### Itération 1 — Règles pures et détections en arrière-plan

- `FastPrepare.Core` complet avec ses tests (HostName, UninstallStrategy, LocalAccountPolicy, PathGuard, OdtConfiguration, DotNetRequirement, ManufacturerMatch, Inventory, CommandLine, Selection).
- `BackgroundRunner`, adaptateurs de lecture (`Hardware`, `InstalledSoftware` avec sonde NSIS bornée, `LocalAccounts` lecture, `Network` lecture, `OneDrive` comptage), `MachineSnapshot`.
- Fenêtre affichée immédiatement, listes remplies à la fin des détections (indicateur « détection en cours… »).
- **Sortie** : E4 levé ; la fenêtre ne gèle plus au démarrage.

**État : ✅ livrée le 2026-11-10** (branche `iteration-1`). Écarts et constats :

- **`Core` complet** : `PathGuard` (`Test-SafeProfilePath`, avec `-AllowInsideProfile` pour un sous-dossier comme OneDrive, et `Test-SafeChildPath`), `CommandLine` (`Split-CommandLine`, `Expand-ConfigPath`, qui refuse une variable inconnue pour signaler une faute de frappe dans `config.json`), `DotNetRequirement` (`Test-VersionInRange`, `Select-DotNetRequirement`, qui renvoie `{ Requirement, IsExactMatch }` ; « 5.7.0 » couvre « 5.7.0.1234 »).
- **`BackgroundRunner`** : `Start-BackgroundWork`, `Test-BackgroundWorkCompleted`, `Receive-BackgroundWork`, `Stop-BackgroundWork`. Le bloc est transmis sous forme de texte (un scriptblock reste lié à son runspace d'origine) ; `$ErrorActionPreference = 'Stop'` est posé par l'état initial du runspace (deux `AddScript` formeraient un pipeline).
- **Journal partagé entre fils** : verrou (`SyncRoot`) autour de l'écriture du fichier, `File.AppendAllText` en UTF-8 avec BOM ; test de 600 écritures simultanées depuis deux fils, aucune perte.
- **Relevé du poste** : `Start-MachineSnapshot` (relevé et export d'inventaire dans un runspace) ; `Register-UiBackgroundWork` dans la pompe appelle le rappel sur le fil de l'interface à la fin du travail. Le contexte porte `ModulePaths` (modules non graphiques importés par le runspace).
- **Présélection constructeur** : elle n'écrase plus une card choisie par le technicien pendant la détection.
- **Bogue de PowerShell 5.1** rencontré : `@($liste)` sur une `List[object]` lève une `ArgumentException` dans le binder (« Les types des arguments ne correspondent pas »), ce qui fermait la fenêtre. Remplacé par `.ToArray()` ; le battement de la pompe est désormais entièrement protégé.
- **Mesuré** sur poste réel (Lenovo 20NR, 32 logiciels) : fenêtre affichée immédiatement, relevé prêt en 7 s ; le fil de l'interface reste réactif pendant tout le relevé (connexion validée pendant la détection). Il subsiste **un gel unique d'environ 0,6 s** au remplissage des sections, à la fin du relevé (construction des lignes de logiciels et première compilation des blocs de script). Un clic coûte ensuite ~30 ms. Piste si besoin : liste des logiciels en `ItemsControl` avec `DataTemplate` XAML au lieu de contrôles construits en code.
- **Vérifié** : 461 tests Pester verts (dont un test d'intégration du relevé réel en arrière-plan, marqué `Integration`), PSScriptAnalyzer sans avertissement, règle d'architecture « runspaces créés uniquement par `BackgroundRunner.ps1` ».

### Itération 2 — Plan unique, moteur en simulation

- `StepRegistry`, `StepOrder`, `ExecutionPlan`, `ExecutionEngine` (mode Simulation), `FinalReport`.
- Les treize fichiers d'étape avec leur `Plan` seulement (`Invoke` non implémenté → l'étape est refusée en mode réel avec un message clair).
- Suppression de `Invoke-Simulation`.
- **Sortie** : le journal de simulation contient les mêmes actions qu'aujourd'hui, dans l'ordre du cahier, produites par le plan ; D2 levé.

### Itération 3 — Exécution réelle des actions réversibles

- `Process`, `Download`, `Winget` (dont `Assert-Winget` : E2), `Power`, `Network` (écriture).
- `Invoke` de `SetPowerPlan`, `DisableIpv6`, `InstallSoftware` (Adobe, E8), `RenameComputer`, `ExportInventory`.
- Mode réel activable (`Lancer.cmd -Real`), confirmation avant exécution.
- **Sortie** : première préparation réelle partielle sur poste de test.

### Itération 4 — Désinstallations

- `LocalAccounts` (suppression), `Appx`, `OneDrive`, `Odt` (suppression), `InstalledSoftware` (code produit MSI).
- `Invoke` de `RemoveLocalAccounts`, `RemoveMicrosoftApps`, `RemoveOneDrive`, `UninstallSoftware` (silencieux puis assistants).
- **Sortie** : étapes 2 à 5 réelles ; recette sur un poste avec Office C2R, Office MSI 2016, Teams classique et nouveau, OneDrive peuplé, deux comptes locaux.

### Itération 5 — Utilitaires constructeurs

- `Prefetch` (E3), `Select-DotNetRequirement` branché (E5), éléments `Install` multiples (E6, Lenovo), `Update` structuré (D9).
- `Invoke` de `InstallVendorUtility` et `UpdateVendorUtility`.
- **Sortie** : recette sur un poste de chaque marque (Dell avec DCU 5.7.0 et 5.7.1, HP, Lenovo, Fujitsu).

### Itération 6 — Office

- `Invoke` de `InstallOffice` (quatre éditions, avec / sans Teams, exclusions).
- **Sortie** : recette des quatre éditions ; XML de chaque installation présent dans le journal.

### Itération 7 — Windows Update, rapport final, livraison

- `WindowsUpdate`, `Invoke` de `RunWindowsUpdate`.
- Copie du journal en repli vers la clé (E7), progression « étape n / N », confirmation à la fermeture.
- `Build-Usb.ps1` finalisé ; `docs/recette.md` déroulée intégralement.
- **Sortie** : toutes les exigences du cahier couvertes ; `Execution.DefaultMode` peut passer à `Real` (DEC6).

| Itération | Sections du cahier | Écarts / dettes levés | Modules principaux |
|---|---|---|---|
| 0 | toutes (affichage) | D1, D3, D4, D6, D8, D10–D15 | squelette des quatre modules, UI |
| 1 | 2, 4, 5, 9, 10 (détections) | D5, D7, E4 | Core, Infrastructure (lecture), MachineSnapshot |
| 2 | ordre d'exécution, 14 | D2 | Application (plan, moteur) |
| 3 | 1, 8, 9, 10 | E2, E8, E9 | Process, Download, Winget |
| 4 | 2, 3, 4 | — | désinstallations |
| 5 | 5, 7 (utilitaire) | D9, E3, E5, E6 | Prefetch, utilitaires |
| 6 | 6 | — | Office |
| 7 | 7 (WU), 14 | E1, E7, E10 | WindowsUpdate, livraison |

---

## 10. Recettes d'extension — ajouter une fonctionnalité

C'est le critère de réussite de cette architecture : chaque évolution prévisible touche **peu de fichiers, toujours les mêmes**, et ne modifie aucun fichier existant sans rapport.

### 10.1 Ajouter une étape d'exécution (ex. « désactiver le démarrage rapide »)

1. `src/FastPrepare.Infrastructure/System/<Domaine>.ps1` : la fonction système (`Disable-FastStartup`), si elle n'existe pas.
2. `src/FastPrepare.Application/Steps/DisableFastStartup.step.ps1` : `Register-Step` avec `Plan` et `Invoke`.
3. `src/FastPrepare.Application/StepOrder.ps1` : insérer l'identifiant à sa place.
4. `src/FastPrepare.Core/Public/Selection.ps1` : la propriété correspondante dans `New-Selection`.
5. Interface : une case dans la section existante concernée (fragment XAML + `GetSelection`), ou une nouvelle section (§10.5).
6. Tests : `Steps/DisableFastStartup.Tests.ps1`. `StepRegistry.Tests` échoue tant que l'étape 3 est oubliée.

### 10.2 Ajouter une marque (ex. Dynabook)

1. `config.json` : un bloc `Utilities.dynabook` (`Label`, `Subtitle`, `Logo`, `ManufacturerPattern`, `Install[]`, `Update`).
2. `logos/dynabook.png` (facultatif).
3. Aucun fichier de code modifié. La card apparaît, la présélection fonctionne, l'installation et la MàJ passent par les étapes 06 et 11. Seule exception : une dépendance conditionnelle à la version (comme .NET pour Dell) demande d'étendre `DotNetRequirement.ps1` en règle générique « dépendances par version ».

### 10.3 Ajouter un logiciel à la section 8 (ex. 7-Zip)

1. `config.json` : une entrée dans `Software[]` (`Id`, `Label`, `WingetId`, `Source`, `DefaultChecked`).
2. Aucun fichier de code modifié.

### 10.4 Ajouter une édition Office ou changer un canal

1. `config.json` : une entrée dans `Office.Editions[]` (avec `NoTeamsProductId` si une variante EEE existe).
2. Un cas dans `OdtConfiguration.Tests.ps1` si l'édition a une particularité.

### 10.5 Ajouter une section d'interface

1. `src/FastPrepare.UI/Xaml/Sections/<Nom>.xaml` : le fragment.
2. `src/FastPrepare.UI/Sections/<Nom>Section.ps1` : `Register-UiSection` (colonne, numéro, `Initialize`, `GetSelection`, `Validate`, `OnSnapshot`).
3. Si la section affiche une détection : la propriété dans `MachineSnapshot.ps1` et l'adaptateur de lecture correspondant.
4. `MainWindow.ps1` n'est pas modifié.

### 10.6 Ce qui demande une décision avant d'être codé

Une règle qui change le **contrat** (format du journal, ordre d'exécution du cahier, comportement en cas d'échec, introduction d'un redémarrage) se décide d'abord dans ce document (§11) et dans le cahier des charges, puis se code.

---

## 11. Décisions

| # | Question | Décision | Itération |
|---|---|---|---|
| DEC1 | Classes PowerShell (`class`) pour les étapes et les objets métier ? | **Non.** En 5.1, une classe définie dans un module n'est visible qu'avec `using module` (chemin fixe en tête de fichier), ne se recharge pas sans redémarrer la session et passe mal entre runspaces. `[pscustomobject]` typés par `PSTypeName` et fonctions `New-*` à la place. | 0 |
| DEC2 | Modules (`.psm1` + manifeste) ou simples scripts dot-sourcés ? | **Modules.** Frontière d'export explicite (`FunctionsToExport`), import en une ligne dans le runspace d'arrière-plan (`InitialSessionState.ImportPSModule`), `Mock -ModuleName` dans Pester. Quatre modules par couche, pas un par fichier (KISS). | 0 |
| DEC3 | Arrière-plan : `Start-Job`, `ThreadJob`, runspace ? | **Runspace.** `Start-Job` lance un processus par tâche (lent, sérialise tout) ; `ThreadJob` n'est pas fourni avec Windows PowerShell 5.1. Un runspace est natif et partage la file de messages. | 1 |
| DEC4 | XAML : un seul fichier ou un fragment par section ? | **Un fragment par section** + `Theme.xaml` fusionné dans les ressources de l'objet `Application` créé au démarrage, pour que les `StaticResource` des fragments se résolvent. | 0 |
| DEC5 | Tests : quelle version de Pester ? | **Pester 5** sur le poste de développement uniquement ; jamais requis sur la clé. Windows 11 embarque Pester 3.4, dont la syntaxe est incompatible. | 0 |
| DEC6 | Mode par défaut. | **Simulation** jusqu'à la fin de l'itération 7 et de la recette complète ; puis `Execution.DefaultMode = "Real"`, la simulation restant disponible par `Lancer.cmd -Simulation`. | 7 |
| DEC7 | Une configuration ou plusieurs (une par marque, un catalogue logiciel…) ? | **Un seul `config.json` à la racine** (contrat du cahier, un seul fichier à relire quand une version change). À reconsidérer au-delà d'une dizaine de marques ou de logiciels. | 0 |
| DEC8 | Exécution d'une `UninstallString` non analysable. | Découpage par `Split-CommandLine` ; en cas d'échec, `cmd.exe /c` **tracé en `ATTN`**, jamais `Invoke-Expression`. Ces lignes viennent du registre du poste, écrites par des installateurs : leur forme n'est pas maîtrisée. | 4 |
| DEC9 | Alimentation : secteur et batterie, ou secteur seulement (point en attente du cahier) ? | **Paramètre `Power.ApplyOnBattery`, `true` par défaut** (comportement actuel). La réponse du cahier changera une valeur, pas le code. | 3 |
| DEC10 | Export de l'inventaire : au démarrage ou à l'étape 1 ? | **Au démarrage** (comportement actuel, utile même si le technicien ne lance rien) ; l'étape 1 ne réexporte que si l'export initial a échoué. | 2 |
| DEC11 | Téléchargement anticipé pour la source `msstore` (Lenovo Commercial Vantage). | `winget download` ne prend pas en charge `msstore` : pas de préchargement pour cet élément, installation en ligne à l'étape 06 ; le préchargement porte sur Thin Installer. | 5 |
| DEC12 | Interface : WPF ou WinForms (les deux sont permis par le cahier) ? | **WPF**, comme l'existant et la maquette validée. | — |

**Questions ouvertes** (à trancher avec le cahier des charges avant l'itération concernée) :

| # | Question | Itération |
|---|---|---|
| QO1 | « Outlook classique » coché **sans** « Office Click-to-Run » : faut-il retirer Outlook seul (ODT suppression ciblée) ? Aujourd'hui la case est purement informative (« retiré avec la suite Office »). | 4 |
| QO2 | Teams classique : supprimer le dossier `%LocalAppData%\Microsoft\Teams` du profil connecté seulement, ou de tous les profils restants ? | 4 |
| QO3 | Windows Update : une passe suffit-elle si une mise à jour en exige une autre (pile de maintenance) ? Le cahier dit « une passe complète » : on journalise « des mises à jour restent disponibles » sans relancer. | 7 |
| QO4 | Préciser les codes de sortie de chaque outil constructeur considérés comme succès (`Update.SuccessExitCodes`). | 5 |
