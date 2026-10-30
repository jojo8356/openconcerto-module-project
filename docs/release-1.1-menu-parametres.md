# Module project 1.1 — le menu Paramètres est désormais visible

**Ce jar remplace celui de la release `v1.1-demarrage-corrige`** : le module
démarre bien, mais le menu de paramétrage des libellés n'apparaissait chez
personne. Il apparaît maintenant.

## Où est le menu

Barre de menus du client, **juste avant `Aide`** :

```
Fichier  Saisie  Gestion  Comptabilité  Déclaration  Statistiques  Paiement  Paye  Structure  Paramètres  Aide
                                                                                            └── Libellés des colonnes
```

C'est là que l'utilisateur qui a **le plus de droits dans la base** choisit le nom
des colonnes de toutes les listes, pour toute l'équipe (`ID_CLIENT` → `CLIENT`,
`ID_AFFAIRE` → `AFFAIRE`, …). Les réglages restent stockés sur le serveur SQL
(`PROJECT_COLUMN_LABEL`, `PROJECT_SETTINGS`) et, pour les valeurs par défaut,
dans le jar (`column-labels.properties`).

## Ce qui n'allait pas

Le menu était ajouté dans `setupMenu`, c'est-à-dire **avant l'ouverture de la
session**. À cet instant, le client ne sait pas encore quel utilisateur est
connecté : la vérification des droits répondait « utilisateur de la session
inconnu », ce qui était traité comme un refus. Conséquence : le menu était masqué
pour **tout le monde**, administrateur compris.

## Ce qui change

- Le menu est ajouté au démarrage (`start()`), quand l'utilisateur est connu,
  directement dans la barre de menus (`MainFrame.addMenuItem`), avec repli dans
  le menu **`Structure`** si le client refuse la création d'un menu de premier
  niveau.
- Tant que la décision ne peut pas être prise, le module **réessaie toutes les
  2 secondes pendant 30 secondes** au lieu de renoncer.
- Seul un refus explicite (« le rôle le plus haut est Gisèle ») masque le menu.
- Le journal du client trace le résultat :
  - `menu « Libellés des colonnes » ajoute (utilisateur …)`
  - `menu « Libellés des colonnes » masque : le role le plus haut est …`

## Vérifications

| Suite | Résultat |
|---|---|
| `scripts/run-tests.sh` | `AffairLinkSupportTest` 35 tests, `ColumnLabelRulesTest` **40 tests**, `SupplierOrderToInvoiceSQLInjectorTest` 19 tests |
| `scripts/test-mutations-colonnes.sh` | **8 contrôles, 0 échec** (la mutation 7 remet l'ancien comportement et est détectée) |
| `tests/sql/e2e-colonnes.sh` | 34 contrôles, 0 échec |

## Installation

1. Fermer OpenConcerto.
2. Copier `org.openconcerto.modules.project-1.1.jar` dans le dossier **Modules**
   (un seul jar de ce module ; `scripts/installer-jar-release.sh --jar …`
   s'occupe de déplacer l'ancien).
3. Redémarrer le client, se connecter avec le compte le mieux doté.
4. Le menu **Paramètres** apparaît à droite de `Structure` (quelques secondes
   suffisent) ; vérifier dans la console la ligne
   `menu « Libellés des colonnes » ajoute (utilisateur …)`.

Mode d'emploi : `docs/parametres-colonnes.md`. Recette cliquable :
`docs/recette-graphique-colonnes.md`. Construction du jar :
`docs/construire-le-jar.md`.
