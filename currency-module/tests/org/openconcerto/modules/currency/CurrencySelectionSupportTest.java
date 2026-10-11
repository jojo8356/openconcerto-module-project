package org.openconcerto.modules.currency;

public final class CurrencySelectionSupportTest {

    public static void main(String[] args) {
        assertTrue(CurrencySelectionSupport.shouldPersistSelection(2, 3), "different currency is persisted");
        assertTrue(CurrencySelectionSupport.shouldPersistSelection(-1, 3), "a currency can be assigned when none is currently set");
        assertFalse(CurrencySelectionSupport.shouldPersistSelection(3, 3), "unchanged currency is not rewritten");
        assertFalse(CurrencySelectionSupport.shouldPersistSelection(3, -1), "empty selection is not persisted");
        assertFalse(CurrencySelectionSupport.shouldPersistSelection(-1, -1), "empty current and selected values are not persisted");
        System.out.println("CurrencySelectionSupportTest: OK");
    }

    private static void assertTrue(boolean value, String message) {
        if (!value) {
            throw new AssertionError(message);
        }
    }

    private static void assertFalse(boolean value, String message) {
        if (value) {
            throw new AssertionError(message);
        }
    }
}
