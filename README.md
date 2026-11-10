# FastPrepare — Outil de préparation de poste Windows 11

Prépare un poste Windows 11 en une seule exécution, depuis une clé USB, juste après une
réinitialisation : le technicien coche les actions dans une fenêtre, clique sur **Lancer**,
lit le journal, puis redémarre lui-même le poste. Applicable à n'importe quel parc :
tout ce qui varie d'un parc à l'autre se règle dans `config.json`.

> **État : itération 9, toutes les étapes du cahier disponibles en mode réel, plus la création
> d'une session locale (section 11) et le catalogue des logiciels modifiable dans l'onglet Réglages.** La simulation
> reste le mode par défaut jusqu'à la recette complète sur postes de test
> ([`docs/recette.md`](docs/recette.md)) ; ensuite, `Execution.DefaultMode` = `"Real"` dans `config.json`.
> Feuille de route : [`docs/architecture_plan.md`](docs/architecture_plan.md) §9.

## Pour le technicien

1. Préparer la clé depuis un poste de développement : `tools\Build-Usb.ps1 -Destination E:\FastPrepare`.
2. Sur le poste à préparer : double-cliquer `Lancer.cmd` (demande les droits administrateur).
3. Lire le journal en bas de la fenêtre ; il est aussi enregistré dans `logs\` sur la clé,
   avec l'inventaire N/S + adresses MAC.

Options : `Lancer.cmd -Simulation` (force la simulation), `Lancer.cmd -Real` (modifie le poste,
après confirmation ; bandeau rouge « MODE RÉEL »). Pendant l'exécution, la barre sous **Lancer**
indique l'action en cours ; la fenêtre ne redémarre jamais le poste.

Session locale (section 11) : nom, nom complet, mot de passe saisi deux fois, administrateur ou
non, mot de passe qui n'expire jamais ou à changer à la première ouverture. Le mot de passe
n'est jamais écrit dans le journal ; une session existante n'est jamais modifiée.

Onglet **Réglages** → « Catalogue des logiciels » : ajouter un logiciel proposé en section 8, par
paquet winget ou par lien direct (`.exe` / `.msi`), le **tester sans rien télécharger ni installer**
(paquet trouvé, lien qui mène bien à un fichier), puis l'enregistrer dans `software.json` sur la clé.
`tools\Build-Usb.ps1` conserve le catalogue déjà présent sur une clé (`-ReplaceSoftwareCatalog` pour
le remplacer par celui du dépôt).

**Rien n'est fait automatiquement hors outil** : réinitialisation de Windows, RMM, antivirus,
BitLocker, activation d'Office, redémarrage (liste dans `config.json`, `ManualReminders`).

## Adapter l'outil à un parc

Tout se fait dans `config.json` (validé au démarrage, avec un message qui indique la clé fautive) :

| Besoin | Clé |
|---|---|
| Ajouter une marque (card de la section 5) | `Utilities.<clé>` + logo facultatif dans `logos\` |
| Changer un identifiant winget, un lien, une version | `Utilities`, `Office` |
| Ajouter, modifier, retirer un logiciel à installer (section 8) | onglet **Réglages** de la fenêtre (enregistré dans `software.json`) |
| Ajouter une édition Office | `Office.Editions[]` |
| Durées d'alimentation, batterie incluse ou non | `Power` |
| Rappels des actions manuelles | `ManualReminders` |
| Options proposées par défaut pour la session à créer (section 11) | `NewLocalAccount` (facultatif) |

## Pour le développeur

- Architecture, responsabilités par fichier, règles et feuille de route : [`docs/architecture_plan.md`](docs/architecture_plan.md).
- Conventions, tests, lint : [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).
- Ajouter une étape d'exécution : un fichier `src\FastPrepare.Application\Steps\<Nom>.step.ps1` + son rang dans `StepOrder.ps1` (plan, §10.1).
- Recette manuelle sur poste réel : [`docs/recette.md`](docs/recette.md).

```text
Lancer.cmd → Preparation.ps1 → src\FastPrepare.UI → src\FastPrepare.Application → src\FastPrepare.Infrastructure
                                                                          └──────────► src\FastPrepare.Core (règles pures)
```
