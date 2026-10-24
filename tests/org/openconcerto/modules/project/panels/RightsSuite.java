package org.openconcerto.modules.project.panels;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Controle 4 : les droits utilisateurs ne masquent aucune donnee des
 * panneaux.
 *
 * <p>
 * Le modele est celui d'OpenConcerto 1.7 (<code>UserRightsManager</code>) :
 * </p>
 * <ul>
 * <li>les lignes de la table des droits sont lues par ID croissant, la
 * premiere occurrence gagne ;</li>
 * <li>un objet NULL est un « joker » : il vaut pour tout objet demande ;</li>
 * <li>les droits « macro » sont decomposes (TABLE_ALL_RIGHTS ->
 * SELECT/UPDATE/INSERT/DELETE, TABLE_ALL_MODIF_RIGHTS ->
 * UPDATE/INSERT/DELETE) ;</li>
 * <li>si le compte n'a aucun droit pour un code, OpenConcerto se replie sur
 * l'utilisateur par defaut ;</li>
 * <li>un SUPERUSER a tous les droits.</li>
 * </ul>
 */
public class RightsSuite implements Suite {

    private static final String[] USERS_TABLES = { "USER_COMMON", "UTILISATEUR_COMMON", "UTILISATEUR", "USER" };
    private static final String[] RIGHTS_TABLES = { "USER_RIGHT", "DROIT_UTILISATEUR", "UTILISATEUR_DROIT", "USER_RIGHTS" };
    private static final String[] CODES_TABLES = { "RIGHT", "DROIT", "TYPE_DROIT" };

    public String name() {
        return "Droits (aucune donnee masquee pour un utilisateur)";
    }

    /** Une ligne de la table des droits, apres expansion des macros. */
    private static final class RightRow {
        long id;
        long userId;
        String code;
        String object;
        boolean have;
        int rank;
    }

    private static final class User {
        long id;
        String login;
        String nom;
        String prenom;
        boolean admin;
        boolean superuser;
    }

    public void run(final Db db, final List<String> schemas, final Report report) throws Exception {
        final String usersSchema = findTable(db, USERS_TABLES);
        final String rightsSchema = findTable(db, RIGHTS_TABLES);
        final String codesSchema = findTable(db, CODES_TABLES);
        if (usersSchema == null || rightsSchema == null || codesSchema == null) {
            report.info("droits", "tables des droits introuvables (USER_COMMON / USER_RIGHT / RIGHT) : controle ignore");
            return;
        }
        final String scope = "droits";
        try {
            final Map<Long, User> users = loadUsers(db, usersSchema);
            final List<RightRow> rights = loadRights(db, rightsSchema, codesSchema);
            final long defaultUserId = findDefaultUser(db, usersSchema, users);

            report.info(scope, users.size() + " utilisateur(s), " + rights.size() + " droit(s) ; utilisateur par defaut = " + defaultUserId);

            // Tables reellement affichees par un panneau.
            final Set<String> tables = new HashSet<String>();
            for (int s = 0; s < schemas.size(); s++) {
                final String schema = (String) schemas.get(s);
                final List panelList = Catalogue.build(schema);
                for (int p = 0; p < panelList.size(); p++) {
                    final Panel panel = (Panel) panelList.get(p);
                    tables.add(panel.getTable());
                }
                final List contract = Catalogue.structureContract();
                for (int c = 0; c < contract.size(); c++) {
                    final Panel panel = (Panel) contract.get(c);
                    final List requirements = panel.getRequired();
                    for (int r = 0; r < requirements.size(); r++) {
                        final Panel.Req req = (Panel.Req) requirements.get(r);
                        tables.add(req.table);
                    }
                }
            }

            final List<String> sortedTables = new ArrayList<String>(tables);
            Collections.sort(sortedTables);

            final List userList = new ArrayList(users.values());
            for (int u = 0; u < userList.size(); u++) {
                final User user = (User) userList.get(u);
                if (user.superuser) {
                    report.info(scope, "utilisateur " + label(user) + " : SUPERUSER, tous les droits");
                    continue;
                }
                final List<String> refused = new ArrayList<String>();
                final List<String> absent = new ArrayList<String>();
                for (String table : sortedTables) {
                    final Boolean value = effective(user, rights, defaultUserId, users, "SELECT_ROW", table);
                    if (value == null) {
                        absent.add(table);
                    } else if (!value.booleanValue()) {
                        refused.add(table);
                    }
                }
                if (!refused.isEmpty()) {
                    report.fail(scope, "utilisateur " + label(user) + " : REFUS EXPLICITE de lecture sur " + refused.size() + " table(s) de panneau : " + refused);
                }
                if (!absent.isEmpty()) {
                    report.info(scope, "utilisateur " + label(user) + " : aucun droit propre sur " + absent.size() + " table(s) de panneau (repli sur l'utilisateur par defaut) : "
                            + absent.subList(0, Math.min(10, absent.size())));
                }
                if (refused.isEmpty() && absent.isEmpty()) {
                    report.ok(scope, "utilisateur " + label(user) + " : lecture autorisee sur tous les panneaux");
                }
            }
        } catch (Exception e) {
            report.fail(scope, "controle des droits impossible : " + e.getMessage());
        }
    }

    private String label(final User user) {
        final StringBuilder sb = new StringBuilder();
        sb.append(user.login == null ? "?" : user.login);
        if (user.prenom != null || user.nom != null) {
            sb.append(" (").append(user.prenom == null ? "" : user.prenom).append(" ").append(user.nom == null ? "" : user.nom).append(")");
        }
        if (user.admin) {
            sb.append(" [admin]");
        }
        return sb.toString().trim();
    }

    /**
     * Valeur effective d'un droit pour un utilisateur : TRUE, FALSE (refus
     * explicite) ou null (aucun droit).
     */
    private Boolean effective(final User user, final List<RightRow> rights, final long defaultUserId, final Map<Long, User> users, final String code, final String object) {
        if (user.superuser) {
            return Boolean.TRUE;
        }
        final Boolean own = lookup(user.id, rights, code, object);
        if (own != null) {
            return own;
        }
        // Repli sur l'utilisateur par defaut.
        final User def = (User) users.get(Long.valueOf(defaultUserId));
        if (def == null) {
            return null;
        }
        if (def.superuser) {
            return Boolean.TRUE;
        }
        return lookup(def.id, rights, code, object);
    }

    private Boolean lookup(final long userId, final List<RightRow> rights, final String code, final String object) {
        final List<RightRow> candidates = new ArrayList<RightRow>();
        for (int i = 0; i < rights.size(); i++) {
            final RightRow row = (RightRow) rights.get(i);
            if (row.userId != userId || !row.code.equals(code)) {
                continue;
            }
            if (object == null) {
                if (row.object == null || !row.have) {
                    candidates.add(row);
                }
            } else if (row.object == null || normalize(row.object).equals(normalize(object))) {
                candidates.add(row);
            }
        }
        if (candidates.isEmpty()) {
            return null;
        }
        // tri par (ID de la ligne, rang) : la premiere ligne gagne.
        for (int i = 1; i < candidates.size(); i++) {
            final RightRow current = (RightRow) candidates.get(i);
            int j = i - 1;
            while (j >= 0 && compareRows((RightRow) candidates.get(j), current) > 0) {
                candidates.set(j + 1, candidates.get(j));
                j--;
            }
            candidates.set(j + 1, current);
        }
        return Boolean.valueOf(((RightRow) candidates.get(0)).have);
    }

    private static int compareRows(final RightRow r1, final RightRow r2) {
        if (r1.id != r2.id) {
            return r1.id < r2.id ? -1 : 1;
        }
        return r1.rank - r2.rank;
    }

    /** « "Schema"."TABLE" » -> « TABLE » */
    private static String normalize(final String object) {
        String value = object.replace("\"", "").trim();
        final int dot = value.lastIndexOf('.');
        if (dot >= 0) {
            value = value.substring(dot + 1);
        }
        return value.toUpperCase();
    }

    private String findTable(final Db db, final String[] candidates) throws Exception {
        for (String candidate : candidates) {
            final List<String> schemas = db.schemasWithTable(candidate);
            if (!schemas.isEmpty()) {
                return (String) schemas.get(0);
            }
        }
        return null;
    }

    private Map<Long, User> loadUsers(final Db db, final String schema) throws Exception {
        final Map<Long, User> users = new HashMap<Long, User>();
        final Set<String> columns = db.columns(schema, "USER_COMMON");
        final boolean hasLogin = columns.contains("LOGIN");
        final boolean hasNom = columns.contains("NOM");
        final boolean hasPrenom = columns.contains("PRENOM");
        final boolean hasAdmin = columns.contains("ADMIN");
        final boolean hasSuper = columns.contains("SUPERUSER");
        final StringBuilder sql = new StringBuilder("select u.\"ID\" as id");
        sql.append(hasLogin ? ", u.\"LOGIN\" as login" : ", null as login");
        sql.append(hasNom ? ", u.\"NOM\" as nom" : ", null as nom");
        sql.append(hasPrenom ? ", u.\"PRENOM\" as prenom" : ", null as prenom");
        sql.append(hasAdmin ? ", u.\"ADMIN\" as admin" : ", false as admin");
        sql.append(hasSuper ? ", u.\"SUPERUSER\" as superuser" : ", false as superuser");
        sql.append(" from ").append(Db.qualified(schema, "USER_COMMON")).append(" u order by u.\"ID\"");
        final List userRows = db.query(sql.toString());
        for (int i = 0; i < userRows.size(); i++) {
            final Map<String, Object> row = (Map<String, Object>) userRows.get(i);
            final User user = new User();
            user.id = parseLong(value(row, "id"));
            user.login = value(row, "login");
            user.nom = value(row, "nom");
            user.prenom = value(row, "prenom");
            user.admin = parseBoolean(value(row, "admin"));
            user.superuser = parseBoolean(value(row, "superuser"));
            users.put(Long.valueOf(user.id), user);
        }
        return users;
    }

    private List<RightRow> loadRights(final Db db, final String rightsSchema, final String codesSchema) throws Exception {
        final List<RightRow> result = new ArrayList<RightRow>();
        final String rightsTable = tableNameIn(db, rightsSchema, RIGHTS_TABLES);
        final String codesTable = tableNameIn(db, codesSchema, CODES_TABLES);
        final String sql = "select ur.\"ID\" as id, ur.\"ID_USER_COMMON\" as uid, c.\"CODE\" as code, ur.\"OBJECT\" as object, ur.\"HAVE_RIGHT\" as have"
                + " from " + Db.qualified(rightsSchema, rightsTable) + " ur"
                + " join " + Db.qualified(codesSchema, codesTable) + " c on c.\"ID\" = ur.\"ID_RIGHT\""
                + " order by ur.\"ID\"";
        final List rightRows = db.query(sql);
        for (int i = 0; i < rightRows.size(); i++) {
            final Map<String, Object> row = (Map<String, Object>) rightRows.get(i);
            final RightRow base = new RightRow();
            base.id = parseLong(value(row, "id"));
            base.userId = parseLong(value(row, "uid"));
            base.code = value(row, "code");
            base.object = value(row, "object");
            base.have = parseBoolean(value(row, "have"));
            base.rank = 1;
            if (base.code == null) {
                continue;
            }
            result.add(base);
            if ("TABLE_ALL_RIGHTS".equals(base.code)) {
                expand(result, base, "SELECT_ROW", 5);
                expand(result, base, "UPDATE_ROW", 3);
                expand(result, base, "INSERT_ROW", 4);
                expand(result, base, "DELETE_ROW", 2);
            } else if ("TABLE_ALL_MODIF_RIGHTS".equals(base.code)) {
                expand(result, base, "UPDATE_ROW", 3);
                expand(result, base, "INSERT_ROW", 4);
                expand(result, base, "DELETE_ROW", 2);
            } else if ("LOCK_ADMIN".equals(base.code)) {
                final RightRow lock = new RightRow();
                lock.id = base.id;
                lock.userId = base.userId;
                lock.code = "LOCK_MENU_ADMIN";
                lock.object = null;
                lock.have = base.have;
                lock.rank = 2;
                result.add(lock);
            }
        }
        return result;
    }

    private void expand(final List<RightRow> result, final RightRow base, final String code, final int rank) {
        final RightRow row = new RightRow();
        row.id = base.id;
        row.userId = base.userId;
        row.code = code;
        row.object = base.object;
        row.have = base.have;
        row.rank = rank;
        result.add(row);
    }

    private String tableNameIn(final Db db, final String schema, final String[] candidates) throws Exception {
        for (String candidate : candidates) {
            if (db.tableExists(schema, candidate)) {
                return candidate;
            }
        }
        return candidates[0];
    }

    private long findDefaultUser(final Db db, final String usersSchema, final Map<Long, User> users) throws Exception {
        try {
            final List<String> schemas = db.schemasWithTable("FWK_UNDEFINED_IDS");
            if (!schemas.isEmpty()) {
                final String sql = "select \"UNDEFINED_ID\" from " + Db.qualified((String) schemas.get(0), "FWK_UNDEFINED_IDS")
                        + " where upper(\"TABLENAME\") like '%USER_COMMON%' limit 1";
                final String value = db.scalar(sql);
                if (value != null) {
                    final long id = parseLong(value);
                    if (users.containsKey(Long.valueOf(id))) {
                        return id;
                    }
                }
            }
        } catch (Exception e) {
            // pas de table d'identifiants indefinis : on prend le plus petit ID
        }
        long min = Long.MAX_VALUE;
        final List ids = new ArrayList(users.keySet());
        for (int i = 0; i < ids.size(); i++) {
            min = Math.min(min, ((Long) ids.get(i)).longValue());
        }
        return min == Long.MAX_VALUE ? 1L : min;
    }

    private static String value(final Map<String, Object> row, final String key) {
        final Object value = row.get(key);
        return value == null ? null : String.valueOf(value);
    }

    private static long parseLong(final String value) {
        if (value == null || value.trim().length() == 0) {
            return 0L;
        }
        try {
            return Long.parseLong(value.trim());
        } catch (NumberFormatException e) {
            return 0L;
        }
    }

    private static boolean parseBoolean(final String value) {
        if (value == null) {
            return false;
        }
        final String v = value.trim();
        return "t".equalsIgnoreCase(v) || "true".equalsIgnoreCase(v) || "1".equals(v) || "y".equalsIgnoreCase(v) || "oui".equalsIgnoreCase(v);
    }
}
