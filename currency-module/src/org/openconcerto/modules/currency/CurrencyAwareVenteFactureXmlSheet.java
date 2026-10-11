package org.openconcerto.modules.currency;

import org.openconcerto.erp.core.sales.invoice.report.VenteFactureXmlSheet;
import org.openconcerto.sql.model.SQLRow;

/** Uses an optional currency-specific XML/ODS template for a sales invoice. */
public final class CurrencyAwareVenteFactureXmlSheet extends VenteFactureXmlSheet {

    public CurrencyAwareVenteFactureXmlSheet(SQLRow row) {
        super(row);
    }

    @Override
    public String getTemplateId() {
        return CurrencyTemplateResolver.selectTemplateId(this, this.row, super.getTemplateId());
    }
}
