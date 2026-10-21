package org.openconcerto.modules.project.panels;

import java.io.PrintStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Point d'entree de la suite de tests « panneaux » du module project.
 *
 * <p>
 * Verifie, sur tous les panneaux du module, que les donnees affichees sont
 * bien TOUTES les donnees de la base, et qu'aucune ligne n'est cachee (lien
 * casse, colonne manquante, droit utilisateur, filtre...).
 * </p>
 *
 * <p>
 * Les requetes sont en lecture seule : la base n'est jamais modifiee.
 * </p>
 *
 * <p>
 * Usage :
 * </p>
 *
 * <pre>
 * java -cp &lt;classes&gt;[:&lt;postgresql.jar&gt;] org.openconcerto.modules.project.panels.TestRunner \
 *      --host 127.0.0.1 --port 5432 --db OpenConcertoKineticTherm \
 *      --user openconcerto --password secret
 * </pre>
 *
 * <p>
 * Si le pilote PostgreSQL n'est pas dans le classpath, la suite utilise le
 * binaire <code>psql</code> (variables d'environnement <code>PGHOST</code>,
 * <code>PGPORT</code>, <code>PGDATABASE</code>, <code>PGUSER</code>,
 * <code>PGPASSWORD</code>).
 * </p>
 */
public final class TestRunner {

    private TestRunner() {
    }

    public static void main(final String[] args) {
        // Les accents doivent etre lisibles quelle que soit la locale du poste.
        PrintStream out;
        try {
            out = new PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.out), true, "UTF-8");
        } catch (java.io.UnsupportedEncodingException e) {
            out = System.out;
        }
        try {
            final Options options = Options.parse(args);
            if (options.help) {
                printUsage(out);
                System.exit(0);
            }
            out.println("=== Tests des panneaux du module org.openconcerto.modules.project ===");
            out.println("Base    : " + options.describe());
            final SqlClient client = options.createClient();
            out.println("Transport: " + client.describe());
            final Db db = new Db(client);
            try {
                final List<String> schemas = resolveSchemas(db, options);
                out.println("Schemas : " + schemas);
                out.println();

                final Report report = new Report();
                final List<Suite> suites = new ArrayList<Suite>();
                suites.add(new StructureSuite());
                suites.add(new VisibilitySuite());
                suites.add(new AggregateSuite());
                suites.add(new RightsSuite());
                for (int i = 0; i < suites.size(); i++) {
                    final Suite suite = (Suite) suites.get(i);
                    out.println("--- " + suite.name());
                    try {
                        suite.run(db, schemas, report);
                    } catch (Throwable t) {
                        report.fail(suite.name(), "suite interrompue : " + t);
                    }
                    out.println();
                }
                report.print(out);
                if (report.getFailures() > 0) {
                    out.println("RESULTAT : ECHEC (" + report.getFailures() + " controle(s) en echec)");
                    System.exit(1);
                }
                out.println("RESULTAT : OK (" + report.getChecks() + " controles, aucune donnee cachee)");
                System.exit(0);
            } finally {
                client.close();
            }
        } catch (Throwable t) {
            out.println();
            out.println("ERREUR : " + t);
            t.printStackTrace(out);
            System.exit(2);
        }
    }

    private static List<String> resolveSchemas(final Db db, final Options options) throws Exception {
        if (options.schemas != null && options.schemas.length > 0) {
            final List<String> schemas = new ArrayList<String>();
            for (int i = 0; i < options.schemas.length; i++) {
                schemas.add(options.schemas[i].trim());
            }
            return schemas;
        }
        List<String> schemas = db.schemasWithTable("AFFAIRE");
        if (schemas.isEmpty()) {
            schemas = db.allSchemas();
        }
        if (schemas.isEmpty()) {
            throw new IllegalStateException("Aucun schema trouve dans la base.");
        }
        return schemas;
    }

    private static void printUsage(final PrintStream out) {
        out.println("Suite de tests des panneaux du module org.openconcerto.modules.project");
        out.println();
        out.println("  --host HOTE        serveur PostgreSQL (defaut : PGHOST ou 127.0.0.1)");
        out.println("  --port PORT        port (defaut : PGPORT ou 5432)");
        out.println("  --db BASE          base (defaut : PGDATABASE ou OpenConcertoKineticTherm)");
        out.println("  --user ROLE        role SQL (defaut : PGUSER ou openconcerto)");
        out.println("  --password MDP     mot de passe (defaut : PGPASSWORD)");
        out.println("  --url URL          URL JDBC complete (prioritaire sur host/port/db)");
        out.println("  --schemas LIST     schemas a controler (defaut : ceux qui contiennent AFFAIRE)");
        out.println("  -h, --help         cette aide");
        out.println();
        out.println("Lecture seule : aucune ecriture n'est faite dans la base.");
    }

    /** Options de la ligne de commande. */
    static final class Options {
        String host;
        String port;
        String database;
        String user;
        String password;
        String url;
        String[] schemas;
        boolean help;

        static Options parse(final String[] args) {
            final Options options = new Options();
            options.host = env("PGHOST", "127.0.0.1");
            options.port = env("PGPORT", "5432");
            options.database = env("PGDATABASE", "OpenConcertoKineticTherm");
            options.user = env("PGUSER", "openconcerto");
            options.password = env("PGPASSWORD", "");
            for (int i = 0; i < args.length; i++) {
                final String arg = args[i];
                if ("-h".equals(arg) || "--help".equals(arg)) {
                    options.help = true;
                } else if ("--host".equals(arg)) {
                    options.host = args[++i];
                } else if ("--port".equals(arg)) {
                    options.port = args[++i];
                } else if ("--db".equals(arg) || "--database".equals(arg)) {
                    options.database = args[++i];
                } else if ("--user".equals(arg)) {
                    options.user = args[++i];
                } else if ("--password".equals(arg)) {
                    options.password = args[++i];
                } else if ("--url".equals(arg)) {
                    options.url = args[++i];
                } else if ("--schemas".equals(arg)) {
                    options.schemas = args[++i].split(",");
                } else {
                    throw new IllegalArgumentException("Option inconnue : " + arg);
                }
            }
            return options;
        }

        String describe() {
            if (this.url != null) {
                return this.url;
            }
            return this.host + ":" + this.port + " base " + this.database + " role " + this.user;
        }

        SqlClient createClient() throws Exception {
            if (hasPostgresDriver()) {
                final String jdbcUrl = this.url != null ? this.url : "jdbc:postgresql://" + this.host + ":" + this.port + "/" + this.database;
                return new JdbcSqlClient(jdbcUrl, this.user, this.password);
            }
            final String psql = findPsql();
            if (psql == null) {
                throw new IllegalStateException("Aucun transport disponible : mettez le pilote PostgreSQL (postgresql.jar) dans le classpath"
                        + " (option --url), ou installez le client psql (postgresql-client).");
            }
            final Map<String, String> env = new HashMap<String, String>();
            env.put("PGHOST", this.host);
            env.put("PGPORT", this.port);
            env.put("PGDATABASE", this.database);
            env.put("PGUSER", this.user);
            env.put("PGPASSWORD", this.password == null ? "" : this.password);
            return new PsqlSqlClient(psql, env);
        }

        private static boolean hasPostgresDriver() {
            try {
                Class.forName("org.postgresql.Driver");
                return true;
            } catch (Throwable t) {
                return false;
            }
        }

        private static String findPsql() {
            final String path = System.getenv("PATH");
            if (path == null) {
                return null;
            }
            final String[] dirs = path.split(File_PATH_SEPARATOR);
            for (String dir : dirs) {
                if (dir.length() == 0) {
                    continue;
                }
                final java.io.File file = new java.io.File(dir, "psql");
                if (file.isFile() && file.canExecute()) {
                    return file.getAbsolutePath();
                }
            }
            return null;
        }
    }

    private static String env(final String name, final String fallback) {
        final String value = System.getenv(name);
        if (value == null || value.length() == 0) {
            return fallback;
        }
        return value;
    }

    private static final String File_PATH_SEPARATOR = java.io.File.pathSeparator;
}
