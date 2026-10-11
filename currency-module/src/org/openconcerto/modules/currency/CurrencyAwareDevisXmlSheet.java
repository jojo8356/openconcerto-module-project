package org.openconcerto.modules.currency;

import org.openconcerto.erp.core.sales.quote.report.DevisXmlSheet;
import org.openconcerto.sql.model.SQLRow;

/** Uses an optional currency-specific XML/ODS template for a quote. */
public final class CurrencyAwareDevisXmlSheet extends DevisXmlSheet {

    public CurrencyAwareDevisXmlSheet(SQLRow row) {
        super(row);
    }

    @Override
    public String getTemplateId() {
        return CurrencyTemplateResolver.selectTemplateId(this, this.row, super.getTemplateId());
    }
}
