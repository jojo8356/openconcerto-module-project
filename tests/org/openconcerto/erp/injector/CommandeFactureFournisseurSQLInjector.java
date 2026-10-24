package org.openconcerto.erp.injector;

import org.openconcerto.sql.model.DBRoot;
import org.openconcerto.sql.model.SQLInjector;
import org.openconcerto.sql.model.SQLRowAccessor;
import org.openconcerto.sql.model.SQLRowValues;
import org.openconcerto.sql.model.SQLTable;

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

    @Override
    protected void merge(final SQLRowAccessor srcRow, final SQLRowValues rowVals) {
        super.merge(srcRow, rowVals);

        // Reproduce the native behavior needed by the contract tests: copy
        // source lines with the default same-name mapping and attach them to
        // the destination header.
        final SQLTable sourceLines = getSource().getDBRoot().findTable("COMMANDE_ELEMENT");
        final SQLTable destinationLines = getSource().getDBRoot().findTable("FACTURE_FOURNISSEUR_ELEMENT");
        if (sourceLines == null || destinationLines == null) {
            return;
        }
        for (final SQLRowValues sourceLine : ((SQLRowValues) srcRow).getReferentRows(sourceLines)) {
            final SQLRowValues destinationLine = new SQLRowValues(destinationLines);
            for (final String fieldName : sourceLine.getFields()) {
                if (!"ID".equals(fieldName) && destinationLines.contains(fieldName)) {
                    destinationLine.put(fieldName, sourceLine.getObject(fieldName));
                }
            }
            destinationLine.put("ID_FACTURE_FOURNISSEUR", rowVals);
        }
    }
}
