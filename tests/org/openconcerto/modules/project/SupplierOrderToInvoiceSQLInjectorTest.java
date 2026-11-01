package org.openconcerto.modules.project;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.openconcerto.erp.injector.CommandeFactureFournisseurSQLInjector;
import org.openconcerto.erp.modules.ComponentsContext;
import org.openconcerto.sql.Configuration;
import org.openconcerto.sql.model.DBRoot;
import org.openconcerto.sql.model.SQLField;
import org.openconcerto.sql.model.SQLInjector;
import org.openconcerto.sql.model.SQLRowValues;
import org.openconcerto.sql.model.SQLTable;

/**
 * Unit and contract tests for supplier order to supplier invoice transfers.
 * OpenConcerto is represented by small in-memory test doubles so these tests do
 * not need a database or a Swing session.
 */
public final class SupplierOrderToInvoiceSQLInjectorTest {

    private static int testCount;

    public static void main(final String[] args) {
        testUsesSupplierOrderToSupplierInvoicePath();
        testCopiesAffairAndKeepsNativeMappings();
        testCustomInjectorReplacesNativeRegistration();
        testDefaultConstructorUsesConfiguredRoot();
        testNullAndUndefinedAffairsAreNotInvented();
        testRepeatedRegistrationKeepsOneAffairMapping();
        testSuccessiveTransfersAreIndependent();
        testMultipleOrdersFromTheSameAffair();
        testGroupedOrdersKeepLineAffairsSeparate();
        testMissingAffairColumnsDegradeSafely();
        testSourceOrderIsNeverModified();
        testInvoiceHeaderExposesAffairField();
        testAffairFieldDeclaredOncePerTable();
        testModuleStartupSurvivesAlreadyDeclaredField();
        testModuleStartupSurvivesFieldNotCreatedByModule();
        testUndefinedLineAffairsUseOrderAffair();
        testDefinedLineAffairIsPreserved();
        testNoOrderAffairLeavesLineAffairsUndefined();
        testMissingLineAffairColumnDoesNotBlockTransfer();

        System.out.println("SupplierOrderToInvoiceSQLInjectorTest OK (" + testCount + " tests)");
    }

    private static void testUsesSupplierOrderToSupplierInvoicePath() {
        final Fixture fixture = new Fixture(true, true);
        final SupplierOrderToInvoiceSQLInjector injector = new SupplierOrderToInvoiceSQLInjector(fixture.root);

        assertEquals("source table", "COMMANDE", injector.getSource().getName());
        assertEquals("destination table", "FACTURE_FOURNISSEUR", injector.getDestination().getName());
        pass();
    }

    private static void testCopiesAffairAndKeepsNativeMappings() {
        final Fixture fixture = new Fixture(true, true);
        final SupplierOrderToInvoiceSQLInjector injector = new SupplierOrderToInvoiceSQLInjector(fixture.root);

        final SQLRowValues invoice = injector.createRowValuesFrom(order(fixture, 10, 330, "Commande affaire 330"));

        assertEquals("affair copied from order", 330, invoice.getObject("ID_AFFAIRE"));
        assertEquals("native supplier mapping retained", 60, invoice.getObject("ID_FOURNISSEUR"));
        assertEquals("native name mapping retained", "Commande affaire 330", invoice.getObject("NOM"));
        assertEquals("native information mapping retained", "Informations commande 10", invoice.getObject("INFOS"));
        pass();
    }

    private static void testCustomInjectorReplacesNativeRegistration() {
        final Fixture fixture = new Fixture(true, true);
        new CommandeFactureFournisseurSQLInjector(fixture.root);
        final SupplierOrderToInvoiceSQLInjector custom = new SupplierOrderToInvoiceSQLInjector(fixture.root);

        final SQLInjector usedByTransfer = SQLInjector.getInjector(fixture.orders, fixture.invoices);
        assertSame("custom injector registered for the native transfer", custom, usedByTransfer);
        final SQLRowValues invoice = usedByTransfer.createRowValuesFrom(order(fixture, 11, 331, "Commande enregistrée"));
        assertEquals("registered injector copies affair", 331, invoice.getObject("ID_AFFAIRE"));
        pass();
    }

    private static void testDefaultConstructorUsesConfiguredRoot() {
        final Fixture fixture = new Fixture(true, true);
        Configuration.setInstance(new Configuration(fixture.root));

        final SupplierOrderToInvoiceSQLInjector injector = new SupplierOrderToInvoiceSQLInjector();

        assertSame("configured source root", fixture.root, injector.getSource().getDBRoot());
        assertSame("configured destination root", fixture.root, injector.getDestination().getDBRoot());
        final SQLRowValues invoice = injector.createRowValuesFrom(order(fixture, 12, 332, "Commande configuration"));
        assertEquals("default constructor copies affair", 332, invoice.getObject("ID_AFFAIRE"));
        pass();
    }

    private static void testNullAndUndefinedAffairsAreNotInvented() {
        final Fixture fixture = new Fixture(true, true);
        final SupplierOrderToInvoiceSQLInjector injector = new SupplierOrderToInvoiceSQLInjector(fixture.root);

        final SQLRowValues nullAffairInvoice = injector.createRowValuesFrom(order(fixture, 13, null, "Sans affaire"));
        final SQLRowValues undefinedAffairInvoice = injector.createRowValuesFrom(order(fixture, 14, 1, "Affaire indéfinie"));

        assertTrue("null affair field is present", nullAffairInvoice.getFields().contains("ID_AFFAIRE"));
        assertEquals("null affair stays null", null, nullAffairInvoice.getObject("ID_AFFAIRE"));
        assertEquals("OpenConcerto undefined ID stays undefined", 1, undefinedAffairInvoice.getObject("ID_AFFAIRE"));
        pass();
    }

    private static void testRepeatedRegistrationKeepsOneAffairMapping() {
        final Fixture fixture = new Fixture(true, true);
        final SupplierOrderToInvoiceSQLInjector first = new SupplierOrderToInvoiceSQLInjector(fixture.root);
        final int initialMappingCount = first.getFrom().size();
        final SupplierOrderToInvoiceSQLInjector second = new SupplierOrderToInvoiceSQLInjector(fixture.root);

        assertEquals("mapping count is stable", initialMappingCount, second.getFrom().size());
        assertEquals("only one affair mapping", 1, countMappings(second, "ID_AFFAIRE"));
        assertSame("latest registration is used", second, SQLInjector.getInjector(fixture.orders, fixture.invoices));
        pass();
    }

    private static void testSuccessiveTransfersAreIndependent() {
        final Fixture fixture = new Fixture(true, true);
        final SupplierOrderToInvoiceSQLInjector injector = new SupplierOrderToInvoiceSQLInjector(fixture.root);

        final SQLRowValues firstInvoice = injector.createRowValuesFrom(order(fixture, 15, 410, "Première affaire"));
        final SQLRowValues secondInvoice = injector.createRowValuesFrom(order(fixture, 16, 420, "Deuxième affaire"));

        assertEquals("first invoice keeps first affair", 410, firstInvoice.getObject("ID_AFFAIRE"));
        assertEquals("second invoice gets second affair", 420, secondInvoice.getObject("ID_AFFAIRE"));
        assertTrue("destination rows are distinct", firstInvoice != secondInvoice);
        pass();
    }

    private static void testMultipleOrdersFromTheSameAffair() {
        final Fixture fixture = new Fixture(true, true);
        final SupplierOrderToInvoiceSQLInjector injector = new SupplierOrderToInvoiceSQLInjector(fixture.root);

        final SQLRowValues invoice = injector.createRowValuesFrom(Arrays.asList(order(fixture, 17, 510, "Commande A"), order(fixture, 18, 510, "Commande B")));

        assertEquals("shared affair retained for grouped transfer", 510, invoice.getObject("ID_AFFAIRE"));
        pass();
    }

    private static void testGroupedOrdersKeepLineAffairsSeparate() {
        final Fixture fixture = new Fixture(true, true);
        final SupplierOrderToInvoiceSQLInjector injector = new SupplierOrderToInvoiceSQLInjector(fixture.root);
        final SQLRowValues firstOrder = order(fixture, 25, 810, "Commande groupe A");
        final SQLRowValues secondOrder = order(fixture, 26, 820, "Commande groupe B");
        line(fixture, firstOrder, null, "Ligne A");
        line(fixture, secondOrder, null, "Ligne B");

        final SQLRowValues invoice = injector.createRowValuesFrom(Arrays.asList(firstOrder, secondOrder));
        final List<SQLRowValues> lines = invoiceLines(fixture, invoice);

        assertEquals("two grouped invoice lines", 2, lines.size());
        assertEquals("first grouped line keeps first affair", 810, lines.get(0).getObject("ID_AFFAIRE"));
        assertEquals("second grouped line keeps second affair", 820, lines.get(1).getObject("ID_AFFAIRE"));
        pass();
    }

    private static void testMissingAffairColumnsDegradeSafely() {
        final boolean[] presence = new boolean[] { false, true };
        for (final boolean sourceHasAffair : presence) {
            for (final boolean destinationHasAffair : presence) {
                final Fixture fixture = new Fixture(sourceHasAffair, destinationHasAffair);
                final SupplierOrderToInvoiceSQLInjector injector = new SupplierOrderToInvoiceSQLInjector(fixture.root);
                final SQLRowValues invoice = injector.createRowValuesFrom(order(fixture, 19, 610, "Schéma partiel"));

                assertEquals("native transfer still works", "Schéma partiel", invoice.getObject("NOM"));
                assertEquals("affair mapped only when both columns exist", sourceHasAffair && destinationHasAffair,
                        invoice.getFields().contains("ID_AFFAIRE"));
                if (sourceHasAffair && destinationHasAffair) {
                    assertEquals("affair copied when available", 610, invoice.getObject("ID_AFFAIRE"));
                }
            }
        }
        pass();
    }

    private static void testSourceOrderIsNeverModified() {
        final Fixture fixture = new Fixture(true, true);
        final SupplierOrderToInvoiceSQLInjector injector = new SupplierOrderToInvoiceSQLInjector(fixture.root);
        final SQLRowValues order = order(fixture, 20, 710, "Commande source");
        final int initialFieldCount = order.getFields().size();

        final SQLRowValues invoice = injector.createRowValuesFrom(order);
        invoice.put("ID_AFFAIRE", 999);

        assertEquals("source field count unchanged", initialFieldCount, order.getFields().size());
        assertEquals("source affair unchanged after invoice edit", 710, order.getObject("ID_AFFAIRE"));
        assertEquals("source name unchanged", "Commande source", order.getObject("NOM"));
        pass();
    }

    private static void testInvoiceHeaderExposesAffairField() {
        final ComponentsContext ctxt = new ComponentsContext();
        final AffairLinkSupport.Schema schema = AffairLinkSupport.schemaOf(
                new java.util.LinkedHashSet<String>(Arrays.asList("FACTURE_FOURNISSEUR")),
                java.util.Collections.<String, java.util.Set<String>> singletonMap("FACTURE_FOURNISSEUR",
                        new java.util.LinkedHashSet<String>(Arrays.asList("ID_AFFAIRE"))));

        final AffairLinkSupport.RegistrationReport report = SupplierInvoiceAffairComponentSupport.register(ctxt, schema);

        assertEquals("affair field registered on supplier invoice header", "FACTURE_FOURNISSEUR", ctxt.getTableName());
        assertEquals("registered header field", "ID_AFFAIRE", ctxt.getFieldName());
        assertEquals("single component registration", 1, ctxt.getRegistrationCount());
        assertEquals("report lists the addition", Arrays.asList("FACTURE_FOURNISSEUR"), report.getAdded());
        assertTrue("report is complete", report.isComplete());
        pass();
    }

    /**
     * Regression du plantage « Already added ID_AFFAIRE in
     * FactureFournisseurSQLElement » : chaque table ne doit etre declaree
     * qu'une fois, meme quand plusieurs documents la concernent.
     */
    private static void testAffairFieldDeclaredOncePerTable() {
        final ComponentsContext ctxt = new ComponentsContext();
        final AffairLinkSupport.Schema schema = AffairLinkSupport.schemaOf(
                new java.util.LinkedHashSet<String>(Arrays.asList("COMMANDE", "FACTURE_FOURNISSEUR", "SAISIE_ACHAT")),
                fieldsMap("COMMANDE", "FACTURE_FOURNISSEUR", "SAISIE_ACHAT"));

        final AffairLinkSupport.RegistrationReport report = SupplierInvoiceAffairComponentSupport.register(ctxt, schema);

        assertEquals("three distinct declarations", 3, ctxt.getRegistrationCount());
        assertEquals("no duplicate", new java.util.LinkedHashSet<String>(ctxt.getRegistrations()).size(), ctxt.getRegistrations().size());
        assertTrue("supplier invoice declared", ctxt.getRegistrations().contains("FACTURE_FOURNISSEUR.ID_AFFAIRE"));
        assertEquals("nothing already present", 0, report.getAlreadyPresent().size());
        pass();
    }

    private static void testModuleStartupSurvivesAlreadyDeclaredField() {
        final ComponentsContext ctxt = new ComponentsContext();
        final AffairLinkSupport.Schema schema = AffairLinkSupport.schemaOf(
                new java.util.LinkedHashSet<String>(Arrays.asList("COMMANDE", "FACTURE_FOURNISSEUR")),
                fieldsMap("COMMANDE", "FACTURE_FOURNISSEUR"));

        final AffairLinkSupport.RegistrationReport first = SupplierInvoiceAffairComponentSupport.register(ctxt, schema);
        // Deuxieme declaration : le contexte reel leve IllegalStateException.
        final AffairLinkSupport.RegistrationReport second = SupplierInvoiceAffairComponentSupport.register(ctxt, schema);

        assertEquals("first call adds everything", 2, first.getAdded().size());
        assertEquals("second call adds nothing", 0, second.getAdded().size());
        assertEquals("second call reports the existing fields", 2, second.getAlreadyPresent().size());
        assertTrue("second call is not an error", second.isComplete());
        assertEquals("each table declared once", 2, ctxt.getRegistrationCount());
        pass();
    }

    private static void testModuleStartupSurvivesFieldNotCreatedByModule() {
        final ComponentsContext ctxt = new ComponentsContext();
        ctxt.refuseFieldOf("SAISIE_ACHAT.ID_AFFAIRE");
        final AffairLinkSupport.Schema schema = AffairLinkSupport.schemaOf(
                new java.util.LinkedHashSet<String>(Arrays.asList("COMMANDE", "SAISIE_ACHAT")),
                fieldsMap("COMMANDE", "SAISIE_ACHAT"));

        final AffairLinkSupport.RegistrationReport report = SupplierInvoiceAffairComponentSupport.register(ctxt, schema);

        assertEquals("refused table is reported, not thrown", 1, report.getRefused().size());
        assertTrue("refusal names the table", report.getRefused().get(0).startsWith("SAISIE_ACHAT"));
        assertEquals("other tables are still declared", Arrays.asList("COMMANDE"), report.getAdded());
        pass();
    }

    /** Schema de test : les tables donnees portent toutes ID_AFFAIRE. */
    private static java.util.Map<String, java.util.Set<String>> fieldsMap(final String... tables) {
        final java.util.Map<String, java.util.Set<String>> fields = new java.util.HashMap<String, java.util.Set<String>>();
        for (final String table : tables) {
            fields.put(table, new java.util.LinkedHashSet<String>(Arrays.asList("ID_AFFAIRE")));
        }
        return fields;
    }

    private static void testUndefinedLineAffairsUseOrderAffair() {
        final Fixture fixture = new Fixture(true, true);
        final SupplierOrderToInvoiceSQLInjector injector = new SupplierOrderToInvoiceSQLInjector(fixture.root);
        final SQLRowValues order = order(fixture, 21, 720, "Lignes sans affaire");
        final SQLRowValues nullLine = line(fixture, order, null, "Affaire NULL");
        final SQLRowValues undefinedLine = line(fixture, order, 1, "Affaire indéfinie");

        final SQLRowValues invoice = injector.createRowValuesFrom(order);
        final List<SQLRowValues> lines = invoiceLines(fixture, invoice);

        assertEquals("two transferred lines", 2, lines.size());
        assertEquals("NULL line affair uses order affair", 720, lines.get(0).getObject("ID_AFFAIRE"));
        assertEquals("undefined line affair uses order affair", 720, lines.get(1).getObject("ID_AFFAIRE"));
        assertEquals("source NULL line unchanged", null, nullLine.getObject("ID_AFFAIRE"));
        assertEquals("source undefined line unchanged", 1, undefinedLine.getObject("ID_AFFAIRE"));
        pass();
    }

    private static void testDefinedLineAffairIsPreserved() {
        final Fixture fixture = new Fixture(true, true);
        final SupplierOrderToInvoiceSQLInjector injector = new SupplierOrderToInvoiceSQLInjector(fixture.root);
        final SQLRowValues order = order(fixture, 22, 730, "Affaire de ligne précise");
        line(fixture, order, 999, "Affaire différente");

        final SQLRowValues invoice = injector.createRowValuesFrom(order);

        assertEquals("header keeps order affair", 730, invoice.getObject("ID_AFFAIRE"));
        assertEquals("defined line affair is not overwritten", 999, onlyInvoiceLine(fixture, invoice).getObject("ID_AFFAIRE"));
        pass();
    }

    private static void testNoOrderAffairLeavesLineAffairsUndefined() {
        final Fixture fixture = new Fixture(true, true);
        final SupplierOrderToInvoiceSQLInjector injector = new SupplierOrderToInvoiceSQLInjector(fixture.root);
        final SQLRowValues order = order(fixture, 23, null, "Sans affaire ni ligne");
        line(fixture, order, null, "Ligne NULL");
        line(fixture, order, 1, "Ligne indéfinie");

        final SQLRowValues invoice = injector.createRowValuesFrom(order);
        final List<SQLRowValues> lines = invoiceLines(fixture, invoice);

        assertEquals("NULL line affair stays NULL", null, lines.get(0).getObject("ID_AFFAIRE"));
        assertEquals("undefined line affair stays undefined", 1, lines.get(1).getObject("ID_AFFAIRE"));
        pass();
    }

    private static void testMissingLineAffairColumnDoesNotBlockTransfer() {
        final Fixture fixture = new Fixture(true, true, false);
        final SupplierOrderToInvoiceSQLInjector injector = new SupplierOrderToInvoiceSQLInjector(fixture.root);
        final SQLRowValues order = order(fixture, 24, 740, "Lignes sans colonne affaire");
        line(fixture, order, null, "Article sans colonne affaire");

        final SQLRowValues invoice = injector.createRowValuesFrom(order);
        final SQLRowValues invoiceLine = onlyInvoiceLine(fixture, invoice);

        assertEquals("header affair still copied", 740, invoice.getObject("ID_AFFAIRE"));
        assertEquals("native line copy retained", "Article sans colonne affaire", invoiceLine.getObject("DESIGNATION"));
        assertTrue("no line affair invented without column", !invoiceLine.getFields().contains("ID_AFFAIRE"));
        pass();
    }

    private static SQLRowValues order(final Fixture fixture, final int id, final Object affairID, final String name) {
        final SQLRowValues order = new SQLRowValues(fixture.orders);
        order.put("ID", id);
        order.put("ID_FOURNISSEUR", 50 + id);
        order.put("NOM", name);
        order.put("INFOS", "Informations commande " + id);
        if (fixture.orders.contains("ID_AFFAIRE")) {
            order.put("ID_AFFAIRE", affairID);
        }
        return order;
    }

    private static SQLRowValues line(final Fixture fixture, final SQLRowValues order, final Object affairID, final String designation) {
        final SQLRowValues line = new SQLRowValues(fixture.orderLines);
        line.put("ID", ++fixture.nextLineID);
        line.put("DESIGNATION", designation);
        if (fixture.orderLines.contains("ID_AFFAIRE")) {
            line.put("ID_AFFAIRE", affairID);
        }
        line.put("ID_COMMANDE", order);
        return line;
    }

    private static List<SQLRowValues> invoiceLines(final Fixture fixture, final SQLRowValues invoice) {
        return new ArrayList<SQLRowValues>(invoice.getReferentRows(fixture.invoiceLines));
    }

    private static SQLRowValues onlyInvoiceLine(final Fixture fixture, final SQLRowValues invoice) {
        final List<SQLRowValues> lines = invoiceLines(fixture, invoice);
        assertEquals("one transferred invoice line", 1, lines.size());
        return lines.get(0);
    }

    private static int countMappings(final SupplierOrderToInvoiceSQLInjector injector, final String fieldName) {
        int result = 0;
        for (final SQLField field : injector.getFrom()) {
            if (fieldName.equals(field.getName())) {
                result++;
            }
        }
        return result;
    }

    private static void pass() {
        testCount++;
    }

    private static void assertTrue(final String message, final boolean condition) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    private static void assertSame(final String message, final Object expected, final Object actual) {
        if (expected != actual) {
            throw new AssertionError(message + ": expected same instance");
        }
    }

    private static void assertEquals(final String message, final Object expected, final Object actual) {
        if (expected == null ? actual != null : !expected.equals(actual)) {
            throw new AssertionError(message + ": expected <" + expected + ">, got <" + actual + ">");
        }
    }

    private static final class Fixture {

        private final DBRoot root = new DBRoot();
        private final SQLTable orders;
        private final SQLTable invoices;
        private final SQLTable orderLines;
        private final SQLTable invoiceLines;
        private int nextLineID;

        private Fixture(final boolean sourceHasAffair, final boolean destinationHasAffair) {
            this(sourceHasAffair, destinationHasAffair, true);
        }

        private Fixture(final boolean sourceHasAffair, final boolean destinationHasAffair, final boolean linesHaveAffair) {
            this.orders = table(this.root, "COMMANDE", sourceHasAffair);
            this.invoices = table(this.root, "FACTURE_FOURNISSEUR", destinationHasAffair);
            this.orderLines = lineTable(this.root, "COMMANDE_ELEMENT", "ID_COMMANDE", linesHaveAffair);
            this.invoiceLines = lineTable(this.root, "FACTURE_FOURNISSEUR_ELEMENT", "ID_FACTURE_FOURNISSEUR", linesHaveAffair);
        }

        private static SQLTable lineTable(final DBRoot root, final String name, final String parentField, final boolean withAffair) {
            final SQLTable table = new SQLTable(root, name);
            root.addTable(table);
            table.addField("ID");
            table.addField(parentField);
            table.addField("DESIGNATION");
            if (withAffair) {
                table.addField("ID_AFFAIRE");
            }
            return table;
        }

        private static SQLTable table(final DBRoot root, final String name, final boolean withAffair) {
            final SQLTable table = new SQLTable(root, name);
            root.addTable(table);
            table.addField("ID");
            table.addField("ID_FOURNISSEUR");
            table.addField("NOM");
            table.addField("INFOS");
            if (withAffair) {
                table.addField("ID_AFFAIRE");
            }
            return table;
        }
    }
}
