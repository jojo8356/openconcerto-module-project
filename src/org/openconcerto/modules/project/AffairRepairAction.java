/*
 * « Aide > Reprendre les affaires des documents ».
 *
 * Repare les documents crees <b>avant</b> le correctif de transfert : la
 * commande fournisseur etait rattachee a une affaire, la facture ne l'etait
 * pas. La reprise relit le lien qui existe deja en base (table de transfert
 * {@code TR_*}, ou {@code SAISIE_ACHAT.SOURCE / IDSOURCE}) et remplit
 * uniquement les affaires vides.
 *
 * L'action est en deux temps, jamais silencieuse :
 * <ol>
 * <li><b>diagnostic</b> : combien de documents seraient rattaches, type par
 * type, sans rien ecrire (fil de fond) ;</li>
 * <li><b>confirmation</b> explicite de l'utilisateur (interface) ;</li>
 * <li><b>reprise</b> puis compte rendu du nombre de lignes reellement mises a
 * jour (fil de fond).</li>
 * </ol>
 *
 * Aucune affaire deja renseignee n'est modifiee : les requetes ne touchent que
 * {@code ID_AFFAIRE NULL} ou {@code = 1} (affaire « Indefini »). L'operation
 * est donc rejouable sans risque.
 */
package org.openconcerto.modules.project;

import java.awt.event.ActionEvent;
import java.util.ArrayList;
import java.util.List;

import javax.swing.AbstractAction;
import javax.swing.JOptionPane;
import javax.swing.SwingWorker;

import org.openconcerto.sql.model.DBRoot;

public final class AffairRepairAction extends AbstractAction {

    private static final long serialVersionUID = 1L;

    private final DBRoot root;

    public AffairRepairAction(final DBRoot root) {
        super("Reprendre les affaires des documents");
        this.root = root;
        putValue(SHORT_DESCRIPTION, "Rattache a leur affaire d'origine les factures, achats et lignes crees par transfert");
    }

    @Override
    public void actionPerformed(final ActionEvent e) {
        final DBRoot dbRoot = this.root != null ? this.root : Module.affairRootForMenu();
        if (dbRoot == null) {
            JOptionPane.showMessageDialog(null, "Aucune base ouverte : impossible de reprendre les affaires.", "Reprise des affaires", JOptionPane.WARNING_MESSAGE);
            return;
        }
        final List<AffairBackfillSupport.Repair> plan;
        try {
            plan = plan(dbRoot);
        } catch (Exception ex) {
            JOptionPane.showMessageDialog(null, "Reprise impossible : " + ex.getMessage(), "Reprise des affaires", JOptionPane.ERROR_MESSAGE);
            return;
        }
        if (plan.isEmpty()) {
            JOptionPane.showMessageDialog(null, "Aucun document transfere n'est relie a un document source : rien a reprendre.",
                    "Reprise des affaires", JOptionPane.INFORMATION_MESSAGE);
            return;
        }

        // 1. Diagnostic (aucune ecriture), hors de l'EDT.
        new SwingWorker<String, Void>() {

            @Override
            protected String doInBackground() {
                final StringBuilder detail = new StringBuilder();
                long total = 0;
                for (final AffairBackfillSupport.Repair repair : plan) {
                    final long count = count(dbRoot, repair);
                    if (count > 0) {
                        detail.append("  - ").append(repair.getDescription()).append(" : ").append(count).append('\n');
                        total += count;
                    }
                }
                return total + "\n" + detail;
            }

            @Override
            protected void done() {
                final String result;
                try {
                    result = get();
                } catch (Exception ex) {
                    JOptionPane.showMessageDialog(null, "Diagnostic impossible : " + ex.getMessage(), "Reprise des affaires", JOptionPane.ERROR_MESSAGE);
                    return;
                }
                final int newline = result.indexOf('\n');
                final long total = Long.parseLong(result.substring(0, newline));
                final String detail = result.substring(newline + 1);
                if (total == 0) {
                    JOptionPane.showMessageDialog(null, "Tous les documents transferes ont deja leur affaire : rien a reprendre.",
                            "Reprise des affaires", JOptionPane.INFORMATION_MESSAGE);
                    return;
                }
                final int answer = JOptionPane.showConfirmDialog(null,
                        total + " document(s) ou ligne(s) sans affaire peuvent etre rattaches a leur affaire d'origine :\n\n" + detail
                                + "\nAucune affaire deja renseignee ne sera modifiee.\nReprendre maintenant ?",
                        "Reprise des affaires", JOptionPane.OK_CANCEL_OPTION, JOptionPane.QUESTION_MESSAGE);
                if (answer == JOptionPane.OK_OPTION) {
                    apply(dbRoot, plan);
                }
            }
        }.execute();
    }

    /** 2. Reprise proprement dite, hors de l'EDT. */
    private static void apply(final DBRoot dbRoot, final List<AffairBackfillSupport.Repair> plan) {
        new SwingWorker<String, Void>() {

            @Override
            protected String doInBackground() {
                long updated = 0;
                final StringBuilder detail = new StringBuilder();
                final List<String> errors = new ArrayList<String>();
                for (final AffairBackfillSupport.Repair repair : plan) {
                    try {
                        final long before = count(dbRoot, repair);
                        if (before == 0) {
                            continue;
                        }
                        dbRoot.getDBSystemRoot().getDataSource().execute(repair.getUpdateSql());
                        final long after = count(dbRoot, repair);
                        final long done = before - after;
                        updated += done;
                        if (done > 0) {
                            detail.append("  - ").append(repair.getDescription()).append(" : ").append(done).append('\n');
                        }
                    } catch (Exception ex) {
                        errors.add(repair.getDescription() + " (" + ex.getMessage() + ")");
                    }
                }
                final StringBuilder report = new StringBuilder();
                report.append(updated).append(" ligne(s) rattachee(s) a leur affaire.\n");
                if (updated > 0) {
                    report.append('\n').append(detail);
                    report.append("\nFermer puis rouvrir la fenetre des documents pour voir la colonne « Affaire ».\n");
                }
                if (!errors.isEmpty()) {
                    report.append("\nNon traite :\n");
                    for (final String error : errors) {
                        report.append("  - ").append(error).append('\n');
                    }
                }
                return report.toString();
            }

            @Override
            protected void done() {
                try {
                    final String message = get();
                    JOptionPane.showMessageDialog(null, message, "Reprise des affaires", JOptionPane.INFORMATION_MESSAGE);
                    Module.log("reprise des affaires : " + message.replace('\n', ' '));
                } catch (Exception ex) {
                    Module.log("reprise des affaires impossible : " + ex);
                    JOptionPane.showMessageDialog(null, "La reprise a echoue : " + ex.getMessage(), "Reprise des affaires", JOptionPane.ERROR_MESSAGE);
                }
            }
        }.execute();
    }

    /** Plan de reprise adapte a la base ouverte. */
    static List<AffairBackfillSupport.Repair> plan(final DBRoot root) {
        final AffairLinkSupport.Schema schema = Module.schemaOf(root);
        final AffairBackfillSupport.Quoter quoter = new AffairBackfillSupport.Quoter() {
            @Override
            public String table(final String tableName) {
                return root.getTable(tableName).getSQLName().quote();
            }

            @Override
            public String column(final String columnName) {
                return "\"" + columnName + "\"";
            }
        };
        return AffairBackfillSupport.plan(schema, quoter);
    }

    /** Nombre de lignes que cette reprise changerait. */
    static long count(final DBRoot root, final AffairBackfillSupport.Repair repair) {
        try {
            final Object value = root.getDBSystemRoot().getDataSource().executeScalar(repair.getCountSql());
            return value instanceof Number ? ((Number) value).longValue() : 0;
        } catch (Exception e) {
            Module.log("comptage impossible (" + repair.getDescription() + ") : " + e);
            return 0;
        }
    }
}
