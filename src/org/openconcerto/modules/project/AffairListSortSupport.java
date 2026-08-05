package org.openconcerto.modules.project;

import java.util.Comparator;

final class AffairListSortSupport {
    static final int DEFAULT_SORT_COMBO_INDEX = 1;
    static final boolean DEFAULT_SORT_BY_DATE = false;

    private AffairListSortSupport() {
    }

    static Comparator<Item> createDateComparator(final int undefinedID) {
        return new Comparator<Item>() {
            @Override
            public int compare(final Item item1, final Item item2) {
                if (isUndefined(undefinedID, item1)) {
                    return isUndefined(undefinedID, item2) ? 0 : 1;
                } else if (isUndefined(undefinedID, item2)) {
                    return -1;
                }
                final int dateCompare = compareNullableLongDesc(item1.getDate(), item2.getDate());
                if (dateCompare != 0) {
                    return dateCompare;
                }
                return item1.getNumero().compareToIgnoreCase(item2.getNumero());
            }
        };
    }

    static Comparator<Item> createNameComparator(final int undefinedID) {
        return new Comparator<Item>() {
            @Override
            public int compare(final Item item1, final Item item2) {
                if (isUndefined(undefinedID, item1)) {
                    return isUndefined(undefinedID, item2) ? 0 : -1;
                } else if (isUndefined(undefinedID, item2)) {
                    return 1;
                }
                return item1.getLabel().compareToIgnoreCase(item2.getLabel());
            }
        };
    }

    static String buildLabel(final String numero, final String client, final String nom, final String fallback) {
        final String cleanNumero = trim(numero);
        final String cleanClient = trim(client);
        final String cleanNom = trim(nom);
        final String cleanFallback = fallback == null ? "" : fallback;
        if (cleanNumero.length() > 0 && cleanClient.length() > 0) {
            return cleanNumero + " " + cleanClient;
        } else if (cleanNom.length() > 0 && cleanClient.length() > 0) {
            return cleanNom + " " + cleanClient;
        } else if (cleanClient.length() > 0) {
            return cleanClient;
        }
        if (cleanNumero.length() > 0 && cleanNom.length() > 0) {
            return cleanNumero + " " + cleanNom;
        } else if (cleanNumero.length() > 0) {
            return cleanNumero;
        } else if (cleanNom.length() > 0) {
            return cleanNom;
        }
        return cleanFallback;
    }

    private static boolean isUndefined(final int undefinedID, final Item item) {
        return item == null || item.getID() < 0 || item.getID() == undefinedID;
    }

    private static int compareNullableLongDesc(final Long value1, final Long value2) {
        if (value1 == null) {
            return value2 == null ? 0 : 1;
        } else if (value2 == null) {
            return -1;
        }
        return value2.compareTo(value1);
    }

    private static String trim(final String value) {
        return value == null ? "" : value.trim();
    }

    static final class Item {
        private final int id;
        private final Long date;
        private final String numero;
        private final String label;

        Item(final int id, final Long date, final String numero, final String label) {
            this.id = id;
            this.date = date;
            this.numero = numero == null ? "" : numero;
            this.label = label == null ? "" : label;
        }

        int getID() {
            return this.id;
        }

        Long getDate() {
            return this.date;
        }

        String getNumero() {
            return this.numero;
        }

        String getLabel() {
            return this.label;
        }
    }
}
