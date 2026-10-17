package org.openconcerto.modules.currency;

import java.awt.BorderLayout;
import java.awt.event.ActionEvent;
import java.io.IOException;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.logging.Level;
import java.util.logging.Logger;

import javax.swing.AbstractAction;
import javax.swing.JFrame;
import javax.swing.JLabel;
import javax.swing.JOptionPane;
import javax.swing.JPanel;
import javax.swing.SwingWorker;

import org.openconcerto.erp.action.CreateFrameAbstractAction;
import org.openconcerto.erp.config.MainFrame;
import org.openconcerto.erp.generationDoc.AbstractSheetXml;
import org.openconcerto.erp.model.MouseSheetXmlListeListener;
import org.openconcerto.erp.modules.AbstractModule;
import org.openconcerto.erp.modules.DBContext;
import org.openconcerto.erp.modules.MenuContext;
import org.openconcerto.erp.modules.ModuleFactory;
import org.openconcerto.sql.Configuration;
import org.openconcerto.sql.element.SQLElement;
import org.openconcerto.sql.element.SQLElementDirectory;
import org.openconcerto.sql.model.DBRoot;
import org.openconcerto.sql.model.FieldPath;
import org.openconcerto.sql.model.SQLRow;
import org.openconcerto.sql.model.SQLRowAccessor;
import org.openconcerto.sql.model.SQLRowValues;
import org.openconcerto.sql.model.SQLTable;
import org.openconcerto.sql.model.graph.Path;
import org.openconcerto.sql.sqlobject.ElementComboBox;
import org.openconcerto.sql.users.rights.UserRightsManager;
import org.openconcerto.sql.utils.AlterTable;
import org.openconcerto.sql.view.IListFrame;
import org.openconcerto.sql.view.ListeAddPanel;
import org.openconcerto.sql.view.list.BaseSQLTableModelColumn;
import org.openconcerto.sql.view.list.IListe;
import org.openconcerto.sql.view.list.IListeAction;
import org.openconcerto.sql.view.list.IListeAction.IListeEvent;
import org.openconcerto.sql.view.list.RowAction;
import org.openconcerto.utils.ExceptionHandler;

/**
 * Standalone currency module for OpenConcerto 1.7.x.
 *
 * <p>The ERP already owns the DEVISE catalogue. This module does not duplicate it: it exposes that
 * catalogue, makes the existing CLIENT.ID_DEVISE relation editable, and routes customer document
 * generation to optional currency-specific templates.</p>
 */
public final class Module extends AbstractModule {

    private static final Logger LOGGER = Logger.getLogger(Module.class.getName());
    private static final AtomicBoolean STARTUP_CURRENCY_SYNC_SCHEDULED = new AtomicBoolean(false);
    private static final String CLIENT_TABLE = "CLIENT";
    private static final String CURRENCY_TABLE = "DEVISE";
    private static final String CLIENT_CURRENCY_FIELD = "ID_DEVISE";

    public Module(ModuleFactory factory) throws IOException {
        super(factory);
    }

    @Override
    protected void install(DBContext context) throws SQLException, IOException {
        super.install(context);

        final DBRoot root = context.getRoot();
        if (!root.contains(CLIENT_TABLE)) {
            throw new SQLException("La table CLIENT est introuvable dans la base de la société.");
        }
        final SQLTable currencyTable = root.findTable(CURRENCY_TABLE, true);
        if (currencyTable == null) {
            throw new SQLException("La table DEVISE est introuvable. Ce module utilise le catalogue de devises d'OpenConcerto 1.7.x et ne le recrée pas.");
        }

        final SQLTable clientTable = root.getTable(CLIENT_TABLE);
        if (!clientTable.contains(CLIENT_CURRENCY_FIELD)) {
            // CLIENT.ID_DEVISE is present in a standard 1.7.6 database. Add the foreign key only
            // for older/custom schemas; never create a second DEVISE table.
            context.getAlterTable(CLIENT_TABLE).addForeignColumn(CLIENT_CURRENCY_FIELD, currencyTable);
        }
    }

    @Override
    protected void setupElements(final SQLElementDirectory directory) {
        super.setupElements(directory);
        exposeClientCurrencyField(directory);
    }

    private static void exposeClientCurrencyField(final SQLElementDirectory directory) {
        final SQLElement clientElement = directory.getElement(CLIENT_TABLE);
        if (clientElement.getTable().contains(CLIENT_CURRENCY_FIELD) && !clientElement.getAdditionalFields().containsKey(CLIENT_CURRENCY_FIELD)) {
            // The stock ClientNormalSQLComponent provides an additional-fields area. A generic
            // foreign-key view there is an ElementComboBox backed by OpenConcerto's DEVISE element.
            clientElement.putAdditionalField(CLIENT_CURRENCY_FIELD);
        }

        final SQLTable clientTable = clientElement.getTable();
        final SQLTable currencyTable = clientTable.getDBRoot().findTable(CURRENCY_TABLE, true);
        if (clientTable.contains(CLIENT_CURRENCY_FIELD)) {
            if (currencyTable != null && currencyTable.contains("CODE")) {
                final Path currencyPath = new Path(clientTable).addForeignField(CLIENT_CURRENCY_FIELD);
                clientElement.addListColumn(new BaseSQLTableModelColumn("Devise", String.class) {
                    @Override
                    protected Object show_(SQLRowAccessor row) {
                        if (row.isForeignEmpty(CLIENT_CURRENCY_FIELD)) {
                            return "";
                        }
                        final SQLRowAccessor currency = row.getForeign(CLIENT_CURRENCY_FIELD);
                        if (currency == null || currency.isUndefined()) {
                            return "";
                        }
                        return currency.getString("CODE");
                    }

                    @Override
                    public Set<FieldPath> getPaths() {
                        return Collections.singleton(new FieldPath(currencyPath, "CODE"));
                    }
                });
            }
            addCurrencyChooserRowAction(clientElement, directory.getElement(CURRENCY_TABLE));
        }
    }

    private static void addCurrencyChooserRowAction(final SQLElement clientElement, final SQLElement currencyElement) {
        if (currencyElement == null) {
            return;
        }
        for (IListeAction action : clientElement.getRowActions()) {
            if (action instanceof RowAction && "currency.client.chooseCurrency".equals(((RowAction) action).getID())) {
                return;
            }
        }

        final RowAction.PredicateRowAction chooseCurrency = new RowAction.PredicateRowAction(new AbstractAction("Choisir / modifier la devise du client") {
            @Override
            public void actionPerformed(ActionEvent event) {
                showCurrencyChooser(event, clientElement, currencyElement);
            }
        }, true, "currency.client.chooseCurrency");
        chooseCurrency.setPredicate(IListeEvent.getSingleSelectionPredicate());
        clientElement.getRowActions().add(chooseCurrency);
    }

    private static void showCurrencyChooser(final ActionEvent event, final SQLElement clientElement, final SQLElement currencyElement) {
        final IListe list = IListe.get(event);
        final SQLRowAccessor clientRow = list.fetchSelectedRow();
        if (clientRow == null || clientRow.isUndefined()) {
            return;
        }
        if (!UserRightsManager.getCurrentUserRights().canModify(clientElement.getTable())) {
            JOptionPane.showMessageDialog(list, "Vous n'avez pas les droits nécessaires pour modifier ce client.", "Devise du client", JOptionPane.WARNING_MESSAGE);
            return;
        }

        // Use a standalone, explicitly initialized ElementComboBox. This stays usable from the
        // client list even when the user opened the client form in read-only mode.
        final ElementComboBox currencyCombo = new ElementComboBox(false, 24);
        currencyCombo.init(currencyElement);
        currencyCombo.setButtonsVisible(false);

        final int currentCurrencyID = clientRow.isForeignEmpty(CLIENT_CURRENCY_FIELD) ? SQLRow.NONEXISTANT_ID : clientRow.getInt(CLIENT_CURRENCY_FIELD);
        if (currentCurrencyID >= SQLRow.MIN_VALID_ID) {
            currencyCombo.setValue(currentCurrencyID);
        }

        final JPanel panel = new JPanel(new BorderLayout(8, 0));
        panel.add(new JLabel("Devise du client :"), BorderLayout.LINE_START);
        panel.add(currencyCombo, BorderLayout.CENTER);
        final int answer = JOptionPane.showConfirmDialog(list, panel, "Choisir la devise du client", JOptionPane.OK_CANCEL_OPTION, JOptionPane.PLAIN_MESSAGE);
        if (answer != JOptionPane.OK_OPTION) {
            return;
        }

        final int selectedCurrencyID = currencyCombo.getSelectedId();
        if (selectedCurrencyID < SQLRow.MIN_VALID_ID) {
            JOptionPane.showMessageDialog(list, "Choisissez une devise dans la liste.", "Devise du client", JOptionPane.WARNING_MESSAGE);
            return;
        }
        if (!CurrencySelectionSupport.shouldPersistSelection(currentCurrencyID, selectedCurrencyID)) {
            return;
        }

        try {
            new SQLRowValues(clientElement.getTable()).put(CLIENT_CURRENCY_FIELD, Integer.valueOf(selectedCurrencyID)).update(clientRow.getID());
        } catch (SQLException e) {
            ExceptionHandler.handle("Impossible d'enregistrer la devise du client.", e);
        }
    }

    @Override
    protected void setupMenu(final MenuContext context) {
        context.addMenuItem(new CreateFrameAbstractAction("Liste des devises") {
            @Override
            public JFrame createFrame() {
                final SQLElement currencyElement = getCurrencyElement();
                if (currencyElement == null) {
                    return messageFrame("Devises", "Le catalogue des devises (table DEVISE) n'est pas accessible dans cette base.");
                }
                return new IListFrame(new ListeAddPanel(currencyElement));
            }
        }, MainFrame.LIST_MENU);

        context.addMenuItem(new CreateFrameAbstractAction("Clients et leur devise") {
            @Override
            public JFrame createFrame() {
                final SQLElement clientElement = getElement(CLIENT_TABLE);
                if (clientElement == null) {
                    return messageFrame("Clients et leur devise", "La table CLIENT n'est pas accessible dans cette base.");
                }
                return new IListFrame(new ListeAddPanel(clientElement));
            }
        }, MainFrame.LIST_MENU);

        context.addMenuItem(new AbstractAction("Synchroniser le catalogue ISO 4217") {
            @Override
            public void actionPerformed(ActionEvent event) {
                synchronizeCurrencyCatalogInteractively();
            }
        }, MainFrame.LIST_MENU);
    }

    @Override
    protected void start() {
        // Reinstall after every module has configured its SQL elements. In particular, another
        // module can replace the quote actions while its setupElements() method runs.
        installCurrencyAwareDocumentActions(Configuration.getInstance().getDirectory());
        synchronizeCurrencyCatalogAtStartup();
    }

    private static void synchronizeCurrencyCatalogAtStartup() {
        if (!STARTUP_CURRENCY_SYNC_SCHEDULED.compareAndSet(false, true)) {
            return;
        }
        final Thread thread = new Thread(new Runnable() {
            @Override
            public void run() {
                try {
                    final CurrencyCatalogSynchronizer.Result result = CurrencyCatalogSynchronizer.synchronize(getCurrencyTable());
                    LOGGER.info(result.getSummary());
                } catch (Exception e) {
                    // Never interrupt OpenConcerto startup because a web service or DB is unavailable.
                    LOGGER.log(Level.WARNING, "Synchronisation du catalogue ISO 4217 impossible; les devises déjà enregistrées sont conservées.", e);
                }
            }
        }, "openconcerto-iso-currency-sync");
        thread.setDaemon(true);
        thread.start();
    }

    private static void synchronizeCurrencyCatalogInteractively() {
        new SwingWorker<CurrencyCatalogSynchronizer.Result, Object>() {
            @Override
            protected CurrencyCatalogSynchronizer.Result doInBackground() throws Exception {
                return CurrencyCatalogSynchronizer.synchronize(getCurrencyTable());
            }

            @Override
            protected void done() {
                try {
                    final CurrencyCatalogSynchronizer.Result result = get();
                    final int messageType = result.getFailedCount() == 0 ? JOptionPane.INFORMATION_MESSAGE : JOptionPane.WARNING_MESSAGE;
                    JOptionPane.showMessageDialog(null, result.getSummary(), "Synchronisation des devises", messageType);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    ExceptionHandler.handle("Synchronisation des devises interrompue.", e);
                } catch (ExecutionException e) {
                    final Throwable cause = e.getCause() == null ? e : e.getCause();
                    ExceptionHandler.handle("Impossible de récupérer le catalogue ISO 4217. Les devises en base n'ont pas été supprimées.", cause);
                }
            }
        }.execute();
    }

    private static SQLTable getCurrencyTable() {
        final SQLElement currencyElement = getCurrencyElement();
        if (currencyElement == null) {
            throw new IllegalStateException("La table DEVISE n'est pas accessible dans cette base.");
        }
        return currencyElement.getTable();
    }

    /**
     * Resolves an element by table name against the global SQLElement directory.
     *
     * <p>DEVISE lives in the shared "Common" schema, not in the company schema, so the module
     * context (which resolves tables in the company root only) cannot find it and throws
     * "Not element found for table DEVISE". Looking the name up in the global directory - the same
     * lookup OpenConcerto's own ListeDesDevisesAction performs - works for both shared and company
     * tables.</p>
     */
    private static SQLElement getElement(final String tableName) {
        if (Configuration.getInstance().getDirectory() == null) {
            return null;
        }
        return Configuration.getInstance().getDirectory().getElement(tableName);
    }

    private static SQLElement getCurrencyElement() {
        return getElement(CURRENCY_TABLE);
    }

    /** Frames returned by menu actions must never be null: the caller packs and shows them. */
    private static JFrame messageFrame(final String title, final String message) {
        final JFrame frame = new JFrame(title);
        frame.add(new JLabel(message));
        return frame;
    }

    private static void installCurrencyAwareDocumentActions(final SQLElementDirectory directory) {
        replaceDocumentActions(directory.getElement("DEVIS"), CurrencyAwareDevisXmlSheet.class, true, true);
        replaceDocumentActions(directory.getElement("COMMANDE_CLIENT"), CurrencyAwareCommandeClientXmlSheet.class, true, true);
        replaceDocumentActions(directory.getElement("SAISIE_VENTE_FACTURE"), CurrencyAwareVenteFactureXmlSheet.class, false, false);
        replaceDocumentActions(directory.getElement("AVOIR_CLIENT"), CurrencyAwareAvoirClientXmlSheet.class, false, false);
    }

    private static void replaceDocumentActions(final SQLElement element, final Class<? extends AbstractSheetXml> sheetClass, final boolean showHeader, final boolean generateHeader) {
        final List<String> documentActionIDs = Arrays.asList("document.modify", "document.preview", "document.print", "document.pdf.send.email", "document.send.email", "document.create");
        final Collection<IListeAction> actions = element.getRowActions();
        final List<IListeAction> actionsToRemove = new ArrayList<IListeAction>();
        for (IListeAction action : actions) {
            if (action instanceof RowAction && documentActionIDs.contains(((RowAction) action).getID())) {
                actionsToRemove.add(action);
            }
        }
        actions.removeAll(actionsToRemove);

        final MouseSheetXmlListeListener listener = new MouseSheetXmlListeListener(element, sheetClass);
        listener.setShowHeader(showHeader);
        listener.setGenerateHeader(generateHeader);
        actions.addAll(listener.getRowActions());
    }

    @Override
    protected void stop() {
    }
}
