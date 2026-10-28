package org.openconcerto.modules.project;

import java.awt.BorderLayout;
import java.awt.Dimension;
import java.awt.FlowLayout;
import java.awt.GridBagConstraints;
import java.awt.GridBagLayout;
import java.awt.event.ActionEvent;
import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import javax.swing.AbstractAction;
import javax.swing.BorderFactory;
import javax.swing.JButton;
import javax.swing.JComboBox;
import javax.swing.JFileChooser;
import javax.swing.JFrame;
import javax.swing.JLabel;
import javax.swing.JOptionPane;
import javax.swing.JPanel;
import javax.swing.JScrollPane;
import javax.swing.JTable;
import javax.swing.JTextField;
import javax.swing.RowFilter;
import javax.swing.SwingUtilities;
import javax.swing.table.TableRowSorter;
import javax.swing.event.DocumentEvent;
import javax.swing.event.DocumentListener;
import javax.swing.table.AbstractTableModel;

import org.openconcerto.sql.model.DBRoot;
import org.openconcerto.sql.model.SQLField;
import org.openconcerto.sql.model.SQLTable;

/**
 * Menu <b>Paramètres &gt; Libellés des colonnes</b>.
 *
 * <p>
 * Ouvert uniquement a l'utilisateur qui a le plus de droits dans la base (voir
 * {@link ColumnLabelAccess}) : le choix qu'il fait s'applique a <b>toute
 * l'equipe</b>, parce qu'il est enregistre dans les tables du module sur le
 * serveur SQL ({@code PROJECT_COLUMN_LABEL}), pas sur son poste.
 *
 * <p>
 * Le cas d'usage a l'origine de l'ecran : une utilisatrice ne veut plus voir
 * {@code ID_CLIENT} ou {@code ID_FACTURE_FOURNISSEUR} dans les listes mais
 * {@code CLIENT} et {@code FACTURE FOURNISSEUR}. Le mode {@code AUTO} le fait
 * deja tout seul (suppression du prefixe {@code ID_}) ; l'ecran permet de
 * corriger un libelle precis, de choisir un libelle pour une colonne dans
 * <b>toutes</b> les tables ({@code *}), et de revenir en arriere.
 *
 * <p>
 * L'ecran ne modifie jamais le jar en place : l'action « Exporter pour le jar »
 * ecrit un fichier {@code column-labels.properties} a poser dans
 * {@code src/org/openconcerto/modules/project/} avant de reconstruire le jar,
 * pour que les nouveaux postes partent avec ces libelles.
 */
public final class ColumnLabelSettingsAction extends AbstractAction {

    private static final long serialVersionUID = 1L;

    private final DBRoot root;

    public ColumnLabelSettingsAction(final DBRoot root) {
        super("Libellés des colonnes");
        this.root = root;
        putValue(SHORT_DESCRIPTION, "Choix des noms de colonnes affiches dans les listes, pour toute l'equipe");
    }

    @Override
    public void actionPerformed(final ActionEvent event) {
        if (!ColumnLabelAccess.canEdit(this.root)) {
            JOptionPane.showMessageDialog(null, "Cet ecran est reserve a l'utilisateur qui a le plus de droits dans la base.\n" + ColumnLabelAccess.explain(this.root), "Parametres des colonnes",
                    JOptionPane.WARNING_MESSAGE);
            return;
        }
        final JFrame frame = new JFrame("Libellés des colonnes — pour toute l'équipe");
        frame.setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
        frame.setContentPane(new SettingsPanel(this.root, frame));
        frame.pack();
        frame.setLocationRelativeTo(null);
        frame.setVisible(true);
    }

    // ------------------------------------------------------------------
    // Panneau
    // ------------------------------------------------------------------

    private static final class SettingsPanel extends JPanel {

        private static final long serialVersionUID = 1L;

        private final DBRoot root;
        private final JFrame frame;
        private final EntryTableModel model;
        private final JTable table;
        private final TableRowSorter<EntryTableModel> sorter;
        private final JTextField filter = new JTextField();
        private final JComboBox modeBox = new JComboBox(new String[] { ColumnLabelRules.MODE_AUTO, ColumnLabelRules.MODE_MAPPING, ColumnLabelRules.MODE_OFF });

        SettingsPanel(final DBRoot root, final JFrame frame) {
            super(new BorderLayout(8, 8));
            this.root = root;
            this.frame = frame;
            this.model = new EntryTableModel(buildEntries(root));
            this.table = new JTable(this.model);
            this.sorter = new TableRowSorter<EntryTableModel>(this.model);
            this.table.setRowSorter(this.sorter);
            this.table.getColumnModel().getColumn(0).setPreferredWidth(160);
            this.table.getColumnModel().getColumn(1).setPreferredWidth(200);
            this.table.getColumnModel().getColumn(2).setPreferredWidth(200);
            this.table.getColumnModel().getColumn(3).setPreferredWidth(220);
            this.table.setRowHeight(22);

            setBorder(BorderFactory.createEmptyBorder(8, 8, 8, 8));
            add(buildHeader(), BorderLayout.NORTH);
            add(new JScrollPane(this.table), BorderLayout.CENTER);
            add(buildButtons(), BorderLayout.SOUTH);
            this.modeBox.setSelectedItem(ColumnLabelStore.getMode());
        }

        private JPanel buildHeader() {
            final JPanel header = new JPanel(new GridBagLayout());
            final GridBagConstraints c = new GridBagConstraints();
            c.gridx = 0;
            c.gridy = 0;
            c.anchor = GridBagConstraints.WEST;
            c.insets = new java.awt.Insets(0, 0, 4, 6);

            final JLabel intro = new JLabel("<html><b>Ces libelles s'appliquent a toute l'equipe.</b> Ils sont enregistres sur le serveur SQL, "
                    + "pas sur ce poste.<br>Laissez la colonne « Libellé » vide pour garder la regle automatique (suppression du prefixe <i>ID_</i>).</html>");
            c.gridwidth = GridBagConstraints.REMAINDER;
            header.add(intro, c);

            c.gridwidth = 1;
            c.gridy = 1;
            header.add(new JLabel("Utilisateur : " + ColumnLabelAccess.currentUserName() + " (" + ColumnLabelAccess.getLastReason() + ")"), c);
            c.gridy = 2;
            header.add(new JLabel("Mode :"), c);
            c.gridx = 1;
            this.modeBox.setToolTipText("AUTO : supprime ID_ partout et applique les regles saisies. MAPPING : uniquement les regles saisies. OFF : aucun changement.");
            header.add(this.modeBox, c);

            c.gridx = 2;
            header.add(new JLabel("Filtrer :"), c);
            c.gridx = 3;
            c.weightx = 1;
            c.fill = GridBagConstraints.HORIZONTAL;
            this.filter.setPreferredSize(new Dimension(200, 22));
            this.filter.getDocument().addDocumentListener(new DocumentListener() {
                @Override
                public void insertUpdate(final DocumentEvent e) {
                    applyFilter();
                }

                @Override
                public void removeUpdate(final DocumentEvent e) {
                    applyFilter();
                }

                @Override
                public void changedUpdate(final DocumentEvent e) {
                    applyFilter();
                }
            });
            header.add(this.filter, c);
            return header;
        }

        private void applyFilter() {
            final String text = this.filter.getText() == null ? "" : this.filter.getText().trim();
            if (text.length() == 0) {
                this.sorter.setRowFilter(null);
                return;
            }
            // Filtre simple sur les quatre colonnes affichees.
            this.sorter.setRowFilter(RowFilter.regexFilter("(?i)" + java.util.regex.Pattern.quote(text)));
        }

        private JPanel buildButtons() {
            final JPanel buttons = new JPanel(new FlowLayout(FlowLayout.RIGHT));
            final JButton save = new JButton("Enregistrer pour l'équipe");
            save.addActionListener(new AbstractAction() {
                private static final long serialVersionUID = 1L;

                @Override
                public void actionPerformed(final ActionEvent e) {
                    saveToDatabase();
                }
            });
            final JButton add = new JButton("Ajouter une colonne…");
            add.addActionListener(new AbstractAction() {
                private static final long serialVersionUID = 1L;

                @Override
                public void actionPerformed(final ActionEvent e) {
                    addRule();
                }
            });
            final JButton remove = new JButton("Supprimer la règle");
            remove.addActionListener(new AbstractAction() {
                private static final long serialVersionUID = 1L;

                @Override
                public void actionPerformed(final ActionEvent e) {
                    final int row = SettingsPanel.this.table.getSelectedRow();
                    if (row >= 0) {
                        SettingsPanel.this.model.remove(SettingsPanel.this.table.convertRowIndexToModel(row));
                    }
                }
            });
            final JButton export = new JButton("Exporter pour le jar…");
            export.addActionListener(new AbstractAction() {
                private static final long serialVersionUID = 1L;

                @Override
                public void actionPerformed(final ActionEvent e) {
                    exportForJar();
                }
            });
            final JButton close = new JButton("Fermer");
            close.addActionListener(new AbstractAction() {
                private static final long serialVersionUID = 1L;

                @Override
                public void actionPerformed(final ActionEvent e) {
                    SettingsPanel.this.frame.dispose();
                }
            });
            buttons.add(add);
            buttons.add(remove);
            buttons.add(export);
            buttons.add(close);
            buttons.add(save);
            return buttons;
        }

        private void saveToDatabase() {
            final Map<String, String> labels = new LinkedHashMap<String, String>();
            for (final Entry entry : this.model.getEntries()) {
                final String label = ColumnLabelRules.cleanLabel(entry.label);
                if (label.length() == 0) {
                    continue;
                }
                if (!ColumnLabelRules.isValidLabel(label)) {
                    JOptionPane.showMessageDialog(this, "Le libelle de « " + entry.key() + " » est invalide (vide, trop long, ou avec un caractere de controle).", "Libellés", JOptionPane.WARNING_MESSAGE);
                    return;
                }
                labels.put(entry.key(), label);
            }
            final String mode = String.valueOf(this.modeBox.getSelectedItem());
            final List<String> problems = ColumnLabelStore.save(this.root, labels, mode, Math.max(0, ColumnLabelAccess.currentUserId()));
            if (!problems.isEmpty()) {
                final StringBuilder sb = new StringBuilder("Enregistrement impossible :\n");
                for (final String problem : problems) {
                    sb.append("  - ").append(problem).append('\n');
                }
                JOptionPane.showMessageDialog(this, sb.toString(), "Libellés", JOptionPane.ERROR_MESSAGE);
                return;
            }
            final int changed = ColumnLabelUi.refreshAll();
            JOptionPane.showMessageDialog(this, "Libellés enregistrés pour toute l'équipe (" + labels.size() + " regle(s), mode " + mode + ").\n"
                    + changed + " colonne(s) mise(s) a jour sur ce poste.\n\nLes autres postes les verront au prochain demarrage du client.", "Libellés", JOptionPane.INFORMATION_MESSAGE);
        }

        private void addRule() {
            final String table = JOptionPane.showInputDialog(this, "Table (ou * pour toutes les tables) :", "Ajouter une règle", JOptionPane.QUESTION_MESSAGE);
            if (table == null || table.trim().length() == 0) {
                return;
            }
            final String tableName = table.trim().toUpperCase();
            if (!ColumnLabelRules.ANY_TABLE.equals(tableName) && !ColumnLabelRules.isValidName(tableName)) {
                JOptionPane.showMessageDialog(this, "Nom de table invalide.", "Libellés", JOptionPane.WARNING_MESSAGE);
                return;
            }
            final String column = JOptionPane.showInputDialog(this, "Colonne (nom technique, ex. ID_CLIENT) :", "Ajouter une règle", JOptionPane.QUESTION_MESSAGE);
            if (column == null || column.trim().length() == 0) {
                return;
            }
            final String columnName = column.trim().toUpperCase();
            if (!ColumnLabelRules.isValidName(columnName)) {
                JOptionPane.showMessageDialog(this, "Nom de colonne invalide.", "Libellés", JOptionPane.WARNING_MESSAGE);
                return;
            }
            final String suggested = ColumnLabelRules.suggestLabel(columnName);
            final String label = JOptionPane.showInputDialog(this, "Libellé a afficher :", suggested);
            if (label == null) {
                return;
            }
            this.model.addOrUpdate(tableName, columnName, ColumnLabelRules.cleanLabel(label));
        }

        private void exportForJar() {
            final JFileChooser chooser = new JFileChooser();
            chooser.setSelectedFile(new File("column-labels.properties"));
            if (chooser.showSaveDialog(this) != JFileChooser.APPROVE_OPTION) {
                return;
            }
            final Map<String, String> labels = new LinkedHashMap<String, String>();
            for (final Entry entry : this.model.getEntries()) {
                final String label = ColumnLabelRules.cleanLabel(entry.label);
                if (label.length() > 0) {
                    labels.put(entry.key(), label);
                }
            }
            try {
                final File file = chooser.getSelectedFile();
                final Writer writer = new OutputStreamWriter(new FileOutputStream(file), "UTF-8");
                try {
                    writer.write(ColumnLabelRules.toProperties(labels, String.valueOf(this.modeBox.getSelectedItem())));
                } finally {
                    writer.close();
                }
                JOptionPane.showMessageDialog(this, "Fichier ecrit :\n" + file.getAbsolutePath()
                        + "\n\nPour l'integrer au jar : copier ce fichier dans\nsrc/org/openconcerto/modules/project/column-labels.properties\npuis reconstruire le jar.",
                        "Libellés", JOptionPane.INFORMATION_MESSAGE);
            } catch (Exception e) {
                JOptionPane.showMessageDialog(this, "Ecriture impossible : " + e, "Libellés", JOptionPane.ERROR_MESSAGE);
            }
        }
    }

    // ------------------------------------------------------------------
    // Donnees de l'ecran
    // ------------------------------------------------------------------

    /** Une ligne de l'ecran : une colonne d'une table et son libelle. */
    static final class Entry {
        final String table;
        final String column;
        String label;

        Entry(final String table, final String column, final String label) {
            this.table = table;
            this.column = column;
            this.label = label == null ? "" : label;
        }

        String key() {
            return ColumnLabelRules.key(this.table, this.column);
        }

        String preview() {
            final String cleaned = ColumnLabelRules.cleanLabel(this.label);
            if (cleaned.length() > 0) {
                return cleaned;
            }
            return ColumnLabelRules.suggestLabel(this.column);
        }
    }

    /**
     * Construit les lignes de l'ecran : toutes les colonnes techniques
     * ({@code ID_...}) des tables de la base, plus les regles deja enregistrees
     * (meme si leur colonne n'existe plus).
     */
    static List<Entry> buildEntries(final DBRoot root) {
        final Map<String, Entry> byKey = new LinkedHashMap<String, Entry>();
        final Map<String, String> existing = ColumnLabelStore.getLabels();
        if (root != null) {
            try {
                final Set<SQLTable> tables = new LinkedHashSet<SQLTable>(root.getTables());
                for (final SQLTable sqlTable : tables) {
                    if (sqlTable == null || sqlTable.getName() == null) {
                        continue;
                    }
                    for (final SQLField field : sqlTable.getFields()) {
                        if (field == null || field.getName() == null) {
                            continue;
                        }
                        if (!ColumnLabelRules.isIdColumn(field.getName())) {
                            continue;
                        }
                        final String key = ColumnLabelRules.key(sqlTable.getName(), field.getName());
                        byKey.put(key, new Entry(sqlTable.getName(), field.getName(), existing.get(key)));
                    }
                }
            } catch (Exception e) {
                Module.log("liste des colonnes impossible : " + e);
            }
        }
        for (final Map.Entry<String, String> rule : existing.entrySet()) {
            if (!byKey.containsKey(rule.getKey())) {
                final int dot = rule.getKey().indexOf('.');
                if (dot > 0) {
                    byKey.put(rule.getKey(), new Entry(rule.getKey().substring(0, dot), rule.getKey().substring(dot + 1), rule.getValue()));
                }
            }
        }
        return new ArrayList<Entry>(byKey.values());
    }

    /** Modele de tableau editable, sans dependance a la base. */
    static final class EntryTableModel extends AbstractTableModel {

        private static final long serialVersionUID = 1L;
        private static final String[] COLUMNS = { "Table", "Colonne", "Aperçu", "Libellé affiché" };

        private final List<Entry> entries;

        EntryTableModel(final List<Entry> entries) {
            this.entries = entries;
        }

        List<Entry> getEntries() {
            return this.entries;
        }

        void addOrUpdate(final String table, final String column, final String label) {
            final String key = ColumnLabelRules.key(table, column);
            for (int i = 0; i < this.entries.size(); i++) {
                if (this.entries.get(i).key().equals(key)) {
                    this.entries.get(i).label = label;
                    fireTableRowsUpdated(i, i);
                    return;
                }
            }
            this.entries.add(new Entry(table.toUpperCase(), column.toUpperCase(), label));
            fireTableRowsInserted(this.entries.size() - 1, this.entries.size() - 1);
        }

        void remove(final int row) {
            if (row >= 0 && row < this.entries.size()) {
                this.entries.remove(row);
                fireTableRowsDeleted(row, row);
            }
        }

        @Override
        public int getRowCount() {
            return this.entries.size();
        }

        @Override
        public int getColumnCount() {
            return COLUMNS.length;
        }

        @Override
        public String getColumnName(final int column) {
            return COLUMNS[column];
        }

        @Override
        public Class<?> getColumnClass(final int column) {
            return String.class;
        }

        @Override
        public boolean isCellEditable(final int row, final int column) {
            return column == 3;
        }

        @Override
        public Object getValueAt(final int row, final int column) {
            final Entry entry = this.entries.get(row);
            switch (column) {
                case 0:
                    return entry.table;
                case 1:
                    return entry.column;
                case 2:
                    return entry.preview();
                default:
                    return entry.label;
            }
        }

        @Override
        public void setValueAt(final Object value, final int row, final int column) {
            if (column != 3) {
                return;
            }
            this.entries.get(row).label = value == null ? "" : String.valueOf(value);
            fireTableRowsUpdated(row, row);
        }
    }

    /** Rafraichit l'affichage des listes ouvertes (utilise par les tests). */
    static void refreshOpenLists() {
        SwingUtilities.invokeLater(new Runnable() {
            @Override
            public void run() {
                ColumnLabelUi.refreshAll();
            }
        });
    }
}
