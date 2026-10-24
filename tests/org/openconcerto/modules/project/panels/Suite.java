package org.openconcerto.modules.project.panels;

import java.util.List;

/** Une famille de controles. */
public interface Suite {

    String name();

    /**
     * @param db      acces lecture seule a la base
     * @param schemas schemas a controler
     * @param report  compte rendu a remplir
     */
    void run(Db db, List<String> schemas, Report report) throws Exception;
}
