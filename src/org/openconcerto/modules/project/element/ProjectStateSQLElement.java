package org.openconcerto.modules.project.element;

import java.util.Arrays;
import java.util.List;

import org.openconcerto.erp.core.common.element.ComptaSQLConfElement;
import org.openconcerto.sql.element.SQLComponent;
import org.openconcerto.sql.element.UISQLComponent;
import org.openconcerto.utils.ListMap;

public class ProjectStateSQLElement extends ComptaSQLConfElement {
    public static final int A_TRAITER = 2;
    public static final int EN_COURS = 3;
    public static final int TRAITEMENT_TERMINE = 4;
    public static final int A_FACTURER = 5;
    public static final int DOSSIER_CLOS = 6;

    public ProjectStateSQLElement() {
        super("ETAT_AFFAIRE", "un état affaire", "états affaires");
    }

    @Override
    protected List<String> getListFields() {
        return Arrays.asList("NOM");
    }

    @Override
    protected List<String> getComboFields() {
        return Arrays.asList("NOM");
    }

    @Override
    public ListMap<String, String> getShowAs() {
        return ListMap.singleton(null, getComboFields());
    }

    @Override
    public SQLComponent createComponent() {
        return new UISQLComponent(this) {
            @Override
            protected void addViews() {
                this.addView("NOM");
            }
        };
    }

    @Override
    protected String createCode() {
        return "project.state";
    }
}
