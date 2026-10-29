package org.openconcerto.modules.project;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Tests de {@link ProjectMenuSupport} : repere du menu dans la barre et chemin
 * d'insertion valide.
 * <p>
 * Cas reel corrige : {@code MainFrame.addMenuItem(action, "Aide")} leve
 * {@code IllegalArgumentException} (« Path should be of the form
 * menu/group/menu/group/... ») car le chemin doit etre <b>pair</b> ; l'entree
 * « Diagnostic affaire » n'apparaissait donc jamais dans le menu Aide.
 */
public final class ProjectMenuSupportTest {

    private static int passed = 0;

    public static void main(final String[] args) {
        testFindMenuByText();
        testFindMenuToleratesCaseAccentsAndSpaces();
        testFindMenuPartialMatch();
        testFindMenuAbsent();
        testPathIsAlwaysEven();
        testPathDefaults();
        testRealMenuBar();
        System.out.println("ProjectMenuSupportTest : " + passed + " tests OK");
    }

    private static void assertEquals(final String label, final Object expected, final Object actual) {
        if (expected == null ? actual != null : !expected.equals(actual)) {
            throw new AssertionError(label + " : attendu <" + expected + ">, obtenu <" + actual + ">");
        }
        passed++;
    }

    private static final List<String> MENUS = Arrays.asList("Fichier", "Saisie", "Gestion", "Comptabilite", "Déclaration", "Statistiques", "Paiement", "Paye", "Structure", "Aide");

    private static void testFindMenuByText() {
        assertEquals("Aide trouve", 9, ProjectMenuSupport.findMenu(MENUS, "Aide"));
        assertEquals("Structure trouve", 8, ProjectMenuSupport.findMenu(MENUS, "Structure"));
        assertEquals("Parametres absent", -1, ProjectMenuSupport.findMenu(MENUS, "Paramètres"));
    }

    private static void testFindMenuToleratesCaseAccentsAndSpaces() {
        assertEquals("minuscules", 9, ProjectMenuSupport.findMenu(MENUS, "aide"));
        assertEquals("espaces de bord", 9, ProjectMenuSupport.findMenu(MENUS, "  AIDE  "));
        assertEquals("accent ignore", 3, ProjectMenuSupport.findMenu(MENUS, "Comptabilité"));
    }

    private static void testFindMenuPartialMatch() {
        // client traduit : « Aide » peut s'appeler « Aide & contact »
        final List<String> menus = Arrays.asList("Fichier", "Aide & contact");
        assertEquals("correspondance partielle", 1, ProjectMenuSupport.findMenu(menus, "Aide"));
        final List<String> menus2 = Arrays.asList("Fichier", "Centre d'aide");
        assertEquals("suffixe", 1, ProjectMenuSupport.findMenu(menus2, "aide"));
    }

    private static void testFindMenuAbsent() {
        assertEquals("liste vide", -1, ProjectMenuSupport.findMenu(new ArrayList<String>(), "Aide"));
        assertEquals("liste nulle", -1, ProjectMenuSupport.findMenu(null, "Aide"));
        assertEquals("recherche nulle", -1, ProjectMenuSupport.findMenu(MENUS, null));
        assertEquals("textes nuls ignores", 1, ProjectMenuSupport.findMenu(Arrays.asList(null, "Aide"), "Aide"));
    }

    /**
     * LE test de la regression : le chemin passe a {@code addMenuItem} doit etre
     * valide (pair). L'ancien code passait un seul element et l'exception etait
     * avalee, donc le menu n'apparaissait jamais.
     */
    private static void testPathIsAlwaysEven() {
        final String[] path = ProjectMenuSupport.path("Aide", null);
        assertEquals("chemin a deux elements", 2, path.length);
        assertEquals("menu", "Aide", path[0]);
        assertEquals("groupe par defaut", ProjectMenuSupport.DEFAULT_GROUP, path[1]);
        assertEquals("chemin valide", Boolean.TRUE, Boolean.valueOf(ProjectMenuSupport.isValidPath(path)));

        // le chemin fautif de l'ancien code est refuse par la regle
        assertEquals("un seul element invalide", Boolean.FALSE, Boolean.valueOf(ProjectMenuSupport.isValidPath(new String[] { "Aide" })));
        assertEquals("trois elements invalides", Boolean.FALSE, Boolean.valueOf(ProjectMenuSupport.isValidPath(new String[] { "Aide", "x", "y" })));
        assertEquals("chemin nul invalide", Boolean.FALSE, Boolean.valueOf(ProjectMenuSupport.isValidPath(null)));
        assertEquals("chemin a quatre elements accepte", Boolean.TRUE, Boolean.valueOf(ProjectMenuSupport.isValidPath(new String[] { "a", "b", "c", "d" })));
    }

    private static void testPathDefaults() {
        assertEquals("menu vide", "Aide", ProjectMenuSupport.path("", "Affichage")[0]);
        assertEquals("menu nul", "Aide", ProjectMenuSupport.path(null, null)[0]);
        assertEquals("groupe vide", ProjectMenuSupport.DEFAULT_GROUP, ProjectMenuSupport.path("Aide", "")[1]);
        assertEquals("espaces nettoyes", "Structure", ProjectMenuSupport.path("  Structure  ", "  Import  ")[0]);
        assertEquals("groupe nettoye", "Import", ProjectMenuSupport.path("Structure", "  Import  ")[1]);
    }

    /**
     * Rejoue la barre de menus reelle du client (capture de l'utilisateur) :
     * l'entree doit atterrir dans « Aide », le dernier menu.
     */
    private static void testRealMenuBar() {
        final int index = ProjectMenuSupport.findMenu(MENUS, "Aide");
        assertEquals("Aide est bien le menu de l'ecran", "Aide", MENUS.get(index));
        // et le chemin de repli reste exploitable
        assertEquals("repli valide", Boolean.TRUE, Boolean.valueOf(ProjectMenuSupport.isValidPath(ProjectMenuSupport.path(MENUS.get(index), null))));
    }
}
