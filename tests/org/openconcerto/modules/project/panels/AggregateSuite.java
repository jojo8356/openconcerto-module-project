package org.openconcerto.modules.project.panels;

import java.math.BigDecimal;
import java.util.List;

/**
 * Controle 3 : les totaux affiches par les panneaux sont bien ceux de la base,
 * et aucune ligne n'est perdue entre la table et le panneau.
 *
 * <p>
 * Pour chaque total du bilan (montant du marche, budget chiffre, montant
 * facture, avoirs, achats, temps), on compare le calcul « comme le panneau »
 * (lignes rattachees a une affaire) au calcul « direct » (toutes les lignes de
 * la table). Un ecart signale des lignes qui n'apparaissent dans aucun
 * panneau.
 * </p>
 *
 * <p>
 * On verifie aussi que le recensement des lignes (affichees + non rattachees
 * + orphelines + ligne technique) redonne exactement le nombre de lignes de
 * la table : aucune ligne ne disparait du controle.
 * </p>
 *
 * <p>
 * Toutes les jointures se font sur la vraie cle primaire des tables (lues
 * dans le catalogue PostgreSQL) : toutes les tables n'ont pas une colonne
 * « ID ».
 * </p>
 */
public class AggregateSuite implements Suite {

    public String name() {
        return "Totaux et recensement (les chiffres des panneaux = ceux de la base)";
    }

    public void run(final Db db, final List<String> schemas, final Report report) throws Exception {
        for (String schema : schemas) {
            if (!Catalogue.isModuleInstalled(db, schema)) {
                report.info(schema, "module project non installe dans ce schema (tables principales absentes) : controle ignore");
                continue;
            }
            for (String panelId : new String[] { "bilan.marche", "bilan.facture", "bilan.achats", "bilan.commandes_fournisseurs" }) {
                final String scope = schema + " / " + panelId;
                try {
                    checkBilan(db, schema, panelId, report, scope);
                } catch (Exception e) {
                    report.fail(scope, "controle des totaux impossible : " + e.getMessage());
                }
            }
            try {
                checkCensus(db, schema, report);
            } catch (Exception e) {
                report.fail(schema + " / recensement", "controle impossible : " + e.getMessage());
            }
        }
    }

    /**
     * Condition « la ligne est rattachee a une affaire qui existe », sur la
     * vraie cle primaire de la table AFFAIRE.
     */
    private static String existsAffaire(final String schema, final String expr, final String affaireKey) {
        return " and exists (select 1 from " + Db.qualified(schema, "AFFAIRE") + " a where a.\"" + affaireKey + "\" = " + expr + ")";
    }

    private void checkBilan(final Db db, final String schema, final String panelId, final Report report, final String scope) throws Exception {
        // cles primaires reelles : toutes les tables n'ont pas une colonne « ID »
        final String affaireKey = db.primaryKey(schema, "AFFAIRE");
        final String ccKey = db.primaryKey(schema, "COMMANDE_CLIENT");
        final String ffKey = db.primaryKey(schema, "FACTURE_FOURNISSEUR");
        final String cmdKey = db.primaryKey(schema, "COMMANDE");
        final String cc = Db.qualified(schema, "COMMANDE_CLIENT") + " c";
        final String ff = Db.qualified(schema, "FACTURE_FOURNISSEUR") + " f";
        final String cmd = Db.qualified(schema, "COMMANDE") + " c";
        if ("bilan.marche".equals(panelId)) {
            compare(db, report, scope, "montant du marche (COMMANDE_CLIENT.T_HT)",
                    "select coalesce(sum(c.\"T_HT\"), 0) from " + cc + " where c.\"ID_AFFAIRE\" is not null and c.\"ID_AFFAIRE\" <> 1"
                            + existsAffaire(schema, "c.\"ID_AFFAIRE\"", affaireKey),
                    "select coalesce(sum(\"T_HT\"), 0) from " + Db.qualified(schema, "COMMANDE_CLIENT"));
            compare(db, report, scope, "budget chiffre (CHIFFRAGE_COMMANDE_CLIENT.T_PA_HT)",
                    "select coalesce(sum(h.\"T_PA_HT\"), 0) from " + Db.qualified(schema, "CHIFFRAGE_COMMANDE_CLIENT") + " h"
                            + " join " + cc + " on c.\"" + ccKey + "\" = h.\"ID_COMMANDE_CLIENT\""
                            + " where c.\"ID_AFFAIRE\" is not null and c.\"ID_AFFAIRE\" <> 1"
                            + existsAffaire(schema, "c.\"ID_AFFAIRE\"", affaireKey),
                    "select coalesce(sum(\"T_PA_HT\"), 0) from " + Db.qualified(schema, "CHIFFRAGE_COMMANDE_CLIENT"));
        } else if ("bilan.facture".equals(panelId)) {
            compare(db, report, scope, "montant facture (SAISIE_VENTE_FACTURE.T_HT)",
                    "select coalesce(sum(f.\"T_HT\"), 0) from " + Db.qualified(schema, "SAISIE_VENTE_FACTURE") + " f where f.\"ID_AFFAIRE\" is not null and f.\"ID_AFFAIRE\" <> 1"
                            + existsAffaire(schema, "f.\"ID_AFFAIRE\"", affaireKey),
                    "select coalesce(sum(\"T_HT\"), 0) from " + Db.qualified(schema, "SAISIE_VENTE_FACTURE"));
            compare(db, report, scope, "avoirs clients deduits (AVOIR_CLIENT.MONTANT_HT)",
                    "select coalesce(sum(v.\"MONTANT_HT\"), 0) from " + Db.qualified(schema, "AVOIR_CLIENT") + " v where v.\"A_DEDUIRE\" and v.\"ID_AFFAIRE\" is not null"
                            + " and v.\"ID_AFFAIRE\" <> 1" + existsAffaire(schema, "v.\"ID_AFFAIRE\"", affaireKey),
                    "select coalesce(sum(\"MONTANT_HT\"), 0) from " + Db.qualified(schema, "AVOIR_CLIENT") + " where \"A_DEDUIRE\"");
        } else if ("bilan.achats".equals(panelId)) {
            compare(db, report, scope, "achats (SAISIE_ACHAT.MONTANT_HT)",
                    "select coalesce(sum(s.\"MONTANT_HT\"), 0) from " + Db.qualified(schema, "SAISIE_ACHAT") + " s where s.\"ID_AFFAIRE\" is not null and s.\"ID_AFFAIRE\" <> 1"
                            + existsAffaire(schema, "s.\"ID_AFFAIRE\"", affaireKey),
                    "select coalesce(sum(\"MONTANT_HT\"), 0) from " + Db.qualified(schema, "SAISIE_ACHAT"));
            compare(db, report, scope, "factures fournisseurs (FACTURE_FOURNISSEUR.T_HT)",
                    "select coalesce(sum(f.\"T_HT\"), 0) from " + ff + " where f.\"ID_AFFAIRE\" is not null and f.\"ID_AFFAIRE\" <> 1"
                            + existsAffaire(schema, "f.\"ID_AFFAIRE\"", affaireKey),
                    "select coalesce(sum(\"T_HT\"), 0) from " + Db.qualified(schema, "FACTURE_FOURNISSEUR"));
            compare(db, report, scope, "articles de facture fournisseur (FACTURE_FOURNISSEUR_ELEMENT.T_PA_HT)",
                    "select coalesce(sum(e.\"T_PA_HT\"), 0) from " + Db.qualified(schema, "FACTURE_FOURNISSEUR_ELEMENT") + " e"
                            + " join " + ff + " on f.\"" + ffKey + "\" = e.\"ID_FACTURE_FOURNISSEUR\""
                            + " where f.\"ID_AFFAIRE\" is not null and f.\"ID_AFFAIRE\" <> 1" + existsAffaire(schema, "f.\"ID_AFFAIRE\"", affaireKey),
                    "select coalesce(sum(\"T_PA_HT\"), 0) from " + Db.qualified(schema, "FACTURE_FOURNISSEUR_ELEMENT"));
            compare(db, report, scope, "avoirs fournisseurs (AVOIR_FOURNISSEUR.MONTANT_HT)",
                    "select coalesce(sum(v.\"MONTANT_HT\"), 0) from " + Db.qualified(schema, "AVOIR_FOURNISSEUR") + " v where v.\"ID_AFFAIRE\" is not null and v.\"ID_AFFAIRE\" <> 1"
                            + existsAffaire(schema, "v.\"ID_AFFAIRE\"", affaireKey),
                    "select coalesce(sum(\"MONTANT_HT\"), 0) from " + Db.qualified(schema, "AVOIR_FOURNISSEUR"));
        } else if ("bilan.commandes_fournisseurs".equals(panelId)) {
            compare(db, report, scope, "commandes fournisseurs (COMMANDE.T_HT)",
                    "select coalesce(sum(c.\"T_HT\"), 0) from " + cmd + " where c.\"ID_AFFAIRE\" is not null and c.\"ID_AFFAIRE\" <> 1"
                            + existsAffaire(schema, "c.\"ID_AFFAIRE\"", affaireKey),
                    "select coalesce(sum(\"T_HT\"), 0) from " + Db.qualified(schema, "COMMANDE"));
            compare(db, report, scope, "articles commandes (COMMANDE_ELEMENT.T_PA_HT)",
                    "select coalesce(sum(e.\"T_PA_HT\"), 0) from " + Db.qualified(schema, "COMMANDE_ELEMENT") + " e"
                            + " join " + cmd + " on c.\"" + cmdKey + "\" = e.\"ID_COMMANDE\""
                            + " where c.\"ID_AFFAIRE\" is not null and c.\"ID_AFFAIRE\" <> 1" + existsAffaire(schema, "c.\"ID_AFFAIRE\"", affaireKey),
                    "select coalesce(sum(\"T_PA_HT\"), 0) from " + Db.qualified(schema, "COMMANDE_ELEMENT"));
        }
    }

    private void compare(final Db db, final Report report, final String scope, final String label, final String panelSql, final String directSql) throws Exception {
        final BigDecimal panelValue = amount(db, panelSql);
        final BigDecimal directValue = amount(db, directSql);
        if (panelValue.compareTo(directValue) == 0) {
            report.ok(scope, label + " : " + panelValue.toPlainString() + " (identique au total de la table)");
        } else {
            final BigDecimal hidden = directValue.subtract(panelValue);
            report.warn(scope, label + " : le panneau affiche " + panelValue.toPlainString() + " alors que la table totalise " + directValue.toPlainString()
                    + " -> " + hidden.toPlainString() + " absent d'un panneau (lignes non rattachees a une affaire)");
        }
    }

    private BigDecimal amount(final Db db, final String sql) throws Exception {
        final String value = db.scalar(sql);
        if (value == null || value.trim().length() == 0) {
            return BigDecimal.ZERO;
        }
        return new BigDecimal(value.trim());
    }

    /**
     * Recensement : pour chaque table liee a une affaire, la somme des
     * categories (affichees, non rattachees, orphelines, ligne technique)
     * doit redonner le nombre de lignes de la table.
     */
    private void checkCensus(final Db db, final String schema, final Report report) throws Exception {
        int checked = 0;
        int problems = 0;
        if (!Catalogue.isModuleInstalled(db, schema)) {
            return;
        }
        final String affaireKey = db.primaryKey(schema, "AFFAIRE");
        final List panelList = Catalogue.build(schema);
        for (int p = 0; p < panelList.size(); p++) {
            final Panel panel = (Panel) panelList.get(p);
            if (!Panel.KIND_HISTORY.equals(panel.getKind())) {
                continue;
            }
            final String expr = PanelSql.affaireExpr(panel);
            if (expr == null) {
                continue;
            }
            if (!db.tableExists(schema, panel.getTable())) {
                continue;
            }
            final boolean hasAffaire = db.tableExists(schema, "AFFAIRE");
            final String from = PanelSql.fromClause(db, panel, schema, hasAffaire);
            final String census = "select count(*) as total"
                    + ", count(*) filter (where " + PanelSql.linkedWhere(db, panel, schema) + ") as linked"
                    + ", count(*) filter (where " + expr + " is not null and " + expr + " <> 1 and not exists (select 1 from "
                    + Db.qualified(schema, "AFFAIRE") + " aff where aff.\"" + affaireKey + "\" = " + expr + ")) as dangling"
                    + ", count(*) filter (where " + expr + " = 1) as undefined"
                    + ", count(*) filter (where " + expr + " is null) as no_link"
                    + " from " + from;
            final List censusRows = db.query(census);
            final java.util.Map counters = (java.util.Map) censusRows.get(0);
            final long total = Long.parseLong(String.valueOf(counters.get("total")).trim());
            final long linked = Long.parseLong(String.valueOf(counters.get("linked")).trim());
            final long dangling = Long.parseLong(String.valueOf(counters.get("dangling")).trim());
            final long undefined = Long.parseLong(String.valueOf(counters.get("undefined")).trim());
            final long noLink = Long.parseLong(String.valueOf(counters.get("no_link")).trim());
            checked++;
            if (linked + dangling + undefined + noLink != total) {
                problems++;
                report.fail(schema + " / recensement", "recensement incomplet pour " + panel.getTable() + " : " + linked + " rattachees + " + dangling + " orphelines + "
                        + undefined + " indefinies + " + noLink + " sans affaire != " + total);
            }
        }
        if (problems == 0) {
            report.ok(schema + " / recensement", "recensement complet : aucune ligne perdue sur " + checked + " table(s)");
        }
    }
}
