package org.openconcerto.modules.project;

import java.awt.BorderLayout;
import java.awt.Color;
import java.awt.Component;
import java.awt.Dimension;
import java.awt.Font;
import java.awt.FlowLayout;
import java.awt.GridBagConstraints;
import java.awt.GridBagLayout;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
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
import javax.swing.DefaultCellEditor;
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
import javax.swing.table.DefaultTableCellRenderer;

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
        /** Sur quelle colonne porte le filtre : -1 = toutes. */
        private final JComboBox filterColumn = new JComboBox(ColumnLabelRules.FILTER_CHOICES.toArray());
        private final JComboBox modeBox = new JComboBox(new String[] { ColumnLabelRules.MODE_AUTO, ColumnLabelRules.MODE_MAPPING, ColumnLabelRules.MODE_OFF });

        SettingsPanel(final DBRoot root, final JFrame frame) {
            super(new BorderLayout(8, 8));
            this.root = root;
            this.frame = frame;
            this.model = new EntryTableModel(buildEntries(root));
            this.table = new JTable(this.model);
            this.sorter = new TableRowSorter<EntryTableModel>(this.model);
            this.table.setRowSorter(this.sorter);
            this.table.getColumnModel().getColumn(0).setPreferredWidth(150);
            this.table.getColumnModel().getColumn(1).setPreferredWidth(190);
            this.table.getColumnModel().getColumn(2).setPreferredWidth(190);
            this.table.getColumnModel().getColumn(3).setPreferredWidth(240);
            this.table.setRowHeight(22);
            this.table.setSelectionMode(javax.swing.ListSelectionModel.MULTIPLE_INTERVAL_SELECTION);
            this.table.setForeground(Color.BLACK);
            this.table.setGridColor(new Color(0xC8, 0xC8, 0xC8));
            // Double-clic (ou F2, ou une simple frappe) pour modifier le libelle.
            // Le rendu specifique ne s'applique qu'a la colonne editable : les
            // autres colonnes gardent le rendu standard (texte noir).
            this.table.getColumnModel().getColumn(3).setCellRenderer(new LabelRenderer());
            this.table.getColumnModel().getColumn(3).setCellEditor(new LabelEditor());
            this.table.getTableHeader().setForeground(Color.BLACK);
            this.table.getTableHeader().setFont(this.table.getTableHeader().getFont() == null ? null : this.table.getTableHeader().getFont().deriveFont(Font.BOLD));
            this.table.getTableHeader().setToolTipText("Libellé affiché : double-cliquez sur une case pour le modifier, videz-la pour revenir au libellé automatique.");

            setBorder(BorderFactory.createEmptyBorder(8, 8, 8, 8));
            add(buildHeader(), BorderLayout.NORTH);
            final JPanel center = new JPanel(new BorderLayout(0, 4));
            center.add(new JScrollPane(this.table), BorderLayout.CENTER);
            final JLabel hint = new JLabel("<html>Double-cliquez sur un libellé pour le modifier. "
                    + ColumnLabelStyle.describe() + ".</html>");
            hint.setForeground(Color.BLACK);
            center.add(hint, BorderLayout.SOUTH);
            add(center, BorderLayout.CENTER);
            add(buildButtons(), BorderLayout.SOUTH);
            this.modeBox.setSelectedItem(ColumnLabelStore.getMode());
            this.model.setMode(ColumnLabelStore.getMode());
            this.modeBox.addActionListener(new ActionListener() {
                @Override
                public void actionPerformed(final ActionEvent e) {
                    // La colonne « Libellé affiché » montre ce que voit
                    // l'utilisateur : elle doit suivre le mode choisi.
                    SettingsPanel.this.model.setMode(String.valueOf(SettingsPanel.this.modeBox.getSelectedItem()));
                }
            });
        }

        private JPanel buildHeader() {
            final JPanel header = new JPanel(new GridBagLayout());
            final GridBagConstraints c = new GridBagConstraints();
            c.gridx = 0;
            c.gridy = 0;
            c.anchor = GridBagConstraints.WEST;
            c.insets = new java.awt.Insets(0, 0, 4, 6);

            final JLabel intro = new JLabel("<html><b>Ces libelles s'appliquent a toute l'equipe.</b> Ils sont enregistres sur le serveur SQL, "
                    + "pas sur ce poste.<br>La colonne <b>Libellé affiché</b> montre ce que voient les utilisateurs : "
                    + "<b>double-cliquez</b> sur une case pour le modifier en direct. "
                    + "Une case vide (ou le bouton <i>Réinitialiser</i>) remet le libelle automatique (suppression du prefixe <i>ID_</i>).</html>");
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
            c.weightx = 0;
            c.fill = GridBagConstraints.NONE;
            // Choix de la colonne filtree : taper « fournisseur » dans « Colonne »
            // va beaucoup plus vite que de parcourir 300 lignes.
            this.filterColumn.setToolTipText("<html>Colonne sur laquelle porte le filtre.<br>"
                    + "« Colonne » cherche dans les noms techniques (ID_FOURNISSEUR),<br>"
                    + "« Libellé affiché » dans ce que voient les utilisateurs.</html>");
            this.filterColumn.addActionListener(new ActionListener() {
                @Override
                public void actionPerformed(final ActionEvent e) {
                    applyFilter();
                }
            });
            header.add(this.filterColumn, c);
            c.gridx = 4;
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

        /** Indice de colonne du modele correspondant au choix du sélecteur. */
        private int filterColumnIndex() {
            return ColumnLabelRules.filterColumnIndex(this.filterColumn.getSelectedIndex());
        }

        private void applyFilter() {
            final String text = this.filter.getText() == null ? "" : this.filter.getText().trim();
            if (text.length() == 0) {
                this.sorter.setRowFilter(null);
                return;
            }
            final String pattern = "(?i)" + java.util.regex.Pattern.quote(text);
            final int index = filterColumnIndex();
            // Filtre sur la colonne choisie, ou sur les quatre si « Toutes ».
            this.sorter.setRowFilter(index < 0 ? RowFilter.regexFilter(pattern) : RowFilter.regexFilter(pattern, index));
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
            final JButton reset = new JButton("Réinitialiser (libellé auto)");
            reset.setToolTipText("Efface la règle des lignes sélectionnées : le libellé automatique revient (suppression du préfixe ID_).");
            reset.addActionListener(new AbstractAction() {
                private static final long serialVersionUID = 1L;

                @Override
                public void actionPerformed(final ActionEvent e) {
                    final int[] rows = SettingsPanel.this.table.getSelectedRows();
                    if (rows.length == 0) {
                        JOptionPane.showMessageDialog(SettingsPanel.this, "Sélectionnez d'abord une ou plusieurs lignes.", "Libellés", JOptionPane.INFORMATION_MESSAGE);
                        return;
                    }
                    // De la fin vers le debut : les indices restent valides quand
                    // une ligne est retiree.
                    for (int i = rows.length - 1; i >= 0; i--) {
                        SettingsPanel.this.model.reset(SettingsPanel.this.table.convertRowIndexToModel(rows[i]));
                    }
                }
            });
            final JButton everywhere = new JButton("Appliquer à toutes les tables (*)");
            everywhere.setToolTipText("<html>Crée une règle <b>*</b> pour la colonne des lignes sélectionnées : le libellé s'appliquera<br>"
                    + "dans toutes les tables qui n'ont pas leur propre règle.<br>Utile pour ID_FOURNISSEUR, ID_CLIENT, ID_AFFAIRE…</html>");
            everywhere.addActionListener(new AbstractAction() {
                private static final long serialVersionUID = 1L;

                @Override
                public void actionPerformed(final ActionEvent e) {
                    applyToAllTables();
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
                    confirmClose();
                }
            });
            buttons.add(add);
            buttons.add(reset);
            buttons.add(everywhere);
            buttons.add(export);
            buttons.add(close);
            buttons.add(save);
            return buttons;
        }

        /**
         * Fermeture de la fenetre : propose d'enregistrer les libelles modifies
         * dans le tableau, puisque le tableau sert maintenant a saisir.
         */
        private void confirmClose() {
            if (this.model.isDirty()) {
                final int answer = JOptionPane.showConfirmDialog(this,
                        "Des libellés ont été modifiés et ne sont pas encore enregistrés pour l'équipe.\nEnregistrer maintenant ?",
                        "Libellés", JOptionPane.YES_NO_CANCEL_OPTION, JOptionPane.QUESTION_MESSAGE);
                if (answer == JOptionPane.CANCEL_OPTION || answer == JOptionPane.CLOSED_OPTION) {
                    return;
                }
                if (answer == JOptionPane.YES_OPTION) {
                    if (!save()) {
                        return;
                    }
                }
            }
            this.frame.dispose();
        }

        private void saveToDatabase() {
            save();
        }

        /**
         * @return <code>true</code> si l'enregistrement a reussi (ou si rien
         *         n'empechait de fermer).
         */
        private boolean save() {
            final Map<String, String> labels = new LinkedHashMap<String, String>();
            for (final Entry entry : this.model.getEntries()) {
                final String label = ColumnLabelRules.cleanLabel(entry.label);
                if (label.length() == 0) {
                    continue;
                }
                if (!ColumnLabelRules.isValidLabel(label)) {
                    JOptionPane.showMessageDialog(this, "Le libelle de « " + entry.key() + " » est invalide (vide, trop long, ou avec un caractere de controle).", "Libellés", JOptionPane.WARNING_MESSAGE);
                    return false;
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
                return false;
            }
            final int changed = ColumnLabelUi.refreshAll();
            this.model.markSaved();
            this.model.setMode(mode);
            // Tables de sauvegarde parmi les regles enregistrees : ces libelles
            // ne s'afficheront dans aucune liste (cas reel : regle posee sur
            // sauvegarde_FACTURE_FOURNISSEUR_avant... au lieu de la vraie table).
            final List<String> backupTables = ColumnLabelRules.backupTables(tablesOf(labels));
            JOptionPane.showMessageDialog(this, ColumnLabelRules.saveReport(labels.size(), changed, mode, backupTables), "Libellés", JOptionPane.INFORMATION_MESSAGE);
            return true;
        }

        /** Tables concernees par un ensemble de regles (cle = TABLE.COLONNE). */
        private List<String> tablesOf(final Map<String, String> labels) {
            final Set<String> tables = new LinkedHashSet<String>();
            for (final String key : labels.keySet()) {
                final int dot = key.indexOf('.');
                if (dot > 0) {
                    tables.add(key.substring(0, dot));
                }
            }
            return new ArrayList<String>(tables);
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

        /**
         * Cree (ou met a jour) une regle {@code *.COLONNE} avec le libelle de la
         * ligne selectionnee, pour que le renommage s'applique dans <b>toutes</b>
         * les tables : c'est la reponse au cas « je veux FOURNISSEUR partout »
         * sans avoir a editer chaque table une par une.
         */
        private void applyToAllTables() {
            final int row = this.table.getSelectedRow();
            if (row < 0) {
                JOptionPane.showMessageDialog(this, "Sélectionnez d'abord une ligne : sa colonne servira pour toutes les tables.",
                        "Libellés", JOptionPane.INFORMATION_MESSAGE);
                return;
            }
            final Entry entry = this.model.getEntries().get(this.table.convertRowIndexToModel(row));
            final String label = entry.display(this.model.getMode(), this.model.wildcardLabel(entry.column));
            // La ligne de depart n'a plus besoin de regle propre : la regle *
            // couvre deja sa table, et evite deux libelles concurrents.
            if (entry.isCustomized() && !ColumnLabelRules.ANY_TABLE.equals(entry.table)) {
                this.model.reset(this.table.convertRowIndexToModel(row));
            }
            this.model.addOrUpdate(ColumnLabelRules.ANY_TABLE, entry.column, label);
            // Amener la nouvelle ligne sous les yeux : elle est en tete de liste,
            // donc invisible si l'utilisateur a fait defiler.
            showRow(ColumnLabelRules.ANY_TABLE, entry.column);
            JOptionPane.showMessageDialog(this,
                    "Règle générale créée : la colonne " + entry.column + " s'affichera « " + label + " » dans toutes les tables.\n\n"
                            + "Elle apparaît en haut de la liste, ligne * / " + entry.column + " (sélectionnée).\n"
                            + "Cliquez sur « Enregistrer pour l'équipe » pour l'appliquer à tout le monde.",
                    "Libellés", JOptionPane.INFORMATION_MESSAGE);
        }

        /** Selectionne et fait defiler jusqu'a la ligne indiquee. */
        private void showRow(final String table, final String column) {
            final int modelRow = this.model.indexOf(ColumnLabelRules.key(table, column));
            if (modelRow < 0) {
                return;
            }
            final int viewRow = this.table.convertRowIndexToView(modelRow);
            if (viewRow < 0) {
                return;
            }
            this.table.setRowSelectionInterval(viewRow, viewRow);
            this.table.scrollRectToVisible(this.table.getCellRect(viewRow, 0, true));
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
        /** Regle saisie ; vide = libelle automatique. */
        String label;
        /** Vrai si la colonne existe dans la base (sinon : regle orpheline). */
        final boolean fromSchema;

        Entry(final String table, final String column, final String label) {
            this(table, column, label, true);
        }

        Entry(final String table, final String column, final String label, final boolean fromSchema) {
            this.table = table;
            this.column = column;
            this.label = label == null ? "" : label;
            this.fromSchema = fromSchema;
        }

        String key() {
            return ColumnLabelRules.key(this.table, this.column);
        }

        /** Libelle automatique, sans regle : ce que montre la colonne « Automatique ». */
        String automatic() {
            return ColumnLabelRules.suggestLabel(this.column);
        }

        /**
         * Ce que voit reellement l'utilisateur final : la regle si elle existe,
         * sinon le libelle automatique. C'est la valeur editable de l'ecran.
         */
        String display(final String mode) {
            return ColumnLabelRules.displayLabel(this.table, this.column, this.label, mode);
        }

        /** Affichage en tenant compte de la regle generale {@code *.COLONNE}. */
        String display(final String mode, final String wildcard) {
            return ColumnLabelRules.resolvedLabel(this.column, this.label, wildcard, mode);
        }

        /** Vrai si la ligne porte une regle saisie (affichee en gras). */
        boolean isCustomized() {
            return ColumnLabelRules.isExplicitRule(this.label);
        }

        /** Reinitialise la regle : retour au libelle automatique. */
        void reset() {
            this.label = "";
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
                    byKey.put(rule.getKey(), new Entry(rule.getKey().substring(0, dot), rule.getKey().substring(dot + 1), rule.getValue(), false));
                }
            }
        }
        // Ordre lisible : les regles generales (*) d'abord (elles valent partout),
        // puis les tables par ordre alphabetique. Sans cela, la liste suit l'ordre
        // interne de la base, ou les tables de sauvegarde se melangent au metier.
        final List<Entry> entries = new ArrayList<Entry>(byKey.values());
        java.util.Collections.sort(entries, new java.util.Comparator<Entry>() {
            @Override
            public int compare(final Entry a, final Entry b) {
                final boolean wildcardA = ColumnLabelRules.ANY_TABLE.equals(a.table);
                final boolean wildcardB = ColumnLabelRules.ANY_TABLE.equals(b.table);
                if (wildcardA != wildcardB) {
                    return wildcardA ? -1 : 1;
                }
                final int byTable = a.table.compareTo(b.table);
                if (byTable != 0) {
                    return byTable;
                }
                return a.column.compareTo(b.column);
            }
        });
        return entries;
    }

    /** Modele de tableau editable, sans dependance a la base. */
    static final class EntryTableModel extends AbstractTableModel {

        private static final long serialVersionUID = 1L;
        private static final String[] COLUMNS = { "Table", "Colonne", "Automatique", "Libellé affiché (double-clic)" };

        private final List<Entry> entries;
        private String mode = ColumnLabelRules.DEFAULT_MODE;
        /** Vrai des qu'une case a ete modifiee sans enregistrement. */
        private boolean dirty = false;

        /** Regles generales : colonne -> libelle (issues des lignes {@code *}). */
        private final Map<String, String> wildcards = new LinkedHashMap<String, String>();

        EntryTableModel(final List<Entry> entries) {
            this.entries = entries;
            rebuildWildcards();
        }

        /** Recalcule l'index des regles {@code *.COLONNE}. */
        private void rebuildWildcards() {
            this.wildcards.clear();
            for (final Entry entry : this.entries) {
                if (ColumnLabelRules.ANY_TABLE.equals(entry.table)) {
                    final String rule = ColumnLabelRules.cleanLabel(entry.label);
                    if (rule.length() > 0) {
                        this.wildcards.put(entry.column, rule);
                    }
                }
            }
        }

        /** Libelle general pour cette colonne, ou <code>null</code>. */
        String wildcardLabel(final String column) {
            return this.wildcards.get(column);
        }

        List<Entry> getEntries() {
            return this.entries;
        }

        String getMode() {
            return this.mode;
        }

        /** Vrai si des libelles ont ete modifies depuis le dernier enregistrement. */
        boolean isDirty() {
            return this.dirty;
        }

        /** A appeler apres un enregistrement reussi. */
        void markSaved() {
            this.dirty = false;
        }

        /** Change le mode : la colonne « Libellé affiché » doit suivre. */
        void setMode(final String mode) {
            this.mode = mode == null ? ColumnLabelRules.DEFAULT_MODE : mode;
            fireTableDataChanged();
        }

        void addOrUpdate(final String table, final String column, final String label) {
            final String key = ColumnLabelRules.key(table, column);
            for (int i = 0; i < this.entries.size(); i++) {
                if (this.entries.get(i).key().equals(key)) {
                    this.entries.get(i).label = label;
                    this.dirty = true;
                    rebuildWildcards();
                    fireTableRowsUpdated(i, i);
                    return;
                }
            }
            final Entry added = new Entry(table.toUpperCase(), column.toUpperCase(), label, false);
            // Les regles generales (*) passent en tete : ce sont celles qui valent
            // partout, et l'utilisateur doit les voir sans faire defiler.
            if (ColumnLabelRules.ANY_TABLE.equals(added.table)) {
                this.entries.add(0, added);
                this.dirty = true;
                rebuildWildcards();
                fireTableRowsInserted(0, 0);
                return;
            }
            this.entries.add(added);
            this.dirty = true;
            rebuildWildcards();
            fireTableRowsInserted(this.entries.size() - 1, this.entries.size() - 1);
        }

        /** Indice de la ligne correspondant a cette cle, {@code -1} si absente. */
        int indexOf(final String key) {
            for (int i = 0; i < this.entries.size(); i++) {
                if (this.entries.get(i).key().equals(key)) {
                    return i;
                }
            }
            return -1;
        }

        /**
         * Revient au libelle automatique pour cette ligne. Une ligne qui vient
         * d'une regle sans colonne correspondante (table ou colonne supprimee)
         * est retiree : elle n'a plus de sens une fois la regle effacee.
         */
        void reset(final int row) {
            if (row < 0 || row >= this.entries.size()) {
                return;
            }
            final Entry entry = this.entries.get(row);
            if (!entry.fromSchema) {
                this.entries.remove(row);
                this.dirty = true;
                rebuildWildcards();
                fireTableRowsDeleted(row, row);
                return;
            }
            entry.reset();
            this.dirty = true;
            rebuildWildcards();
            fireTableRowsUpdated(row, row);
        }

        void remove(final int row) {
            if (row >= 0 && row < this.entries.size()) {
                this.entries.remove(row);
                this.dirty = true;
                rebuildWildcards();
                fireTableRowsDeleted(row, row);
            }
        }

        /** Nombre de lignes portant une regle saisie. */
        int countCustomized() {
            int count = 0;
            for (final Entry entry : this.entries) {
                if (entry.isCustomized()) {
                    count++;
                }
            }
            return count;
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

        /** Seule la colonne « Libellé affiché » se modifie, directement dans le tableau. */
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
                    return entry.automatic();
                default:
                    return entry.display(this.mode, this.wildcards.get(entry.column));
            }
        }

        /**
         * Enregistre la saisie en direct : le texte devient la regle, une case
         * videe revient au libelle automatique.
         */
        @Override
        public void setValueAt(final Object value, final int row, final int column) {
            if (column != 3 || row < 0 || row >= this.entries.size()) {
                return;
            }
            final Entry entry = this.entries.get(row);
            final String typed = value == null ? "" : String.valueOf(value);
            if (typed.trim().length() > ColumnLabelRules.MAX_LABEL_LENGTH) {
                JOptionPane.showMessageDialog(null, "Libelle trop long (" + typed.trim().length() + " caracteres, maximum " + ColumnLabelRules.MAX_LABEL_LENGTH + ").",
                        "Libellés", JOptionPane.WARNING_MESSAGE);
                fireTableRowsUpdated(row, row);
                return;
            }
            // Case videe = retour a l'automatique ; texte inchange = pas de regle.
            final String newRule = ColumnLabelRules.applyEdit(entry.table, entry.column, entry.label, this.mode, typed);
            if (!newRule.equals(ColumnLabelRules.cleanLabel(entry.label))) {
                this.dirty = true;
            }
            entry.label = newRule;
            fireTableRowsUpdated(row, row);
        }
    }

    // ------------------------------------------------------------------
    // Rendu et edition de la colonne « Libellé affiché »
    // ------------------------------------------------------------------

    /**
     * Rend la colonne « Libellé affiché » lisible d'un coup d'oeil : tout en
     * noir, en gras ce qui est personnalise (voir {@link ColumnLabelStyle}).
     * L'utilisateur voit donc immediatement ce qui est deja choisi, et non une
     * case vide.
     */
    private static final class LabelRenderer extends DefaultTableCellRenderer {

        private static final long serialVersionUID = 1L;

        @Override
        public Component getTableCellRendererComponent(final JTable table, final Object value, final boolean isSelected, final boolean hasFocus, final int row, final int column) {
            final Component component = super.getTableCellRendererComponent(table, value, isSelected, hasFocus, row, column);
            boolean customized = false;
            if (table.getModel() instanceof EntryTableModel) {
                final int modelRow = table.convertRowIndexToModel(row);
                final EntryTableModel model = (EntryTableModel) table.getModel();
                if (modelRow >= 0 && modelRow < model.getEntries().size()) {
                    customized = model.getEntries().get(modelRow).isCustomized();
                }
            }
            // Tout en noir : le gris rendait les libelles automatiques difficiles
            // a lire. Seule la graisse distingue une regle (gras) d'un libelle
            // automatique (normal).
            final Font base = table.getFont();
            component.setFont(ColumnLabelStyle.font(base, customized));
            if (!isSelected) {
                component.setForeground(ColumnLabelStyle.color());
            }
            if (component instanceof javax.swing.JLabel) {
                ((javax.swing.JLabel) component).setToolTipText("<html>Double-cliquez pour modifier ce libellé.<br>Videz la case pour revenir au libellé automatique.</html>");
            }
            return component;
        }
    }

    /**
     * Editeur de la colonne « Libellé affiché » : ouvrable par double-clic, par
     * F2 ou en tapant directement. Le texte de la case est pre-selectionne pour
     * etre remplace d'une seule frappe ; Entree valide, Echap annule.
     */
    private static final class LabelEditor extends DefaultCellEditor {

        private static final long serialVersionUID = 1L;

        LabelEditor() {
            super(new JTextField());
            setClickCountToStart(2);
            final JTextField field = (JTextField) getComponent();
            field.setToolTipText("Libellé affiché dans les listes. Vide = libellé automatique.");
        }

        @Override
        public Component getTableCellEditorComponent(final JTable table, final Object value, final boolean isSelected, final int row, final int column) {
            final Component component = super.getTableCellEditorComponent(table, value, isSelected, row, column);
            // Pre-selection : taper remplace tout le libelle.
            if (component instanceof JTextField) {
                final JTextField field = (JTextField) component;
                field.selectAll();
                SwingUtilities.invokeLater(new Runnable() {
                    @Override
                    public void run() {
                        field.selectAll();
                    }
                });
            }
            return component;
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
