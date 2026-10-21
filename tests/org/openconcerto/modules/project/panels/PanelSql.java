package org.openconcerto.modules.project.panels;

import java.util.List;

/**
 * Construction du SQL des panneaux. Les alias utilises :
 * <ul>
 * <li><code>t</code> : la table du panneau ;</li>
 * <li><code>p1</code>, <code>p2</code>... : les tables parentes de la chaine
 * de rattachement a l'affaire ;</li>
 * <li><code>a</code> : la table AFFAIRE.</li>
 * </ul>
 */
public final class PanelSql {

    private PanelSql() {
    }

    /**
     * La table du panneau, qualifiee et aliasee, avec la chaine de
     * rattachement a l'affaire et la table AFFAIRE (alias <code>a</code>).
     */
    public static String fromClause(Db db, Panel panel, String schema) throws Exception {
        return fromClause(db, panel, schema, true);
    }

    /**
     * Idem, mais sans la jointure sur AFFAIRE si la table n'existe pas dans
     * ce schema.
     *
     * <p>
     * Les jointures se font sur la vraie cle primaire de la table mere :
     * toutes les tables n'ont pas une colonne « ID ».
     * </p>
     */
    public static String fromClause(Db db, Panel panel, String schema, boolean withAffaire) throws Exception {
        final StringBuilder sb = new StringBuilder();
        sb.append(Db.qualified(schema, panel.getTable())).append(" t");
        final List<Panel.Link> chain = panel.getChain();
        String previous = "t";
        for (int i = 0; i < chain.size(); i++) {
            final Panel.Link link = (Panel.Link) chain.get(i);
            final String key = db.primaryKey(schema, link.table);
            sb.append(" left join ").append(Db.qualified(schema, link.table)).append(" p").append(i + 1).append(" on p").append(i + 1).append(".\"").append(key).append("\" = ")
                    .append(previous).append(".\"").append(link.field).append("\"");
            previous = "p" + (i + 1);
        }
        final String expr = affaireExpr(panel);
        if (withAffaire && expr != null) {
            // l'affaire elle-meme est jointe : les filtres propres aux
            // panneaux peuvent l'interroger (ex. ID_ETAT_AFFAIRE)
            final String affaireKey = db.primaryKey(schema, "AFFAIRE");
            sb.append(" left join ").append(Db.qualified(schema, "AFFAIRE")).append(" a on a.\"").append(affaireKey).append("\" = ").append(expr);
        }
        return sb.toString();
    }

    /**
     * Expression donnant l'ID d'affaire auquel la ligne est rattachee (NULL
     * si la ligne n'est rattachee a aucune affaire).
     */
    public static String affaireExpr(Panel panel) {
        final List<Panel.Link> chain = panel.getChain();
        if (!chain.isEmpty()) {
            return "p" + chain.size() + ".\"ID_AFFAIRE\"";
        }
        if (panel.getAffaireColumn() != null) {
            return "t.\"" + panel.getAffaireColumn() + "\"";
        }
        return null;
    }

    /**
     * Condition SQL (sans le WHERE) qui selectionne exactement les lignes
     * affichees par le panneau.
     */
    public static String visibleWhere(Panel panel, String schema) {
        final StringBuilder sb = new StringBuilder();
        if (Panel.KIND_LIST.equals(panel.getKind())) {
            sb.append("1 = 1");
        } else if (Panel.KIND_STRUCTURE.equals(panel.getKind())) {
            sb.append("1 = 1");
        } else {
            final String expr = affaireExpr(panel);
            if (expr == null) {
                // La table est la table des affaires elle-meme.
                sb.append("t.\"ID\" <> 1");
            } else {
                sb.append(expr).append(" IS NOT NULL AND ").append(expr).append(" <> 1 AND EXISTS (select 1 from ")
                        .append(Db.qualified(schema, "AFFAIRE")).append(" aff where aff.\"ID\" = ").append(expr).append(")");
            }
        }
        if (panel.getExtraCondition() != null) {
            sb.append(" AND (").append(panel.getExtraCondition()).append(")");
        }
        return sb.toString();
    }

    /**
     * Condition « la ligne est rattachee a une affaire existante », sans le
     * filtre propre au panneau.
     */
    public static String linkedWhere(Panel panel, String schema) {
        final String expr = affaireExpr(panel);
        if (expr == null) {
            return "1 = 1";
        }
        return expr + " IS NOT NULL AND " + expr + " <> 1 AND EXISTS (select 1 from " + Db.qualified(schema, "AFFAIRE") + " aff where aff.\"ID\" = " + expr + ")";
    }
}
