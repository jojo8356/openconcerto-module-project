package org.openconcerto.modules.project;

import org.openconcerto.sql.model.DBRoot;
import org.openconcerto.sql.model.SQLInjector;
import org.openconcerto.sql.model.SQLTable;

/**
 * Transfert des lignes d'une « demande de prix » vers les lignes d'une
 * « commande fournisseur ».
 *
 * On suit exactement la convention d'OpenConcerto (cf. l'injecteur natif
 * {@code ArticleCommandeEltSQLInjector}) : toutes les colonnes de même nom
 * sont recopiées. Le prix unitaire et les totaux de la demande de prix sont
 * donc repris comme valeurs de départ ; le fournisseur ayant confirmé un
 * autre prix, il suffit de le corriger dans la commande, OpenConcerto
 * recalcule les totaux tout seul.
 */
public class DemandePrixElementCommandeElementSQLInjector extends SQLInjector {

    public DemandePrixElementCommandeElementSQLInjector() {
        this(DemandePrixCommandeSQLInjector.root());
    }

    public DemandePrixElementCommandeElementSQLInjector(final DBRoot root) {
        // pas de table de transfert pour les lignes : seul l'en-tete est lie
        super(root, "DEMANDE_PRIX_ELEMENT", "COMMANDE_ELEMENT", false);
        // colonnes de meme nom (ID_ARTICLE, QTE, ID_UNITE_VENTE, DESCRIPTIF...)
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
    }
}
