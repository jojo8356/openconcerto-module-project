# Release 1.4 - Supplier Invoice Order Number Column

**Release date:** 2026-10-10  
**Module id:** `org.openconcerto.modules.project`  
**Module version (database-facing):** `1.1` (unchanged on purpose)  
**Primary artifact:** `org.openconcerto.modules.project-1.1.jar`

## Executive Summary

In the affair history window, the `Factures fournisseurs` tab now displays a
`N° commande fournisseur` column. Each supplier invoice shows the number of the
supplier order (`COMMANDE.NUMERO`) it was created from, exactly as that number
appears in the `Commandes fournisseurs` tab. This makes it possible to identify
which order every supplier invoice corresponds to.

## Implementation Details

Updated files:

- `src/org/openconcerto/modules/project/ProjectHistory.java`
- `CHANGELOG.md`

New behavior in `ProjectHistory`:

- `installSupplierInvoiceOrderNumberColumn` adds a computed column to every
  `FACTURE_FOURNISSEUR` list of the history window.
- The column is inserted directly after the invoice `Numéro` column when that
  column can be located, otherwise it is appended at the end.

## Order Resolution Strategy

The supplier order number is resolved through two links, in order:

1. **Transfer link (primary).** OpenConcerto records every
   `Commande fournisseur -> Facture fournisseur` transfer in the `TR_COMMANDE`
   table (`ID_COMMANDE` / `ID_FACTURE_FOURNISSEUR`). This is the canonical
   source and covers all invoices created with the standard transfer action.
2. **Invoice line link (fallback).** When no transfer row exists, the column
   falls back to the invoice lines:
   `FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT` ->
   `COMMANDE_ELEMENT.ID_COMMANDE` -> `COMMANDE.NUMERO`. This reuses the
   `ID_COMMANDE_ELEMENT` column added by the
   `fix-facture-fournisseur-element` correction shipped earlier in this
   repository.

Additional rules:

- Several distinct orders on one invoice are joined with `, `.
- Duplicate numbers are shown only once.
- Manually entered invoices with no linked order display an empty cell.
- Both links are declared through `getPaths()`, so the data is fetched with the
  list query itself (no per-row SQL round trip), following the same pattern as
  the existing `Temps Total` and supplier-name columns.

## Robustness

The installer degrades gracefully and simply skips the column when:

- the `COMMANDE` table or its `NUMERO` field is absent;
- neither `TR_COMMANDE` (with both foreign keys) nor the
  `FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT` /
  `COMMANDE_ELEMENT.ID_COMMANDE` chain is available.

This keeps the module startup tolerant on databases that miss the optional
tables, consistent with the rest of `ProjectHistory`.

## Versioning Note

As agreed, `module.properties` remains at version `1.1` so that existing
databases keep their module metadata untouched. Only the changelog and this
document advance the documentation version.

## Validation

- `AffairListSortSupportTest` passes (`scripts/run-tests.sh` logic executed
  with a Java 8 compiler).
- The new `ProjectHistory` code compiles with `javac` 1.8 (`-source 8
  -target 8`).
- The full module build (`scripts/build-java8-compatible.sh`) requires a local
  `OpenConcerto.jar` and must be run on a machine where it is installed, as
  usual.
