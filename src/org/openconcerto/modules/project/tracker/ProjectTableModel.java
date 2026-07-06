package org.openconcerto.modules.project.tracker;

import java.util.ArrayList;
import java.util.List;

import javax.swing.table.AbstractTableModel;

public class ProjectTableModel extends AbstractTableModel {
    private final List<TrackedProject> list;

    public ProjectTableModel(List<TrackedProject> l) {
        list = l;
    }

    @Override
    public int getRowCount() {
        return list.size() + 1;
    }

    @Override
    public int getColumnCount() {
        final List<String> l = getColumns();
        return l.size() + 1;
    }

    private List<String> getColumns() {
        List<String> l = new ArrayList<String>();
        for (TrackedProject trackedProject : list) {
            String[] t = trackedProject.getTypes();
            for (int i = 0; i < t.length; i++) {
                String string = t[i];
                if (!l.contains(string)) {
                    l.add(string);
                }
            }
        }
        return l;
    }

    @Override
    public String getColumnName(int columnIndex) {
        if (columnIndex == 0) {
            return "Projets";
        }
        return getColumns().get(columnIndex - 1);
    }

    @Override
    public Class<?> getColumnClass(int columnIndex) {
        return String.class;
    }

    @Override
    public boolean isCellEditable(int rowIndex, int columnIndex) {
        return false;
    }

    @Override
    public Object getValueAt(int rowIndex, int columnIndex) {
        if (rowIndex == getRowCount() - 1) {
            if (columnIndex == 0) {
                return "Total";
            } else {
                String n = getColumnName(columnIndex);
                int total = 0;
                for (TrackedProject trackedProject : list) {
                    total += trackedProject.getDuration(n);
                }
                return total + "s";
            }
        }

        final TrackedProject trackedProject = list.get(rowIndex);
        if (columnIndex == 0) {
            return trackedProject.getTitle();
        }
        String n = getColumnName(columnIndex);
        return trackedProject.getDuration(n) + "s";
    }

    @Override
    public void setValueAt(Object aValue, int rowIndex, int columnIndex) {
    }

}
