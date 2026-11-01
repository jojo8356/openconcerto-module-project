/*
 * Regles de la colonne « Affaire » dans les tableaux de lignes.
 *
 * Classe volontairement <b>sans dependance OpenConcerto ni Swing</b> : toutes
 * les decisions sont testees ({@code ItemAffairColumnRulesTest}) et
 * {@code ItemTableAffairColumn} ne fait que les appliquer a l'interface.
 *
 * Contexte du besoin : dans le detail d'une commande fournisseur, le tableau
 * des lignes (COMMANDE_ELEMENT) n'a <b>aucune</b> colonne « Affaire ». Le champ
 * Affaire de l'en-tete est, lui, bien renseigne. Ces regles disent :
 * <ul>
 * <li>quels tableaux de lignes peuvent recevoir la colonne ;</li>
 * <li>d'ou vient la valeur : de la ligne elle-meme si elle porte
 * {@code ID_AFFAIRE}, sinon de son document parent (COMMANDE,
 * FACTURE_FOURNISSEUR, COMMANDE_CLIENT...) ;</li>
 * <li>comment formater le libelle (NUMERO de l'affaire, jamais tout en
 * majuscules).</li>
 * </ul>
 */
package org.openconcerto.modules.project;

import java.text.Normalizer;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class ItemAffairColumnRules {

    /** Titre de la colonne ajoutee. */
    public static final String HEADER = "Affaire";

    /** Champ de l'affaire, sur la ligne ou sur son document. */
    public static final String FIELD = "ID_AFFAIRE";

    /**
     * Identifiant de la ligne « indéfinie » des tables OpenConcerto : il ne
     * designe aucune affaire et doit s'afficher comme une case vide.
     */
    public static final int UNDEFINED_ID = 1;

    /**
     * Tableaux de lignes pouvant recevoir la colonne : ce sont les lignes des
     * documents rattaches a une affaire, en achat comme en vente.
     */
    public static final List<String> LINE_TABLES;

    /**
     * Lien vers le document parent, pour les tables de lignes qui ne portent
     * pas elles-memes {@code ID_AFFAIRE} : c'est le cas courant en OpenConcerto
     * 1.7.6, ou seuls les en-tetes de documents ont le champ.
     */
    private static final Map<String, String[]> PARENTS;

    static {
        final Map<String, String[]> parents = new LinkedHashMap<String, String[]>();
        // achats
        parents.put("COMMANDE_ELEMENT", new String[] { "ID_COMMANDE", "COMMANDE" });
        parents.put("FACTURE_FOURNISSEUR_ELEMENT", new String[] { "ID_FACTURE_FOURNISSEUR", "FACTURE_FOURNISSEUR" });
        parents.put("BON_RECEPTION_ELEMENT", new String[] { "ID_BON_RECEPTION", "BON_RECEPTION" });
        parents.put("DEMANDE_PRIX_ELEMENT", new String[] { "ID_DEMANDE_PRIX", "DEMANDE_PRIX" });
        parents.put("DEMANDE_ACHAT_ELEMENT", new String[] { "ID_DEMANDE_ACHAT", "DEMANDE_ACHAT" });
        parents.put("SAISIE_ACHAT_ELEMENT", new String[] { "ID_SAISIE_ACHAT", "SAISIE_ACHAT" });
        parents.put("AVOIR_FOURNISSEUR_ELEMENT", new String[] { "ID_AVOIR_FOURNISSEUR", "AVOIR_FOURNISSEUR" });
        // ventes
        parents.put("COMMANDE_CLIENT_ELEMENT", new String[] { "ID_COMMANDE_CLIENT", "COMMANDE_CLIENT" });
        parents.put("SAISIE_VENTE_FACTURE_ELEMENT", new String[] { "ID_SAISIE_VENTE_FACTURE", "SAISIE_VENTE_FACTURE" });
        parents.put("DEVIS_ELEMENT", new String[] { "ID_DEVIS", "DEVIS" });
        parents.put("AVOIR_CLIENT_ELEMENT", new String[] { "ID_AVOIR_CLIENT", "AVOIR_CLIENT" });
        parents.put("BON_DE_LIVRAISON_ELEMENT", new String[] { "ID_BON_DE_LIVRAISON", "BON_DE_LIVRAISON" });
        PARENTS = Collections.unmodifiableMap(parents);
        LINE_TABLES = Collections.unmodifiableList(Arrays.asList(parents.keySet().toArray(new String[0])));
    }

    private ItemAffairColumnRules() {
    }

    /** Vrai si ce tableau de lignes fait partie de ceux qu'on equipe. */
    public static boolean isLineTable(final String tableName) {
        return tableName != null && PARENTS.containsKey(tableName.trim().toUpperCase(Locale.ROOT));
    }

    /** Table du document parent, ou <code>null</code> si elle est inconnue. */
    public static String parentTable(final String lineTableName) {
        if (lineTableName == null) {
            return null;
        }
        final String[] parent = PARENTS.get(lineTableName.trim().toUpperCase(Locale.ROOT));
        return parent == null ? null : parent[1];
    }

    /** Champ de la ligne qui pointe vers le document parent, ou <code>null</code>. */
    public static String parentField(final String lineTableName) {
        if (lineTableName == null) {
            return null;
        }
        final String[] parent = PARENTS.get(lineTableName.trim().toUpperCase(Locale.ROOT));
        return parent == null ? null : parent[0];
    }

    /** Vrai si cet identifiant designe une vraie affaire. */
    public static boolean isRealAffair(final Integer id) {
        return id != null && id.intValue() > UNDEFINED_ID;
    }

    /**
     * Faut-il ajouter la colonne a ce tableau de lignes ?
     *
     * @param tableName        table des lignes (ex. {@code COMMANDE_ELEMENT}).
     * @param hasOwnField      vrai si la ligne porte elle-meme {@code ID_AFFAIRE}.
     * @param hasParentField   vrai si le document parent porte {@code ID_AFFAIRE}.
     * @param alreadyHasColumn vrai si le tableau affiche deja une colonne
     *                         « Affaire ».
     * @param enabled          faux pour desactiver la fonctionnalite.
     * @return vrai si la colonne doit etre ajoutee.
     */
    public static boolean shouldAdd(final String tableName, final boolean hasOwnField, final boolean hasParentField, final boolean alreadyHasColumn, final boolean enabled) {
        if (!enabled || alreadyHasColumn) {
            return false;
        }
        if (!isLineTable(tableName)) {
            return false;
        }
        // Sans champ exploitable, la colonne serait vide : mieux vaut ne rien
        // afficher qu'une colonne qui ne dit jamais rien.
        return hasOwnField || hasParentField;
    }

    /**
     * Affaire a afficher pour une ligne.
     *
     * <p>
     * La valeur de la ligne passe avant celle du document, mais uniquement si
     * elle est renseignee : une ligne peut avoir garde le lien vers une affaire
     * alors que son document en a change, et inversement.
     * </p>
     *
     * @return l'identifiant a afficher, ou {@code 0} s'il n'y a rien a montrer.
     */
    public static int resolve(final Integer ownAffairID, final Integer parentAffairID) {
        if (isRealAffair(ownAffairID)) {
            return ownAffairID.intValue();
        }
        if (isRealAffair(parentAffairID)) {
            return parentAffairID.intValue();
        }
        return 0;
    }

    /**
     * Libelle d'une affaire dans la colonne.
     *
     * <p>
     * Regles de l'equipe : le numero de l'affaire tel qu'il est saisi (ex.
     * {@code 11870}), jamais recase ; le nom seulement s'il n'y a pas de
     * numero ; et a defaut {@code Affaire 145} — en minuscules, jamais tout en
     * majuscules.
     * </p>
     *
     * @param id     identifiant de l'affaire (peut etre <code>null</code>).
     * @param numero numero saisi par l'utilisateur (peut etre vide).
     * @param nom    nom de l'affaire (souvent vide en pratique).
     * @return le texte a afficher, vide si l'affaire n'est pas renseignee.
     */
    public static String formatLabel(final Integer id, final String numero, final String nom) {
        final String num = trimToEmpty(numero);
        if (num.length() > 0) {
            return num;
        }
        final String name = trimToEmpty(nom);
        if (name.length() > 0) {
            return name;
        }
        if (isRealAffair(id)) {
            return HEADER + " " + id.intValue();
        }
        return "";
    }

    /** Vrai si un des titres de colonnes correspond deja a « Affaire ». */
    public static boolean hasAffairColumn(final List<String> columnTitles) {
        if (columnTitles == null) {
            return false;
        }
        for (final String title : columnTitles) {
            if (title != null && normalize(title).endsWith(normalize(HEADER))) {
                return true;
            }
        }
        return false;
    }

    /** Vrai si la fonctionnalite est active (propriete systeme, active par defaut). */
    public static boolean isEnabled(final String propertyValue) {
        if (propertyValue == null || propertyValue.trim().length() == 0) {
            return true;
        }
        final String v = propertyValue.trim().toLowerCase(Locale.ROOT);
        return !("false".equals(v) || "0".equals(v) || "off".equals(v) || "non".equals(v));
    }

    /** Pourquoi la colonne est (ou n'est pas) ajoutee : message pour le journal. */
    public static String explain(final String tableName, final boolean hasOwnField, final boolean hasParentField, final boolean alreadyHasColumn, final boolean enabled) {
        if (!enabled) {
            return "colonne « " + HEADER + " » des lignes desactivee (-Dproject.itemAffair=false)";
        }
        if (!isLineTable(tableName)) {
            return "tableau de lignes ignoré : « " + tableName + " » n'est pas un document rattaché à une affaire";
        }
        if (alreadyHasColumn) {
            return "colonne « " + HEADER + " » déjà présente dans " + tableName;
        }
        if (hasOwnField) {
            return "colonne « " + HEADER + " » ajoutée dans " + tableName + " (affaire de la ligne)";
        }
        if (hasParentField) {
            return "colonne « " + HEADER + " » ajoutée dans " + tableName + " (affaire de " + parentTable(tableName) + ")";
        }
        return "colonne « " + HEADER + " » impossible : ni " + tableName + " ni " + parentTable(tableName) + " n'ont de champ " + FIELD;
    }

    /** Index ou inserer la colonne (apres « Désignation »), -1 si inconnu. */
    public static int insertionIndex(final List<String> columnTitles) {
        if (columnTitles == null) {
            return -1;
        }
        for (int i = 0; i < columnTitles.size(); i++) {
            final String title = columnTitles.get(i);
            if (title != null && normalize(title).startsWith("design")) {
                return i + 1;
            }
        }
        return -1;
    }

    /** Copie normalisee (sans accents, minuscules) d'un titre, pour comparer. */
    public static String normalize(final String text) {
        if (text == null) {
            return "";
        }
        return Normalizer.normalize(text, Normalizer.Form.NFD).replaceAll("\\p{M}", "").trim().toLowerCase(Locale.ROOT);
    }

    /** Titres des colonnes tel qu'affiches, pour la detection de doublon. */
    public static Map<String, Integer> titleIndex(final List<String> titles) {
        final Map<String, Integer> result = new HashMap<String, Integer>();
        if (titles != null) {
            for (int i = 0; i < titles.size(); i++) {
                result.put(normalize(titles.get(i)), Integer.valueOf(i));
            }
        }
        return result;
    }

    private static String trimToEmpty(final String s) {
        return s == null ? "" : s.trim();
    }
}
