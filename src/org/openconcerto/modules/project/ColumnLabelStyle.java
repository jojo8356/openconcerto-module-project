package org.openconcerto.modules.project;

import java.awt.Color;
import java.awt.Font;

/**
 * Rendu du texte de la colonne <b>« Libellé affiché »</b> de l'écran de
 * paramétrage.
 *
 * <p>
 * Pourquoi une classe à part : la première version affichait les libellés
 * automatiques en gris italique et les libellés personnalisés en bleu. Sur le
 * poste de l'utilisateur, le gris était trop pâle pour être lu confortablement.
 * La règle est donc désormais simple et unique :
 * <ul>
 * <li><b>toujours noir</b>, quel que soit le thème du client ;</li>
 * <li><b>gras</b> quand le libellé est personnalisé (une règle existe) ;</li>
 * <li>normal sinon (libellé automatique).</li>
 * </ul>
 *
 * <p>
 * Classe sans dépendance OpenConcerto (uniquement {@link Color} et
 * {@link Font}) : elle est vérifiée par {@code ColumnLabelRulesTest}, ce qui
 * évite qu'un futur passage ne remette du gris.
 */
public final class ColumnLabelStyle {

    private ColumnLabelStyle() {
    }

    /** Couleur du libellé affiché : noir, lisible sur tous les thèmes. */
    public static Color color() {
        return Color.BLACK;
    }

    /**
     * Graisse du libellé affiché.
     *
     * @param base       police du tableau (peut être <code>null</code>).
     * @param customized vrai si la ligne porte une règle saisie.
     * @return la police à appliquer : grasse si personnalisé, normale sinon.
     */
    public static Font font(final Font base, final boolean customized) {
        if (base == null) {
            return null;
        }
        return base.deriveFont(customized ? Font.BOLD : Font.PLAIN);
    }

    /** Vrai si le libellé doit être mis en gras (règle saisie). */
    public static boolean isBold(final boolean customized) {
        return customized;
    }

    /** Description lisible, utilisée dans l'aide de l'écran. */
    public static String describe() {
        return "les libellés en gras sont personnalisés ; les autres sont les libellés automatiques";
    }
}
