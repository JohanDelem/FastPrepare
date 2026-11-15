# FastPrepare — Outil de préparation de poste Windows 11

Prépare un poste Windows 11 en une seule exécution, juste après une réinitialisation : le
technicien coche les actions dans une fenêtre, clique sur **Lancer**, lit le journal, puis
redémarre lui-même le poste.

L'outil ne suppose rien de la façon dont il est arrivé sur le poste : dossier copié depuis un
support amovible, archive téléchargée, partage réseau. Il ne suppose rien non plus du parc :
ce qui varie d'un parc à l'autre se règle dans `config.json` (écrit à la main) et dans le
catalogue des logiciels `software.json` (modifié depuis l'onglet **Réglages**).

> **État : version 1.13.0** (fichier `VERSION`, affichée dans le titre de la fenêtre et en tête du
> journal). Toutes les étapes fonctionnent en mode réel. La simulation reste le mode par défaut
> jusqu'à la recette complète sur postes de test ([`docs/recette.md`](docs/recette.md)) ; ensuite,
> `Execution.DefaultMode` = `"Real"` dans `config.json`.
> Feuille de route et décisions : [`docs/architecture_plan.md`](docs/architecture_plan.md) §9 et §11.

## Pour le technicien

1. **Obtenir l'outil** : le dossier `FastPrepare-<version>` (ou l'archive `.zip` du même nom,
   **à extraire entièrement**). Il se place où l'on veut : disque du poste, support amovible,
   partage réseau.
2. **Lancer** : double-cliquer `Lancer.cmd` (demande les droits administrateur).
3. **Cocher** ce qui doit être fait, dans l'ordre où ce sera exécuté :

   | Section | Contenu |
   |---|---|
   | 1 · Numéro de série et adresses MAC | Relevé, copie, export |
   | 2 · Suppression des sessions locales | Comptes et profils |
   | 3 · Désinstallation des programmes Microsoft | Office, Outlook, OneNote, Teams, OneDrive |
   | 4 · Désinstallation des logiciels installés | Silencieuse si possible, assistant sinon |
   | 5 · Installations | Logiciels du catalogue, **outil du constructeur détecté**, Microsoft Office |
   | 6 · Configuration des paramètres système | IPv6, alimentation |
   | 7 · Mises à jour | Pilotes et BIOS par l'outil du constructeur, Windows Update |
   | 8 · Changer le nom d'hôte | Pris en compte au redémarrage |
   | 9 · Créer une session locale | Pour l'utilisateur final |

4. **Lire le journal** en bas de la fenêtre. Il est aussi enregistré, avec l'inventaire N/S +
   adresses MAC, dans le **dossier de sortie** (`Output.Folder` de `config.json`, par défaut
   `logs\` dans le dossier de l'outil).

L'outil ne propose que l'outil du constructeur du poste (Dell Command Update sur un Dell, HP
Image Assistant sur un HP…). Sur un poste de constructeur inconnu ou une machine virtuelle,
aucun outil constructeur n'est proposé.

Options : `Lancer.cmd -Simulation` (force la simulation), `Lancer.cmd -Real` (modifie le poste,
après confirmation ; bandeau rouge « MODE RÉEL »). Pendant l'exécution, la barre sous **Lancer**
indique l'action en cours ; la fenêtre ne redémarre jamais le poste.

Session locale : nom, nom complet, mot de passe saisi deux fois, administrateur ou non, mot de
passe qui n'expire jamais ou à changer à la première ouverture. Le mot de passe n'est jamais
écrit dans le journal ; une session existante n'est jamais modifiée.

**Ce que l'outil laisse sur le poste** : rien d'autre que ce qui a été coché. Ses téléchargements
et le dossier de l'Office Deployment Tool (`%ProgramData%\FastPrepare`) sont supprimés à la fin
d'une exécution réelle sans échec d'installation ; en cas d'échec ils sont conservés pour le
diagnostic, et le rapport final le dit.

**Rien n'est fait automatiquement hors outil** : réinitialisation de Windows, RMM, antivirus,
BitLocker, activation d'Office, redémarrage (liste dans `config.json`, `ManualReminders`).

## Où vont le journal et l'inventaire

`Output.Folder` accepte trois formes :

| Valeur | Effet |
|---|---|
| `"logs"` (par défaut) | Dans le dossier de l'outil : pratique quand l'outil repart avec le technicien (support amovible). |
| `"D:\\Preparations"` | Chemin absolu. |
| `"\\\\serveur\\partage\\preparations"` | Partage réseau : tous les journaux et inventaires au même endroit, même si l'outil a été téléchargé sur chaque poste. Le partage est ouvert avec le compte qui lance l'outil ; aucun identifiant n'est stocké. |

Si ce dossier n'est pas accessible en écriture (support en lecture seule, partage injoignable),
le journal et l'inventaire sont écrits sur le poste, dans `%ProgramData%\FastPrepare\sortie`. La
fenêtre le signale, une nouvelle copie est tentée en fin d'exécution, et le rapport final donne
le chemin à copier à la main si elle échoue encore.

## Adapter l'outil à un parc

`config.json` et `software.json` sont validés au démarrage, avec un message qui indique le
réglage ou l'entrée fautive.

| Besoin | Où |
|---|---|
| Ajouter, modifier, retirer un logiciel à installer | Onglet **Réglages** (enregistré dans `software.json`) |
| Ajouter l'outil d'une marque, ou le limiter à une marque | Onglet **Réglages**, champ « Constructeur » (ex. `Dell`, `HP\|Hewlett`) |
| Commande de mise à jour des pilotes et du BIOS d'une marque | Bloc `Update` de l'entrée, dans `software.json` |
| Ajouter une édition Office | `config.json` → `Office.Editions[]` |
| Dossier du journal et de l'inventaire | `config.json` → `Output.Folder` |
| Catalogue commun à plusieurs techniciens | `config.json` → `SoftwareCatalog` (chemin absolu ou réseau) |
| Durées d'alimentation, batterie incluse ou non | `config.json` → `Power` |
| Rappels des actions manuelles (facultatifs) | `config.json` → `ManualReminders` |
| Mode par défaut (simulation ou réel) | `config.json` → `Execution.DefaultMode` |
| Options proposées par défaut pour la session à créer | `config.json` → `NewLocalAccount` (facultatif) |

Onglet **Réglages** → « Catalogue des logiciels » : ajouter un logiciel par paquet winget ou par
lien direct (`.exe` / `.msi`), le **tester sans rien télécharger ni installer** (paquet trouvé,
lien qui mène bien à un fichier), puis l'enregistrer. L'ancienne version du catalogue est gardée
en `software.json.bak`.

Une configuration d'une version antérieure (`ConfigVersion` 3 ou moins) est refusée au démarrage
avec la consigne de migration ; un `software.json` au format 1 est lu tel quel.

## Pour le développeur

- Architecture, responsabilités par fichier, règles et feuille de route : [`docs/architecture_plan.md`](docs/architecture_plan.md).
- Conventions, tests, lint : [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).
- Produire le livrable : `tools\Build-Release.ps1 -Destination D:\Livraisons -Zip` (lint et tests, puis dossier et archive `FastPrepare-<version>`).
- Ajouter une étape d'exécution : un fichier `src\FastPrepare.Application\Steps\<Nom>.step.ps1` + son rang dans `StepOrder.ps1` (plan, §10.1).
- Ajouter un réglage à l'onglet Réglages : une section `Register-UiSection -Column Settings` (plan, §10.6).
- Recette manuelle sur poste réel : [`docs/recette.md`](docs/recette.md).

```text
Lancer.cmd → Preparation.ps1 → src\FastPrepare.UI → src\FastPrepare.Application → src\FastPrepare.Infrastructure
                                                                          └──────────► src\FastPrepare.Core (règles pures)
```
