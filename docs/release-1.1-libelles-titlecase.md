# Module project 1.1 — libellés automatiques en « Title », plus en capitales

**Ce jar remplace celui de `v1.1-libelles-filets`.** Il corrige la mise en forme
des libellés **automatiques** : ils s'écrivaient en capitales (`FOURNISSEUR`),
ils suivent maintenant la mise en forme du cœur d'OpenConcerto (`Fournisseur`).

## La cause

La suggestion automatique partait d'un nom de colonne **normalisé en
majuscules** (`ID_FOURNISSEUR`) et se contentait de retirer `ID_` et de remplacer
les `_` : elle produisait donc `FOURNISSEUR`.

Or le cœur d'OpenConcerto n'a jamais d'en-têtes en capitales : il utilise
`SQLFieldTranslator.getDefaultDesc`, qui applique `firstUpThenLow` puis remplace
`_` par une espace. Le module applique désormais **la même règle**, ce qui rend
ses libellés indiscernables de ceux de l'ERP.

## Ce qui change

| Colonne | Avant | Après |
|---|---|---|
| `ID_FOURNISSEUR` | `FOURNISSEUR` | **`Fournisseur`** |
| `ID_CLIENT` | `CLIENT` | **`Client`** |
| `ID_ETAT_AFFAIRE` | `ETAT AFFAIRE` | **`Etat affaire`** |
| `ID_FACTURE_FOURNISSEUR` | `FACTURE FOURNISSEUR` | **`Facture fournisseur`** |
| `ID_USER_COMMON_CREATE` | `USER COMMON CREATE` | **`User common create`** |
| `TOTAL_HT`, `DATE` | inchangés | inchangés (pas une clé étrangère) |

- Les libellés **que vous avez saisis** ne sont pas touchés : une règle
  `FOURNISSEURES` reste `FOURNISSEURES` jusqu'à ce que vous la corrigiez
  (double-clic → `FOURNISSEUR` → **Enregistrer pour l'équipe**).
- Les accents ne sont pas inventés (`ETAT` reste `Etat`) : le cœur ne les
  devine pas non plus.

## Vérifications

| Suite | Résultat |
|---|---|
| `scripts/run-tests.sh` | `AffairLinkSupportTest` 38, `ColumnLabelRulesTest` **58**, `SupplierOrderToInvoiceSQLInjectorTest` 19 |
| `scripts/test-mutations-colonnes.sh` | **18 contrôles, 0 échec** — mutation 17 remet les capitales et fait échouer la suite |
| `tests/sql/e2e-colonnes.sh` | 34 contrôles, 0 échec |
| compilation contre `OpenConcerto.jar` 1.7.6 (CI) | success |

## Recette

1. **Paramètres → Libellés des colonnes** : la colonne `Automatique` affiche
   `Fournisseur`, `Mouvement`, `Salaire`, `User common create`… (plus aucune
   capitale).
2. Corriger la ligne `*` / `ID_FOURNISSEUR` en `FOURNISSEUR`, **Enregistrer pour
   l'équipe**.
3. Ouvrir **Historique affaires → Articles commandés** : l'en-tête affiche
   `FOURNISSEUR`.
4. Supprimer la règle (double-clic → vider → Entrée) : l'en-tête revient à
   `Fournisseur`, sans redémarrage.
