package org.openconcerto.modules.project;

import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Tests de {@link AffairBackfillSupport} : la reprise des affaires sur les
 * documents <b>deja</b> transferes.
 * <p>
 * C'est le second volet du probleme : « meme pour les existantes c'est encore
 * pire ». Les documents crees avant le correctif n'ont pas d'affaire ; on la
 * reconstruit a partir des liens qui existent deja en base (tables
 * {@code TR_*}, {@code SAISIE_ACHAT.SOURCE / IDSOURCE}), sans jamais ecraser
 * une affaire renseignee.
 */
public final class AffairBackfillSupportTest {

    private static int passed = 0;

    private static final AffairBackfillSupport.Quoter Q = AffairBackfillSupport.simpleQuoter();

    public static void main(final String[] args) {
        testSupplierInvoiceFromOrder();
        testSaisieAchatFromSource();
        testBuyerInvoiceFromReceipt();
        testLineRepairs();
        testNoColumnNoRepair();
        testNoTransferTableNoRepair();
        testNeverOverwritesExistingAffair();
        testOrderOfRepairs();
        testRealClientSchema();
        testDevisWithOwnKey();
        testPlaceholderRowsAreIgnored();
        testCountSqlScope();
        testTableWithoutKeyIsSkipped();
        testEmptyAndRealAffairPredicates();
        testNullSchema();
        testDescriptions();
        System.out.println("AffairBackfillSupportTest : " + passed + " tests OK");
    }

    private static void assertEquals(final String label, final Object expected, final Object actual) {
        if (expected == null ? actual != null : !expected.equals(actual)) {
            throw new AssertionError(label + " : attendu <" + expected + ">, obtenu <" + actual + ">");
        }
        passed++;
    }

    private static AffairLinkSupport.Schema schema(final Map<String, String[]> tables) {
        final Set<String> names = new HashSet<String>();
        final Map<String, Set<String>> fields = new HashMap<String, Set<String>>();
        for (final Map.Entry<String, String[]> entry : tables.entrySet()) {
            names.add(entry.getKey());
            fields.put(entry.getKey(), new HashSet<String>(Arrays.asList(entry.getValue())));
        }
        return AffairLinkSupport.schemaOf(names, fields);
    }

    private static Map<String, String[]> tables(final Object... pairs) {
        final Map<String, String[]> result = new HashMap<String, String[]>();
        for (int i = 0; i < pairs.length; i += 2) {
            result.put((String) pairs[i], (String[]) pairs[i + 1]);
        }
        return result;
    }

    private static String[] cols(final String... names) {
        return names;
    }

    private static AffairBackfillSupport.Repair find(final List<AffairBackfillSupport.Repair> plan, final String table, final String fragment) {
        for (final AffairBackfillSupport.Repair repair : plan) {
            if (repair.getTarget().equals(table) && repair.getDescription().contains(fragment)) {
                return repair;
            }
        }
        return null;
    }

    /** Facture fournisseur creee depuis une commande : le cas signale. */
    private static void testSupplierInvoiceFromOrder() {
        final Map<String, String[]> t = tables(
                "COMMANDE", cols("ID", "ID_AFFAIRE"),
                "FACTURE_FOURNISSEUR", cols("ID", "ID_AFFAIRE"),
                "TR_COMMANDE", cols("ID", "ID_COMMANDE", "ID_FACTURE_FOURNISSEUR"));
        final List<AffairBackfillSupport.Repair> plan = AffairBackfillSupport.plan(schema(t), Q);
        final AffairBackfillSupport.Repair repair = find(plan, "FACTURE_FOURNISSEUR", "TR_COMMANDE");
        assertEquals("reprise presente", Boolean.TRUE, Boolean.valueOf(repair != null));
        assertEquals("mise a jour de l'affaire", Boolean.TRUE, Boolean.valueOf(repair.getUpdateSql().contains("SET \"ID_AFFAIRE\" = \"COMMANDE\".\"ID_AFFAIRE\"")));
        assertEquals("jointure par la table de transfert", Boolean.TRUE, Boolean.valueOf(repair.getUpdateSql().contains("\"TR_COMMANDE\".\"ID_FACTURE_FOURNISSEUR\" = \"FACTURE_FOURNISSEUR\".\"ID\"")));
        assertEquals("jointure vers la commande", Boolean.TRUE, Boolean.valueOf(repair.getUpdateSql().contains("\"TR_COMMANDE\".\"ID_COMMANDE\" = \"COMMANDE\".\"ID\"")));
        assertEquals("comptage fourni", Boolean.TRUE, Boolean.valueOf(repair.getCountSql().startsWith("SELECT count(*)")));
        assertEquals("comptage sur la meme jointure", Boolean.TRUE, Boolean.valueOf(repair.getCountSql().contains("\"TR_COMMANDE\"")));
    }

    /** Saisie d'achat : SOURCE / IDSOURCE. */
    private static void testSaisieAchatFromSource() {
        final Map<String, String[]> t = tables(
                "COMMANDE", cols("ID", "ID_AFFAIRE"),
                "SAISIE_ACHAT", cols("ID", "ID_AFFAIRE", "SOURCE", "IDSOURCE"));
        final List<AffairBackfillSupport.Repair> plan = AffairBackfillSupport.plan(schema(t), Q);
        final AffairBackfillSupport.Repair repair = find(plan, "SAISIE_ACHAT", "SOURCE / IDSOURCE");
        assertEquals("reprise presente", Boolean.TRUE, Boolean.valueOf(repair != null));
        assertEquals("source verifiee", Boolean.TRUE, Boolean.valueOf(repair.getUpdateSql().contains("\"SOURCE\" = 'COMMANDE'")));
        assertEquals("lien par IDSOURCE", Boolean.TRUE, Boolean.valueOf(repair.getUpdateSql().contains("\"SAISIE_ACHAT\".\"IDSOURCE\" = \"COMMANDE\".\"ID\"")));
    }

    private static void testBuyerInvoiceFromReceipt() {
        final Map<String, String[]> t = tables(
                "BON_RECEPTION", cols("ID", "ID_AFFAIRE"),
                "FACTURE_FOURNISSEUR", cols("ID", "ID_AFFAIRE"),
                "TR_BON_RECEPTION", cols("ID", "ID_BON_RECEPTION", "ID_FACTURE_FOURNISSEUR"));
        final List<AffairBackfillSupport.Repair> plan = AffairBackfillSupport.plan(schema(t), Q);
        assertEquals("reprise bon de reception", Boolean.TRUE, Boolean.valueOf(find(plan, "FACTURE_FOURNISSEUR", "TR_BON_RECEPTION") != null));
    }

    /** Les lignes reprennent l'affaire de leur document. */
    private static void testLineRepairs() {
        final Map<String, String[]> t = tables(
                "COMMANDE", cols("ID", "ID_AFFAIRE"),
                "COMMANDE_ELEMENT", cols("ID", "ID_AFFAIRE", "ID_COMMANDE"));
        final List<AffairBackfillSupport.Repair> plan = AffairBackfillSupport.plan(schema(t), Q);
        final AffairBackfillSupport.Repair repair = find(plan, "COMMANDE_ELEMENT", "(lignes)");
        assertEquals("reprise des lignes", Boolean.TRUE, Boolean.valueOf(repair != null));
        assertEquals("lien vers le document", Boolean.TRUE, Boolean.valueOf(repair.getUpdateSql().contains("\"COMMANDE_ELEMENT\".\"ID_COMMANDE\" = \"COMMANDE\".\"ID\"")));
    }

    /** Une table sans colonne d'affaire ne produit aucune reprise. */
    private static void testNoColumnNoRepair() {
        final Map<String, String[]> t = tables(
                "COMMANDE", cols("ID", "ID_AFFAIRE"),
                "FACTURE_FOURNISSEUR", cols("ID"),
                "TR_COMMANDE", cols("ID", "ID_COMMANDE", "ID_FACTURE_FOURNISSEUR"));
        final List<AffairBackfillSupport.Repair> plan = AffairBackfillSupport.plan(schema(t), Q);
        assertEquals("aucune reprise sur la facture", null, find(plan, "FACTURE_FOURNISSEUR", "TR_COMMANDE"));
        assertEquals("aucune ligne non plus", Integer.valueOf(0), Integer.valueOf(plan.size()));
    }

    /** Sans table de transfert, pas de reprise par TR (mais on ne casse rien). */
    private static void testNoTransferTableNoRepair() {
        final Map<String, String[]> t = tables(
                "BON_RECEPTION", cols("ID", "ID_AFFAIRE"),
                "FACTURE_FOURNISSEUR", cols("ID", "ID_AFFAIRE"));
        final List<AffairBackfillSupport.Repair> plan = AffairBackfillSupport.plan(schema(t), Q);
        assertEquals("aucune reprise", Integer.valueOf(0), Integer.valueOf(plan.size()));
    }

    /** Regle d'or : on ne remplit que le vide. */
    private static void testNeverOverwritesExistingAffair() {
        final Map<String, String[]> t = tables(
                "COMMANDE", cols("ID", "ID_AFFAIRE"),
                "FACTURE_FOURNISSEUR", cols("ID", "ID_AFFAIRE"),
                "TR_COMMANDE", cols("ID", "ID_COMMANDE", "ID_FACTURE_FOURNISSEUR"),
                "SAISIE_ACHAT", cols("ID", "ID_AFFAIRE", "SOURCE", "IDSOURCE"),
                "COMMANDE_ELEMENT", cols("ID", "ID_AFFAIRE", "ID_COMMANDE"));
        for (final AffairBackfillSupport.Repair repair : AffairBackfillSupport.plan(schema(t), Q)) {
            if (!repair.getUpdateSql().contains("IS NULL")) {
                throw new AssertionError("mise a jour sans garde sur le vide : " + repair.getUpdateSql());
            }
            if (!repair.getUpdateSql().contains("= 1")) {
                throw new AssertionError("l'affaire « Indefini » (1) n'est pas traitee comme du vide : " + repair.getUpdateSql());
            }
            if (!repair.getUpdateSql().contains("> 1")) {
                throw new AssertionError("la source peut etre une affaire indefinie : " + repair.getUpdateSql());
            }
            passed += 3;
        }
    }

    /** Documents d'abord, lignes ensuite : sinon les lignes n'ont rien a reprendre. */
    private static void testOrderOfRepairs() {
        final Map<String, String[]> t = tables(
                "COMMANDE", cols("ID", "ID_AFFAIRE"),
                "FACTURE_FOURNISSEUR", cols("ID", "ID_AFFAIRE"),
                "TR_COMMANDE", cols("ID", "ID_COMMANDE", "ID_FACTURE_FOURNISSEUR"),
                "COMMANDE_ELEMENT", cols("ID", "ID_AFFAIRE", "ID_COMMANDE"));
        final List<AffairBackfillSupport.Repair> plan = AffairBackfillSupport.plan(schema(t), Q);
        int lineIndex = -1;
        int factureIndex = -1;
        for (int i = 0; i < plan.size(); i++) {
            if (plan.get(i).getTarget().equals("FACTURE_FOURNISSEUR")) {
                factureIndex = i;
            }
            if (plan.get(i).getTarget().equals("COMMANDE_ELEMENT")) {
                lineIndex = i;
            }
        }
        assertEquals("facture traitee", Boolean.TRUE, Boolean.valueOf(factureIndex >= 0));
        assertEquals("lignes apres les documents", Boolean.TRUE, Boolean.valueOf(lineIndex > factureIndex));
    }

    /** Schema reel du client : toutes les reprises attendues sont generees. */
    private static void testRealClientSchema() {
        final String[] doc = cols("ID", "ID_AFFAIRE");
        final Map<String, String[]> t = tables(
                "COMMANDE", doc,
                "SAISIE_ACHAT", cols("ID", "ID_AFFAIRE", "SOURCE", "IDSOURCE"),
                "BON_RECEPTION", doc,
                "FACTURE_FOURNISSEUR", doc,
                "AVOIR_FOURNISSEUR", doc,
                "DEVIS", doc,
                "COMMANDE_CLIENT", doc,
                "SAISIE_VENTE_FACTURE", doc,
                "AVOIR_CLIENT", doc,
                "BON_DE_LIVRAISON", doc,
                "TR_COMMANDE", cols("ID", "ID_COMMANDE", "ID_BON_RECEPTION", "ID_SAISIE_ACHAT", "ID_FACTURE_FOURNISSEUR"),
                "TR_BON_RECEPTION", cols("ID", "ID_BON_RECEPTION", "ID_SAISIE_ACHAT", "ID_FACTURE_FOURNISSEUR"),
                "TR_SAISIE_ACHAT", cols("ID", "ID_SAISIE_ACHAT", "ID_AVOIR_FOURNISSEUR"),
                "TR_DEVIS", cols("ID", "ID_DEVIS", "ID_COMMANDE", "ID_COMMANDE_CLIENT", "ID_SAISIE_VENTE_FACTURE", "ID_BON_DE_LIVRAISON"),
                "TR_COMMANDE_CLIENT", cols("ID", "ID_COMMANDE_CLIENT", "ID_SAISIE_VENTE_FACTURE", "ID_BON_DE_LIVRAISON", "ID_COMMANDE"),
                "TR_BON_DE_LIVRAISON", cols("ID", "ID_BON_DE_LIVRAISON", "ID_SAISIE_VENTE_FACTURE"),
                "TR_SAISIE_VENTE_FACTURE", cols("ID", "ID_SAISIE_VENTE_FACTURE", "ID_AVOIR_CLIENT", "ID_BON_DE_LIVRAISON", "ID_COMMANDE"));
        final List<AffairBackfillSupport.Repair> plan = AffairBackfillSupport.plan(schema(t), Q);
        assertEquals("facture depuis commande", Boolean.TRUE, Boolean.valueOf(find(plan, "FACTURE_FOURNISSEUR", "TR_COMMANDE") != null));
        assertEquals("facture depuis bon de reception", Boolean.TRUE, Boolean.valueOf(find(plan, "FACTURE_FOURNISSEUR", "TR_BON_RECEPTION") != null));
        assertEquals("saisie d'achat depuis commande", Boolean.TRUE, Boolean.valueOf(find(plan, "SAISIE_ACHAT", "SOURCE / IDSOURCE") != null));
        assertEquals("bon de reception depuis commande", Boolean.TRUE, Boolean.valueOf(find(plan, "BON_RECEPTION", "TR_COMMANDE") != null));
        assertEquals("facture de vente depuis commande client", Boolean.TRUE, Boolean.valueOf(find(plan, "SAISIE_VENTE_FACTURE", "TR_COMMANDE_CLIENT") != null));
        assertEquals("avoir client depuis facture", Boolean.TRUE, Boolean.valueOf(find(plan, "AVOIR_CLIENT", "TR_SAISIE_VENTE_FACTURE") != null));
        assertEquals("bon de livraison depuis commande client", Boolean.TRUE, Boolean.valueOf(find(plan, "BON_DE_LIVRAISON", "TR_COMMANDE_CLIENT") != null));
        assertEquals("plan consequent", Boolean.TRUE, Boolean.valueOf(plan.size() >= 8));
    }

    /**
     * Base reelle : {@code DEVIS} n'a pas de colonne {@code ID} mais
     * {@code ID_DEVIS}. Les quatre transferts partant d'un devis doivent utiliser
     * cette cle, sinon ils echouent et les documents issus d'un devis ne sont
     * jamais repris.
     */
    private static void testDevisWithOwnKey() {
        final String[] doc = cols("ID", "ID_AFFAIRE");
        final Map<String, String[]> t = tables(
                "DEVIS", cols("ID_DEVIS", "ID_AFFAIRE", "NUMERO"),
                "COMMANDE", doc,
                "COMMANDE_CLIENT", doc,
                "SAISIE_VENTE_FACTURE", doc,
                "BON_DE_LIVRAISON", doc,
                "TR_DEVIS", cols("ID", "ID_DEVIS", "ID_COMMANDE", "ID_COMMANDE_CLIENT", "ID_SAISIE_VENTE_FACTURE", "ID_BON_DE_LIVRAISON"));
        final AffairLinkSupport.Schema schema = schema(t);
        assertEquals("cle du devis", "ID_DEVIS", AffairBackfillSupport.keyOf(schema, "DEVIS"));
        assertEquals("cle d'une table standard", "ID", AffairBackfillSupport.keyOf(schema, "COMMANDE"));
        assertEquals("table inconnue", null, AffairBackfillSupport.keyOf(schema, "INCONNUE"));
        final List<AffairBackfillSupport.Repair> plan = AffairBackfillSupport.plan(schema, Q);
        final AffairBackfillSupport.Repair commande = find(plan, "COMMANDE", "TR_DEVIS");
        assertEquals("reprise commande depuis devis", Boolean.TRUE, Boolean.valueOf(commande != null));
        assertEquals("jointure sur ID_DEVIS", Boolean.TRUE, Boolean.valueOf(commande.getUpdateSql().contains("\"DEVIS\".\"ID_DEVIS\"")));
        assertEquals("aucune jointure sur DEVIS.ID", Boolean.FALSE, Boolean.valueOf(commande.getUpdateSql().contains("\"DEVIS\".\"ID\"")));
        int depuisDevis = 0;
        for (final AffairBackfillSupport.Repair repair : plan) {
            if (repair.getDescription().contains("TR_DEVIS")) {
                depuisDevis++;
            }
        }
        assertEquals("quatre reprises depuis le devis", Integer.valueOf(4), Integer.valueOf(depuisDevis));
    }

    /**
     * Ligne « Indefini » (ID 1) et cles etrangeres non renseignees (valeur 1) :
     * elles ne doivent jamais etre comptees ni mises a jour. Mesure sur la base
     * du client : sans ce garde-fou, 200 « saisies d'achat a reparer » alors
     * qu'il n'y en avait que 3 — les 200 etaient la meme ligne 1.
     */
    private static void testPlaceholderRowsAreIgnored() {
        final Map<String, String[]> t = tables(
                "COMMANDE", cols("ID", "ID_AFFAIRE"),
                "SAISIE_ACHAT", cols("ID", "ID_AFFAIRE", "SOURCE", "IDSOURCE"),
                "BON_RECEPTION", cols("ID", "ID_AFFAIRE"),
                "TR_COMMANDE", cols("ID", "ID_COMMANDE", "ID_BON_RECEPTION", "ID_SAISIE_ACHAT", "ID_FACTURE_FOURNISSEUR"),
                "COMMANDE_ELEMENT", cols("ID", "ID_AFFAIRE", "ID_COMMANDE"));
        final List<AffairBackfillSupport.Repair> plan = AffairBackfillSupport.plan(schema(t), Q);
        final AffairBackfillSupport.Repair source = find(plan, "SAISIE_ACHAT", "SOURCE / IDSOURCE");
        // la source et la cible doivent etre de vrais documents...
        assertEquals("source reelle", Boolean.TRUE, Boolean.valueOf(source.getUpdateSql().contains("\"COMMANDE\".\"ID\" > 1")));
        assertEquals("cible reelle", Boolean.TRUE, Boolean.valueOf(source.getUpdateSql().contains("\"SAISIE_ACHAT\".\"ID\" > 1")));
        assertEquals("lien reel", Boolean.TRUE, Boolean.valueOf(source.getUpdateSql().contains("\"SAISIE_ACHAT\".\"IDSOURCE\" > 1")));
        // ...et la ligne de transfert ne doit pas pointer la ligne 1
        final AffairBackfillSupport.Repair transfer = find(plan, "BON_RECEPTION", "TR_COMMANDE");
        assertEquals("cle de transfert reelle", Boolean.TRUE,
                Boolean.valueOf(transfer.getUpdateSql().contains("\"TR_COMMANDE\".\"ID_BON_RECEPTION\" > 1")));
        assertEquals("source du transfert reelle", Boolean.TRUE,
                Boolean.valueOf(transfer.getUpdateSql().contains("\"TR_COMMANDE\".\"ID_COMMANDE\" > 1")));
        // les lignes : ni la ligne 1 du document, ni un lien a 1
        final AffairBackfillSupport.Repair line = find(plan, "COMMANDE_ELEMENT", "lignes");
        assertEquals("document de la ligne reel", Boolean.TRUE,
                Boolean.valueOf(line.getUpdateSql().contains("\"COMMANDE\".\"ID\" > 1")));
        assertEquals("lien de la ligne reel", Boolean.TRUE,
                Boolean.valueOf(line.getUpdateSql().contains("\"COMMANDE_ELEMENT\".\"ID_COMMANDE\" > 1")));
        // la regle est publique et testable seule
        assertEquals("realKey", "\"T\".\"ID\" > 1", AffairBackfillSupport.realKey(Q, "T", "ID"));
        assertEquals("realKey sans cle", "1 = 1", AffairBackfillSupport.realKey(Q, "T", null));
    }

    /**
     * Les requetes de comptage doivent etre acceptees par PostgreSQL, pas
     * seulement par SQLite.
     * <p>
     * Sur la base du client, les 19 comptages echouaient et le menu annoncait
     * « rien a reprendre ». Deux causes, toutes deux verifiees sur PostgreSQL 16 :
     * une colonne {@code SOURCE} non qualifiee (« column reference \"SOURCE\" is
     * ambiguous ») et la condition de la table source placee dans le premier
     * {@code ON}, avant que cette table soit jointe (« invalid reference to
     * FROM-clause entry »).
     * </p>
     */
    private static void testCountSqlScope() {
        // 1. colonne qualifiee, meme si la table jointe porte le meme nom.
        final Map<String, String[]> sources = tables(
                "SAISIE_ACHAT", cols("ID", "ID_AFFAIRE", "SOURCE", "IDSOURCE"),
                "COMMANDE", cols("ID", "ID_AFFAIRE", "SOURCE"));
        final AffairBackfillSupport.Repair source = find(AffairBackfillSupport.plan(schema(sources), Q), "SAISIE_ACHAT", "SOURCE / IDSOURCE");
        final String sourceSql = source.getCountSql();
        assertEquals("SOURCE qualifiee", Boolean.TRUE, Boolean.valueOf(sourceSql.contains("\"SAISIE_ACHAT\".\"SOURCE\" = 'COMMANDE'")));
        assertEquals("jamais \"SOURCE\" nu", Boolean.FALSE, Boolean.valueOf(sourceSql.contains("WHERE \"SOURCE\"")));

        // 2. le premier ON ne cite que la cible et la table de transfert.
        final Map<String, String[]> transferts = tables(
                "COMMANDE", cols("ID", "ID_AFFAIRE"),
                "FACTURE_FOURNISSEUR", cols("ID", "ID_AFFAIRE"),
                "TR_COMMANDE", cols("ID", "ID_COMMANDE", "ID_FACTURE_FOURNISSEUR"));
        final AffairBackfillSupport.Repair transfer = find(AffairBackfillSupport.plan(schema(transferts), Q), "FACTURE_FOURNISSEUR", "TR_COMMANDE");
        final String count = transfer.getCountSql();
        final int firstJoin = count.indexOf("INNER JOIN \"TR_COMMANDE\" ON ");
        final int sourceJoin = count.indexOf("INNER JOIN \"COMMANDE\"", firstJoin);
        assertEquals("la table de transfert est jointe", Boolean.TRUE, Boolean.valueOf(firstJoin > 0));
        assertEquals("la source est jointe apres", Boolean.TRUE, Boolean.valueOf(sourceJoin > firstJoin));
        final String firstOn = count.substring(firstJoin, sourceJoin);
        assertEquals("premier ON : pas de reference a la source", Boolean.FALSE, Boolean.valueOf(firstOn.contains("\"COMMANDE\".\"")));
        assertEquals("premier ON : la cible est bien jointe", Boolean.TRUE, Boolean.valueOf(firstOn.contains("\"FACTURE_FOURNISSEUR\".\"ID\"")));
        assertEquals("second ON : la source est jointe sur la table de transfert", Boolean.TRUE,
                Boolean.valueOf(count.substring(sourceJoin).contains("\"TR_COMMANDE\".\"ID_COMMANDE\" = \"COMMANDE\".\"ID\"")));
        // 3. la mise a jour, elle, garde les deux conditions (les deux tables y sont visibles).
        assertEquals("UPDATE : les deux conditions", Boolean.TRUE,
                Boolean.valueOf(transfer.getUpdateSql().contains("AND \"TR_COMMANDE\".\"ID_COMMANDE\" = \"COMMANDE\".\"ID\"")));
    }

    /**
     * Table de documents sans aucune colonne de cle : la paire est ignoree, elle
     * produirait une jointure impossible.
     */
    private static void testTableWithoutKeyIsSkipped() {
        final String[] doc = cols("ID", "ID_AFFAIRE");
        final Map<String, String[]> t = tables(
                "COMMANDE", doc,
                "COMMANDE_CLIENT", doc,
                "SAISIE_VENTE_FACTURE", doc,
                "BON_DE_LIVRAISON", doc,
                "DEVIS", cols("ID_AFFAIRE", "NUMERO"),
                "TR_DEVIS", cols("ID", "ID_DEVIS", "ID_COMMANDE", "ID_COMMANDE_CLIENT", "ID_SAISIE_VENTE_FACTURE", "ID_BON_DE_LIVRAISON"),
                "TR_COMMANDE_CLIENT", cols("ID", "ID_COMMANDE_CLIENT", "ID_SAISIE_VENTE_FACTURE", "ID_BON_DE_LIVRAISON", "ID_COMMANDE"));
        final List<AffairBackfillSupport.Repair> plan = AffairBackfillSupport.plan(schema(t), Q);
        assertEquals("devis sans cle : aucune reprise depuis le devis", null, find(plan, "COMMANDE", "TR_DEVIS"));
        assertEquals("devis sans cle : aucune reprise vers la commande client", null, find(plan, "COMMANDE_CLIENT", "TR_DEVIS"));
        assertEquals("devis sans cle : aucune reprise vers la facture de vente", null, find(plan, "SAISIE_VENTE_FACTURE", "TR_DEVIS"));
        assertEquals("devis sans cle : aucune reprise vers le bon de livraison", null, find(plan, "BON_DE_LIVRAISON", "TR_DEVIS"));
        // les transferts sans devis restent generes
        assertEquals("reprise commande client -> facture conservee", Boolean.TRUE,
                Boolean.valueOf(find(plan, "SAISIE_VENTE_FACTURE", "TR_COMMANDE_CLIENT") != null));
        assertEquals("reprise commande client -> bon de livraison conservee", Boolean.TRUE,
                Boolean.valueOf(find(plan, "BON_DE_LIVRAISON", "TR_COMMANDE_CLIENT") != null));
        // et aucune requete ne parle du devis
        for (final AffairBackfillSupport.Repair repair : plan) {
            assertEquals("aucune requete sur DEVIS : " + repair.getDescription(),
                    Boolean.FALSE, Boolean.valueOf(repair.getUpdateSql().contains("\"DEVIS\"")));
        }
    }

    private static void testEmptyAndRealAffairPredicates() {
        assertEquals("vide", "(\"T\".\"ID_AFFAIRE\" IS NULL OR \"T\".\"ID_AFFAIRE\" = 1)", AffairBackfillSupport.emptyAffair(Q, "T"));
        assertEquals("reelle", "(\"T\".\"ID_AFFAIRE\" IS NOT NULL AND \"T\".\"ID_AFFAIRE\" > 1)", AffairBackfillSupport.realAffair(Q, "T"));
    }

    private static void testNullSchema() {
        assertEquals("schema nul", Integer.valueOf(0), Integer.valueOf(AffairBackfillSupport.plan(null, Q).size()));
        assertEquals("quoter nul", Integer.valueOf(0), Integer.valueOf(AffairBackfillSupport.plan(schema(tables("COMMANDE", cols("ID"))), null).size()));
    }

    private static void testDescriptions() {
        final Map<String, String[]> t = tables(
                "COMMANDE", cols("ID", "ID_AFFAIRE"),
                "FACTURE_FOURNISSEUR", cols("ID", "ID_AFFAIRE"),
                "TR_COMMANDE", cols("ID", "ID_COMMANDE", "ID_FACTURE_FOURNISSEUR"));
        final AffairBackfillSupport.Repair repair = find(AffairBackfillSupport.plan(schema(t), Q), "FACTURE_FOURNISSEUR", "TR_COMMANDE");
        assertEquals("description claire", "FACTURE_FOURNISSEUR <- COMMANDE (via TR_COMMANDE)", repair.getDescription());
        assertEquals("toString", "FACTURE_FOURNISSEUR : FACTURE_FOURNISSEUR <- COMMANDE (via TR_COMMANDE)", repair.toString());
    }
}
