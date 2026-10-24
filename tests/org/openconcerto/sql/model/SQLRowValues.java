package org.openconcerto.sql.model;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

/** In-memory row values with the same field validation needed by the tests. */
public class SQLRowValues implements SQLRowAccessor {

    private final SQLTable table;
    private final Map<String, Object> values = new LinkedHashMap<String, Object>();

    public SQLRowValues(final SQLTable table) {
        this.table = table;
    }

    @Override
    public SQLTable getTable() {
        return this.table;
    }

    public SQLRowValues put(final String fieldName, final Object value) {
        // OpenConcerto also rejects writes to unknown fields. Keeping this check
        // in the test double catches an invalid source or destination mapping.
        this.table.getField(fieldName);
        this.values.put(fieldName, value);
        return this;
    }

    @Override
    public Object getObject(final String fieldName) {
        return this.values.get(fieldName);
    }

    public Set<String> getFields() {
        return Collections.unmodifiableSet(this.values.keySet());
    }
}
