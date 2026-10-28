package org.openconcerto.modules.project;

import java.awt.AWTEvent;
import java.awt.Color;
import java.awt.Component;
import java.awt.Container;
import java.awt.Toolkit;
import java.awt.Window;
import java.awt.event.AWTEventListener;
import java.awt.event.ContainerEvent;
import java.util.List;

import javax.swing.JTable;
import javax.swing.SwingUtilities;
import javax.swing.table.DefaultTableCellRenderer;
import javax.swing.table.JTableHeader;
import javax.swing.table.TableCellRenderer;
import javax.swing.event.TableModelEvent;
import javax.swing.event.TableModelListener;
import javax.swing.table.TableColumn;
import javax.swing.table.TableColumnModel;

import org.openconcerto.sql.view.list.IListe;
import org.openconcerto.sql.view.list.ITableModel;

/**
 * Applique les libelles de colonnes a l'interface, <b>sans modifier le cœur
 * OpenConcerto</b>.
 *
 * <p>
 * Deux niveaux, complementaires :
 * <ol>
 * <li><b>le modele d'une liste</b> ({@link #applyToIListe(IListe, String)}) :
 * la liste des noms de colonnes exposee par {@code ITableModel} est reecrite.
 * C'est ce que voient l'en-tete <i>et</i> la recherche ;</li>
 * <li><b>l'en-tete du tableau Swing</b> ({@link #applyToTree(Component)}) : on
 * renomme la valeur d'en-tete de chaque {@code TableColumn}. Cela couvre les
 * listes que le module ne construit pas lui-meme (listes du cœur, ecrans de
 * saisie), ce qui est indispensable puisque le besoin concerne toute l'equipe
 * et pas seulement l'historique des affaires.</li>
 * </ol>
 *
 * <p>
 * Le renommage est <b>idempotent</b> : {@code ID_CLIENT} devient {@code CLIENT},
 * et repasser la regle sur {@code CLIENT} ne change rien. Il est aussi
 * <b>reversible</b> : en mode {@link ColumnLabelRules#MODE_OFF}, l'en-tete
 * reprend le texte du modele.
 *
 * <p>
 * Toute erreur est avalee et tracee : un libelle ne doit jamais empecher une
 * liste de s'afficher.
 */
public final class ColumnLabelUi {

    private static final String INSTALLED_KEY = "project-column-labels-installed";
    private static final String HEADER_RENDERER_KEY = "project-column-labels-header-renderer";
    private static final String MODEL_LISTENER_KEY = "project-column-labels-model-listener";

    private static volatile boolean globalInstalled = false;

    /** Nombre de tableaux sur lesquels le rendu d'en-tete est en place. */
    private static final java.util.Set<JTable> MANAGED_TABLES = java.util.Collections.newSetFromMap(new java.util.WeakHashMap<JTable, Boolean>());

    /** Nombre de tableaux suivis (diagnostic affiche apres un enregistrement). */
    public static int countManagedTables() {
        synchronized (MANAGED_TABLES) {
            return MANAGED_TABLES.size();
        }
    }

    /** Journal detaille des resolutions (option -Dproject.labels.debug=true). */
    private static final boolean DEBUG = Boolean.getBoolean("project.labels.debug");

    private ColumnLabelUi() {
    }

    /** Libelle a afficher pour cet en-tete (regles + mode en vigueur). */
    public static String labelFor(final String header, final String table) {
        return ColumnLabelRules.resolve(header, table, ColumnLabelStore.getLabels(), ColumnLabelStore.getMode());
    }

    /**
     * Libelle a afficher en connaissant le champ technique de la colonne.
     *
     * @param header     texte affiche par le coeur (souvent un libelle metier).
     * @param table      table de la colonne, si connue.
     * @param identifier identifiant OpenConcerto de la colonne, au format
     *                   {@code TABLE.CHAMP} (voir
     *                   {@code SQLTableModelColumn.getIdentifier()}).
     */
    public static String labelForColumn(final String header, final String table, final String identifier) {
        final String field = ColumnLabelRules.technicalField(identifier);
        final String tableName = table != null && table.trim().length() > 0 ? table : ColumnLabelRules.technicalTable(identifier);
        return ColumnLabelRules.resolveForColumn(header, tableName, field, ColumnLabelStore.getLabels(), ColumnLabelStore.getMode());
    }

    /**
     * Resolution d'un en-tete pour une colonne d'un tableau donne : utilise
     * l'identifiant technique quand il est disponible, et retombe sinon sur la
     * resolution par libelle (voir {@link ColumnLabelRules#ruleByAutomaticLabel}).
     */
    static String resolvedHeader(final String header, final JTable table, final String tableName, final int modelIndex) {
        final String identifier = identifierOf(table, modelIndex);
        final String resolved = labelForColumn(header, tableNameOf(table, tableName), identifier);
        if (identifier == null && resolved != null && resolved.equals(header) && DEBUG) {
            Module.log("libelles : identifiant technique indisponible pour la colonne « " + header + " » (resolution par libelle)");
        }
        return resolved;
    }

    /**
     * Identifiant technique ({@code TABLE.CHAMP}) de la colonne de modele
     * <code>modelIndex</code>, ou <code>null</code> si le modele du tableau n'est
     * pas une liste de l'ERP.
     * <p>
     * C'est ce qui permet d'appliquer une regle {@code *.ID_FOURNISSEUR} a une
     * colonne dont l'en-tete affiche deja « Fournisseur ».
     */
    static String identifierOf(final JTable table, final int modelIndex) {
        if (table == null || modelIndex < 0) {
            return null;
        }
        try {
            final Object model = table.getModel();
            if (!(model instanceof ITableModel)) {
                return null;
            }
            final ITableModel iModel = (ITableModel) model;
            if (modelIndex >= iModel.getColumnCount()) {
                return null;
            }
            return iModel.getReq().getColumn(modelIndex).getIdentifier();
        } catch (Exception e) {
            return null;
        }
    }

    // ------------------------------------------------------------------
    // Niveau modele (IListe)
    // ------------------------------------------------------------------

    /**
     * Reecrit les noms de colonnes d'une liste.
     *
     * @param liste     liste de l'ERP.
     * @param tableName table des lignes, ou <code>null</code> si elle n'est pas
     *                  connue (les regles {@code *.COLONNE} et la regle
     *                  automatique s'appliquent quand meme).
     * @return le nombre de colonnes renommees.
     */
    public static int applyToIListe(final IListe liste, final String tableName) {
        if (liste == null) {
            return 0;
        }
        int changed = 0;
        try {
            final ITableModel model = liste.getModel();
            if (model == null) {
                return 0;
            }
            final List<String> columnNames = model.getColumnNames();
            if (columnNames == null) {
                return 0;
            }
            for (int i = 0; i < columnNames.size(); i++) {
                final String current = columnNames.get(i);
                final String resolved = labelFor(current, tableName);
                if (resolved != null && !resolved.equals(current)) {
                    columnNames.set(i, resolved);
                    changed++;
                }
            }
        } catch (Exception e) {
            Module.log("libelles : application a une liste impossible (" + e + ")");
            return changed;
        }
        if (changed > 0) {
            try {
                final JTable table = liste.getJTable();
                if (table != null) {
                    applyHeaders(table, tableName);
                    table.getTableHeader().repaint();
                }
            } catch (Exception e) {
                Module.log("libelles : rafraichissement de l'en-tete impossible (" + e + ")");
            }
        }
        return changed;
    }

    // ------------------------------------------------------------------
    // Niveau Swing (toutes les listes de l'application)
    // ------------------------------------------------------------------

    /**
     * Renomme les en-tetes d'un tableau.
     *
     * @return le nombre de colonnes renommees.
     */
    public static int applyHeaders(final JTable table, final String tableName) {
        if (table == null) {
            return 0;
        }
        if (ColumnLabelRules.MODE_OFF.equals(ColumnLabelStore.getMode())) {
            return 0;
        }
        int changed = 0;
        try {
            final TableColumnModel columnModel = table.getColumnModel();
            for (int i = 0; i < columnModel.getColumnCount(); i++) {
                final TableColumn column = columnModel.getColumn(i);
                final Object header = column.getHeaderValue();
                if (!(header instanceof String)) {
                    continue;
                }
                final String current = (String) header;
                final int modelIndex = table.convertColumnIndexToModel(i);
                final String resolved = resolvedHeader(current, table, tableName, modelIndex);
                if (resolved != null && !resolved.equals(current)) {
                    column.setHeaderValue(resolved);
                    changed++;
                }
            }
        } catch (Exception e) {
            Module.log("libelles : renommage d'un en-tete impossible (" + e + ")");
        }
        return changed;
    }

    /**
     * Parcourt un arbre de composants et renomme les en-tetes de tous les
     * tableaux rencontres.
     *
     * @return le nombre de colonnes renommees.
     */
    public static int applyToTree(final Component component) {
        if (component == null) {
            return 0;
        }
        int changed = 0;
        if (component instanceof JTable) {
            changed += installOnTable((JTable) component);
        } else if (component instanceof Container) {
            final Component[] children = ((Container) component).getComponents();
            for (int i = 0; i < children.length; i++) {
                changed += applyToTree(children[i]);
            }
        }
        return changed;
    }

    /**
     * Installe le renommage sur un tableau et le rejoue a chaque changement de
     * modele (les en-tetes sont reconstruits par le cœur a ce moment-la).
     */
    public static int installOnTable(final JTable table) {
        if (table == null) {
            return 0;
        }
        final int changed = applyHeaders(table, null);
        installHeaderRenderer(table);
        if (Boolean.TRUE.equals(table.getClientProperty(MODEL_LISTENER_KEY))) {
            return changed;
        }
        try {
            table.getModel().addTableModelListener(new TableModelListener() {
                @Override
                public void tableChanged(final TableModelEvent e) {
                    // Les en-tetes sont reconstruits apres un changement de modele :
                    // on reapplique une fois le modele stabilise.
                    SwingUtilities.invokeLater(new Runnable() {
                        @Override
                        public void run() {
                            applyHeaders(table, null);
                            if (table.getTableHeader() != null) {
                                table.getTableHeader().repaint();
                            }
                        }
                    });
                }
            });
            table.putClientProperty(MODEL_LISTENER_KEY, Boolean.TRUE);
        } catch (Exception e) {
            Module.log("libelles : surveillance d'un tableau impossible (" + e + ")");
        }
        return changed;
    }

    /**
     * Installe un rendu d'en-tete qui applique le libelle <b>au moment de
     * l'affichage</b>.
     * <p>
     * Pourquoi ne pas se contenter de reecrire la valeur des colonnes : les
     * listes de l'ERP reconstruisent leurs colonnes a chaque rafraichissement
     * ({@code ITableModel.updateColNames}), et un en-tete deja renomme peut etre
     * reintroduit tel quel par le cœur. Resultat constate : le libelle changeait
     * dans l'ecran de parametrage mais <b>pas dans les listes</b>
     * (« Articles commandés », « Factures fournisseurs »...).
     * <p>
     * En resolvant le libelle au dessin, n'importe quel rafraichissement ou
     * changement de modele affiche la bonne valeur, sans dependre d'un evenement.
     * Le rendu d'origine du theme est conserve (tri, icones, couleurs).
     */
    static void installHeaderRenderer(final JTable table) {
        if (table == null || table.getTableHeader() == null) {
            return;
        }
        try {
            final JTableHeader header = table.getTableHeader();
            final TableCellRenderer current = header.getDefaultRenderer();
            // Les listes du coeur remplacent le rendu d'en-tete apres leur
            // construction : on ne se contente donc pas de « deja installe »,
            // on verifie que notre rendu est toujours celui en place.
            if (current instanceof LabelHeaderRenderer) {
                return;
            }
            header.setDefaultRenderer(new LabelHeaderRenderer(table, current));
            synchronized (MANAGED_TABLES) {
                MANAGED_TABLES.add(table);
            }
            if (!Boolean.TRUE.equals(table.getClientProperty(HEADER_RENDERER_KEY))) {
                table.putClientProperty(HEADER_RENDERER_KEY, Boolean.TRUE);
                Module.log("libelles : rendu d'en-tete installe sur un tableau");
            }
        } catch (Exception e) {
            Module.log("libelles : rendu d'en-tete impossible (" + e + ")");
        }
    }

    /**
     * Rendu d'en-tete qui traduit la valeur affichee (voir
     * {@link ColumnLabelUi#installHeaderRenderer(JTable)}).
     */
    private static final class LabelHeaderRenderer implements TableCellRenderer {

        private final JTable table;
        private final TableCellRenderer previous;
        private final TableCellRenderer fallback = new DefaultTableCellRenderer();

        LabelHeaderRenderer(final JTable table, final TableCellRenderer previous) {
            this.table = table;
            this.previous = previous;
        }

        @Override
        public Component getTableCellRendererComponent(final JTable ignored, final Object value, final boolean isSelected, final boolean hasFocus, final int row, final int column) {
            Object displayed = value;
            if (value instanceof String) {
                try {
                    final int modelIndex = this.table.convertColumnIndexToModel(column);
                    final String label = resolvedHeader((String) value, this.table, null, modelIndex);
                    if (label != null && label.length() > 0) {
                        displayed = label;
                    }
                } catch (Exception e) {
                    // jamais d'exception pendant un dessin
                }
            }
            final TableCellRenderer delegate = this.previous == null ? this.fallback : this.previous;
            final Component component = delegate.getTableCellRendererComponent(this.table, displayed, isSelected, hasFocus, row, column);
            if (!isSelected && component instanceof javax.swing.JLabel) {
                // En-tetes lisibles quel que soit le theme (meme exigence que
                // l'ecran de parametrage : plus de gris pale).
                ((javax.swing.JLabel) component).setForeground(new Color(0x20, 0x20, 0x20));
            }
            return component;
        }
    }

    /**
     * Installe le renommage <b>global</b> : toute fenetre ouverte et tout tableau
     * ajoute ensuite est traite, y compris les listes du cœur OpenConcerto que le
     * module ne construit pas.
     *
     * <p>
     * L'installation est faite une seule fois par session. Elle ne bloque rien :
     * chaque etape est protegee par un {@code try/catch} qui trace une ligne
     * {@code [module project] ...}.
     *
     * @return le nombre de tableaux deja traites au moment de l'installation.
     */
    public static int installGlobal() {
        if (globalInstalled) {
            return 0;
        }
        synchronized (ColumnLabelUi.class) {
            if (globalInstalled) {
                return 0;
            }
            int changed = 0;
            try {
                Toolkit.getDefaultToolkit().addAWTEventListener(new AWTEventListener() {
                    @Override
                    public void eventDispatched(final AWTEvent event) {
                        if (event instanceof ContainerEvent) {
                            final Component child = ((ContainerEvent) event).getChild();
                            if (child != null) {
                                SwingUtilities.invokeLater(new Runnable() {
                                    @Override
                                    public void run() {
                                        try {
                                            applyToTree(child);
                                        } catch (Exception e) {
                                            Module.log("libelles : traitement d'un composant impossible (" + e + ")");
                                        }
                                    }
                                });
                            }
                        }
                    }
                }, AWTEvent.CONTAINER_EVENT_MASK);
            } catch (Exception e) {
                Module.log("libelles : installation globale impossible (" + e + ")");
            }
            for (final Window window : Window.getWindows()) {
                changed += applyToTree(window);
            }
            globalInstalled = true;
            Module.log("libelles de colonnes : mode " + ColumnLabelStore.getMode() + ", " + ColumnLabelStore.getLabels().size() + " regle(s), application globale installee");
            return changed;
        }
    }

    /**
     * Reapplique les libelles a toutes les fenetres ouvertes : appele apres un
     * enregistrement, pour que l'equipe voie immediatement le resultat sur son
     * poste sans redemarrer.
     *
     * @return le nombre de colonnes renommees.
     */
    public static int refreshAll() {
        int changed = 0;
        for (final Window window : Window.getWindows()) {
            changed += applyToTree(window);
            if (window != null) {
                window.repaint();
            }
        }
        return changed;
    }

    /** Nom de table porte par un tableau, s'il a ete annonce par le module. */
    static String tableNameOf(final JTable table, final String fallback) {
        if (fallback != null && fallback.trim().length() > 0) {
            return fallback;
        }
        try {
            final Object value = table.getClientProperty("project.tableName");
            if (value != null) {
                return String.valueOf(value);
            }
        } catch (Exception e) {
            // sans nom de table : seules les regles *.COLONNE et automatiques s'appliquent
        }
        return null;
    }

    /** Annonce la table d'un tableau, pour que les regles {@code TABLE.COLONNE} s'appliquent. */
    public static void tagTable(final JTable table, final String tableName) {
        if (table != null && tableName != null) {
            table.putClientProperty("project.tableName", tableName);
        }
    }

    /** Vrai si l'installation globale a eu lieu. */
    public static boolean isGlobalInstalled() {
        return globalInstalled;
    }

}
