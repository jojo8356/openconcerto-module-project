package org.openconcerto.modules.currency;

import org.openconcerto.erp.core.sales.order.report.CommandeClientXmlSheet;
import org.openconcerto.sql.model.SQLRow;

/** Uses an optional currency-specific XML/ODS template for a customer order. */
public final class CurrencyAwareCommandeClientXmlSheet extends CommandeClientXmlSheet {

    public CurrencyAwareCommandeClientXmlSheet(SQLRow row) {
        super(row);
    }

    @Override
    public String getTemplateId() {
        return CurrencyTemplateResolver.selectTemplateId(this, this.row, super.getTemplateId());
    }
}
