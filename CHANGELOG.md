# Changelog

> **La version qui compte pour OpenConcerto est celle de `module.properties`**
> (installée en `1.2` ; prochaine version publiée : `1.5`, les tags `v1.1` à
> `v1.4` étant déjà pris). C'est elle que le client compare à la base pour
> savoir s'il doit rejouer l'installation SQL du module, et elle ne doit jamais
> redescendre. Les sections ci-dessous sont datées ; la version publiée est
> précisée dans le titre des sections de release.
> Voir `docs/release-process.md`.

## Module project 1.5 - 2026-10-22 (à publier)

### Added

- `scripts/build-release.sh` : préparation d'une release (bump de version,
  compilation Java 8, jar dans `dist/`, tag Git, push) et publication d'une
  **release GitHub avec le jar compilé en pièce jointe**.
- `docs/release-process.md` : pourquoi OpenConcerto inscrit les modules dans
  `FWK_MODULE_METADATA`, comment le numéro de version est utilisé au
  démarrage, et la procédure de publication pas à pas.

### Fixed

- `FWK_MODULE_METADATA` : le numéro de version enregistré pour les colonnes
  `ID_AFFAIRE` créées par le module suit maintenant la version déclarée du
  module (il était codé en dur à `1.0` alors que le module est en `1.2`).

### Changed

- Le transfert « demande de prix » → « commande fournisseur » reprend les
  prix de la demande de prix comme **valeurs de départ** (convention du core
  OpenConcerto) au lieu de les vider : `T_PA_HT` est `NOT NULL` dans
  `COMMANDE_ELEMENT`. Les totaux sont recalculés par le client.

## 2026-10-22 — Transfert « demande de prix » → « commande fournisseur »

### Added

- Bouton « Transfert en commande fournisseur » dans l'onglet « Demandes de
  prix » de l'historique des affaires (sélection d'une seule demande).
- Transfert complet : en-tête (fournisseur, date, affaire) et lignes
  (désignation, quantité, article, unité) recopiés vers une nouvelle commande
  fournisseur.
- Table de transfert `TR_DEMANDE_PRIX` créée **automatiquement** par le core
  OpenConcerto (rien à faire en SQL, rien à créer à la main).
- Documentation : `docs/transfert-demande-prix-commande.md`,
  `docs/test-transfert-demande-prix-interface-graphique.md`,
  `docs/message-pere-demande-prix-commande.md`.

### Validation

- Bouton visible dans le client 1.7.6 (« Gestion Projet v1.2 — Démarré »).
- `scripts/structure-demande-prix.sh --mode docker` : `TR_DEMANDE_PRIX`
  présente, avec `ID_DEMANDE_PRIX` → `DEMANDE_PRIX` et `ID_COMMANDE` →
  `COMMANDE`.
- `scripts/panel-tests-docker.sh --stack ~/oc-176-docker` : aucun échec.

## 2026-10-10 — N° commande fournisseur dans l'historique des factures

### Added

- A `N° commande fournisseur` column in the `Factures fournisseurs` tab of the affair history window, so each supplier invoice can be matched with the supplier order it comes from (same `NUMERO` as displayed in the `Commandes fournisseurs` tab).

### Behavior

- The order number is resolved first through the OpenConcerto transfer table `TR_COMMANDE` (filled by the order-to-invoice transfer), then through the invoice lines (`FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT` -> `COMMANDE_ELEMENT.ID_COMMANDE`) as a fallback.
- Invoices built from several orders show all order numbers, separated by commas.
- Invoices entered manually (no linked order) show an empty cell.
- The column is inserted right after the invoice number column and degrades gracefully when the optional tables or fields are missing.

### Validation

- `AffairListSortSupportTest` passes.
- The new history column code compiles with `javac` targeting Java 8.

## 2026-08-05 — Tri du sélecteur d'affaires

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

## 2026-07-30 — Tri par défaut et documentation de release

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

## 2026-07-08 — Historique des affaires

### Changed

- Integrated the previous runtime patch behavior directly into source-controlled Java code.
- Added affair history sorting controls, closed-affair filtering, direct affair modification, optional-table tolerance, family filters, supplier display corrections, and Java 8 compatible packaging.
