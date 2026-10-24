package org.openconcerto.sql.model;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

/** Test double for an OpenConcerto table. */
public class SQLTable {

    private final DBRoot root;
    private final String name;
    private final Map<String, SQLField> fields = new LinkedHashMap<String, SQLField>();

    public SQLTable(final DBRoot root, final String name) {
        this.root = root;
        this.name = name;
    }

    public DBRoot getDBRoot() {
        return this.root;
    }

    public String getName() {
        return this.name;
    }

    public SQLField addField(final String fieldName) {
        final SQLField field = new SQLField(this, fieldName);
        this.fields.put(fieldName, field);
        return field;
    }

    public boolean contains(final String fieldName) {
        return this.fields.containsKey(fieldName);
    }

    public SQLField getField(final String fieldName) {
        final SQLField field = this.fields.get(fieldName);
        if (field == null) {
            throw new IllegalArgumentException(fieldName + " is not in table " + this.name);
        }
        return field;
    }

    public Set<String> getFieldsName() {
        return Collections.unmodifiableSet(this.fields.keySet());
    }
}
