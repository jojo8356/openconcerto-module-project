package org.openconcerto.modules.project;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Tests des regles de <b>libelles de colonnes</b>.
 *
 * <p>
 * Chaque test correspond a une situation reelle : une utilisatrice ne veut plus
 * voir {@code ID_CLIENT} mais {@code CLIENT} ; une administratrice veut un
 * libelle different pour {@code ID_AFFAIRE} selon la table ; un libelle vide ne
 * doit pas pouvoir etre enregistre ; le role le plus haut doit etre celui qui a
 * le plus de droits ; etc.
 */
public final class ColumnLabelRulesTest {

    private static int testCount;
    private static final List<String> failures = new ArrayList<String>();

    public static void main(final String[] args) {
        // 1. Libelle propose automatiquement (le cas Gisèle).
        testIdPrefixIsRemoved();
        testUnderscoresBecomeSpaces();
        testNonIdColumnsAreKept();
        testBareIdIsKept();
        testLowercaseIsNormalized();

        // 2. Resolution d'un libelle.
        testExplicitRuleWins();
        testWildcardAppliesEverywhere();
        testExactRuleWinsOverWildcard();
        testAutoModeStripsPrefix();
        testMappingModeDoesNotStrip();
        testOffModeChangesNothing();
        testUnknownTableUsesUniqueRule();
        testUnknownTableIgnoresAmbiguousRule();
        testNullHeaderStaysNull();
        testResolutionIsIdempotent();
        testResolveAllKeepsOrderAndSize();
        testChangesAnything();

        // 3. Validation.
        testValidLabels();
        testInvalidLabels();
        testCleanLabel();
        testInvalidNames();
        testValidateReportsProblems();
        testValidateAcceptsCorrectRules();

        // 4. Fusion jar / base.
        testDatabaseOverridesJar();
        testJarFillsMissingRules();
        testMergeNeverNull();

        // 5. Qui peut parametrer.
        testSuperUserWins();
        testAdminWinsWithoutSuperUser();
        testMostRightsWinsWithoutAdminOrSuperUser();
        testSeveralTopUsers();
        testDeniedForOrdinaryUser();
        testDescribeAccessExplains();
        testUndeterminedAccessIsRetried();

        // 5. Edition en direct dans l'ecran (colonne « Libellé affiché »).
        testDisplayLabelShowsWhatUsersSee();
        testDisplayLabelFollowsMode();
        testEditDoesNotCreateUselessRule();
        testEditClearsRuleWhenEmptied();
        testEditReplacesLabel();
        testDisplayedLabelIsBlack();
        testCustomizedLabelIsBold();

        // 5 ter. Tables de sauvegarde et message de fin d'enregistrement.
        testBackupTablesAreDetected();
        testBusinessTablesAreNotBackups();
        testSaveReportExplainsWhatWasSaved();
        testWildcardRuleAppliesEverywhere();
        testFilterChoicesMatchColumns();

        // 6. SQL.
        testCreateStatementsAreIdempotentAndSchemaQualified();
        testSaveIsOneTransaction();
        testSaveSkipsInvalidRules();
        testQuoteStringEscapes();
        testRoleRightsQuerySelectsExpectedColumns();
        testSqlFileMatchesJava();
        testPropertiesExport();

        System.out.println("ColumnLabelRulesTest : " + testCount + " tests OK");
        if (!failures.isEmpty()) {
            for (final String failure : failures) {
                System.err.println(failure);
            }
            throw new AssertionError(failures.size() + " test(s) en echec");
        }
    }

    // ------------------------------------------------------------------
    // 1. Libelle propose
    // ------------------------------------------------------------------

    private static void testIdPrefixIsRemoved() {
        assertEquals("ID_CLIENT devient CLIENT", "CLIENT", ColumnLabelRules.suggestLabel("ID_CLIENT"));
        assertEquals("ID_AFFAIRE devient AFFAIRE", "AFFAIRE", ColumnLabelRules.suggestLabel("ID_AFFAIRE"));
        pass();
    }

    private static void testUnderscoresBecomeSpaces() {
        assertEquals("ID_FACTURE_FOURNISSEUR devient FACTURE FOURNISSEUR", "FACTURE FOURNISSEUR", ColumnLabelRules.suggestLabel("ID_FACTURE_FOURNISSEUR"));
        pass();
    }

    private static void testNonIdColumnsAreKept() {
        assertEquals("TOTAL_HT inchange", "TOTAL_HT", ColumnLabelRules.suggestLabel("TOTAL_HT"));
        assertEquals("DATE inchangee", "DATE", ColumnLabelRules.suggestLabel("DATE"));
        pass();
    }

    private static void testBareIdIsKept() {
        assertEquals("ID seul n'est pas un prefixe", "ID", ColumnLabelRules.suggestLabel("ID"));
        pass();
    }

    private static void testLowercaseIsNormalized() {
        assertEquals("minuscules acceptees", "CLIENT", ColumnLabelRules.suggestLabel("id_client"));
        pass();
    }

    // ------------------------------------------------------------------
    // 2. Resolution
    // ------------------------------------------------------------------

    private static Map<String, String> rules(final String... entries) {
        final Map<String, String> map = new LinkedHashMap<String, String>();
        for (final String entry : entries) {
            final int index = entry.indexOf('=');
            map.put(entry.substring(0, index), entry.substring(index + 1));
        }
        return map;
    }

    private static void testExplicitRuleWins() {
        final Map<String, String> labels = rules("COMMANDE.ID_AFFAIRE=Affaire de la commande");
        assertEquals("regle explicite", "Affaire de la commande", ColumnLabelRules.resolve("ID_AFFAIRE", "COMMANDE", labels, ColumnLabelRules.MODE_AUTO));
        pass();
    }

    private static void testWildcardAppliesEverywhere() {
        final Map<String, String> labels = rules("*.ID_CLIENT=Client");
        assertEquals("regle generique sur COMMANDE", "Client", ColumnLabelRules.resolve("ID_CLIENT", "COMMANDE", labels, ColumnLabelRules.MODE_AUTO));
        assertEquals("regle generique sans table connue", "Client", ColumnLabelRules.resolve("ID_CLIENT", null, labels, ColumnLabelRules.MODE_AUTO));
        pass();
    }

    private static void testExactRuleWinsOverWildcard() {
        final Map<String, String> labels = rules("*.ID_AFFAIRE=Affaire", "FACTURE_FOURNISSEUR.ID_AFFAIRE=Affaire (facture)");
        assertEquals("la regle de table gagne", "Affaire (facture)", ColumnLabelRules.resolve("ID_AFFAIRE", "FACTURE_FOURNISSEUR", labels, ColumnLabelRules.MODE_AUTO));
        assertEquals("l'autre table garde la generique", "Affaire", ColumnLabelRules.resolve("ID_AFFAIRE", "COMMANDE", labels, ColumnLabelRules.MODE_AUTO));
        pass();
    }

    private static void testAutoModeStripsPrefix() {
        assertEquals("mode AUTO sans regle", "CLIENT", ColumnLabelRules.resolve("ID_CLIENT", "COMMANDE", rules(), ColumnLabelRules.MODE_AUTO));
        pass();
    }

    private static void testMappingModeDoesNotStrip() {
        assertEquals("mode MAPPING sans regle : inchange", "ID_CLIENT", ColumnLabelRules.resolve("ID_CLIENT", "COMMANDE", rules(), ColumnLabelRules.MODE_MAPPING));
        pass();
    }

    private static void testOffModeChangesNothing() {
        final Map<String, String> labels = rules("*.ID_CLIENT=Client");
        assertEquals("mode OFF ignore meme les regles", "ID_CLIENT", ColumnLabelRules.resolve("ID_CLIENT", "COMMANDE", labels, ColumnLabelRules.MODE_OFF));
        pass();
    }

    private static void testUnknownTableUsesUniqueRule() {
        final Map<String, String> labels = rules("AFFAIRE.ID_FACTURE_FOURNISSEUR=Facture");
        assertEquals("une seule regle pour cette colonne : utilisable", "Facture", ColumnLabelRules.resolve("ID_FACTURE_FOURNISSEUR", null, labels, ColumnLabelRules.MODE_MAPPING));
        pass();
    }

    private static void testUnknownTableIgnoresAmbiguousRule() {
        final Map<String, String> labels = rules("COMMANDE.ID_FOURNISSEUR=Fournisseur", "FACTURE_FOURNISSEUR.ID_FOURNISSEUR=Fournisseur facture");
        assertEquals("deux libelles differents : on ne devine pas", "ID_FOURNISSEUR", ColumnLabelRules.resolve("ID_FOURNISSEUR", null, labels, ColumnLabelRules.MODE_MAPPING));
        pass();
    }

    private static void testNullHeaderStaysNull() {
        assertTrue("en-tete null", ColumnLabelRules.resolve(null, "COMMANDE", rules(), ColumnLabelRules.MODE_AUTO) == null);
        pass();
    }

    private static void testResolutionIsIdempotent() {
        final Map<String, String> labels = rules("*.ID_CLIENT=Client");
        final String once = ColumnLabelRules.resolve("ID_CLIENT", "COMMANDE", labels, ColumnLabelRules.MODE_AUTO);
        final String twice = ColumnLabelRules.resolve(once, "COMMANDE", labels, ColumnLabelRules.MODE_AUTO);
        assertEquals("appliquer deux fois ne change rien", once, twice);
        pass();
    }

    private static void testResolveAllKeepsOrderAndSize() {
        final List<String> headers = Arrays.asList("NUMERO", "ID_CLIENT", "DATE");
        final List<String> resolved = ColumnLabelRules.resolveAll(headers, "COMMANDE", rules(), ColumnLabelRules.MODE_AUTO);
        assertEquals("meme taille", headers.size(), resolved.size());
        assertEquals("CLIENT en deuxieme position", "CLIENT", resolved.get(1));
        assertEquals("NUMERO inchange", "NUMERO", resolved.get(0));
        pass();
    }

    private static void testChangesAnything() {
        assertTrue("ID_CLIENT change", ColumnLabelRules.changesAnything(Arrays.asList("ID_CLIENT"), "X", rules(), ColumnLabelRules.MODE_AUTO));
        assertTrue("mode OFF ne change rien", !ColumnLabelRules.changesAnything(Arrays.asList("ID_CLIENT"), "X", rules(), ColumnLabelRules.MODE_OFF));
        pass();
    }

    // ------------------------------------------------------------------
    // 3. Validation
    // ------------------------------------------------------------------

    private static void testValidLabels() {
        assertTrue("libelle simple", ColumnLabelRules.isValidLabel("Client"));
        assertTrue("libelle accentue", ColumnLabelRules.isValidLabel("N° de devis"));
        assertTrue("libelle avec espaces", ColumnLabelRules.isValidLabel("  Facture fournisseur  "));
        pass();
    }

    private static void testInvalidLabels() {
        assertTrue("null refuse", !ColumnLabelRules.isValidLabel(null));
        assertTrue("vide refuse", !ColumnLabelRules.isValidLabel("   "));
        assertTrue("tabulation refusee", !ColumnLabelRules.isValidLabel("Cli\tent"));
        assertTrue("saut de ligne refuse", !ColumnLabelRules.isValidLabel("Cli\nent"));
        final StringBuilder tooLong = new StringBuilder();
        for (int i = 0; i < ColumnLabelRules.MAX_LABEL_LENGTH + 1; i++) {
            tooLong.append('x');
        }
        assertTrue("trop long refuse", !ColumnLabelRules.isValidLabel(tooLong.toString()));
        pass();
    }

    private static void testCleanLabel() {
        assertEquals("espaces nettoyes", "Facture fournisseur", ColumnLabelRules.cleanLabel("  Facture   fournisseur "));
        assertEquals("null devient vide", "", ColumnLabelRules.cleanLabel(null));
        pass();
    }

    private static void testInvalidNames() {
        assertTrue("nom vide", !ColumnLabelRules.isValidName(""));
        assertTrue("nom avec point", !ColumnLabelRules.isValidName("TABLE.COLONNE"));
        assertTrue("nom correct", ColumnLabelRules.isValidName("ID_CLIENT"));
        pass();
    }

    private static void testValidateReportsProblems() {
        final Map<String, String> labels = rules("SANS_POINT=Libelle", "*.ID_CLIENT=", "T.C.=Trop court");
        final List<String> problems = ColumnLabelRules.validate(labels);
        assertTrue("trois problemes detectes (obtenu : " + problems + ")", problems.size() >= 3);
        pass();
    }

    private static void testValidateAcceptsCorrectRules() {
        final Map<String, String> labels = rules("*.ID_CLIENT=Client", "COMMANDE.ID_AFFAIRE=Affaire");
        assertEquals("aucun probleme", Collections.emptyList(), ColumnLabelRules.validate(labels));
        pass();
    }

    // ------------------------------------------------------------------
    // 4. Fusion jar / base
    // ------------------------------------------------------------------

    private static void testDatabaseOverridesJar() {
        final Map<String, String> fromJar = rules("*.ID_CLIENT=Client (jar)");
        final Map<String, String> fromDb = rules("*.ID_CLIENT=Client (base)");
        assertEquals("la base gagne", "Client (base)", ColumnLabelRules.merge(fromJar, fromDb).get("*.ID_CLIENT"));
        pass();
    }

    private static void testJarFillsMissingRules() {
        final Map<String, String> merged = ColumnLabelRules.merge(rules("*.ID_CLIENT=Client"), rules("*.ID_AFFAIRE=Affaire"));
        assertEquals("le jar complete", 2, merged.size());
        pass();
    }

    private static void testMergeNeverNull() {
        assertEquals("aucune source : map vide", 0, ColumnLabelRules.merge(null, null).size());
        pass();
    }

    // ------------------------------------------------------------------
    // 5. Qui peut parametrer
    // ------------------------------------------------------------------

    private static ColumnLabelRules.UserRightsInfo user(final int id, final String name, final int rights, final boolean admin, final boolean superUser) {
        return new ColumnLabelRules.UserRightsInfo(id, name, rights, admin, superUser);
    }

    private static void testSuperUserWins() {
        final List<ColumnLabelRules.UserRightsInfo> users = Arrays.asList(user(1, "Gisele", 5, false, true), user(2, "Nadia", 2, true, false), user(4, "Sophie", 4, false, false));
        assertEquals("un seul role de tete", 1, ColumnLabelRules.topUsers(users).size());
        assertEquals("c'est la superutilisatrice", 1, ColumnLabelRules.topUsers(users).get(0).getUserId());
        assertTrue("elle peut parametrer", ColumnLabelRules.canEdit(1, users));
        pass();
    }

    private static void testAdminWinsWithoutSuperUser() {
        final List<ColumnLabelRules.UserRightsInfo> users = Arrays.asList(user(2, "Nadia", 2, true, false), user(4, "Sophie", 4, false, false));
        assertTrue("l'administratrice passe avant les droits", ColumnLabelRules.canEdit(2, users));
        assertTrue("la personne avec plus de droits mais sans admin ne passe pas", !ColumnLabelRules.canEdit(4, users));
        pass();
    }

    private static void testMostRightsWinsWithoutAdminOrSuperUser() {
        final List<ColumnLabelRules.UserRightsInfo> users = Arrays.asList(user(4, "Sophie", 4, false, false), user(5, "Marc", 1, false, false));
        assertTrue("la personne avec le plus de droits decide", ColumnLabelRules.canEdit(4, users));
        assertTrue("les autres non", !ColumnLabelRules.canEdit(5, users));
        pass();
    }

    private static void testSeveralTopUsers() {
        final List<ColumnLabelRules.UserRightsInfo> users = Arrays.asList(user(4, "Sophie", 4, false, false), user(7, "Lea", 4, false, false), user(5, "Marc", 1, false, false));
        assertEquals("les deux ex aequo", 2, ColumnLabelRules.topUsers(users).size());
        assertTrue("Sophie", ColumnLabelRules.canEdit(4, users));
        assertTrue("Lea", ColumnLabelRules.canEdit(7, users));
        assertTrue("Marc non", !ColumnLabelRules.canEdit(5, users));
        pass();
    }

    private static void testDeniedForOrdinaryUser() {
        assertTrue("liste vide : personne", !ColumnLabelRules.canEdit(3, new ArrayList<ColumnLabelRules.UserRightsInfo>()));
        assertTrue("liste nulle : personne", !ColumnLabelRules.canEdit(3, null));
        pass();
    }

    private static void testDescribeAccessExplains() {
        final List<ColumnLabelRules.UserRightsInfo> users = Arrays.asList(user(2, "Nadia", 2, true, false), user(5, "Marc", 1, false, false));
        final String granted = ColumnLabelRules.describeAccess(2, users);
        assertTrue("acces accorde explique (" + granted + ")", granted.startsWith("acces accorde"));
        final String denied = ColumnLabelRules.describeAccess(5, users);
        assertTrue("refus explique (" + denied + ")", denied.startsWith("acces refuse") && denied.contains("Nadia"));
        pass();
    }

    /**
     * Un utilisateur inconnu (menu construit avant l'ouverture de la session)
     * ne doit pas etre traite comme un refus : sinon le menu disparait pour tout
     * le monde, y compris pour l'administrateur. Un refus explicite, lui, doit
     * bien masquer le menu.
     */
    private static void testUndeterminedAccessIsRetried() {
        assertTrue("utilisateur inconnu : indetermine",
                ColumnLabelRules.accessIsUndetermined("utilisateur de la session inconnu : parametrage reserve aux administrateurs"));
        assertTrue("aucun utilisateur lisible : indetermine",
                ColumnLabelRules.accessIsUndetermined("aucun utilisateur lisible dans la base : parametrage reserve aux administrateurs"));
        assertTrue("raison vide : indetermine", ColumnLabelRules.accessIsUndetermined(null));
        assertTrue("refus explicite : decision definitive",
                !ColumnLabelRules.accessIsUndetermined("acces refuse : le role le plus haut est Gisèle (superutilisateur, 5 droits)"));
        assertTrue("acces accorde : decision definitive", !ColumnLabelRules.accessIsUndetermined("acces accorde : Gisèle (superutilisateur, 5 droits)"));
        assertTrue("pas de table de droits : decision definitive",
                !ColumnLabelRules.accessIsUndetermined("aucune table de droits dans la base : parametrage ouvert"));
        pass();
    }

    // ------------------------------------------------------------------
    // 5 bis. Edition en direct (« Libellé affiché »)
    // ------------------------------------------------------------------

    /**
     * L'ecran doit montrer ce que voient les utilisateurs, pas une case vide :
     * sans regle, la case affiche le libelle automatique.
     */
    private static void testDisplayLabelShowsWhatUsersSee() {
        assertEquals("sans regle, on voit le libelle automatique", "FOURNISSEUR",
                ColumnLabelRules.displayLabel("COMMANDE", "ID_FOURNISSEUR", "", ColumnLabelRules.MODE_AUTO));
        assertEquals("sans regle et sans mode auto, le nom technique", "ID_FOURNISSEUR",
                ColumnLabelRules.displayLabel("COMMANDE", "ID_FOURNISSEUR", null, ColumnLabelRules.MODE_MAPPING));
        assertEquals("avec regle, on voit la regle", "Fournisseur",
                ColumnLabelRules.displayLabel("COMMANDE", "ID_FOURNISSEUR", "Fournisseur", ColumnLabelRules.MODE_MAPPING));
        assertEquals("mode OFF : nom technique meme avec une regle", "ID_FOURNISSEUR",
                ColumnLabelRules.displayLabel("COMMANDE", "ID_FOURNISSEUR", "Fournisseur", ColumnLabelRules.MODE_OFF));
        pass();
    }

    private static void testDisplayLabelFollowsMode() {
        final String auto = ColumnLabelRules.displayLabel("AFFAIRE", "ID_CLIENT", "", ColumnLabelRules.MODE_AUTO);
        final String mapping = ColumnLabelRules.displayLabel("AFFAIRE", "ID_CLIENT", "", ColumnLabelRules.MODE_MAPPING);
        assertEquals("AUTO supprime le prefixe", "CLIENT", auto);
        assertEquals("MAPPING ne touche pas au libelle", "ID_CLIENT", mapping);
        pass();
    }

    /** Cliquer puis Entree ne doit pas creer une regle identique a l'automatique. */
    private static void testEditDoesNotCreateUselessRule() {
        assertEquals("texte inchange : aucune regle creee", "",
                ColumnLabelRules.applyEdit("COMMANDE", "ID_FOURNISSEUR", "", ColumnLabelRules.MODE_AUTO, "FOURNISSEUR"));
        assertEquals("regle existante inchangee : regle conservee", "Fournisseur",
                ColumnLabelRules.applyEdit("COMMANDE", "ID_FOURNISSEUR", "Fournisseur", ColumnLabelRules.MODE_AUTO, "Fournisseur"));
        pass();
    }

    private static void testEditClearsRuleWhenEmptied() {
        assertEquals("case videe : retour a l'automatique", "",
                ColumnLabelRules.applyEdit("COMMANDE", "ID_FOURNISSEUR", "Fournisseur", ColumnLabelRules.MODE_AUTO, "   "));
        assertEquals("case videe (null)", "",
                ColumnLabelRules.applyEdit("COMMANDE", "ID_FOURNISSEUR", "Fournisseur", ColumnLabelRules.MODE_AUTO, null));
        pass();
    }

    private static void testEditReplacesLabel() {
        assertEquals("nouveau libelle saisi", "Notre fournisseur",
                ColumnLabelRules.applyEdit("COMMANDE", "ID_FOURNISSEUR", "", ColumnLabelRules.MODE_AUTO, "  Notre   fournisseur "));
        assertEquals("saisir le nom technique force l'affichage brut", "ID_FOURNISSEUR",
                ColumnLabelRules.applyEdit("COMMANDE", "ID_FOURNISSEUR", "", ColumnLabelRules.MODE_AUTO, "ID_FOURNISSEUR"));
        pass();
    }

    /** Le libelle affiche doit etre noir : le gris etait trop pale a l'ecran. */
    private static void testDisplayedLabelIsBlack() {
        assertEquals("libelle en noir", java.awt.Color.BLACK, ColumnLabelStyle.color());
        assertTrue("ce n'est pas un gris", ColumnLabelStyle.color().getRed() < 32 && ColumnLabelStyle.color().getGreen() < 32 && ColumnLabelStyle.color().getBlue() < 32);
        assertTrue("aide de l'ecran a jour", ColumnLabelStyle.describe().contains("gras"));
        pass();
    }

    private static void testCustomizedLabelIsBold() {
        final java.awt.Font base = new java.awt.Font("Dialog", java.awt.Font.PLAIN, 12);
        assertEquals("personnalise : gras", java.awt.Font.BOLD, ColumnLabelStyle.font(base, true).getStyle());
        assertEquals("automatique : normal", java.awt.Font.PLAIN, ColumnLabelStyle.font(base, false).getStyle());
        assertEquals("police inconnue : null", null, ColumnLabelStyle.font(null, true));
        pass();
    }

    /**
     * Cas reel : une regle saisie sur {@code sauvegarde_FACTURE_FOURNISSEUR_avant…}
     * est bien enregistree mais n'a aucun effet visible, car cette table
     * n'apparait dans aucune liste.
     */
    private static void testBackupTablesAreDetected() {
        assertTrue("prefixe sauvegarde_", ColumnLabelRules.looksLikeBackupTable("sauvegarde_FACTURE_FOURNISSEUR_avant_2024"));
        assertTrue("suffixe _old", ColumnLabelRules.looksLikeBackupTable("FACTURE_FOURNISSEUR_OLD"));
        assertTrue("suffixe _avant", ColumnLabelRules.looksLikeBackupTable("COMMANDE_AVANT"));
        assertTrue("prefixe zz_", ColumnLabelRules.looksLikeBackupTable("zz_essai"));
        assertTrue("fragment _copie_", ColumnLabelRules.looksLikeBackupTable("COMMANDE_copie_1"));
        assertTrue("null : pas une sauvegarde", !ColumnLabelRules.looksLikeBackupTable(null));

        final List<String> tables = Arrays.asList("COMMANDE", "sauvegarde_FACTURE_FOURNISSEUR_avant_2024",
                "FACTURE_FOURNISSEUR", "sauvegarde_FACTURE_FOURNISSEUR_avant_2024");
        final List<String> backups = ColumnLabelRules.backupTables(tables);
        assertEquals("une seule table de sauvegarde, sans doublon", 1, backups.size());
        assertEquals("c'est la table sauvegardee", "sauvegarde_FACTURE_FOURNISSEUR_avant_2024", backups.get(0));
        pass();
    }

    /** Garde-fou : ne pas confondre une table metier avec une sauvegarde. */
    private static void testBusinessTablesAreNotBackups() {
        for (final String table : Arrays.asList("FACTURE_FOURNISSEUR", "COMMANDE", "ATTESTATION", "SAISIE_ACHAT", "AFFAIRE", "TEST", "CONTACT_FOURNISSEUR")) {
            assertTrue("table metier non signalee : " + table, !ColumnLabelRules.looksLikeBackupTable(table));
        }
        pass();
    }

    private static void testSaveReportExplainsWhatWasSaved() {
        final String plain = ColumnLabelRules.saveReport(1, 0, ColumnLabelRules.MODE_AUTO, new ArrayList<String>());
        assertTrue("regle bien enregistree (" + plain + ")", plain.contains("1 règle en base"));
        assertTrue("mode rappele", plain.contains("AUTO"));
        assertTrue("rafraichissement explique", plain.contains("Listes déjà ouvertes") && plain.contains("0 colonne"));
        assertTrue("prochain demarrage rappele", plain.contains("prochain démarrage"));
        assertTrue("aucun avertissement sans table de sauvegarde", !plain.contains("sauvegarde :"));

        final String warn = ColumnLabelRules.saveReport(1, 0, ColumnLabelRules.MODE_AUTO, Arrays.asList("sauvegarde_FACTURE_FOURNISSEUR_avant_2024"));
        assertTrue("avertissement de table de sauvegarde (" + warn + ")", warn.contains("table de sauvegarde"));
        assertTrue("nom de la table cite", warn.contains("sauvegarde_FACTURE_FOURNISSEUR_avant_2024"));
        assertTrue("conseil du caractere etoile", warn.contains("toutes les tables (*)"));

        final String plurals = ColumnLabelRules.saveReport(3, 5, ColumnLabelRules.MODE_MAPPING, new ArrayList<String>());
        assertTrue("pluriel des regles", plurals.contains("3 règles"));
        assertTrue("colonnes rafraichies", plurals.contains("5 colonne(s)"));
        pass();
    }

    /**
     * Cas reel : apres « Appliquer a toutes les tables (*) », les lignes du
     * tableau continuaient d'afficher le libelle automatique, ce qui donnait
     * l'impression que le bouton n'avait rien fait. La regle generale doit etre
     * prise en compte pour l'affichage.
     */
    private static void testWildcardRuleAppliesEverywhere() {
        assertEquals("regle generale appliquee", "FOURNISSEUR UNIQUE",
                ColumnLabelRules.resolvedLabel("ID_FOURNISSEUR", "", "FOURNISSEUR UNIQUE", ColumnLabelRules.MODE_AUTO));
        assertEquals("la regle de la table gagne", "Notre fournisseur",
                ColumnLabelRules.resolvedLabel("ID_FOURNISSEUR", "Notre fournisseur", "FOURNISSEUR UNIQUE", ColumnLabelRules.MODE_AUTO));
        assertEquals("sans regle : automatique", "FOURNISSEUR",
                ColumnLabelRules.resolvedLabel("ID_FOURNISSEUR", "", null, ColumnLabelRules.MODE_AUTO));
        assertEquals("mode MAPPING sans regle : nom technique", "ID_FOURNISSEUR",
                ColumnLabelRules.resolvedLabel("ID_FOURNISSEUR", "", "", ColumnLabelRules.MODE_MAPPING));
        assertEquals("regle generale en MAPPING", "FOURNISSEUR UNIQUE",
                ColumnLabelRules.resolvedLabel("ID_FOURNISSEUR", "", "FOURNISSEUR UNIQUE", ColumnLabelRules.MODE_MAPPING));
        assertEquals("mode OFF ignore tout", "ID_FOURNISSEUR",
                ColumnLabelRules.resolvedLabel("ID_FOURNISSEUR", "Notre fournisseur", "FOURNISSEUR UNIQUE", ColumnLabelRules.MODE_OFF));
        pass();
    }

    /** Le selecteur de filtre doit viser la bonne colonne du tableau. */
    private static void testFilterChoicesMatchColumns() {
        assertEquals("cinq choix", 5, ColumnLabelRules.FILTER_CHOICES.size());
        assertEquals("premier choix : toutes", "Toutes les colonnes", ColumnLabelRules.FILTER_CHOICES.get(0));
        assertEquals("toutes les colonnes = -1", -1, ColumnLabelRules.filterColumnIndex(0));
        assertEquals("Table = colonne 0", 0, ColumnLabelRules.filterColumnIndex(1));
        assertEquals("Colonne = colonne 1", 1, ColumnLabelRules.filterColumnIndex(2));
        assertEquals("Automatique = colonne 2", 2, ColumnLabelRules.filterColumnIndex(3));
        assertEquals("Libellé affiché = colonne 3", 3, ColumnLabelRules.filterColumnIndex(4));
        assertEquals("choix hors liste : toutes", -1, ColumnLabelRules.filterColumnIndex(9));
        pass();
    }

    // ------------------------------------------------------------------
    // 6. SQL
    // ------------------------------------------------------------------

    private static void testCreateStatementsAreIdempotentAndSchemaQualified() {
        final List<String> statements = ColumnLabelRules.createTableStatements("OpenConcerto42");
        assertEquals("trois instructions (2 tables + 1 index)", 3, statements.size());
        for (final String statement : statements) {
            assertTrue("idempotent : " + statement, statement.contains("if not exists"));
            assertTrue("qualifie par le schema : " + statement, statement.contains("\"OpenConcerto42\""));
        }
        assertTrue("table des libelles", statements.get(1).contains("PROJECT_COLUMN_LABEL"));
        assertTrue("index unique", statements.get(2).contains("PROJECT_COLUMN_LABEL_UNQ") && statements.get(2).contains("unique"));
        pass();
    }

    private static void testSaveIsOneTransaction() {
        final Map<String, String> labels = rules("*.ID_CLIENT=Client");
        final String sql = ColumnLabelRules.saveStatements("OpenConcerto42", labels, ColumnLabelRules.MODE_AUTO, 7);
        assertTrue("commence par begin", sql.startsWith("begin;"));
        assertTrue("finit par commit", sql.endsWith("commit;"));
        assertEquals("un seul begin", 1, count(sql, "begin;"));
        assertEquals("un seul commit", 1, count(sql, "commit;"));
        assertTrue("remplace les libelles", sql.contains("delete from \"OpenConcerto42\".\"PROJECT_COLUMN_LABEL\""));
        assertTrue("enregistre le mode", sql.contains("column.label.mode"));
        assertTrue("trace l'utilisateur", sql.contains(", now(), 7);"));
        assertTrue("libelle insere tel que saisi", sql.contains("'Client'"));
        pass();
    }

    private static void testSaveSkipsInvalidRules() {
        final Map<String, String> labels = rules("SANS_POINT=Libelle", "*.ID_CLIENT=", "COMMANDE.ID_AFFAIRE=Affaire");
        final String sql = ColumnLabelRules.saveStatements("S", labels, ColumnLabelRules.MODE_AUTO, 1);
        assertEquals("une seule regle valide enregistree", 1, count(sql, "insert into \"S\".\"PROJECT_COLUMN_LABEL\""));
        assertTrue("la regle valide est celle attendue", sql.contains("'COMMANDE'") && sql.contains("'ID_AFFAIRE'"));
        pass();
    }

    private static void testQuoteStringEscapes() {
        assertEquals("apostrophe doublee", "'l''affaire'", ColumnLabelRules.quoteString("l'affaire"));
        assertEquals("null", "null", ColumnLabelRules.quoteString(null));
        assertEquals("identifiant echappe", "\"A\"\"B\"", ColumnLabelRules.quoteIdentifier("A\"B"));
        pass();
    }

    private static void testRoleRightsQuerySelectsExpectedColumns() {
        final String query = ColumnLabelRules.roleRightsQuery("OpenConcerto42");
        assertTrue("identifiant utilisateur", query.contains("as \"ID_USER\""));
        assertTrue("nom", query.contains("as \"NOM\""));
        assertTrue("drapeau superutilisateur", query.contains("as \"SUPERUSER\""));
        assertTrue("drapeau administrateur", query.contains("as \"ADMIN\""));
        assertTrue("nombre de droits", query.contains("as \"DROITS\""));
        assertTrue("compte les droits accordes", query.contains("from \"OpenConcerto42\".\"USER_RIGHT\" r"));
        assertTrue("ignore les comptes desactives", query.contains("u.\"IS_ACTIVE\" is null or u.\"IS_ACTIVE\""));
        assertTrue("superutilisateurs en tete", query.contains("order by 3 desc"));
        pass();
    }

    /**
     * La requete du module doit etre identique a celle du fichier SQL de
     * reference (lui-meme execute par {@code tests/sql/e2e-colonnes.sh}).
     * C'est ce qui empeche la derive entre le Java et le SQL.
     */
    private static void testSqlFileMatchesJava() {
        final File file = new File("tests/sql/migration-colonnes.sql");
        if (!file.exists()) {
            assertTrue("fichier de migration introuvable (lancer depuis la racine du depot)", false);
        }
        final String expected = normalize(ColumnLabelRules.roleRightsQuery("__SCHEMA__"));
        final String fromFile = extractQuery(file, "roleRights");
        assertEquals("la requete SQL du fichier est celle du Java", expected, fromFile);
        pass();
    }

    private static void testPropertiesExport() {
        final String exported = ColumnLabelRules.toProperties(rules("*.ID_CLIENT=Client"), ColumnLabelRules.MODE_AUTO);
        assertTrue("le mode est ecrit", exported.contains("mode=AUTO"));
        assertTrue("la regle est ecrite", exported.contains("*.ID_CLIENT=Client"));
        assertTrue("un commentaire explique la priorite de la base", exported.contains("PROJECT_COLUMN_LABEL"));
        pass();
    }

    // ------------------------------------------------------------------
    // Outils
    // ------------------------------------------------------------------

    private static int count(final String text, final String pattern) {
        int count = 0;
        int index = text.indexOf(pattern);
        while (index >= 0) {
            count++;
            index = text.indexOf(pattern, index + pattern.length());
        }
        return count;
    }

    private static String normalize(final String sql) {
        return sql.replaceAll("\\s+", " ").trim().toLowerCase();
    }

    private static String extractQuery(final File file, final String name) {
        try {
            final BufferedReader reader = new BufferedReader(new InputStreamReader(new FileInputStream(file), "UTF-8"));
            try {
                final StringBuilder query = new StringBuilder();
                boolean inside = false;
                String line;
                while ((line = reader.readLine()) != null) {
                    if (line.trim().equals("-- query: " + name)) {
                        inside = true;
                        continue;
                    }
                    if (inside && line.trim().equals("-- query: end")) {
                        break;
                    }
                    if (inside) {
                        query.append(line).append('\n');
                    }
                }
                return normalize(query.toString());
            } finally {
                reader.close();
            }
        } catch (Exception e) {
            throw new AssertionError("lecture de " + file + " impossible : " + e);
        }
    }

    private static void pass() {
        testCount++;
    }

    private static void assertTrue(final String message, final boolean condition) {
        if (!condition) {
            failures.add("ECHEC : " + message);
        }
    }

    private static void assertEquals(final String message, final Object expected, final Object actual) {
        if (expected == null ? actual != null : !expected.equals(actual)) {
            failures.add("ECHEC : " + message + " : attendu <" + expected + ">, obtenu <" + actual + ">");
        }
    }
}
