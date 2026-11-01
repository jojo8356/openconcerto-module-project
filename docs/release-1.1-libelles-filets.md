# Module project 1.1 — libellés : filets de sécurité dans les listes du cœur

**Ce jar remplace celui de `v1.1-libelles-partout`.** Il vise le dernier cas
signalé : les en-têtes restent inchangés dans **Historique affaires → Articles
commandés**.

## Ce qui est corrigé

1. **Rendu d'en-tête réinstallé** : les listes d'OpenConcerto posent leur propre
   rendu d'en-tête à la construction, ce qui pouvait écraser le nôtre. Le module
   vérifie désormais à chaque passage que son rendu est bien en place, et le
   réinstalle sinon (plus de drapeau « déjà installé » définitif).
2. **Résolution par libellé automatique** : quand une liste n'expose pas
   l'identifiant technique de ses colonnes, une règle sur `ID_FOURNISSEUR` est
   retrouvée grâce à son libellé automatique `FOURNISSEUR`, qui correspond à
   l'en-tête « Fournisseur » affiché par le cœur. Priorité : règle de table, puis
   règle `*`.

## Vérifier sur le poste

Après un enregistrement, la console affiche :

```
[module project] libelles : enregistrement de 1 regle(s), 3 colonne(s) rafraichie(s), 4 tableau(x) suivi(s)
```

- `tableau(x) suivi(s) = 0` → aucune liste n'est ouverte : ouvrir une liste,
  puis rouvrir l'écran et enregistrer à nouveau.
- `-Dproject.labels.debug=true` au lancement du client → chaque colonne non
  reconnue est tracée.

## Vérifications

| Suite | Résultat |
|---|---|
| `scripts/run-tests.sh` | `AffairLinkSupportTest` 38, `ColumnLabelRulesTest` **57**, `SupplierOrderToInvoiceSQLInjectorTest` 19 |
| `scripts/test-mutations-colonnes.sh` | **17 contrôles, 0 échec** (mutation 16 : filet supprimé ⇒ échec) |
| compilation contre `OpenConcerto.jar` 1.7.6 (CI) | success |

## Recette

1. **Paramètres → Libellés des colonnes** : ligne `*` / `ID_FOURNISSEUR` →
   saisir `FOURNISSEUR` (attention : la règle actuelle porte `FOURNISSEURES`),
   puis **Enregistrer pour l'équipe**.
2. Ouvrir **Historique affaires → Articles commandés** : l'en-tête passe à
   `FOURNISSEUR` immédiatement.
3. Si ce n'est pas le cas : relever la ligne
   `[module project] libelles : enregistrement …` et les lignes
   `[module project] libelles : …` de la console, et me les transmettre.
