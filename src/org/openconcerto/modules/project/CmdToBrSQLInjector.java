package org.openconcerto.modules.project;

import org.openconcerto.sql.Configuration;

public class CmdToBrSQLInjector extends org.openconcerto.erp.injector.CommandeBrSQLInjector {

    public CmdToBrSQLInjector() {
        super(Configuration.getInstance().getRoot());
        if (getSource().contains("ID_AFFAIRE") && getDestination().contains("ID_AFFAIRE")) {
            map(getSource().getField("ID_AFFAIRE"), getDestination().getField("ID_AFFAIRE"));
        }
    }
}
