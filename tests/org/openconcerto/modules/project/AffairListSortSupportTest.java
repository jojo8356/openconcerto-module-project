package org.openconcerto.modules.project;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

public final class AffairListSortSupportTest {

    public static void main(final String[] args) {
        testDefaultNameSort();
        testDateSort();
        testLabelConstruction();
        System.out.println("AffairListSortSupportTest OK");
    }

    private static void testDefaultNameSort() {
        assertEquals("default combo index", 1, AffairListSortSupport.DEFAULT_SORT_COMBO_INDEX);
        assertEquals("default sort mode", false, AffairListSortSupport.DEFAULT_SORT_BY_DATE);

        final List<AffairListSortSupport.Item> items = new ArrayList<AffairListSortSupport.Item>(Arrays.asList(
                item(4, null, "A-004", "Zeta client"),
                item(1, null, "", "Toutes les affaires"),
                item(3, null, "A-003", "alpha client"),
                item(2, null, "A-002", "Beta client")));

        Collections.sort(items, AffairListSortSupport.createNameComparator(1));

        assertIDs("default name sort", items, 1, 3, 2, 4);
    }

    private static void testDateSort() {
        final List<AffairListSortSupport.Item> items = new ArrayList<AffairListSortSupport.Item>(Arrays.asList(
                item(1, null, "", "Toutes les affaires"),
                item(2, day(2026, 1, 10), "A-010", "Older"),
                item(3, day(2026, 2, 20), "A-020", "Newest same date second"),
                item(4, null, "A-030", "No date"),
                item(5, day(2026, 2, 20), "A-005", "Newest same date first")));

        Collections.sort(items, AffairListSortSupport.createDateComparator(1));

        assertIDs("date sort", items, 5, 3, 2, 4, 1);
    }

    private static void testLabelConstruction() {
        assertEquals("numero and client first", "A-001 Client SA", AffairListSortSupport.buildLabel(" A-001 ", " Client SA ", "Ignored name", "fallback"));
        assertEquals("name and client", "Projet Client SA", AffairListSortSupport.buildLabel("", "Client SA", "Projet", "fallback"));
        assertEquals("numero and name", "A-001 Projet", AffairListSortSupport.buildLabel("A-001", "", "Projet", "fallback"));
        assertEquals("fallback", "fallback", AffairListSortSupport.buildLabel("", "", "", "fallback"));
    }

    private static AffairListSortSupport.Item item(final int id, final Long date, final String numero, final String label) {
        return new AffairListSortSupport.Item(id, date, numero, label);
    }

    private static Long day(final int year, final int month, final int day) {
        return Long.valueOf((year * 10000L) + (month * 100L) + day);
    }

    private static void assertIDs(final String message, final List<AffairListSortSupport.Item> items, final int... expected) {
        if (items.size() != expected.length) {
            throw new AssertionError(message + ": expected " + expected.length + " items, got " + items.size());
        }
        for (int i = 0; i < expected.length; i++) {
            if (items.get(i).getID() != expected[i]) {
                throw new AssertionError(message + ": expected id " + expected[i] + " at index " + i + ", got " + items.get(i).getID());
            }
        }
    }

    private static void assertEquals(final String message, final String expected, final String actual) {
        if (!expected.equals(actual)) {
            throw new AssertionError(message + ": expected <" + expected + ">, got <" + actual + ">");
        }
    }

    private static void assertEquals(final String message, final int expected, final int actual) {
        if (expected != actual) {
            throw new AssertionError(message + ": expected <" + expected + ">, got <" + actual + ">");
        }
    }

    private static void assertEquals(final String message, final boolean expected, final boolean actual) {
        if (expected != actual) {
            throw new AssertionError(message + ": expected <" + expected + ">, got <" + actual + ">");
        }
    }
}
