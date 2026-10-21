package org.openconcerto.modules.project.panels;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Transport « psql » : la suite est alors utilisable avec un simple JDK et
 * postgresql-client, sans JAR de pilote JDBC.
 *
 * <p>
 * On utilise le mode CSV de psql (&gt;= 12) : l'entete donne les noms de
 * colonnes, une cellule vide non quotee vaut NULL, une cellule vide quotee
 * vaut la chaine vide.
 * </p>
 */
public class PsqlSqlClient implements SqlClient {

    private final String psqlPath;
    private final Map<String, String> env;
    private final String description;

    public PsqlSqlClient(String psqlPath, Map<String, String> env) {
        this.psqlPath = psqlPath;
        this.env = env;
        final StringBuilder sb = new StringBuilder("psql");
        if (env.get("PGHOST") != null) {
            sb.append(" -h ").append(env.get("PGHOST"));
        }
        if (env.get("PGPORT") != null) {
            sb.append(" -p ").append(env.get("PGPORT"));
        }
        if (env.get("PGDATABASE") != null) {
            sb.append(" -d ").append(env.get("PGDATABASE"));
        }
        if (env.get("PGUSER") != null) {
            sb.append(" -U ").append(env.get("PGUSER"));
        }
        this.description = sb.toString();
    }

    public List<Map<String, Object>> query(String sql) throws Exception {
        final CsvTable table = runCsv(sql);
        final List<Map<String, Object>> result = new ArrayList<Map<String, Object>>();
        if (table.names.isEmpty()) {
            return result;
        }
        for (int r = 0; r < table.rows.size(); r++) {
            final List values = (List) table.rows.get(r);
            final List quotedList = (List) table.quoted.get(r);
            final Map<String, Object> row = new LinkedHashMap<String, Object>();
            for (int c = 0; c < table.names.size(); c++) {
                final String value = c < values.size() ? (String) values.get(c) : null;
                final boolean isQuoted = c < quotedList.size() && ((Boolean) quotedList.get(c)).booleanValue();
                if (value == null || (!isQuoted && value.length() == 0)) {
                    row.put((String) table.names.get(c), null);
                } else {
                    row.put((String) table.names.get(c), value);
                }
            }
            result.add(row);
        }
        return result;
    }

    public void execute(String sql) throws Exception {
        runCsv(sql);
    }

    public void close() {
        // rien a liberer
    }

    public String describe() {
        return this.description;
    }

    private CsvTable runCsv(String sql) throws Exception {
        final File script = File.createTempFile("oc-panneaux-", ".sql");
        try {
            final Writer out = new OutputStreamWriter(new FileOutputStream(script), "UTF-8");
            try {
                out.write(sql);
                if (!sql.endsWith(";")) {
                    out.write(";");
                }
                out.write("\n");
            } finally {
                out.close();
            }
            final List<String> cmd = new ArrayList<String>();
            cmd.add(this.psqlPath);
            cmd.add("--csv");
            cmd.add("-X");
            cmd.add("-v");
            cmd.add("ON_ERROR_STOP=1");
            cmd.add("-f");
            cmd.add(script.getAbsolutePath());
            final ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.environment().putAll(this.env);
            final Process process = pb.start();
            final String stdout = readFully(process.getInputStream());
            final String stderr = readFully(process.getErrorStream());
            final int code = process.waitFor();
            if (code != 0) {
                throw new IllegalStateException("psql a echoue (code " + code + ") :\n" + stderr + "\n" + stdout);
            }
            return parseCsv(stdout);
        } finally {
            script.delete();
        }
    }

    private static String readFully(InputStream in) throws Exception {
        final ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        final byte[] chunk = new byte[8192];
        int read;
        while ((read = in.read(chunk)) > 0) {
            buffer.write(chunk, 0, read);
        }
        in.close();
        return new String(buffer.toByteArray(), "UTF-8");
    }

    /**
     * Analyse minimale du CSV de psql : gerer les guillemets doubles et les
     * cellules vides (quotees = chaine vide, non quotees = NULL).
     */
    static CsvTable parseCsv(String text) {
        final CsvTable table = new CsvTable();
        final List<String> values = new ArrayList<String>();
        final List<Boolean> quotedFlags = new ArrayList<Boolean>();
        final StringBuilder current = new StringBuilder();
        boolean quoted = false;
        boolean fieldWasQuoted = false;
        boolean inQuotes = false;
        int i = 0;
        final int length = text.length();
        while (i < length) {
            final char c = text.charAt(i);
            if (inQuotes) {
                if (c == '"') {
                    if (i + 1 < length && text.charAt(i + 1) == '"') {
                        current.append('"');
                        i += 2;
                        continue;
                    }
                    inQuotes = false;
                    i++;
                    continue;
                }
                current.append(c);
                i++;
                continue;
            }
            if (c == '"') {
                inQuotes = true;
                fieldWasQuoted = true;
                i++;
                continue;
            }
            if (c == ',') {
                values.add(current.toString());
                quotedFlags.add(Boolean.valueOf(fieldWasQuoted));
                current.setLength(0);
                fieldWasQuoted = false;
                i++;
                continue;
            }
            if (c == '\n' || c == '\r') {
                if (c == '\r' && i + 1 < length && text.charAt(i + 1) == '\n') {
                    i++;
                }
                i++;
                if (values.size() > 0 || current.length() > 0 || fieldWasQuoted) {
                    values.add(current.toString());
                    quotedFlags.add(Boolean.valueOf(fieldWasQuoted));
                    current.setLength(0);
                    fieldWasQuoted = false;
                    // copie : la liste de travail est videe juste apres
                    table.rows.add(new ArrayList<String>(values));
                    table.quoted.add(new ArrayList<Boolean>(quotedFlags));
                    values.clear();
                    quotedFlags.clear();
                }
                continue;
            }
            current.append(c);
            i++;
        }
        if (values.size() > 0 || current.length() > 0 || fieldWasQuoted) {
            values.add(current.toString());
            quotedFlags.add(Boolean.valueOf(fieldWasQuoted));
            table.rows.add(values);
            table.quoted.add(quotedFlags);
        }
        if (!table.rows.isEmpty()) {
            table.names = new ArrayList<String>();
            final List firstRow = (List) table.rows.get(0);
            for (int c = 0; c < firstRow.size(); c++) {
                table.names.add((String) firstRow.get(c));
            }
            table.rows.remove(0);
            table.quoted.remove(0);
        }
        return table;
    }

    static final class CsvTable {
        List<String> names = new ArrayList<String>();
        List<List<String>> rows = new ArrayList<List<String>>();
        List<List<Boolean>> quoted = new ArrayList<List<Boolean>>();
    }
}
