/*
 * Colonne « Affaire » dans les tableaux de lignes des documents.
 *
 * Le champ Affaire de l'en-tete d'une commande fournisseur est bien renseigne,
 * mais le tableau des lignes ne montre rien : OpenConcerto n'affiche l'affaire
 * que sur l'en-tete du document et sur l'onglet « Articles commandes » de
 * l'historique. Cette classe ajoute la colonne manquante, en lecture seule,
 * dans les tableaux de lignes (achats et ventes).
 *
 * Choix techniques :
 * <ul>
 * <li>aucune modification du jar OpenConcerto : tout passe par les API
 * publiques ({@code AbstractArticleItemTable.getModel()},
 * {@code RowValuesTableModel.addColumn()}, {@code XTableColumnModel}) ;</li>
 * <li>la valeur vient de la ligne si elle porte {@code ID_AFFAIRE}, sinon du
 * document parent (voir {@link ItemAffairColumnRules}) ;</li>
 * <li>la colonne est en lecture seule : on ne modifie pas l'affaire d'une
 * ligne en cliquant dans le tableau ;</li>
 * <li>l'installation est idempotente et se fait a l'affichage : un tableau
 * deja equipe n'est jamais retouche.</li>
 * </ul>
 */
package org.openconcerto.modules.project;

import java.awt.Component;
import java.awt.Container;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import javax.swing.SwingUtilities;
import javax.swing.table.TableColumn;

import org.openconcerto.erp.core.common.ui.AbstractArticleItemTable;
import org.openconcerto.sql.element.SQLElement;
import org.openconcerto.sql.model.SQLRow;
import org.openconcerto.sql.model.SQLRowValues;
import org.openconcerto.sql.model.SQLTable;
import org.openconcerto.sql.view.list.RowValuesTable;
import org.openconcerto.sql.view.list.RowValuesTableModel;
import org.openconcerto.sql.view.list.SQLTableElement;
import org.openconcerto.ui.table.XTableColumnModel;

public final class ItemTableAffairColumn {

    /** Propriete systeme pour desactiver la colonne : {@code -Dproject.itemAffair=false}. */
    public static final String ENABLED_PROPERTY = "project.itemAffair";

    /** Marque posee sur un tableau deja equipe. */
    private static final String DONE = "project.itemAffairColumn";

    private static final String AFFAIR_TABLE = AffairLinkSupport.AFFAIR_TABLE;
    private static final int WIDTH = 90;

    private ItemTableAffairColumn() {
    }

    /** Vrai si la fonctionnalite est active. */
    public static boolean isEnabled() {
        return ItemAffairColumnRules.isEnabled(System.getProperty(ENABLED_PROPERTY));
    }

    /**
     * Equipe tous les tableaux de lignes contenus dans ce composant.
     *
     * @return le nombre de colonnes ajoutees.
     */
    public static int install(final Component component) {
        if (component == null || !isEnabled()) {
            return 0;
        }
        final List<AbstractArticleItemTable> tables = new ArrayList<AbstractArticleItemTable>();
        collect(component, tables, 0);
        int added = 0;
        for (final AbstractArticleItemTable itemTable : tables) {
            try {
                if (installOn(itemTable)) {
                    added++;
                }
            } catch (Exception e) {
                // Une colonne manquante ne doit jamais empecher l'ecran de
                // s'afficher.
                System.err.println("colonne Affaire : installation impossible sur " + itemTable.getClass().getName() + " : " + e);
            }
        }
        return added;
    }

    /** Variante differee, pour l'EDT. */
    public static void installLater(final Component component) {
        if (component == null) {
            return;
        }
        SwingUtilities.invokeLater(new Runnable() {
            @Override
            public void run() {
                install(component);
            }
        });
    }

    private static void collect(final Component component, final List<AbstractArticleItemTable> result, final int depth) {
        if (component == null || depth > 60) {
            return;
        }
        if (component instanceof AbstractArticleItemTable) {
            result.add((AbstractArticleItemTable) component);
            // inutile de descendre : le tableau interne n'en contient pas d'autre
            return;
        }
        if (component instanceof Container) {
            final Component[] children = ((Container) component).getComponents();
            if (children != null) {
                for (int i = 0; i < children.length; i++) {
                    collect(children[i], result, depth + 1);
                }
            }
        }
    }

    /**
     * Ajoute la colonne « Affaire » a un tableau de lignes.
     *
     * @return vrai si la colonne vient d'etre ajoutee.
     */
    public static boolean installOn(final AbstractArticleItemTable itemTable) {
        if (itemTable == null || Boolean.TRUE.equals(itemTable.getClientProperty(DONE))) {
            return false;
        }
        final SQLElement element = itemTable.getSQLElement();
        if (element == null || element.getTable() == null) {
            return false;
        }
        final SQLTable lineTable = element.getTable();
        final String tableName = lineTable.getName();
        if (!ItemAffairColumnRules.isLineTable(tableName)) {
            return false;
        }
        final RowValuesTable rowValuesTable = itemTable.getRowValuesTable();
        final RowValuesTableModel model = itemTable.getModel();
        if (rowValuesTable == null || model == null) {
            return false;
        }

        final boolean hasOwnField = lineTable.contains(ItemAffairColumnRules.FIELD);
        final boolean hasParentField = hasParentAffairField(lineTable);
        final List<String> titles = columnTitles(model);
        final boolean already = ItemAffairColumnRules.hasAffairColumn(titles);
        final boolean enabled = isEnabled();

        if (!ItemAffairColumnRules.shouldAdd(tableName, hasOwnField, hasParentField, already, enabled)) {
            // On ne marque pas le tableau comme traite quand rien n'est
            // possible : le schema peut encore changer (colonne ID_AFFAIRE
            // ajoutee plus tard par ensureAffairColumns()).
            return false;
        }

        final AffairLineTableElement column = new AffairLineTableElement(lineTable, hasOwnField, hasParentField);
        // 1. le modele : la colonne est ajoutee en fin de liste (les index des
        // colonnes deja affichees ne bougent donc pas).
        model.addColumn(column);
        final int modelIndex = model.getColumnCount() - 1;

        // 2. la vue : une colonne de plus, placee a la suite de « Désignation »
        // quand elle existe, sinon en fin de tableau.
        addTableColumn(rowValuesTable, column, modelIndex);

        itemTable.putClientProperty(DONE, Boolean.TRUE);
        System.out.println("Affaire : " + ItemAffairColumnRules.explain(tableName, hasOwnField, hasParentField, already, enabled));
        return true;
    }

    private static void addTableColumn(final RowValuesTable table, final SQLTableElement element, final int modelIndex) {
        final TableColumn tableColumn = new TableColumn(modelIndex);
        tableColumn.setHeaderValue(element.getColumnName());
        tableColumn.setPreferredWidth(WIDTH);
        tableColumn.setIdentifier(element.getColumnName());
        tableColumn.setMinWidth(50);

        if (table.getColumnModel() instanceof XTableColumnModel) {
            final XTableColumnModel columnModel = (XTableColumnModel) table.getColumnModel();
            columnModel.addColumn(tableColumn);
            columnModel.setColumnVisible(tableColumn, true);
            final int lastIndex = columnModel.getColumnCount(true) - 1;
            // Position d'affichage : juste apres « Désignation » quand elle
            // existe, sinon en fin de tableau.
            final int position = ItemAffairColumnRules.insertionIndex(visibleTitles(columnModel));
            if (position >= 0 && position < lastIndex) {
                try {
                    // Le modele garde la colonne en dernier : seule la position
                    // d'affichage change, aucun index de donnees n'est decale.
                    columnModel.moveColumn(lastIndex, position);
                } catch (Exception e) {
                    System.err.println("colonne Affaire : deplacement impossible (" + e + ")");
                }
            }
        } else {
            table.getColumnModel().addColumn(tableColumn);
        }
        table.revalidate();
        table.repaint();
        table.getTableHeader().revalidate();
        table.getTableHeader().repaint();
    }

    /** Titres des colonnes telles qu'affichees, dans l'ordre de l'ecran. */
    private static List<String> visibleTitles(final XTableColumnModel columnModel) {
        final List<TableColumn> columns = columnModel.getColumns(true);
        final List<String> titles = new ArrayList<String>(columns.size());
        for (final TableColumn column : columns) {
            titles.add(column.getHeaderValue() == null ? "" : column.getHeaderValue().toString());
        }
        return titles;
    }

    /** Vrai si le document parent porte le champ Affaire. */
    private static boolean hasParentAffairField(final SQLTable lineTable) {
        final String parentTableName = ItemAffairColumnRules.parentTable(lineTable.getName());
        if (parentTableName == null) {
            return false;
        }
        try {
            if (!lineTable.getDBRoot().contains(parentTableName)) {
                return false;
            }
            final SQLTable parentTable = lineTable.getDBRoot().getTable(parentTableName);
            return parentTable.contains(ItemAffairColumnRules.FIELD) && lineTable.contains(ItemAffairColumnRules.parentField(lineTable.getName()));
        } catch (Exception e) {
            return false;
        }
    }

    private static List<String> columnTitles(final RowValuesTableModel model) {
        final List<String> titles = new ArrayList<String>(model.getColumnCount());
        for (int i = 0; i < model.getColumnCount(); i++) {
            titles.add(model.getColumnName(i));
        }
        return titles;
    }

    /**
     * Cellule « Affaire » : lit l'affaire de la ligne, sinon celle du document
     * parent, et l'affiche en lecture seule.
     */
    static final class AffairLineTableElement extends SQLTableElement {

        private final SQLTable lineTable;
        private final boolean hasOwnField;
        private final boolean hasParentField;
        /** Identifiant d'affaire -> libelle (null si introuvable). */
        private final Map<Integer, String> labels = new HashMap<Integer, String>();
        /** Document parent -> identifiant d'affaire (0 si aucune). */
        private final Map<Integer, Integer> parentAffairs = new HashMap<Integer, Integer>();

        AffairLineTableElement(final SQLTable lineTable, final boolean hasOwnField, final boolean hasParentField) {
            super(String.class, ItemAffairColumnRules.HEADER);
            this.lineTable = lineTable;
            this.hasOwnField = hasOwnField;
            this.hasParentField = hasParentField;
        }

        @Override
        protected String getRowField() {
            // Ancre de lecture : un champ qui existe a coup sur, pour que
            // RowValuesTableModel.getValueAt() ne lise pas une cle nulle.
            if (this.hasOwnField) {
                return ItemAffairColumnRules.FIELD;
            }
            final String parentField = ItemAffairColumnRules.parentField(this.lineTable.getName());
            if (parentField != null && this.lineTable.contains(parentField)) {
                return parentField;
            }
            return this.lineTable.getKey().getName();
        }

        @Override
        public boolean isCellEditable(final SQLRowValues vals, final int rowIndex, final int columnIndex) {
            // Lecture seule : l'affaire se change sur le document, pas ligne
            // par ligne.
            return false;
        }

        @Override
        public Object getValueFrom(final SQLRowValues row) {
            final Integer own = this.hasOwnField ? toInteger(row == null ? null : row.getObject(ItemAffairColumnRules.FIELD)) : null;
            final Integer parentAffair = this.hasParentField ? parentAffair(row) : null;
            final int affairID = ItemAffairColumnRules.resolve(own, parentAffair);
            if (affairID <= 0) {
                return "";
            }
            return label(affairID);
        }

        private Integer parentAffair(final SQLRowValues row) {
            final String parentField = ItemAffairColumnRules.parentField(this.lineTable.getName());
            final String parentTableName = ItemAffairColumnRules.parentTable(this.lineTable.getName());
            if (parentField == null || parentTableName == null) {
                return null;
            }
            final Integer parentID = toInteger(row == null ? null : row.getObject(parentField));
            if (!isRealID(parentID)) {
                return null;
            }
            return affairOfParent(parentTableName, parentID.intValue());
        }

        private Integer affairOfParent(final String parentTableName, final int parentID) {
            final Integer cached = this.parentAffairs.get(Integer.valueOf(parentID));
            if (cached != null) {
                return cached.intValue() > 0 ? cached : null;
            }
            Integer result = null;
            try {
                final SQLTable parentTable = this.lineTable.getDBRoot().getTable(parentTableName);
                final SQLRow parent = parentTable.getRow(parentID);
                final Integer value = toInteger(parent.getObject(ItemAffairColumnRules.FIELD));
                if (ItemAffairColumnRules.isRealAffair(value)) {
                    result = value;
                }
            } catch (Exception e) {
                System.err.println("colonne Affaire : document " + parentTableName + " " + parentID + " illisible : " + e);
            }
            this.parentAffairs.put(Integer.valueOf(parentID), result == null ? Integer.valueOf(0) : result);
            return result;
        }

        private String label(final int affairID) {
            final Integer key = Integer.valueOf(affairID);
            final String cached = this.labels.get(key);
            if (cached != null) {
                return cached;
            }
            String result = "";
            try {
                final SQLTable affairTable = this.lineTable.getDBRoot().getTable(AFFAIR_TABLE);
                final SQLRow affair = affairTable.getRow(affairID);
                result = ItemAffairColumnRules.formatLabel(key, string(affair, "NUMERO"), string(affair, "NOM"));
            } catch (Exception e) {
                System.err.println("colonne Affaire : affaire " + affairID + " illisible : " + e);
                result = ItemAffairColumnRules.formatLabel(key, null, null);
            }
            this.labels.put(key, result);
            return result;
        }

        private static boolean isRealID(final Integer id) {
            return id != null && id.intValue() > ItemAffairColumnRules.UNDEFINED_ID;
        }

        private static Integer toInteger(final Object value) {
            if (value instanceof Number) {
                return Integer.valueOf(((Number) value).intValue());
            }
            if (value instanceof String) {
                try {
                    return Integer.valueOf(Integer.parseInt(((String) value).trim()));
                } catch (NumberFormatException e) {
                    return null;
                }
            }
            return null;
        }

        private static String string(final SQLRow row, final String field) {
            try {
                return row.getTable().contains(field) ? row.getString(field) : null;
            } catch (Exception e) {
                return null;
            }
        }
    }
}
