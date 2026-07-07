/*
 * Créé le 3 juin 2012
 */
package org.openconcerto.modules.project;

import java.awt.BorderLayout;
import java.awt.Component;
import java.awt.Container;
import java.awt.FlowLayout;
import java.awt.GridBagConstraints;
import java.awt.Insets;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.awt.event.WindowAdapter;
import java.awt.event.WindowEvent;
import java.io.File;
import java.math.BigDecimal;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Calendar;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import javax.swing.Action;
import javax.swing.AbstractAction;
import javax.swing.JButton;
import javax.swing.JCheckBox;
import javax.swing.JComboBox;
import javax.swing.JFrame;
import javax.swing.JLabel;
import javax.swing.JList;
import javax.swing.JPanel;
import javax.swing.JSplitPane;
import javax.swing.ListCellRenderer;
import javax.swing.SwingUtilities;
import javax.swing.event.ListDataEvent;
import javax.swing.event.ListDataListener;
import javax.swing.event.ListSelectionEvent;
import javax.swing.event.ListSelectionListener;
import javax.swing.event.TableModelEvent;
import javax.swing.event.TableModelListener;

import org.openconcerto.erp.config.ComptaPropsConfiguration;
import org.openconcerto.erp.config.Gestion;
import org.openconcerto.erp.core.common.ui.IListFilterDatePanel;
import org.openconcerto.erp.core.reports.history.ui.ListeHistoriquePanel;
import org.openconcerto.erp.core.sales.account.VenteFactureSituationSQLComponent;
import org.openconcerto.erp.core.sales.account.VenteFactureSoldeSQLComponent;
import org.openconcerto.erp.utils.TM;
import org.openconcerto.modules.project.element.ProjectStateSQLElement;
import org.openconcerto.modules.project.panel.HistoriqueAffaireBilanPanel;
import org.openconcerto.sql.Configuration;
import org.openconcerto.sql.element.SQLElement;
import org.openconcerto.sql.model.FieldPath;
import org.openconcerto.sql.model.SQLBase;
import org.openconcerto.sql.model.SQLField;
import org.openconcerto.sql.model.SQLRowAccessor;
import org.openconcerto.sql.model.SQLRowValues;
import org.openconcerto.sql.model.SQLSelect;
import org.openconcerto.sql.model.SQLTable;
import org.openconcerto.sql.model.SQLTableEvent;
import org.openconcerto.sql.model.SQLTableModifiedListener;
import org.openconcerto.sql.model.Where;
import org.openconcerto.sql.model.graph.Path;
import org.openconcerto.sql.request.ComboSQLRequest;
import org.openconcerto.sql.sqlobject.IComboSelectionItem;
import org.openconcerto.sql.users.rights.JListSQLTableModel;
import org.openconcerto.sql.users.rights.JListSQLTablePanel;
import org.openconcerto.sql.view.EditFrame;
import org.openconcerto.sql.view.EditPanel;
import org.openconcerto.sql.view.IListPanel;
import org.openconcerto.sql.view.list.BaseSQLTableModelColumn;
import org.openconcerto.sql.view.list.IListe;
import org.openconcerto.sql.view.list.IListeAction;
import org.openconcerto.sql.view.list.IListeAction.IListeEvent;
import org.openconcerto.sql.view.list.ITableModel;
import org.openconcerto.sql.view.list.RowAction;
import org.openconcerto.sql.view.list.RowAction.PredicateRowAction;
import org.openconcerto.sql.view.list.SQLTableModelColumn;
import org.openconcerto.ui.DefaultGridBagConstraints;
import org.openconcerto.ui.FrameUtil;
import org.openconcerto.ui.PanelFrame;
import org.openconcerto.ui.state.WindowStateManager;
import org.openconcerto.utils.CollectionUtils;
import org.openconcerto.utils.DecimalUtils;
import org.openconcerto.utils.GestionDevise;
import org.openconcerto.utils.cc.ITransformer;

public class ProjectHistory {
    private PanelFrame panelFrame;
    private ListeHistoriquePanel listPanel;

    public ListeHistoriquePanel getHistoriquePanel() {
        return this.listPanel;
    }

    private static Map<String, List<String>> moduleTab = new HashMap<String, List<String>>();

    public static void addTab(String tabName, List<String> table) {
        moduleTab.put(tabName, table);
    }

    public ProjectHistory() {

        final ComptaPropsConfiguration comptaPropsConfiguration = ((ComptaPropsConfiguration) Configuration.getInstance());
        final SQLBase b = comptaPropsConfiguration.getSQLBaseSociete();

        final Map<String, List<String>> mapList = new LinkedHashMap<String, List<String>>();
        mapList.put("Devis", Arrays.asList("DEVIS"));
        mapList.put("Bons de commande", Arrays.asList("COMMANDE_CLIENT"));
        mapList.put("Chiffrage", Arrays.asList("CHIFFRAGE_COMMANDE_CLIENT"));
        mapList.put("Factures", Arrays.asList("SAISIE_VENTE_FACTURE"));
        mapList.put("Avoirs", Arrays.asList("AVOIR_CLIENT"));
        mapList.put("Demandes d'achat", Arrays.asList("DEMANDE_ACHAT_ELEMENT"));
        mapList.put("Demandes de prix", Arrays.asList("DEMANDE_PRIX"));
        putIfTableExists(mapList, "Bons de livraison clients", "BON_DE_LIVRAISON");

        Map<SQLTable, SQLField> fieldLink = new HashMap<SQLTable, SQLField>();
        fieldLink.put(b.getTable("CHIFFRAGE_COMMANDE_CLIENT"), b.getTable("CHIFFRAGE_COMMANDE_CLIENT").getField("ID_COMMANDE_CLIENT"));

        putIfTableExists(mapList, "Commandes fournisseurs", "COMMANDE");
        mapList.put("Articles commandés", Arrays.asList("COMMANDE_ELEMENT"));
        if (!b.getTable("COMMANDE_ELEMENT").contains("ID_AFFAIRE")) {
            fieldLink.put(b.getTable("COMMANDE_ELEMENT"), b.getTable("COMMANDE_ELEMENT").getField("ID_COMMANDE"));
        }
        putIfTableExists(mapList, "Bons de réception fournisseurs", "BON_RECEPTION");

        mapList.put("Articles réceptionnés", Arrays.asList("BON_RECEPTION_ELEMENT"));
        if (!b.getTable("BON_RECEPTION_ELEMENT").contains("ID_AFFAIRE")) {
            fieldLink.put(b.getTable("BON_RECEPTION_ELEMENT"), b.getTable("BON_RECEPTION_ELEMENT").getField("ID_BON_RECEPTION"));
        }
        mapList.put("Achats", Arrays.asList("SAISIE_ACHAT"));
        // mapList.put("Factures fournisseurs", Arrays.asList("FACTURE_FOURNISSEUR"));

        mapList.put("Avoirs fournisseurs", Arrays.asList("AVOIR_FOURNISSEUR"));
        if (Configuration.getInstance().getRoot().findTable("AFFAIRE_TEMPS") != null) {
            mapList.put("Temps", Arrays.asList("AFFAIRE_TEMPS"));
        }
        if (b.getTable("AFFAIRE").contains("ID_DEPOT_STOCK")) {
            mapList.put("Stock", Arrays.asList("MOUVEMENT_STOCK"));
        }

        if (Configuration.getInstance().getRoot().findTable("NOTE_DE_FRAIS") != null) {
            mapList.put("Note de frais", Arrays.asList("NOTE_DE_FRAIS_ELEMENT"));
        }
        if (Configuration.getInstance().getRoot().findTable("POINTAGE") != null) {
            mapList.put("Pointage", Arrays.asList("POINTAGE_ELEMENT"));
        }
        if (b.getTable("FACTURE_FOURNISSEUR_ELEMENT").contains("ID_AFFAIRE")) {
            mapList.put("Factures fournisseurs", Arrays.asList("FACTURE_FOURNISSEUR_ELEMENT"));
        } else {
            mapList.put("Factures fournisseurs", Arrays.asList("FACTURE_FOURNISSEUR"));
        }

        mapList.putAll(moduleTab);

        final HistoriqueAffaireBilanPanel bilanPanel = new HistoriqueAffaireBilanPanel();

        final List<String> affairFields = new java.util.ArrayList<String>(Arrays.asList("NUMERO", "ID_CLIENT", "NOM"));
        if (b.getTable("AFFAIRE").contains("DATE")) {
            affairFields.add("DATE");
        }
        final ComboSQLRequest request = new org.openconcerto.sql.request.ComboSQLRequest(b.getTable("AFFAIRE"), affairFields);
        if (b.getTable("AFFAIRE").contains("ID_SOCIETE_COMMON")) {

            final int socID = comptaPropsConfiguration.getSocieteID();
            request.setSelectTransf(new ITransformer<SQLSelect, SQLSelect>() {
                @Override
                public SQLSelect transformChecked(SQLSelect input) {
                    Where w = new Where(b.getTable("AFFAIRE").getField("ID_SOCIETE_COMMON"), "=", (Object) null).or(new Where(b.getTable("AFFAIRE").getField("ID_SOCIETE_COMMON"), "=", 1))
                            .or(new Where(b.getTable("AFFAIRE").getField("ID_SOCIETE_COMMON"), "=", socID));

                    input.andWhere(w);
                    return input;
                }
            });
        }
        request.setUndefLabel("Toutes les affaires");
        request.setFieldSeparator(" ");
        Map<String, String> splitter = new HashMap<String, String>();
        if (!b.getTable("AFFAIRE").contains("ID_DEPOT_STOCK")) {
            splitter.put("DEMANDE_ACHAT_ELEMENT", "ID_FAMILLE_ARTICLE");
            splitter.put("COMMANDE_ELEMENT", "ID_FAMILLE_ARTICLE");
        }

        // if (Configuration.getInstance().getRoot().findTable("POINTAGE") != null) {
        // fieldLink.put(b.getTable("POINTAGE"),
        // b.getTable("POINTAGE_ELEMENT").getField("ID_POINTAGE"));
        // }

        this.listPanel = new ListeHistoriquePanel("Affaires", request, mapList, bilanPanel, fieldLink, null, true, null, null, splitter);

        int nbList = mapList.size();
        Map<IListe, SQLField> mapFilterDate = new HashMap<>();
        for (int i = 0; i < nbList; i++) {
            IListe liste = this.listPanel.getListe(i);
            final List<SQLTableModelColumn> columns = liste.getModel().getReq().getColumns();
            boolean dateFound = false;
            for (SQLTableModelColumn sqlTableModelColumn : columns) {
                final Set<SQLField> fields = sqlTableModelColumn.getFields();
                for (SQLField field : fields) {
                    if (field.getName().equals("DATE")) {
                        mapFilterDate.put(liste, field);
                        dateFound = true;
                        break;
                    }
                    if (field.getName().equals("DATE_DU")) {
                        mapFilterDate.put(liste, field);
                        dateFound = true;
                        break;
                    }
                }
                if (dateFound) {
                    break;
                }
            }

        }
        IListFilterDatePanel filterDate = new IListFilterDatePanel(mapFilterDate, IListFilterDatePanel.getDefaultMap());
        GridBagConstraints cDate = new DefaultGridBagConstraints();
        cDate.gridwidth = GridBagConstraints.REMAINDER;
        cDate.weightx = 1;
        cDate.weighty = 0;
        cDate.fill = GridBagConstraints.HORIZONTAL;
        bilanPanel.add(filterDate, cDate);
        final IListPanel listeDevis = listPanel.getIListePanelFromTableName("DEVIS");
        GridBagConstraints c = new DefaultGridBagConstraints();
        c.gridy = 4;
        c.fill = GridBagConstraints.BOTH;
        final ProjectHistoryDevisBottomPanel devisPanel = new ProjectHistoryDevisBottomPanel();
        listeDevis.add(devisPanel, c);
        listeDevis.getListe().getTableModel().addTableModelListener(new TableModelListener() {

            @Override
            public void tableChanged(TableModelEvent e) {
                devisPanel.updateDevis(listeDevis.getListe());
                devisPanel.updateTimeDevis(listeDevis.getListe());
            }
        });

        final IListPanel listeVente = this.listPanel.getIListePanelFromTableName("SAISIE_VENTE_FACTURE");
        final SQLElement eltFacture = listeVente.getElement();
        final PredicateRowAction action = new PredicateRowAction(new AbstractAction(TM.tr("display")) {

            @Override
            public void actionPerformed(ActionEvent e) {
                EditFrame editModifyFrame;
                SQLRowAccessor row = IListe.get(e).getSelectedRowAccessor();
                if (eltFacture.getTable().getName().equals("SAISIE_VENTE_FACTURE") && row.getBoolean("PARTIAL")) {
                    editModifyFrame = new EditFrame(eltFacture.createComponent(VenteFactureSituationSQLComponent.ID), EditPanel.READONLY);
                } else if (eltFacture.getTable().getName().equals("SAISIE_VENTE_FACTURE") && row.getBoolean("SOLDE")) {
                    editModifyFrame = new EditFrame(eltFacture.createComponent(VenteFactureSoldeSQLComponent.ID), EditPanel.READONLY);
                } else {
                    editModifyFrame = new EditFrame(eltFacture, EditPanel.READONLY);
                }
                editModifyFrame.selectionId(row.getID());
                editModifyFrame.setVisible(true);

            }
        }, false);
        action.setPredicate(IListeEvent.getSingleSelectionPredicate());
        listeVente.getListe().setDefaultRowAction(action);

        final List<IListPanel> listeCmdElts = listPanel.getAllIListePanelFromTableName("COMMANDE_ELEMENT");
        if (listeCmdElts != null && !listeCmdElts.isEmpty()) {
            for (final IListPanel listeCmdElt : listeCmdElts) {

                if (listeCmdElt.getListe().getSource().getColumns(b.getTable("COMMANDE_ELEMENT").getField("ID_FAMILLE_ARTICLE")).isEmpty()) {
                    listeCmdElt.getListe().getSource().getColumns().add(new BaseSQLTableModelColumn("Famille", String.class) {

                        @Override
                        protected Object show_(SQLRowAccessor r) {
                            final SQLRowAccessor nonEmptyForeign = r.getNonEmptyForeign("ID_FAMILLE_ARTICLE");
                            if (nonEmptyForeign != null) {
                                return nonEmptyForeign.getString("NOM");
                            } else {
                                return "";
                            }
                        }

                        @Override
                        public Set<FieldPath> getPaths() {
                            Path p = new Path(listeCmdElt.getListe().getSource().getPrimaryTable());
                            p = p.add(p.getLast().getField("ID_FAMILLE_ARTICLE"));
                            return CollectionUtils.createSet(new FieldPath(p, "NOM"));
                        }
                    });
                }
                listeCmdElt.getListe().getSource().getColumns().add(new BaseSQLTableModelColumn("Etat", String.class) {

                    @Override
                    protected Object show_(SQLRowAccessor r) {
                        final BigDecimal qteU = r.getBigDecimal("QTE_UNITAIRE");
                        final int qte = r.getInt("QTE");
                        final BigDecimal qteRecue = r.getBigDecimal("QTE_RECUE");
                        final Boolean recu = r.getBoolean("RECU");
                        final Boolean recuForced = r.getBoolean("RECU_FORCED");
                        final BigDecimal qteCmd = qteU.multiply(new BigDecimal(qte), DecimalUtils.HIGH_PRECISION);
                        if ((recu != null && recu) || (recuForced != null && recuForced) || qteRecue == null || qteCmd.compareTo(qteRecue) <= 0) {
                            return "Réceptionné";
                        } else if (qteRecue != null && qteRecue.signum() > 0) {
                            return "Partiellement réceptionné";
                        } else {
                            return "Non réceptionné";
                        }
                    }

                    @Override
                    public Set<FieldPath> getPaths() {
                        Path p = new Path(listeCmdElt.getListe().getSource().getPrimaryTable());

                        return CollectionUtils.createSet(new FieldPath(p, "QTE"), new FieldPath(p, "QTE_UNITAIRE"), new FieldPath(p, "QTE_RECUE"), new FieldPath(p, "RECU"),
                                new FieldPath(p, "RECU_FORCED"));
                    }
                });
            }
        }

        final IListPanel listeCmd = listPanel.getIListePanelFromTableName("COMMANDE_CLIENT");
        final ProjectHistoryCmdBottomPanel cmdPanel = new ProjectHistoryCmdBottomPanel();

        listeCmd.add(cmdPanel, c);
        listeCmd.getListe().getTableModel().addTableModelListener(new TableModelListener() {

            @Override
            public void tableChanged(TableModelEvent e) {
                cmdPanel.updateCmd(listeCmd.getListe());
                cmdPanel.updateTimeCmd(listeCmd.getListe());
            }
        });

        // If time tracking is installed
        final IListPanel listeTemps = listPanel.getIListePanelFromTableName("AFFAIRE_TEMPS");
        if (listeTemps != null) {
            final ProjectHistoryTimeBottomPanel timePanel = new ProjectHistoryTimeBottomPanel();
            listeTemps.add(timePanel, c);
            listeTemps.getListe().getTableModel().addTableModelListener(new TableModelListener() {

                @Override
                public void tableChanged(TableModelEvent e) {
                    timePanel.updateTime(listeTemps.getListe());
                }
            });
        }
        // History
        this.panelFrame = new PanelFrame(this.listPanel, "Historique affaires");
        installHistoryControls();
        this.panelFrame.addWindowListener(new WindowAdapter() {

            public void windowClosing(WindowEvent e) {
                listPanel.removeAllTableListener();
            };

        });

        this.panelFrame.setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);

        final SQLTableModifiedListener cmdClientListener = new SQLTableModifiedListener() {

            @Override
            public void tableModified(SQLTableEvent evt) {
                if (bilanPanel != null) {
                    final SQLRowAccessor selectedRow = ProjectHistory.this.listPanel.getSelectedRow();
                    if (selectedRow != null) {
                        bilanPanel.updateCommandeClient(selectedRow.asRow());
                    }
                }
            }
        };
        final SQLTableModifiedListener devisListener = new SQLTableModifiedListener() {

            @Override
            public void tableModified(SQLTableEvent evt) {
                if (bilanPanel != null) {
                    final SQLRowAccessor selectedRow = ProjectHistory.this.listPanel.getSelectedRow();
                    if (selectedRow != null) {
                        bilanPanel.updateDevis(selectedRow.asRow());
                    }
                }
            }
        };
        this.panelFrame.addWindowListener(new WindowAdapter() {
            public void windowClosing(WindowEvent e) {
                listPanel.removeAllTableListener();
                b.getTable("COMMANDE_CLIENT").removeTableModifiedListener(cmdClientListener);
                b.getTable("DEVIS").removeTableModifiedListener(devisListener);
            };
        });

        b.getTable("COMMANDE_CLIENT").addTableModifiedListener(cmdClientListener);
        b.getTable("DEVIS").addTableModifiedListener(devisListener);

        this.listPanel.addListSelectionListener(new ListSelectionListener() {

            @Override
            public void valueChanged(ListSelectionEvent arg0) {

                final SQLRowAccessor selectedRow = ProjectHistory.this.listPanel.getSelectedRow();
                if (selectedRow != null) {
                    bilanPanel.updateCommandeClient(selectedRow.asRow());
                    bilanPanel.updateDevis(selectedRow.asRow());
                    bilanPanel.updateBilanPreBilan(ProjectHistory.this.listPanel.getIListeFromTableName("COMMANDE"));
                }
            }
        });

        this.listPanel.addListenerTable(new TableModelListener() {
            public void tableChanged(TableModelEvent arg0) {
                final SQLRowAccessor selectedRow = ProjectHistory.this.listPanel.getSelectedRow();
                if (selectedRow != null) {
                    bilanPanel.updateBilanPreBilan(ProjectHistory.this.listPanel.getIListeFromTableName("COMMANDE"));
                }
            }
        }, "COMMANDE");

        this.listPanel.addListenerTable(new TableModelListener() {
            public void tableChanged(TableModelEvent arg0) {
                bilanPanel.updateAchat(ProjectHistory.this.listPanel.getIListeFromTableName("SAISIE_ACHAT"), ProjectHistory.this.listPanel.getIListeFromTableName("AVOIR_FOURNISSEUR"),
                        ProjectHistory.this.listPanel.getIListeFromTableName("FACTURE_FOURNISSEUR"), ProjectHistory.this.listPanel.getIListeFromTableName("FACTURE_FOURNISSEUR_ELEMENT"));
            }
        }, "SAISIE_ACHAT");
        this.listPanel.addListenerTable(new TableModelListener() {
            public void tableChanged(TableModelEvent arg0) {
                bilanPanel.updateAchat(ProjectHistory.this.listPanel.getIListeFromTableName("SAISIE_ACHAT"), ProjectHistory.this.listPanel.getIListeFromTableName("AVOIR_FOURNISSEUR"),
                        ProjectHistory.this.listPanel.getIListeFromTableName("FACTURE_FOURNISSEUR"), ProjectHistory.this.listPanel.getIListeFromTableName("FACTURE_FOURNISSEUR_ELEMENT"));
            }
        }, "AVOIR_FOURNISSEUR");

        this.listPanel.addListenerTable(new TableModelListener() {
            public void tableChanged(TableModelEvent arg0) {
                bilanPanel.updateFacturer(ProjectHistory.this.listPanel.getIListeFromTableName("SAISIE_VENTE_FACTURE"), ProjectHistory.this.listPanel.getIListeFromTableName("AVOIR_CLIENT"));
            }
        }, "SAISIE_VENTE_FACTURE");

        this.listPanel.addListenerTable(new TableModelListener() {
            public void tableChanged(TableModelEvent arg0) {
                bilanPanel.updateFacturer(ProjectHistory.this.listPanel.getIListeFromTableName("SAISIE_VENTE_FACTURE"), ProjectHistory.this.listPanel.getIListeFromTableName("AVOIR_CLIENT"));
            }
        }, "AVOIR_CLIENT");

        if (comptaPropsConfiguration.getRowSociete().getString("NOM").startsWith("CIM ")) {
            GridBagConstraints cBilan = new DefaultGridBagConstraints();
            cBilan.insets = new Insets(2, 2, 2, 75);
            cBilan.gridx = 0;
            cBilan.gridy += 6;
            cBilan.gridwidth = GridBagConstraints.REMAINDER;
            cBilan.weightx = 1;
            final JLabel labelBudgetMecaPneu = new JLabel("Budget achats méca et pneu");
            bilanPanel.add(labelBudgetMecaPneu, cBilan);
            cBilan.gridx++;
            final JLabel labelBudgetElec = new JLabel("Budget achats elec");
            bilanPanel.add(labelBudgetElec, cBilan);
            cBilan.gridy++;
            cBilan.gridx = 0;
            final JLabel labelTotalMecaPneu = new JLabel("Total cmde méca et pneu");
            bilanPanel.add(labelTotalMecaPneu, cBilan);
            cBilan.gridx++;
            final JLabel labelTotalElec = new JLabel("Total cmde achats elec");
            bilanPanel.add(labelTotalElec, cBilan);

            this.listPanel.addListenerTable(new TableModelListener() {
                public void tableChanged(TableModelEvent arg0) {
                    final IListe liste = listPanel.getIListeFromTableName("CHIFFRAGE_COMMANDE_CLIENT");
                    if (liste == null) {
                        return;
                    }

                    BigDecimal montantMecaPneu = BigDecimal.ZERO;
                    BigDecimal montantElec = BigDecimal.ZERO;
                    for (int i = 0; i < liste.getRowCount(); i++) {
                        final SQLRowValues rowAt = ITableModel.getLine(liste.getModel(), i).getRow();
                        final Number foreignID = rowAt.getNonEmptyForeignIDNumber("ID_FAMILLE_ARTICLE");
                        if (foreignID != null && foreignID.intValue() == 12) {
                            montantElec = montantElec.add(rowAt.getBigDecimal("T_PA_HT"));
                        } else {
                            montantMecaPneu = montantMecaPneu.add(rowAt.getBigDecimal("T_PA_HT"));
                        }
                    }
                    labelBudgetMecaPneu.setText("Budget achats méca et pneu : " + GestionDevise.currencyToString(montantMecaPneu) + "€");
                    labelBudgetElec.setText("Budget achats elec : " + GestionDevise.currencyToString(montantElec) + "€");

                }
            }, "CHIFFRAGE_COMMANDE_CLIENT");

            this.listPanel.addListenerTable(new TableModelListener() {
                public void tableChanged(TableModelEvent arg0) {
                    final IListe liste = listPanel.getIListeFromTableName("COMMANDE_ELEMENT");
                    if (liste == null || listeCmdElts == null) {
                        return;
                    }

                    BigDecimal montantMecaPneu = BigDecimal.ZERO;
                    BigDecimal montantElec = BigDecimal.ZERO;
                    for (IListPanel panel : listeCmdElts) {
                        for (int i = 0; i < panel.getListe().getRowCount(); i++) {
                            final SQLRowValues rowAt = ITableModel.getLine(panel.getListe().getModel(), i).getRow();
                            final Number foreignID = rowAt.getNonEmptyForeignIDNumber("ID_FAMILLE_ARTICLE");
                            if (foreignID != null && foreignID.intValue() == 12) {
                                montantElec = montantElec.add(rowAt.getBigDecimal("T_PA_HT"));
                            } else {
                                montantMecaPneu = montantMecaPneu.add(rowAt.getBigDecimal("T_PA_HT"));
                            }
                        }
                    }
                    labelTotalMecaPneu.setText("Total cmde méca et pneu : " + GestionDevise.currencyToString(montantMecaPneu) + "€");
                    labelTotalElec.setText("Total cmde achats elec : " + GestionDevise.currencyToString(montantElec) + "€");

                }
            }, "COMMANDE_ELEMENT");

        }

    }

    private void installHistoryControls() {
        normalizeDisplayAction(this.listPanel, "DEVIS");
        normalizeDisplayAction(this.listPanel, "COMMANDE_CLIENT");
        normalizeDisplayAction(this.listPanel, "CHIFFRAGE_COMMANDE_CLIENT");
        normalizeDisplayAction(this.listPanel, "SAISIE_VENTE_FACTURE");
        normalizeDisplayAction(this.listPanel, "AVOIR_CLIENT");
        normalizeDisplayAction(this.listPanel, "DEMANDE_ACHAT_ELEMENT");
        normalizeDisplayAction(this.listPanel, "DEMANDE_PRIX");
        normalizeDisplayAction(this.listPanel, "COMMANDE_ELEMENT");
        normalizeDisplayAction(this.listPanel, "BON_RECEPTION_ELEMENT");
        normalizeDisplayAction(this.listPanel, "SAISIE_ACHAT");
        normalizeDisplayAction(this.listPanel, "AVOIR_FOURNISSEUR");
        normalizeDisplayAction(this.listPanel, "FACTURE_FOURNISSEUR");
        normalizeDisplayAction(this.listPanel, "FACTURE_FOURNISSEUR_ELEMENT");
        installModifyAction(this.listPanel, "AFFAIRE");
        installModifyAction(this.listPanel, "BON_DE_LIVRAISON");
        installModifyAction(this.listPanel, "COMMANDE");
        installModifyAction(this.listPanel, "BON_RECEPTION");
        normalizeDisplayAction(this.listPanel, "BON_DE_LIVRAISON");
        normalizeDisplayAction(this.listPanel, "COMMANDE");
        normalizeDisplayAction(this.listPanel, "BON_RECEPTION");
        installProjectListControls();
        installAffairListSort(true, true);
        installAffairListDateRenderer();
    }

    private static void putIfTableExists(final Map<String, List<String>> tabs, final String label, final String tableName) {
        try {
            final Configuration configuration = Configuration.getInstance();
            final SQLBase base = configuration instanceof ComptaPropsConfiguration ? ((ComptaPropsConfiguration) configuration).getSQLBaseSociete() : configuration.getBase();
            if (base != null && base.containsTable(tableName)) {
                tabs.put(label, Arrays.asList(tableName));
            }
        } catch (Exception e) {
            // Keep the module startup tolerant if a customer database misses one of the optional tables.
        }
    }

    private static void installModifyAction(final ListeHistoriquePanel historyPanel, final String tableName) {
        final List<IListPanel> panels = historyPanel.getAllIListePanelFromTableName(tableName);
        for (final IListPanel listPanel : panels) {
            normalizeDisplayAction(listPanel.getListe());
            final JButton button = listPanel.getButtonModify();
            if (button == null) {
                continue;
            }
            for (final ActionListener listener : button.getActionListeners()) {
                button.removeActionListener(listener);
            }
            button.setVisible(true);
            button.addActionListener(new ActionListener() {
                @Override
                public void actionPerformed(final ActionEvent e) {
                    openModificationFrame(listPanel);
                }
            });
        }
    }

    private static void openModificationFrame(final IListPanel listPanel) {
        final IListe list = listPanel.getListe();
        if (list == null || !list.hasSelection()) {
            return;
        }
        final int selectedId = list.getSelectedId();
        if (selectedId <= 1) {
            return;
        }
        final SQLElement element = listPanel.getElement();
        final EditFrame frame = new EditFrame(element, EditPanel.MODIFICATION);
        frame.selectionId(selectedId);
        FrameUtil.show(frame);
    }

    private void installProjectListControls() {
        final JSplitPane split = findSplitPane(this.listPanel);
        if (split == null) {
            return;
        }
        final Component left = split.getLeftComponent();
        if (left instanceof JPanel && "project-history-affair-left-panel".equals(left.getName())) {
            return;
        }

        final JComboBox sortCombo = new JComboBox(new String[] { "Par date", "Par nom" });
        sortCombo.setName("project-history-affair-sort-combo");
        sortCombo.setSelectedIndex(0);
        final JCheckBox hideClosedCheckBox = new JCheckBox("Masquer dossiers clos");
        hideClosedCheckBox.setName("project-history-affair-hide-closed-checkbox");
        hideClosedCheckBox.setOpaque(false);
        hideClosedCheckBox.setSelected(true);
        sortCombo.addActionListener(new ActionListener() {
            @Override
            public void actionPerformed(final ActionEvent e) {
                installAffairListSort(sortCombo.getSelectedIndex() == 0, hideClosedCheckBox.isSelected());
            }
        });
        hideClosedCheckBox.addActionListener(new ActionListener() {
            @Override
            public void actionPerformed(final ActionEvent e) {
                installAffairListSort(sortCombo.getSelectedIndex() == 0, hideClosedCheckBox.isSelected());
            }
        });

        final JPanel topPanel = new JPanel(new FlowLayout(FlowLayout.RIGHT, 4, 2));
        topPanel.setOpaque(false);
        topPanel.add(hideClosedCheckBox);
        topPanel.add(sortCombo);

        final JButton modifyButton = new JButton("Modifier l'affaire");
        modifyButton.addActionListener(new ActionListener() {
            @Override
            public void actionPerformed(final ActionEvent e) {
                openSelectedProject();
            }
        });

        final JPanel wrapper = new JPanel(new BorderLayout());
        wrapper.setName("project-history-affair-left-panel");
        wrapper.setOpaque(false);
        wrapper.add(topPanel, BorderLayout.NORTH);
        wrapper.add(left, BorderLayout.CENTER);
        wrapper.add(modifyButton, BorderLayout.SOUTH);
        split.setLeftComponent(wrapper);
        split.setDividerLocation(360);
        split.revalidate();
        split.repaint();
    }

    private void installAffairListDateRenderer() {
        final JListSQLTablePanel listPanel = findJListSQLTablePanel(this.listPanel);
        if (listPanel == null) {
            return;
        }
        final JList list = listPanel.getJList();
        if (list == null || "project-history-affair-date-renderer".equals(list.getName())) {
            return;
        }
        final ListCellRenderer delegate = list.getCellRenderer();
        final DateFormat dateFormat = new SimpleDateFormat("dd/MM/yyyy");
        list.setName("project-history-affair-date-renderer");
        list.setCellRenderer(new ListCellRenderer() {
            @Override
            public Component getListCellRendererComponent(final JList list, final Object value, final int index, final boolean isSelected, final boolean cellHasFocus) {
                final Component component = delegate.getListCellRendererComponent(list, value, index, isSelected, cellHasFocus);
                if (component instanceof JLabel && index >= 0 && list.getModel() instanceof JListSQLTableModel) {
                    final JLabel label = (JLabel) component;
                    final SQLRowAccessor row = ((JListSQLTableModel) list.getModel()).getRowAt(index);
                    label.setText(buildAffairDisplayText(row, label.getText(), dateFormat));
                }
                return component;
            }
        });
    }

    private void installAffairListSort(final boolean sortByDate, final boolean hideClosedProjects) {
        final JListSQLTablePanel listPanel = findJListSQLTablePanel(this.listPanel);
        if (listPanel == null || !(listPanel.getModel() instanceof JListSQLTableModel)) {
            return;
        }
        final JListSQLTableModel model = (JListSQLTableModel) listPanel.getModel();
        if (!"AFFAIRE".equalsIgnoreCase(model.getTable().getName())) {
            return;
        }
        try {
            final java.lang.reflect.Field compField = JListSQLTableModel.class.getDeclaredField("comp");
            compField.setAccessible(true);
            compField.set(model, sortByDate ? createAffairDateComparator(model) : createAffairNameComparator(model));
            installUndefinedRemoval(model, listPanel.getJList());
            model.setWhere(createAffairListWhere(model, hideClosedProjects));
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private static Where createAffairListWhere(final JListSQLTableModel model, final boolean hideClosedProjects) {
        Where where = new Where(model.getTable().getKey(), "!=", model.getTable().getUndefinedID());
        if (hideClosedProjects && model.getTable().contains("ID_ETAT_AFFAIRE")) {
            where = where.and(new Where(model.getTable().getField("ID_ETAT_AFFAIRE"), "!=", ProjectStateSQLElement.DOSSIER_CLOS));
        }
        return where;
    }

    private static void installUndefinedRemoval(final JListSQLTableModel model, final JList list) {
        if (Boolean.TRUE.equals(list.getClientProperty("project-history-affair-hide-undefined"))) {
            return;
        }
        list.putClientProperty("project-history-affair-hide-undefined", Boolean.TRUE);
        model.addListDataListener(new ListDataListener() {
            @Override
            public void intervalAdded(final ListDataEvent e) {
                removeLater();
            }

            @Override
            public void intervalRemoved(final ListDataEvent e) {
            }

            @Override
            public void contentsChanged(final ListDataEvent e) {
                removeLater();
            }

            private void removeLater() {
                SwingUtilities.invokeLater(new Runnable() {
                    @Override
                    public void run() {
                        removeUndefinedItem(model, list);
                    }
                });
            }
        });
        SwingUtilities.invokeLater(new Runnable() {
            @Override
            public void run() {
                removeUndefinedItem(model, list);
            }
        });
    }

    private static void removeUndefinedItem(final JListSQLTableModel model, final JList list) {
        for (int i = model.getSize() - 1; i >= 0; i--) {
            final Object item = model.getElementAt(i);
            if (item instanceof IComboSelectionItem && isUndefinedListItem(model, (IComboSelectionItem) item)) {
                removeModelItem(model, i);
            }
        }
        list.revalidate();
        list.repaint();
    }

    private static boolean isUndefinedListItem(final JListSQLTableModel model, final IComboSelectionItem item) {
        if (item == null) {
            return true;
        }
        final int id = item.getId();
        final String label = item.getLabel();
        return id <= 1 || id == model.getTable().getUndefinedID() || (label != null && "Indéfini".equalsIgnoreCase(label.trim()));
    }

    private static void removeModelItem(final JListSQLTableModel model, final int index) {
        try {
            final java.lang.reflect.Field listField = JListSQLTableModel.class.getDeclaredField("list");
            listField.setAccessible(true);
            final List items = (List) listField.get(model);
            if (index >= 0 && index < items.size()) {
                items.remove(index);
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private static Comparator<IComboSelectionItem> createAffairDateComparator(final JListSQLTableModel model) {
        final Map<Integer, Long> dates = new HashMap<Integer, Long>();
        return new Comparator<IComboSelectionItem>() {
            @Override
            public int compare(final IComboSelectionItem item1, final IComboSelectionItem item2) {
                if (isUndefined(model, item1)) {
                    return isUndefined(model, item2) ? 0 : 1;
                } else if (isUndefined(model, item2)) {
                    return -1;
                }
                final Long date1 = getItemDate(model, item1, dates);
                final Long date2 = getItemDate(model, item2, dates);
                final int dateCompare = compareNullableLongDesc(date1, date2);
                if (dateCompare != 0) {
                    return dateCompare;
                }
                return getItemNumero(model, item1).compareToIgnoreCase(getItemNumero(model, item2));
            }
        };
    }

    private static Comparator<IComboSelectionItem> createAffairNameComparator(final JListSQLTableModel model) {
        final Map<Integer, String> labels = new HashMap<Integer, String>();
        return new Comparator<IComboSelectionItem>() {
            @Override
            public int compare(final IComboSelectionItem item1, final IComboSelectionItem item2) {
                if (isUndefined(model, item1)) {
                    return isUndefined(model, item2) ? 0 : -1;
                } else if (isUndefined(model, item2)) {
                    return 1;
                }
                final String label1 = getItemSortLabel(model, item1, labels);
                final String label2 = getItemSortLabel(model, item2, labels);
                return label1.compareToIgnoreCase(label2);
            }
        };
    }

    private static boolean isUndefined(final JListSQLTableModel model, final IComboSelectionItem item) {
        if (item == null) {
            return true;
        }
        final int id = item.getId();
        return id < 0 || id == model.getTable().getUndefinedID();
    }

    private static Long getItemDate(final JListSQLTableModel model, final IComboSelectionItem item, final Map<Integer, Long> cache) {
        final Integer id = Integer.valueOf(item.getId());
        if (cache.containsKey(id)) {
            return cache.get(id);
        }
        Long result = null;
        try {
            SQLRowAccessor row = item.getRow();
            if (row == null || !row.getTable().contains("DATE")) {
                row = model.getTable().getRow(item.getId());
            }
            if (row != null) {
                final Calendar date = getBestDate(row);
                if (date != null) {
                    result = Long.valueOf(date.getTimeInMillis());
                }
            }
        } catch (Exception e) {
            result = null;
        }
        cache.put(id, result);
        return result;
    }

    private static int compareNullableLongDesc(final Long value1, final Long value2) {
        if (value1 == null) {
            return value2 == null ? 0 : 1;
        } else if (value2 == null) {
            return -1;
        }
        return value2.compareTo(value1);
    }

    private static String getItemSortLabel(final JListSQLTableModel model, final IComboSelectionItem item, final Map<Integer, String> cache) {
        final Integer id = Integer.valueOf(item.getId());
        if (cache.containsKey(id)) {
            return cache.get(id);
        }
        String result = item.getLabel() == null ? "" : item.getLabel();
        try {
            SQLRowAccessor row = item.getRow();
            if (row == null) {
                row = model.getTable().getRow(item.getId());
            }
            if (row != null) {
                result = getAffairLabel(row, result);
            }
        } catch (Exception e) {
            result = item.getLabel() == null ? "" : item.getLabel();
        }
        cache.put(id, result);
        return result;
    }

    private static String getItemNumero(final JListSQLTableModel model, final IComboSelectionItem item) {
        String result = item.getLabel() == null ? "" : item.getLabel();
        try {
            SQLRowAccessor row = item.getRow();
            if (row == null || !row.getTable().contains("NUMERO")) {
                row = model.getTable().getRow(item.getId());
            }
            final String numero = getString(row, "NUMERO");
            if (numero.length() > 0) {
                result = numero;
            }
        } catch (Exception e) {
            result = item.getLabel() == null ? "" : item.getLabel();
        }
        return result;
    }

    private static String buildAffairDisplayText(final SQLRowAccessor row, final String fallback, final DateFormat dateFormat) {
        if (row == null || !row.getTable().contains("DATE")) {
            return fallback;
        }
        final Calendar date = getBestDate(row);
        if (date == null) {
            return fallback;
        }
        final String label = getAffairLabel(row, fallback);
        return dateFormat.format(date.getTime()) + " " + label;
    }

    private static Calendar getBestDate(final SQLRowAccessor row) {
        if (row == null) {
            return null;
        }
        return row.getTable().contains("DATE") ? row.getDate("DATE") : null;
    }

    private static String getAffairLabel(final SQLRowAccessor row, final String fallback) {
        final String numero = getString(row, "NUMERO");
        final String client = getClientName(row);
        final String nom = getString(row, "NOM");
        if (numero.length() > 0 && client.length() > 0) {
            return numero + " " + client;
        } else if (nom.length() > 0 && client.length() > 0) {
            return nom + " " + client;
        } else if (client.length() > 0) {
            return client;
        }
        if (numero.length() > 0 && nom.length() > 0) {
            return numero + " " + nom;
        } else if (numero.length() > 0) {
            return numero;
        } else if (nom.length() > 0) {
            return nom;
        }
        return fallback;
    }

    private static String getClientName(final SQLRowAccessor row) {
        if (row == null || !row.getTable().contains("ID_CLIENT")) {
            return "";
        }
        try {
            final SQLRowAccessor client = row.getForeign("ID_CLIENT");
            if (client == null || client.isUndefined()) {
                return "";
            }
            final String nom = getString(client, "NOM");
            if (nom.length() > 0) {
                return nom;
            }
            return getString(client, "NOM_COURT");
        } catch (Exception e) {
            return "";
        }
    }

    private static String getString(final SQLRowAccessor row, final String fieldName) {
        if (row == null || !row.getTable().contains(fieldName)) {
            return "";
        }
        final String value = row.getString(fieldName);
        return value == null ? "" : value.trim();
    }

    private static JListSQLTablePanel findJListSQLTablePanel(final Container container) {
        for (final Component component : container.getComponents()) {
            if (component instanceof JListSQLTablePanel) {
                return (JListSQLTablePanel) component;
            }
            if (component instanceof Container) {
                final JListSQLTablePanel panel = findJListSQLTablePanel((Container) component);
                if (panel != null) {
                    return panel;
                }
            }
        }
        return null;
    }

    private void openSelectedProject() {
        final SQLRowAccessor row = this.listPanel.getSelectedRow();
        if (row == null || row.getID() <= 1) {
            return;
        }
        final SQLElement element = Configuration.getInstance().getDirectory().getElement("AFFAIRE");
        final EditFrame frame = new EditFrame(element, EditPanel.MODIFICATION);
        frame.selectionId(row.getID());
        FrameUtil.show(frame);
    }

    private static JSplitPane findSplitPane(final Container container) {
        for (final Component component : container.getComponents()) {
            if (component instanceof JSplitPane) {
                return (JSplitPane) component;
            }
            if (component instanceof Container) {
                final JSplitPane split = findSplitPane((Container) component);
                if (split != null) {
                    return split;
                }
            }
        }
        return null;
    }

    private static void normalizeDisplayAction(final ListeHistoriquePanel historyPanel, final String tableName) {
        final List<IListPanel> panels = historyPanel.getAllIListePanelFromTableName(tableName);
        for (final IListPanel listPanel : panels) {
            normalizeDisplayAction(listPanel.getListe());
        }
    }

    private static void normalizeDisplayAction(final IListe list) {
        if (list == null) {
            return;
        }
        final IListeAction rowAction = list.getDefaultRowAction();
        if (!(rowAction instanceof RowAction)) {
            return;
        }
        final Action action = ((RowAction) rowAction).getAction();
        if (action == null) {
            return;
        }
        final Object name = action.getValue(Action.NAME);
        if (name == null || "display".equals(name) || "!display!".equals(name) || name.toString().contains("display")) {
            action.putValue(Action.NAME, "Afficher");
        }
    }

    public PanelFrame getFrame() {
        this.panelFrame.setIconImages(Gestion.getFrameIcon());
        final WindowStateManager stateManager = new WindowStateManager(this.panelFrame,
                new File(Configuration.getInstance().getConfDir(), "Configuration" + File.separator + "Frame" + File.separator + "HistoAffaires.xml"), true);
        this.panelFrame.setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
        this.panelFrame.pack();
        this.panelFrame.setLocationRelativeTo(null);
        stateManager.loadState();
        return this.panelFrame;
    }
}
