package org.openconcerto.modules.project;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Tests des regles de rattachement a une affaire.
 * <p>
 * Chaque test correspond a un scenario reel constate (ou redoute) en
 * production : colonne absente, colonne presente mais vide, ligne rattachee
 * seulement au document parent, affaire indefinie, onglet dont la table
 * disparait, etc.
 */
public final class AffairLinkSupportTest {

    private static int testCount;
    private static final List<String> failures = new ArrayList<String>();

    public static void main(final String[] args) {
        // 1. Couverture du module : quelles tables doivent porter ID_AFFAIRE.
        testSupplierInvoiceIsCovered();
        testSupplierOrderIsCovered();
        testDirectTablesHaveNoDuplicate();
        testEveryDirectTableHasATabOrIsDocumented();
        testDocumentTabsCoverSupplierOrderAndInvoice();

        // 2. Plan de filtrage des onglets d'historique.
        testDirectLinkWhenColumnExists();
        testViaParentWhenColumnMissing();
        testUnavailableWhenNothingCanLink();
        testUnavailableWhenTableMissing();
        testUnavailableWhenParentHasNoAffair();
        testMissingChildColumnBreaksParentLink();
        testUnknownTableIsUnavailable();
        testNullSchemaIsUnavailable();
        testKnownParentLinkIsUsedAutomatically();
        testExplicitParentLinkWinsOverKnownOne();
        testPreferParentUsesParentEvenWhenChildHasColumn();
        testPreferParentFallsBackToDirectWithoutParent();
        testLineTablesAreFilteredByTheirDocument();

        // 3. Predicats SQL produits pour l'historique.
        testDirectPredicate();
        testViaParentPredicate();
        testUnavailableHasNoPredicate();

        // 4. Valeurs d'affaire.
        testRealAffairValues();

        // 5. Auto-reparation du schema.
        testMissingAffairColumnsOnExistingInstall();
        testNothingMissingOnCleanSchema();
        testMissingColumnsIgnoreAbsentTables();
        testMissingColumnsAreStableAndIdempotent();

        // 5 bis. Fermeture de l'historique : jamais d'exception.
        testCleanupSkipsUnbuiltPanel();
        testCleanupRunsOnBuiltPanel();
        testCleanupAcceptsUnknownPanelType();
        testMissingColumnsNeverCreateLineColumns();
        testMigrationPlanCoversSupplierInvoiceAndOrder();

        // 6. Ecrans de saisie.
        testComponentFieldsExposeSupplierInvoiceAndOrder();
        testComponentFieldsDoNotIncludeDevis();
        testComponentFieldsRequireTheColumn();

        // 7. Diagnostics.
        testAmbiguousLineTablesDetected();
        testAmbiguousLineTablesEmptyOnCleanSchema();
        testUncoveredTablesDetected();

        // 8. Verification croisee avec le script SQL de migration.
        testSqlMigrationScriptMatchesJavaList();

        System.out.println("AffairLinkSupportTest : " + testCount + " tests OK");
        if (!failures.isEmpty()) {
            for (final String failure : failures) {
                System.err.println(failure);
            }
            throw new AssertionError(failures.size() + " test(s) en echec");
        }
    }

    // ------------------------------------------------------------------
    // 1. Couverture du module
    // ------------------------------------------------------------------

    /**
     * Regression du bug principal : sans FACTURE_FOURNISSEUR dans la liste, la
     * facture fournisseur n'a ni colonne « Affaire », ni action « Historique
     * affaire », et l'affaire saisie reste invisible dans l'ERP.
     */
    private static void testSupplierInvoiceIsCovered() {
        assertTrue("FACTURE_FOURNISSEUR doit porter ID_AFFAIRE", AffairLinkSupport.DIRECT_AFFAIR_TABLES.contains("FACTURE_FOURNISSEUR"));
        pass();
    }

    private static void testSupplierOrderIsCovered() {
        assertTrue("COMMANDE doit porter ID_AFFAIRE", AffairLinkSupport.DIRECT_AFFAIR_TABLES.contains("COMMANDE"));
        pass();
    }

    private static void testDirectTablesHaveNoDuplicate() {
        final Set<String> unique = new LinkedHashSet<String>(AffairLinkSupport.DIRECT_AFFAIR_TABLES);
        assertEquals("pas de doublon dans DIRECT_AFFAIR_TABLES", AffairLinkSupport.DIRECT_AFFAIR_TABLES.size(), unique.size());
        assertTrue("la table AFFAIRE elle-meme n'est pas dans la liste", !unique.contains(AffairLinkSupport.AFFAIR_TABLE));
        pass();
    }

    private static void testEveryDirectTableHasATabOrIsDocumented() {
        final List<String> withoutTab = AffairLinkSupport.getDocumentTablesWithoutTab();
        // Seules les tables de lignes (rattachees via leur parent) n'ont pas
        // d'onglet propre. Toute autre table doit avoir un onglet, sinon un
        // document rattache a une affaire resterait invisible.
        for (final String table : withoutTab) {
            assertTrue("table sans onglet mais rattachable directement : " + table, AffairLinkSupport.findParentLink(table) != null);
        }
        pass();
    }

    private static void testDocumentTabsCoverSupplierOrderAndInvoice() {
        final Map<String, String> tabs = AffairLinkSupport.getDocumentTabs();
        assertTrue("onglet Commandes fournisseurs", tabs.containsValue("COMMANDE"));
        assertTrue("onglet Factures fournisseurs", tabs.containsValue("FACTURE_FOURNISSEUR"));
        assertEquals("libelle de l'onglet commande", "COMMANDE", tabs.get("Commandes fournisseurs"));
        assertEquals("libelle de l'onglet facture", "FACTURE_FOURNISSEUR", tabs.get("Factures fournisseurs"));
        pass();
    }

    // ------------------------------------------------------------------
    // 2. Plan de filtrage
    // ------------------------------------------------------------------

    private static void testDirectLinkWhenColumnExists() {
        final AffairLinkSupport.Schema schema = schema("COMMANDE", "FACTURE_FOURNISSEUR");
        final AffairLinkSupport.TabLink tab = AffairLinkSupport.planTab("FACTURE_FOURNISSEUR", schema, null);
        assertTrue("lien direct attendu", tab.isDirect());
        assertTrue("onglet disponible", tab.isAvailable());
        assertEquals("pas de parent pour un lien direct", null, tab.getParentTable());
        pass();
    }

    private static void testViaParentWhenColumnMissing() {
        final AffairLinkSupport.Schema schema = schemaFields("COMMANDE_ELEMENT=ID_COMMANDE,DESIGNATION", "COMMANDE=ID_AFFAIRE,NUMERO");
        final AffairLinkSupport.TabLink tab = AffairLinkSupport.planTab("COMMANDE_ELEMENT", schema, null);
        assertTrue("lien via parent attendu", tab.isViaParent());
        assertEquals("parent", "COMMANDE", tab.getParentTable());
        assertEquals("colonne de liaison", "ID_COMMANDE", tab.getParentField());
        pass();
    }

    private static void testUnavailableWhenNothingCanLink() {
        final AffairLinkSupport.Schema schema = schemaFields("FACTURE_FOURNISSEUR=NUMERO,T_HT", "FACTURE_FOURNISSEUR_ELEMENT=ID_FACTURE_FOURNISSEUR");
        // ni colonne sur la facture, ni parent rattachable : l'onglet doit etre
        // ignore proprement (et non lever une exception qui casserait la boucle
        // de selection de tous les onglets).
        final AffairLinkSupport.TabLink tab = AffairLinkSupport.planTab("FACTURE_FOURNISSEUR", schema, null);
        assertTrue("onglet indisponible", !tab.isAvailable());
        assertTrue("pas de predicat", AffairLinkSupport.buildSelectionPredicate(tab, 42, "t", "ID") == null);
        pass();
    }

    private static void testUnavailableWhenTableMissing() {
        final AffairLinkSupport.TabLink tab = AffairLinkSupport.planTab("SAISIE_ACHAT", schema("COMMANDE"), null);
        assertTrue("table absente : indisponible", !tab.isAvailable());
        assertTrue("raison mentionnee", tab.getReason().contains("absente"));
        pass();
    }

    private static void testUnavailableWhenParentHasNoAffair() {
        final AffairLinkSupport.Schema schema = AffairLinkSupport.schemaOf(new LinkedHashSet<String>(Arrays.asList("COMMANDE_ELEMENT", "COMMANDE")),
                fieldsOf("COMMANDE_ELEMENT=ID_COMMANDE", "COMMANDE=NUMERO"));
        final AffairLinkSupport.TabLink tab = AffairLinkSupport.planTab("COMMANDE_ELEMENT", schema, null);
        assertTrue("parent sans affaire : indisponible", !tab.isAvailable());
        assertEquals("raison", true, tab.getReason().contains("ni ID_AFFAIRE"));
        pass();
    }

    private static void testMissingChildColumnBreaksParentLink() {
        // Cas reel : une table de lignes sans ID_COMMANDE ne peut pas etre
        // rattachee, meme si la commande porte l'affaire.
        final AffairLinkSupport.Schema schema = AffairLinkSupport.schemaOf(new LinkedHashSet<String>(Arrays.asList("COMMANDE_ELEMENT", "COMMANDE")),
                fieldsOf("COMMANDE_ELEMENT=DESIGNATION", "COMMANDE=ID_AFFAIRE"));
        final AffairLinkSupport.TabLink tab = AffairLinkSupport.planTab("COMMANDE_ELEMENT", schema, null);
        assertTrue("lien impossible sans colonne de liaison", !tab.isAvailable());
        pass();
    }

    private static void testUnknownTableIsUnavailable() {
        assertTrue("table null", !AffairLinkSupport.planTab(null, schema("COMMANDE"), null).isAvailable());
        pass();
    }

    private static void testNullSchemaIsUnavailable() {
        assertTrue("schema null", !AffairLinkSupport.planTab("COMMANDE", null, null).isAvailable());
        pass();
    }

    private static void testKnownParentLinkIsUsedAutomatically() {
        final AffairLinkSupport.Schema schema = schemaFields("BON_RECEPTION_ELEMENT=ID_BON_RECEPTION", "BON_RECEPTION=ID_AFFAIRE");
        final AffairLinkSupport.TabLink tab = AffairLinkSupport.planTab("BON_RECEPTION_ELEMENT", schema, null);
        assertTrue("parent connu detecte", tab.isViaParent());
        assertEquals("parent", "BON_RECEPTION", tab.getParentTable());
        pass();
    }

    private static void testExplicitParentLinkWinsOverKnownOne() {
        final AffairLinkSupport.Schema schema = schemaFields("COMMANDE_ELEMENT=ID_COMMANDE", "COMMANDE=ID_AFFAIRE", "BON_RECEPTION=ID_AFFAIRE");
        final AffairLinkSupport.TabLink tab = AffairLinkSupport.planTab("COMMANDE_ELEMENT", schema,
                new AffairLinkSupport.ParentLink("COMMANDE_ELEMENT", "ID_COMMANDE", "BON_RECEPTION"));
        assertEquals("parent explicite", "BON_RECEPTION", tab.getParentTable());
        pass();
    }

    /**
     * Regle « aucune ligne cachee » : pour une table de lignes, on filtre via le
     * document meme si la colonne de ligne existe (elle est souvent vide).
     */
    private static void testPreferParentUsesParentEvenWhenChildHasColumn() {
        final AffairLinkSupport.Schema schema = schemaFields("COMMANDE_ELEMENT=ID_COMMANDE,ID_AFFAIRE", "COMMANDE=ID_AFFAIRE");
        final AffairLinkSupport.ParentLink link = new AffairLinkSupport.ParentLink("COMMANDE_ELEMENT", "ID_COMMANDE", "COMMANDE");
        final AffairLinkSupport.TabLink tab = AffairLinkSupport.planTab("COMMANDE_ELEMENT", schema, link, true);
        assertTrue("filtrage via le document", tab.isViaParent());
        assertEquals("parent", "COMMANDE", tab.getParentTable());
        final AffairLinkSupport.TabLink withoutPreference = AffairLinkSupport.planTab("COMMANDE_ELEMENT", schema, link, false);
        assertTrue("sans preference, la colonne de ligne gagne", withoutPreference.isDirect());
        pass();
    }

    private static void testPreferParentFallsBackToDirectWithoutParent() {
        final AffairLinkSupport.Schema schema = schema("FACTURE_FOURNISSEUR");
        final AffairLinkSupport.TabLink tab = AffairLinkSupport.planTab("FACTURE_FOURNISSEUR", schema, null, true);
        assertTrue("lien direct faute de parent", tab.isDirect());
        pass();
    }

    private static void testLineTablesAreFilteredByTheirDocument() {
        // Les tables de lignes suivies par le module doivent passer par leur
        // document : c'est ce qui evite que les lignes sans affaire de ligne
        // disparaissent de l'historique.
        final String[] lineTables = { "COMMANDE_ELEMENT", "BON_RECEPTION_ELEMENT" };
        final String[] parents = { "COMMANDE", "BON_RECEPTION" };
        for (int i = 0; i < lineTables.length; i++) {
            final AffairLinkSupport.ParentLink link = AffairLinkSupport.findParentLink(lineTables[i]);
            assertTrue("parent declare pour " + lineTables[i], link != null);
            assertEquals("parent de " + lineTables[i], parents[i], link.getParentTable());
            final AffairLinkSupport.Schema schema = schemaFields(lineTables[i] + "=" + link.getChildField() + ",ID_AFFAIRE", parents[i] + "=ID_AFFAIRE");
            final AffairLinkSupport.TabLink tab = AffairLinkSupport.planTab(lineTables[i], schema, link, true);
            assertTrue(lineTables[i] + " filtree via son document", tab.isViaParent());
        }
        pass();
    }

    // ------------------------------------------------------------------
    // 3. Predicats
    // ------------------------------------------------------------------

    private static void testDirectPredicate() {
        final AffairLinkSupport.TabLink tab = AffairLinkSupport.planTab("FACTURE_FOURNISSEUR", schema("FACTURE_FOURNISSEUR"), null);
        assertEquals("predicat direct", "t.\"ID_AFFAIRE\" = 330", AffairLinkSupport.buildSelectionPredicate(tab, 330, "t", "ID"));
        pass();
    }

    private static void testViaParentPredicate() {
        final AffairLinkSupport.Schema schema = schemaFields("COMMANDE_ELEMENT=ID_COMMANDE", "COMMANDE=ID_AFFAIRE");
        final AffairLinkSupport.TabLink tab = AffairLinkSupport.planTab("COMMANDE_ELEMENT", schema, null);
        assertEquals("predicat indirect", "t.\"ID_COMMANDE\" in (select p.\"ID\" from \"COMMANDE\" p where p.\"ID_AFFAIRE\" = 330)",
                AffairLinkSupport.buildSelectionPredicate(tab, 330, "t", "ID"));
        pass();
    }

    private static void testUnavailableHasNoPredicate() {
        final AffairLinkSupport.TabLink tab = AffairLinkSupport.planTab("SAISIE_ACHAT", schema("COMMANDE"), null);
        assertEquals("pas de predicat", null, AffairLinkSupport.buildSelectionPredicate(tab, 330, "t", "ID"));
        pass();
    }

    // ------------------------------------------------------------------
    // 4. Valeurs d'affaire
    // ------------------------------------------------------------------

    private static void testRealAffairValues() {
        assertTrue("null n'est pas une affaire", !AffairLinkSupport.isRealAffair(null));
        assertTrue("1 (indefini) n'est pas une affaire", !AffairLinkSupport.isRealAffair(Integer.valueOf(1)));
        assertTrue("0 n'est pas une affaire", !AffairLinkSupport.isRealAffair(Integer.valueOf(0)));
        assertTrue("330 est une affaire", AffairLinkSupport.isRealAffair(Integer.valueOf(330)));
        pass();
    }

    // ------------------------------------------------------------------
    // 5. Auto-reparation du schema
    // ------------------------------------------------------------------

    /**
     * Etat d'une installation existante : le module est deja installe (donc
     * {@code install()} n'est plus rejoue) et les colonnes ajoutees par la
     * version d'origine manquent sur les documents fournisseurs.
     */
    private static void testMissingAffairColumnsOnExistingInstall() {
        final AffairLinkSupport.Schema schema = AffairLinkSupport.schemaOf(
                new LinkedHashSet<String>(Arrays.asList("DEVIS", "COMMANDE_CLIENT", "COMMANDE", "FACTURE_FOURNISSEUR", "SAISIE_ACHAT")),
                fieldsOf("DEVIS=ID_AFFAIRE", "COMMANDE_CLIENT=ID_AFFAIRE", "COMMANDE=NUMERO", "FACTURE_FOURNISSEUR=NUMERO", "SAISIE_ACHAT=MONTANT_HT"));
        final List<String> missing = AffairLinkSupport.getMissingAffairColumns(schema);
        assertEquals("colonnes manquantes", Arrays.asList("COMMANDE", "FACTURE_FOURNISSEUR", "SAISIE_ACHAT"), missing);
        pass();
    }

    private static void testNothingMissingOnCleanSchema() {
        final Set<String> tables = new LinkedHashSet<String>(AffairLinkSupport.DIRECT_AFFAIR_TABLES);
        final List<String> specs = new ArrayList<String>();
        for (final String table : tables) {
            specs.add(table + "=" + AffairLinkSupport.AFFAIR_FIELD);
        }
        final AffairLinkSupport.Schema schema = AffairLinkSupport.schemaOf(tables, fieldsOf(specs.toArray(new String[specs.size()])));
        assertEquals("aucune colonne a creer", Collections.emptyList(), AffairLinkSupport.getMissingAffairColumns(schema));
        pass();
    }

    private static void testMissingColumnsIgnoreAbsentTables() {
        final AffairLinkSupport.Schema schema = AffairLinkSupport.schemaOf(new LinkedHashSet<String>(Arrays.asList("COMMANDE")), fieldsOf("COMMANDE=NUMERO"));
        assertEquals("une seule table presente", Arrays.asList("COMMANDE"), AffairLinkSupport.getMissingAffairColumns(schema));
        pass();
    }

    private static void testMissingColumnsAreStableAndIdempotent() {
        final AffairLinkSupport.Schema schema = AffairLinkSupport.schemaOf(new LinkedHashSet<String>(Arrays.asList("COMMANDE")), fieldsOf("COMMANDE=NUMERO"));
        final List<String> first = AffairLinkSupport.getMissingAffairColumns(schema);
        final List<String> second = AffairLinkSupport.getMissingAffairColumns(schema);
        assertEquals("deux appels identiques", first, second);
        // une fois la colonne creee, plus rien a faire
        final AffairLinkSupport.Schema after = AffairLinkSupport.schemaOf(new LinkedHashSet<String>(Arrays.asList("COMMANDE")), fieldsOf("COMMANDE=NUMERO,ID_AFFAIRE"));
        assertEquals("apres migration, plus rien", Collections.emptyList(), AffairLinkSupport.getMissingAffairColumns(after));
        pass();
    }

    private static void testMissingColumnsNeverCreateLineColumns() {
        // La migration ne doit JAMAIS ajouter ID_AFFAIRE sur une table de
        // lignes : cela desactiverait le filtrage via le document parent.
        for (final AffairLinkSupport.ParentLink link : AffairLinkSupport.PARENT_LINKS) {
            assertTrue("pas de colonne de ligne dans la migration : " + link.getChildTable(),
                    !AffairLinkSupport.DIRECT_AFFAIR_TABLES.contains(link.getChildTable()));
        }
        pass();
    }

    private static void testMigrationPlanCoversSupplierInvoiceAndOrder() {
        final AffairLinkSupport.Schema schema = AffairLinkSupport.schemaOf(new LinkedHashSet<String>(Arrays.asList("COMMANDE", "FACTURE_FOURNISSEUR")),
                fieldsOf("COMMANDE=NUMERO", "FACTURE_FOURNISSEUR=NUMERO"));
        final List<String> missing = AffairLinkSupport.getMissingAffairColumns(schema);
        assertTrue("commande fournisseur migree", missing.contains("COMMANDE"));
        assertTrue("facture fournisseur migree", missing.contains("FACTURE_FOURNISSEUR"));
        pass();
    }

    // ------------------------------------------------------------------
    // 6. Ecrans de saisie
    // ------------------------------------------------------------------

    private static void testComponentFieldsExposeSupplierInvoiceAndOrder() {
        final AffairLinkSupport.Schema schema = schema("COMMANDE", "FACTURE_FOURNISSEUR", "COMMANDE_CLIENT");
        final List<String> tables = AffairLinkSupport.getComponentFieldTables(schema);
        assertTrue("champ Affaire sur la commande fournisseur", tables.contains("COMMANDE"));
        assertTrue("champ Affaire sur la facture fournisseur", tables.contains("FACTURE_FOURNISSEUR"));
        assertTrue("champ Affaire sur la commande client", tables.contains("COMMANDE_CLIENT"));
        pass();
    }

    private static void testComponentFieldsDoNotIncludeDevis() {
        final AffairLinkSupport.Schema schema = schema("DEVIS", "COMMANDE");
        assertTrue("DEVIS a son propre ecran", !AffairLinkSupport.getComponentFieldTables(schema).contains("DEVIS"));
        pass();
    }

    private static void testComponentFieldsRequireTheColumn() {
        final AffairLinkSupport.Schema schema = AffairLinkSupport.schemaOf(new LinkedHashSet<String>(Arrays.asList("COMMANDE")), fieldsOf("COMMANDE=NUMERO"));
        assertEquals("pas de champ sans colonne", Collections.emptyList(), AffairLinkSupport.getComponentFieldTables(schema));
        pass();
    }

    // ------------------------------------------------------------------
    // 7. Diagnostics
    // ------------------------------------------------------------------

    /**
     * Configuration piegeante reellement presente chez le client : la table de
     * lignes porte son propre ID_AFFAIRE, donc l'historique filtre dessus et les
     * lignes dont l'affaire est vide disparaissent.
     */
    private static void testAmbiguousLineTablesDetected() {
        final AffairLinkSupport.Schema schema = schema("COMMANDE_ELEMENT", "COMMANDE", "FACTURE_FOURNISSEUR_ELEMENT", "FACTURE_FOURNISSEUR");
        final List<String> ambiguous = AffairLinkSupport.getAmbiguousLineTables(schema);
        assertTrue("COMMANDE_ELEMENT signalee", ambiguous.contains("COMMANDE_ELEMENT"));
        assertTrue("FACTURE_FOURNISSEUR_ELEMENT signalee", ambiguous.contains("FACTURE_FOURNISSEUR_ELEMENT"));
        pass();
    }

    private static void testAmbiguousLineTablesEmptyOnCleanSchema() {
        final AffairLinkSupport.Schema schema = schemaFields("COMMANDE_ELEMENT=ID_COMMANDE", "COMMANDE=ID_AFFAIRE");
        assertEquals("aucune ambiguite", Collections.emptyList(), AffairLinkSupport.getAmbiguousLineTables(schema));
        pass();
    }

    private static void testUncoveredTablesDetected() {
        final AffairLinkSupport.Schema schema = schema("COMMANDE", "FACTURE_FOURNISSEUR", "SAISIE_ACHAT");
        final List<String> covered = Arrays.asList("COMMANDE", "FACTURE_FOURNISSEUR");
        assertEquals("SAISIE_ACHAT oubliee", Arrays.asList("SAISIE_ACHAT"), AffairLinkSupport.getUncoveredTables(schema, covered));
        pass();
    }

    // ------------------------------------------------------------------
    // 8. Le script SQL de migration doit rester aligne sur le Java
    // ------------------------------------------------------------------

    /**
     * Empeche la derive entre {@link AffairLinkSupport#DIRECT_AFFAIR_TABLES} et
     * {@code tests/sql/migration-affaire-fournisseur.sql} : le test lit le
     * script et verifie qu'il couvre exactement les memes tables.
     */
    private static void testSqlMigrationScriptMatchesJavaList() {
        final java.io.File script = new java.io.File("tests/sql/migration-affaire-fournisseur.sql");
        if (!script.isFile()) {
            System.out.println("  (script SQL absent, verification ignoree : " + script.getAbsolutePath() + ")");
            pass();
            return;
        }
        final List<String> expected = new ArrayList<String>(AffairLinkSupport.DIRECT_AFFAIR_TABLES);
        Collections.sort(expected);
        final List<String> markers = new ArrayList<String>(readMarkedTables(script));
        Collections.sort(markers);
        assertEquals("tables annoncees par le script SQL", expected, markers);
        final List<String> alterations = new ArrayList<String>(readAlteredTables(script));
        Collections.sort(alterations);
        assertEquals("tables reellement modifiees par le script SQL", expected, alterations);
        pass();
    }

    /** Tables annoncees par les lignes « -- table: NOM ». */
    private static List<String> readMarkedTables(final java.io.File file) {
        final List<String> result = new ArrayList<String>();
        for (final String line : readLines(file)) {
            final String trimmed = line.trim();
            if (trimmed.startsWith("-- table:")) {
                result.add(trimmed.substring("-- table:".length()).trim());
            }
        }
        return result;
    }

    /** Tables effectivement modifiees par un « alter table ... add column ID_AFFAIRE ». */
    private static List<String> readAlteredTables(final java.io.File file) {
        final List<String> result = new ArrayList<String>();
        for (final String line : readLines(file)) {
            final String trimmed = line.trim().toLowerCase();
            if (!trimmed.startsWith("alter table") || trimmed.indexOf("add column") < 0) {
                continue;
            }
            // alter table "__SCHEMA__"."COMMANDE" add column if not exists "ID_AFFAIRE" integer;
            final int firstQuote = trimmed.indexOf('"');
            final int secondQuote = trimmed.indexOf('"', firstQuote + 1);
            final int thirdQuote = trimmed.indexOf('"', secondQuote + 1);
            final int fourthQuote = trimmed.indexOf('"', thirdQuote + 1);
            if (firstQuote < 0 || fourthQuote < 0) {
                throw new AssertionError("ligne SQL illisible : " + line);
            }
            result.add(trimmed.substring(thirdQuote + 1, fourthQuote).toUpperCase());
        }
        return result;
    }

    private static List<String> readLines(final java.io.File file) {
        final List<String> result = new ArrayList<String>();
        try {
            final java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.InputStreamReader(new java.io.FileInputStream(file), "UTF-8"));
            try {
                String line;
                while ((line = reader.readLine()) != null) {
                    result.add(line);
                }
            } finally {
                reader.close();
            }
        } catch (java.io.IOException e) {
            throw new AssertionError("lecture impossible de " + file + " : " + e);
        }
        return result;
    }

    // ------------------------------------------------------------------
    // Outils
    // ------------------------------------------------------------------

    /**
     * Schema de test : chaque table nommee porte ID_AFFAIRE.
     */
    private static AffairLinkSupport.Schema schema(final String... tables) {
        final Set<String> tableSet = new LinkedHashSet<String>(Arrays.asList(tables));
        final List<String> specs = new ArrayList<String>();
        for (final String table : tables) {
            specs.add(table + "=ID_AFFAIRE");
        }
        return AffairLinkSupport.schemaOf(tableSet, fieldsOf(specs.toArray(new String[specs.size()])));
    }

    // ------------------------------------------------------------------
    // Fermeture de l'historique (trace « UncaughtException » corrigee)
    // ------------------------------------------------------------------

    /** Panneau de test reproduisant le champ interne du coeur. */
    public static final class FakePanelWithLeftList {
        @SuppressWarnings("unused")
        private Object jListePanel;

        FakePanelWithLeftList(final boolean built) {
            this.jListePanel = built ? new Object() : null;
        }
    }

    /** Panneau de test sans le champ interne (autre version du client). */
    public static final class FakePanelOtherVersion {
    }

    /**
     * Cas du plantage : {@code jListePanel == null} (liste de gauche non
     * construite). Le nettoyage doit etre ignore, sans exception.
     */
    private static void testCleanupSkipsUnbuiltPanel() {
        assertTrue("panneau non construit : pas de nettoyage", !HistoryPanelCleanup.isReadyForCleanup(new FakePanelWithLeftList(false)));
        assertTrue("panneau null : pas de nettoyage", !HistoryPanelCleanup.isReadyForCleanup(null));
        final String reason = HistoryPanelCleanup.describe(new FakePanelWithLeftList(false));
        assertTrue("raison explicite (" + reason + ")", reason.contains("jListePanel null"));
        pass();
    }

    private static void testCleanupRunsOnBuiltPanel() {
        assertTrue("panneau construit : nettoyage autorise", HistoryPanelCleanup.isReadyForCleanup(new FakePanelWithLeftList(true)));
        assertTrue("decision loguee", HistoryPanelCleanup.describe(new FakePanelWithLeftList(true)).contains("nettoyage"));
        pass();
    }

    /** Version du client ou le champ n'existe pas : on ne bloque pas. */
    private static void testCleanupAcceptsUnknownPanelType() {
        assertTrue("champ absent : nettoyage autorise", HistoryPanelCleanup.isReadyForCleanup(new FakePanelOtherVersion()));
        assertEquals("champ recherche", HistoryPanelCleanup.REQUIRED_FIELD, "jListePanel");
        pass();
    }

    /**
     * Schema de test ou les champs sont donnes explicitement :
     * {@code schemaFields("COMMANDE_ELEMENT=ID_COMMANDE", "COMMANDE=ID_AFFAIRE")}.
     */
    private static AffairLinkSupport.Schema schemaFields(final String... specs) {
        final Set<String> tables = new LinkedHashSet<String>();
        for (final String spec : specs) {
            tables.add(spec.substring(0, spec.indexOf('=')));
        }
        return AffairLinkSupport.schemaOf(tables, fieldsOf(specs));
    }

    /** Construit une map table -&gt; champs depuis "TABLE=CHAMP1,CHAMP2". */
    private static Map<String, Set<String>> fieldsOf(final String... specs) {
        final Map<String, Set<String>> result = new HashMap<String, Set<String>>();
        for (final String spec : specs) {
            final int index = spec.indexOf('=');
            final String table = spec.substring(0, index);
            final String[] fields = spec.substring(index + 1).split(",");
            result.put(table, new LinkedHashSet<String>(Arrays.asList(fields)));
        }
        return result;
    }

    private static void pass() {
        testCount++;
    }

    private static void assertTrue(final String message, final boolean condition) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static void assertEquals(final String message, final Object expected, final Object actual) {
        if (expected == null ? actual != null : !expected.equals(actual)) {
            throw new AssertionError(message + " : attendu <" + expected + ">, obtenu <" + actual + ">");
        }
    }
}
