package org.openconcerto.modules.project;

import org.openconcerto.erp.injector.CommandeFactureFournisseurSQLInjector;
import org.openconcerto.sql.Configuration;
import org.openconcerto.sql.model.DBRoot;
import org.openconcerto.sql.model.SQLRowAccessor;
import org.openconcerto.sql.model.SQLRowValues;
import org.openconcerto.sql.model.SQLTable;

/**
 * Transfert « commande fournisseur » → « facture fournisseur » qui conserve le
 * rattachement à l'affaire.
 * <p>
 * L'injecteur natif OpenConcerto continue de gérer les autres champs, les lignes
 * et la table de transfert. Ce sous-type ajoute la reprise de
 * {@code COMMANDE.ID_AFFAIRE} dans {@code FACTURE_FOURNISSEUR.ID_AFFAIRE} et
 * dans les lignes de facture dont l'affaire est vide ou indéfinie.
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

    @Override
    protected void merge(final SQLRowAccessor srcRow, final SQLRowValues rowVals) {
        // Le natif crée d'abord les lignes et les rattache à l'en-tête.
        super.merge(srcRow, rowVals);

        final SQLTable invoiceLines = getSource().getDBRoot().findTable("FACTURE_FOURNISSEUR_ELEMENT");
        if (invoiceLines == null || !invoiceLines.contains("ID_AFFAIRE") || !getDestination().contains("ID_AFFAIRE")) {
            return;
        }
        final Object headerAffair = rowVals.getObject("ID_AFFAIRE");
        if (headerAffair == null || rowVals.isForeignEmpty("ID_AFFAIRE")) {
            return;
        }

        for (final SQLRowValues invoiceLine : rowVals.getReferentRows(invoiceLines)) {
            // Le mapping natif des lignes peut déjà avoir repris une affaire
            // précise : ne l'écraser que si elle est vide ou indéfinie.
            if (invoiceLine.getObject("ID_AFFAIRE") == null || invoiceLine.isForeignEmpty("ID_AFFAIRE")) {
                invoiceLine.put("ID_AFFAIRE", headerAffair);
            }
        }
    }
}
