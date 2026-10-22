package org.openconcerto.modules.project;

import org.openconcerto.sql.Configuration;
import org.openconcerto.sql.model.DBRoot;
import org.openconcerto.sql.model.SQLInjector;
import org.openconcerto.sql.model.SQLTable;

/**
 * Transfert « demande de prix » vers « commande fournisseur ».
 *
 * Le module project gere deja de la meme facon le transfert devis -&gt; commande
 * ({@link QuoteToOrderSQLInjector}) et commande -&gt; bon de reception
 * ({@link CmdToBrSQLInjector}) : on s'appuie sur le mecanisme standard
 * OpenConcerto.
 *
 * La table de transfert {@code TR_DEMANDE_PRIX} (qui relie la demande de prix
 * a la commande creee) est creee automatiquement par
 * {@link SQLInjector#createTransferTables(DBRoot)} : il n'y a donc aucune table a
 * creer a la main.
 */
public class DemandePrixCommandeSQLInjector extends SQLInjector {

    public DemandePrixCommandeSQLInjector() {
        this(root());
    }

    public DemandePrixCommandeSQLInjector(final DBRoot root) {
        // storeTransfer = true : le lien demande de prix -> commande est memorise
        super(root, "DEMANDE_PRIX", "COMMANDE", true);
        final SQLTable src = getSource();
        final SQLTable dest = getDestination();
        // origine de la commande (colonnes natives de COMMANDE)
        if (dest.contains("SOURCE")) {
            mapDefaultValues(dest.getField("SOURCE"), src.getName());
        }
        if (dest.contains("IDSOURCE")) {
            map(src.getKey(), dest.getField("IDSOURCE"));
        }
        // champs communs presents des deux cotes
        mapIfExists(src, dest, "ID_AFFAIRE");
        mapIfExists(src, dest, "ID_FOURNISSEUR");
        mapIfExists(src, dest, "DATE");
        mapIfExists(src, dest, "NOM");
    }

    /**
     * Le root qui contient reellement les tables (schema societe).
     */
    public static DBRoot root() {
        final SQLTable table = Configuration.getInstance().getRoot().findTable("DEMANDE_PRIX");
        return table.getDBRoot();
    }

    private void mapIfExists(final SQLTable src, final SQLTable dest, final String name) {
        if (src.contains(name) && dest.contains(name)) {
            map(src.getField(name), dest.getField(name));
        }
    }
}
