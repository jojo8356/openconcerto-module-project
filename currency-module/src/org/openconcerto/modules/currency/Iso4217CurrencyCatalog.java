package org.openconcerto.modules.currency;

import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;

import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.ParserConfigurationException;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.xml.sax.SAXException;

/** Downloads and parses the current ISO 4217 currency-and-funds list published by SIX. */
public final class Iso4217CurrencyCatalog {

    public static final String OFFICIAL_LIST_URL = "https://www.six-group.com/dam/download/financial-information/data-center/iso-currrency/lists/list-one.xml";
    private static final int CONNECT_TIMEOUT_MS = 8000;
    private static final int READ_TIMEOUT_MS = 12000;
    private static final int MINIMUM_VALID_CODES = 150;
    private static final Pattern ALPHA_CODE = Pattern.compile("[A-Z]{3}");

    private Iso4217CurrencyCatalog() {
    }

    public static List<CurrencyDefinition> download() throws IOException {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(OFFICIAL_LIST_URL).openConnection();
            connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
            connection.setReadTimeout(READ_TIMEOUT_MS);
            connection.setUseCaches(false);
            connection.setInstanceFollowRedirects(true);
            connection.setRequestMethod("GET");
            connection.setRequestProperty("Accept", "application/xml, text/xml;q=0.9, */*;q=0.1");
            connection.setRequestProperty("User-Agent", "OpenConcerto-Currency-Module/1.0");

            final int status = connection.getResponseCode();
            if (status < 200 || status >= 300) {
                throw new IOException("Le catalogue SIX a répondu avec le statut HTTP " + status);
            }

            final List<CurrencyDefinition> currencies;
            try (InputStream input = connection.getInputStream()) {
                currencies = parse(input);
            }
            if (currencies.size() < MINIMUM_VALID_CODES) {
                throw new IOException("Catalogue ISO 4217 incomplet : seulement " + currencies.size() + " codes distincts ont été reçus.");
            }
            return currencies;
        } finally {
            if (connection != null) {
                connection.disconnect();
            }
        }
    }

    /** Parse an ISO 4217 List One XML stream and deduplicate repeated country/currency rows by code. */
    public static List<CurrencyDefinition> parse(InputStream input) throws IOException {
        if (input == null) {
            throw new IOException("Flux XML ISO 4217 absent.");
        }

        try {
            final DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
            factory.setNamespaceAware(false);
            factory.setXIncludeAware(false);
            factory.setExpandEntityReferences(false);
            factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
            factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
            factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
            factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
            disableExternalAccess(factory);

            final DocumentBuilder builder = factory.newDocumentBuilder();
            final Document document = builder.parse(input);
            final NodeList entries = document.getElementsByTagName("CcyNtry");
            final Map<String, CurrencyDefinition> byCode = new LinkedHashMap<String, CurrencyDefinition>();
            for (int i = 0; i < entries.getLength(); i++) {
                final Node node = entries.item(i);
                if (!(node instanceof Element)) {
                    continue;
                }
                final Element entry = (Element) node;
                final String code = normalizeCode(childText(entry, "Ccy"));
                if (code == null) {
                    // List One also contains territories which have no universal currency.
                    continue;
                }
                String name = childText(entry, "CcyNm");
                if (name == null || name.trim().isEmpty()) {
                    name = code;
                }
                final CurrencyDefinition current = byCode.get(code);
                if (current == null) {
                    byCode.put(code, new CurrencyDefinition(code, name.trim(), childText(entry, "CcyNbr"), childText(entry, "CcyMnrUnts")));
                }
            }
            if (byCode.isEmpty()) {
                throw new IOException("Le document reçu ne contient aucun code devise ISO 4217 valide.");
            }
            return new ArrayList<CurrencyDefinition>(byCode.values());
        } catch (ParserConfigurationException e) {
            throw new IOException("Configuration sécurisée du parseur XML indisponible.", e);
        } catch (SAXException e) {
            throw new IOException("Le catalogue ISO 4217 reçu n'est pas un XML valide.", e);
        } catch (RuntimeException e) {
            throw new IOException("Impossible de lire le catalogue ISO 4217.", e);
        }
    }

    private static void disableExternalAccess(DocumentBuilderFactory factory) {
        try {
            factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "");
            factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
        } catch (IllegalArgumentException e) {
            // The parser features above still disable DTD and external-entity processing on older JREs.
        }
    }

    private static String normalizeCode(String value) {
        if (value == null) {
            return null;
        }
        final String code = value.trim().toUpperCase(Locale.ROOT);
        return ALPHA_CODE.matcher(code).matches() ? code : null;
    }

    private static String childText(Element parent, String tagName) {
        final NodeList children = parent.getChildNodes();
        for (int i = 0; i < children.getLength(); i++) {
            final Node child = children.item(i);
            if (child instanceof Element && tagName.equals(child.getNodeName())) {
                final String text = child.getTextContent();
                return text == null ? null : text.trim();
            }
        }
        return null;
    }

    public static final class CurrencyDefinition {
        private final String code;
        private final String name;
        private final String numericCode;
        private final String minorUnits;

        CurrencyDefinition(String code, String name, String numericCode, String minorUnits) {
            this.code = code;
            this.name = name;
            this.numericCode = numericCode;
            this.minorUnits = minorUnits;
        }

        public String getCode() {
            return this.code;
        }

        public String getName() {
            return this.name;
        }

        public String getNumericCode() {
            return this.numericCode;
        }

        public String getMinorUnits() {
            return this.minorUnits;
        }
    }
}
