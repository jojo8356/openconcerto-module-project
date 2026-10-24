package org.openconcerto.sql.model;

/** Minimal row contract used by the injector tests. */
public interface SQLRowAccessor {

    SQLTable getTable();

    Object getObject(String fieldName);
}
