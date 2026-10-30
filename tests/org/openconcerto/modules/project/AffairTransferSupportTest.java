package org.openconcerto.modules.project;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Tests de {@link AffairTransferSupport} : la reprise de l'affaire dans les
 * transferts de documents.
 * <p>
 * Cas reel corrige : l'affaire est renseignee sur une commande fournisseur, on
 * la transfere en facture, et la facture n'a pas d'affaire. Mesure : dans
 * OpenConcerto 1.7.6, <b>aucun</b> injecteur du c&oelig;ur ne mentionne
 * {@code ID_AFFAIRE} (26 injecteurs, 0 occurrence) : le champ n'est donc jamais
 * copie.
 */
public final class AffairTransferSupportTest {

    private static int passed = 0;

    public static void main(final String[] args) {
        testPairsList();
        testRealPairIsDeclared();
        testIsTransferPair();
        testShouldMap();
        testShouldMapRequiresBothColumns();
        testShouldMapRequiresSchema();
        testInstallAddsMapping();
        testInstallIsIdempotent();
        testInstallWithoutInjector();
        testInstallWithoutColumn();
        testInstallFailureDoesNotStop();
        testEveryPairIsKnown();
        System.out.println("AffairTransferSupportTest : " + passed + " tests OK");
    }

    private static void assertEquals(final String label, final Object expected, final Object actual) {
        if (expected == null ? actual != null : !expected.equals(actual)) {
            throw new AssertionError(label + " : attendu <" + expected + ">, obtenu <" + actual + ">");
        }
        passed++;
    }

    private static AffairLinkSupport.Schema schema(final String... tables) {
        final Set<String> names = new HashSet<String>(Arrays.asList(tables));
        final Map<String, Set<String>> fields = new HashMap<String, Set<String>>();
        for (final String table : tables) {
            fields.put(table, new HashSet<String>(Arrays.asList(AffairLinkSupport.AFFAIR_FIELD, "ID", "SOURCE", "IDSOURCE")));
        }
        return AffairLinkSupport.schemaOf(names, fields);
    }

    /** Injecteur simule : registre de paires, avec ou sans affaire. */
    private static final class FakeAccess implements AffairTransferSupport.InjectorAccess {
        final Set<String> registered = new HashSet<String>();
        final Set<String> mapped = new HashSet<String>();
        final List<String> added = new ArrayList<String>();
        final Set<String> failing = new HashSet<String>();

        FakeAccess(final String... pairs) {
            this.registered.addAll(Arrays.asList(pairs));
        }

        @Override
        public boolean isRegistered(final String src, final String dest) {
            return this.registered.contains(src + "->" + dest);
        }

        @Override
        public boolean isMapped(final String src, final String dest) {
            return this.mapped.contains(src + "->" + dest);
        }

        @Override
        public boolean addMapping(final String src, final String dest) {
            if (this.failing.contains(src + "->" + dest)) {
                throw new IllegalStateException("boom");
            }
            this.mapped.add(src + "->" + dest);
            this.added.add(src + "->" + dest);
            return true;
        }
    }

    private static final String[] ALL_TABLES = new String[] { "COMMANDE", "SAISIE_ACHAT", "FACTURE_FOURNISSEUR", "BON_RECEPTION", "DEVIS", "AVOIR_FOURNISSEUR",
            "COMMANDE_CLIENT", "SAISIE_VENTE_FACTURE", "BON_DE_LIVRAISON", "AVOIR_CLIENT" };

    private static void testPairsList() {
        assertEquals("au moins 15 paires", Boolean.TRUE, Boolean.valueOf(AffairTransferSupport.TRANSFER_PAIRS.size() >= 15));
        for (final String[] pair : AffairTransferSupport.TRANSFER_PAIRS) {
            if (pair == null || pair.length != 2 || pair[0].equals(pair[1])) {
                throw new AssertionError("paire invalide : " + Arrays.toString(pair));
            }
            passed++;
        }
    }

    /** La paire du bouton « Transfert en facture » d'une commande fournisseur. */
    private static void testRealPairIsDeclared() {
        assertEquals("commande -> saisie achat", Boolean.TRUE, Boolean.valueOf(AffairTransferSupport.isTransferPair("COMMANDE", "SAISIE_ACHAT")));
        assertEquals("commande -> facture fournisseur", Boolean.TRUE, Boolean.valueOf(AffairTransferSupport.isTransferPair("COMMANDE", "FACTURE_FOURNISSEUR")));
        assertEquals("bon de reception -> facture fournisseur", Boolean.TRUE, Boolean.valueOf(AffairTransferSupport.isTransferPair("BON_RECEPTION", "FACTURE_FOURNISSEUR")));
        assertEquals("devis -> commande client", Boolean.TRUE, Boolean.valueOf(AffairTransferSupport.isTransferPair("DEVIS", "COMMANDE_CLIENT")));
        // les lignes ne sont pas des documents : le coeur recopie deja tous les
        // champs de meme nom pour ces paires
        assertEquals("ligne de commande -> ligne de saisie", Boolean.FALSE, Boolean.valueOf(AffairTransferSupport.isTransferPair("COMMANDE_ELEMENT", "SAISIE_ACHAT_ELEMENT")));
    }

    private static void testIsTransferPair() {
        assertEquals("casse", Boolean.TRUE, Boolean.valueOf(AffairTransferSupport.isTransferPair("commande", "saisie_achat")));
        assertEquals("espaces", Boolean.TRUE, Boolean.valueOf(AffairTransferSupport.isTransferPair(" COMMANDE ", "SAISIE_ACHAT ")));
        assertEquals("sens inverse non declare", Boolean.FALSE, Boolean.valueOf(AffairTransferSupport.isTransferPair("SAISIE_ACHAT", "COMMANDE")));
        assertEquals("paire inconnue", Boolean.FALSE, Boolean.valueOf(AffairTransferSupport.isTransferPair("ARTICLE", "COMMANDE")));
        assertEquals("source nulle", Boolean.FALSE, Boolean.valueOf(AffairTransferSupport.isTransferPair(null, "COMMANDE")));
        assertEquals("destination nulle", Boolean.FALSE, Boolean.valueOf(AffairTransferSupport.isTransferPair("COMMANDE", null)));
    }

    private static void testShouldMap() {
        assertEquals("paire complete", Boolean.TRUE, Boolean.valueOf(AffairTransferSupport.shouldMap("COMMANDE", "SAISIE_ACHAT", schema(ALL_TABLES))));
        assertEquals("schema nul", Boolean.FALSE, Boolean.valueOf(AffairTransferSupport.shouldMap("COMMANDE", "SAISIE_ACHAT", null)));
    }

    private static void testShouldMapRequiresBothColumns() {
        // la commande a l'affaire, la saisie d'achat non : rien a transporter
        assertEquals("destination sans colonne", Boolean.FALSE,
                Boolean.valueOf(AffairTransferSupport.shouldMap("COMMANDE", "SAISIE_ACHAT", schema("COMMANDE"))));
        // la source n'a pas l'affaire
        assertEquals("source sans colonne", Boolean.FALSE,
                Boolean.valueOf(AffairTransferSupport.shouldMap("COMMANDE", "SAISIE_ACHAT", schema("SAISIE_ACHAT"))));
        // table absente du schema
        assertEquals("table absente", Boolean.FALSE,
                Boolean.valueOf(AffairTransferSupport.shouldMap("COMMANDE", "SAISIE_ACHAT", schema("COMMANDE", "FACTURE_FOURNISSEUR"))));
    }

    private static void testShouldMapRequiresSchema() {
        final Set<String> tables = new HashSet<String>(Arrays.asList("COMMANDE", "SAISIE_ACHAT"));
        final Map<String, Set<String>> fields = new HashMap<String, Set<String>>();
        fields.put("COMMANDE", new HashSet<String>(Arrays.asList(AffairLinkSupport.AFFAIR_FIELD)));
        fields.put("SAISIE_ACHAT", new HashSet<String>(Arrays.asList("ID")));
        assertEquals("colonne absente cote destination", Boolean.FALSE,
                Boolean.valueOf(AffairTransferSupport.shouldMap("COMMANDE", "SAISIE_ACHAT", AffairLinkSupport.schemaOf(tables, fields))));
    }

    /** LE test du correctif : la paire de l'utilisateur recoit le mapping. */
    private static void testInstallAddsMapping() {
        final FakeAccess access = new FakeAccess("COMMANDE->SAISIE_ACHAT");
        final AffairTransferSupport.Report report = AffairTransferSupport.install(schema(ALL_TABLES), access);
        assertEquals("paire corrigee", Arrays.asList("COMMANDE -> SAISIE_ACHAT"), report.getAdded());
        assertEquals("mapping pose", Boolean.TRUE, Boolean.valueOf(access.isMapped("COMMANDE", "SAISIE_ACHAT")));
        assertEquals("compte rendu complet", Boolean.TRUE, Boolean.valueOf(report.isComplete()));
        assertEquals("resume mentionne la paire", Boolean.TRUE, Boolean.valueOf(report.getSummary().contains("COMMANDE -> SAISIE_ACHAT")));
    }

    private static void testInstallIsIdempotent() {
        final FakeAccess access = new FakeAccess("COMMANDE->SAISIE_ACHAT");
        access.mapped.add("COMMANDE->SAISIE_ACHAT");
        final AffairTransferSupport.Report report = AffairTransferSupport.install(schema(ALL_TABLES), access);
        assertEquals("deja en place", Arrays.asList("COMMANDE -> SAISIE_ACHAT"), report.getAlreadyMapped());
        assertEquals("aucun ajout", Integer.valueOf(0), Integer.valueOf(report.getAdded().size()));
        assertEquals("aucune ecriture", Integer.valueOf(0), Integer.valueOf(access.added.size()));
    }

    private static void testInstallWithoutInjector() {
        // le coeur n'enregistre pas d'injecteur : on ne cree rien a sa place
        final FakeAccess access = new FakeAccess();
        final AffairTransferSupport.Report report = AffairTransferSupport.install(schema(ALL_TABLES), access);
        assertEquals("aucun ajout", Integer.valueOf(0), Integer.valueOf(report.getAdded().size()));
        assertEquals("paires sans injecteur signalees", Boolean.TRUE, Boolean.valueOf(report.getNoInjector().contains("COMMANDE -> SAISIE_ACHAT")));
        assertEquals("aucune ecriture", Integer.valueOf(0), Integer.valueOf(access.added.size()));
        assertEquals("compte rendu complet", Boolean.TRUE, Boolean.valueOf(report.isComplete()));
    }

    private static void testInstallWithoutColumn() {
        final FakeAccess access = new FakeAccess("COMMANDE->SAISIE_ACHAT");
        final AffairTransferSupport.Report report = AffairTransferSupport.install(schema("COMMANDE"), access);
        assertEquals("aucun ajout", Integer.valueOf(0), Integer.valueOf(report.getAdded().size()));
        assertEquals("sans colonne", Boolean.TRUE, Boolean.valueOf(report.getNoColumn().contains("COMMANDE -> SAISIE_ACHAT")));
        assertEquals("aucune ecriture", Integer.valueOf(0), Integer.valueOf(access.added.size()));
    }

    private static void testInstallFailureDoesNotStop() {
        final FakeAccess access = new FakeAccess("COMMANDE->SAISIE_ACHAT", "COMMANDE->BON_RECEPTION");
        access.failing.add("COMMANDE->SAISIE_ACHAT");
        final AffairTransferSupport.Report report = AffairTransferSupport.install(schema(ALL_TABLES), access);
        assertEquals("un echec", Integer.valueOf(1), Integer.valueOf(report.getFailed().size()));
        assertEquals("le suivant est traite", Boolean.TRUE, Boolean.valueOf(report.getAdded().contains("COMMANDE -> BON_RECEPTION")));
        assertEquals("compte rendu incomplet", Boolean.FALSE, Boolean.valueOf(report.isComplete()));
        assertEquals("message d'echec", Boolean.TRUE, Boolean.valueOf(report.getFailed().get(0).contains("boom")));
    }

    /** Toutes les paires declarees doivent etre des documents du module. */
    private static void testEveryPairIsKnown() {
        final List<String> known = Arrays.asList(ALL_TABLES);
        for (final String[] pair : AffairTransferSupport.TRANSFER_PAIRS) {
            if (!known.contains(pair[0]) || !known.contains(pair[1])) {
                throw new AssertionError("paire hors module : " + pair[0] + " -> " + pair[1]);
            }
            passed++;
        }
        // aucune paire en double
        final Set<String> unique = new HashSet<String>();
        for (final String[] pair : AffairTransferSupport.TRANSFER_PAIRS) {
            if (!unique.add(pair[0] + "->" + pair[1])) {
                throw new AssertionError("paire en double : " + pair[0] + " -> " + pair[1]);
            }
            passed++;
        }
    }
}
