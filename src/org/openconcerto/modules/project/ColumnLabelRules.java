package org.openconcerto.modules.project;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Regles pures des <b>libelles de colonnes</b> : comment transformer le nom
 * technique d'une colonne ({@code ID_AFFAIRE}, {@code ID_CLIENT}...) en un
 * libelle lisible, comment le personnaliser par table, et qui a le droit de le
 * faire.
 * <p>
 * Le besoin metier : dans les listes de l'ERP, certaines colonnes s'affichent
 * avec leur nom technique ({@code ID_CLIENT}, {@code ID_FACTURE_FOURNISSEUR}).
 * Un utilisateur metier ne veut pas voir le prefixe {@code ID_} : il veut
 * « CLIENT », « FACTURE FOURNISSEUR ». Le libelle doit etre choisi une fois par
 * la personne qui a le plus de droits, et s'appliquer a <b>toute l'equipe</b>.
 *
 * <h2>Resolution d'un libelle</h2>
 * L'ordre est fixe, du plus precis au plus general :
 * <ol>
 * <li><b>TABLE.COLONNE</b> : regle explicite pour cette table ;</li>
 * <li><b>*.COLONNE</b> : regle pour cette colonne dans toutes les tables
 * (une seule saisie pour {@code ID_CLIENT} partout) ;</li>
 * <li><b>regle automatique</b> ({@link #suggestLabel(String)}) : suppression du
 * prefixe {@code ID_} quand le mode est {@link #MODE_AUTO} ;</li>
 * <li>sinon le libelle d'origine, inchange.</li>
 * </ol>
 *
 * <h2>Qui peut modifier</h2>
 * Le « role le plus haut de la base » est, dans l'ordre : les super-utilisateurs
 * s'il y en a, sinon les administrateurs, sinon le ou les utilisateurs qui
 * cumulent le plus de droits accordes dans {@code USER_RIGHT}. Les regles de
 * selection sont ici, les requetes SQL sont dans {@link #roleRightsQuery(String)}.
 *
 * <p>
 * Classe volontairement <b>sans dependance OpenConcerto</b> : elle est testee
 * par {@code ColumnLabelRulesTest} et utilisee par {@link ColumnLabelStore} et
 * {@link ColumnLabelSettingsAction}.
 */
public final class ColumnLabelRules {

    /** Aucune transformation : les libelles s'affichent tels quels. */
    public static final String MODE_OFF = "OFF";
    /** Seules les regles explicites sont appliquees. */
    public static final String MODE_MAPPING = "MAPPING";
    /** Regles explicites, puis suppression automatique du prefixe {@code ID_}. */
    public static final String MODE_AUTO = "AUTO";

    /** Mode par defaut : c'est ce que demande l'utilisateur metier. */
    public static final String DEFAULT_MODE = MODE_AUTO;

    /** Mode choisi par defaut, utilise dans les listes des autres modules. */
    public static final List<String> MODES = Collections.unmodifiableList(Arrays.asList(MODE_AUTO, MODE_MAPPING, MODE_OFF));

    /** Table des reglages du module (cle / valeur), par schema societe. */
    public static final String SETTINGS_TABLE = "PROJECT_SETTINGS";

    /** Table des libelles personnalises, par schema societe. */
    public static final String LABEL_TABLE = "PROJECT_COLUMN_LABEL";

    /** Cle du reglage contenant le mode. */
    public static final String MODE_KEY = "column.label.mode";

    /** Valeur de {@code TABLE_NAME} pour une regle valable dans toutes les tables. */
    public static final String ANY_TABLE = "*";

    /** Longueur maximale d'un libelle (la colonne SQL est en 128). */
    public static final int MAX_LABEL_LENGTH = 128;

    /** Longueur maximale d'un nom de table ou de colonne. */
    public static final int MAX_NAME_LENGTH = 64;

    private ColumnLabelRules() {
    }

    // ------------------------------------------------------------------
    // Noms et libelles
    // ------------------------------------------------------------------

    /** Normalise un nom de table ou de colonne : majuscules, sans espaces autour. */
    public static String normalizeName(final String name) {
        if (name == null) {
            return "";
        }
        return name.trim().toUpperCase();
    }

    /** Cle d'une regle explicite : {@code TABLE.COLONNE}. */
    public static String key(final String table, final String column) {
        return normalizeName(table) + "." + normalizeName(column);
    }

    /** Vrai si la colonne est une cle etrangere technique ({@code ID_...}). */
    public static boolean isIdColumn(final String column) {
        final String name = normalizeName(column);
        return name.startsWith("ID_") && name.length() > 3;
    }

    /**
     * Libelle propose automatiquement pour une colonne : suppression du prefixe
     * {@code ID_} et remplacement des soulignes par des espaces.
     * <p>
     * {@code ID_AFFAIRE} devient {@code AFFAIRE}, {@code ID_CLIENT} devient
     * {@code CLIENT}, {@code ID_FACTURE_FOURNISSEUR} devient
     * {@code FACTURE FOURNISSEUR}. Une colonne qui n'est pas une cle etrangere
     * ({@code DATE}, {@code TOTAL_HT}, {@code ID}) est renvoyee telle quelle :
     * on ne « devine » jamais un libelle metier.
     */
    public static String suggestLabel(final String column) {
        final String name = normalizeName(column);
        if (!isIdColumn(name)) {
            return name;
        }
        return name.substring(3).replace('_', ' ');
    }

    /**
     * Vrai si le libelle peut etre enregistre : non vide apres nettoyage, sans
     * caractere de controle, et assez court pour la colonne SQL.
     */
    public static boolean isValidLabel(final String label) {
        if (label == null) {
            return false;
        }
        final String trimmed = label.trim();
        if (trimmed.length() == 0 || trimmed.length() > MAX_LABEL_LENGTH) {
            return false;
        }
        for (int i = 0; i < trimmed.length(); i++) {
            final char c = trimmed.charAt(i);
            if (c < ' ' || c == 0x7F) {
                return false;
            }
        }
        return true;
    }

    /** Nettoie un libelle saisi : espaces autour supprimes, espaces multiples reduits. */
    public static String cleanLabel(final String label) {
        if (label == null) {
            return "";
        }
        return label.trim().replaceAll("\\s+", " ");
    }

    /** Vrai si le nom de table ou de colonne tient dans la colonne SQL. */
    public static boolean isValidName(final String name) {
        final String trimmed = name == null ? "" : name.trim();
        return trimmed.length() > 0 && trimmed.length() <= MAX_NAME_LENGTH && trimmed.indexOf('.') < 0;
    }

    /** Normalise un mode : toute valeur inconnue retombe sur le mode par defaut. */
    public static String normalizeMode(final String mode) {
        final String value = normalizeName(mode);
        if (MODES.contains(value)) {
            return value;
        }
        return DEFAULT_MODE;
    }

    // ------------------------------------------------------------------
    // Resolution
    // ------------------------------------------------------------------

    /**
     * Libelle a afficher pour un en-tete de colonne.
     *
     * @param header  en-tete actuel (nom technique ou deja lisible) ;
     * @param table   table de la colonne, ou <code>null</code> si elle n'est pas
     *                connue (l'application a l'ecran ne connait pas toujours la
     *                table d'une colonne : les regles {@code TABLE.COLONNE} ne
     *                s'appliquent alors pas, mais {@code *.COLONNE} et la regle
     *                automatique s'appliquent) ;
     * @param labels  regles explicites, indexees par {@link #key(String, String)}
     *                ou par {@code *.COLONNE} ;
     * @param mode    {@link #MODE_AUTO}, {@link #MODE_MAPPING} ou {@link #MODE_OFF}.
     * @return le libelle a afficher ; jamais <code>null</code> si <code>header</code>
     *         ne l'est pas.
     */
    public static String resolve(final String header, final String table, final Map<String, String> labels, final String mode) {
        if (header == null) {
            return null;
        }
        final String normalizedMode = normalizeMode(mode);
        if (MODE_OFF.equals(normalizedMode) || labels == null) {
            return header;
        }
        final String column = normalizeName(header);
        if (table != null && !table.trim().isEmpty()) {
            final String exact = labels.get(key(table, column));
            if (isUsable(exact)) {
                return exact;
            }
        }
        final String wildcard = labels.get(key(ANY_TABLE, column));
        if (isUsable(wildcard)) {
            return wildcard;
        }
        // Une regle explicite dont la table est inconnue de l'ecran : on
        // l'accepte seulement si elle est unique pour cette colonne, pour ne
        // jamais afficher le libelle d'une autre table.
        if (table == null) {
            final String unique = uniqueLabelForColumn(column, labels);
            if (unique != null) {
                return unique;
            }
        }
        if (MODE_AUTO.equals(normalizedMode) && isIdColumn(column)) {
            return suggestLabel(column);
        }
        return header;
    }

    /** Choix du selecteur de filtre de l'ecran de parametrage. */
    public static final List<String> FILTER_CHOICES = Collections.unmodifiableList(Arrays.asList(
            "Toutes les colonnes", "Table", "Colonne", "Automatique", "Libellé affiché"));

    /**
     * Indice de colonne du tableau correspondant a un choix du filtre.
     * <p>
     * Indexe comme les colonnes de l'ecran : 0 = Table, 1 = Colonne,
     * 2 = Automatique, 3 = Libellé affiché.
     *
     * @param choice indice dans {@link #FILTER_CHOICES}.
     * @return l'indice de colonne, ou {@code -1} pour « toutes les colonnes ».
     */
    public static int filterColumnIndex(final int choice) {
        if (choice <= 0 || choice >= FILTER_CHOICES.size()) {
            return -1;
        }
        return choice - 1;
    }

    /** Debuts de nom qui designent une copie de table (sauvegarde, essai...). */
    private static final List<String> BACKUP_PREFIXES = Collections.unmodifiableList(Arrays.asList(
            "sauvegarde", "sauvegarde_", "backup", "copie", "archive", "ancien", "tmp_", "zz_"));

    /** Fins de nom qui designent une copie de table. */
    private static final List<String> BACKUP_SUFFIXES = Collections.unmodifiableList(Arrays.asList(
            "_avant", "_old", "_ancien", "_ancienne", "_backup", "_copie", "_bck", "_sauvegarde", "_archive"));

    /** Fragments internes qui designent une copie de table. */
    private static final List<String> BACKUP_INFIXES = Collections.unmodifiableList(Arrays.asList(
            "_sauvegarde_", "_backup_", "_copie_", "_avant_"));

    /**
     * Vrai si le nom de table ressemble a une <b>copie</b> de table (sauvegarde,
     * archivage, essai). Ces tables n'apparaissent dans aucune liste de l'ERP :
     * une regle de libelle posee dessus n'a donc aucun effet visible.
     * <p>
     * Cas reel : une regle avait ete saisie sur
     * {@code sauvegarde_FACTURE_FOURNISSEUR_avant_...} au lieu de
     * {@code FACTURE_FOURNISSEUR}. Le libelle etait bien enregistre, mais
     * l'utilisateur ne voyait aucun changement dans ses listes — d'ou le message
     * d'aide au moment d'enregistrer.
     * <p>
     * La detection est volontairement <b>stricte</b> (debut, fin ou fragment
     * explicite) : chercher « test » n'importe ou declencherait des faux
     * positifs sur des tables metier (une « ATTESTATION », par exemple).
     */
    public static boolean looksLikeBackupTable(final String table) {
        if (table == null) {
            return false;
        }
        final String name = normalizeName(table).toLowerCase(java.util.Locale.ROOT);
        if (name.length() == 0) {
            return false;
        }
        for (final String prefix : BACKUP_PREFIXES) {
            if (name.startsWith(prefix)) {
                return true;
            }
        }
        for (final String suffix : BACKUP_SUFFIXES) {
            if (name.endsWith(suffix)) {
                return true;
            }
        }
        for (final String infix : BACKUP_INFIXES) {
            if (name.contains(infix)) {
                return true;
            }
        }
        return false;
    }

    /** Tables de sauvegarde parmi une liste, dans l'ordre d'apparition, sans doublon. */
    public static List<String> backupTables(final java.util.Collection<String> tables) {
        final List<String> result = new ArrayList<String>();
        if (tables == null) {
            return result;
        }
        for (final String table : tables) {
            if (looksLikeBackupTable(table) && !result.contains(table)) {
                result.add(table);
            }
        }
        return result;
    }

    /**
     * Texte du message de fin d'enregistrement.
     * <p>
     * Il separe deux choses que l'ancien message melangeait, au point de faire
     * croire que rien n'avait ete enregistre :
     * <ol>
     * <li>les <b>regles</b> ecrites sur le serveur SQL (partagees) ;</li>
     * <li>les <b>colonnes deja affichees</b> sur ce poste qui ont ete
     * rafraichies (souvent 0 : les listes ne sont pas ouvertes, ou la colonne
     * n'y figure pas).</li>
     * </ol>
     * Et il signale les regles posees sur une table de sauvegarde, qui n'auront
     * aucun effet visible.
     *
     * @param rules        nombre de regles enregistrees.
     * @param refreshed    nombre de colonnes rafraichies sur ce poste.
     * @param mode         mode enregistre.
     * @param backupTables tables de sauvegarde concernees (vide si aucune).
     */
    public static String saveReport(final int rules, final int refreshed, final String mode, final List<String> backupTables) {
        final StringBuilder sb = new StringBuilder();
        sb.append("Libellés enregistrés sur le serveur SQL pour toute l'équipe.\n");
        sb.append("- ").append(rules).append(rules > 1 ? " règles" : " règle").append(" en base, mode ").append(normalizeMode(mode)).append(".\n");
        sb.append("- Listes déjà ouvertes sur ce poste : ").append(refreshed);
        sb.append(refreshed == 0 ? " colonne mise à jour (aucune liste ouverte n'affiche ces colonnes).\n" : " colonne(s) mise(s) à jour.\n");
        sb.append("\nLes autres postes verront les nouveaux libellés au prochain démarrage du client.");
        if (backupTables != null && !backupTables.isEmpty()) {
            sb.append("\n\n⚠ ").append(backupTables.size()).append(backupTables.size() > 1 ? " règles concernent" : " règle concerne");
            sb.append(" une table de sauvegarde :\n  ");
            for (int i = 0; i < backupTables.size() && i < 3; i++) {
                if (i > 0) {
                    sb.append("\n  ");
                }
                sb.append(backupTables.get(i));
            }
            sb.append("\nCes tables n'apparaissent dans aucune liste : ces libellés n'auront aucun effet visible.");
            sb.append("\nPour renommer une colonne dans toutes les tables, utilisez « Appliquer à toutes les tables (*) ».");
        }
        return sb.toString();
    }

    /**
     * Identifiant de colonne nettoye : sans le prefixe de classe
     * ({@code FieldPath}), sans guillemets et sans chemin technique inutile.
     * <p>
     * OpenConcerto renvoie par exemple
     * {@code FieldPath "COMMANDE_ELEMENT"."ID_COMMANDE"."ID_FOURNISSEUR"} pour
     * une colonne « Fournisseur » de l'onglet « Articles commandés ».
     */
    static List<String> identifierParts(final String identifier) {
        if (identifier == null) {
            return Collections.emptyList();
        }
        String cleaned = stripQuotes(identifier.trim());
        // Prefixe de classe : « FieldPath » (ou tout autre nom de classe) suivi
        // d'un espace.
        final int space = cleaned.indexOf(' ');
        if (space > 0 && space < 32 && cleaned.substring(0, space).indexOf('.') < 0) {
            cleaned = cleaned.substring(space + 1).trim();
        }
        final List<String> parts = new ArrayList<String>();
        for (final String part : cleaned.split("\\.")) {
            final String trimmed = part.trim();
            if (trimmed.length() > 0) {
                parts.add(trimmed);
            }
        }
        return parts;
    }

    /**
     * Nom de champ technique a partir de l'identifiant d'une colonne de liste :
     * le <b>dernier</b> segment.
     * <p>
     * Exemples : {@code FACTURE_FOURNISSEUR.ID_FOURNISSEUR} et
     * {@code FieldPath "COMMANDE_ELEMENT"."ID_COMMANDE"."ID_FOURNISSEUR"} donnent
     * tous deux {@code ID_FOURNISSEUR} : c'est ce champ qui porte la regle, meme
     * quand la liste l'atteint par une jointure.
     *
     * @return le nom du champ, ou <code>null</code> si l'identifiant est vide.
     */
    public static String technicalField(final String identifier) {
        final List<String> parts = identifierParts(identifier);
        if (parts.isEmpty()) {
            return null;
        }
        return parts.get(parts.size() - 1).toUpperCase(java.util.Locale.ROOT);
    }

    /**
     * Nom de table a partir de l'identifiant d'une colonne de liste : le
     * <b>premier</b> segment (la table de la liste), en sautant un eventuel
     * schema ({@code OpenConcerto42}).
     *
     * @return le nom de table, ou <code>null</code> si l'identifiant n'en porte
     *         pas.
     */
    public static String technicalTable(final String identifier) {
        final List<String> parts = identifierParts(identifier);
        if (parts.size() < 2) {
            return null;
        }
        final String first = parts.get(0);
        if (parts.size() >= 3 && first.toLowerCase(java.util.Locale.ROOT).startsWith("openconcerto")) {
            return parts.get(1).toUpperCase(java.util.Locale.ROOT);
        }
        return first.toUpperCase(java.util.Locale.ROOT);
    }

    private static String stripQuotes(final String value) {
        return value.replace("\"", "").replace("`", "");
    }

    /**
     * Resolution d'un en-tete <b>en connaissant le champ technique</b> de la
     * colonne.
     * <p>
     * C'est le cas des listes de l'ERP : l'en-tete affiche est deja un libelle
     * metier (« Fournisseur ») alors que la regle saisie porte sur le nom
     * technique ({@code ID_FOURNISSEUR}). Sans cette methode, la regle
     * {@code *.ID_FOURNISSEUR} ne s'appliquait jamais a ces colonnes.
     * <p>
     * Ordre de priorite :
     * <ol>
     * <li>{@code TABLE.CHAMP} ;</li>
     * <li>{@code *.CHAMP} ;</li>
     * <li>{@code TABLE.EN-TETE} (regle saisie sur le libelle affiche) ;</li>
     * <li>{@code *.EN-TETE} ;</li>
     * <li>mode AUTO : suppression du prefixe {@code ID_} du champ technique ;</li>
     * <li>en-tete d'origine.</li>
     * </ol>
     *
     * @param header  texte affiche par le coeur (peut etre un libelle metier).
     * @param table   table de la colonne, si connue.
     * @param field   champ technique, si connu ({@code ID_FOURNISSEUR}).
     * @param labels  regles saisies.
     * @param mode    mode courant.
     */
    public static String resolveForColumn(final String header, final String table, final String field, final Map<String, String> labels, final String mode) {
        if (header == null) {
            return null;
        }
        final String normalizedMode = normalizeMode(mode);
        if (MODE_OFF.equals(normalizedMode) || labels == null) {
            return header;
        }
        final String normalizedField = field == null ? null : normalizeName(field);
        if (normalizedField != null && normalizedField.length() > 0) {
            if (table != null && table.trim().length() > 0) {
                final String exact = labels.get(key(table, normalizedField));
                if (isUsable(exact)) {
                    return exact;
                }
            }
            final String wildcard = labels.get(key(ANY_TABLE, normalizedField));
            if (isUsable(wildcard)) {
                return wildcard;
            }
        }
        final String byHeader = resolve(header, table, labels, MODE_MAPPING);
        if (byHeader != null && !byHeader.equals(header)) {
            return byHeader;
        }
        if (MODE_AUTO.equals(normalizedMode)) {
            // Le mode AUTO ne remplace pas un libelle metier deja lisible
            // (« Fournisseur », « Designation ») : il ne s'applique qu'aux
            // en-tetes techniques. Sinon, toutes les listes du coeur perdraient
            // leurs libelles soignes au profit de majuscules techniques.
            if (isIdColumn(header)) {
                return suggestLabel(header);
            }
            if (normalizedField != null && normalizedField.length() > 0 && isIdColumn(normalizedField) && looksTechnical(header, normalizedField)) {
                return suggestLabel(normalizedField);
            }
        }
        return header;
    }

    /**
     * Vrai si l'en-tete affiche est en fait le nom technique (ou le contient) :
     * {@code ID_FOURNISSEUR}, {@code Id fournisseur}, {@code ID_FOURNISSEUR (…)},
     * etc. Sert a ne pas ecraser un libelle metier en mode AUTO.
     */
    public static boolean looksTechnical(final String header, final String field) {
        if (header == null || field == null) {
            return false;
        }
        // On compare sans espaces, sans apostrophes et sans soulignes : « ID CLIENT »,
        // « id_client » et « ID_CLIENT » doivent etre reconnus comme le meme en-tete.
        final String compactHeader = normalizeName(header).replace(" ", "").replace("'", "").replace("_", "");
        final String compactField = normalizeName(field).replace(" ", "").replace("_", "");
        return compactField.length() > 0 && (compactHeader.equals(compactField) || compactHeader.startsWith(compactField) || compactHeader.contains(compactField));
    }

    /**
     * Libelle <b>reellement affiche</b> pour une colonne, tel que l'ecran de
     * parametrage doit le montrer : la regle si elle existe, sinon le libelle
     * automatique du mode courant.
     * <p>
     * Pourquoi cette methode existe : l'ecran affichait la <i>regle</i>, donc une
     * case vide pour toutes les colonnes non personnalisees. L'utilisateur ne
     * pouvait pas voir ce qui s'affiche aujourd'hui, ni cliquer sur la bonne
     * valeur de depart. Ici on montre toujours ce que voit l'utilisateur final.
     *
     * @param table    table de la colonne ({@code *} accepte).
     * @param column   nom technique de la colonne (ex. {@code ID_FOURNISSEUR}).
     * @param rule     regle saisie, vide ou <code>null</code> si aucune.
     * @param mode     mode courant.
     */
    public static String displayLabel(final String table, final String column, final String rule, final String mode) {
        return resolvedLabel(column, rule, null, mode);
    }

    /**
     * Variante qui tient compte de la regle generale {@code *.COLONNE}.
     * <p>
     * Sans cela, une regle creee par « Appliquer a toutes les tables (*) » etait
     * bien enregistree mais <b>les lignes du tableau continuaient d'afficher le
     * libelle automatique</b> : l'utilisateur croyait que le bouton n'avait rien
     * fait. C'est exactement la meme resolution que celle appliquee aux listes :
     * regle de la table, puis regle {@code *}, puis automatique.
     *
     * @param column   nom technique de la colonne.
     * @param rule     regle propre a la table (vide si aucune).
     * @param wildcard regle {@code *.COLONNE} (vide ou <code>null</code> si aucune).
     * @param mode     mode courant.
     */
    public static String resolvedLabel(final String column, final String rule, final String wildcard, final String mode) {
        final String normalizedMode = normalizeMode(mode);
        final String cleaned = cleanLabel(rule);
        final String cleanedWildcard = cleanLabel(wildcard);
        if (MODE_OFF.equals(normalizedMode)) {
            return column;
        }
        if (cleaned.length() > 0) {
            return cleaned;
        }
        if (cleanedWildcard.length() > 0) {
            return cleanedWildcard;
        }
        if (MODE_AUTO.equals(normalizedMode)) {
            return suggestLabel(column);
        }
        return column;
    }

    /**
     * Valeur a enregistrer pour une case « Libellé affiché » apres edition :
     * texte nettoye, ou chaine vide si l'utilisateur a vide la case (retour au
     * libelle automatique).
     */
    public static String editLabel(final String value) {
        return cleanLabel(value);
    }

    /**
     * Regle a enregistrer apres une edition en direct de la case « Libellé
     * affiché ».
     * <p>
     * Trois cas, et c'est tout l'interet de la methode :
     * <ul>
     * <li>la case est videe : on <b>efface</b> la regle (retour a
     * l'automatique) ;</li>
     * <li>le texte est identique a ce qui etait affiche : rien ne change, on ne
     * cree pas de regle inutile (sinon un simple clic + Entree remplirait la
     * table de centaines de regles identiques au libelle automatique) ;</li>
     * <li>sinon : le texte devient la regle.</li>
     * </ul>
     *
     * @param currentRule regle actuelle (vide si aucune).
     * @param mode        mode courant, pour savoir ce qui etait affiche.
     * @param newValue    texte saisi dans la case.
     * @return la nouvelle regle (chaine vide = automatique).
     */
    public static String applyEdit(final String table, final String column, final String currentRule, final String mode, final String newValue) {
        final String cleaned = editLabel(newValue);
        final String before = displayLabel(table, column, currentRule, mode);
        if (cleaned.equals(before)) {
            return cleanLabel(currentRule);
        }
        return cleaned;
    }

    /** Vrai si la case porte une regle explicite (donc personnalisee). */
    public static boolean isExplicitRule(final String label) {
        return cleanLabel(label).length() > 0;
    }

    /**
     * Applique les regles a une liste d'en-tetes (une liste de l'ERP, un tableau
     * de parametrage...).
     *
     * @return une nouvelle liste, de meme taille et de meme ordre.
     */
    public static List<String> resolveAll(final List<String> headers, final String table, final Map<String, String> labels, final String mode) {
        final List<String> result = new ArrayList<String>(headers.size());
        for (final String header : headers) {
            result.add(resolve(header, table, labels, mode));
        }
        return result;
    }

    /** Vrai si au moins un en-tete serait modifie par les regles. */
    public static boolean changesAnything(final List<String> headers, final String table, final Map<String, String> labels, final String mode) {
        for (final String header : headers) {
            final String resolved = resolve(header, table, labels, mode);
            if (resolved != null && !resolved.equals(header)) {
                return true;
            }
        }
        return false;
    }

    private static boolean isUsable(final String label) {
        return label != null && label.trim().length() > 0;
    }

    /**
     * Libelle explicite d'une colonne quand il n'existe qu'une seule regle pour
     * cette colonne, toutes tables confondues.
     *
     * @return le libelle, ou <code>null</code> s'il n'y en a aucune ou plusieurs
     *         differentes.
     */
    static String uniqueLabelForColumn(final String column, final Map<String, String> labels) {
        final String wanted = normalizeName(column);
        final Set<String> found = new LinkedHashSet<String>();
        for (final Map.Entry<String, String> entry : labels.entrySet()) {
            final String ruleKey = entry.getKey();
            if (ruleKey == null) {
                continue;
            }
            final int dot = ruleKey.indexOf('.');
            if (dot < 0) {
                continue;
            }
            if (normalizeName(ruleKey.substring(dot + 1)).equals(wanted) && isUsable(entry.getValue())) {
                found.add(entry.getValue().trim());
            }
        }
        if (found.size() == 1) {
            return found.iterator().next();
        }
        return null;
    }

    /**
     * Construit le jeu de regles effectif : les valeurs par defaut livrees dans
     * le jar, ecrasees par celles enregistrees en base pour l'equipe.
     *
     * @param jarDefaults regles du fichier {@code column-labels.properties} du jar.
     * @param database    regles de la table {@code PROJECT_COLUMN_LABEL}.
     * @return une map fusionnee (base gagnante).
     */
    public static Map<String, String> merge(final Map<String, String> jarDefaults, final Map<String, String> database) {
        final Map<String, String> result = new LinkedHashMap<String, String>();
        if (jarDefaults != null) {
            result.putAll(jarDefaults);
        }
        if (database != null) {
            result.putAll(database);
        }
        return result;
    }

    /**
     * Valide un jeu de regles avant enregistrement.
     *
     * @return la liste des problemes, vide si tout est correct.
     */
    public static List<String> validate(final Map<String, String> labels) {
        final List<String> problems = new ArrayList<String>();
        if (labels == null) {
            return problems;
        }
        for (final Map.Entry<String, String> entry : labels.entrySet()) {
            final String ruleKey = entry.getKey();
            if (ruleKey == null || ruleKey.indexOf('.') <= 0) {
                problems.add("regle « " + ruleKey + " » : la cle doit etre de la forme TABLE.COLONNE");
                continue;
            }
            final String table = ruleKey.substring(0, ruleKey.indexOf('.'));
            final String column = ruleKey.substring(ruleKey.indexOf('.') + 1);
            if (!ANY_TABLE.equals(table) && !isValidName(table)) {
                problems.add("regle « " + ruleKey + " » : nom de table invalide");
            }
            if (!isValidName(column)) {
                problems.add("regle « " + ruleKey + " » : nom de colonne invalide");
            }
            if (!isValidLabel(entry.getValue())) {
                problems.add("regle « " + ruleKey + " » : libelle vide, trop long ou invalide");
            }
        }
        return problems;
    }

    // ------------------------------------------------------------------
    // Qui a le droit de parametrer
    // ------------------------------------------------------------------

    /**
     * Droits d'un utilisateur, tels que lus dans la base.
     * <p>
     * OpenConcerto n'a pas de table de « roles » : ce sont les drapeaux
     * {@code SUPERUSER} / {@code ADMIN} de {@code USER_COMMON} et le nombre de
     * droits accordes dans {@code USER_RIGHT} qui font la hierarchie.
     */
    public static final class UserRightsInfo {
        private final int userId;
        private final String userName;
        private final int grantedRights;
        private final boolean admin;
        private final boolean superUser;

        public UserRightsInfo(final int userId, final String userName, final int grantedRights, final boolean admin, final boolean superUser) {
            this.userId = userId;
            this.userName = userName == null ? "" : userName;
            this.grantedRights = grantedRights;
            this.admin = admin;
            this.superUser = superUser;
        }

        public int getUserId() {
            return this.userId;
        }

        public String getUserName() {
            return this.userName;
        }

        public int getGrantedRights() {
            return this.grantedRights;
        }

        public boolean isAdmin() {
            return this.admin;
        }

        public boolean isSuperUser() {
            return this.superUser;
        }

        /** Rang de privilege : plus grand = plus de droits. */
        public int getRank() {
            final int base = this.superUser ? 2 : (this.admin ? 1 : 0);
            return base * 1000000 + this.grantedRights;
        }

        @Override
        public String toString() {
            return this.userName + " (" + (this.superUser ? "superutilisateur" : this.admin ? "administrateur" : "utilisateur") + ", " + this.grantedRights + " droits)";
        }
    }

    /**
     * Utilisateurs qui ont le plus de droits dans la base : les super-utilisateurs
     * s'il y en a, sinon les administrateurs, sinon ceux qui cumulent le plus de
     * droits accordes.
     *
     * @return les utilisateurs de tete, jamais vide si l'entree ne l'est pas.
     */
    public static List<UserRightsInfo> topUsers(final List<UserRightsInfo> all) {
        final List<UserRightsInfo> result = new ArrayList<UserRightsInfo>();
        if (all == null || all.isEmpty()) {
            return result;
        }
        final List<UserRightsInfo> superUsers = new ArrayList<UserRightsInfo>();
        final List<UserRightsInfo> admins = new ArrayList<UserRightsInfo>();
        for (final UserRightsInfo info : all) {
            if (info == null) {
                continue;
            }
            if (info.isSuperUser()) {
                superUsers.add(info);
            } else if (info.isAdmin()) {
                admins.add(info);
            }
        }
        if (!superUsers.isEmpty()) {
            return superUsers;
        }
        if (!admins.isEmpty()) {
            return admins;
        }
        int max = Integer.MIN_VALUE;
        for (final UserRightsInfo info : all) {
            if (info != null) {
                max = Math.max(max, info.getGrantedRights());
            }
        }
        for (final UserRightsInfo info : all) {
            if (info != null && info.getGrantedRights() == max) {
                result.add(info);
            }
        }
        return result;
    }

    /** Vrai si cet utilisateur fait partie de ceux qui ont le plus de droits. */
    public static boolean canEdit(final int userId, final List<UserRightsInfo> all) {
        for (final UserRightsInfo info : topUsers(all)) {
            if (info.getUserId() == userId) {
                return true;
            }
        }
        return false;
    }

    /**
     * Explique pourquoi l'acces est accorde ou refuse, pour l'afficher dans le
     * journal du client.
     */
    public static String describeAccess(final int userId, final List<UserRightsInfo> all) {
        final List<UserRightsInfo> top = topUsers(all);
        if (top.isEmpty()) {
            return "aucun utilisateur lisible dans la base : parametrage reserve aux administrateurs";
        }
        for (final UserRightsInfo info : top) {
            if (info.getUserId() == userId) {
                return "acces accorde : " + info;
            }
        }
        final StringBuilder sb = new StringBuilder("acces refuse : le role le plus haut est ");
        for (int i = 0; i < top.size(); i++) {
            if (i > 0) {
                sb.append(", ");
            }
            sb.append(top.get(i).toString());
        }
        return sb.toString();
    }

    // ------------------------------------------------------------------
    // SQL (verifie par le test de bout en bout, cf. tests/sql/e2e-colonnes.sh)
    // ------------------------------------------------------------------

    /**
     * Vrai quand la decision d'acces n'a pas pu etre prise faute de savoir
     * <b>qui</b> est connecte (ou faute d'utilisateurs lisibles).
     * <p>
     * C'est le cas au demarrage du client : le menu du module est construit
     * avant que la session soit etablie. Traiter ce cas comme un refus faisait
     * disparaitre le menu pour <b>tout le monde</b>, y compris pour
     * l'administrateur ; il faut au contraire reessayer un peu plus tard. Seul
     * un refus explicite (« le role le plus haut est X ») doit masquer le menu.
     */
    public static boolean accessIsUndetermined(final String reason) {
        if (reason == null) {
            return true;
        }
        return reason.startsWith("utilisateur de la session inconnu") || reason.startsWith("aucun utilisateur lisible");
    }

    /**
     * Requete qui donne, pour chaque utilisateur actif, ses droits : drapeaux
     * {@code SUPERUSER} / {@code ADMIN} et nombre de droits accordes.
     * <p>
     * Elle n'utilise que des tables du cœur OpenConcerto ({@code USER_COMMON},
     * {@code USER_RIGHT}) et reste lisible meme si {@code USER_RIGHT} est absent
     * (la sous-requete renvoie alors 0 grace au {@code coalesce}).
     *
     * @param schema schema de la societe.
     */
    public static String roleRightsQuery(final String schema) {
        final String s = quoteIdentifier(schema);
        return "select u.\"ID\" as \"ID_USER\", coalesce(u.\"NOM\", u.\"LOGIN\", '') as \"NOM\","
                + " (case when u.\"SUPERUSER\" then 1 else 0 end) as \"SUPERUSER\","
                + " (case when u.\"ADMIN\" then 1 else 0 end) as \"ADMIN\","
                + " (select count(*) from " + s + ".\"USER_RIGHT\" r"
                + "    where r.\"ID_USER_COMMON\" = u.\"ID\" and (r.\"HAVE_RIGHT\" is null or r.\"HAVE_RIGHT\")) as \"DROITS\""
                + " from " + s + ".\"USER_COMMON\" u"
                + " where (u.\"IS_ACTIVE\" is null or u.\"IS_ACTIVE\")"
                + " order by 3 desc, 4 desc, 5 desc, 1";
    }

    /**
     * DDL de reference des deux tables du module. Idempotent : rejouable a chaque
     * demarrage.
     */
    public static List<String> createTableStatements(final String schema) {
        final String s = quoteIdentifier(schema);
        final List<String> statements = new ArrayList<String>();
        statements.add("create table if not exists " + s + ".\"" + SETTINGS_TABLE + "\" ("
                + "\"KEY\" varchar(128) not null primary key,"
                + " \"VALUE\" varchar(1024),"
                + " \"DATE\" timestamp,"
                + " \"ID_USER\" integer)");
        statements.add("create table if not exists " + s + ".\"" + LABEL_TABLE + "\" ("
                + "\"ID\" serial primary key,"
                + " \"TABLE_NAME\" varchar(64) not null,"
                + " \"COLUMN_NAME\" varchar(64) not null,"
                + " \"LABEL\" varchar(128) not null,"
                + " \"DATE\" timestamp,"
                + " \"ID_USER\" integer)");
        statements.add("create unique index if not exists " + quoteIdentifier(LABEL_TABLE + "_UNQ") + " on " + s + ".\"" + LABEL_TABLE + "\" (\"TABLE_NAME\", \"COLUMN_NAME\")");
        return statements;
    }

    /** Requete de lecture des libelles enregistres. */
    public static String loadLabelsQuery(final String schema) {
        final String s = quoteIdentifier(schema);
        return "select \"TABLE_NAME\", \"COLUMN_NAME\", \"LABEL\" from " + s + ".\"" + LABEL_TABLE + "\" order by \"TABLE_NAME\", \"COLUMN_NAME\"";
    }

    /** Requete de lecture des reglages (mode...). */
    public static String loadSettingsQuery(final String schema) {
        return "select \"KEY\", \"VALUE\" from " + quoteIdentifier(schema) + ".\"" + SETTINGS_TABLE + "\"";
    }

    /**
     * Instructions d'enregistrement d'un jeu de libelles, en <b>une seule
     * transaction</b> : l'equipe voit soit l'ancien etat, soit le nouveau, jamais
     * un melange.
     * <p>
     * Le remplacement complet est volontaire : les lignes supprimees dans
     * l'ecran de parametrage disparaissent aussi en base.
     *
     * @param labels regles a enregistrer (cle {@code TABLE.COLONNE}).
     * @param userId utilisateur qui enregistre (trace).
     * @param mode   mode a enregistrer.
     */
    public static String saveStatements(final String schema, final Map<String, String> labels, final String mode, final int userId) {
        final String s = quoteIdentifier(schema);
        final StringBuilder sb = new StringBuilder();
        sb.append("begin;");
        sb.append("delete from ").append(s).append(".\"").append(LABEL_TABLE).append("\";");
        if (labels != null) {
            for (final Map.Entry<String, String> entry : labels.entrySet()) {
                final String ruleKey = entry.getKey();
                if (ruleKey == null || ruleKey.indexOf('.') <= 0) {
                    continue;
                }
                final String table = ruleKey.substring(0, ruleKey.indexOf('.'));
                final String column = ruleKey.substring(ruleKey.indexOf('.') + 1);
                if (!isValidName(table) && !ANY_TABLE.equals(table)) {
                    continue;
                }
                if (!isValidName(column) || !isValidLabel(entry.getValue())) {
                    continue;
                }
                sb.append("insert into ").append(s).append(".\"").append(LABEL_TABLE).append("\""
                        + " (\"TABLE_NAME\", \"COLUMN_NAME\", \"LABEL\", \"DATE\", \"ID_USER\") values (");
                sb.append(quoteString(table.toUpperCase())).append(", ");
                sb.append(quoteString(column.toUpperCase())).append(", ");
                sb.append(quoteString(cleanLabel(entry.getValue()))).append(", now(), ");
                sb.append(userId).append(");");
            }
        }
        sb.append("delete from ").append(s).append(".\"").append(SETTINGS_TABLE).append("\" where \"KEY\" = ").append(quoteString(MODE_KEY)).append(";");
        sb.append("insert into ").append(s).append(".\"").append(SETTINGS_TABLE).append("\" (\"KEY\", \"VALUE\", \"DATE\", \"ID_USER\") values (")
                .append(quoteString(MODE_KEY)).append(", ").append(quoteString(normalizeMode(mode))).append(", now(), ").append(userId).append(");");
        sb.append("commit;");
        return sb.toString();
    }

    /** Echappe une valeur pour l'inserer dans une chaine SQL litterale. */
    public static String quoteString(final String value) {
        if (value == null) {
            return "null";
        }
        return "'" + value.replace("'", "''") + "'";
    }

    /** Entoure un identifiant de guillemets doubles, en doublant ceux qu'il contient. */
    public static String quoteIdentifier(final String identifier) {
        final String name = identifier == null ? "" : identifier;
        return "\"" + name.replace("\"", "\"\"") + "\"";
    }

    /**
     * Contenu du fichier {@code column-labels.properties} livrable dans le jar,
     * a partir des regles en vigueur.
     * <p>
     * C'est le second emplacement demande : les libelles sont enregistres en base
     * pour l'equipe (source de verite au quotidien) et peuvent etre figes dans le
     * jar, qui sert alors de valeurs par defaut a l'installation.
     */
    public static String toProperties(final Map<String, String> labels, final String mode) {
        final StringBuilder sb = new StringBuilder();
        sb.append("# Libelles de colonnes du module project\n");
        sb.append("# Genere par « Parametres > Libelles des colonnes > Exporter pour le jar ».\n");
        sb.append("# Les valeurs en base (table ").append(LABEL_TABLE).append(") restent prioritaires.\n");
        sb.append("mode=").append(normalizeMode(mode)).append("\n");
        if (labels != null) {
            for (final Map.Entry<String, String> entry : labels.entrySet()) {
                if (entry.getKey() == null || entry.getValue() == null) {
                    continue;
                }
                final String value = cleanLabel(entry.getValue()).replace("\\", "\\\\").replace("=", "\\=");
                sb.append(entry.getKey().toUpperCase().replace("=", "\\=")).append('=').append(value).append('\n');
            }
        }
        return sb.toString();
    }
}
