package org.openconcerto.modules.project.panels;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Controle 1 : la structure attendue par chaque panneau existe bien.
 *
 * <p>
 * Une colonne manquante ne fait pas « disparaitre » une ligne, mais elle casse
 * le panneau (le module lit la colonne, la colonne n'est pas la : erreur
 * « X is not in table /T/.../ »). C'est le controle qui aurait detecte le
 * bug ID_COMMANDE_ELEMENT de la production.
 * </p>
 */
public class StructureSuite implements Suite {

    public String name() {
        return "Structure (tables et colonnes attendues par les panneaux)";
    }

    public void run(Db db, List<String> schemas, Report report) throws Exception {
        for (String schema : schemas) {
            if (!Catalogue.isModuleInstalled(db, schema)) {
                report.info(schema, "module project non installe dans ce schema (tables principales absentes) : controle ignore");
                continue;
            }
            final List<Panel> panels = new ArrayList<Panel>(Catalogue.build(schema));
            panels.addAll(Catalogue.structureContract());
            for (int p = 0; p < panels.size(); p++) {
                final Panel panel = (Panel) panels.get(p);
                final String scope = schema + " / " + panel.getId();
                try {
                    checkPanel(db, schema, panel, report, scope);
                } catch (Exception e) {
                    report.fail(scope, "controle de structure impossible : " + e.getMessage());
                }
            }
        }
    }

    private void checkPanel(final Db db, final String schema, final Panel panel, final Report report, final String scope) throws Exception {
        if (!db.tableExists(schema, panel.getTable())) {
            if (panel.isOptional()) {
                report.info(scope, "table optionnelle absente : " + panel.getTable() + " (panneau non affiche)");
            } else {
                report.fail(scope, "TABLE ABSENTE : " + panel.getTable() + " (" + panel.getLabel() + ")");
            }
            return;
        }

        // Cache des colonnes par table.
        final Map columnsCache = new HashMap();
        int missing = 0;
        final List requirements = panel.getRequired();
        for (int r = 0; r < requirements.size(); r++) {
            final Panel.Req req = (Panel.Req) requirements.get(r);
            final Set columns = columnsOf(db, columnsCache, schema, req.table);
            if (columns == null) {
                report.info(scope, "table absente, exigence ignoree : " + req.table + "." + req.column);
                continue;
            }
            if (!columns.contains(req.column)) {
                missing++;
                report.fail(scope, "COLONNE MANQUANTE : " + req.table + "." + req.column + " (" + req.reason + ")");
            }
        }
        if (missing == 0) {
            report.ok(scope, "structure complete : " + panel.getTable() + " (" + panel.getRequired().size() + " colonnes verifiees)");
        }

        // Cle etrangere exigee (transfert commande -> facture / bon de reception).
        if (panel.getFkColumn() != null && panel.getFkTarget() != null) {
            final String sql = "select count(*) from pg_constraint c"
                    + " join pg_class t on t.oid = c.conrelid"
                    + " join pg_namespace n on n.oid = t.relnamespace"
                    + " join pg_class rt on rt.oid = c.confrelid"
                    + " join pg_namespace rn on rn.oid = rt.relnamespace"
                    + " join pg_attribute a on a.attrelid = t.oid and a.attname = " + Db.literal(panel.getFkColumn()) + " and a.attnum = any(c.conkey)"
                    + " where c.contype = 'f' and n.nspname = " + Db.literal(schema) + " and t.relname = " + Db.literal(panel.getTable())
                    + " and rn.nspname = " + Db.literal(schema) + " and rt.relname = " + Db.literal(panel.getFkTarget());
            final long fks = db.count(sql);
            if (fks > 0) {
                report.ok(scope, "cle etrangere presente : " + panel.getTable() + "." + panel.getFkColumn() + " -> " + panel.getFkTarget());
            } else {
                report.fail(scope, "CLE ETRANGERE MANQUANTE : " + panel.getTable() + "." + panel.getFkColumn() + " -> " + panel.getFkTarget());
            }
            final String idx = "select count(*) from pg_indexes where schemaname = " + Db.literal(schema) + " and tablename = " + Db.literal(panel.getTable())
                    + " and indexdef ilike " + Db.literal("%" + panel.getFkColumn() + "%");
            if (db.count(idx) > 0) {
                report.ok(scope, "index present sur " + panel.getFkColumn());
            } else {
                report.info(scope, "aucun index sur " + panel.getTable() + "." + panel.getFkColumn() + " (performance, pas de donnee cachee)");
            }
        }
    }

    private Set columnsOf(final Db db, final Map cache, final String schema, final String table) throws Exception {
        final String key = schema + "." + table;
        if (cache.containsKey(key)) {
            return (Set) cache.get(key);
        }
        Set columns = null;
        if (db.tableExists(schema, table)) {
            columns = db.columns(schema, table);
        }
        cache.put(key, columns);
        return columns;
    }
}
