package org.openconcerto.modules.currency;

import java.io.IOException;
import java.math.BigDecimal;
import java.sql.SQLException;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

import org.openconcerto.sql.model.SQLRow;
import org.openconcerto.sql.model.SQLRowListRSH;
import org.openconcerto.sql.model.SQLRowValues;
import org.openconcerto.sql.model.SQLSelect;
import org.openconcerto.sql.model.SQLTable;

/** Idempotently reconciles OpenConcerto's DEVISE catalogue with the current ISO 4217 List One. */
public final class CurrencyCatalogSynchronizer {

    private static final Logger LOGGER = Logger.getLogger(CurrencyCatalogSynchronizer.class.getName());
    private static final BigDecimal INITIAL_RATE = BigDecimal.ONE;

    private CurrencyCatalogSynchronizer() {
    }

    /**
     * Downloads and validates the complete ISO feed before changing the database. Existing manual
     * exchange rates are deliberately preserved; newly imported rates start at 1 and can be edited
     * in OpenConcerto's normal currency form.
     */
    public static synchronized Result synchronize(SQLTable currencyTable) throws IOException, SQLException {
        if (currencyTable == null || !currencyTable.contains("CODE")) {
            throw new IllegalArgumentException("La table DEVISE doit contenir le champ CODE.");
        }

        // Validate/download first, so a timeout, HTML error page, or truncated response never
        // leaves the database half-populated.
        final List<Iso4217CurrencyCatalog.CurrencyDefinition> definitions = Iso4217CurrencyCatalog.download();
        final Map<String, SQLRow> existingByCode = loadExistingCurrencies(currencyTable);
        int inserted = 0;
        int updated = 0;
        int unchanged = 0;
        int failed = 0;

        for (Iso4217CurrencyCatalog.CurrencyDefinition definition : definitions) {
            final String code = definition.getCode();
            final SQLRow existing = existingByCode.get(code);
            try {
                if (existing == null) {
                    final SQLRowValues values = new SQLRowValues(currencyTable);
                    values.put("CODE", code);
                    if (currencyTable.contains("NOM")) {
                        values.put("NOM", definition.getName());
                    }
                    if (currencyTable.contains("TAUX")) {
                        values.put("TAUX", INITIAL_RATE);
                    }
                    if (currencyTable.contains("TAUX_COMMERCIAL")) {
                        values.put("TAUX_COMMERCIAL", INITIAL_RATE);
                    }
                    final SQLRow insertedRow = values.insert();
                    existingByCode.put(code, insertedRow);
                    inserted++;
                } else {
                    final SQLRowValues values = new SQLRowValues(currencyTable);
                    boolean changed = false;
                    if (!code.equals(existing.getString("CODE"))) {
                        values.put("CODE", code);
                        changed = true;
                    }
                    if (currencyTable.contains("NOM") && !definition.getName().equals(existing.getString("NOM"))) {
                        values.put("NOM", definition.getName());
                        changed = true;
                    }
                    if (currencyTable.isArchivable() && isArchived(existing)) {
                        final Class<?> archiveType = currencyTable.getArchiveField().getType().getJavaType();
                        final Object unarchivedValue = Boolean.class.equals(archiveType) ? Boolean.FALSE : Integer.valueOf(0);
                        values.put("ARCHIVE", unarchivedValue);
                        changed = true;
                    }
                    if (changed) {
                        values.update(existing.getID());
                        updated++;
                    } else {
                        unchanged++;
                    }
                }
            } catch (Exception e) {
                // Continue with the rest of the official list. A single damaged/custom row must not
                // prevent all other currencies from being saved; the next sync retries it.
                failed++;
                LOGGER.log(Level.WARNING, "Impossible de synchroniser la devise ISO " + code + ".", e);
            }
        }

        return new Result(definitions.size(), inserted, updated, unchanged, failed);
    }

    private static boolean isArchived(SQLRow row) {
        final Object value = row.getObject("ARCHIVE");
        if (value instanceof Boolean) {
            return ((Boolean) value).booleanValue();
        }
        if (value instanceof Number) {
            return ((Number) value).intValue() != 0;
        }
        return value != null && Boolean.parseBoolean(value.toString());
    }

    private static Map<String, SQLRow> loadExistingCurrencies(SQLTable currencyTable) throws SQLException {
        final SQLSelect select = new SQLSelect();
        // Include archived rows so an ISO code can be reactivated rather than inserted twice.
        // Keep SQLSelect's default exclusion of OpenConcerto's undefined row.
        select.setArchivedPolicy(SQLSelect.BOTH);
        select.addSelect(currencyTable.getKey());
        select.addSelect(currencyTable.getField("CODE"));
        if (currencyTable.contains("NOM")) {
            select.addSelect(currencyTable.getField("NOM"));
        }
        if (currencyTable.contains("ARCHIVE")) {
            select.addSelect(currencyTable.getField("ARCHIVE"));
        }

        final Map<String, SQLRow> result = new HashMap<String, SQLRow>();
        final List<SQLRow> rows = SQLRowListRSH.execute(select);
        for (SQLRow row : rows) {
            if (row.isUndefined()) {
                continue;
            }
            final String code = row.getString("CODE");
            if (code != null && !code.trim().isEmpty()) {
                final String normalized = code.trim().toUpperCase(Locale.ROOT);
                if (!result.containsKey(normalized)) {
                    result.put(normalized, row);
                }
            }
        }
        return result;
    }

    public static final class Result {
        private final int sourceCount;
        private final int insertedCount;
        private final int updatedCount;
        private final int unchangedCount;
        private final int failedCount;

        Result(int sourceCount, int insertedCount, int updatedCount, int unchangedCount, int failedCount) {
            this.sourceCount = sourceCount;
            this.insertedCount = insertedCount;
            this.updatedCount = updatedCount;
            this.unchangedCount = unchangedCount;
            this.failedCount = failedCount;
        }

        public int getSourceCount() {
            return this.sourceCount;
        }

        public int getInsertedCount() {
            return this.insertedCount;
        }

        public int getUpdatedCount() {
            return this.updatedCount;
        }

        public int getUnchangedCount() {
            return this.unchangedCount;
        }

        public int getFailedCount() {
            return this.failedCount;
        }

        public String getSummary() {
            return "Catalogue ISO reçu : " + this.sourceCount + " devises/fonds. " + this.insertedCount + " ajoutée(s), " + this.updatedCount + " mise(s) à jour, " + this.unchangedCount
                    + " déjà à jour, " + this.failedCount + " erreur(s).";
        }
    }
}
