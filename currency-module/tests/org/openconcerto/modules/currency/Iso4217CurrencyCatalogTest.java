package org.openconcerto.modules.currency;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;

public final class Iso4217CurrencyCatalogTest {

    public static void main(String[] args) throws Exception {
        testCodesAreDeduplicatedAndNoCurrencyTerritoriesAreSkipped();
        testMalformedAndDtdXmlAreRejected();
        System.out.println("Iso4217CurrencyCatalogTest: OK");
    }

    private static void testCodesAreDeduplicatedAndNoCurrencyTerritoriesAreSkipped() throws IOException {
        final String xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
                + "<ISO_4217><CcyTbl>"
                + "<CcyNtry><CtryNm>FRANCE</CtryNm><CcyNm>Euro</CcyNm><Ccy>EUR</Ccy><CcyNbr>978</CcyNbr><CcyMnrUnts>2</CcyMnrUnts></CcyNtry>"
                + "<CcyNtry><CtryNm>MONACO</CtryNm><CcyNm>Euro</CcyNm><Ccy>EUR</Ccy><CcyNbr>978</CcyNbr><CcyMnrUnts>2</CcyMnrUnts></CcyNtry>"
                + "<CcyNtry><CtryNm>ANTARCTICA</CtryNm><CcyNm>No universal currency</CcyNm></CcyNtry>"
                + "<CcyNtry><CtryNm>JAPAN</CtryNm><CcyNm>Yen</CcyNm><Ccy>JPY</Ccy><CcyNbr>392</CcyNbr><CcyMnrUnts>0</CcyMnrUnts></CcyNtry>"
                + "</CcyTbl></ISO_4217>";
        final List<Iso4217CurrencyCatalog.CurrencyDefinition> currencies = Iso4217CurrencyCatalog.parse(bytes(xml));
        assertEquals(2, currencies.size(), "unique codes");
        assertEquals("EUR", currencies.get(0).getCode(), "first code");
        assertEquals("Euro", currencies.get(0).getName(), "currency name");
        assertEquals("978", currencies.get(0).getNumericCode(), "numeric code");
        assertEquals("0", currencies.get(1).getMinorUnits(), "minor unit");
    }

    private static void testMalformedAndDtdXmlAreRejected() throws IOException {
        assertIOException("<not-closed>");
        assertIOException("<!DOCTYPE ISO_4217 [<!ENTITY xxe SYSTEM \"file:///etc/passwd\">]><ISO_4217>&xxe;</ISO_4217>");
    }

    private static void assertIOException(String xml) {
        try {
            Iso4217CurrencyCatalog.parse(bytes(xml));
            throw new AssertionError("Expected IOException for untrusted XML");
        } catch (IOException expected) {
            // Expected: malformed XML and DTD/entity declarations are rejected.
        }
    }

    private static ByteArrayInputStream bytes(String xml) {
        return new ByteArrayInputStream(xml.getBytes(StandardCharsets.UTF_8));
    }

    private static void assertEquals(Object expected, Object actual, String message) {
        if (expected == null ? actual != null : !expected.equals(actual)) {
            throw new AssertionError(message + ": expected '" + expected + "', got '" + actual + "'");
        }
    }
}
