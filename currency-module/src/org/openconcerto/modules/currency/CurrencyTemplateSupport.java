package org.openconcerto.modules.currency;

import java.util.Locale;

/**
 * Selects an optional currency-specific OpenConcerto document template.
 *
 * <p>Currency variants follow the convention {@code <templateId>_<ISO currency code>}, for example
 * {@code VenteFacture_USD}. The selected OpenConcerto template remains the fallback.</p>
 */
public final class CurrencyTemplateSupport {

    public interface TemplateAvailability {
        boolean exists(String templateId);
    }

    private CurrencyTemplateSupport() {
    }

    /**
     * Resolve a template ID without changing the model selected by OpenConcerto unless a matching
     * currency variant exists.
     *
     * @param selectedTemplateId the template ID selected by OpenConcerto for this document
     * @param currencyCode the client's ISO currency code
     * @param availability checks whether the template (including its language/type variant) exists
     * @return the currency-specific template ID when available, otherwise {@code selectedTemplateId}
     */
    public static String selectTemplateId(final String selectedTemplateId, final String currencyCode, final TemplateAvailability availability) {
        if (selectedTemplateId == null || selectedTemplateId.trim().isEmpty() || availability == null) {
            return selectedTemplateId;
        }

        final String normalizedCode = normalizeCurrencyCode(currencyCode);
        if (normalizedCode == null) {
            return selectedTemplateId;
        }

        final String candidate = selectedTemplateId + "_" + normalizedCode;
        return availability.exists(candidate) ? candidate : selectedTemplateId;
    }

    static String normalizeCurrencyCode(final String currencyCode) {
        if (currencyCode == null) {
            return null;
        }
        final String code = currencyCode.trim().toUpperCase(Locale.ROOT);
        if (code.length() != 3) {
            return null;
        }
        for (int i = 0; i < code.length(); i++) {
            final char c = code.charAt(i);
            if (c < 'A' || c > 'Z') {
                return null;
            }
        }
        return code;
    }
}
