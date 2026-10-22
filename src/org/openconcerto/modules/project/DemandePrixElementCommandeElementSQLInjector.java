package org.openconcerto.modules.project;

import org.openconcerto.sql.model.DBRoot;
import org.openconcerto.sql.model.SQLInjector;
import org.openconcerto.sql.model.SQLField;
import org.openconcerto.sql.model.SQLTable;

/**
 * Transfert des lignes d'une « demande de prix » vers les lignes d'une
 * « commande fournisseur ».
 *
 * Le transfert est fait « a blanc » : on recopie l'article, la designation et
 * la quantite, mais pas les totaux (qui sont recalcules par le client). Le
 * prix unitaire reste donc a saisir, comme dans une demande de prix.
 */
public class DemandePrixElementCommandeElementSQLInjector extends SQLInjector {

    /** Colonnes de total : recalculees par le client, on ne les recopie pas. */
    private static final String[] TOTAUX = new String[] { "T_HT", "T_TTC", "T_PA_HT", "T_PA_TTC", "MONTANT_HT", "MONTANT_TTC" };

    public DemandePrixElementCommandeElementSQLInjector() {
        this(DemandePrixCommandeSQLInjector.root());
    }

    public DemandePrixElementCommandeElementSQLInjector(final DBRoot root) {
        // pas de table de transfert pour les lignes : seul l'en-tete est lie
        super(root, "DEMANDE_PRIX_ELEMENT", "COMMANDE_ELEMENT", false);
        // colonnes de meme nom (ID_ARTICLE, QTE, ID_UNITE_VENTE...)
        createDefaultMap();
        final SQLTable src = getSource();
        final SQLTable dest = getDestination();
        // la designation peut s'appeler DESIGNATION ou DESCRIPTIF selon la version
        // (si la destination a deja une colonne DESIGNATION, le mapping par defaut
        // a fait le travail)
        if (src.contains("DESIGNATION") && !dest.contains("DESIGNATION")) {
            if (dest.contains("DESCRIPTIF")) {
                map(src.getField("DESIGNATION"), dest.getField("DESCRIPTIF"));
            } else if (dest.contains("DESIGNIF")) {
                map(src.getField("DESIGNATION"), dest.getField("DESIGNIF"));
            }
        }
        // on ne recopie pas les totaux
        for (int i = 0; i < TOTAUX.length; i++) {
            final String name = TOTAUX[i];
            if (src.contains(name) && dest.contains(name)) {
                unmap(src.getField(name), dest.getField(name));
            }
        }
    }

    /**
     * Supprime une correspondance du mapping si elle existe.
     */
    private void unmap(final SQLField from, final SQLField to) {
        final java.util.List<SQLField> src = getFrom();
        final java.util.List<SQLField> dest = getTo();
        for (int i = 0; i < src.size() && i < dest.size(); i++) {
            if (src.get(i).getName().equalsIgnoreCase(from.getName()) && dest.get(i).getName().equalsIgnoreCase(to.getName())) {
                remove(src.get(i), dest.get(i));
                return;
            }
        }
    }
}
