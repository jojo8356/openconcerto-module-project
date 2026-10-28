package org.openconcerto.modules.project;

import org.openconcerto.erp.modules.ComponentsContext;

/**
 * Declare le champ <b>Affaire</b> dans les ecrans de saisie (commandes, factures,
 * avoirs...), afin que l'affaire soit visible et enregistrable.
 *
 * <p>
 * Point important : {@code ComponentsContext.putAdditionalField} leve une
 * {@link IllegalStateException} (« Already added ID_AFFAIRE in ... ») quand le
 * champ est deja declare. Une double declaration faisait echouer le demarrage
 * complet du module (« Unable to start JarModuleFactory »). Tout passe donc par
 * {@link AffairLinkSupport#registerComponentFields}, qui dedoublonne les tables
 * et transforme « deja declare » en simple information.
 */
final class SupplierInvoiceAffairComponentSupport {

    private SupplierInvoiceAffairComponentSupport() {
    }

    /**
     * Declare l'affaire dans les ecrans de saisie des tables qui portent
     * reellement la colonne.
     *
     * @param ctxt   contexte des composants fourni par OpenConcerto.
     * @param schema schema de la base societe (voir {@code Module.schemaOf}).
     * @return le compte rendu : ajoutes, deja presents, refuses.
     */
    static AffairLinkSupport.RegistrationReport register(final ComponentsContext ctxt, final AffairLinkSupport.Schema schema) {
        return AffairLinkSupport.registerComponentFields(schema, new AffairLinkSupport.AdditionalFieldTarget() {
            @Override
            public boolean putAdditionalField(final String table, final String field) {
                ctxt.putAdditionalField(table, field);
                return true;
            }
        });
    }
}
