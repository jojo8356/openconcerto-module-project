# Patch Integration Revision Report

**Project:** OpenConcerto Project Module  
**Revision date:** 2026-07-06  
**Prepared by:** Codex  
**Scope:** Replacement of runtime/JAR bytecode patching with maintainable source-level implementation, validated build, and local module deployment.

## Executive Summary

This revision removes the post-build patching mechanism previously represented by `PatchProjectJar.java` and `ProjectHistoryPatch.java`. The behavior implemented by those patch classes has been integrated directly into the module source code. The result is a simpler, reviewable, source-controlled implementation that no longer depends on ASM bytecode rewriting or patch-only helper classes.

The revision affects the project history UI, project list ordering, supplier purchase balance computation, generated documentation inventory, and the installed OpenConcerto module JAR. No patch-oriented Java sources remain in the project tree, and the deployed module JAR no longer contains `ProjectHistoryPatch` or `PatchProjectJar` classes.

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
| Project history UI and table behavior | `src/org/openconcerto/modules/project/ProjectHistory.java` | Updated |
| Project list fields | `src/org/openconcerto/modules/project/element/ProjectSQLElement.java` | Updated to use `DATE` as a visible list field and remove the former start-date field |
| Purchase balance computation | `src/org/openconcerto/modules/project/panel/HistoriqueAffaireBilanPanel.java` | Updated |
| Patch JAR utility | `src/org/openconcerto/modules/project/PatchProjectJar.java` | Deleted |
| Runtime patch helper | `src/org/openconcerto/modules/project/ProjectHistoryPatch.java` | Deleted |
| Source tree documentation | `docs/source-tree-analysis.md` | Updated |
| Component inventory documentation | `docs/component-inventory.md` | Updated |
| Installed module JAR | `/home/jojokes/.local/share/OpenConcerto/Modules/org.openconcerto.modules.project-1.03.jar` | Rebuilt and replaced |

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
  - sort selector: "Par date" / "Par nom"
  - "Modifier l'affaire" action button
- Applies the default date-based affair sort.
- Installs a date-aware renderer for the project list.

Review assessment:

- The patch hook previously injected into `ProjectHistory` construction is now a direct method call.
- UI behavior is discoverable in the owning class.
- Existing French UI labels are preserved for user-facing consistency.

### 4. Affair List Sorting and Rendering

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

Review assessment:

- The behavior matches the intent of the prior runtime patch.
- The final algorithm intentionally ignores the former start-date field; this was corrected after database inspection on `OpenConcertoKineticTherm`.
- The expected ordering is equivalent to `ORDER BY "DATE" DESC NULLS LAST, "NUMERO"`.
- Reflection is still used for `JListSQLTableModel` internals, which should be treated as a compatibility risk if OpenConcerto internals change.

### 5. Project List Fields and Date Column

`ProjectSQLElement.java` no longer injects the former start-date field into the project list fields. It now adds `DATE` directly to the affair list fields, immediately after `NUMERO`, so the business date can appear as a normal column in the affairs list.

Primary location:

- `ProjectSQLElement.java:46-50`

Review assessment:

- The list-field behavior no longer exposes or depends on the former start-date field.
- This keeps the module aligned with the final business rule: use only `DATE` for project history ordering.
- `DATE` is now part of the list model, enabling a visible `Date` column in OpenConcerto.
- The French label already existed in `labels_fr.xml` as `<FIELD name="DATE" label="Date" />`, so no label addition was required.

### 6. Supplier Purchase Balance Fix

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

### 7. Documentation Inventory Cleanup

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
| Java compiler invocation | Passed: full module compilation completed against `/opt/openconcerto/OpenConcerto.jar` and installed modules. |
| Module JAR packaging | Passed: rebuilt `org.openconcerto.modules.project-1.03.jar` with resources and module metadata. |
| Installed module verification | Passed: only one active project JAR remains in `~/.local/share/OpenConcerto/Modules`, and it has no patch classes or former start-date references. |

Compiler command used:

```sh
javac -proc:none -encoding UTF-8 -source 8 -target 8 \
  -cp "/opt/openconcerto/OpenConcerto.jar:/opt/openconcerto/OpenConcerto-Configuration.jar:/home/jojokes/.local/share/OpenConcerto/Modules/*" \
  -d /tmp/openconcerto-project-build/classes \
  $(find src -name '*.java' | sort)
```

Compilation result:

The compilation completed successfully. Remaining output is limited to Java 8 bootstrap/deprecation warnings and existing deprecated constructor warnings.

Deployment result:

- Built JAR: `/tmp/openconcerto-project-build/org.openconcerto.modules.project-1.03.jar`
- Installed JAR: `/home/jojokes/.local/share/OpenConcerto/Modules/org.openconcerto.modules.project-1.03.jar`
- Backups of previous installed JARs:
  - `build/module-backups/org.openconcerto.modules.project-1.03.before-date-sort-fix-20260706.jar`
  - `build/module-backups/org.openconcerto.modules.project-1.03.before-date-column-20260706.jar`

## Risk Assessment

| Risk | Severity | Notes | Mitigation |
| --- | --- | --- | --- |
| Reflection against `JListSQLTableModel` internals | Medium | Existing patch behavior depended on private fields such as `comp` and `list`. | Validate against the target OpenConcerto version; consider upstream API extension if available. |
| UI integration timing | Medium | Controls are installed immediately after `ListeHistoriquePanel` frame creation. | Smoke-test the history window in the actual application runtime. |
| Optional database tables and fields | Low to Medium | Customer schemas may vary. | Existing conditional checks are preserved for optional tables and fields. |
| Runtime smoke test still manual | Medium | The module is built and installed, but the UI must still be opened in OpenConcerto to validate visual behavior. | Restart OpenConcerto and verify the history window. |
| Line-ending/style churn | Low | Some edited regions may now mix local line ending style. | Let Eclipse formatter or repository normalization handle this if required by the team. |

## Review Findings

### Findings Requiring Attention

1. Reflection-based list manipulation remains a compatibility risk.

   The source-level implementation preserves the previous behavior, but it still depends on private implementation details of `JListSQLTableModel`. This is acceptable as a direct migration from the patch but should be revisited if the target OpenConcerto version exposes public sorting/filtering hooks.

2. Runtime verification must be completed in OpenConcerto.

   The module is compiled, packaged, and installed, but the final confirmation requires launching OpenConcerto and opening the "Historique affaires" window.

### Accepted Trade-Offs

- The revision intentionally preserves behavior rather than redesigning the history panel API.
- The patch helper logic was folded into `ProjectHistory.java` to keep behavior close to the owning UI workflow.
- Defensive optional-table checks were kept to support customer database variance.

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
   - the affairs table exposes a `Date` column; if it is hidden by saved UI preferences, enable it from the column chooser or reset the list configuration;
   - switching to "Par nom" reorders the affair list by label;
   - "Modifier l'affaire" opens the selected affair for modification;
   - supplier invoice item totals are included correctly in the purchase balance.
4. If OpenConcerto still shows stale behavior, disable/re-enable the module in module management and restart the application.

## Release Note Draft

Removed the bytecode patching workflow for the project module and integrated the previous patch behavior directly into the Java source. The history UI now registers optional supplier/customer tables, normalizes display actions, supports project list sorting by `DATE` descending or by name, exposes `DATE` as a visible affairs-list column, exposes direct modification actions, and fixes supplier invoice item total calculation. Patch-only Java sources and documentation references were removed. The module was compiled and installed as `org.openconcerto.modules.project-1.03.jar` in the local OpenConcerto modules directory.

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
