package org.openconcerto.erp.modules;

import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Double en memoire du {@code ComponentsContext} d'OpenConcerto, pour les tests.
 *
 * <p>
 * Il reproduit le point de comportement qui a fait echouer un demarrage reel :
 * {@code putAdditionalField} <b>leve une IllegalStateException</b> quand le champ
 * est deja declare (« Already added ID_AFFAIRE in
 * FactureFournisseurSQLElement »). Un double permissif laisserait passer
 * exactement le bug qu'on veut detecter.
 */
public class ComponentsContext {

    private final List<String> registrations = new ArrayList<String>();
    private final Set<String> declared = new LinkedHashSet<String>();

    /** Les tables pour lesquelles le module n'a pas cree le champ : declaration refusee. */
    private final Set<String> notCreatedByModule = new LinkedHashSet<String>();

    /** Refuse la declaration comme le fait OpenConcerto pour un champ non cree par le module. */
    public void refuseFieldOf(final String key) {
        this.notCreatedByModule.add(key);
    }

    public void putAdditionalField(final String tableName, final String fieldName) {
        final String key = tableName + "." + fieldName;
        if (this.notCreatedByModule.contains(key)) {
            throw new IllegalArgumentException("The field " + key + " wasn't created by this module");
        }
        if (!this.declared.add(key)) {
            throw new IllegalStateException("Already added " + fieldName + " in " + tableName);
        }
        this.registrations.add(key);
    }

    /** Declarations acceptees, dans l'ordre : {@code TABLE.CHAMP}. */
    public List<String> getRegistrations() {
        return Collections.unmodifiableList(this.registrations);
    }

    /** Nombre de declarations distinctes acceptees. */
    public int getRegistrationCount() {
        return this.registrations.size();
    }

    /** Table de la derniere declaration acceptee. */
    public String getTableName() {
        if (this.registrations.isEmpty()) {
            return null;
        }
        final String last = this.registrations.get(this.registrations.size() - 1);
        return last.substring(0, last.indexOf('.'));
    }

    /** Champ de la derniere declaration acceptee. */
    public String getFieldName() {
        if (this.registrations.isEmpty()) {
            return null;
        }
        final String last = this.registrations.get(this.registrations.size() - 1);
        return last.substring(last.indexOf('.') + 1);
    }
}
