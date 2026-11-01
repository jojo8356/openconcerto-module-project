package org.openconcerto.modules.project;

import java.util.ArrayList;
import java.util.List;

import org.openconcerto.sql.model.DBRoot;
import org.openconcerto.sql.users.User;
import org.openconcerto.sql.users.UserManager;
import org.openconcerto.sql.users.rights.UserRights;
import org.openconcerto.sql.users.rights.UserRightsManager;

/**
 * Decide qui peut ouvrir les <b>parametres des libelles de colonnes</b>.
 *
 * <p>
 * Regle demandee : « le role le plus haut disponible sur la base, celui qui a le
 * plus de droits ». OpenConcerto n'a pas de table de roles : la hierarchie est
 * portee par les drapeaux {@code SUPERUSER} et {@code ADMIN} de
 * {@code USER_COMMON}, puis par le nombre de droits accordes dans
 * {@code USER_RIGHT}. On applique donc, dans l'ordre :
 * <ol>
 * <li>s'il existe au moins un super-utilisateur : seuls les super-utilisateurs ;</li>
 * <li>sinon, s'il existe au moins un administrateur : seuls les administrateurs ;</li>
 * <li>sinon, le ou les utilisateurs qui cumulent le plus de droits accordes.</li>
 * </ol>
 *
 * <p>
 * Trois garde-fous, pour ne jamais bloquer l'ERP :
 * <ul>
 * <li>base sans table de droits : le cœur OpenConcerto considere alors que tout
 * est permis, on fait pareil ;</li>
 * <li>requete impossible (table absente, droits SQL insuffisants) : on retombe
 * sur les drapeaux de la session ({@code isSuperUser()} /
 * {@code canModifyRights()}) ;</li>
 * <li>aucun utilisateur lisible : parametrage reserve aux administrateurs.</li>
 * </ul>
 */
public final class ColumnLabelAccess {

    private static volatile Boolean lastResult = null;
    private static volatile String lastReason = "";

    private ColumnLabelAccess() {
    }

    /** Vrai si l'utilisateur de la session peut parametrer les libelles. */
    public static boolean canEdit() {
        return canEdit(null);
    }

    /**
     * Vrai si l'utilisateur de la session peut parametrer les libelles.
     *
     * @param root base de la societe (peut etre <code>null</code> : la decision
     *             se prend alors sur les droits de la session).
     */
    public static boolean canEdit(final DBRoot root) {
        return canEdit(root, true);
    }

    /**
     * Variante silencieuse, utilisee par les nouvelles tentatives d'affichage
     * du menu : seule la decision finale doit apparaitre dans le journal.
     */
    public static boolean canEdit(final DBRoot root, final boolean logDecision) {
        final String reason = explain(root);
        lastReason = reason;
        final boolean allowed = reason.startsWith("acces accorde") || reason.startsWith("aucune table de droits");
        lastResult = Boolean.valueOf(allowed);
        if (!allowed && logDecision) {
            Module.log("parametres des colonnes : " + reason);
        }
        return allowed;
    }

    /**
     * Vrai quand la decision n'a pas pu etre prise (utilisateur de la session
     * encore inconnu au demarrage) : il faut reessayer, pas masquer le menu.
     */
    public static boolean isUndetermined() {
        return ColumnLabelRules.accessIsUndetermined(lastReason);
    }

    /** Vrai si la decision a deja ete prise dans cette session. */
    public static boolean isDecided() {
        return lastResult != null;
    }

    /** Explication de la derniere decision (pour le journal et l'ecran). */
    public static String getLastReason() {
        return lastReason;
    }

    /** Identifiant de l'utilisateur de la session, {@code -1} s'il est inconnu. */
    public static int currentUserId() {
        try {
            final UserManager manager = UserManager.getInstance();
            if (manager == null) {
                return -1;
            }
            final User user = manager.getCurrentUser();
            if (user != null) {
                return user.getId();
            }
            return UserManager.getUserID();
        } catch (Exception e) {
            return -1;
        }
    }

    /** Nom de l'utilisateur de la session, vide s'il est inconnu. */
    public static String currentUserName() {
        try {
            final UserManager manager = UserManager.getInstance();
            final User user = manager == null ? null : manager.getCurrentUser();
            if (user == null) {
                return "";
            }
            final String name = user.getFullName();
            return name == null || name.trim().length() == 0 ? user.getName() : name;
        } catch (Exception e) {
            return "";
        }
    }

    /**
     * Explique la decision d'acces, sans effet de bord : l'ecran de parametrage
     * affiche ce texte, et le journal du client le reprend quand l'acces est
     * refuse.
     */
    public static String explain(final DBRoot root) {
        final int userId = currentUserId();

        final UserRights sessionRights;
        try {
            sessionRights = UserRightsManager.getCurrentUserRights();
        } catch (Exception e) {
            // Pas de gestion de droits chargee : on ne peut pas decider ici.
            return "aucune table de droits dans la base : parametrage ouvert (" + e + ")";
        }

        if (root != null) {
            try {
                final List<ColumnLabelRules.UserRightsInfo> users = loadUsers(root);
                if (!users.isEmpty()) {
                    if (userId < 0) {
                        return "utilisateur de la session inconnu : parametrage reserve aux administrateurs";
                    }
                    return ColumnLabelRules.describeAccess(userId, users);
                }
            } catch (Exception e) {
                Module.log("lecture des droits impossible (" + e + ") : decision sur la session");
            }
        }

        // Repli : drapeaux de la session.
        try {
            if (sessionRights != null && sessionRights.isSuperUser()) {
                return "acces accorde : superutilisateur (" + currentUserName() + ")";
            }
            if (sessionRights != null && sessionRights.canModifyRights()) {
                return "acces accorde : droit de modifier les droits (" + currentUserName() + ")";
            }
        } catch (Exception e) {
            return "aucune table de droits dans la base : parametrage ouvert (" + e + ")";
        }
        return "acces refuse : la base ne donne pas le droit de modifier les droits a " + currentUserName();
    }

    /**
     * Lit les utilisateurs et leurs droits depuis la base.
     *
     * @return la liste, vide si la requete ne renvoie rien.
     * @throws Exception si la base n'a pas les tables attendues.
     */
    public static List<ColumnLabelRules.UserRightsInfo> loadUsers(final DBRoot root) throws Exception {
        final List<ColumnLabelRules.UserRightsInfo> result = new ArrayList<ColumnLabelRules.UserRightsInfo>();
        if (root == null) {
            return result;
        }
        final Object rows = root.getDBSystemRoot().getDataSource().executeA(ColumnLabelRules.roleRightsQuery(ColumnLabelStore.schemaOf(root)));
        if (!(rows instanceof List)) {
            return result;
        }
        for (final Object row : (List<?>) rows) {
            if (!(row instanceof Object[])) {
                continue;
            }
            final Object[] values = (Object[]) row;
            if (values.length < 5 || values[0] == null) {
                continue;
            }
            final int id = toInt(values[0]);
            final String name = values[1] == null ? "" : String.valueOf(values[1]);
            final boolean superUser = toInt(values[2]) != 0;
            final boolean admin = toInt(values[3]) != 0;
            final int rights = toInt(values[4]);
            result.add(new ColumnLabelRules.UserRightsInfo(id, name, rights, admin, superUser));
        }
        return result;
    }

    private static int toInt(final Object value) {
        if (value instanceof Number) {
            return ((Number) value).intValue();
        }
        if (value instanceof Boolean) {
            return ((Boolean) value).booleanValue() ? 1 : 0;
        }
        if (value == null) {
            return 0;
        }
        try {
            return Integer.parseInt(String.valueOf(value).trim());
        } catch (NumberFormatException e) {
            return 0;
        }
    }
}
