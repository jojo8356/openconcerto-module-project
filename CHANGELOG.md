# Changelog

## 1.4 - 2026-10-10

### Added

- A `N° commande fournisseur` column in the `Factures fournisseurs` tab of the affair history window, so each supplier invoice can be matched with the supplier order it comes from (same `NUMERO` as displayed in the `Commandes fournisseurs` tab).

### Behavior

- The order number is resolved first through the OpenConcerto transfer table `TR_COMMANDE` (filled by the order-to-invoice transfer), then through the invoice lines (`FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT` -> `COMMANDE_ELEMENT.ID_COMMANDE`) as a fallback.
- Invoices built from several orders show all order numbers, separated by commas.
- Invoices entered manually (no linked order) show an empty cell.
- The column is inserted right after the invoice number column and degrades gracefully when the optional tables or fields are missing.

### Preserved

- `module.properties` stays at version `1.1` to avoid the module metadata issue in existing databases.

### Validation

- `AffairListSortSupportTest` passes.
- The new history column code compiles with `javac` targeting Java 8.

## 1.3 - 2026-08-05

### Added

- Automated tests for the affair history selector sort behavior.
- A lightweight `scripts/run-tests.sh` test runner for the extracted sort logic.

### Changed

- Extracted affair-list sort rules into a small testable support class.
- Centralized the default sort constants so the visible combo selection and the initially applied comparator stay aligned.

### Validation

- `sh scripts/run-tests.sh`
- `./scripts/build-java8-compatible.sh`
- Java bytecode verification: all classes are classfile major version `52` or lower.

### Artifact

- `build/org.openconcerto.modules.project-1.3.jar`

## 1.2 - 2026-07-30

### Added

- Professional release documentation for the default affair-name sort feature.

### Changed

- The history screen's affair selector now defaults to `Tri par nom`.
- The initial comparator installed on the affair selector now matches the visible default selection.
- The build script now derives the JAR version from `module.properties`, reducing release-version drift.

### Preserved

- Users can still switch manually to `Tri par date`.
- Closed affairs remain hidden by default through `Masquer dossiers clos`.
- Date rendering in the affair selector remains unchanged when affair dates are available.

### Validation

- `./scripts/build-java8-compatible.sh`
- Java bytecode verification: all classes are classfile major version `52` or lower.

### Artifact

- `build/org.openconcerto.modules.project-1.2.jar`
- `/home/jojokes/.local/share/OpenConcerto/Modules/org.openconcerto.modules.project-1.2.jar`

## 1.1 - 2026-07-08

### Changed

- Integrated the previous runtime patch behavior directly into source-controlled Java code.
- Added affair history sorting controls, closed-affair filtering, direct affair modification, optional-table tolerance, family filters, supplier display corrections, and Java 8 compatible packaging.
