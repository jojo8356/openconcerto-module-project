package org.openconcerto.modules.currency;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

public final class CurrencyTemplateSupportTest {

    public static void main(String[] args) {
        testCurrencyVariantIsSelectedWhenAvailable();
        testNormalTemplateIsUsedWhenVariantIsMissing();
        testExplicitModelVariantIsPreserved();
        testInvalidCurrencyCodeDoesNotChangeTemplate();
        System.out.println("CurrencyTemplateSupportTest: OK");
    }

    private static void testCurrencyVariantIsSelectedWhenAvailable() {
        final Set<String> templates = new HashSet<String>(Arrays.asList("VenteFacture_USD"));
        assertEquals("VenteFacture_USD", CurrencyTemplateSupport.selectTemplateId("VenteFacture", "usd", availability(templates)), "available currency template");
    }

    private static void testNormalTemplateIsUsedWhenVariantIsMissing() {
        assertEquals("Devis", CurrencyTemplateSupport.selectTemplateId("Devis", "EUR", availability(new HashSet<String>())), "missing currency template fallback");
    }

    private static void testExplicitModelVariantIsPreserved() {
        final Set<String> templates = new HashSet<String>(Arrays.asList("CustomInvoice_GBP"));
        assertEquals("CustomInvoice_GBP", CurrencyTemplateSupport.selectTemplateId("CustomInvoice", "gbp", availability(templates)), "explicit model currency variant");
        assertEquals("CustomInvoice", CurrencyTemplateSupport.selectTemplateId("CustomInvoice", "USD", availability(templates)), "explicit model fallback");
    }

    private static void testInvalidCurrencyCodeDoesNotChangeTemplate() {
        final Set<String> templates = new HashSet<String>(Arrays.asList("VenteFacture_XXX"));
        assertEquals("VenteFacture", CurrencyTemplateSupport.selectTemplateId("VenteFacture", "€", availability(templates)), "non-ISO currency code");
        assertEquals("VenteFacture", CurrencyTemplateSupport.selectTemplateId("VenteFacture", null, availability(templates)), "missing currency");
    }

    private static CurrencyTemplateSupport.TemplateAvailability availability(final Set<String> availableTemplates) {
        return new CurrencyTemplateSupport.TemplateAvailability() {
            @Override
            public boolean exists(String templateId) {
                return availableTemplates.contains(templateId);
            }
        };
    }

    private static void assertEquals(String expected, String actual, String message) {
        if (expected == null ? actual != null : !expected.equals(actual)) {
            throw new AssertionError(message + ": expected '" + expected + "', got '" + actual + "'");
        }
    }
}
