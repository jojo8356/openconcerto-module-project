# Module project 1.1 — libellés des colonnes en noir

**Ce jar remplace celui de `v1.1-edition-libelles`.** Seule différence visible :
la lisibilité de l'écran de paramétrage.

## Ce qui change

| Avant | Maintenant |
|---|---|
| Les libellés automatiques s'affichaient en **gris italique** | tout est en **noir** |
| Il fallait plisser les yeux pour lire `TAXE PORT`, `DEVIS`, `AFFAIRE`… | lisibles immédiatement, quel que soit le thème du client |
| Le reste du tableau dépendait du thème | tableau et en-têtes en noir explicite, grille en gris clair |

La distinction reste visible : **gras** = libellé personnalisé (une règle
existe), texte normal = libellé automatique (suppression du préfixe `ID_`).
Le double-clic pour modifier est inchangé.

## Vérifications

| Suite | Résultat |
|---|---|
| `scripts/run-tests.sh` | `AffairLinkSupportTest` 35, `ColumnLabelRulesTest` **47**, `SupplierOrderToInvoiceSQLInjectorTest` 19 |
| `scripts/test-mutations-colonnes.sh` | **11 contrôles, 0 échec** — la mutation 10 remet le gris pâle et la suite échoue |
| compilation contre `OpenConcerto.jar` 1.7.6 (CI) | success, bytecode Java 8 vérifié |

## Installation

1. Fermer OpenConcerto.
2. Copier `org.openconcerto.modules.project-1.1.jar` dans le dossier **Modules**
   (un seul jar de ce module).
3. Redémarrer, ouvrir **Paramètres → Libellés des colonnes**.

Mode d'emploi : `docs/parametres-colonnes.md`. Détail technique du rendu :
`src/org/openconcerto/modules/project/ColumnLabelStyle.java`.
