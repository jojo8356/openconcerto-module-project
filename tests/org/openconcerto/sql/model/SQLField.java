package org.openconcerto.sql.model;

/** Test double for an OpenConcerto field. */
public class SQLField {

    private final SQLTable table;
    private final String name;

    public SQLField(final SQLTable table, final String name) {
        this.table = table;
        this.name = name;
    }

    public SQLTable getTable() {
        return this.table;
    }

    public String getName() {
        return this.name;
    }
}
