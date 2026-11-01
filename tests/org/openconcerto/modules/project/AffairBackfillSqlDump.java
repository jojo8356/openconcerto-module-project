package org.openconcerto.modules.project;

import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Ecrit sur la sortie standard le <b>plan de reprise</b> calcule par
 * {@link AffairBackfillSupport} pour un schema de type client.
 *
 * <p>
 * Ce programme ne sert qu'aux tests en ligne de commande : il permet a
 * {@code tests/cli/test-affaire-transfert.py} d'executer <b>exactement</b> le SQL
 * que le module produirait, dans une base SQLite jetable, sans OpenConcerto ni
 * PostgreSQL.
 * </p>
 *
 * <p>
 * Format, une ligne par requete, champs separes par des barres verticales :
 * </p>
 *
 * <pre>
 * TABLE|nom|colonne,colonne,...
 * COUNT|description|requete de comptage
 * UPDATE|description|requete de mise a jour
 * </pre>
 *
 * <p>
 * Les lignes {@code TABLE} permettent au test d'executer le SQL sans jamais
 * redire le schema : la base de test est creee a partir de ce que le plan a
 * reellement vu.
 * </p>
 *
 * <p>
 * Les tables sont prefixees par le schema {@code OpenConcerto42}, comme sur la
 * base du client.
 * </p>
 */
public final class AffairBackfillSqlDump {

    /** Schema de la societe, repris de la base du client. */
    private static final String SCHEMA = "OpenConcerto42";

    /** Tables de documents et leurs colonnes utiles. */
    private static final Object[][] DOCUMENTS = new Object[][] {
            { "COMMANDE", new String[] { "ID", "ID_AFFAIRE", "NUMERO", "ID_FOURNISSEUR" } },
            { "SAISIE_ACHAT", new String[] { "ID", "ID_AFFAIRE", "SOURCE", "IDSOURCE", "ID_FOURNISSEUR" } },
            { "BON_RECEPTION", new String[] { "ID", "ID_AFFAIRE", "ID_FOURNISSEUR" } },
            { "FACTURE_FOURNISSEUR", new String[] { "ID", "ID_AFFAIRE", "ID_FOURNISSEUR" } },
            { "AVOIR_FOURNISSEUR", new String[] { "ID", "ID_AFFAIRE" } },
            { "DEVIS", new String[] { "ID", "ID_AFFAIRE" } },
            { "COMMANDE_CLIENT", new String[] { "ID", "ID_AFFAIRE" } },
            { "SAISIE_VENTE_FACTURE", new String[] { "ID", "ID_AFFAIRE" } },
            { "AVOIR_CLIENT", new String[] { "ID", "ID_AFFAIRE" } },
            { "BON_DE_LIVRAISON", new String[] { "ID", "ID_AFFAIRE" } } };

    /** Tables de lignes (colonnes = cle, affaire, lien vers le document). */
    private static final Object[][] LINES = new Object[][] {
            { "COMMANDE_ELEMENT", "ID_COMMANDE" },
            { "FACTURE_FOURNISSEUR_ELEMENT", "ID_FACTURE_FOURNISSEUR" },
            { "BON_RECEPTION_ELEMENT", "ID_BON_RECEPTION" },
            { "SAISIE_ACHAT_ELEMENT", "ID_SAISIE_ACHAT" },
            { "COMMANDE_CLIENT_ELEMENT", "ID_COMMANDE_CLIENT" },
            { "SAISIE_VENTE_FACTURE_ELEMENT", "ID_SAISIE_VENTE_FACTURE" },
            { "DEVIS_ELEMENT", "ID_DEVIS" },
            { "AVOIR_CLIENT_ELEMENT", "ID_AVOIR_CLIENT" },
            { "BON_DE_LIVRAISON_ELEMENT", "ID_BON_DE_LIVRAISON" },
            { "AVOIR_FOURNISSEUR_ELEMENT", "ID_AVOIR_FOURNISSEUR" },
            { "DEMANDE_PRIX_ELEMENT", "ID_DEMANDE_PRIX" },
            { "DEMANDE_ACHAT_ELEMENT", "ID_DEMANDE_ACHAT" } };

    /** Tables de transfert du c&oelig;ur et leurs deux cles etrangeres. */
    private static final Object[][] TRANSFERS = new Object[][] {
            { "TR_COMMANDE", new String[] { "ID", "ID_COMMANDE", "ID_BON_RECEPTION", "ID_SAISIE_ACHAT", "ID_FACTURE_FOURNISSEUR" } },
            { "TR_BON_RECEPTION", new String[] { "ID", "ID_BON_RECEPTION", "ID_SAISIE_ACHAT", "ID_FACTURE_FOURNISSEUR" } },
            { "TR_SAISIE_ACHAT", new String[] { "ID", "ID_SAISIE_ACHAT", "ID_AVOIR_FOURNISSEUR" } },
            { "TR_DEVIS", new String[] { "ID", "ID_DEVIS", "ID_COMMANDE", "ID_COMMANDE_CLIENT", "ID_SAISIE_VENTE_FACTURE", "ID_BON_DE_LIVRAISON" } },
            { "TR_COMMANDE_CLIENT", new String[] { "ID", "ID_COMMANDE_CLIENT", "ID_SAISIE_VENTE_FACTURE", "ID_BON_DE_LIVRAISON", "ID_COMMANDE" } },
            { "TR_SAISIE_VENTE_FACTURE", new String[] { "ID", "ID_SAISIE_VENTE_FACTURE", "ID_AVOIR_CLIENT", "ID_BON_DE_LIVRAISON", "ID_COMMANDE" } },
            { "TR_BON_DE_LIVRAISON", new String[] { "ID", "ID_BON_DE_LIVRAISON", "ID_SAISIE_VENTE_FACTURE" } } };

    public static void main(final String[] args) {
        final AffairLinkSupport.Schema schema = schema();
        final AffairBackfillSupport.Quoter quoter = new AffairBackfillSupport.Quoter() {
            @Override
            public String table(final String tableName) {
                return "\"" + SCHEMA + "\".\"" + tableName + "\"";
            }

            @Override
            public String column(final String columnName) {
                return "\"" + columnName + "\"";
            }
        };
        // Schema reellement decrit, pour creer la base de test a l'identique.
        for (final Object[] document : DOCUMENTS) {
            printTable((String) document[0], (String[]) document[1]);
        }
        for (final Object[] line : LINES) {
            final String table = (String) line[0];
            printTable(table, new String[] { "ID", "ID_AFFAIRE", (String) line[1] });
        }
        for (final Object[] transfer : TRANSFERS) {
            printTable((String) transfer[0], (String[]) transfer[1]);
        }

        final List<AffairBackfillSupport.Repair> plan = AffairBackfillSupport.plan(schema, quoter);
        if (plan.isEmpty()) {
            System.err.println("plan vide : schema inattendu");
            System.exit(1);
        }
        for (final AffairBackfillSupport.Repair repair : plan) {
            System.out.println("COUNT|" + repair.getDescription() + "|" + repair.getCountSql());
            System.out.println("UPDATE|" + repair.getDescription() + "|" + repair.getUpdateSql());
        }
        System.err.println(plan.size() + " reprises generees");
    }

    /** Schema complet, decrit pour les regles pures. */
    public static AffairLinkSupport.Schema schema() {
        final Set<String> tables = new HashSet<String>();
        final Map<String, Set<String>> fields = new HashMap<String, Set<String>>();
        for (final Object[] document : DOCUMENTS) {
            add(tables, fields, (String) document[0], (String[]) document[1]);
        }
        for (final Object[] line : LINES) {
            final String table = (String) line[0];
            final String link = (String) line[1];
            add(tables, fields, table, new String[] { "ID", "ID_AFFAIRE", link });
            // la table de lignes n'existe dans le schema que si son document
            // existe aussi (voir le plan : la reprise est conditionnee aux deux)
        }
        for (final Object[] transfer : TRANSFERS) {
            add(tables, fields, (String) transfer[0], (String[]) transfer[1]);
        }
        return AffairLinkSupport.schemaOf(tables, fields);
    }

    private static void printTable(final String name, final String[] columns) {
        final StringBuilder sb = new StringBuilder("TABLE|").append(name).append('|');
        for (int i = 0; i < columns.length; i++) {
            if (i > 0) {
                sb.append(',');
            }
            sb.append(columns[i]);
        }
        System.out.println(sb);
    }

    private static void add(final Set<String> tables, final Map<String, Set<String>> fields, final String table, final String[] columns) {
        tables.add(table);
        fields.put(table, new HashSet<String>(Arrays.asList(columns)));
    }

    private AffairBackfillSqlDump() {
    }
}
