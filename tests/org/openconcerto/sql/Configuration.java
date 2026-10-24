package org.openconcerto.sql;

import org.openconcerto.sql.model.DBRoot;

/** Configurable test double for the OpenConcerto global configuration. */
public class Configuration {

    private static Configuration instance;

    private final DBRoot root;

    public Configuration(final DBRoot root) {
        this.root = root;
    }

    public static Configuration getInstance() {
        if (instance == null) {
            throw new IllegalStateException("No test configuration installed");
        }
        return instance;
    }

    public static void setInstance(final Configuration configuration) {
        instance = configuration;
    }

    public DBRoot getRoot() {
        return this.root;
    }
}
