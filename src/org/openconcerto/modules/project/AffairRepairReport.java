/*
 * Compte rendu du diagnostic de reprise des affaires.
 *
 * <p>
 * Cette classe existe pour une raison precise : un comptage qui echoue ne doit
 * <b>jamais</b> etre presente comme « rien a reprendre ». Sur la base du client,
 * une reprise dont toutes les requetes de comptage echouaient affichait
 * « Tous les documents transferes ont deja leur affaire : rien a reprendre »
 * alors que 37 documents attendaient leur affaire : l'erreur SQL etait avalee
 * et transformee en zero.
 * </p>
 *
 * <p>
 * Aucune dependance a OpenConcerto : la classe est testable en ligne de
 * commande, sans base et sans interface.
 * </p>
 */
package org.openconcerto.modules.project;

import java.util.ArrayList;
import java.util.List;

public final class AffairRepairReport {

    /** Message quand il n'y a effectivement rien a faire. */
    public static final String NOTHING_TO_DO = "Tous les documents transferes ont deja leur affaire : rien a reprendre.";

    /** Message quand des comptages ont echoue : le total n'est pas fiable. */
    public static final String COUNT_FAILED = "Aucune reprise n'a pu etre comptee : le diagnostic a echoue.";

    /** Avertissement ajoute des qu'une reprise a echoue. */
    public static final String INCOMPLETE = "Reprises en echec (le total ci-dessus est donc INCOMPLET) :";

    private long total = 0;
    private final StringBuilder detail = new StringBuilder();
    private final List<String> errors = new ArrayList<String>();

    /** Ajoute une reprise realisable. Les comptes nuls ou negatifs sont ignores. */
    public void add(final String description, final long count) {
        if (count <= 0) {
            return;
        }
        this.detail.append("  - ").append(description).append(" : ").append(count).append('\n');
        this.total += count;
    }

    /**
     * Ajoute une reprise dont le comptage a echoue.
     *
     * @param description reprise concernee
     * @param cause       message de l'exception (jamais null)
     * @param sql         requete en echec, pour le support (peut etre null)
     */
    public void addError(final String description, final String cause, final String sql) {
        final StringBuilder error = new StringBuilder();
        error.append(description).append('\n');
        error.append("    cause : ").append(cause == null || cause.length() == 0 ? "erreur sans message" : cause);
        if (sql != null && sql.length() > 0) {
            error.append('\n').append("    requete : ").append(sql);
        }
        this.errors.add(error.toString());
    }

    /** Nombre total de documents et de lignes a reprendre. */
    public long getTotal() {
        return this.total;
    }

    /** Vrai si au moins une reprise n'a pas pu etre comptee. */
    public boolean hasErrors() {
        return !this.errors.isEmpty();
    }

    /** Vrai si tout s'est bien passe et qu'il n'y a rien a reprendre. */
    public boolean isNothingToDo() {
        return this.total == 0 && !hasErrors();
    }

    /** Detail ligne par ligne des reprises realisables. */
    public String getDetail() {
        return this.detail.toString();
    }

    /** Texte a afficher : jamais « rien a reprendre » si un comptage a echoue. */
    public String message() {
        if (isNothingToDo()) {
            return NOTHING_TO_DO;
        }
        final StringBuilder message = new StringBuilder();
        if (this.total > 0) {
            message.append(this.total).append(" document(s) ou ligne(s) sans affaire peuvent etre rattaches a leur affaire d'origine :\n\n");
            message.append(this.detail);
            message.append("\nAucune affaire deja renseignee ne sera modifiee.\nReprendre maintenant ?");
        } else {
            message.append(COUNT_FAILED);
        }
        if (hasErrors()) {
            message.append("\n\n").append(INCOMPLETE).append('\n');
            for (final String error : this.errors) {
                message.append("  - ").append(error).append('\n');
            }
        }
        return message.toString();
    }
}
