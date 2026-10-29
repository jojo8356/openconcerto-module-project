/*
 * Diagnostic « l'affaire n'est pas visible / pas choisissable ».
 *
 * But : répondre EN UN CLIC, dans la session de l'utilisateur concerné, à la
 * question « pourquoi le champ Affaire est-il vide ou grisé ? » — sans SQL et
 * sans deviner.
 *
 * Le rapport rassemble :
 * <ul>
 * <li>l'utilisateur courant (identifiant, nom) ;</li>
 * <li>ses droits réels sur les tables concernées, calculés par le cœur
 * ({@link org.openconcerto.sql.users.rights.UserRights#canView(SQLTable)},
 * qui tient compte de l'héritage du compte « Indéfini ») ;</li>
 * <li>le nombre de lignes des tables ;</li>
 * <li>le contenu réel du menu déroulant des affaires
 * ({@link ComboSQLRequest#getComboItems()}) : nombre d'entrées, entrées sans
 * texte, et si l'affaire enregistrée sur un document y figure.</li>
 * </ul>
 *
 * Aucune donnée n'est modifiée : uniquement des lectures.
 */
package org.openconcerto.modules.project;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;

import javax.swing.JOptionPane;
import javax.swing.JScrollPane;
import javax.swing.JTextArea;
import javax.swing.SwingUtilities;

import org.openconcerto.sql.Configuration;
import org.openconcerto.sql.element.SQLElement;
import org.openconcerto.sql.model.DBRoot;
import org.openconcerto.sql.model.SQLTable;
import org.openconcerto.sql.request.ComboSQLRequest;
import org.openconcerto.sql.sqlobject.IComboSelectionItem;
import org.openconcerto.sql.users.User;
import org.openconcerto.sql.users.UserManager;
import org.openconcerto.sql.users.rights.UserRights;

public final class AffairDiagnostic {

    /** Tables dont la lecture conditionne l'affichage de l'affaire. */
    private static final String[] TABLES = new String[] { "AFFAIRE", "COMMANDE", "FACTURE_FOURNISSEUR", "SAISIE_ACHAT", "COMMANDE_CLIENT", "SAISIE_VENTE_FACTURE" };

    private AffairDiagnostic() {
    }

    /**
     * Construit le rapport. Lit la base : appeler hors de l'EDT.
     *
     * @param root base de la société.
     * @return le rapport, en texte.
     */
    public static String buildReport(final DBRoot root) {
        final StringBuilder sb = new StringBuilder();
        sb.append("diagnostic affaire — ").append(new Date()).append('\n');

        // --- utilisateur et droits -------------------------------------
        final UserRights rights = currentRights(sb);
        sb.append('\n');

        // --- lecture des tables ----------------------------------------
        sb.append("droits sur les tables (lecture / modification) :\n");
        if (root == null) {
            sb.append("  base indisponible : impossible de conclure\n");
        } else {
            for (final String tableName : TABLES) {
                final SQLTable table = root.contains(tableName) ? root.getTable(tableName) : null;
                if (table == null) {
                    sb.append("  ").append(pad(tableName)).append(" : table absente\n");
                    continue;
                }
                String view = "?";
                String modify = "?";
                if (rights != null) {
                    view = yesNo(rights.canView(table));
                    modify = yesNo(rights.canModify(table));
                }
                sb.append("  ").append(pad(tableName)).append(" : lecture ").append(view);
                sb.append(", modification ").append(modify);
                try {
                    sb.append(", ").append(table.getRowCount(false)).append(" ligne(s)");
                } catch (Exception e) {
                    sb.append(", lignes illisibles (").append(e).append(')');
                }
                sb.append('\n');
            }
        }

        // --- contenu du menu deroulant ---------------------------------
        sb.append('\n').append("menu déroulant des affaires :\n");
        appendCombo(sb);

        return sb.toString();
    }

    private static UserRights currentRights(final StringBuilder sb) {
        try {
            final User user = UserManager.getInstance().getCurrentUser();
            if (user == null) {
                sb.append("utilisateur : aucun (session non ouverte)\n");
                return null;
            }
            final String nom = (user.getName() + " " + user.getFirstName()).trim();
            sb.append("utilisateur : ").append(nom.length() == 0 ? "(sans nom)" : nom);
            sb.append(" (ID ").append(user.getId()).append(")\n");
            final UserRights rights = user.getRights();
            sb.append("superutilisateur : ").append(rights == null ? "?" : yesNo(rights.isSuperUser())).append('\n');
            return rights;
        } catch (Throwable t) {
            sb.append("utilisateur : illisible (").append(t).append(")\n");
            return null;
        }
    }

    private static void appendCombo(final StringBuilder sb) {
        try {
            final SQLElement elem = Configuration.getInstance().getDirectory().getElement("AFFAIRE");
            if (elem == null) {
                sb.append("  élément AFFAIRE introuvable\n");
                return;
            }
            final ComboSQLRequest req = elem.getComboRequest(true);
            final List<IComboSelectionItem> items = req.getComboItems();
            final int total = items == null ? 0 : items.size();
            sb.append("  entrées proposées : ").append(total).append('\n');
            if (total == 0) {
                sb.append("  => le menu déroulant est VIDE : c'est la cause du champ grisé\n");
                return;
            }
            final List<String> vides = new ArrayList<String>();
            int sansTexte = 0;
            for (final IComboSelectionItem item : items) {
                final String label = item == null ? null : item.getLabel();
                if (label == null || label.trim().length() == 0) {
                    sansTexte++;
                    if (vides.size() < 5) {
                        vides.add(String.valueOf(item == null ? -1 : item.getId()));
                    }
                }
            }
            sb.append("  entrées sans texte : ").append(sansTexte);
            if (sansTexte > 0) {
                sb.append(" (ID ").append(join(vides)).append(") — elles s'affichent comme des lignes vides");
            }
            sb.append('\n');
            sb.append("  trois premières entrées : ");
            final List<String> trois = new ArrayList<String>();
            for (int i = 0; i < total && i < 3; i++) {
                final IComboSelectionItem item = items.get(i);
                trois.add(item == null ? "?" : item.getLabel());
            }
            sb.append(join(trois)).append('\n');
        } catch (Throwable t) {
            sb.append("  lecture impossible (").append(t).append(")\n");
        }
    }

    private static String join(final List<String> values) {
        final StringBuilder sb = new StringBuilder();
        for (final String v : values) {
            if (sb.length() > 0) {
                sb.append(", ");
            }
            sb.append(v);
        }
        return sb.toString();
    }

    private static String pad(final String text) {
        final StringBuilder sb = new StringBuilder(text);
        while (sb.length() < 22) {
            sb.append(' ');
        }
        return sb.toString();
    }

    private static String yesNo(final boolean value) {
        return value ? "oui" : "NON";
    }

    /**
     * Lance le diagnostic dans un fil de fond puis affiche le rapport.
     * <p>
     * Aucune exception ne remonte : un diagnostic ne doit jamais gêner le
     * travail en cours.
     */
    public static void run(final DBRoot root) {
        final Thread t = new Thread(new Runnable() {
            @Override
            public void run() {
                final String report;
                try {
                    report = buildReport(root);
                } catch (Throwable e) {
                    Module.log("diagnostic affaire : impossible (" + e + ")");
                    return;
                }
                Module.log("diagnostic affaire\n" + report);
                SwingUtilities.invokeLater(new Runnable() {
                    @Override
                    public void run() {
                        try {
                            final JTextArea area = new JTextArea(report, 18, 72);
                            area.setEditable(false);
                            area.setLineWrap(false);
                            JOptionPane.showMessageDialog(null, new JScrollPane(area), "Diagnostic affaire (lecture seule)", JOptionPane.INFORMATION_MESSAGE);
                        } catch (Throwable e) {
                            Module.log("diagnostic affaire : affichage impossible (" + e + ")");
                        }
                    }
                });
            }
        }, "project-affair-diagnostic");
        t.setDaemon(true);
        t.start();
    }
}
