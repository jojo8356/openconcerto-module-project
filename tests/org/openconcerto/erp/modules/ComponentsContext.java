package org.openconcerto.erp.modules;

/** In-memory recording double for module component registration. */
public class ComponentsContext {

    private String tableName;
    private String fieldName;
    private int registrationCount;

    public void putAdditionalField(final String tableName, final String fieldName) {
        this.tableName = tableName;
        this.fieldName = fieldName;
        this.registrationCount++;
    }

    public String getTableName() {
        return this.tableName;
    }

    public String getFieldName() {
        return this.fieldName;
    }

    public int getRegistrationCount() {
        return this.registrationCount;
    }
}
