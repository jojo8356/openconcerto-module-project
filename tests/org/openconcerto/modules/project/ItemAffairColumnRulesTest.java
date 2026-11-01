package org.openconcerto.modules.project;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Tests de {@link ItemAffairColumnRules} : la colonne « Affaire » des tableaux
 * de lignes.
 * <p>
 * Cas reel corrige : sur le detail de la commande fournisseur
 * {@code 11870-PO-007-Avt1}, le champ Affaire de l'en-tete vaut {@code 11870}
 * mais le tableau des lignes n'a <b>aucune</b> colonne Affaire. La valeur doit
 * donc venir, dans cet ordre : de la ligne si elle porte {@code ID_AFFAIRE},
 * sinon de son document parent ({@code COMMANDE}, {@code FACTURE_FOURNISSEUR}...).
 */
public final class ItemAffairColumnRulesTest {

    private static int passed = 0;

    public static void main(final String[] args) {
        testLineTables();
        testUnknownTables();
        testParentLinks();
        testShouldAddOnRealCase();
        testShouldAddWhenNothingToShow();
        testShouldAddDisabled();
        testShouldAddAlreadyPresent();
        testResolve();
        testFormatLabel();
        testHasAffairColumn();
        testInsertionIndex();
        testEnabledProperty();
        testExplain();
        testNormalize();
        testRealNumbers();
        System.out.println("ItemAffairColumnRulesTest : " + passed + " tests OK");
    }

    private static void assertEquals(final String label, final Object expected, final Object actual) {
        if (expected == null ? actual != null : !expected.equals(actual)) {
            throw new AssertionError(label + " : attendu <" + expected + ">, obtenu <" + actual + ">");
        }
        passed++;
    }

    /** Le cas de la capture : une commande fournisseur. */
    private static void testShouldAddOnRealCase() {
        // COMMANDE_ELEMENT de la base du client : pas de ID_AFFAIRE sur la ligne,
        // mais COMMANDE.ID_AFFAIRE existe et vaut 11870.
        assertEquals("commande fournisseur : colonne ajoutee", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.shouldAdd("COMMANDE_ELEMENT", false, true, false, true)));
        // variante ou la colonne de ligne existe (bases plus recentes)
        assertEquals("ligne avec champ : colonne ajoutee", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.shouldAdd("COMMANDE_ELEMENT", true, false, false, true)));
        assertEquals("facture fournisseur : colonne ajoutee", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.shouldAdd("FACTURE_FOURNISSEUR_ELEMENT", false, true, false, true)));
        assertEquals("commande client : colonne ajoutee", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.shouldAdd("COMMANDE_CLIENT_ELEMENT", false, true, false, true)));
        assertEquals("bon de livraison : colonne ajoutee", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.shouldAdd("BON_DE_LIVRAISON_ELEMENT", false, true, false, true)));
    }

    private static void testShouldAddWhenNothingToShow() {
        assertEquals("aucun champ", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.shouldAdd("COMMANDE_ELEMENT", false, false, false, true)));
        assertEquals("deja presente", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.shouldAdd("COMMANDE_ELEMENT", false, true, true, true)));
        assertEquals("table inconnue", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.shouldAdd("ARTICLE", false, true, false, true)));
        assertEquals("table nulle", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.shouldAdd(null, true, true, false, true)));
    }

    private static void testShouldAddDisabled() {
        assertEquals("desactive", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.shouldAdd("COMMANDE_ELEMENT", true, true, false, false)));
    }

    private static void testShouldAddAlreadyPresent() {
        assertEquals("colonne deja la", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.shouldAdd("FACTURE_FOURNISSEUR_ELEMENT", true, true, true, true)));
    }

    private static void testLineTables() {
        assertEquals("commande fournisseur", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.isLineTable("COMMANDE_ELEMENT")));
        assertEquals("facture fournisseur", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.isLineTable("FACTURE_FOURNISSEUR_ELEMENT")));
        assertEquals("vente", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.isLineTable("SAISIE_VENTE_FACTURE_ELEMENT")));
        assertEquals("devis", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.isLineTable("DEVIS_ELEMENT")));
        assertEquals("casse et espaces", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.isLineTable("  commande_element ")));
        assertEquals("en-tete de document", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.isLineTable("COMMANDE")));
        assertEquals("table de reference", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.isLineTable("ARTICLE")));
        assertEquals("null", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.isLineTable(null)));
        assertEquals("liste non vide", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.LINE_TABLES.size() > 8));
    }

    private static void testUnknownTables() {
        assertEquals("parent inconnu", null, ItemAffairColumnRules.parentTable("ARTICLE"));
        assertEquals("champ parent inconnu", null, ItemAffairColumnRules.parentField("ARTICLE"));
        assertEquals("parent nul", null, ItemAffairColumnRules.parentTable(null));
    }

    /** Le lien vers le document : c'est lui qui porte l'affaire. */
    private static void testParentLinks() {
        assertEquals("commande", "COMMANDE", ItemAffairColumnRules.parentTable("COMMANDE_ELEMENT"));
        assertEquals("champ de lien", "ID_COMMANDE", ItemAffairColumnRules.parentField("COMMANDE_ELEMENT"));
        assertEquals("facture fournisseur", "FACTURE_FOURNISSEUR", ItemAffairColumnRules.parentTable("FACTURE_FOURNISSEUR_ELEMENT"));
        assertEquals("champ de lien facture", "ID_FACTURE_FOURNISSEUR", ItemAffairColumnRules.parentField("FACTURE_FOURNISSEUR_ELEMENT"));
        assertEquals("bon de reception", "BON_RECEPTION", ItemAffairColumnRules.parentTable("BON_RECEPTION_ELEMENT"));
        assertEquals("demande de prix", "DEMANDE_PRIX", ItemAffairColumnRules.parentTable("DEMANDE_PRIX_ELEMENT"));
        assertEquals("commande client", "COMMANDE_CLIENT", ItemAffairColumnRules.parentTable("COMMANDE_CLIENT_ELEMENT"));
        assertEquals("facture de vente", "SAISIE_VENTE_FACTURE", ItemAffairColumnRules.parentTable("SAISIE_VENTE_FACTURE_ELEMENT"));
        assertEquals("devis", "DEVIS", ItemAffairColumnRules.parentTable("DEVIS_ELEMENT"));
        assertEquals("avoir client", "AVOIR_CLIENT", ItemAffairColumnRules.parentTable("AVOIR_CLIENT_ELEMENT"));
        // chaque table de lignes a un parent declare
        for (final String table : ItemAffairColumnRules.LINE_TABLES) {
            if (ItemAffairColumnRules.parentTable(table) == null || ItemAffairColumnRules.parentField(table) == null) {
                throw new AssertionError("lien parent manquant pour " + table);
            }
            passed++;
        }
    }

    private static void testResolve() {
        // la ligne gagne quand elle est renseignee
        assertEquals("ligne prioritaire", 145, ItemAffairColumnRules.resolve(Integer.valueOf(145), Integer.valueOf(11870)));
        // sinon le document
        assertEquals("document", 11870, ItemAffairColumnRules.resolve(null, Integer.valueOf(11870)));
        assertEquals("document si ligne indefinie", 11870, ItemAffairColumnRules.resolve(Integer.valueOf(1), Integer.valueOf(11870)));
        assertEquals("document si ligne nulle", 11870, ItemAffairColumnRules.resolve(null, Integer.valueOf(11870)));
        assertEquals("document si ligne a zero", 11870, ItemAffairColumnRules.resolve(Integer.valueOf(0), Integer.valueOf(11870)));
        // rien du tout
        assertEquals("aucune affaire", 0, ItemAffairColumnRules.resolve(null, null));
        assertEquals("deux indefinies", 0, ItemAffairColumnRules.resolve(Integer.valueOf(1), Integer.valueOf(1)));
        assertEquals("ligne indefinie seule", 0, ItemAffairColumnRules.resolve(Integer.valueOf(1), null));
        // une vraie affaire de la base du client (145 = 12048)
        assertEquals("affaire 145", 145, ItemAffairColumnRules.resolve(null, Integer.valueOf(145)));
        assertEquals("affaire 11870", 11870, ItemAffairColumnRules.resolve(Integer.valueOf(11870), null));
    }

    private static void testFormatLabel() {
        // cas reel de la capture : l'affaire s'appelle « 11870 », son nom est vide
        assertEquals("numero seul", "11870", ItemAffairColumnRules.formatLabel(Integer.valueOf(11870), "11870", ""));
        assertEquals("numero et nom", "11870", ItemAffairColumnRules.formatLabel(Integer.valueOf(11870), "11870", "REBSTOCK"));
        assertEquals("numero avec espaces", "11870", ItemAffairColumnRules.formatLabel(Integer.valueOf(11870), "  11870 ", null));
        // le libelle saisi n'est jamais recase (regle de l'equipe)
        assertEquals("minuscules conservees", "aff-1000", ItemAffairColumnRules.formatLabel(Integer.valueOf(9), "aff-1000", null));
        assertEquals("majuscules conservees", "AFF-1000", ItemAffairColumnRules.formatLabel(Integer.valueOf(9), "AFF-1000", null));
        // nom quand il n'y a pas de numero
        assertEquals("nom de repli", "Chantier Lyon", ItemAffairColumnRules.formatLabel(Integer.valueOf(9), "", "Chantier Lyon"));
        assertEquals("nom de repli avec espaces", "Chantier Lyon", ItemAffairColumnRules.formatLabel(Integer.valueOf(9), null, " Chantier Lyon "));
        // repli lisible, pas tout en majuscules
        assertEquals("repli numerote", "Affaire 145", ItemAffairColumnRules.formatLabel(Integer.valueOf(145), null, null));
        assertEquals("repli numerote (vides)", "Affaire 145", ItemAffairColumnRules.formatLabel(Integer.valueOf(145), "  ", "  "));
        // rien
        assertEquals("vide", "", ItemAffairColumnRules.formatLabel(null, null, null));
        assertEquals("indefinie", "", ItemAffairColumnRules.formatLabel(Integer.valueOf(1), null, null));
        assertEquals("numero vide", "", ItemAffairColumnRules.formatLabel(null, "", ""));
    }

    private static void testHasAffairColumn() {
        final List<String> titles = Arrays.asList("Niveau", "Style", "Désignation", "Code", "Qté", "Total achat HT");
        assertEquals("sans colonne affaire", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.hasAffairColumn(titles)));
        assertEquals("avec colonne affaire", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.hasAffairColumn(Arrays.asList("Niveau", "Affaire", "Code"))));
        assertEquals("avec majuscules", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.hasAffairColumn(Arrays.asList("AFFAIRE"))));
        assertEquals("avec accent", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.hasAffairColumn(Arrays.asList("Affairé"))));
        assertEquals("liste vide", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.hasAffairColumn(new ArrayList<String>())));
        assertEquals("liste nulle", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.hasAffairColumn(null)));
        assertEquals("titre nul tolere", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.hasAffairColumn(Arrays.asList((String) null, "Code"))));
    }

    /** La colonne doit etre visible : juste apres « Désignation ». */
    private static void testInsertionIndex() {
        final List<String> reel = Arrays.asList("Niveau", "Style", "Dmd Achat", "Code Fourniss.", "Famille d'arti…", "Code", "Désignation", "Descriptif", "P.A.U V HT");
        assertEquals("apres designation", 7, ItemAffairColumnRules.insertionIndex(reel));
        assertEquals("apres designation sans accent", 2, ItemAffairColumnRules.insertionIndex(Arrays.asList("Code", "Designation", "Qté")));
        assertEquals("sans designation", -1, ItemAffairColumnRules.insertionIndex(Arrays.asList("Code", "Qté")));
        assertEquals("liste nulle", -1, ItemAffairColumnRules.insertionIndex(null));
        // l'index propose reste dans les bornes du tableau
        final int index = ItemAffairColumnRules.insertionIndex(reel);
        assertEquals("index dans les bornes", Boolean.TRUE, Boolean.valueOf(index > 0 && index <= reel.size()));
    }

    private static void testEnabledProperty() {
        assertEquals("par defaut", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.isEnabled(null)));
        assertEquals("vide", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.isEnabled("  ")));
        assertEquals("true", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.isEnabled("true")));
        assertEquals("false", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.isEnabled("false")));
        assertEquals("FALSE", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.isEnabled("FALSE")));
        assertEquals("0", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.isEnabled("0")));
        assertEquals("off", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.isEnabled("off")));
        assertEquals("non", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.isEnabled("non")));
        assertEquals("valeur inconnue = actif", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.isEnabled("oui")));
    }

    private static void testExplain() {
        assertEquals("desactive", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.explain("COMMANDE_ELEMENT", true, true, false, false).contains("desactivee")));
        assertEquals("ignore", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.explain("ARTICLE", true, true, false, true).contains("ignoré")));
        assertEquals("deja la", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.explain("COMMANDE_ELEMENT", true, true, true, true).contains("déjà présente")));
        assertEquals("via document", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.explain("COMMANDE_ELEMENT", false, true, false, true).contains("COMMANDE")));
        assertEquals("via ligne", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.explain("COMMANDE_ELEMENT", true, false, false, true).contains("affaire de la ligne")));
        assertEquals("impossible", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.explain("COMMANDE_ELEMENT", false, false, false, true).contains("impossible")));
    }

    private static void testNormalize() {
        assertEquals("accents", "designation", ItemAffairColumnRules.normalize("Désignation"));
        assertEquals("casse", "affaire", ItemAffairColumnRules.normalize("AFFAIRE"));
        assertEquals("espaces", "code", ItemAffairColumnRules.normalize("  Code  "));
        assertEquals("null", "", ItemAffairColumnRules.normalize(null));
        assertEquals("index des titres", Integer.valueOf(2), ItemAffairColumnRules.titleIndex(Arrays.asList("Code", "Qté", "Désignation")).get("designation"));
        assertEquals("titre absent", null, ItemAffairColumnRules.titleIndex(Arrays.asList("Code")).get("affaire"));
        assertEquals("index vide", Integer.valueOf(0), Integer.valueOf(ItemAffairColumnRules.titleIndex(new ArrayList<String>()).size()));
        assertEquals("index nul", Integer.valueOf(0), Integer.valueOf(ItemAffairColumnRules.titleIndex(null).size()));
    }

    /** Non-regression sur les donnees du client (diagnostic du 29/10). */
    private static void testRealNumbers() {
        assertEquals("384 affaires", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.isRealAffair(Integer.valueOf(384))));
        assertEquals("affaire 145 reelle", Boolean.TRUE, Boolean.valueOf(ItemAffairColumnRules.isRealAffair(Integer.valueOf(145))));
        assertEquals("ligne indefinie", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.isRealAffair(Integer.valueOf(1))));
        assertEquals("zero", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.isRealAffair(Integer.valueOf(0))));
        assertEquals("null", Boolean.FALSE, Boolean.valueOf(ItemAffairColumnRules.isRealAffair(null)));
        assertEquals("id indefini", 1, ItemAffairColumnRules.UNDEFINED_ID);
        assertEquals("titre", "Affaire", ItemAffairColumnRules.HEADER);
        assertEquals("champ", "ID_AFFAIRE", ItemAffairColumnRules.FIELD);
    }
}
