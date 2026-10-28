package org.openconcerto.modules.project;

import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;

import org.openconcerto.sql.model.DBRoot;

/**
 * Stockage des <b>libelles de colonnes</b>, partages par toute l'equipe.
 *
 * <p>
 * Deux emplacements, comme demande :
 * <ol>
 * <li><b>le serveur SQL</b> — deux tables dans le schema de la societe,
 * {@code PROJECT_COLUMN_LABEL} (les regles) et {@code PROJECT_SETTINGS} (le
 * mode). C'est la source de verite : ce que la personne qui a le plus de droits
 * enregistre s'applique a <b>tous les postes</b>, sans redemarrage du serveur ;</li>
 * <li><b>le jar</b> — le fichier {@code column-labels.properties} embarque
 * dans le jar fournit les valeurs par defaut d'une nouvelle installation. Les
 * valeurs en base, si elles existent, l'emportent toujours.</li>
 * </ol>
 *
 * <p>
 * La classe ne fait aucune supposition sur le contenu des tables du cœur : si
 * {@code USER_COMMON} ou {@code PROJECT_SETTINGS} n'existent pas, elle renvoie
 * des valeurs par defaut et trace une ligne
 * {@code [module project] ...} au lieu de faire echouer le client.
 */
public final class ColumnLabelStore {

    /** Ressource par defaut livree dans le jar. */
    public static final String DEFAULTS_RESOURCE = "/org/openconcerto/modules/project/column-labels.properties";

    /** Cache de la session courante : evite une requete a chaque liste ouverte. */
    private static volatile Map<String, String> cachedLabels = new LinkedHashMap<String, String>();
    private static volatile String cachedMode = ColumnLabelRules.DEFAULT_MODE;
    private static volatile boolean loaded = false;

    private ColumnLabelStore() {
    }

    // ------------------------------------------------------------------
    // Lecture
    // ------------------------------------------------------------------

    /** Libelles en vigueur (valeurs du jar + valeurs de la base, base gagnante). */
    public static Map<String, String> getLabels() {
        return cachedLabels;
    }

    /** Mode en vigueur ({@link ColumnLabelRules#MODE_AUTO} par defaut). */
    public static String getMode() {
        return cachedMode;
    }

    /** Vrai si la base a deja ete lue dans cette session. */
    public static boolean isLoaded() {
        return loaded;
    }

    /**
     * (Re)charge les libelles depuis la base et met le cache a jour.
     * <p>
     * A appeler au demarrage du module et apres chaque enregistrement.
     *
     * @return les libelles en vigueur (jamais <code>null</code>).
     */
    public static Map<String, String> reload(final DBRoot root) {
        final Map<String, String> fromJar = loadJarDefaults();
        final Map<String, String> fromDatabase = new LinkedHashMap<String, String>();
        // Le mode du jar sert de valeur par defaut ; la base, si elle a une ligne,
        // l'emporte (c'est elle qui porte le choix de l'equipe).
        String mode = modeFromJar();
        if (root != null) {
            try {
                ensureTables(root);
                for (final Object[] row : executeRows(root, ColumnLabelRules.loadLabelsQuery(schemaOf(root)))) {
                    if (row.length >= 3 && row[0] != null && row[1] != null && row[2] != null) {
                        final String key = ColumnLabelRules.key(String.valueOf(row[0]), String.valueOf(row[1]));
                        fromDatabase.put(key, String.valueOf(row[2]));
                    }
                }
                for (final Object[] row : executeRows(root, ColumnLabelRules.loadSettingsQuery(schemaOf(root)))) {
                    if (row.length >= 2 && row[0] != null && ColumnLabelRules.MODE_KEY.equalsIgnoreCase(String.valueOf(row[0]))) {
                        mode = ColumnLabelRules.normalizeMode(row[1] == null ? null : String.valueOf(row[1]));
                    }
                }
            } catch (Exception e) {
                Module.log("libelles de colonnes : lecture impossible (" + e + "), valeurs du jar utilisees");
            }
        }
        final Map<String, String> merged = ColumnLabelRules.merge(fromJar, fromDatabase);
        cachedLabels = merged;
        cachedMode = mode;
        loaded = true;
        return merged;
    }

    /**
     * Lit le fichier de valeurs par defaut du jar.
     *
     * @return les regles declarees, vide si la ressource est absente ou illisible.
     */
    public static Map<String, String> loadJarDefaults() {
        final Map<String, String> result = new LinkedHashMap<String, String>();
        final InputStream stream = ColumnLabelStore.class.getResourceAsStream(DEFAULTS_RESOURCE);
        if (stream == null) {
            return result;
        }
        try {
            final Properties properties = new Properties();
            properties.load(new InputStreamReader(stream, "UTF-8"));
            for (final String name : properties.stringPropertyNames()) {
                if ("mode".equalsIgnoreCase(name)) {
                    continue;
                }
                final String key = name.trim().toUpperCase();
                if (key.indexOf('.') < 0) {
                    continue;
                }
                final String value = properties.getProperty(name);
                if (ColumnLabelRules.isValidLabel(value)) {
                    result.put(key, ColumnLabelRules.cleanLabel(value));
                }
            }
        } catch (Exception e) {
            Module.log("libelles du jar illisibles : " + e);
        } finally {
            try {
                stream.close();
            } catch (Exception e) {
                // rien a faire
            }
        }
        return result;
    }

    /** Mode declare dans le fichier de valeurs par defaut du jar. */
    public static String modeFromJar() {
        final InputStream stream = ColumnLabelStore.class.getResourceAsStream(DEFAULTS_RESOURCE);
        if (stream == null) {
            return ColumnLabelRules.DEFAULT_MODE;
        }
        try {
            final Properties properties = new Properties();
            properties.load(new InputStreamReader(stream, "UTF-8"));
            return ColumnLabelRules.normalizeMode(properties.getProperty("mode"));
        } catch (Exception e) {
            return ColumnLabelRules.DEFAULT_MODE;
        } finally {
            try {
                stream.close();
            } catch (Exception e) {
                // rien a faire
            }
        }
    }

    // ------------------------------------------------------------------
    // Ecriture
    // ------------------------------------------------------------------

    /**
     * Enregistre les libelles pour <b>toute l'equipe</b> (table
     * {@code PROJECT_COLUMN_LABEL}) en une seule transaction, puis recharge le
     * cache.
     *
     * @param root   base de la societe.
     * @param labels regles a enregistrer.
     * @param mode   mode d'application.
     * @param userId utilisateur qui enregistre (trace dans la table).
     * @return la liste des problemes rencontres, vide si tout s'est bien passe.
     */
    public static List<String> save(final DBRoot root, final Map<String, String> labels, final String mode, final int userId) {
        final java.util.List<String> problems = ColumnLabelRules.validate(labels);
        if (root == null) {
            problems.add("aucune base de donnees : rien ne peut etre enregistre");
            return problems;
        }
        if (!problems.isEmpty()) {
            return problems;
        }
        try {
            ensureTables(root);
            execute(root, ColumnLabelRules.saveStatements(schemaOf(root), labels, mode, userId));
        } catch (Exception e) {
            problems.add("enregistrement impossible : " + e);
            return problems;
        }
        reload(root);
        return problems;
    }

    /**
     * Cree les deux tables du module si elles manquent. Idempotent et sans effet
     * bloquant : une erreur est tracee, le client continue de fonctionner avec
     * les valeurs du jar.
     *
     * @return les problemes rencontres (vide si tout va bien).
     */
    public static List<String> ensureTables(final DBRoot root) {
        final java.util.List<String> problems = new java.util.ArrayList<String>();
        if (root == null) {
            problems.add("aucune base : tables de libelles non verifiees");
            return problems;
        }
        for (final String statement : ColumnLabelRules.createTableStatements(schemaOf(root))) {
            try {
                execute(root, statement);
            } catch (Exception e) {
                // Deja existant = cas normal (l'operation est idempotente).
                if (!Module.isAlreadyExists(e)) {
                    problems.add("creation impossible : " + e);
                }
            }
        }
        return problems;
    }

    /** Nom du schema de la societe. */
    public static String schemaOf(final DBRoot root) {
        return root == null ? "" : root.getName();
    }

    // ------------------------------------------------------------------
    // Execution SQL
    // ------------------------------------------------------------------

    private static void execute(final DBRoot root, final String sql) {
        root.getDBSystemRoot().getDataSource().execute(sql);
    }

    @SuppressWarnings("unchecked")
    private static List<Object[]> executeRows(final DBRoot root, final String sql) {
        final Object result = root.getDBSystemRoot().getDataSource().executeA(sql);
        if (result instanceof List) {
            return (List<Object[]>) result;
        }
        return new java.util.ArrayList<Object[]>();
    }
}
