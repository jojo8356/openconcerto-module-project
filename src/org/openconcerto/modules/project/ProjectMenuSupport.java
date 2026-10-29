/*
 * Choix de l'emplacement d'un menu dans la barre de menus.
 *
 * Classe volontairement <b>sans dependance Swing ni OpenConcerto</b> : la regle
 * est testable ({@code ProjectMenuSupportTest}) et {@code Module} ne fait
 * qu'appliquer le resultat a la {@code JMenuBar}.
 *
 * Pourquoi cette classe existe : {@code MainFrame.addMenuItem(action, "Aide")}
 * leve {@code IllegalArgumentException} (« Path should be of the form
 * menu/group/menu/group/... ») car le chemin doit comporter un nombre PAIR
 * d'elements (menu puis groupe). L'exception etait avalee par un catch, donc le
 * menu n'apparaissait jamais.
 */
package org.openconcerto.modules.project;

import java.util.List;

public final class ProjectMenuSupport {

    /** Groupe utilise quand le client n'en impose pas. */
    public static final String DEFAULT_GROUP = "Affichage";

    private ProjectMenuSupport() {
    }

    /**
     * Choisit l'indice du menu a utiliser dans la barre.
     *
     * @param menuTexts textes des menus de la barre, dans l'ordre
     *                  (les entrees <code>null</code> sont ignorees).
     * @param wanted    texte recherche, compare sans tenir compte de la casse,
     *                  des accents ni des espaces de bord (ex. « Aide »).
     * @return l'indice du menu, ou <code>-1</code> si aucun ne correspond.
     */
    public static int findMenu(final List<String> menuTexts, final String wanted) {
        if (menuTexts == null || wanted == null) {
            return -1;
        }
        final String target = normalize(wanted);
        if (target.length() == 0) {
            return -1;
        }
        // 1. correspondance exacte
        for (int i = 0; i < menuTexts.size(); i++) {
            if (normalize(menuTexts.get(i)).equals(target)) {
                return i;
            }
        }
        // 2. correspondance partielle (client traduit : « Aide » / « Help »)
        for (int i = 0; i < menuTexts.size(); i++) {
            final String text = normalize(menuTexts.get(i));
            if (text.length() > 0 && (text.startsWith(target) || text.endsWith(target))) {
                return i;
            }
        }
        return -1;
    }

    /**
     * Chemin a passer a {@code MainFrame.addMenuItem} : toujours <b>pair</b>
     * (menu, groupe), sous peine d'{@code IllegalArgumentException}.
     *
     * @param menu  texte du menu (« Aide »).
     * @param group groupe (« Affichage ») ; {@link #DEFAULT_GROUP} si vide.
     * @return exactement deux elements.
     */
    public static String[] path(final String menu, final String group) {
        final String safeMenu = menu == null || menu.trim().length() == 0 ? "Aide" : menu.trim();
        final String safeGroup = group == null || group.trim().length() == 0 ? DEFAULT_GROUP : group.trim();
        return new String[] { safeMenu, safeGroup };
    }

    /** Vrai si le chemin est acceptable pour {@code addMenuItem} (non vide, pair). */
    public static boolean isValidPath(final String[] path) {
        return path != null && path.length > 0 && path.length % 2 == 0;
    }

    /** Minuscules, sans accents, sans espaces de bord. */
    static String normalize(final String text) {
        if (text == null) {
            return "";
        }
        final String lower = java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFD)
                .replaceAll("\\p{M}", "");
        return lower.trim().toLowerCase(java.util.Locale.ROOT);
    }
}
