package org.openconcerto.modules.project;

import java.lang.reflect.Field;

/**
 * Nettoyage <b>sans risque</b> des écouteurs de l'historique des affaires quand
 * la fenêtre se ferme.
 *
 * <p>
 * Historique du défaut (trace utilisateur) :
 *
 * <pre>
 * java.lang.NullPointerException: Cannot invoke "JListSQLTablePanel.removeAllTableListener()"
 *   because "this.jListePanel" is null
 *     at ListeHistoriquePanel.removeAllTableListener(ListeHistoriquePanel.java:643)
 *     at ProjectHistory$8.windowClosing(ProjectHistory.java:387)
 * </pre>
 *
 * <p>
 * Cause : {@code ListeHistoriquePanel} construit ses onglets <b>avant</b> de
 * créer la liste de gauche ({@code jListePanel}). Si la construction ne va pas
 * jusqu'au bout (table absente, onglet impossible à filtrer, ou simplement
 * version du client où le panneau est créé plus tard), {@code jListePanel}
 * reste {@code null} et l'appel de nettoyage lève une {@code NullPointerException}
 * <b>au moment où l'utilisateur ferme la fenêtre</b> — donc dans un écouteur
 * d'événement, ce qui déclenche la boîte « UncaughtException » d'OpenConcerto.
 *
 * <p>
 * Fermer une fenêtre ne doit jamais produire d'erreur : ce nettoyage ne sert
 * qu'à éviter des fuites d'écouteurs. Cette classe vérifie donc que le panneau
 * est prêt avant d'appeler le cœur, et répond « rien à faire » sinon.
 *
 * <p>
 * Sans dépendance OpenConcerto (seulement de la réflexion) : elle est vérifiable
 * par {@code AffairLinkSupportTest} avec de faux panneaux.
 */
public final class HistoryPanelCleanup {

    /** Nom du champ interne du cœur qui doit exister avant tout nettoyage. */
    public static final String REQUIRED_FIELD = "jListePanel";

    private HistoryPanelCleanup() {
    }

    /**
     * Vrai si le panneau est assez construit pour que
     * {@code removeAllTableListener()} puisse être appelé.
     *
     * <ul>
     * <li>panneau <code>null</code> : non ;</li>
     * <li>champ {@code jListePanel} présent et <code>null</code> : non (c'est le
     * cas du plantage) ;</li>
     * <li>champ présent et non <code>null</code> : oui ;</li>
     * <li>champ absent (autre version du client, ou objet de test) : oui — on ne
     * peut pas juger, et le nettoyage sera de toute façon protégé.</li>
     * </ul>
     */
    public static boolean isReadyForCleanup(final Object panel) {
        if (panel == null) {
            return false;
        }
        final Field field = findField(panel.getClass());
        if (field == null) {
            return true;
        }
        try {
            field.setAccessible(true);
            return field.get(panel) != null;
        } catch (Exception e) {
            // Champ inaccessible (modules Java récents) : on laisse l'appel
            // protégé décider, sans bloquer la fermeture.
            return true;
        }
    }

    /** Champ {@link #REQUIRED_FIELD} dans la classe ou ses parents, ou <code>null</code>. */
    public static Field findField(final Class<?> type) {
        Class<?> current = type;
        while (current != null) {
            try {
                return current.getDeclaredField(REQUIRED_FIELD);
            } catch (NoSuchFieldException e) {
                current = current.getSuperclass();
            } catch (SecurityException e) {
                return null;
            }
        }
        return null;
    }

    /**
     * Décide et explique ce qu'il faut faire à la fermeture de la fenêtre.
     *
     * @return un texte lisible, destiné au journal du module.
     */
    public static String describe(final Object panel) {
        if (panel == null) {
            return "historique : aucun panneau à nettoyer";
        }
        if (isReadyForCleanup(panel)) {
            return "historique : nettoyage des ecouteurs";
        }
        return "historique : liste de gauche non construite (jListePanel null) : nettoyage ignore";
    }
}
