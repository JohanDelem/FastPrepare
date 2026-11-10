# Contribuer à FastPrepare

## Environnement

- **Cible d'exécution** : Windows 11, Windows PowerShell **5.1** uniquement, aucun module tiers sur la clé.
- **Poste de développement** : Windows PowerShell 5.1, plus deux modules de développement :
  - [Pester](https://pester.dev) **5.5 ou plus** : `Install-Module Pester -Scope CurrentUser -MinimumVersion 5.5 -SkipPublisherCheck`
    (Windows 11 n'embarque que Pester 3.4, incompatible). Sans installation : télécharger le paquet
    depuis la PowerShell Gallery et passer `-PesterPath <dossier contenant Pester.psd1>`.
  - PSScriptAnalyzer : `Install-Module PSScriptAnalyzer -Scope CurrentUser`.

## Commandes

| Commande | Rôle |
|---|---|
| `tools\Invoke-Tests.ps1 [-PesterPath <chemin>] [-Coverage]` | Tests Pester (`tests\`) |
| `tools\Invoke-Lint.ps1` | PSScriptAnalyzer + contrôle des encodages ; échoue au premier avertissement |
| `tools\Build-Usb.ps1 -Destination <dossier>` | Lint + tests, puis copie du seul nécessaire sur la clé |
| `Lancer.cmd -Simulation` | Lancer l'outil sans rien modifier sur le poste |

Avant chaque commit : `Invoke-Lint.ps1` et `Invoke-Tests.ps1` verts.

## Règles de code

- **Compatibilité 5.1** : pas d'opérateur ternaire, pas de `??`, pas de `ForEach-Object -Parallel`, pas de `Test-Json`, pas de classes PowerShell (décision DEC1).
- **Encodage** : `.ps1`, `.psm1`, `.psd1` en **UTF-8 avec BOM** ; tous les fichiers texte en **CRLF** (`.editorconfig`, `.gitattributes`). Le lint le vérifie.
- **Nommage** : verbes approuvés (`Get-Verb`), noms au singulier (`Get-LocalAccount`, pas `Get-LocalAccounts`), paramètres nommés, messages utilisateur en français, identifiants de code en anglais.
- **Couches** (vérifiées par `tests\Architecture.Tests.ps1`) :
  - `FastPrepare.Core` : fonctions pures ; ni fichier, ni registre, ni WMI, ni `$env:`, ni WPF.
  - `FastPrepare.Infrastructure` : seul endroit qui touche au système.
  - `FastPrepare.Application` : cas d'usage ; aucun type WPF.
  - `FastPrepare.UI` : WPF uniquement ; n'appelle jamais `Infrastructure\System\*` directement.
- **Jamais** d'`Invoke-Expression`, de `Restart-Computer` ni de lien `http(s)://` dans `src\` (les liens vivent dans `config.json`).
- **Une fonction exportée** = une entrée dans `FunctionsToExport` du manifeste du module.
- **Une règle métier = un propriétaire** (tableau §6 du plan d'architecture) : on l'appelle, on ne la réécrit pas. Toucher une règle, c'est mettre à jour son test.

## Ajouter une fonctionnalité

Voir les recettes du plan d'architecture, §10 (étape d'exécution, marque, logiciel, édition Office, section d'interface).

## Commits

Conventional Commits en français (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`), une itération par branche (`iteration-N`) fusionnée dans `main` par pull request.
