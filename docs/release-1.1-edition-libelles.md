# Module project 1.1 — libellés des colonnes : édition directe

**Ce jar remplace celui de `v1.1-menu-parametres`** : même écran, mais on
modifie maintenant les noms **directement dans le tableau**, et la case
« Libellé affiché » montre enfin quelque chose.

## Ce qui change dans l'écran

| Avant | Maintenant |
|---|---|
| La case **Libellé affiché** était vide tant qu'aucune règle n'existait | elle affiche **le libellé réellement vu par les utilisateurs** |
| Il fallait passer par « Ajouter une colonne… » ou deviner | **double-clic** sur la case, on tape, **Entrée** |
| Rien ne distinguait une règle d'un libellé automatique | **gras** = personnalisé, texte normal = automatique |
| Les libellés automatiques étaient en gris pâle, difficiles à lire | **tout est en noir** (`ColumnLabelStyle`) |
| « Supprimer la règle » supprimait la ligne | **Réinitialiser (libellé auto)** : la règle est effacée, le libellé automatique revient |

Le tableau a quatre colonnes : **Table**, **Colonne**, **Automatique** (ce que
donnerait la suppression du préfixe `ID_`) et **Libellé affiché (double-clic)**.

## Mode d'emploi

1. **Paramètres → Libellés des colonnes** (compte le mieux doté de la base).
2. Chercher la ligne avec **Filtrer** (`facture`, `client`, `affaire`…).
3. **Double-cliquer** dans la colonne « Libellé affiché », taper le texte,
   **Entrée**. `Échap` annule. Le texte est pré-sélectionné : taper remplace tout.
   On peut aussi taper directement sur la case sélectionnée, ou presser **F2**.
4. **Vider** la case (ou bouton **Réinitialiser**) = retour à l'automatique.
5. **Enregistrer pour l'équipe** : écrit sur le serveur SQL, met à jour les
   listes ouvertes sur ce poste ; les autres postes suivent au redémarrage.
   Fermer sans enregistrer déclenche une confirmation.

Détail important : un texte **inchangé** ne crée pas de règle. Cliquer dans une
case puis valider ne remplit donc pas la table de centaines de règles identiques
au libellé automatique.

## Vérifications

| Suite | Résultat |
|---|---|
| `scripts/run-tests.sh` | `AffairLinkSupportTest` 35, `ColumnLabelRulesTest` **47**, `SupplierOrderToInvoiceSQLInjectorTest` 19 |
| `scripts/test-mutations-colonnes.sh` | **11 contrôles, 0 échec** (mutations 8, 9 et 10 : case vide, règles inutiles, gris pâle) |
| `tests/sql/e2e-colonnes.sh` | 34 contrôles, 0 échec |
| compilation contre le vrai `OpenConcerto.jar` | aucune erreur imputable au module (CI) |

## Installation

1. Fermer OpenConcerto.
2. Copier `org.openconcerto.modules.project-1.1.jar` dans le dossier **Modules**
   (un seul jar de ce module).
3. Redémarrer, se connecter avec le compte le mieux doté, ouvrir
   **Paramètres → Libellés des colonnes**.

Mode d'emploi complet : `docs/parametres-colonnes.md`. Recette cliquable :
`docs/recette-graphique-colonnes.md`.
