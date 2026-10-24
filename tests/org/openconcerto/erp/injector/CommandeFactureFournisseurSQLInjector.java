package org.openconcerto.erp.injector;

import org.openconcerto.sql.model.DBRoot;
import org.openconcerto.sql.model.SQLInjector;

/**
 * Test double for the native OpenConcerto supplier-order-to-invoice injector.
 * It keeps the native header mappings used by these tests.
 */
public class CommandeFactureFournisseurSQLInjector extends SQLInjector {

    public CommandeFactureFournisseurSQLInjector(final DBRoot root) {
        super(root, "COMMANDE", "FACTURE_FOURNISSEUR", true);
        map(getSource().getField("ID_FOURNISSEUR"), getDestination().getField("ID_FOURNISSEUR"));
        map(getSource().getField("NOM"), getDestination().getField("NOM"));
        map(getSource().getField("INFOS"), getDestination().getField("INFOS"));
    }
}
