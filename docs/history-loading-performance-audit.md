# Technical Audit: Slow Loading of the Project History Table

Date: 2026-07-07

Status: implemented. The eager family splitters were replaced by tab-local dynamic `Famille article` combo filters, and missing Kinetic Therm `ID_AFFAIRE` indexes were added.

Scope: `ProjectHistory` / `ListeHistoriquePanel` loading path for Kinetic Therm project history.

## Executive Summary

The slow loading is unlikely to be caused by the `AFFAIRE` date sort itself. PostgreSQL answers the left-side affair list query in about 1 ms on the current Kinetic Therm database.

The main technical risk is the eager construction of the full history screen: the code builds many historical `IListe` views at startup, including split views for article families. Since the database has 164 `FAMILLE_ARTICLE` rows and the module enables two split tables (`DEMANDE_ACHAT_ELEMENT` and `COMMANDE_ELEMENT`), the UI can create hundreds of internal list panels before the user uses them.

The second risk was database scaling: current row counts are still small enough that sequential scans are fast, but the initial audit found no PostgreSQL indexes on `ID_AFFAIRE`. The Kinetic Therm database has since been updated with the missing `ID_AFFAIRE` indexes.

## Evidence

### Code Path

`ProjectHistory` defines many historical tables eagerly:

- `DEVIS`
- `COMMANDE_CLIENT`
- `CHIFFRAGE_COMMANDE_CLIENT`
- `SAISIE_VENTE_FACTURE`
- `AVOIR_CLIENT`
- `DEMANDE_ACHAT_ELEMENT`
- `DEMANDE_PRIX`
- `BON_DE_LIVRAISON`
- `COMMANDE`
- `COMMANDE_ELEMENT`
- `BON_RECEPTION`
- `BON_RECEPTION_ELEMENT`
- `SAISIE_ACHAT`
- `AVOIR_FOURNISSEUR`
- optionally `AFFAIRE_TEMPS`, `MOUVEMENT_STOCK`, `NOTE_DE_FRAIS_ELEMENT`, `POINTAGE_ELEMENT`
- `FACTURE_FOURNISSEUR_ELEMENT` or `FACTURE_FOURNISSEUR`

Source reference: `src/org/openconcerto/modules/project/ProjectHistory.java:113`.

The costly construction point is:

```java
this.listPanel = new ListeHistoriquePanel("Affaires", request, mapList, bilanPanel, fieldLink, null, true, null, null, splitter);
```

Source reference: `src/org/openconcerto/modules/project/ProjectHistory.java:196`.

Immediately after construction, the code walks the generated lists to inspect model columns and build date filters:

```java
IListe liste = this.listPanel.getListe(i);
final List<SQLTableModelColumn> columns = liste.getModel().getReq().getColumns();
```

Source reference: `src/org/openconcerto/modules/project/ProjectHistory.java:198`.

### Splitter Multiplication

Because `AFFAIRE` does not contain `ID_DEPOT_STOCK` in Kinetic Therm, this branch is active:

```java
splitter.put("DEMANDE_ACHAT_ELEMENT", "ID_FAMILLE_ARTICLE");
splitter.put("COMMANDE_ELEMENT", "ID_FAMILLE_ARTICLE");
```

Source reference: `src/org/openconcerto/modules/project/ProjectHistory.java:185`.

The OpenConcerto `ListeHistoriquePanel` bytecode shows that when a splitter is configured, it performs a `SELECT *` on the foreign table and creates one `IListPanel` per returned row. For these two tables, the foreign table is `FAMILLE_ARTICLE`.

Database evidence:

```text
FAMILLE_ARTICLE rows: 164
```

Consequence:

```text
2 split tables * 164 families = up to 328 split list panels
```

That is before counting the normal non-split history lists. This is the strongest explanation for a long first load even with modest SQL execution times.

### Database Volume

Current row counts from Kinetic Therm:

```text
COMMANDE_ELEMENT              2284
FACTURE_FOURNISSEUR_ELEMENT   1590
MOUVEMENT_STOCK                820
SAISIE_VENTE_FACTURE           490
COMMANDE                       425
DEVIS                          381
AFFAIRE                        374
COMMANDE_CLIENT                350
FAMILLE_ARTICLE                164
BON_RECEPTION_ELEMENT           10
BON_RECEPTION                   10
DEMANDE_ACHAT_ELEMENT            4
SAISIE_ACHAT                     3
```

`AFFAIRE` itself is not large. The heavier tables are document line tables and stock/accounting-related tables.

### Initial Index State

Tables with `ID_AFFAIRE` columns existed, but the initial PostgreSQL inspection reported no indexes containing `ID_AFFAIRE`.

```text
ID_AFFAIRE columns found in audited tables: 11
Indexes containing ID_AFFAIRE: 0
```

This matters because `ListeHistoriquePanel` filters history lists by the selected affair. For direct tables this becomes logically equivalent to:

```sql
where "ID_AFFAIRE" = ?
```

For element tables like `COMMANDE_ELEMENT`, OpenConcerto builds an indirect condition through the parent document table, e.g. `COMMANDE.ID_AFFAIRE = ?`, then joins the element table through `ID_COMMANDE`.

### Query Measurements

Left-side affair list, with the current "hide closed" behavior:

```sql
select "ID", "NUMERO", "DATE", "ID_CLIENT", "NOM"
from "OpenConcerto42"."AFFAIRE"
where "ID" <> 1
  and "ID_ETAT_AFFAIRE" <> 6
order by "DATE" desc nulls last, "NUMERO";
```

Observed plan:

```text
Seq Scan on "AFFAIRE"
Rows returned: 287
Rows removed by filter: 87
Execution Time: ~1.057 ms
```

Direct history table examples:

```text
DEVIS by ID_AFFAIRE=330:
Seq Scan, 381 rows checked, Execution Time ~0.367 ms

COMMANDE by ID_AFFAIRE=330:
Seq Scan, 425 rows checked, Execution Time ~1.007 ms

COMMANDE_CLIENT by ID_AFFAIRE=330:
Seq Scan, 350 rows checked, Execution Time ~0.347 ms

SAISIE_VENTE_FACTURE by ID_AFFAIRE=330:
Seq Scan, 490 rows checked, Execution Time ~0.597 ms

BON_DE_LIVRAISON by ID_AFFAIRE=330:
Seq Scan, 204 rows checked, Execution Time ~0.259 ms
```

Indirect element-table example:

```text
COMMANDE_ELEMENT through COMMANDE.ID_AFFAIRE=330:
Seq Scan on COMMANDE, then Index Scan on COMMANDE_ELEMENT_ID_COMMANDE_fki
Execution Time ~0.468 ms
```

The isolated SQL timings are acceptable today. The expensive part is the multiplication of UI/model work and the number of refreshes.

## Root Causes

### 1. Eager UI Construction

`ListeHistoriquePanel` builds all configured lists immediately. The history screen is therefore front-loaded: it pays the cost for all tabs and sub-tabs even if the user only needs one.

Severity: High.

Impact: slow first opening, UI freeze risk, Swing EDT congestion.

### 2. Split-by-Family Explosion

The `splitter` creates per-family views for `DEMANDE_ACHAT_ELEMENT` and `COMMANDE_ELEMENT`. With 164 families, this can generate hundreds of internal list panels.

Severity: High.

Impact: large object graph, many table models, many request objects, many listeners, unnecessary work for empty families.

### 3. Missing `ID_AFFAIRE` Indexes

Current data is small enough that seq scans were fast, but the initial audit found no indexes on `ID_AFFAIRE`, while history filtering depends on `ID_AFFAIRE`.

Initial severity: Medium now, High later.

Impact if left unresolved: performance would degrade as document tables grow.

### 4. Column Introspection After Construction

After `ListeHistoriquePanel` construction, `ProjectHistory` iterates over the lists and asks each model request for its columns to find date fields.

Severity: Medium.

Impact: extra initialization cost and metadata/model work at startup.

### 5. Renderer and Comparator Row Access

The left list renderer and comparator can fall back to:

```java
model.getTable().getRow(item.getId())
row.getForeign("ID_CLIENT")
```

Source references:

- `src/org/openconcerto/modules/project/ProjectHistory.java:819`
- `src/org/openconcerto/modules/project/ProjectHistory.java:852`
- `src/org/openconcerto/modules/project/ProjectHistory.java:873`
- `src/org/openconcerto/modules/project/ProjectHistory.java:930`

Because `DATE`, `NUMERO`, `ID_CLIENT`, and `NOM` are included in the combo request, this should usually be cached. But on cache misses or renderer repaint bursts, it can still create extra row lookups.

Severity: Low to Medium.

Impact: mostly affects the left affair selector responsiveness, not the entire history tab load.

### 6. The Date Change Is Not the Main Bottleneck

The current date behavior uses `DATE` only, not `DATE_DEBUT`. The affair list query sorted by `DATE` returns quickly. There is no evidence that the `DATE` sort itself is the cause of the slow loading.

Severity: Low.

## Recommendations

### Priority 1: Remove or Reduce Splitter Explosion

Best quick test:

```java
// temporarily disable:
// splitter.put("DEMANDE_ACHAT_ELEMENT", "ID_FAMILLE_ARTICLE");
// splitter.put("COMMANDE_ELEMENT", "ID_FAMILLE_ARTICLE");
```

Expected result: if first load becomes much faster, the bottleneck is confirmed.

Production options:

- remove split-by-family entirely for history
- only split the active selected tab lazily
- only create sub-tabs for families that have rows for the selected affair
- replace per-family sub-tabs with a normal `ID_FAMILLE_ARTICLE` column/filter

### Priority 2: Add Indexes on `ID_AFFAIRE`

Status: implemented on the Kinetic Therm database. The SQL below documents the intended index set; the applied migration also checked PostgreSQL catalogs first to avoid duplicating existing indexes.

Recommended PostgreSQL indexes:

```sql
create index if not exists "DEVIS_ID_AFFAIRE_idx"
on "OpenConcerto42"."DEVIS" ("ID_AFFAIRE");

create index if not exists "COMMANDE_CLIENT_ID_AFFAIRE_idx"
on "OpenConcerto42"."COMMANDE_CLIENT" ("ID_AFFAIRE");

create index if not exists "SAISIE_VENTE_FACTURE_ID_AFFAIRE_idx"
on "OpenConcerto42"."SAISIE_VENTE_FACTURE" ("ID_AFFAIRE");

create index if not exists "BON_DE_LIVRAISON_ID_AFFAIRE_idx"
on "OpenConcerto42"."BON_DE_LIVRAISON" ("ID_AFFAIRE");

create index if not exists "COMMANDE_ID_AFFAIRE_idx"
on "OpenConcerto42"."COMMANDE" ("ID_AFFAIRE");

create index if not exists "AVOIR_CLIENT_ID_AFFAIRE_idx"
on "OpenConcerto42"."AVOIR_CLIENT" ("ID_AFFAIRE");

create index if not exists "AVOIR_FOURNISSEUR_ID_AFFAIRE_idx"
on "OpenConcerto42"."AVOIR_FOURNISSEUR" ("ID_AFFAIRE");

create index if not exists "DEMANDE_PRIX_ID_AFFAIRE_idx"
on "OpenConcerto42"."DEMANDE_PRIX" ("ID_AFFAIRE");

create index if not exists "SAISIE_ACHAT_ID_AFFAIRE_idx"
on "OpenConcerto42"."SAISIE_ACHAT" ("ID_AFFAIRE");

create index if not exists "FACTURE_FOURNISSEUR_ID_AFFAIRE_idx"
on "OpenConcerto42"."FACTURE_FOURNISSEUR" ("ID_AFFAIRE");

create index if not exists "FACTURE_FOURNISSEUR_ELEMENT_ID_AFFAIRE_idx"
on "OpenConcerto42"."FACTURE_FOURNISSEUR_ELEMENT" ("ID_AFFAIRE");
```

Optional index for the left affair selector:

```sql
create index if not exists "AFFAIRE_DATE_NUMERO_OPEN_idx"
on "OpenConcerto42"."AFFAIRE" ("DATE" desc, "NUMERO")
where "ID" <> 1 and "ID_ETAT_AFFAIRE" <> 6;
```

This optional index is not urgent with 374 affairs, but it protects the date selector as the table grows.

### Priority 3: Lazy-Load History Tabs

Longer-term fix: avoid constructing every `IListPanel` at screen startup. Build only the left affair list and the default selected tab, then create each tab when selected.

Expected result:

- faster window opening
- fewer initial SQL requests
- fewer Swing components and listeners
- less memory pressure

### Priority 4: Avoid Date Filter Introspection on Every List at Startup

Instead of asking every generated model for its columns after construction, define date-capable tables statically or lazily inspect only the active list.

Current code:

```java
final List<SQLTableModelColumn> columns = liste.getModel().getReq().getColumns();
```

This can force request/model initialization earlier than needed.

### Priority 5: Cache Left-List Display Text

The renderer currently formats date + affair label during rendering. A small cache keyed by affair ID would avoid repeated `ID_CLIENT` foreign row resolution during repaint/scroll.

This is secondary compared with the splitter issue.

## Validation Plan

1. Temporarily disable the two `splitter.put(...)` lines.
2. Compile and install the module.
3. Measure the time from opening the history screen to first usable interaction.
4. Re-enable one splitter at a time:
   - first `COMMANDE_ELEMENT`
   - then `DEMANDE_ACHAT_ELEMENT`
5. Compare timings.
6. Confirm the `ID_AFFAIRE` index set in the target database.
7. Re-run `EXPLAIN ANALYZE` for the same selected affair.
8. Test with a larger historical dataset if available.

## Conclusion

The most probable cause is not the date algorithm. The current `DATE`-only sort is cheap on Kinetic Therm.

The main bottleneck was architectural: `ListeHistoriquePanel` eagerly created a very large number of history views, amplified by split-by-family tabs. The DB was fast per query on the audited dataset; the missing `ID_AFFAIRE` indexes were added to prevent that from becoming a future bottleneck.

The first experiment disabled the two splitter entries and significantly improved loading. The production fix keeps those eager splitters disabled and preserves the feature through dynamic `ID_FAMILLE_ARTICLE` filters:

- families are loaded once from `FAMILLE_ARTICLE`;
- each relevant article tab exposes its own `Famille article` combo;
- `Articles commandés` filters `COMMANDE_ELEMENT.ID_FAMILLE_ARTICLE`;
- `Articles réceptionnés` filters `BON_RECEPTION_ELEMENT.ID_FAMILLE_ARTICLE`;
- `Toutes les familles` removes the corresponding tab filter;
- each filter is applied only after user selection through `ListeHistoriquePanel.addWhere(...)`.

The Kinetic Therm database was also updated with missing `ID_AFFAIRE` indexes on history tables. Existing `ID_FAMILLE_ARTICLE` indexes were detected and not duplicated.
