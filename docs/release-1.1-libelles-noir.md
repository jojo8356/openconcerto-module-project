# Module project 1.1 — libellés : noir, message clair, règle « * »

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

## Message de fin d'enregistrement

L'ancien message disait « 0 colonne(s) mise(s) à jour sur ce poste », ce qui
laissait croire que la modification n'avait pas été prise en compte. Il sépare
maintenant :

- **le nombre de règles écrites en base** (partagées par toute l'équipe) ;
- **le nombre de colonnes rafraîchies sur ce poste** (0 quand aucune liste
  ouverte n'affiche ces colonnes : normal).

## Tables de sauvegarde

Une règle posée sur une table de sauvegarde (`sauvegarde_FACTURE_FOURNISSEUR_avant_…`,
`…_old`, `…_copie`) est enregistrée mais **n'a aucun effet visible** : ces tables
n'apparaissent dans aucune liste. Le module le signale désormais explicitement et
rappelle l'existence du bouton **« Appliquer à toutes les tables (*) »**, qui crée
la règle `*.COLONNE` à partir de la ligne sélectionnée — un seul geste pour
renommer `ID_FOURNISSEUR` dans toutes les listes.

## Vérifications

| Suite | Résultat |
|---|---|
| `scripts/run-tests.sh` | `AffairLinkSupportTest` 35, `ColumnLabelRulesTest` **50**, `SupplierOrderToInvoiceSQLInjectorTest` 19 |
| `scripts/test-mutations-colonnes.sh` | **13 contrôles, 0 échec** — mutations 10, 11 et 12 (gris pâle, avertissement supprimé, faux positifs) détectées |
| compilation contre `OpenConcerto.jar` 1.7.6 (CI) | success, bytecode Java 8 vérifié |

## Installation

1. Fermer OpenConcerto.
2. Copier `org.openconcerto.modules.project-1.1.jar` dans le dossier **Modules**
   (un seul jar de ce module).
3. Redémarrer, ouvrir **Paramètres → Libellés des colonnes**.

Mode d'emploi : `docs/parametres-colonnes.md`. Détail technique du rendu :
`src/org/openconcerto/modules/project/ColumnLabelStyle.java`.
