# Changelog

> **La version qui compte pour OpenConcerto est celle de `module.properties`**
> (installée en `1.2` ; prochaine version publiée : `1.5`, les tags `v1.1` à
> `v1.4` étant déjà pris). C'est elle que le client compare à la base pour
> savoir s'il doit rejouer l'installation SQL du module, et elle ne doit jamais
> redescendre. Les sections ci-dessous sont datées ; la version publiée est
> précisée dans le titre des sections de release.
> Voir `docs/release-process.md`.

## 2026-10-26 — Affaire sur les documents fournisseurs : audit et correctif

### Fixed

- **Facture fournisseur absente de la liste des tables à affaire**
  (`Module.listTableAffaire`) : elle n'avait donc ni colonne « Affaire » dans la
  liste de l'ERP, ni action « Historique affaire », et sa colonne n'était jamais
  créée lors de l'installation. La liste du module vient maintenant de
  `AffairLinkSupport.DIRECT_AFFAIR_TABLES`, qui la contient.
- **Colonnes `ID_AFFAIRE` réparées à chaque démarrage**
  (`Module.ensureAffairColumns`) : jusqu'ici elles n'étaient créées qu'à la
  première installation du module, puis pour quatre tables seulement
  (`COMMANDE`, `SAISIE_ACHAT`, `AVOIR_FOURNISSEUR`… pouvaient rester sans
  colonne, donc sans affaire enregistrable).
- **Création de colonne non bloquée par les affaires supprimées** : la colonne
  est ajoutée seule, puis la contrainte `FOREIGN KEY … NOT VALID`. Un document
  pointant vers une affaire inexistante ne peut plus empêcher la création de la
  colonne (l'ancien `ADD COLUMN … REFERENCES` échouait entièrement et l'erreur
  n'était qu'imprimée dans la console).
- **Historique des affaires : plus de boucle de filtrage cassée**
  (`ProjectHistory.putAffairTab`). Un onglet dont la table n'a pas `ID_AFFAIRE`
  et aucun parent rattachable est ignoré avec un message, au lieu de faire lever
  une exception à `ListeHistoriquePanel` — exception qui laissait **tous les
  onglets suivants** non filtrés (donc invisibles).
- **Lignes des commandes/bons de réception rattachées par leur document** : le
  filtrage passe par le document parent même quand la table de lignes porte sa
  propre colonne `ID_AFFAIRE`, sinon les lignes dont l'affaire de ligne est vide
  (le cas normal) disparaissaient de l'historique.
- Action « Modifier » disponible sur les factures fournisseurs et les achats
  depuis l'historique des affaires.

### Added

- `AffairLinkSupport` : règles pures et testables du rattachement à une affaire
  (tables concernées, plan de filtrage d'un onglet, colonnes manquantes, champs
  à exposer dans les écrans).
- `AffairLinkSupportTest` : 35 tests.
- `tests/sql/e2e-affaire-fournisseur.sh` : 26 contrôles de bout en bout sur
  PostgreSQL (pglite), avec la base « installation existante » et la migration.
- `tests/sql/migration-affaire-fournisseur.sql` : DDL de référence, idempotent,
  index inclus, contraintes `NOT VALID`.
- `scripts/diagnostic-affaire-fournisseur.sh` : diagnostic **lecture seule** de
  la base du client (colonnes manquantes, lignes sans affaire, lignes cachées,
  affaires inexistantes, mode démonstration `--pglite`).
- `tests/sql/scenario-creation-fournisseur.sh` : **scénario complet de 71
  contrôles** — création d'une affaire, saisie d'une commande fournisseur
  rattachée (en-tête + lignes), transfert en facture fournisseur rattachée,
  modification de l'affaire d'un document déjà enregistré (changement d'affaire,
  retrait), garde-fous (affaire « Indéfinie », affaire inexistante, affaire
  supprimée), puis **une requête par onglet de l'historique**, dans l'ordre de
  `ProjectHistory` : c'est la reproduction de la boucle de
  `ListeHistoriquePanel` qui cassait.
- `scripts/test-affaire-fournisseur.sh` : suite complète en une commande
  (Java + e2e + scénario + mutations), avec `--sans-java` et
  `--sans-mutations`.
- `scripts/test-mutations-affaire.sh` : 10 tests de mutation (ajout de
  « scénario sans migration » et « base client sans colonne sur les factures
  fournisseurs »).
- `docs/audit-affaire-fournisseur.md` : rapport d'audit complet.

### Validation

- `sh scripts/run-tests.sh` : 35 + 16 tests OK.
- `sh tests/sql/e2e-affaire-fournisseur.sh` : 26 contrôles, 0 échec.
- `sh tests/sql/scenario-creation-fournisseur.sh` : 71 contrôles, 0 échec.
- `sh scripts/test-mutations-affaire.sh` : 10 contrôles, 0 échec.
- `sh scripts/test-affaire-fournisseur.sh` : 4 suites, 0 échec.
- Compilation de vérification Java 8 (ECJ `-source 1.8 -target 1.8`).

## 2026-10-24 — Affaire reprise lors du transfert commande fournisseur → facture

### Added

- Le transfert **Commandes fournisseurs → Factures fournisseurs** recopie
  maintenant `COMMANDE.ID_AFFAIRE` dans `FACTURE_FOURNISSEUR.ID_AFFAIRE` tout en
  conservant l’injecteur natif OpenConcerto pour les autres champs et les lignes.
  Les lignes de facture dont `ID_AFFAIRE` est vide ou indéfini reprennent aussi
  l’affaire de leur commande ; une affaire de ligne déjà définie est conservée.
- L’en-tête de l’écran de facture fournisseur expose maintenant le champ
  **Affaire**, afin de voir la valeur reprise avant l’enregistrement.
- `SupplierOrderToInvoiceSQLInjectorTest` : 16 tests de contrat couvrant la
  copie de l’affaire dans l’en-tête et les lignes, la préservation des affaires
  de ligne définies, l’enregistrement de l’injecteur et du champ d’en-tête, les
  valeurs vides et indéfinies, les transferts successifs et groupés, ainsi que
  les schémas sans colonne `ID_AFFAIRE`.
- Procédure de recette graphique :
  `docs/test-transfert-commande-fournisseur-facture.md`.

### Compatibility

- `module.properties` reste volontairement en `version=1.1` pour correspondre à
  la version du module enregistrée dans la base installée. Ce correctif ne
  demande aucune migration de version de la DB et produit
  `org.openconcerto.modules.project-1.1.jar`.

### Validation

- `AffairListSortSupportTest` : OK.
- `SupplierOrderToInvoiceSQLInjectorTest` : 16 tests OK.

## Module project 1.5 - 2026-10-22 (à publier)

### Added

- `scripts/fix-module-version.sh` : diagnostic et correction de la version du
  module épinglée en base. Quand le jar est remplacé, la base garde l'ancienne
  version (`FWK_MODULE_METADATA` + préférence `modules/required`) et le client
  refuse de démarrer avec `NO_FACTORY=[Module … v1.1]`. Le script aligne la
  base sur la version du jar (transaction SQL, idempotente, lecture seule par
  défaut).

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
