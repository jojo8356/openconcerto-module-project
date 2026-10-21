package org.openconcerto.modules.project.panels;

import java.util.List;
import java.util.Map;

/**
 * Controle 2 : chaque panneau montre bien TOUTES les donnees de la base, et
 * aucune ligne n'est cachee.
 *
 * <p>
 * Pour chaque panneau, une seule requete agrege les compteurs :
 * </p>
 * <ul>
 * <li>nombre de lignes de la table ;</li>
 * <li>nombre de lignes reellement affichees par le panneau ;</li>
 * <li>detail des lignes non affichees : non rattachees a une affaire,
 * rattachees a une affaire disparue, mere absente, ligne technique
 * « Indefini » (ID 1).</li>
 * </ul>
 *
 * <p>
 * Une ligne rattachee a une affaire disparue, ou dont la mere a disparu, ne
 * peut jamais etre affichee : c'est une donnee cachee, donc un echec. Une
 * ligne simplement non rattachee (ID_AFFAIRE NULL) est une alerte : elle
 * n'apparait dans aucun onglet de l'historique.
 * </p>
 */
public class VisibilitySuite implements Suite {

    public String name() {
        return "Visibilite (toutes les lignes des panneaux, aucune donnee cachee)";
    }

    public void run(Db db, List<String> schemas, Report report) throws Exception {
        for (String schema : schemas) {
            if (!Catalogue.isModuleInstalled(db, schema)) {
                report.info(schema, "module project non installe dans ce schema (tables principales absentes) : controle ignore");
                continue;
            }
            final List panels = Catalogue.build(schema);
            for (int p = 0; p < panels.size(); p++) {
                final Panel panel = (Panel) panels.get(p);
                final String scope = schema + " / " + panel.getId();
                try {
                    checkPanel(db, schema, panel, report, scope);
                } catch (Exception e) {
                    report.fail(scope, "controle de visibilite impossible : " + e.getMessage());
                }
            }
        }
    }

    private void checkPanel(final Db db, final String schema, final Panel panel, final Report report, final String scope) throws Exception {
        if (!db.tableExists(schema, panel.getTable())) {
            return;
        }
        final boolean hasAffaire = db.tableExists(schema, "AFFAIRE");
        final String from = PanelSql.fromClause(db, panel, schema, hasAffaire);
        final String key = db.primaryKey(schema, panel.getTable());
        final String expr = PanelSql.affaireExpr(panel);
        final String visibleWhere = PanelSql.visibleWhere(panel, schema);
        final String linkedWhere = PanelSql.linkedWhere(panel, schema);
        final List chain = panel.getChain();
        final String deepest = chain.isEmpty() ? null : "p" + chain.size();
        final String deepestKey = chain.isEmpty() ? key : db.primaryKey(schema, ((Panel.Link) chain.get(chain.size() - 1)).table);

        final StringBuilder sql = new StringBuilder("select count(*) as total");
        sql.append(", count(distinct t.\"").append(key).append("\") as distinct_ids");
        sql.append(", count(*) filter (where ").append(visibleWhere).append(") as visible");
        sql.append(", count(*) filter (where ").append(linkedWhere).append(") as linked");
        if (expr != null) {
            sql.append(", count(*) filter (where ").append(expr).append(" is not null and ").append(expr).append(" <> 1 and not exists (select 1 from ")
                    .append(Db.qualified(schema, "AFFAIRE")).append(" aff where aff.\"ID\" = ").append(expr).append(")) as dangling");
            sql.append(", count(*) filter (where ").append(expr).append(" = 1) as undefined");
            sql.append(", count(*) filter (where ").append(expr).append(" is null) as no_link");
        }
        if (deepest != null) {
            sql.append(", count(*) filter (where ").append(deepest).append(".\"").append(deepestKey).append("\" is null) as parent_missing");
            sql.append(", count(*) filter (where ").append(deepest).append(".\"").append(deepestKey).append("\" is not null and ").append(deepest)
                    .append(".\"ID_AFFAIRE\" is null) as parent_without_affaire");
        }
        sql.append(" from ").append(from);

        final List rows = db.query(sql.toString());
        final Map counters = (Map) rows.get(0);
        final long total = longValue(counters, "total");
        final long distinctIds = longValue(counters, "distinct_ids");
        final long visible = longValue(counters, "visible");
        final long linked = longValue(counters, "linked");
        final long dangling = longValue(counters, "dangling");
        final long undefined = longValue(counters, "undefined");
        final long noLink = longValue(counters, "no_link");
        final long parentMissing = longValue(counters, "parent_missing");
        final long parentWithoutAffaire = longValue(counters, "parent_without_affaire");

        if (Panel.KIND_LIST.equals(panel.getKind())) {
            if (visible != total) {
                report.fail(scope, "le panneau n'affiche pas toutes les lignes : " + visible + " affichees sur " + total);
            } else {
                report.ok(scope, "toutes les lignes sont affichees : " + total);
            }
        } else if (visible > total) {
            report.fail(scope, "incoherence : " + visible + " lignes affichees pour " + total + " lignes dans la table");
        }

        if (distinctIds != total) {
            report.fail(scope, "doublons dans la jointure du panneau : " + total + " lignes mais " + distinctIds + " identifiants distincts");
        }

        if (dangling > 0) {
            report.fail(scope, dangling + " ligne(s) rattachees a une AFFAIRE INEXISTANTE : donnees cachees dans tous les panneaux. Exemples : "
                    + samples(db, from, expr + " is not null and " + expr + " <> 1 and not exists (select 1 from " + Db.qualified(schema, "AFFAIRE")
                    + " aff where aff.\"ID\" = " + expr + ")"));
        }
        if (parentMissing > 0) {
            report.fail(scope, parentMissing + " ligne(s) dont la table mere a disparu : donnees cachees. Exemples : "
                    + samples(db, from, deepest + ".\"" + deepestKey + "\" is null"));
        }
        if (parentWithoutAffaire > 0) {
            report.warn(scope, parentWithoutAffaire + " ligne(s) dont la mere n'est rattachee a aucune affaire : invisibles dans l'historique. Exemples : "
                    + samples(db, from, deepest + ".\"ID\" is not null and " + deepest + ".\"ID_AFFAIRE\" is null"));
        }
        if (noLink > 0) {
            report.warn(scope, noLink + " ligne(s) non rattachees a une affaire : invisibles dans l'historique. Exemples : "
                    + samples(db, from, expr + " is null"));
        }
        if (undefined > 0) {
            report.info(scope, undefined + " ligne(s) rattachees a l'affaire technique « Indefini » (ID 1)");
        }
        final long filteredOut = linked - visible;
        if (filteredOut > 0) {
            final String why = panel.getExtraCondition() == null ? "le panneau ne montre que les lignes rattachees a une affaire"
                    : "le filtre propre au panneau (" + panel.getExtraCondition() + ")";
            report.info(scope, filteredOut + " ligne(s) rattachees a une affaire mais masquees : " + why);
        }
        if (dangling == 0 && parentMissing == 0 && parentWithoutAffaire == 0 && noLink == 0 && visible == total) {
            report.ok(scope, "aucune donnee cachee : " + visible + " ligne(s) affichee(s) sur " + total + " (schema " + schema + ")");
        }
    }

    private static long longValue(final Map row, final String key) {
        final Object value = row.get(key);
        if (value == null) {
            return 0L;
        }
        try {
            return Long.parseLong(String.valueOf(value).trim());
        } catch (NumberFormatException e) {
            return 0L;
        }
    }

    private String samples(final Db db, final String from, final String condition) throws Exception {
        final List rows = db.query("select t.* from " + from + " where " + condition + " limit 10");
        return Db.firstColumn(rows).toString();
    }
}
