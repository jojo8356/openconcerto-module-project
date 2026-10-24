package org.openconcerto.sql.model;

import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** In-memory row values with the same field validation needed by the tests. */
public class SQLRowValues implements SQLRowAccessor {

    private final SQLTable table;
    private final Map<String, Object> values = new LinkedHashMap<String, Object>();
    private final List<SQLRowValues> referentRows = new ArrayList<SQLRowValues>();

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
        if (value instanceof SQLRowValues) {
            ((SQLRowValues) value).addReferent(this);
        }
        return this;
    }

    private void addReferent(final SQLRowValues referent) {
        if (!this.referentRows.contains(referent)) {
            this.referentRows.add(referent);
        }
    }

    public Collection<SQLRowValues> getReferentRows(final SQLTable table) {
        final List<SQLRowValues> result = new ArrayList<SQLRowValues>();
        for (final SQLRowValues row : this.referentRows) {
            if (row.getTable() == table) {
                result.add(row);
            }
        }
        return result;
    }

    public boolean isForeignEmpty(final String fieldName) {
        final Object value = getObject(fieldName);
        return value instanceof Number && ((Number) value).intValue() == 1;
    }

    @Override
    public Object getObject(final String fieldName) {
        return this.values.get(fieldName);
    }

    public Set<String> getFields() {
        return Collections.unmodifiableSet(this.values.keySet());
    }
}
