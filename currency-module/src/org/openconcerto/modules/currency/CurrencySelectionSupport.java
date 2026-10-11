package org.openconcerto.modules.currency;

/** Small, UI-independent rules for persisting a selected client currency. */
public final class CurrencySelectionSupport {

    private CurrencySelectionSupport() {
    }

    /**
     * Whether a selected foreign-row ID should be written to CLIENT.ID_DEVISE.
     * A negative ID is OpenConcerto's empty/non-existent combo selection.
     */
    public static boolean shouldPersistSelection(final int currentCurrencyID, final int selectedCurrencyID) {
        return selectedCurrencyID >= 0 && selectedCurrencyID != currentCurrencyID;
    }
}
