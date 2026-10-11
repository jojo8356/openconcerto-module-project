package org.openconcerto.modules.currency;

import org.openconcerto.erp.generationDoc.gestcomm.AvoirClientXmlSheet;
import org.openconcerto.sql.model.SQLRow;

/** Uses an optional currency-specific XML/ODS template for a customer credit note. */
public final class CurrencyAwareAvoirClientXmlSheet extends AvoirClientXmlSheet {

    public CurrencyAwareAvoirClientXmlSheet(SQLRow row) {
        super(row);
    }

    @Override
    public String getTemplateId() {
        return CurrencyTemplateResolver.selectTemplateId(this, this.row, super.getTemplateId());
    }
}
