package org.openconcerto.modules.project.element;

import java.util.Arrays;
import java.util.List;

import org.openconcerto.erp.core.common.element.ComptaSQLConfElement;
import org.openconcerto.sql.element.SQLComponent;
import org.openconcerto.sql.element.UISQLComponent;
import org.openconcerto.utils.ListMap;

public class ProjectTypeSQLElement extends ComptaSQLConfElement {

    public ProjectTypeSQLElement() {
        super("TYPE_AFFAIRE", "un type d'affaire", "types d'affaire");
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
        return "project.type";
    }
}
