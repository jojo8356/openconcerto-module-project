package org.openconcerto.modules.project;

import org.openconcerto.erp.modules.ComponentsContext;

/** Enregistre le rattachement à l'affaire dans l'écran de facture fournisseur. */
final class SupplierInvoiceAffairComponentSupport {

    private static final String TABLE_NAME = "FACTURE_FOURNISSEUR";
    private static final String FIELD_NAME = "ID_AFFAIRE";

    private SupplierInvoiceAffairComponentSupport() {
    }

    static void register(final ComponentsContext ctxt) {
        // Sans ce champ supplémentaire, la colonne existe et l'injecteur la
        // remplit, mais l'écran de facture ne permet pas de voir sa valeur.
        ctxt.putAdditionalField(TABLE_NAME, FIELD_NAME);
    }
}
