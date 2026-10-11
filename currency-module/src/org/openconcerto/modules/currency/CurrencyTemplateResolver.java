package org.openconcerto.modules.currency;

import java.io.IOException;
import java.io.InputStream;

import org.openconcerto.erp.generationDoc.AbstractSheetXml;
import org.openconcerto.erp.generationDoc.TemplateManager;
import org.openconcerto.sql.model.SQLRow;

/** OpenConcerto adapters used by the currency-aware XML sheet classes. */
final class CurrencyTemplateResolver {

    private CurrencyTemplateResolver() {
    }

    static String selectTemplateId(final AbstractSheetXml sheet, final SQLRow documentRow, final String selectedTemplateId) {
        final String currencyCode = getClientCurrencyCode(documentRow);
        return CurrencyTemplateSupport.selectTemplateId(selectedTemplateId, currencyCode, new CurrencyTemplateSupport.TemplateAvailability() {
            @Override
            public boolean exists(String templateId) {
                return hasTemplate(sheet, templateId);
            }
        });
    }

    private static String getClientCurrencyCode(SQLRow documentRow) {
        if (documentRow == null || !documentRow.getTable().contains("ID_CLIENT") || documentRow.isForeignEmpty("ID_CLIENT")) {
            return null;
        }
        final SQLRow clientRow = documentRow.getForeignRow("ID_CLIENT");
        if (clientRow == null || clientRow.isUndefined() || !clientRow.getTable().contains("ID_DEVISE") || clientRow.isForeignEmpty("ID_DEVISE")) {
            return null;
        }
        final SQLRow currencyRow = clientRow.getForeignRow("ID_DEVISE");
        if (currencyRow == null || currencyRow.isUndefined() || !currencyRow.getTable().contains("CODE")) {
            return null;
        }
        return currencyRow.getString("CODE");
    }

    private static boolean hasTemplate(AbstractSheetXml sheet, String templateId) {
        InputStream template = null;
        InputStream configuration = null;
        try {
            final SQLRow languageRow = sheet.getRowLanguage();
            final String language = languageRow == null || languageRow.isUndefined() || !languageRow.getTable().contains("CHEMIN") ? null : languageRow.getString("CHEMIN");
            template = TemplateManager.getInstance().getTemplate(templateId, language, sheet.getType());
            if (template == null) {
                return false;
            }
            configuration = TemplateManager.getInstance().getTemplateConfiguration(templateId, language, sheet.getType());
            return configuration != null;
        } catch (RuntimeException e) {
            // A missing template must never prevent generation with the normal OpenConcerto model.
            return false;
        } finally {
            closeQuietly(template);
            closeQuietly(configuration);
        }
    }

    private static void closeQuietly(InputStream stream) {
        if (stream != null) {
            try {
                stream.close();
            } catch (IOException e) {
                // The streams are used only to check availability; ignore close failures.
            }
        }
    }
}
