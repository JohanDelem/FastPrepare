# FastPrepare — Outil de préparation de poste Windows 11

Prépare un poste Windows 11 en une seule exécution, depuis une clé USB, juste après une
réinitialisation : le technicien coche les actions dans une fenêtre, clique sur **Lancer**,
lit le journal, puis redémarre lui-même le poste. Applicable à n'importe quel parc :
tout ce qui varie d'un parc à l'autre se règle dans `config.json`.

> **État : itération 3** — simulation par défaut ; **mode réel** disponible pour l'alimentation,
> IPv6, les logiciels de la section 8 (winget) et le nom d'hôte. Les autres étapes sont ignorées
> en mode réel (et signalées) jusqu'aux itérations suivantes.
> Feuille de route : [`docs/architecture_plan.md`](docs/architecture_plan.md) §9.

## Pour le technicien

1. Préparer la clé depuis un poste de développement : `tools\Build-Usb.ps1 -Destination E:\FastPrepare`.
2. Sur le poste à préparer : double-cliquer `Lancer.cmd` (demande les droits administrateur).
3. Lire le journal en bas de la fenêtre ; il est aussi enregistré dans `logs\` sur la clé,
   avec l'inventaire N/S + adresses MAC.

Options : `Lancer.cmd -Simulation` (force la simulation), `Lancer.cmd -Real` (modifie le poste,
après confirmation ; à réserver pour l'instant aux postes de test).

**Rien n'est fait automatiquement hors outil** : réinitialisation de Windows, RMM, antivirus,
BitLocker, activation d'Office, redémarrage (liste dans `config.json`, `ManualReminders`).

## Adapter l'outil à un parc

Tout se fait dans `config.json` (validé au démarrage, avec un message qui indique la clé fautive) :

| Besoin | Clé |
|---|---|
| Ajouter une marque (card de la section 5) | `Utilities.<clé>` + logo facultatif dans `logos\` |
| Changer un identifiant winget, un lien, une version | `Utilities`, `Office`, `Software` |
| Ajouter un logiciel à installer (section 8) | `Software[]` |
| Ajouter une édition Office | `Office.Editions[]` |
| Durées d'alimentation, batterie incluse ou non | `Power` |
| Rappels des actions manuelles | `ManualReminders` |

## Pour le développeur

- Architecture, responsabilités par fichier, règles et feuille de route : [`docs/architecture_plan.md`](docs/architecture_plan.md).
- Conventions, tests, lint : [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).
- Ajouter une étape d'exécution : un fichier `src\FastPrepare.Application\Steps\<Nom>.step.ps1` + son rang dans `StepOrder.ps1` (plan, §10.1).
- Recette manuelle sur poste réel : [`docs/recette.md`](docs/recette.md).

```text
Lancer.cmd → Preparation.ps1 → src\FastPrepare.UI → src\FastPrepare.Application → src\FastPrepare.Infrastructure
                                                                          └──────────► src\FastPrepare.Core (règles pures)
```
