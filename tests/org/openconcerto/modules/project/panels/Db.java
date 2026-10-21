package org.openconcerto.modules.project.panels;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Petites aides au-dessus de {@link SqlClient} : quoting des identifiants
 * (OpenConcerto utilise des tables en MAJUSCULES, dans des schemas dont le
 * nom n'est pas forcement en minuscules), decouverte des schemas et des
 * colonnes, agregats.
 */
public class Db {

    private final SqlClient client;
    private final Map cache = new HashMap();

    public Db(SqlClient client) {
        this.client = client;
    }

    public SqlClient getClient() {
        return this.client;
    }

    /** « Default » -> « "Default" » (guillemets SQL). */
    public static String quote(String identifier) {
        if (identifier == null) {
            return "null";
        }
        return "\"" + identifier.replace("\"", "\"\"") + "\"";
    }

    /** "schema"."table" */
    public static String qualified(String schema, String table) {
        return quote(schema) + "." + quote(table);
    }

    public List<Map<String, Object>> query(String sql) throws Exception {
        return this.client.query(sql);
    }

    /** Premiere valeur de la premiere ligne (null si aucune ligne). */
    public String scalar(String sql) throws Exception {
        final List rows = this.client.query(sql);
        if (rows.isEmpty()) {
            return null;
        }
        final Map row = (Map) rows.get(0);
        final Iterator values = row.values().iterator();
        if (!values.hasNext()) {
            return null;
        }
        final Object value = values.next();
        return value == null ? null : String.valueOf(value);
    }

    public long count(String sql) throws Exception {
        final String value = this.scalar(sql);
        if (value == null || value.trim().length() == 0) {
            return 0L;
        }
        return Long.parseLong(value.trim());
    }

    public boolean tableExists(String schema, String table) throws Exception {
        final String key = "table:" + schema + "." + table;
        if (this.cache.containsKey(key)) {
            return ((Boolean) this.cache.get(key)).booleanValue();
        }
        final String sql = "select count(*) from information_schema.tables where table_schema = " + literal(schema) + " and table_name = " + literal(table);
        final boolean exists = count(sql) > 0;
        this.cache.put(key, Boolean.valueOf(exists));
        return exists;
    }

    public Set<String> columns(String schema, String table) throws Exception {
        final String cacheKey = "columns:" + schema + "." + table;
        if (this.cache.containsKey(cacheKey)) {
            return (Set<String>) this.cache.get(cacheKey);
        }
        final String sql = "select column_name from information_schema.columns where table_schema = " + literal(schema) + " and table_name = " + literal(table)
                + " order by ordinal_position";
        final Set<String> result = new LinkedHashSet<String>();
        final List rows = this.client.query(sql);
        for (int i = 0; i < rows.size(); i++) {
            final Map row = (Map) rows.get(i);
            final Iterator values = row.values().iterator();
            if (values.hasNext()) {
                final Object value = values.next();
                if (value != null) {
                    result.add(String.valueOf(value));
                }
            }
        }
        this.cache.put(cacheKey, result);
        return result;
    }

    /** Tous les schemas (hors systeme) contenant une table donnee. */
    public List<String> schemasWithTable(String table) throws Exception {
        final String sql = "select distinct table_schema from information_schema.tables where table_name = " + literal(table)
                + " and table_schema not in ('pg_catalog','information_schema') order by table_schema";
        return stringColumn(sql);
    }

    /** Tous les schemas non systeme de la base. */
    public List<String> allSchemas() throws Exception {
        final String sql = "select distinct table_schema from information_schema.tables where table_schema not in ('pg_catalog','information_schema') order by table_schema";
        return stringColumn(sql);
    }

    /** Table contenant une colonne donnee (recherche dans tous les schemas). */
    public List<String> schemasWithTableAndColumn(String table, String column) throws Exception {
        final String sql = "select distinct table_schema from information_schema.columns where table_name = " + literal(table) + " and column_name = " + literal(column)
                + " and table_schema not in ('pg_catalog','information_schema') order by table_schema";
        return stringColumn(sql);
    }

    private List<String> stringColumn(final String sql) throws Exception {
        final List<String> result = new ArrayList<String>();
        final List rows = this.client.query(sql);
        for (int i = 0; i < rows.size(); i++) {
            final Map row = (Map) rows.get(i);
            final Iterator values = row.values().iterator();
            if (values.hasNext()) {
                final Object value = values.next();
                if (value != null) {
                    result.add(String.valueOf(value));
                }
            }
        }
        return result;
    }

    /** Echappe une valeur pour l'injecter dans une chaine SQL. */
    public static String literal(String value) {
        if (value == null) {
            return "null";
        }
        return "'" + value.replace("'", "''") + "'";
    }

    /** Liste d'identifiants SQL, separes par des virgules. */
    public static String idList(final List ids) {
        final StringBuilder sb = new StringBuilder();
        for (int i = 0; i < ids.size(); i++) {
            if (sb.length() > 0) {
                sb.append(", ");
            }
            sb.append(String.valueOf(ids.get(i)));
        }
        return sb.toString();
    }

    /** Premiere valeur de la premiere ligne. */
    public static String first(final List rows) {
        if (rows == null || rows.isEmpty()) {
            return null;
        }
        final Map row = (Map) rows.get(0);
        final Iterator values = row.values().iterator();
        if (!values.hasNext()) {
            return null;
        }
        final Object value = values.next();
        return value == null ? null : String.valueOf(value);
    }

    /** Toutes les valeurs de la premiere colonne. */
    public static List<String> firstColumn(final List rows) {
        final List<String> result = new ArrayList<String>();
        if (rows == null) {
            return result;
        }
        for (int i = 0; i < rows.size(); i++) {
            final Map row = (Map) rows.get(i);
            final Iterator values = row.values().iterator();
            if (values.hasNext()) {
                final Object value = values.next();
                if (value != null) {
                    result.add(String.valueOf(value));
                }
            }
        }
        return result;
    }
}
