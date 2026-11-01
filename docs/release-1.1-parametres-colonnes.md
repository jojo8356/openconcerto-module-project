# Module project 1.1 — libellés des colonnes pour toute l'équipe

Ce lot ajoute le menu **Paramètres → Libellés des colonnes**. Il répond
à la gêne signalée par Gisèle : dans les listes, les colonnes s'appellent
`ID_CLIENT`, `ID_AFFAIRE`, `ID_FACTURE_FOURNISSEUR`… alors qu'elle veut lire
`CLIENT`, `AFFAIRE`, `FACTURE FOURNISSEUR`.

La version du module reste **1.1** (aucune nouvelle fonctionnalité n'est retirée,
le jar se substitue au précédent).

## Qui décide

Le menu n'est proposé qu'à l'utilisateur qui a **le plus de droits dans la base** :
super-utilisateurs s'il y en a, sinon administrateurs, sinon les comptes qui
cumulent le plus de droits dans `USER_RIGHT` (comptes désactivés ignorés). Pour
les autres, le menu est masqué et la raison est écrite dans le journal du client.

## Ce qui est enregistré, et où

| Emplacement | Contenu | Portée |
|---|---|---|
| **Serveur SQL** : `PROJECT_COLUMN_LABEL`, `PROJECT_SETTINGS` | les libellés choisis, avec `DATE` et `ID_USER` | **toute l'équipe**, immédiat pour le poste qui enregistre, au redémarrage pour les autres |
| **Jar** : `column-labels.properties` | valeurs par défaut d'une nouvelle installation ; exportables depuis l'écran | nouvelle installation |

- Index unique `(TABLE_NAME, COLUMN_NAME)` : pas de règle concurrente.
- `TABLE_NAME = '*'` : la règle vaut pour toutes les tables.
- Trois modes : `AUTO` (défaut, retire le préfixe `ID_`), `MAPPING` (uniquement
  les règles saisies), `OFF` (aucun changement, retour arrière immédiat).

## Ce qui est couvert

- les listes de l'historique des affaires construites par le module (en-tête et
  recherche) ;
- les en-têtes de **tous les tableaux** de l'application, listes du cœur
  comprises, via un écouteur global — **sans modifier OpenConcerto** et sans
  jamais renommer les colonnes SQL.

## Vérifications

| Suite | Résultat |
|---|---|
| `scripts/run-tests.sh` | `AffairLinkSupportTest` 35 tests, `ColumnLabelRulesTest` 39 tests, `SupplierOrderToInvoiceSQLInjectorTest` 16 tests |
| `tests/sql/e2e-colonnes.sh` | 34 contrôles, 0 échec |
| `scripts/test-mutations-colonnes.sh` | 7 mutations, 0 échec |
| `scripts/test-affaire-fournisseur.sh` | 7 suites, 0 échec |

## Installation

1. Fermer OpenConcerto.
2. Copier `org.openconcerto.modules.project-1.1.jar` dans le dossier **Modules**
   (garder **un seul** jar de ce module). Chemin fiable : client → **? / Aide →
   Informations → « Dossiers des modules »**.
3. Redémarrer le client. Le menu apparaît pour le compte le mieux doté.
4. Vérifier l'empreinte : `sha256sum org.openconcerto.modules.project-1.1.jar`
   doit correspondre au fichier `.sha256` joint.

Détails : `docs/installation-du-jar.md`. Mode d'emploi de l'écran :
`docs/parametres-colonnes.md`.
