package org.openconcerto.modules.project;

import java.awt.Color;
import java.awt.GridBagConstraints;
import java.awt.GridBagLayout;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.beans.PropertyChangeEvent;
import java.beans.PropertyChangeListener;
import java.io.IOException;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.Set;

import javax.swing.AbstractAction;
import javax.swing.JButton;
import javax.swing.JComponent;
import javax.swing.JFrame;
import javax.swing.JLabel;
import javax.swing.JOptionPane;
import javax.swing.JPanel;
import javax.swing.JScrollPane;
import javax.swing.SwingUtilities;

import org.openconcerto.erp.action.CreateFrameAbstractAction;
import org.openconcerto.erp.config.ComptaPropsConfiguration;
import org.openconcerto.erp.config.MainFrame;
import org.openconcerto.erp.core.common.element.NumerotationAutoSQLElement;
import org.openconcerto.erp.core.sales.invoice.ui.SaisieVenteFactureItemTable;
import org.openconcerto.erp.core.sales.order.ui.CommandeClientItemTable;
import org.openconcerto.erp.core.sales.quote.component.DevisSQLComponent;
import org.openconcerto.erp.core.sales.quote.element.DevisSQLElement;
import org.openconcerto.erp.core.sales.quote.element.EtatDevisSQLElement;
import org.openconcerto.erp.core.sales.quote.report.DevisXmlSheet;
import org.openconcerto.erp.generationEcritures.GenerationMvtSaisieVenteFacture;
import org.openconcerto.erp.generationEcritures.provider.AccountingRecordsProvider;
import org.openconcerto.erp.generationEcritures.provider.AccountingRecordsProviderManager;
import org.openconcerto.erp.model.MouseSheetXmlListeListener;
import org.openconcerto.erp.modules.AbstractModule;
import org.openconcerto.erp.modules.AlterTableRestricted;
import org.openconcerto.erp.modules.ComponentsContext;
import org.openconcerto.erp.modules.DBContext;
import org.openconcerto.erp.modules.MenuContext;
import org.openconcerto.erp.modules.ModuleFactory;
import org.openconcerto.modules.project.element.ProjectSQLElement;
import org.openconcerto.modules.project.element.ProjectStateSQLElement;
import org.openconcerto.modules.project.element.ProjectTypeSQLElement;
import org.openconcerto.sql.Configuration;
import org.openconcerto.sql.element.SQLComponent;
import org.openconcerto.sql.element.SQLElement;
import org.openconcerto.sql.element.SQLElementDirectory;
import org.openconcerto.sql.model.DBRoot;
import org.openconcerto.sql.model.FieldPath;
import org.openconcerto.sql.model.SQLRow;
import org.openconcerto.sql.model.SQLRowAccessor;
import org.openconcerto.sql.model.SQLRowValues;
import org.openconcerto.sql.model.SQLRowValuesListFetcher;
import org.openconcerto.sql.model.SQLSelect;
import org.openconcerto.sql.model.SQLSelectJoin;
import org.openconcerto.sql.model.SQLTable;
import org.openconcerto.sql.model.SQLTableEvent;
import org.openconcerto.sql.model.SQLTableEvent.Mode;
import org.openconcerto.sql.model.SQLTableModifiedListener;
import org.openconcerto.sql.model.Where;
import org.openconcerto.sql.model.graph.Link.Direction;
import org.openconcerto.sql.model.graph.Path;
import org.openconcerto.sql.request.ComboSQLRequest;
import org.openconcerto.sql.sqlobject.SQLRequestComboBox;
import org.openconcerto.sql.utils.AlterTable;
import org.openconcerto.sql.utils.SQLCreateTable;
import org.openconcerto.sql.view.EditFrame;
import org.openconcerto.sql.view.EditPanel.EditMode;
import org.openconcerto.sql.view.IListFrame;
import org.openconcerto.sql.view.ListeAddPanel;
import org.openconcerto.sql.view.column.ColumnFooterRenderer;
import org.openconcerto.sql.view.column.ColumnPanel;
import org.openconcerto.sql.view.column.ColumnPanelFetcher;
import org.openconcerto.sql.view.column.ColumnRowRenderer;
import org.openconcerto.sql.view.list.BaseSQLTableModelColumn;
import org.openconcerto.sql.view.list.IListe;
import org.openconcerto.sql.view.list.RowAction;
import org.openconcerto.sql.view.list.action.ListEvent;
import org.openconcerto.ui.DefaultGridBagConstraints;
import org.openconcerto.ui.FrameUtil;
import org.openconcerto.ui.PanelFrame;
import org.openconcerto.utils.CollectionUtils;
import org.openconcerto.utils.ExceptionHandler;
import org.openconcerto.utils.Tuple2;
import org.openconcerto.utils.cc.IExnClosure;
import org.openconcerto.utils.cc.ITransformer;

public final class Module extends AbstractModule {

    public static final String PROJECT_TABLENAME = "AFFAIRE";
    private List<String> listTableAffaire = Arrays.asList("DEMANDE_PRIX", "BON_RECEPTION", "DEMANDE_ACHAT_ELEMENT", "SAISIE_VENTE_FACTURE", "AVOIR_CLIENT", "BON_DE_LIVRAISON", "COMMANDE_CLIENT",
            "DEVIS", "COMMANDE", "SAISIE_ACHAT", "AVOIR_FOURNISSEUR");

    public Module(ModuleFactory f) throws IOException {
        super(f);

    }

    @Override
    @SuppressWarnings("deprecation")
    protected void install(DBContext ctxt) throws SQLException, IOException {
        super.install(ctxt);

        if (ctxt.getLastInstalledVersion() == null) {

            if (ctxt.getRoot().getTable(PROJECT_TABLENAME) == null) {
                final SQLCreateTable createTableEtatAff = ctxt.getCreateTable("ETAT_AFFAIRE");
                createTableEtatAff.addVarCharColumn("NOM", 128);

                final SQLCreateTable createTableType = ctxt.getCreateTable("TYPE_AFFAIRE");
                createTableType.addVarCharColumn("NOM", 256);

                // AFFAIRE
                final SQLCreateTable createTable = ctxt.getCreateTable(PROJECT_TABLENAME);
                createTable.addVarCharColumn("NUMERO", 256);
                createTable.addVarCharColumn("NOM", 1024);
                createTable.addVarCharColumn("INFOS", 1024);
                createTable.addForeignColumn("ID_CLIENT", ctxt.getRoot().getTable("CLIENT"));
                createTable.addForeignColumn("ID_DEVIS", ctxt.getRoot().getTable("DEVIS"));
                createTable.addColumn("DATE", "date");
                createTable.addForeignColumn("ID_COMMERCIAL", ctxt.getRoot().getTable("COMMERCIAL"));
                createTable.addForeignColumn("ID_ETAT_AFFAIRE", createTableEtatAff);
                createTable.addForeignColumn("ID_TYPE_AFFAIRE", createTableType);

                for (String table : this.listTableAffaire) {
                    SQLTable tableDevis = ctxt.getRoot().getTable(table);
                    if (!tableDevis.getFieldsName().contains("ID_AFFAIRE")) {
                        AlterTableRestricted alter = ctxt.getAlterTable(table);
                        alter.addForeignColumn("ID_AFFAIRE", createTable);
                    }
                }

                ctxt.manipulateData(new IExnClosure<DBRoot, SQLException>() {

                    @Override
                    public void executeChecked(DBRoot input) throws SQLException {
                        // Undefined Affaire
                        SQLTable tableAff = input.getTable(PROJECT_TABLENAME);
                        SQLRowValues rowVals = new SQLRowValues(tableAff);
                        rowVals.insert();

                        // Etat Affaire
                        SQLTable tableTypeAffaire = input.getTable("TYPE_AFFAIRE");
                        rowVals = new SQLRowValues(tableTypeAffaire);
                        rowVals.put("NOM", "Indéfini");
                        rowVals.insert();

                        // Etat Affaire
                        SQLTable tableEtatAffaire = input.getTable("ETAT_AFFAIRE");
                        rowVals = new SQLRowValues(tableEtatAffaire);
                        rowVals.put("NOM", "Indéfini");
                        rowVals.insert();

                        rowVals.clear();
                        rowVals.put("NOM", "A traiter");
                        rowVals.insert();

                        rowVals.clear();
                        rowVals.put("NOM", "En cours");
                        rowVals.insert();

                        rowVals.clear();
                        rowVals.put("NOM", "Traitement terminé");
                        rowVals.insert();

                        rowVals.clear();
                        rowVals.put("NOM", "A facturer");
                        rowVals.insert();

                        rowVals.clear();
                        rowVals.put("NOM", "Dossier clos");
                        rowVals.insert();
                    }
                });

            }
        }

    }

    @Override
    @SuppressWarnings("deprecation")
    protected void setupElements(final SQLElementDirectory dir) {
        super.setupElements(dir);
        dir.addSQLElement(ProjectSQLElement.class);
        dir.addSQLElement(ProjectStateSQLElement.class);
        dir.addSQLElement(ProjectTypeSQLElement.class);

        final SQLElement element = dir.getElement("DEVIS");
        DevisSQLElement eltDevis = dir.getElement(DevisSQLElement.class);
        eltDevis.getRowActions().clear();

        eltDevis.addListColumn(new BaseSQLTableModelColumn("Temps Total", Double.class) {

            SQLTable tableDevisElt = Configuration.getInstance().getDirectory().getElement("DEVIS_ELEMENT").getTable();

            @Override
            protected Object show_(SQLRowAccessor r) {

                Collection<? extends SQLRowAccessor> rows = r.getReferentRows(tableDevisElt);
                double time = 0;
                for (SQLRowAccessor sqlRowAccessor : rows) {
                    time += OrderColumnRowRenderer.getHours(sqlRowAccessor);
                }
                return time;
            }

            @Override
            public Set<FieldPath> getPaths() {
                SQLTable table = Configuration.getInstance().getDirectory().getElement("DEVIS").getTable();
                Path p = new Path(table).add(tableDevisElt.getField("ID_DEVIS"));

                Path p2 = new Path(table).add(tableDevisElt.getField("ID_DEVIS")).addForeignField("ID_UNITE_VENTE");
                return CollectionUtils.createSet(new FieldPath(p, "QTE"), new FieldPath(p, "QTE_UNITAIRE"), new FieldPath(p2, "CODE"));
            }
        });

        // Transfert vers facture
        RowAction factureAction = eltDevis.getDevis2FactureAction();
        eltDevis.getRowActions().add(factureAction);

        // Transfert vers commande
        RowAction commandeAction = eltDevis.getDevis2CmdCliAction();
        eltDevis.getRowActions().add(commandeAction);

        // Marqué accepté
        RowAction accepteAction = getAcceptAction();
        eltDevis.getRowActions().add(accepteAction);

        // Marqué accepté
        RowAction refuseAction = eltDevis.getRefuseAction();
        eltDevis.getRowActions().add(refuseAction);

        // // Dupliquer
        RowAction cloneAction = eltDevis.getCloneAction();
        eltDevis.getRowActions().add(cloneAction);

        MouseSheetXmlListeListener mouseSheetXmlListeListener = new MouseSheetXmlListeListener(eltDevis, DevisXmlSheet.class);
        mouseSheetXmlListeListener.setGenerateHeader(true);
        mouseSheetXmlListeListener.setShowHeader(true);
        eltDevis.getRowActions().addAll(mouseSheetXmlListeListener.getRowActions());

        element.addComponentFactory(SQLElement.DEFAULT_COMP_ID, new ITransformer<Tuple2<SQLElement, String>, SQLComponent>() {

            @Override
            public SQLComponent transformChecked(Tuple2<SQLElement, String> input) {
                return new DevisSQLComponent(element) {

                    public int insert(SQLRow order) {
                        int id = super.insert(order);
                        checkAffaire(id);
                        return id;
                    }

                    public void update() {
                        super.update();
                        checkAffaire(getSelectedID());
                    }

                };
            }
        });

        final SQLElement elementCmd = dir.getElement("COMMANDE_CLIENT");
        elementCmd.addListColumn(new BaseSQLTableModelColumn("Temps Total", Double.class) {

            SQLTable tableCmdElt = dir.getElement("COMMANDE_CLIENT_ELEMENT").getTable();

            @Override
            protected Object show_(SQLRowAccessor r) {

                Collection<? extends SQLRowAccessor> rows = r.getReferentRows(tableCmdElt);
                double time = 0;
                for (SQLRowAccessor sqlRowAccessor : rows) {
                    time += OrderColumnRowRenderer.getHours(sqlRowAccessor);
                }
                return time;
            }

            @Override
            public Set<FieldPath> getPaths() {
                final SQLTable table = elementCmd.getTable();
                final Path p = new Path(table).add(tableCmdElt.getField("ID_COMMANDE_CLIENT"));
                final Path p2 = new Path(table).add(tableCmdElt.getField("ID_COMMANDE_CLIENT")).addForeignField("ID_UNITE_VENTE");
                return CollectionUtils.createSet(new FieldPath(p, "QTE"), new FieldPath(p, "QTE_UNITAIRE"), new FieldPath(p2, "CODE"));
            }
        });

        NumerotationAutoSQLElement.addClass(ProjectSQLElement.class, PROJECT_TABLENAME);

        for (String tableName : this.listTableAffaire) {
            if (!tableName.equalsIgnoreCase("DEVIS")) {
                final SQLElement elt = dir.getElement(tableName);
                if (elt == null) {
                    JOptionPane.showMessageDialog(null, "Table " + tableName + " manquante");
                    continue;
                }
                RowAction action = new RowAction(new AbstractAction("Historique affaire") {
                    @Override
                    public void actionPerformed(ActionEvent e) {
                        ProjectHistory histo = new ProjectHistory();
                        histo.getHistoriquePanel().selectIDinJList(IListe.get(e).getSelectedRow().getForeignID("ID_AFFAIRE"));
                        histo.getFrame().setVisible(true);
                    }
                }, false) {

                    @Override
                    public boolean enabledFor(List<SQLRowValues> evt) {
                        if (evt.size() == 1) {
                            SQLRowAccessor r = evt.get(0);
                            return !r.isForeignEmpty("ID_AFFAIRE");
                        }
                        return false;
                    }
                };

                elt.getRowActions().add(action);
                elt.addListColumn(new BaseSQLTableModelColumn("Affaire", String.class) {

                    @Override
                    protected Object show_(SQLRowAccessor r) {
                        if (!r.isForeignEmpty("ID_AFFAIRE") && r.getForeign("ID_AFFAIRE") != null) {
                            return r.getForeign("ID_AFFAIRE").getString("NUMERO");
                        } else {
                            return "";
                        }
                    }

                    @Override
                    public Set<FieldPath> getPaths() {
                        SQLTable table = elt.getTable();
                        Path p = new Path(table).add(table.getField("ID_AFFAIRE"));
                        return CollectionUtils.createSet(new FieldPath(p, "NUMERO"));
                    }
                });
            }
        }

        final SQLElement elt = dir.getElement("DEVIS");
        RowAction action = new RowAction(new AbstractAction("Historique affaire") {
            @Override
            public void actionPerformed(ActionEvent e) {
                ProjectHistory histo = new ProjectHistory();
                SQLRowAccessor selectedRow = IListe.get(e).getSelectedRow();
                Collection<? extends SQLRowAccessor> l = selectedRow.getReferentRows(selectedRow.getTable().getTable("AFFAIRE"));
                histo.getHistoriquePanel().selectIDinJList(l.iterator().next().getID());
                histo.getFrame().setVisible(true);
            }
        }, false) {

            @Override
            public boolean enabledFor(List<SQLRowValues> evt) {
                if (evt.size() == 1) {
                    SQLRowAccessor r = evt.get(0);
                    Collection<? extends SQLRowAccessor> l = r.getReferentRows(r.getTable().getTable("AFFAIRE"));
                    return l.size() > 0;
                }
                return false;
            }
        };

        elt.getRowActions().add(action);

        elt.addListColumn(new BaseSQLTableModelColumn("Affaire", String.class) {

            @Override
            protected Object show_(SQLRowAccessor r) {
                final SQLRowAccessor foreignAff = r.getForeign("ID_AFFAIRE");
                if (foreignAff != null && !foreignAff.isUndefined()) {
                    return foreignAff.getString("NUMERO");
                } else {
                    Collection<? extends SQLRowAccessor> rows = r.getReferentRows(elt.getTable().getTable("AFFAIRE"));
                    if (rows.size() == 1) {
                        return rows.iterator().next().getString("NUMERO");
                    } else {
                        return "";
                    }
                }
            }

            @Override
            public Set<FieldPath> getPaths() {
                SQLTable table = elt.getTable();
                Path pDev = new Path(table).add(table.getField("ID_AFFAIRE"));
                Path pAff = new Path(table).add(table.getTable("AFFAIRE"), Direction.REFERENT);
                return CollectionUtils.createSet(new FieldPath(pDev, "NUMERO"), new FieldPath(pAff, "NUMERO"));
            }
        });
        new CmdToBrSQLInjector();
        new QuoteToOrderSQLInjector();
        new QuoteToInvoiceSQLInjector();
        new OrderToInvoiceSQLInjector();
    }

    public static JFrame checkAffaire(int id) {
        return checkAffaire(id, true);
    }

    @SuppressWarnings("deprecation")
    public static JFrame checkAffaire(int id, final boolean createCommandeClient) {
        final SQLTable tableDevis = Configuration.getInstance().getRoot().findTable("DEVIS");
        final SQLTable tableNum = Configuration.getInstance().getRoot().findTable("NUMEROTATION_AUTO");
        final SQLRow row = tableDevis.getRow(id);
        final SQLRow rowAffaire = row.getForeign("ID_AFFAIRE");
        if (rowAffaire == null || rowAffaire.isUndefined()) {
            if (row.getInt("ID_ETAT_DEVIS") == EtatDevisSQLElement.ACCEPTE) {
                // FIXME Vérifier si le devis n'est pas déjà rattaché à une affaire

                JPanel p = new JPanel(new GridBagLayout());
                GridBagConstraints c = new DefaultGridBagConstraints();
                c.gridwidth = GridBagConstraints.REMAINDER;
                p.add(new JLabel("Voulez vous intégrer ce devis sur une affaire existante?"), c);
                c.gridy++;
                c.gridwidth = 1;
                p.add(new JLabel("Rattacher à l'affaire : "), c);
                c.gridx++;
                final SQLRequestComboBox box = new SQLRequestComboBox();
                final ComboSQLRequest comboRequest = Configuration.getInstance().getDirectory().getElement("AFFAIRE").getComboRequest(true);
                Where w = new Where(comboRequest.getPrimaryTable().getField("ID_CLIENT"), "=", row.getForeignID("ID_CLIENT"));
                comboRequest.setWhere(w);
                box.uiInit(comboRequest);
                p.add(box, c);
                c.gridy++;
                c.gridx = 0;
                final JButton buttonApply = new JButton("Appliquer");
                JButton buttonAnnuler = new JButton("Nouvelle affaire");
                p.add(buttonApply, c);
                buttonApply.setEnabled(false);
                box.addValueListener(new PropertyChangeListener() {

                    @Override
                    public void propertyChange(PropertyChangeEvent evt) {
                        buttonApply.setEnabled(box.getSelectedRow() != null);

                    }
                });
                c.gridx++;
                p.add(buttonAnnuler, c);
                final PanelFrame f = new PanelFrame(p, "Affection d'un devis à une affaire");

                buttonAnnuler.addActionListener(new ActionListener() {

                    @Override
                    public void actionPerformed(ActionEvent ae) {
                        f.dispose();
                        final SQLTable table = tableDevis.getTable(PROJECT_TABLENAME);
                        final SQLRowValues rowVals = new SQLRowValues(table);

                        final String nextNumero = NumerotationAutoSQLElement.getNextNumero(ProjectSQLElement.class);
                        rowVals.put("NUMERO", nextNumero);

                        // incrémentation du numéro auto
                        final SQLRowValues rowValsNum = new SQLRowValues(tableNum);
                        int val = tableNum.getRow(2).getInt(NumerotationAutoSQLElement.getLabelNumberFor(ProjectSQLElement.class));
                        val++;
                        rowValsNum.put(NumerotationAutoSQLElement.getLabelNumberFor(ProjectSQLElement.class), new Integer(val));
                        try {
                            rowValsNum.update(2);
                        } catch (final SQLException e) {
                            e.printStackTrace();
                        }

                        rowVals.put("ID_DEVIS", row.getID());
                        rowVals.put("ID_CLIENT", row.getObject("ID_CLIENT"));
                        rowVals.put("ID_COMMERCIAL", row.getObject("ID_COMMERCIAL"));
                        rowVals.put("DATE", new Date());
                        rowVals.put("ID_ETAT_AFFAIRE", ProjectStateSQLElement.EN_COURS);

                        SQLRowValues rowValsDevis = row.asRowValues();
                        rowValsDevis.put("ID_AFFAIRE", rowVals);

                        try {
                            int id = rowVals.commit().getID();
                            row.fetchValues();
                            if (createCommandeClient) {
                                Configuration.getInstance().getDirectory().getElement(DevisSQLElement.class).transfertCommandeClient(Arrays.asList(row.asRowValues()));
                                EditFrame frame = new EditFrame(Configuration.getInstance().getDirectory().getElement("AFFAIRE"), EditMode.MODIFICATION);
                                frame.selectionId(id);
                                FrameUtil.showPacked(frame);
                            }
                        } catch (SQLException exn) {
                            // TODO Bloc catch auto-généré
                            exn.printStackTrace();
                        }
                    }
                });

                buttonApply.addActionListener(new ActionListener() {

                    @Override
                    public void actionPerformed(ActionEvent e) {
                        f.dispose();

                        SQLRowValues rowValsDevis = row.asRowValues();
                        rowValsDevis.put("ID_AFFAIRE", box.getSelectedId());

                        try {
                            rowValsDevis.commit();
                            row.fetchValues();
                            if (createCommandeClient) {
                                Configuration.getInstance().getDirectory().getElement(DevisSQLElement.class).transfertCommandeClient(Arrays.asList(row.asRowValues()));
                            }
                        } catch (SQLException exn) {
                            ExceptionHandler.handle("Erreur lors de la création de la commande client!", exn);
                        }
                    }
                });
                FrameUtil.show(f);
                return f;
            }

        } else if (row.getInt("ID_ETAT_DEVIS") != EtatDevisSQLElement.ACCEPTE) {
            SQLRowValues rowVals = rowAffaire.asRowValues();
            rowVals.putEmptyLink("ID_DEVIS");
            try {
                rowVals.update();
            } catch (SQLException exn) {
                exn.printStackTrace();
            }
        }
        return null;
    }

    List<Integer> idsAsked = new ArrayList<Integer>();

    @SuppressWarnings("deprecation")
    public void checkProjectState(final SQLRowAccessor rowFact) {
        if (!rowFact.isForeignEmpty("ID_AFFAIRE")) {
            final SQLRowAccessor rowAff = rowFact.getForeign("ID_AFFAIRE");

            if (rowAff.getInt("ID_ETAT_AFFAIRE") < ProjectStateSQLElement.DOSSIER_CLOS) {

                SQLSelect sel = new SQLSelect();
                final SQLTable tableVF = rowFact.getTable();
                sel.addSelect(tableVF.getField("T_TTC"), "SUM");
                Where w = new Where(tableVF.getField("ID_AFFAIRE"), "=", rowAff.getID());
                sel.setWhere(w);

                // Null si aucune facture
                Number total = (Number) tableVF.getDBSystemRoot().getDataSource().executeScalar(sel.asString());

                final SQLRowAccessor devisRef = rowAff.getNonEmptyForeign("ID_DEVIS");
                if (devisRef != null) {
                    long devis = devisRef.getLong("T_TTC");
                    if (total != null && devis == total.longValue()) {
                        if (!idsAsked.contains(rowFact.getID())) {
                            idsAsked.add(rowFact.getID());
                            SwingUtilities.invokeLater(new Runnable() {

                                @Override
                                public void run() {
                                    int a = JOptionPane.showConfirmDialog(null, "Voulez vous passer l'affaire " + rowAff.getString("NUMERO") + " dans l'état \"Dossier Clos\"?",
                                            "Affaire 100% facturée", JOptionPane.YES_NO_OPTION);
                                    if (a == JOptionPane.YES_OPTION) {
                                        SQLRowValues rowVals = rowAff.createEmptyUpdateRow();
                                        rowVals.put("ID_ETAT_AFFAIRE", ProjectStateSQLElement.DOSSIER_CLOS);
                                        try {
                                            rowVals.commit();
                                        } catch (SQLException e) {
                                            ExceptionHandler.handle("Erreur lors de la mise à jour de l'état de l'affaire", e);
                                        }
                                    }
                                    idsAsked.remove(Integer.valueOf(rowFact.getID()));
                                }
                            });
                        }
                    }
                }

            }
        }
    }

    public RowAction getAcceptAction() {
        return new RowAction(new AbstractAction() {
            public void actionPerformed(ActionEvent e) {
                SQLRow selectedRow = IListe.get(e).getSelectedRow().asRow();
                SQLRowValues rowVals = selectedRow.createEmptyUpdateRow();
                rowVals.put("ID_ETAT_DEVIS", EtatDevisSQLElement.ACCEPTE);
                try {
                    rowVals.update();
                } catch (SQLException e1) {
                    e1.printStackTrace();
                }
                selectedRow.getTable().fireTableModified(selectedRow.getID());
                checkAffaire(selectedRow.getID());
            }
        }, false, "project.accept") {

            public boolean enabledFor(List<SQLRowValues> selection) {
                if (selection != null && selection.size() == 1) {
                    if (selection.get(0).getInt("ID_ETAT_DEVIS") == EtatDevisSQLElement.EN_ATTENTE) {
                        return true;
                    }
                }
                return false;
            };

        };
    }

    @Override
    protected void setupComponents(final ComponentsContext ctxt) {

        DBRoot root = ComptaPropsConfiguration.getInstanceCompta().getRootSociete();
        List<String> table2check = Arrays.asList("BON_RECEPTION", "DEMANDE_PRIX", "DEMANDE_ACHAT_ELEMENT", "FACTURE_FOURNISSEUR");
        for (String table : table2check) {
            if (root.contains(table)) {
                SQLTable tableCR = root.getTable(table);
                if (!tableCR.contains("ID_AFFAIRE")) {
                    try {
                        AlterTable alt = new AlterTable(tableCR);
                        alt.addForeignColumn("ID_AFFAIRE", root.getTable("AFFAIRE"));
                        root.getDBSystemRoot().getDataSource().execute(alt.asString());
                        String s = "INSERT INTO " + root.getTable("FWK_MODULE_METADATA").getSQLName().quote()
                                + "(\"MODULE_NAME\",\"TABLE\",\"FIELD\",\"KEY\",\"MODULE_VERSION\") VALUES('org.openconcerto.modules.project','" + table + "','ID_AFFAIRE',true,10000)";
                        root.getDBSystemRoot().getDataSource().execute(s);
                        root.getSchema().updateVersion();
                        root.refetchTable(tableCR.getName());
                    } catch (SQLException e) {
                        e.printStackTrace();
                    }
                }
            }
        }

        for (String table : this.listTableAffaire) {
            if (!table.equalsIgnoreCase("DEVIS"))
                ctxt.putAdditionalField(table, "ID_AFFAIRE");
        }

    }

    @Override
    protected void setupMenu(final MenuContext ctxt) {
        ctxt.addMenuItem(new CreateFrameAbstractAction("Liste des affaires") {
            @Override
            public JFrame createFrame() {
                IListFrame frame = new IListFrame(new ListeAddPanel(ctxt.getElement(PROJECT_TABLENAME)));
                return frame;
            }
        }, MainFrame.LIST_MENU);
        ctxt.addMenuItem(new CreateFrameAbstractAction("Historique des affaires") {
            @Override
            public JFrame createFrame() {
                ProjectHistory histo = new ProjectHistory();

                return histo.getFrame();
            }
        }, MainFrame.LIST_MENU);

        ctxt.addMenuItem(new CreateFrameAbstractAction("Saisie affaire") {
            @Override
            public JFrame createFrame() {
                return new EditFrame(ctxt.getElement(PROJECT_TABLENAME));
            }
        }, MainFrame.CREATE_MENU);

        addMenuImportExport(ctxt);

    }

    private void addMenuImportExport(final MenuContext ctxt) {
        ////

        ctxt.addMenuItem(new AbstractAction("Export Affaire") {
            @Override
            public void actionPerformed(ActionEvent e) {
                ProjectImportExport importExport = new ProjectImportExport(ctxt.getElement("AFFAIRE").getTable().getDBRoot());
                importExport.export();
            }
        }, MainFrame.HELP_MENU);

        ctxt.addMenuItem(new AbstractAction("Import Affaire") {
            @Override
            public void actionPerformed(ActionEvent e) {
                ProjectImportExport importExport = new ProjectImportExport(ctxt.getElement("AFFAIRE").getTable().getDBRoot());
                importExport.importProjects();
            }
        }, MainFrame.HELP_MENU);
        if (false) {
            ctxt.addMenuItem(new AbstractAction("Fix ID_AFFAIRE") {
                @Override
                public void actionPerformed(ActionEvent e) {
                    {
                        SQLTable tableCmd = ctxt.getElement("COMMANDE_CLIENT").getTable();
                        SQLSelect selBadCmd = new SQLSelect();
                        selBadCmd.addSelect(tableCmd.getKey());
                        selBadCmd.addSelect(tableCmd.getField("ID_AFFAIRE"));
                        SQLSelectJoin joinTR = selBadCmd.addBackwardJoin("RIGHT", "tr", tableCmd.getTable().getTable("TR_DEVIS").getField("ID_COMMANDE_CLIENT"), null);
                        SQLSelectJoin joinDevis = selBadCmd.addJoin("LEFT", joinTR.getJoinedTable().getField("ID_DEVIS"));
                        SQLSelectJoin joinAff = selBadCmd.addBackwardJoin("LEFT", "aff", tableCmd.getTable().getTable("AFFAIRE").getField("ID_DEVIS"), null);
                        selBadCmd.addSelect(joinAff.getJoinedTable().getKey());

                        selBadCmd.setWhere(Where.isNull(tableCmd.getField("ID_AFFAIRE")));
                        System.err.println(selBadCmd.asString());

                        @SuppressWarnings("unchecked")
                        List<Object[]> result = (List<Object[]>) tableCmd.getDBSystemRoot().getDataSource().executeA(selBadCmd.asString());
                        try {
                            for (Object[] objects : result) {
                                if (objects[2] != null && objects[2].toString().trim().length() > 0)
                                    tableCmd.getRow(((Number) objects[0]).intValue()).createEmptyUpdateRow().put("ID_AFFAIRE", ((Number) objects[2]).intValue()).commit();
                            }
                        } catch (SQLException e1) {
                            // TODO Auto-generated catch block
                            e1.printStackTrace();
                        }

                        // List<SQLRow> list = SQLRowListRSH.execute(selBadVF);
                    }
                    {
                        SQLTable tableVF = ctxt.getElement("SAISIE_VENTE_FACTURE").getTable();
                        SQLSelect selBadVF = new SQLSelect();
                        selBadVF.addSelect(tableVF.getKey());
                        selBadVF.addSelect(tableVF.getField("ID_AFFAIRE"));
                        SQLSelectJoin joinTR = selBadVF.addBackwardJoin("RIGHT", "tr", tableVF.getTable().getTable("TR_COMMANDE_CLIENT").getField("ID_SAISIE_VENTE_FACTURE"), null);
                        SQLSelectJoin joinCmd = selBadVF.addJoin("LEFT", joinTR.getJoinedTable().getField("ID_COMMANDE_CLIENT"));
                        selBadVF.addSelect(joinCmd.getJoinedTable().getField("ID_AFFAIRE"));

                        selBadVF.setWhere(Where.isNull(tableVF.getField("ID_AFFAIRE")));
                        System.err.println(selBadVF.asString());
                        @SuppressWarnings("unchecked")
                        List<Object[]> result = (List<Object[]>) tableVF.getDBSystemRoot().getDataSource().executeA(selBadVF.asString());
                        try {
                            for (Object[] objects : result) {
                                if (objects[2] != null && objects[2].toString().trim().length() > 0)
                                    tableVF.getRow(((Number) objects[0]).intValue()).createEmptyUpdateRow().put("ID_AFFAIRE", ((Number) objects[2]).intValue()).commit();
                            }
                        } catch (SQLException e1) {
                            // TODO Auto-generated catch block
                            e1.printStackTrace();
                        }
                    }
                }
            }, MainFrame.CREATE_MENU);
        }
        ctxt.addMenuItem(new AbstractAction("Recalcul Total achat facture prorata") {
            @Override
            public void actionPerformed(ActionEvent e) {

                {
                    final SQLTable table = ctxt.getElement("SAISIE_VENTE_FACTURE").getTable();
                    SQLRowValues rowValsFact = new SQLRowValues(table);
                    rowValsFact.putNulls("SOLDE", "PARTIAL", "T_HA", "T_HT");

                    final SQLTable tableCmd = ctxt.getElement("COMMANDE_CLIENT").getTable();
                    SQLRowValues rowValsCmd = new SQLRowValues(tableCmd);
                    rowValsCmd.putNulls("T_HT");

                    final SQLTable tableCmdElt = ctxt.getElement("COMMANDE_CLIENT_ELEMENT").getTable();
                    SQLRowValues rowValsCmdElt = new SQLRowValues(tableCmdElt);
                    rowValsCmdElt.put("ID_COMMANDE_CLIENT", rowValsCmd);
                    rowValsCmdElt.putNulls("T_PA_HT", "NIVEAU");

                    final SQLTable tableTR = table.getTable("TR_COMMANDE_CLIENT");
                    SQLRowValues rowValsTR = new SQLRowValues(tableTR);
                    rowValsTR.put("ID_SAISIE_VENTE_FACTURE", rowValsFact);
                    rowValsTR.put("ID_COMMANDE_CLIENT", rowValsCmd);

                    SQLRowValuesListFetcher fetcher = SQLRowValuesListFetcher.create(rowValsFact);
                    fetcher.appendSelTransf(new ITransformer<SQLSelect, SQLSelect>() {
                        @Override
                        public SQLSelect transformChecked(SQLSelect input) {
                            Where w = new Where(table.getField("SOLDE"), "=", Boolean.TRUE);
                            w = w.or(new Where(table.getField("PARTIAL"), "=", Boolean.TRUE));
                            input.setWhere(w);
                            return input;
                        }
                    });

                    List<SQLRowValues> rowVals = fetcher.fetch();

                    for (SQLRowValues sqlRowValues : rowVals) {
                        // Recuperation de la commande
                        final Collection<SQLRowValues> referentRows = sqlRowValues.getReferentRows(tableTR);
                        if (!referentRows.isEmpty()) {
                            SQLRowAccessor rowTR = referentRows.iterator().next();
                            SQLRowAccessor rowCmd = rowTR.getForeign("ID_COMMANDE_CLIENT");
                            final long htCmd = rowCmd.getLong("T_HT");
                            if (htCmd != 0) {

                                BigDecimal totalHA = BigDecimal.ZERO;
                                Collection<? extends SQLRowAccessor> elt = rowCmd.getReferentRows(tableCmdElt);
                                for (SQLRowAccessor sqlRowAccessor : elt) {
                                    if (sqlRowAccessor.getInt("NIVEAU") == 1) {
                                        totalHA = totalHA.add(sqlRowAccessor.getBigDecimal("T_PA_HT"));
                                    }
                                }
                                BigDecimal prorata = new BigDecimal((double) sqlRowValues.getLong("T_HT") / (double) htCmd);
                                try {
                                    sqlRowValues.createEmptyUpdateRow().put("T_HA", totalHA.multiply(prorata).movePointRight(2).setScale(0, RoundingMode.HALF_UP).longValue()).update();
                                } catch (SQLException e1) {
                                    e1.printStackTrace();
                                }
                            }
                        }
                    }
                }
            }
        }, MainFrame.CREATE_MENU);
    }

    @Override
    protected void start() {

        final JComponent quoteComponent = createQuotePanel();
        final JComponent orderComponent = createOrderPanel();
        MainFrame.getInstance().getTabbedPane().addTab("Commandes en cours", orderComponent);
        MainFrame.getInstance().getTabbedPane().addTab("Devis en attente", quoteComponent);
        MainFrame.getInstance().getTabbedPane().addTab("Affaires", new ListeAddPanel(Configuration.getInstance().getDirectory().getElement(PROJECT_TABLENAME)));
        // Fix for classic XP Theme
        quoteComponent.setOpaque(true);
        quoteComponent.setBackground(Color.WHITE);
        orderComponent.setOpaque(true);
        orderComponent.setBackground(Color.WHITE);
        // Select first tab
        MainFrame.getInstance().getTabbedPane().setSelectedIndex(1);

        CommandeClientItemTable.getVisibilityMap().put("POURCENT_ACOMPTE", Boolean.TRUE);
        SaisieVenteFactureItemTable.getVisibilityMap().put("POURCENT_ACOMPTE", Boolean.TRUE);
        AccountingRecordsProvider p = new AccountingRecordsProvider() {

            @Override
            public void putLabel(SQLRowAccessor rowSource, Map<String, Object> values) {
                values.put("NOM", "Fact. vente " + rowSource.getString("NUMERO"));
            }

            @Override
            public void putPieceLabel(SQLRowAccessor rowSource, SQLRowValues rowValsPiece) {
                rowValsPiece.put("NOM", rowSource.getString("NUMERO"));
            }
        };
        AccountingRecordsProviderManager.put(GenerationMvtSaisieVenteFacture.ID, p);

        final SQLTable tableFact = ComptaPropsConfiguration.getInstanceCompta().getRootSociete().getTable("SAISIE_VENTE_FACTURE");

        tableFact.addTableModifiedListener(new SQLTableModifiedListener() {

            @Override
            public void tableModified(SQLTableEvent evt) {
                if (evt.getMode() == Mode.ROW_ADDED || evt.getMode() == Mode.ROW_UPDATED) {
                    checkProjectState(evt.getRow());
                }
            }
        });
    }

    private JComponent createQuotePanel() {
        ColumnRowRenderer cRenderer = new QuoteColumnRowRenderer();
        ColumnFooterRenderer fRenderer = new QuoteColumnFooterRenderer();
        final ColumnPanel columnPanel = new ColumnPanel(220, cRenderer, fRenderer);
        columnPanel.setOpaque(false);
        final SQLElement element = Configuration.getInstance().getDirectory().getElement("DEVIS_ELEMENT");
        Path p = Path.get(element.getTable()).addForeignField("ID_ARTICLE").addForeignField("ID_FAMILLE_ARTICLE");

        SQLRowValues values = new SQLRowValues(element.getTable());
        values.put("NOM", null);
        values.put("T_PV_HT", null);
        SQLRowValues rowValsClient = new SQLRowValues(element.getTable().getTable("CLIENT"));
        rowValsClient.put("NOM", null);
        final SQLTable tableDevis = element.getTable().getTable("DEVIS");
        SQLRowValues rowValsDevis = new SQLRowValues(tableDevis);
        rowValsDevis.put("NUMERO", null);
        rowValsDevis.put("DATE", null);
        rowValsDevis.put("T_HT", null);

        rowValsDevis.put("ID_CLIENT", rowValsClient);
        values.put("ID_DEVIS", rowValsDevis);
        SQLRowValues rowValsUnite = new SQLRowValues(element.getTable().getTable("UNITE_VENTE"));
        rowValsUnite.put("CODE", null);
        values.put("ID_UNITE_VENTE", rowValsUnite);
        values.put("QTE", null);
        values.put("QTE_UNITAIRE", null);

        ITransformer<SQLSelect, SQLSelect> t = new ITransformer<SQLSelect, SQLSelect>() {
            @Override
            public SQLSelect transformChecked(SQLSelect input) {
                input.andWhere(new Where(input.getAlias(tableDevis.getField("ID_ETAT_DEVIS")), "=", EtatDevisSQLElement.EN_ATTENTE));
                return input;
            }
        };
        final ColumnPanelFetcher projectFetcher = new ColumnPanelFetcher(values, new FieldPath(p, "NOM"), t);
        columnPanel.setHeaderRenderer(new TotalHeaderRenderer());
        columnPanel.setFetch(projectFetcher);

        final JScrollPane comp = new JScrollPane(columnPanel);
        comp.setBorder(null);
        comp.getViewport().setOpaque(false);
        return comp;
    }

    private JComponent createOrderPanel() {
        ColumnRowRenderer cRenderer = new OrderColumnRowRenderer();
        ColumnFooterRenderer fRenderer = new OrderColumnFooterRenderer();
        final ColumnPanel columnPanel = new ColumnPanel(220, cRenderer, fRenderer);
        columnPanel.setOpaque(false);
        final SQLElement element = Configuration.getInstance().getDirectory().getElement("COMMANDE_CLIENT_ELEMENT");
        final SQLTable tableOrder = element.getTable();
        Path p = Path.get(tableOrder).addForeignField("ID_ARTICLE").addForeignField("ID_FAMILLE_ARTICLE");

        SQLRowValues values = new SQLRowValues(tableOrder);
        values.put("NOM", null);
        values.put("T_PV_HT", null);
        SQLRowValues rowValsClient = new SQLRowValues(tableOrder.getTable("CLIENT"));
        rowValsClient.put("NOM", null);
        SQLRowValues rowValsCmd = new SQLRowValues(tableOrder.getTable("COMMANDE_CLIENT"));
        rowValsCmd.put("NUMERO", null);
        rowValsCmd.put("DATE", null);
        rowValsCmd.put("T_HT", null);

        rowValsCmd.put("ID_CLIENT", rowValsClient);
        values.put("ID_COMMANDE_CLIENT", rowValsCmd);
        SQLRowValues rowValsUnite = new SQLRowValues(tableOrder.getTable("UNITE_VENTE"));
        rowValsUnite.put("CODE", null);
        values.put("ID_UNITE_VENTE", rowValsUnite);
        values.put("QTE", null);
        values.put("QTE_UNITAIRE", null);

        final SQLTable tableAffaire = tableOrder.getTable(PROJECT_TABLENAME);
        SQLRowValues rowValsAffaire = new SQLRowValues(tableAffaire);
        rowValsAffaire.put("NUMERO", null);
        rowValsAffaire.put("DATE", null);
        rowValsCmd.put("ID_AFFAIRE", rowValsAffaire);

        if (tableOrder.getDBRoot().contains("AFFAIRE_TEMPS")) {
            final SQLTable tableAffaireTemps = tableOrder.getTable("AFFAIRE_TEMPS");
            SQLRowValues rowValsAffaireTemps = new SQLRowValues(tableAffaireTemps);
            rowValsAffaireTemps.put("TEMPS", null);
            rowValsAffaireTemps.put("ID_COMMANDE_CLIENT_ELEMENT", values);
        }
        ITransformer<SQLSelect, SQLSelect> t = new ITransformer<SQLSelect, SQLSelect>() {
            @Override
            public SQLSelect transformChecked(SQLSelect input) {
                input.andWhere(new Where(input.getAlias(tableAffaire.getField("ID_ETAT_AFFAIRE")), "=", ProjectStateSQLElement.EN_COURS));
                return input;
            }
        };
        final ColumnPanelFetcher projectFetcher = new ColumnPanelFetcher(values, new FieldPath(p, "NOM"), t);
        columnPanel.setHeaderRenderer(new TotalHeaderRenderer());
        columnPanel.setFetch(projectFetcher);
        final JScrollPane comp = new JScrollPane(columnPanel);
        comp.setBorder(null);
        comp.getViewport().setOpaque(false);
        return comp;
    }

    @Override
    protected void stop() {
    }
}
