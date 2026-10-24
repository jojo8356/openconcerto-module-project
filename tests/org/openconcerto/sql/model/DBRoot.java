package org.openconcerto.sql.model;

import java.util.LinkedHashMap;
import java.util.Map;

/** Test double for the OpenConcerto root table registry. */
public class DBRoot {

    private final Map<String, SQLTable> tables = new LinkedHashMap<String, SQLTable>();

    public void addTable(final SQLTable table) {
        this.tables.put(table.getName(), table);
    }

    public boolean contains(final String tableName) {
        return this.tables.containsKey(tableName);
    }

    public SQLTable findTable(final String tableName) {
        return this.tables.get(tableName);
    }

    public SQLTable getTable(final String tableName) {
        final SQLTable table = findTable(tableName);
        if (table == null) {
            throw new IllegalArgumentException("Unknown table: " + tableName);
        }
        return table;
    }
}
