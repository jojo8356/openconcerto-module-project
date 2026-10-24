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
import java.lang.reflect.Field;
import java.math.BigDecimal;
import java.text.DateFormat;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Calendar;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import javax.swing.Action;
import javax.swing.AbstractAction;
import javax.swing.JButton;
import javax.swing.JCheckBox;
import javax.swing.JComboBox;
import javax.swing.DefaultComboBoxModel;
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
import org.openconcerto.sql.model.SQLRow;
import org.openconcerto.sql.model.SQLRowListRSH;
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
    private static final String FAMILY_FILTER_COMMANDE_KEY = "project-history-family-filter-commande";
    private static final String FAMILY_FILTER_BON_RECEPTION_KEY = "project-history-family-filter-bon-reception";

    private PanelFrame panelFrame;
    private ListeHistoriquePanel listPanel;
    private final SQLBase sqlBase;

    public ListeHistoriquePanel getHistoriquePanel() {
        return this.listPanel;
    }

    private static Map<String, List<String>> moduleTab = new HashMap<String, List<String>>();

    public static void addTab(String tabName, List<String> table) {
        moduleTab.put(tabName, table);
    }

    @SuppressWarnings("deprecation")
    public ProjectHistory() {

        // Bouton "Transfert en commande fournisseur" : il doit etre enregistre
        // sur l'element DEMANDE_PRIX AVANT la creation des listes, car les
        // actions de liste sont lues a ce moment-la.
        TransfertDemandePrixAction.install();

        final ComptaPropsConfiguration comptaPropsConfiguration = ((ComptaPropsConfiguration) Configuration.getInstance());
        final SQLBase b = comptaPropsConfiguration.getSQLBaseSociete();
        this.sqlBase = b;

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
        putIfTableExists(mapList, "Factures fournisseurs", "FACTURE_FOURNISSEUR");

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
        // Keep family split tabs disabled: they create one list per article family at startup.
        // Family filtering is now handled by a single dynamic combo box below.

        // if (Configuration.getInstance().getRoot().findTable("POINTAGE") != null) {
        // fieldLink.put(b.getTable("POINTAGE"),
        // b.getTable("POINTAGE_ELEMENT").getField("ID_POINTAGE"));
        // }

        this.listPanel = new ListeHistoriquePanel("Affaires", request, mapList, bilanPanel, fieldLink, null, true, null, null, splitter);

        // Bouton de transfert demande de prix -> commande : on l'ajoute aussi
        // directement sur la liste (menu contextuel), en plus de l'action de
        // l'element, pour qu'il soit visible meme si l'element n'a pas encore
        // d'action de liste.
        final IListPanel listeDemandePrix = listPanel.getIListePanelFromTableName("DEMANDE_PRIX");
        if (listeDemandePrix != null) {
            listeDemandePrix.getListe().addRowAction(new TransfertDemandePrixAction.DemandePrixTransfertAction());
        }

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
                removeColumnByName(listeCmdElt, "Nom");

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

    private static void removeColumnByName(final IListPanel listPanel, final String columnName) {
        if (listPanel == null || columnName == null) {
            return;
        }
        final List<SQLTableModelColumn> columns = listPanel.getListe().getSource().getColumns();
        for (int i = columns.size() - 1; i >= 0; i--) {
            if (columnName.equalsIgnoreCase(columns.get(i).getName())) {
                columns.remove(i);
            }
        }
    }

    private void installHistoryControls() {
        installElementRowActions(this.listPanel, "COMMANDE_CLIENT");
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
        installSupplierInvoiceItemSupplierNameColumn(this.listPanel);
        installSupplierInvoiceOrderNumberColumn(this.listPanel);
        installModifyAction(this.listPanel, "AFFAIRE");
        installModifyAction(this.listPanel, "BON_DE_LIVRAISON");
        installModifyAction(this.listPanel, "COMMANDE");
        installModifyAction(this.listPanel, "BON_RECEPTION");
        normalizeDisplayAction(this.listPanel, "BON_DE_LIVRAISON");
        normalizeDisplayAction(this.listPanel, "COMMANDE");
        normalizeDisplayAction(this.listPanel, "BON_RECEPTION");
        installProjectListControls(this.sqlBase);
        installArticleFamilyFilters(this.sqlBase);
        installAffairListSort(AffairListSortSupport.DEFAULT_SORT_BY_DATE, true);
        installAffairListDateRenderer();
    }

    private static void installElementRowActions(final ListeHistoriquePanel historyPanel, final String tableName) {
        final List<IListPanel> panels = historyPanel.getAllIListePanelFromTableName(tableName);
        for (final IListPanel listPanel : panels) {
            final IListe liste = listPanel.getListe();
            if (liste == null || Boolean.TRUE.equals(liste.getClientProperty("project-history-row-actions-installed-" + tableName))) {
                continue;
            }
            liste.addIListeActions(listPanel.getElement().getRowActions());
            liste.putClientProperty("project-history-row-actions-installed-" + tableName, Boolean.TRUE);
        }
    }

    @SuppressWarnings("deprecation")
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

    private static void installSupplierInvoiceItemSupplierNameColumn(final ListeHistoriquePanel historyPanel) {
        final List<IListPanel> panels = historyPanel.getAllIListePanelFromTableName("FACTURE_FOURNISSEUR_ELEMENT");
        for (final IListPanel panel : panels) {
            final SQLTable primaryTable = panel.getListe().getSource().getPrimaryTable();
            if (primaryTable == null || !primaryTable.contains("ID_FACTURE_FOURNISSEUR")) {
                continue;
            }
            final List<SQLTableModelColumn> columns = panel.getListe().getSource().getColumns();
            int nameColumnIndex = -1;
            for (int i = 0; i < columns.size(); i++) {
                if ("Nom".equalsIgnoreCase(columns.get(i).getName())) {
                    nameColumnIndex = i;
                    break;
                }
            }
            if (nameColumnIndex >= 0) {
                columns.remove(nameColumnIndex);
            } else {
                nameColumnIndex = 0;
            }
            columns.add(nameColumnIndex, new BaseSQLTableModelColumn("Nom", String.class) {

                @Override
                protected Object show_(final SQLRowAccessor r) {
                    final SQLRowAccessor invoice = r.getNonEmptyForeign("ID_FACTURE_FOURNISSEUR");
                    if (invoice == null) {
                        return "";
                    }
                    final SQLRowAccessor supplier = invoice.getNonEmptyForeign("ID_FOURNISSEUR");
                    if (supplier != null && supplier.getTable().contains("NOM")) {
                        return supplier.getString("NOM");
                    }
                    return invoice.getTable().contains("NOM") ? invoice.getString("NOM") : "";
                }

                @Override
                public Set<FieldPath> getPaths() {
                    Path p = new Path(primaryTable);
                    final SQLTable invoiceTable = primaryTable.getBase().getTable("FACTURE_FOURNISSEUR");
                    final Path invoicePath = p.add(primaryTable.getField("ID_FACTURE_FOURNISSEUR"));
                    if (invoiceTable.contains("ID_FOURNISSEUR") && primaryTable.getBase().containsTable("FOURNISSEUR")) {
                        final Path supplierPath = invoicePath.add(invoiceTable.getField("ID_FOURNISSEUR"));
                        return CollectionUtils.createSet(new FieldPath(supplierPath, "NOM"));
                    }
                    return CollectionUtils.createSet(new FieldPath(invoicePath, "NOM"));
                }
            });
        }
    }

    // Adds a "N° commande fournisseur" column to the "Factures fournisseurs" tab so each supplier
    // invoice shows the number of the supplier order (COMMANDE) it was transferred from, as
    // displayed in the "Commandes fournisseurs" tab.
    private static void installSupplierInvoiceOrderNumberColumn(final ListeHistoriquePanel historyPanel) {
        final List<IListPanel> panels = historyPanel.getAllIListePanelFromTableName("FACTURE_FOURNISSEUR");
        if (panels == null || panels.isEmpty()) {
            return;
        }
        for (final IListPanel panel : panels) {
            final SQLTable invoiceTable = panel.getListe().getSource().getPrimaryTable();
            if (invoiceTable == null) {
                continue;
            }
            final SQLBase base = invoiceTable.getBase();
            if (!base.containsTable("COMMANDE") || !base.getTable("COMMANDE").contains("NUMERO")) {
                continue;
            }
            // Main link: the OpenConcerto transfer table filled by "Transférer en facture
            // fournisseur" on a supplier order.
            final SQLTable transferTable = base.containsTable("TR_COMMANDE") ? base.getTable("TR_COMMANDE") : null;
            final boolean useTransferLink = transferTable != null && transferTable.contains("ID_COMMANDE") && transferTable.contains("ID_FACTURE_FOURNISSEUR");
            // Fallback link: invoice items keep a reference to the order item they come from
            // (FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT -> COMMANDE_ELEMENT.ID_COMMANDE).
            final SQLTable invoiceItemTable = base.containsTable("FACTURE_FOURNISSEUR_ELEMENT") ? base.getTable("FACTURE_FOURNISSEUR_ELEMENT") : null;
            final SQLTable orderItemTable = base.containsTable("COMMANDE_ELEMENT") ? base.getTable("COMMANDE_ELEMENT") : null;
            final boolean useItemLink = invoiceItemTable != null && orderItemTable != null && invoiceItemTable.contains("ID_FACTURE_FOURNISSEUR")
                    && invoiceItemTable.contains("ID_COMMANDE_ELEMENT") && orderItemTable.contains("ID_COMMANDE");
            if (!useTransferLink && !useItemLink) {
                continue;
            }
            final List<SQLTableModelColumn> columns = panel.getListe().getSource().getColumns();
            // Show the order number right after the invoice number when possible.
            int insertIndex = columns.size();
            if (invoiceTable.contains("NUMERO")) {
                final SQLField invoiceNumberField = invoiceTable.getField("NUMERO");
                for (int i = 0; i < columns.size(); i++) {
                    if (columns.get(i).getFields().contains(invoiceNumberField)) {
                        insertIndex = i + 1;
                        break;
                    }
                }
            }
            columns.add(insertIndex, new BaseSQLTableModelColumn("N° commande fournisseur", String.class) {

                @Override
                protected Object show_(final SQLRowAccessor r) {
                    final Set<String> orderNumbers = new LinkedHashSet<String>();
                    if (useTransferLink) {
                        for (final SQLRowAccessor transferRow : r.getReferentRows(transferTable.getField("ID_FACTURE_FOURNISSEUR"))) {
                            addOrderNumber(orderNumbers, transferRow.getNonEmptyForeign("ID_COMMANDE"));
                        }
                    }
                    if (orderNumbers.isEmpty() && useItemLink) {
                        for (final SQLRowAccessor invoiceItem : r.getReferentRows(invoiceItemTable.getField("ID_FACTURE_FOURNISSEUR"))) {
                            final SQLRowAccessor orderItem = invoiceItem.getNonEmptyForeign("ID_COMMANDE_ELEMENT");
                            if (orderItem != null) {
                                addOrderNumber(orderNumbers, orderItem.getNonEmptyForeign("ID_COMMANDE"));
                            }
                        }
                    }
                    return CollectionUtils.join(new ArrayList<String>(orderNumbers), ", ");
                }

                @Override
                public Set<FieldPath> getPaths() {
                    final Set<FieldPath> paths = new HashSet<FieldPath>();
                    if (useTransferLink) {
                        final Path transferPath = new Path(invoiceTable).add(transferTable.getField("ID_FACTURE_FOURNISSEUR")).add(transferTable.getField("ID_COMMANDE"));
                        paths.add(new FieldPath(transferPath, "NUMERO"));
                    }
                    if (useItemLink) {
                        final Path itemPath = new Path(invoiceTable).add(invoiceItemTable.getField("ID_FACTURE_FOURNISSEUR")).add(invoiceItemTable.getField("ID_COMMANDE_ELEMENT"))
                                .add(orderItemTable.getField("ID_COMMANDE"));
                        paths.add(new FieldPath(itemPath, "NUMERO"));
                    }
                    return paths;
                }
            });
        }
    }

    private static void addOrderNumber(final Set<String> orderNumbers, final SQLRowAccessor orderRow) {
        if (orderRow == null || !orderRow.getTable().contains("NUMERO")) {
            return;
        }
        final String number = orderRow.getString("NUMERO");
        if (number != null && number.trim().length() > 0) {
            orderNumbers.add(number.trim());
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

    private void installArticleFamilyFilters(final SQLBase base) {
        if (this.listPanel == null || base == null || !base.containsTable("FAMILLE_ARTICLE")) {
            return;
        }
        final SQLTable familyTable = base.getTable("FAMILLE_ARTICLE");
        final Map<Integer, FamilyItem> familyItems = loadArticleFamilies(familyTable);
        if (familyItems.isEmpty()) {
            return;
        }
        installArticleFamilyFilter(base, "COMMANDE_ELEMENT", "COMMANDE", "ID_COMMANDE", FAMILY_FILTER_COMMANDE_KEY, familyItems);
        installArticleFamilyFilter(base, "BON_RECEPTION_ELEMENT", "BON_RECEPTION", "ID_BON_RECEPTION", FAMILY_FILTER_BON_RECEPTION_KEY, familyItems);
    }

    private void installArticleFamilyFilter(final SQLBase base, final String itemTableName, final String parentTableName, final String parentFieldName, final String filterKey,
            final Map<Integer, FamilyItem> familyItems) {
        if (!base.containsTable(itemTableName) || !base.containsTable(parentTableName)) {
            return;
        }
        final SQLTable itemTable = base.getTable(itemTableName);
        if (!hasFamilyField(itemTable) || !itemTable.contains(parentFieldName)) {
            return;
        }
        final IListPanel panel = this.listPanel.getIListePanelFromTableName(itemTableName);
        if (panel == null) {
            return;
        }
        final Map<Integer, List<FamilyItem>> familiesByAffair = loadUsedArticleFamilies(base, itemTable, base.getTable(parentTableName), parentFieldName, familyItems);
        final JPanel filterPanel = createArticleFamilyFilterPanel(itemTable, filterKey, familiesByAffair);
        if (filterPanel == null) {
            return;
        }
        addArticleFamilyFilterPanel(panel, filterPanel);
    }

    private JPanel createArticleFamilyFilterPanel(final SQLTable itemTable, final String filterKey, final Map<Integer, List<FamilyItem>> familiesByAffair) {
        if (itemTable == null || filterKey == null || familiesByAffair == null) {
            return null;
        }

        final JComboBox<FamilyItem> familyCombo = new JComboBox<FamilyItem>();
        familyCombo.setName("project-history-article-family-filter-combo-" + itemTable.getName());
        final boolean[] comboUpdating = new boolean[] { false };
        familyCombo.addActionListener(new ActionListener() {
            @Override
            public void actionPerformed(final ActionEvent e) {
                if (comboUpdating[0]) {
                    return;
                }
                final Object selected = familyCombo.getSelectedItem();
                if (selected instanceof FamilyItem) {
                    applyArticleFamilyFilter(filterKey, itemTable, (FamilyItem) selected);
                }
            }
        });

        final JPanel filterPanel = new JPanel(new FlowLayout(FlowLayout.LEFT, 4, 2));
        filterPanel.setOpaque(false);
        filterPanel.add(new JLabel("Famille article"));
        filterPanel.add(familyCombo);
        this.listPanel.addListSelectionListener(new ListSelectionListener() {
            @Override
            public void valueChanged(final ListSelectionEvent e) {
                if (e != null && e.getValueIsAdjusting()) {
                    return;
                }
                updateArticleFamilyCombo(familyCombo, familiesByAffair, comboUpdating, filterKey, itemTable);
            }
        });
        updateArticleFamilyCombo(familyCombo, familiesByAffair, comboUpdating, filterKey, itemTable);
        return filterPanel;
    }

    private static void addArticleFamilyFilterPanel(final IListPanel listPanel, final JPanel filterPanel) {
        try {
            final Field searchPanelField = IListPanel.class.getDeclaredField("searchPanel");
            searchPanelField.setAccessible(true);
            final Object searchPanelObject = searchPanelField.get(listPanel);
            if (searchPanelObject instanceof JPanel) {
                final JPanel searchPanel = (JPanel) searchPanelObject;
                final GridBagConstraints c = new GridBagConstraints();
                c.gridx = 0;
                c.gridy = 1;
                c.gridwidth = GridBagConstraints.REMAINDER;
                c.weightx = 1;
                c.fill = GridBagConstraints.HORIZONTAL;
                c.insets = new Insets(2, 0, 2, 0);
                searchPanel.add(filterPanel, c);
                searchPanel.revalidate();
                searchPanel.repaint();
                return;
            }
        } catch (Exception e) {
            // Older OpenConcerto builds can move the search panel internals; fall back to the list panel.
        }
        final GridBagConstraints c = new DefaultGridBagConstraints();
        c.gridx = 0;
        c.gridy = 2;
        c.gridwidth = GridBagConstraints.REMAINDER;
        c.weightx = 1;
        c.fill = GridBagConstraints.HORIZONTAL;
        listPanel.add(filterPanel, c);
        listPanel.revalidate();
        listPanel.repaint();
    }

    private static boolean hasFamilyField(final SQLTable table) {
        return table != null && table.contains("ID_FAMILLE_ARTICLE");
    }

    private static Map<Integer, FamilyItem> loadArticleFamilies(final SQLTable familyTable) {
        final Map<Integer, FamilyItem> result = new HashMap<Integer, FamilyItem>();
        try {
            final SQLSelect select = new SQLSelect();
            select.addSelectStar(familyTable);
            if (familyTable.contains("NOM")) {
                select.addFieldOrder(familyTable.getField("NOM"));
            }
            final List<SQLRow> rows = SQLRowListRSH.execute(select);
            for (final SQLRow row : rows) {
                if (row == null || row.isUndefined()) {
                    continue;
                }
                final String name = row.contains("NOM") ? row.getString("NOM") : null;
                final String label = name == null || name.trim().length() == 0 ? "Famille " + row.getID() : name.trim();
                result.put(Integer.valueOf(row.getID()), new FamilyItem(row.getID(), label));
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return result;
    }

    private Map<Integer, List<FamilyItem>> loadUsedArticleFamilies(final SQLBase base, final SQLTable itemTable, final SQLTable parentTable, final String parentFieldName,
            final Map<Integer, FamilyItem> familyItems) {
        final Map<Integer, Map<Integer, FamilyItem>> byAffair = new HashMap<Integer, Map<Integer, FamilyItem>>();
        if (base == null || itemTable == null || parentTable == null || parentFieldName == null || !hasFamilyField(itemTable) || !itemTable.contains(parentFieldName)
                || !parentTable.contains("ID_AFFAIRE")) {
            return new HashMap<Integer, List<FamilyItem>>();
        }
        final String sql = "select distinct p.\"ID_AFFAIRE\", e.\"ID_FAMILLE_ARTICLE\" from " + itemTable.getSQLName().quote() + " e join " + parentTable.getSQLName().quote()
                + " p on e.\"" + parentFieldName + "\" = p.\"ID\" where p.\"ID_AFFAIRE\" > 1 and e.\"ID_FAMILLE_ARTICLE\" > 1";
        addUsedArticleFamilies(byAffair, familyItems, base.getDataSource().executeA(sql));

        final Map<Integer, List<FamilyItem>> result = new HashMap<Integer, List<FamilyItem>>();
        for (final Map.Entry<Integer, Map<Integer, FamilyItem>> entry : byAffair.entrySet()) {
            final List<FamilyItem> items = new java.util.ArrayList<FamilyItem>(entry.getValue().values());
            java.util.Collections.sort(items);
            result.put(entry.getKey(), items);
        }
        return result;
    }

    private static void addUsedArticleFamilies(final Map<Integer, Map<Integer, FamilyItem>> byAffair, final Map<Integer, FamilyItem> familyItems, final List rows) {
        for (final Object rowObject : rows) {
            if (!(rowObject instanceof Object[])) {
                continue;
            }
            final Object[] row = (Object[]) rowObject;
            if (row.length < 2 || !(row[0] instanceof Number) || !(row[1] instanceof Number)) {
                continue;
            }
            final Integer affairID = Integer.valueOf(((Number) row[0]).intValue());
            final Integer familyID = Integer.valueOf(((Number) row[1]).intValue());
            final FamilyItem family = familyItems.get(familyID);
            if (family == null) {
                continue;
            }
            Map<Integer, FamilyItem> families = byAffair.get(affairID);
            if (families == null) {
                families = new HashMap<Integer, FamilyItem>();
                byAffair.put(affairID, families);
            }
            families.put(familyID, family);
        }
    }

    private void updateArticleFamilyCombo(final JComboBox<FamilyItem> familyCombo, final Map<Integer, List<FamilyItem>> familiesByAffair, final boolean[] comboUpdating, final String filterKey,
            final SQLTable itemTable) {
        final SQLRowAccessor row = this.listPanel.getSelectedRow();
        final List<FamilyItem> currentFamilies = row == null ? null : familiesByAffair.get(Integer.valueOf(row.getID()));
        final List<FamilyItem> items = new java.util.ArrayList<FamilyItem>();
        items.add(FamilyItem.ALL);
        if (currentFamilies != null) {
            items.addAll(currentFamilies);
        }
        comboUpdating[0] = true;
        try {
            familyCombo.setModel(new DefaultComboBoxModel<FamilyItem>(items.toArray(new FamilyItem[items.size()])));
            familyCombo.setSelectedIndex(0);
        } finally {
            comboUpdating[0] = false;
        }
        applyArticleFamilyFilter(filterKey, itemTable, FamilyItem.ALL);
    }

    private void applyArticleFamilyFilter(final String filterKey, final SQLTable itemTable, final FamilyItem selected) {
        if (selected == null || selected.isAll()) {
            this.listPanel.removeWhere(filterKey);
            return;
        }
        if (hasFamilyField(itemTable)) {
            this.listPanel.addWhere(filterKey, new Where(itemTable.getField("ID_FAMILLE_ARTICLE"), "=", selected.getID()));
        }
    }

    private void installProjectListControls(final SQLBase base) {
        final JSplitPane split = findSplitPane(this.listPanel);
        if (split == null) {
            return;
        }
        final Component left = split.getLeftComponent();
        if (left instanceof JPanel && "project-history-affair-left-panel".equals(left.getName())) {
            return;
        }

        final JComboBox<String> sortCombo = new JComboBox<String>(new String[] { "Tri par date", "Tri par nom" });
        sortCombo.setName("project-history-affair-sort-combo");
        sortCombo.setSelectedIndex(AffairListSortSupport.DEFAULT_SORT_COMBO_INDEX);
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

        final JPanel northPanel = new JPanel(new BorderLayout());
        northPanel.setOpaque(false);
        northPanel.add(topPanel, BorderLayout.NORTH);

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
        wrapper.add(northPanel, BorderLayout.NORTH);
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
        final JList<?> list = listPanel.getJList();
        if (list == null || "project-history-affair-date-renderer".equals(list.getName())) {
            return;
        }
        final ListCellRenderer<Object> delegate = castListCellRenderer(list.getCellRenderer());
        final DateFormat dateFormat = new SimpleDateFormat("dd/MM/yyyy");
        final Map<Integer, String> displayTextCache = new HashMap<Integer, String>();
        list.getModel().addListDataListener(new ListDataListener() {
            @Override
            public void intervalAdded(final ListDataEvent e) {
                displayTextCache.clear();
            }

            @Override
            public void intervalRemoved(final ListDataEvent e) {
                displayTextCache.clear();
            }

            @Override
            public void contentsChanged(final ListDataEvent e) {
                displayTextCache.clear();
            }
        });
        list.setName("project-history-affair-date-renderer");
        setRawListCellRenderer(list, new ListCellRenderer<Object>() {
            @Override
            public Component getListCellRendererComponent(final JList<?> list, final Object value, final int index, final boolean isSelected, final boolean cellHasFocus) {
                final Component component = delegate.getListCellRendererComponent(list, value, index, isSelected, cellHasFocus);
                if (component instanceof JLabel && index >= 0 && list.getModel() instanceof JListSQLTableModel) {
                    final JLabel label = (JLabel) component;
                    final SQLRowAccessor row = ((JListSQLTableModel) list.getModel()).getRowAt(index);
                    if (row != null) {
                        final Integer id = Integer.valueOf(row.getID());
                        String text = displayTextCache.get(id);
                        if (text == null) {
                            text = buildAffairDisplayText(row, label.getText(), dateFormat);
                            displayTextCache.put(id, text);
                        }
                        label.setText(text);
                    }
                }
                return component;
            }
        });
    }

    @SuppressWarnings("unchecked")
    private static ListCellRenderer<Object> castListCellRenderer(final ListCellRenderer<?> renderer) {
        return (ListCellRenderer<Object>) renderer;
    }

    @SuppressWarnings({ "unchecked", "rawtypes" })
    private static void setRawListCellRenderer(final JList<?> list, final ListCellRenderer<Object> renderer) {
        ((JList) list).setCellRenderer(renderer);
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
        final Map<Integer, AffairSortValue> values = loadAffairSortValues(model.getTable());
        final Comparator<AffairListSortSupport.Item> comparator = AffairListSortSupport.createDateComparator(model.getTable().getUndefinedID());
        return new Comparator<IComboSelectionItem>() {
            @Override
            public int compare(final IComboSelectionItem item1, final IComboSelectionItem item2) {
                return comparator.compare(toSortItem(item1, getAffairSortValue(item1, values)), toSortItem(item2, getAffairSortValue(item2, values)));
            }
        };
    }

    private static Comparator<IComboSelectionItem> createAffairNameComparator(final JListSQLTableModel model) {
        final Map<Integer, AffairSortValue> values = loadAffairSortValues(model.getTable());
        final Comparator<AffairListSortSupport.Item> comparator = AffairListSortSupport.createNameComparator(model.getTable().getUndefinedID());
        return new Comparator<IComboSelectionItem>() {
            @Override
            public int compare(final IComboSelectionItem item1, final IComboSelectionItem item2) {
                return comparator.compare(toSortItem(item1, getAffairSortValue(item1, values)), toSortItem(item2, getAffairSortValue(item2, values)));
            }
        };
    }

    private static AffairListSortSupport.Item toSortItem(final IComboSelectionItem item, final AffairSortValue value) {
        if (item == null) {
            return null;
        }
        final Long date = value == null ? null : value.date;
        return new AffairListSortSupport.Item(item.getId(), date, getItemNumero(item, value), getItemSortLabel(item, value));
    }

    private static Map<Integer, AffairSortValue> loadAffairSortValues(final SQLTable affairTable) {
        final Map<Integer, AffairSortValue> result = new HashMap<Integer, AffairSortValue>();
        if (affairTable == null) {
            return result;
        }
        try {
            final StringBuilder sql = new StringBuilder();
            sql.append("select a.\"ID\", a.\"DATE\", a.\"NUMERO\", a.\"NOM\"");
            final boolean joinClient = affairTable.contains("ID_CLIENT") && affairTable.getBase().containsTable("CLIENT");
            final SQLTable clientTable = joinClient ? affairTable.getBase().getTable("CLIENT") : null;
            final boolean clientHasShortName = clientTable != null && clientTable.contains("NOM_COURT");
            if (joinClient) {
                sql.append(", c.\"NOM\"");
                if (clientHasShortName) {
                    sql.append(", c.\"NOM_COURT\"");
                }
            }
            sql.append(" from ").append(affairTable.getSQLName().quote()).append(" a");
            if (joinClient) {
                sql.append(" left join ").append(clientTable.getSQLName().quote()).append(" c on a.\"ID_CLIENT\" = c.\"ID\"");
            }
            sql.append(" where a.\"ID\" > 1");

            final List rows = affairTable.getBase().getDataSource().executeA(sql.toString());
            for (final Object rowObject : rows) {
                if (!(rowObject instanceof Object[])) {
                    continue;
                }
                final Object[] row = (Object[]) rowObject;
                if (row.length < 4 || !(row[0] instanceof Number)) {
                    continue;
                }
                final int id = ((Number) row[0]).intValue();
                final Long date = toMillis(row[1]);
                final String numero = toTrimmedString(row[2]);
                final String nom = toTrimmedString(row[3]);
                final String clientName = joinClient && row.length > 4 ? firstNonEmpty(toTrimmedString(row[4]), clientHasShortName && row.length > 5 ? toTrimmedString(row[5]) : "") : "";
                final String label = AffairListSortSupport.buildLabel(numero, clientName, nom, "");
                result.put(Integer.valueOf(id), new AffairSortValue(date, numero, label));
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return result;
    }

    private static AffairSortValue getAffairSortValue(final IComboSelectionItem item, final Map<Integer, AffairSortValue> values) {
        return item == null ? null : values.get(Integer.valueOf(item.getId()));
    }

    private static Long toMillis(final Object value) {
        if (value instanceof java.util.Date) {
            return Long.valueOf(((java.util.Date) value).getTime());
        }
        if (value instanceof Calendar) {
            return Long.valueOf(((Calendar) value).getTimeInMillis());
        }
        return null;
    }

    private static String toTrimmedString(final Object value) {
        return value == null ? "" : value.toString().trim();
    }

    private static String firstNonEmpty(final String value1, final String value2) {
        return value1.length() > 0 ? value1 : value2;
    }

    private static String getItemSortLabel(final IComboSelectionItem item, final AffairSortValue value) {
        if (value != null && value.label.length() > 0) {
            return value.label;
        }
        String result = item.getLabel() == null ? "" : item.getLabel();
        try {
            SQLRowAccessor row = item.getRow();
            if (row != null) {
                result = getAffairLabel(row, result);
            }
        } catch (Exception e) {
            result = item.getLabel() == null ? "" : item.getLabel();
        }
        return result;
    }

    private static String getItemNumero(final IComboSelectionItem item, final AffairSortValue value) {
        if (value != null && value.numero.length() > 0) {
            return value.numero;
        }
        String result = item.getLabel() == null ? "" : item.getLabel();
        try {
            SQLRowAccessor row = item.getRow();
            if (row != null && row.getTable().contains("NUMERO")) {
                final String numero = getString(row, "NUMERO");
                if (numero.length() > 0) {
                    result = numero;
                }
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
        return AffairListSortSupport.buildLabel(numero, client, nom, fallback);
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

    private static final class FamilyItem implements Comparable<FamilyItem> {
        static final FamilyItem ALL = new FamilyItem(-1, "Toutes les familles");

        private final int id;
        private final String label;

        FamilyItem(final int id, final String label) {
            this.id = id;
            this.label = label;
        }

        int getID() {
            return this.id;
        }

        boolean isAll() {
            return this.id < 0;
        }

        @Override
        public String toString() {
            return this.label;
        }

        @Override
        public int compareTo(final FamilyItem other) {
            if (other == null) {
                return -1;
            }
            return this.label.compareToIgnoreCase(other.label);
        }
    }

    private static final class AffairSortValue {
        private final Long date;
        private final String numero;
        private final String label;

        AffairSortValue(final Long date, final String numero, final String label) {
            this.date = date;
            this.numero = numero == null ? "" : numero;
            this.label = label == null ? "" : label;
        }
    }
}
