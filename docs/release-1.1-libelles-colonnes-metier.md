# Module project 1.1 — les libellés s'appliquent enfin partout

**Ce jar remplace celui de `v1.1-fermeture-historique`.**

## Le problème corrigé

Dans **Historique affaires → Articles commandés** (capture : colonnes
`Référence`, `Fournisseur`, `Code …`, `Désignation`), les en-têtes ne suivaient
pas les règles saisies. La raison : ces colonnes affichent déjà un **libellé
métier** (« Fournisseur ») alors que la règle porte sur le nom technique
(`ID_FOURNISSEUR`). Le module compare désormais les deux.

## Ce qui change

- Lecture de l'identifiant technique de chaque colonne de liste
  (`FieldPath "COMMANDE_ELEMENT"."ID_COMMANDE"."ID_FOURNISSEUR"` par exemple) :
  une règle `*.ID_FOURNISSEUR` s'applique à **toutes** les colonnes de ce champ,
  y compris celles affichées « Fournisseur ».
- Priorité : `TABLE.CHAMP` > `*.CHAMP` > `TABLE.EN-TÊTE` > `*.EN-TÊTE` >
  automatique > en-tête d'origine.
- Le mode `AUTO` **ne dégrade plus** les listes du cœur : « Fournisseur » reste
  « Fournisseur » ; seuls les en-têtes techniques (`ID_CLIENT`) sont simplifiés.

## Vérifications

| Suite | Résultat |
|---|---|
| `scripts/run-tests.sh` | `AffairLinkSupportTest` 38, `ColumnLabelRulesTest` **56**, `SupplierOrderToInvoiceSQLInjectorTest` 19 |
| `scripts/test-mutations-colonnes.sh` | **16 contrôles, 0 échec** (mutations 14 et 15 détectées) |
| `tests/sql/e2e-colonnes.sh` | 34 contrôles, 0 échec |
| compilation contre `OpenConcerto.jar` 1.7.6 (CI) | success |

## Recette

1. **Paramètres → Libellés des colonnes**, ligne `*` / `ID_FOURNISSEUR`, saisir
   `FOURNISSEUR` (au singulier), **Enregistrer pour l'équipe**.
2. Ouvrir **Historique affaires → Articles commandés** : l'en-tête devient
   `FOURNISSEUR` immédiatement, sans redémarrer.
3. Ouvrir **Achats → Factures fournisseurs** : même libellé.

Mode d'emploi : `docs/parametres-colonnes.md` (§7 et suivants).
