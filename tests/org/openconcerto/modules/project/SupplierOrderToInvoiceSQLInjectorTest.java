package org.openconcerto.modules.project;

import java.util.Arrays;

import org.openconcerto.erp.injector.CommandeFactureFournisseurSQLInjector;
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
        testMissingAffairColumnsDegradeSafely();
        testSourceOrderIsNeverModified();

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

        private Fixture(final boolean sourceHasAffair, final boolean destinationHasAffair) {
            this.orders = table(this.root, "COMMANDE", sourceHasAffair);
            this.invoices = table(this.root, "FACTURE_FOURNISSEUR", destinationHasAffair);
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
