# Patch Integration Revision Report

**Project:** OpenConcerto Project Module  
**Revision date:** 2026-07-07  
**Prepared by:** Codex  
**Scope:** Replacement of runtime/JAR bytecode patching with maintainable source-level implementation, validated build, local module deployment, and post-review UI refinements for Kinetic Therm.

## Executive Summary

This revision removes the post-build patching mechanism previously represented by `PatchProjectJar.java` and `ProjectHistoryPatch.java`. The behavior implemented by those patch classes has been integrated directly into the module source code. The result is a simpler, reviewable, source-controlled implementation that no longer depends on ASM bytecode rewriting or patch-only helper classes.

The revision affects the project history UI, project list ordering, closed-affair visibility, supplier purchase balance computation, supplier article-list presentation, generated documentation inventory, and the installed OpenConcerto module JAR. No patch-oriented Java sources remain in the project tree, and the deployed module JAR no longer contains `ProjectHistoryPatch` or `PatchProjectJar` classes.

## Research Basis

The review format and quality criteria used for this report were informed by current engineering guidance gathered through targeted web research:

| Source | Applied Principle |
| --- | --- |
| Google Engineering Practices, "Writing good CL descriptions" | A change record should explain what changed, why it changed, implementation context, and known limitations. |
| Google Engineering Practices, "What to look for in a code review" | Review should cover design, functionality, complexity, tests, naming, documentation, consistency, and system context. |
| Google Engineering Practices, "Small CLs" | A reviewable change should be self-contained, understandable from its code and description, and safe to roll back. |
| Martin Fowler, "Continuous Integration" | Source should remain buildable and integration should be verified with automated build/test feedback where dependencies are available. |
| Atlassian, "What are code reviews and how they actually save time" | Code review should reduce defects, improve maintainability, and share implementation knowledge across the team. |

References are listed at the end of this document.

## Original Problem

The project contained Java sources whose purpose was not normal module functionality but post-processing:

- `src/org/openconcerto/modules/project/PatchProjectJar.java`
- `src/org/openconcerto/modules/project/ProjectHistoryPatch.java`

`PatchProjectJar.java` modified compiled classes inside the output JAR using ASM. This created several maintainability problems:

- The effective runtime behavior was not fully visible in the production source classes.
- Rebuilding or packaging required a separate patch step.
- Reviewers had to understand bytecode instrumentation instead of ordinary Java logic.
- The module could drift between source behavior and packaged behavior.
- `.class` patching made debugging and future refactoring harder.

The requested outcome was to inspect all patch behavior, implement it directly in the project, avoid executable `.class` patching, and delete the Java patch sources afterward.

## Change Inventory

| Area | File | Status |
| --- | --- | --- |
| Project history UI, filtering, and supplier list presentation | `src/org/openconcerto/modules/project/ProjectHistory.java` | Updated |
| Project list fields | `src/org/openconcerto/modules/project/element/ProjectSQLElement.java` | Updated to use `DATE` as a visible list field and remove the former start-date field |
| Purchase balance computation | `src/org/openconcerto/modules/project/panel/HistoriqueAffaireBilanPanel.java` | Updated |
| Performance review | `docs/history-loading-performance-audit.md` | Added |
| Patch JAR utility | `src/org/openconcerto/modules/project/PatchProjectJar.java` | Deleted |
| Runtime patch helper | `src/org/openconcerto/modules/project/ProjectHistoryPatch.java` | Deleted |
| Source tree documentation | `docs/source-tree-analysis.md` | Updated |
| Component inventory documentation | `docs/component-inventory.md` | Updated |
| Installed module JAR | `/home/jojokes/.local/share/OpenConcerto/Modules/org.openconcerto.modules.project-1.1.jar` | Rebuilt and replaced |

## Detailed Technical Review

### 1. Runtime Patch Removal

The ASM-based patch utility was removed. The previous bytecode rewriting responsibilities were moved into normal source files.

Removed files:

- `src/org/openconcerto/modules/project/PatchProjectJar.java`
- `src/org/openconcerto/modules/project/ProjectHistoryPatch.java`

Post-change validation confirms:

- No `*patch*` files remain in the project.
- No `.class` files remain in the project.
- No source references remain to `PatchProjectJar`, `ProjectHistoryPatch`, or `org.objectweb.asm`.
- The installed module JAR no longer contains `ProjectHistoryPatch` or `PatchProjectJar`.

### 2. Project History Table Registration

`ProjectHistory.java` now registers the optional history tables directly in the constructor.

Relevant implementation:

- `BON_DE_LIVRAISON` is added as "Bons de livraison clients" when present.
- Supplier `COMMANDE` is exposed as "Commandes fournisseurs" when present.
- Supplier `BON_RECEPTION` is exposed as "Bons de réception fournisseurs" when present.
- Optional table lookup is protected by `putIfTableExists(...)` to preserve startup tolerance across customer databases.

Primary locations:

- `ProjectHistory.java:111-129`
- `ProjectHistory.java:540-550`

Review assessment:

- The behavior is now explicit and source-level.
- Optional schema handling is preserved.
- The original customer-database tolerance from the patch helper is retained.

### 3. Project History UI Controls

`ProjectHistory.java` now installs the history UI controls immediately after the history panel frame is created.

Primary locations:

- `ProjectHistory.java:344-346`
- `ProjectHistory.java:514-537`

Implemented behavior:

- Normalizes default row action labels from internal display values to `Afficher`.
- Enables modification actions for `AFFAIRE`, `BON_DE_LIVRAISON`, `COMMANDE`, and `BON_RECEPTION`.
- Adds a left-side project list wrapper with:
  - checkbox: "Masquer dossiers clos"
  - sort selector: "Tri par date" / "Tri par nom"
  - "Modifier l'affaire" action button
- Applies the default date-based affair sort.
- Hides closed affairs by default in the left affair selector.
- Installs a date-aware renderer for the project list.

Review assessment:

- The patch hook previously injected into `ProjectHistory` construction is now a direct method call.
- UI behavior is discoverable in the owning class.
- Existing French UI labels are preserved for user-facing consistency.
- The closed-affair filter is user-controllable and reversible without changing the database.

### 4. Closed-Affair Visibility Checkbox

The new checkbox `Masquer dossiers clos` is displayed immediately to the left of the sort selector in the history screen's left-side affair selector.

Primary locations:

- `ProjectHistory.java:604-622`
- `ProjectHistory.java:675-700`

Implemented behavior:

- The checkbox is selected by default.
- When selected, closed affairs are excluded from the left-side affair selector.
- When unselected, closed affairs are shown again in the selector.
- The setting is applied together with the active sort mode, so changing either the checkbox or the sort selector refreshes the same affair-list model.
- The filter only affects the affair selector list, not the underlying database rows and not the persisted affair state.

Technical mechanism:

```java
Where where = new Where(model.getTable().getKey(), "!=", model.getTable().getUndefinedID());
if (hideClosedProjects && model.getTable().contains("ID_ETAT_AFFAIRE")) {
    where = where.and(new Where(model.getTable().getField("ID_ETAT_AFFAIRE"), "!=", ProjectStateSQLElement.DOSSIER_CLOS));
}
```

The closed state is therefore identified by `ProjectStateSQLElement.DOSSIER_CLOS`, currently value `6`, through the `AFFAIRE.ID_ETAT_AFFAIRE` column.

Review assessment:

- The default view is cleaner for day-to-day use because closed dossiers are hidden.
- The user can still access closed dossiers by clearing the checkbox.
- The implementation is defensive: if a customer schema does not expose `ID_ETAT_AFFAIRE`, the closed-affair predicate is skipped.
- The filter is intentionally scoped to the left affair selector. It does not delete, mutate, or reclassify any affair.

### 5. Affair List Sorting and Rendering

The project list now supports date/name sorting and richer display text directly inside `ProjectHistory.java`.

Primary locations:

- `ProjectHistory.java:588-630`
- `ProjectHistory.java:632-656`
- `ProjectHistory.java:658-676`
- `ProjectHistory.java:748-870`
- `ProjectHistory.java:873-919`

Implemented behavior:

- Date sort uses only `AFFAIRE.DATE`, in descending order, with null dates last.
- When dates are equal, the fallback ordering uses `NUMERO`.
- Name sort uses a normalized affair label built from `NUMERO`, client name, and `NOM`.
- Display text includes the formatted date when available.
- Undefined rows are hidden from the project selector after list updates.
- The date comparator no longer falls back to `model.getTable().getRow(item.getId())` for each affair when `DATE` is missing from the combo item; it relies on the row values already loaded by the `ComboSQLRequest`.
- The date and name comparators preload affair sort data in one SQL query (`ID`, `DATE`, `NUMERO`, `NOM`, client name), then compare from that in-memory map.
- The preloading query now checks whether `CLIENT.NOM_COURT` exists before selecting it; Kinetic Therm's `CLIENT` table exposes `NOM` but not `NOM_COURT`.
- The expected default date order is therefore aligned with `ORDER BY "DATE" DESC NULLS LAST, "NUMERO"`.
- The list renderer caches rendered display text by affair ID and clears the cache on list data changes.
- The renderer cache avoids repeated `row.getForeign("ID_CLIENT")` work during repaint and scroll.

Review assessment:

- The behavior matches the intent of the prior runtime patch.
- The final algorithm intentionally ignores the former start-date field; this was corrected after database inspection on `OpenConcertoKineticTherm`.
- The expected ordering is equivalent to `ORDER BY "DATE" DESC NULLS LAST, "NUMERO"`.
- The performance audit file `/home/jojokes/Documents/reparation_pere/audit_performance_historique_affaires_20260707.md` identified row-by-row fetches and repeated renderer client resolution as likely hotspots; those safe corrections have been applied.
- Reflection is still used for `JListSQLTableModel` internals, which should be treated as a compatibility risk if OpenConcerto internals change.

### 6. Project List Fields and Date Column

`ProjectSQLElement.java` no longer injects the former start-date field into the project list fields. It now adds `DATE` directly to the affair list fields, immediately after `NUMERO`, so the business date can appear as a normal column in the affairs list.

Primary location:

- `ProjectSQLElement.java:46-50`

Review assessment:

- The list-field behavior no longer exposes or depends on the former start-date field.
- This keeps the module aligned with the final business rule: use only `DATE` for project history ordering.
- `DATE` is now part of the list model, enabling a visible `Date` column in OpenConcerto.
- The French label already existed in `labels_fr.xml` as `<FIELD name="DATE" label="Date" />`, so no label addition was required.

### 7. Supplier Purchase Balance Fix

`HistoriqueAffaireBilanPanel.java` now reads invoice item rows from `modelFitem` during the `modelFitem` loop.

Primary location:

- `HistoriqueAffaireBilanPanel.java:218-221`

Previous behavior:

- The loop iterated over `modelFitem` but read rows from `modelF`, which could produce incorrect totals or index errors when the two models had different row counts.

New behavior:

- The loop reads each row from `modelFitem`, matching the iteration source.

Review assessment:

- This is a direct correctness fix.
- The change reduces risk of incorrect purchase totals and out-of-bounds access.

### 8. History Loading Performance Fix

A performance audit was added after runtime testing showed the history screen loaded slowly with Kinetic Therm data.

Primary document:

- `docs/history-loading-performance-audit.md`

Key finding:

- The slow loading was not caused by the `DATE` sort.
- The bottleneck came from eager creation of family-split history views.
- The previous splitter configuration created one internal list panel per `FAMILLE_ARTICLE` row for both `DEMANDE_ACHAT_ELEMENT` and `COMMANDE_ELEMENT`.
- Kinetic Therm currently has 164 article families, so those two split tables can inflate the initial UI by hundreds of internal views.

Final implementation:

- The eager OpenConcerto splitters remain disabled.
- Article families are loaded once when the history panel is built.
- A `Famille article` combo box is added inside each relevant article tab:
  - `Articles commandés`
  - `Articles réceptionnés`
- `Toutes les familles` removes the dynamic family filters.
- Selecting a family applies filters to:
  - `COMMANDE_ELEMENT.ID_FAMILLE_ARTICLE`
  - `BON_RECEPTION_ELEMENT.ID_FAMILLE_ARTICLE`
- The filters are independent per tab and are applied through `ListeHistoriquePanel.addWhere(...)`, so the current selected affair and date filters remain compatible with the family filter.

Review assessment:

- Runtime feedback confirmed the screen loads much faster after removing eager family split-panel creation.
- This validates the audit finding that the first-load problem is primarily UI/model construction, not a slow PostgreSQL affair-date query.
- The family feature is preserved as a dynamic filter instead of startup-created sub-tabs.
- The feature now scales with user interaction rather than with the total number of article families.

### 9. Post-Review Java UI Corrections

After the previous report update, the only Java file modified was:

- `src/org/openconcerto/modules/project/ProjectHistory.java`

The Java-only deltas are:

- In `Articles commandés` (`COMMANDE_ELEMENT`), the misleading `Nom` column is removed from the table source before the table is displayed.
- In `Factures fournisseurs` when backed by `FACTURE_FOURNISSEUR_ELEMENT`, the `Nom` column no longer displays line style labels such as `Normal`, `Titre 1`, or `Titre 2`.
- That supplier invoice item `Nom` column is replaced by a computed column that reads the supplier name through:

```text
FACTURE_FOURNISSEUR_ELEMENT
  -> ID_FACTURE_FOURNISSEUR
  -> ID_FOURNISSEUR
  -> NOM
```

Primary locations:

- `ProjectHistory.java:276-330`
- `ProjectHistory.java:528-538`
- `ProjectHistory.java:601-648`

Review assessment:

- This keeps `Articles commandés` focused on article/order-line information and removes a low-value style-label column.
- The supplier invoice history tab now presents the supplier as the first visible `Nom` value, matching the user's operational expectation for supplier invoice lines.
- The implementation is scoped to the two affected history tables and does not change database schema or persisted data.
- The computed supplier column uses OpenConcerto `FieldPath` metadata so the list model can load the required parent invoice and supplier fields.

### 10. Database Indexes for History Filters

The Kinetic Therm PostgreSQL database was updated with missing history indexes.

Implementation details:

- Indexes were created only when the target column existed.
- Existing indexes were detected through PostgreSQL catalog tables and not duplicated.
- New indexes were added on `ID_AFFAIRE` for the history document tables that previously had no index.
- Existing `ID_FAMILLE_ARTICLE` indexes were detected and kept as-is.

Created `ID_AFFAIRE` indexes:

- `DEVIS.ID_AFFAIRE`
- `COMMANDE_CLIENT.ID_AFFAIRE`
- `SAISIE_VENTE_FACTURE.ID_AFFAIRE`
- `BON_DE_LIVRAISON.ID_AFFAIRE`
- `COMMANDE.ID_AFFAIRE`
- `AVOIR_CLIENT.ID_AFFAIRE`
- `AVOIR_FOURNISSEUR.ID_AFFAIRE`
- `DEMANDE_PRIX.ID_AFFAIRE`
- `SAISIE_ACHAT.ID_AFFAIRE`
- `FACTURE_FOURNISSEUR.ID_AFFAIRE`
- `FACTURE_FOURNISSEUR_ELEMENT.ID_AFFAIRE`
- `DEMANDE_ACHAT_ELEMENT.ID_AFFAIRE`
- `BON_RECEPTION.ID_AFFAIRE`

Verified existing `ID_FAMILLE_ARTICLE` indexes:

- `COMMANDE_ELEMENT.ID_FAMILLE_ARTICLE`
- `DEMANDE_ACHAT_ELEMENT.ID_FAMILLE_ARTICLE`
- `BON_RECEPTION_ELEMENT.ID_FAMILLE_ARTICLE`
- `FACTURE_FOURNISSEUR_ELEMENT.ID_FAMILLE_ARTICLE`

Post-change query plan example:

```text
Index Scan using commande_id_affaire_idx on "COMMANDE"
Index Cond: ("ID_AFFAIRE" = 330)
Execution Time: ~0.142 ms
```

### 11. Documentation Inventory Cleanup

The generated project documentation no longer lists the removed patch sources as active components.

Updated files:

- `docs/source-tree-analysis.md`
- `docs/component-inventory.md`

Review assessment:

- Documentation now matches the project tree.
- This follows the review guidance that deleted or deprecated code should be reflected in associated documentation.

## Validation Performed

| Check | Result |
| --- | --- |
| Search for remaining patch files | Passed: no `*patch*` files remain. |
| Search for compiled class artifacts | Passed: no `.class` files remain. |
| Search for ASM references | Passed: no `org.objectweb.asm` references remain. |
| Search for removed patch class references | Passed: no references to `PatchProjectJar` or `ProjectHistoryPatch` remain. |
| Targeted source inspection | Passed: revised behavior is present in normal source files. |
| Kinetic Therm database inspection | Passed: `OpenConcertoKineticTherm` uses schema `"OpenConcerto42"` and `AFFAIRE.DATE` is a PostgreSQL `date` column. |
| Date-order verification query | Passed: `ORDER BY "DATE" DESC NULLS LAST, "NUMERO"` returns the expected recent affairs first. |
| Visible `DATE` column source check | Passed: `ProjectSQLElement.getListFields()` now adds `DATE` immediately after `NUMERO`. |
| Closed-affair checkbox source check | Passed: `Masquer dossiers clos` is installed in the left history selector and applies `ID_ETAT_AFFAIRE != ProjectStateSQLElement.DOSSIER_CLOS` when selected. |
| Kinetic Therm closed-affair count check | Passed: database inspection found 86 closed affairs and 287 open affairs, confirming the checkbox has meaningful data to filter. |
| History loading performance audit | Passed: the audit identified eager family split-panel creation as the likely bottleneck, and runtime feedback confirmed removing those eager splitters makes loading much faster. |
| Dynamic family filter source check | Passed: article families are loaded once and exposed through tab-local `Famille article` combo boxes on `Articles commandés` and `Articles réceptionnés`. |
| Dynamic family filter behavior | Passed by source inspection: selecting a family applies `ID_FAMILLE_ARTICLE` filters to the active article table (`COMMANDE_ELEMENT` or `BON_RECEPTION_ELEMENT`); selecting all families removes that tab's filter. |
| `Articles commandés` column cleanup | Passed by source inspection: `ProjectHistory` removes the `Nom` column from `COMMANDE_ELEMENT` panels before adding the custom family/status columns. |
| Supplier invoice item supplier name | Passed by source inspection: `ProjectHistory` replaces the `FACTURE_FOURNISSEUR_ELEMENT` `Nom` column with a computed supplier-name column based on `ID_FACTURE_FOURNISSEUR.ID_FOURNISSEUR.NOM`. |
| PostgreSQL history indexes | Passed: missing `ID_AFFAIRE` indexes were created and existing `ID_FAMILLE_ARTICLE` indexes were detected without duplication. |
| PostgreSQL post-index query plan | Passed: `COMMANDE.ID_AFFAIRE = 330` uses `commande_id_affaire_idx`. |
| External performance audit corrections | Passed: no `model.getTable().getRow(item.getId())` fallback remains in affair date/name/number comparator paths; sort data is preloaded once. |
| Date sort verification query | Passed: Kinetic Therm SQL reference order starts `12194`, `12195`, `226869`, `12196`, `226871`, `12192`, `12193` for open affairs. |
| Client column compatibility | Passed: the sort preload query no longer selects `CLIENT.NOM_COURT` when the column is absent. |
| Affair renderer cache | Passed: rendered affair labels are cached by affair ID and invalidated when the list data changes. |
| Java compiler invocation | Passed: full module compilation completed through `scripts/build-java8-compatible.sh` against `/opt/openconcerto/OpenConcerto.jar`. |
| Module JAR packaging | Passed: rebuilt `org.openconcerto.modules.project-1.1.jar` with resources and module metadata. |
| Java 8-21 runtime compatibility guard | Passed: the module is compiled with Java 8 as the release target and the resulting JAR was verified to contain only classfile major version `52` or lower. |
| Installed module verification | Passed: only one active project JAR remains in `~/.local/share/OpenConcerto/Modules`, and it has no patch classes or former start-date references. |

Compiler command used:

```sh
./scripts/build-java8-compatible.sh
```

Compilation result:

The compilation completed successfully with JDK 21 while targeting Java 8. Remaining output is limited to Java 8 obsolescence warnings from modern `javac`, deprecation notes, and unchecked-operation notes.

Compatibility basis:

- On JDK 9 and newer, the build uses `javac --release 8`, which compiles with Java 8 language rules and Java 8 platform APIs.
- On JDK 8, the build falls back to `-source 8 -target 8`.
- `scripts/verify-java8-bytecode.sh` rejects any class with a classfile major version above `52`.
- The local OpenConcerto dependency used for compilation also reports classfile major version `52`.

Deployment result:

- Built JAR: `build/org.openconcerto.modules.project-1.1.jar`
- Installed JAR: `/home/jojokes/.local/share/OpenConcerto/Modules/org.openconcerto.modules.project-1.1.jar`
- Backups of previous installed JARs:
  - `build/module-backups/org.openconcerto.modules.project-1.03.before-date-sort-fix-20260706.jar`
  - `build/module-backups/org.openconcerto.modules.project-1.03.before-date-column-20260706.jar`

## Risk Assessment

| Risk | Severity | Notes | Mitigation |
| --- | --- | --- | --- |
| Reflection against `JListSQLTableModel` internals | Medium | Existing patch behavior depended on private fields such as `comp` and `list`. | Validate against the target OpenConcerto version; consider upstream API extension if available. |
| UI integration timing | Medium | Controls are installed immediately after `ListeHistoriquePanel` frame creation. | Smoke-test the history window in the actual application runtime. |
| Optional database tables and fields | Low to Medium | Customer schemas may vary. | Existing conditional checks are preserved for optional tables and fields. |
| Closed-affair filter scope | Low | The checkbox filters the left affair selector only. It does not globally remove closed affairs from all already-loaded history data. | This is intentional; document user behavior and test selector refresh only. |
| Family split UI change | Low to Medium | The old UI exposed one sub-tab per family; the new UI exposes one combo filter. The data remains accessible, but navigation differs. | Smoke-test with users who depended on per-family sub-tabs. |
| Family filter scope | Low | The family combos filter `COMMANDE_ELEMENT` and `BON_RECEPTION_ELEMENT`, matching the two tabs requested for the current UI. | Extend only if another tab needs family filtering later. |
| Supplier invoice item display semantics | Low | The `Nom` column in supplier invoice item history now means supplier name, not line style name. | This is intentional for Kinetic Therm's workflow; verify with users who relied on style-line labels. |
| Column state cache | Medium | OpenConcerto may keep user-specific table column layouts. Removed/replaced source columns can still require a UI cache reset or column layout refresh to be visible immediately. | Restart OpenConcerto and reset list configuration if stale columns remain. |
| PostgreSQL indexes applied directly to Kinetic Therm | Low | The indexes were created in the current Kinetic Therm database, not as an OpenConcerto module migration for every future database. | Re-run the conditional index script on other customer databases if needed. |
| Runtime smoke test still manual | Medium | The module is built and installed, but the UI must still be opened in OpenConcerto to validate visual behavior. | Restart OpenConcerto and verify the history window. |
| Line-ending/style churn | Low | Some edited regions may now mix local line ending style. | Let Eclipse formatter or repository normalization handle this if required by the team. |

## Review Findings

### Findings Requiring Attention

1. Reflection-based list manipulation remains a compatibility risk.

   The source-level implementation preserves the previous behavior, but it still depends on private implementation details of `JListSQLTableModel`. This is acceptable as a direct migration from the patch but should be revisited if the target OpenConcerto version exposes public sorting/filtering hooks.

2. Runtime verification must be completed in OpenConcerto.

   The module is compiled, packaged, and installed, but the final confirmation requires launching OpenConcerto and opening the "Historique affaires" window.

3. The family filter UI needs runtime smoke testing.

   The code compiles and is packaged, but the combo placement and filtering should be verified in the actual OpenConcerto window.

### Accepted Trade-Offs

- The revision intentionally preserves behavior rather than redesigning the history panel API.
- The patch helper logic was folded into `ProjectHistory.java` to keep behavior close to the owning UI workflow.
- Defensive optional-table checks were kept to support customer database variance.
- The closed-affair checkbox is implemented as a UI filter over `ID_ETAT_AFFAIRE`, not as a database mutation.
- The family splitter was replaced by a dynamic filter after confirming eager split-panel creation caused a significant runtime slowdown on Kinetic Therm.

## Acceptance Criteria Status

| Acceptance Criterion | Status |
| --- | --- |
| All patch behavior inspected | Met |
| Behavior implemented in project source | Met |
| No need to patch executable `.class` files | Met |
| Java patch sources removed | Met |
| Documentation updated to remove deleted patch sources | Met |
| No patch/ASM references remain | Met |
| Date ordering uses only `AFFAIRE.DATE` | Met |
| `DATE` is available as a visible affairs-list column | Met |
| Closed affairs can be hidden from the affair selector | Met |
| Closed affairs can be shown again by unchecking the checkbox | Met |
| History loading bottleneck documented and tested | Met |
| Family split feature preserved without eager split tabs | Met |
| Article families are loaded once for the filter combo | Met |
| Family filter applies only when the user selects a family | Met |
| `Articles commandés` no longer shows the misleading `Nom` line-style column | Met |
| `Factures fournisseurs` shows supplier name instead of line-style labels in `Nom` | Met |
| Useful Kinetic Therm PostgreSQL history indexes added | Met |
| Full module compile against OpenConcerto runtime | Met |
| Module JAR installed in local OpenConcerto modules directory | Met |

## Recommended Follow-Up

1. Restart OpenConcerto so the replaced module JAR is loaded.
2. Smoke-test the "Historique affaires" window with the Kinetic Therm database containing:
   - `BON_DE_LIVRAISON`
   - `COMMANDE`
   - `BON_RECEPTION`
   - `DATE` on `AFFAIRE`
   - `FACTURE_FOURNISSEUR_ELEMENT`
3. Verify the following UI behavior:
   - supplier orders and receipts display under the renamed labels;
   - delivery notes display under "Bons de livraison clients";
   - the affair list sorts by `DATE` descending by default;
   - "Masquer dossiers clos" is checked by default;
   - closed affairs are absent while the checkbox is checked;
   - closed affairs reappear when the checkbox is unchecked;
   - the affairs table exposes a `Date` column; if it is hidden by saved UI preferences, enable it from the column chooser or reset the list configuration;
   - switching to "Tri par nom" reorders the affair list by label;
   - "Modifier l'affaire" opens the selected affair for modification;
   - supplier invoice item totals are included correctly in the purchase balance;
   - history loading remains faster without eager family split tabs;
   - the `Famille article` combo appears in `Articles commandés`;
   - the `Famille article` combo appears in `Articles réceptionnés`;
   - selecting a family filters the corresponding article tab only;
   - selecting `Toutes les familles` removes the family filter;
   - `Articles commandés` no longer displays the `Nom` column;
   - `Factures fournisseurs` displays supplier names in the `Nom` column instead of `Normal`, `Titre 1`, or `Titre 2`.
4. Re-run the conditional index creation step on any other customer database that uses this module and lacks the same `ID_AFFAIRE` indexes.
5. If OpenConcerto still shows stale behavior, disable/re-enable the module in module management and restart the application.

## Release Note Draft

Removed the bytecode patching workflow for the project module and integrated the previous patch behavior directly into the Java source. The history UI now registers optional supplier/customer tables, normalizes display actions, supports project list sorting by `DATE` descending or by name, exposes `DATE` as a visible affairs-list column, adds a `Masquer dossiers clos` checkbox backed by `ID_ETAT_AFFAIRE`, exposes direct modification actions, and fixes supplier invoice item total calculation. A performance audit identified eager family split tabs as the history-loading bottleneck on Kinetic Therm; the eager splitters were replaced by tab-local dynamic `Famille article` filters on `Articles commandés` and `Articles réceptionnés`, preserving family filtering without constructing hundreds of list panels at startup. The Java UI layer now also removes the misleading `Nom` column from `Articles commandés` and replaces supplier invoice item line-style labels with the supplier name in `Factures fournisseurs`. Missing PostgreSQL `ID_AFFAIRE` indexes were added on the Kinetic Therm history tables, while existing `ID_FAMILLE_ARTICLE` indexes were preserved. Patch-only Java sources and documentation references were removed. The module version was set to `1.1`; Kinetic Therm module metadata was downgraded from internal version `10003` to `10001`, then the module was compiled and installed as `org.openconcerto.modules.project-1.1.jar` in the local OpenConcerto modules directory.

## References

- Google Engineering Practices: Writing good CL descriptions  
  https://google.github.io/eng-practices/review/developer/cl-descriptions.html
- Google Engineering Practices: What to look for in a code review  
  https://google.github.io/eng-practices/review/reviewer/looking-for.html
- Google Engineering Practices: Small CLs  
  https://google.github.io/eng-practices/review/developer/small-cls.html
- Martin Fowler: Continuous Integration  
  https://martinfowler.com/articles/continuousIntegration.html
- Atlassian: What are code reviews and how they actually save time  
  https://www.atlassian.com/agile/software-development/code-reviews
