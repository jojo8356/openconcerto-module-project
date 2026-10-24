package org.openconcerto.modules.project.panels;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;

/**
 * Transport JDBC. Necessite le pilote PostgreSQL dans le classpath
 * (<code>org.postgresql.Driver</code>).
 */
public class JdbcSqlClient implements SqlClient {

    private final Connection connection;
    private final String description;

    public JdbcSqlClient(String url, String user, String password) throws SQLException {
        try {
            Class.forName("org.postgresql.Driver");
        } catch (ClassNotFoundException e) {
            throw new SQLException("Pilote PostgreSQL absent du classpath (org.postgresql.Driver)", e);
        }
        final Properties props = new Properties();
        if (user != null && user.length() > 0) {
            props.setProperty("user", user);
        }
        if (password != null && password.length() > 0) {
            props.setProperty("password", password);
        }
        this.connection = DriverManager.getConnection(url, props);
        this.description = "JDBC " + url;
        try {
            // Filet de securite : la session est declaree en lecture seule.
            this.connection.setReadOnly(true);
        } catch (SQLException e) {
            // Some drivers refuse setReadOnly : ce n'est pas bloquant.
        }
    }

    public List<Map<String, Object>> query(String sql) throws Exception {
        final List<Map<String, Object>> result = new ArrayList<Map<String, Object>>();
        final Statement stmt = this.connection.createStatement();
        try {
            final ResultSet rs = stmt.executeQuery(sql);
            try {
                final ResultSetMetaData meta = rs.getMetaData();
                final int columnCount = meta.getColumnCount();
                final List<String> names = new ArrayList<String>(columnCount);
                for (int i = 1; i <= columnCount; i++) {
                    names.add(meta.getColumnLabel(i));
                }
                while (rs.next()) {
                    final Map<String, Object> row = new LinkedHashMap<String, Object>();
                    for (int i = 1; i <= columnCount; i++) {
                        final Object value = rs.getObject(i);
                        row.put((String) names.get(i - 1), value == null ? null : String.valueOf(value));
                    }
                    result.add(row);
                }
            } finally {
                rs.close();
            }
        } finally {
            stmt.close();
        }
        return result;
    }

    public void execute(String sql) throws Exception {
        final Statement stmt = this.connection.createStatement();
        try {
            stmt.execute(sql);
        } finally {
            stmt.close();
        }
    }

    public void close() {
        try {
            this.connection.close();
        } catch (SQLException e) {
            // ignore
        }
    }

    public String describe() {
        return this.description;
    }
}
