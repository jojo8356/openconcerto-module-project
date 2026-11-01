/*
 * Tests du compte rendu de la reprise, sans base et sans interface.
 *
 * Le defaut reproduit ici est celui constate dans l'interface : les comptages
 * echouaient, l'erreur etait avalee, et le menu annoncait « tous les documents
 * transferes ont deja leur affaire » alors que 37 documents attendaient leur
 * affaire. Un compte rendu ne doit jamais transformer une erreur en zero.
 */
package org.openconcerto.modules.project;

public final class AffairRepairReportTest {

    private static int passed = 0;

    public static void main(final String[] args) {
        testNothingToDo();
        testCountsAreSummed();
        testZeroCountsIgnored();
        testErrorIsNeverNothingToDo();
        testErrorKeepsCountsAndWarns();
        testSqlAndCauseAreReported();
        System.out.println("AffairRepairReportTest : " + passed + " controles, 0 echec");
    }

    /** Cas normal : rien a reprendre, et le message le dit. */
    private static void testNothingToDo() {
        final AffairRepairReport report = new AffairRepairReport();
        assertEquals("aucun total", 0L, Long.valueOf(report.getTotal()));
        assertEquals("aucune erreur", Boolean.FALSE, Boolean.valueOf(report.hasErrors()));
        assertEquals("rien a faire", Boolean.TRUE, Boolean.valueOf(report.isNothingToDo()));
        assertEquals("message", AffairRepairReport.NOTHING_TO_DO, report.message());
    }

    /** Les comptes s'additionnent, dans l'ordre, avec leur description. */
    private static void testCountsAreSummed() {
        final AffairRepairReport report = new AffairRepairReport();
        report.add("FACTURE_FOURNISSEUR <- COMMANDE (via TR_COMMANDE)", 17);
        report.add("COMMANDE_CLIENT <- DEVIS (via TR_DEVIS)", 8);
        report.add("BON_DE_LIVRAISON <- COMMANDE_CLIENT (via TR_COMMANDE_CLIENT)", 1);
        assertEquals("total", 26L, Long.valueOf(report.getTotal()));
        assertEquals("pas d'erreur", Boolean.FALSE, Boolean.valueOf(report.hasErrors()));
        assertEquals("pas rien a faire", Boolean.FALSE, Boolean.valueOf(report.isNothingToDo()));
        assertContains("total dans le message", report.message(), "26 document(s)");
        assertContains("detail 1", report.message(), "FACTURE_FOURNISSEUR <- COMMANDE (via TR_COMMANDE) : 17");
        assertContains("detail 3", report.message(), "BON_DE_LIVRAISON <- COMMANDE_CLIENT (via TR_COMMANDE_CLIENT) : 1");
        assertContains("question", report.message(), "Reprendre maintenant ?");
        assertNotContains("jamais « rien a reprendre »", report.message(), AffairRepairReport.NOTHING_TO_DO);
    }

    /** Un compte nul ou negatif n'apparait pas et n'ajoute rien. */
    private static void testZeroCountsIgnored() {
        final AffairRepairReport report = new AffairRepairReport();
        report.add("cas vide", 0);
        report.add("cas absurde", -3);
        assertEquals("total nul", 0L, Long.valueOf(report.getTotal()));
        assertEquals("toujours rien a faire", Boolean.TRUE, Boolean.valueOf(report.isNothingToDo()));
        assertEquals("aucun detail", "", report.getDetail());
    }

    /** Une erreur seule ne doit JAMAIS produire « rien a reprendre ». */
    private static void testErrorIsNeverNothingToDo() {
        final AffairRepairReport report = new AffairRepairReport();
        report.addError("SAISIE_ACHAT <- COMMANDE (SOURCE / IDSOURCE)", "ERROR: column \"IDSOURCE\" does not exist", null);
        assertEquals("total nul", 0L, Long.valueOf(report.getTotal()));
        assertEquals("erreur signalee", Boolean.TRUE, Boolean.valueOf(report.hasErrors()));
        assertEquals("pas rien a faire", Boolean.FALSE, Boolean.valueOf(report.isNothingToDo()));
        assertNotContains("pas de « deja leur affaire »", report.message(), "deja leur affaire");
        assertContains("dit que le diagnostic a echoue", report.message(), AffairRepairReport.COUNT_FAILED);
        assertContains("avertit que le total est incomplet", report.message(), AffairRepairReport.INCOMPLETE);
    }

    /** Une erreur parmi des comptes valides : le total reste affiche, mais signale incomplet. */
    private static void testErrorKeepsCountsAndWarns() {
        final AffairRepairReport report = new AffairRepairReport();
        report.add("FACTURE_FOURNISSEUR <- COMMANDE (via TR_COMMANDE)", 17);
        report.addError("COMMANDE_ELEMENT <- COMMANDE (lignes)", "timeout", "SELECT count(*) FROM ...");
        assertEquals("total conserve", 17L, Long.valueOf(report.getTotal()));
        assertEquals("erreur signalee", Boolean.TRUE, Boolean.valueOf(report.hasErrors()));
        assertContains("total dans le message", report.message(), "17 document(s)");
        assertContains("avertissement", report.message(), AffairRepairReport.INCOMPLETE);
        assertNotContains("pas de « rien a reprendre »", report.message(), AffairRepairReport.NOTHING_TO_DO);
    }

    /** La cause et la requete sont reprises dans le message, pour le support. */
    private static void testSqlAndCauseAreReported() {
        final AffairRepairReport report = new AffairRepairReport();
        final String sql = "SELECT count(*) FROM \"OpenConcerto42\".\"COMMANDE\" WHERE \"ID_AFFAIRE\" > 1";
        report.addError("SAISIE_ACHAT <- COMMANDE", "ERROR: relation does not exist", sql);
        final String message = report.message();
        assertContains("la reprise", message, "SAISIE_ACHAT <- COMMANDE");
        assertContains("la cause", message, "ERROR: relation does not exist");
        assertContains("la requete", message, "SELECT count(*) FROM \"OpenConcerto42\".\"COMMANDE\"");

        final AffairRepairReport withoutMessage = new AffairRepairReport();
        withoutMessage.addError("cas sans cause", "", null);
        assertContains("cause par defaut", withoutMessage.message(), "erreur sans message");
        assertNotContains("pas de requete vide", withoutMessage.message(), "requete :");
    }

    private static void assertEquals(final String label, final Object expected, final Object actual) {
        if (expected == null ? actual == null : expected.equals(actual)) {
            passed++;
            return;
        }
        System.err.println("ECHEC " + label + " : attendu <" + expected + "> obtenu <" + actual + ">");
        throw new IllegalStateException(label);
    }

    private static void assertContains(final String label, final String text, final String expected) {
        if (text != null && text.indexOf(expected) >= 0) {
            passed++;
            return;
        }
        System.err.println("ECHEC " + label + " : <" + expected + "> absent de <" + text + ">");
        throw new IllegalStateException(label);
    }

    private static void assertNotContains(final String label, final String text, final String forbidden) {
        if (text == null || text.indexOf(forbidden) < 0) {
            passed++;
            return;
        }
        System.err.println("ECHEC " + label + " : <" + forbidden + "> present dans <" + text + ">");
        throw new IllegalStateException(label);
    }
}
