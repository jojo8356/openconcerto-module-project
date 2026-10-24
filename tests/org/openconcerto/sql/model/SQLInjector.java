package org.openconcerto.sql.model;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Small in-memory version of OpenConcerto's injector contract: explicit field
 * mappings, destination row creation and global source/destination registration.
 */
public class SQLInjector {

    private static final Map<DBRoot, Map<SQLTable, Map<SQLTable, SQLInjector>>> REGISTERED = new HashMap<DBRoot, Map<SQLTable, Map<SQLTable, SQLInjector>>>();

    private final SQLTable source;
    private final SQLTable destination;
    private final List<SQLField> from = new ArrayList<SQLField>();
    private final List<SQLField> to = new ArrayList<SQLField>();

    public SQLInjector(final DBRoot root, final String source, final String destination, final boolean storeTransfer) {
        this(root.getTable(source), root.getTable(destination), storeTransfer);
    }

    public SQLInjector(final SQLTable source, final SQLTable destination, final boolean storeTransfer) {
        this.source = source;
        this.destination = destination;

        Map<SQLTable, Map<SQLTable, SQLInjector>> bySource = REGISTERED.get(source.getDBRoot());
        if (bySource == null) {
            bySource = new HashMap<SQLTable, Map<SQLTable, SQLInjector>>();
            REGISTERED.put(source.getDBRoot(), bySource);
        }
        Map<SQLTable, SQLInjector> byDestination = bySource.get(source);
        if (byDestination == null) {
            byDestination = new HashMap<SQLTable, SQLInjector>();
            bySource.put(source, byDestination);
        }
        // As in OpenConcerto, the most recently created injector for a pair of
        // tables replaces the previous one.
        byDestination.put(destination, this);
    }

    protected final void map(final SQLField from, final SQLField to) {
        if (from.getTable() != this.source) {
            throw new IllegalArgumentException("Source field does not belong to " + this.source.getName());
        }
        if (to.getTable() != this.destination) {
            throw new IllegalArgumentException("Destination field does not belong to " + this.destination.getName());
        }
        final int existingIndex = this.from.indexOf(from);
        if (existingIndex >= 0) {
            this.to.set(existingIndex, to);
        } else {
            this.from.add(from);
            this.to.add(to);
        }
    }

    public final SQLRowValues createRowValuesFrom(final SQLRowAccessor sourceRow) {
        final SQLRowValues result = new SQLRowValues(this.destination);
        mergeChecked(sourceRow, result);
        return result;
    }

    public final SQLRowValues createRowValuesFrom(final List<? extends SQLRowAccessor> sourceRows) {
        final SQLRowValues result = new SQLRowValues(this.destination);
        for (final SQLRowAccessor sourceRow : sourceRows) {
            mergeChecked(sourceRow, result);
        }
        return result;
    }

    private void mergeChecked(final SQLRowAccessor sourceRow, final SQLRowValues result) {
        if (sourceRow.getTable() != this.source) {
            throw new IllegalArgumentException("Row is not from source table " + this.source.getName());
        }
        merge(sourceRow, result);
    }

    protected void merge(final SQLRowAccessor sourceRow, final SQLRowValues result) {
        for (int i = 0; i < this.from.size(); i++) {
            result.put(this.to.get(i).getName(), sourceRow.getObject(this.from.get(i).getName()));
        }
    }

    public final SQLTable getSource() {
        return this.source;
    }

    public final SQLTable getDestination() {
        return this.destination;
    }

    public final List<SQLField> getFrom() {
        return this.from;
    }

    public final List<SQLField> getTo() {
        return this.to;
    }

    public static SQLInjector getInjector(final SQLTable source, final SQLTable destination) {
        final Map<SQLTable, Map<SQLTable, SQLInjector>> bySource = REGISTERED.get(source.getDBRoot());
        if (bySource != null) {
            final Map<SQLTable, SQLInjector> byDestination = bySource.get(source);
            if (byDestination != null && byDestination.containsKey(destination)) {
                return byDestination.get(destination);
            }
        }

        // Fallback provided by OpenConcerto when no custom injector exists.
        final SQLInjector fallback = new SQLInjector(source, destination, false);
        for (final String fieldName : source.getFieldsName()) {
            if (!"ID".equals(fieldName) && destination.contains(fieldName)) {
                fallback.map(source.getField(fieldName), destination.getField(fieldName));
            }
        }
        return fallback;
    }
}
