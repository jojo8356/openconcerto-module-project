package org.openconcerto.modules.project;

import org.openconcerto.erp.injector.CommandeFactureFournisseurSQLInjector;
import org.openconcerto.sql.Configuration;
import org.openconcerto.sql.model.DBRoot;

/**
 * Transfert « commande fournisseur » → « facture fournisseur » qui conserve le
 * rattachement à l'affaire.
 * <p>
 * L'injecteur natif OpenConcerto continue de gérer les autres champs, les lignes
 * et la table de transfert. Ce sous-type ajoute uniquement la reprise de
 * {@code COMMANDE.ID_AFFAIRE} dans {@code FACTURE_FOURNISSEUR.ID_AFFAIRE}.
 */
public class SupplierOrderToInvoiceSQLInjector extends CommandeFactureFournisseurSQLInjector {

    public SupplierOrderToInvoiceSQLInjector() {
        this(Configuration.getInstance().getRoot());
    }

    public SupplierOrderToInvoiceSQLInjector(final DBRoot root) {
        super(root);
        // Ne pas empêcher le démarrage sur un schéma ancien ou partiel : le
        // transfert natif reste utilisable et seule la reprise d'affaire est
        // désactivée si l'une des deux colonnes n'existe pas.
        if (getSource().contains("ID_AFFAIRE") && getDestination().contains("ID_AFFAIRE")) {
            map(getSource().getField("ID_AFFAIRE"), getDestination().getField("ID_AFFAIRE"));
        }
    }
}
