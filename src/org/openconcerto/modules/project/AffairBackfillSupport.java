/*
 * Reprise des affaires sur les documents deja transferes.
 *
 * Le correctif de {@link AffairTransferSupport} ne vaut que pour les transferts
 * <b>a venir</b>. Les documents crees avant lui n'ont pas d'affaire : c'est le
 * « meme pour les existantes c'est encore pire ». Cette classe reconstruit le
 * lien manquant a partir de ce que la base sait deja :
 *
 * <ul>
 * <li>{@code SAISIE_ACHAT.SOURCE} / {@code SAISIE_ACHAT.IDSOURCE} : la saisie
 * d'achat n'ait d'une commande ou d'un bon de reception sait de quel document
 * elle vient ;</li>
 * <li>tables {@code TR_<SOURCE>} : chaque transfert y laisse une ligne
 * {@code (ID_<SOURCE>, ID_<DESTINATION>)} ;</li>
 * <li>enfin les <b>lignes</b> : elles reprennent l'affaire de leur document,
 * qui vient d'etre reparee aux etapes precedentes (d'ou l'ordre).</li>
 * </ul>
 *
 * Les regles produisent du SQL a partir du seul schema (presence des tables et
 * des colonnes) : rien n'est suppose present, et une base partielle ne produit
 * simplement pas les reprises impossibles. Les mises a jour ne touchent
 * <b>jamais</b> une affaire deja renseignee : elles ne remplissent que le vide
 * ({@code NULL} ou l'affaire « Indefini » d'identifiant 1), et sont donc
 * idempotentes et sans risque pour les donnees.
 */
package org.openconcerto.modules.project;

import java.util.ArrayList;
import java.util.List;

public final class AffairBackfillSupport {

    /** Champ de l'affaire. */
    public static final String AFFAIR_FIELD = AffairLinkSupport.AFFAIR_FIELD;

    /** Cle primaire des tables OpenConcerto. */
    public static final String KEY_FIELD = "ID";

    /**
     * Affaire « Indefini » : elle ne designe aucune affaire et doit etre
     * traitee comme du vide.
     */
    public static final int UNDEFINED_ID = AffairLinkSupport.UNDEFINED_ID;

    /** Ecriture des noms de tables et de colonnes dans le SQL produit. */
    public interface Quoter {
        /** Nom complet et protege d'une table (ex. {@code "OpenConcerto42"."COMMANDE"}). */
        String table(String tableName);

        /** Nom protege d'une colonne (ex. {@code "ID_AFFAIRE"}). */
        String column(String columnName);
    }

    /** Implementation simple, pour les tests et le SQL portable. */
    public static Quoter simpleQuoter() {
        return new Quoter() {
            @Override
            public String table(final String tableName) {
                return "\"" + tableName + "\"";
            }

            @Override
            public String column(final String columnName) {
                return "\"" + columnName + "\"";
            }
        };
    }

    /** Une reprise : combien de lignes, et quelle mise a jour. */
    public static final class Repair {
        private final String target;
        private final String description;
        private final String countSql;
        private final String updateSql;

        Repair(final String target, final String description, final String countSql, final String updateSql) {
            this.target = target;
            this.description = description;
            this.countSql = countSql;
            this.updateSql = updateSql;
        }

        /** Table mise a jour. */
        public String getTarget() {
            return this.target;
        }

        /** Description lisible (« saisies d'achat depuis la commande ... »). */
        public String getDescription() {
            return this.description;
        }

        /** Requete de comptage : ce que la reprise changerait. */
        public String getCountSql() {
            return this.countSql;
        }

        /** Mise a jour, idempotente. */
        public String getUpdateSql() {
            return this.updateSql;
        }

        @Override
        public String toString() {
            return this.target + " : " + this.description;
        }
    }

    private AffairBackfillSupport() {
    }

    /**
     * Construit le plan de reprise.
     *
     * @param schema schema de la base.
     * @param quoter facon d'ecrire les noms dans le SQL.
     * @return les reprises dans l'ordre d'execution (documents, puis lignes).
     */
    public static List<Repair> plan(final AffairLinkSupport.Schema schema, final Quoter quoter) {
        final List<Repair> repairs = new ArrayList<Repair>();
        if (schema == null || quoter == null) {
            return repairs;
        }
        addSourceRepairs(repairs, schema, quoter);
        addTransferRepairs(repairs, schema, quoter);
        addLineRepairs(repairs, schema, quoter);
        return repairs;
    }

    /** Etape 1 : les saisies d'achat connaissent leur document d'origine. */
    private static void addSourceRepairs(final List<Repair> repairs, final AffairLinkSupport.Schema schema, final Quoter q) {
        final String target = "SAISIE_ACHAT";
        if (!hasAffair(schema, target) || !schema.hasField(target, "IDSOURCE") || !schema.hasField(target, "SOURCE")) {
            return;
        }
        // Les valeurs possibles de SOURCE sont les tables sources des
        // injecteurs : COMMANDE et BON_RECEPTION.
        for (final String source : new String[] { "COMMANDE", "BON_RECEPTION" }) {
            if (!hasAffair(schema, source) || !hasKey(schema, source)) {
                continue;
            }
            final String sourceValue = q.column("SOURCE") + " = '" + source + "'";
            final String join = a(q, target, "IDSOURCE") + " = " + a(q, source, KEY_FIELD);
            final String empty = emptyAffair(q, target);
            final String real = realAffair(q, source);
            final String description = target + " <- " + source + " (SOURCE / IDSOURCE)";
            repairs.add(new Repair(target, description,
                    "SELECT count(*) FROM " + q.table(target) + " INNER JOIN " + q.table(source) + " ON " + join
                            + " WHERE " + sourceValue + " AND " + empty + " AND " + real,
                    "UPDATE " + q.table(target) + " SET " + q.column(AFFAIR_FIELD) + " = " + a(q, source, AFFAIR_FIELD)
                            + " FROM " + q.table(source) + " WHERE " + join + " AND " + sourceValue + " AND " + empty + " AND " + real));
        }
    }

    /** Etape 2 : les tables de transfert du c&oelig;ur ({@code TR_<SOURCE>}). */
    private static void addTransferRepairs(final List<Repair> repairs, final AffairLinkSupport.Schema schema, final Quoter q) {
        for (final String[] pair : AffairTransferSupport.TRANSFER_PAIRS) {
            final String source = pair[0];
            final String target = pair[1];
            final String transferTable = "TR_" + source;
            if (!hasAffair(schema, source) || !hasAffair(schema, target) || !schema.hasTable(transferTable)) {
                continue;
            }
            // Certaines bases n'ont pas de colonne ID sur toutes les tables
            // (constate sur DEVIS) : sans elle, la jointure est impossible et la
            // reprise doit etre ignoree, pas produire une requete en echec.
            if (!hasKey(schema, source) || !hasKey(schema, target)) {
                continue;
            }
            final String srcKey = "ID_" + source;
            final String destKey = "ID_" + target;
            if (!schema.hasField(transferTable, srcKey) || !schema.hasField(transferTable, destKey)) {
                continue;
            }
            final String empty = emptyAffair(q, target);
            final String real = realAffair(q, source);
            final String join = a(q, transferTable, destKey) + " = " + a(q, target, KEY_FIELD)
                    + " AND " + a(q, transferTable, srcKey) + " = " + a(q, source, KEY_FIELD);
            repairs.add(new Repair(target, target + " <- " + source + " (via " + transferTable + ")",
                    "SELECT count(*) FROM " + q.table(target) + " INNER JOIN " + q.table(transferTable) + " ON " + join
                            + " INNER JOIN " + q.table(source) + " ON " + a(q, transferTable, srcKey) + " = " + a(q, source, KEY_FIELD)
                            + " WHERE " + empty + " AND " + real,
                    "UPDATE " + q.table(target) + " SET " + q.column(AFFAIR_FIELD) + " = " + a(q, source, AFFAIR_FIELD)
                            + " FROM " + q.table(transferTable) + " INNER JOIN " + q.table(source) + " ON "
                            + a(q, transferTable, srcKey) + " = " + a(q, source, KEY_FIELD)
                            + " WHERE " + join + " AND " + empty + " AND " + real));
        }
    }

    /** Etape 3 : les lignes reprennent l'affaire de leur document. */
    private static void addLineRepairs(final List<Repair> repairs, final AffairLinkSupport.Schema schema, final Quoter q) {
        for (final String lineTable : ItemAffairColumnRules.LINE_TABLES) {
            final String document = ItemAffairColumnRules.parentTable(lineTable);
            final String link = ItemAffairColumnRules.parentField(lineTable);
            if (document == null || link == null) {
                continue;
            }
            if (!hasAffair(schema, lineTable) || !hasAffair(schema, document) || !schema.hasField(lineTable, link)) {
                continue;
            }
            if (!hasKey(schema, document)) {
                continue;
            }
            final String empty = emptyAffair(q, lineTable);
            final String real = realAffair(q, document);
            final String join = a(q, lineTable, link) + " = " + a(q, document, KEY_FIELD);
            repairs.add(new Repair(lineTable, lineTable + " <- " + document + " (lignes)",
                    "SELECT count(*) FROM " + q.table(lineTable) + " INNER JOIN " + q.table(document) + " ON " + join + " WHERE " + empty + " AND " + real,
                    "UPDATE " + q.table(lineTable) + " SET " + q.column(AFFAIR_FIELD) + " = " + a(q, document, AFFAIR_FIELD)
                            + " FROM " + q.table(document) + " WHERE " + join + " AND " + empty + " AND " + real));
        }
    }

    private static boolean hasAffair(final AffairLinkSupport.Schema schema, final String table) {
        return schema.hasTable(table) && schema.hasField(table, AFFAIR_FIELD);
    }

    /**
     * Vrai si la table porte la cle primaire utilisee par les jointures.
     * <p>
     * Toutes les installations n'ont pas {@code ID} partout : sur la base du
     * client, {@code DEVIS} n'a pas cette colonne. Sans ce controle, la reprise
     * produirait un {@code join ... on "DEVIS"."ID" = ...} qui echoue et, dans
     * une transaction unique, annulerait toutes les autres reprises.
     * </p>
     */
    private static boolean hasKey(final AffairLinkSupport.Schema schema, final String table) {
        return schema.hasField(table, KEY_FIELD);
    }

    /** {@code <table>.<colonne>}, tel qu'ecrit dans le SQL produit. */
    private static String a(final Quoter q, final String table, final String column) {
        return q.table(table) + "." + q.column(column);
    }

    /** Affaire vide (nulle ou « Indefini »). */
    static String emptyAffair(final Quoter q, final String table) {
        return "(" + a(q, table, AFFAIR_FIELD) + " IS NULL OR " + a(q, table, AFFAIR_FIELD) + " = " + UNDEFINED_ID + ")";
    }

    /** Affaire reellement renseignee. */
    static String realAffair(final Quoter q, final String table) {
        return "(" + a(q, table, AFFAIR_FIELD) + " IS NOT NULL AND " + a(q, table, AFFAIR_FIELD) + " > " + UNDEFINED_ID + ")";
    }
}
