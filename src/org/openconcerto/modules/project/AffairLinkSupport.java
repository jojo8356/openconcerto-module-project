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
 * Regles pures (sans dependance OpenConcerto) qui decident <b>comment un
 * document est rattache a une affaire</b>.
 * <p>
 * Cette classe existe parce que le rattachement a une affaire se joue a trois
 * endroits differents, qui doivent rester d'accord :
 * <ol>
 * <li><b>l'ecriture</b> : les ecrans de saisie doivent exposer le champ
 * {@code ID_AFFAIRE} (sinon l'utilisateur ne peut rien saisir) ;</li>
 * <li><b>le stockage</b> : la colonne doit exister sur la table du document
 * (sinon la valeur n'a nulle part ou aller) ;</li>
 * <li><b>la lecture</b> : l'historique des affaires filtre chaque onglet sur
 * {@code ID_AFFAIRE}, directement ou via le document parent
 * ({@code fieldLink} de {@code ListeHistoriquePanel}).</li>
 * </ol>
 * Un desaccord entre ces trois couches produit exactement le symptome constate :
 * « je mets l'affaire sur la facture ou la commande fournisseur, et elle ne
 * s'affiche pas ».
 * <p>
 * Toutes les methodes sont statiques et sans effet de bord : elles sont
 * verifiees par {@code AffairLinkSupportTest} et utilisees par {@link Module}
 * et {@link ProjectHistory}.
 */
public final class AffairLinkSupport {

    /** Table des affaires. */
    public static final String AFFAIR_TABLE = "AFFAIRE";

    /** Nom de la colonne de rattachement. */
    public static final String AFFAIR_FIELD = "ID_AFFAIRE";

    /** Valeur OpenConcerto de la ligne « Indefini ». */
    public static final int UNDEFINED_ID = 1;

    /**
     * Tables qui doivent porter <b>directement</b> {@code ID_AFFAIRE}.
     * <p>
     * C'est la source de verite unique du module : {@link Module} s'en sert pour
     * creer la colonne, pour l'exposer dans les ecrans de saisie et pour ajouter
     * la colonne « Affaire » et l'action « Historique affaire » dans les listes
     * de l'ERP.
     * <p>
     * <b>FACTURE_FOURNISSEUR</b> figure ici : son absence (avant ce correctif)
     * expliquait que l'affaire d'une facture fournisseur ne s'affichait ni en
     * liste, ni via l'action « Historique affaire », alors que l'ecran de saisie
     * avait ete corrige isolement par {@code SupplierInvoiceAffairComponentSupport}.
     */
    public static final List<String> DIRECT_AFFAIR_TABLES = Collections.unmodifiableList(Arrays.asList(
            "DEVIS",
            "COMMANDE_CLIENT",
            "SAISIE_VENTE_FACTURE",
            "AVOIR_CLIENT",
            "BON_DE_LIVRAISON",
            "DEMANDE_PRIX",
            "BON_RECEPTION",
            "COMMANDE",
            "FACTURE_FOURNISSEUR",
            "SAISIE_ACHAT",
            "AVOIR_FOURNISSEUR",
            "DEMANDE_ACHAT_ELEMENT"));

    /** Tables dont les ecrans de saisie n'ont pas besoin du champ supplementaire. */
    private static final List<String> COMPONENT_FIELD_EXCLUSIONS = Collections.unmodifiableList(Arrays.asList("DEVIS"));

    /** Nature du lien utilise par un onglet de l'historique. */
    public static final int LINK_DIRECT = 0;
    public static final int LINK_VIA_PARENT = 1;
    /** L'onglet ne peut pas etre filtre : il doit etre ignore, pas casse. */
    public static final int LINK_UNAVAILABLE = 2;

    private AffairLinkSupport() {
    }

    /**
     * Acces minimal au schema, implemente par le module sur {@code SQLBase} et,
     * dans les tests, par une simple {@link Map}.
     */
    public interface Schema {
        boolean hasTable(String tableName);

        boolean hasField(String tableName, String fieldName);
    }

    /** Implementation de {@link Schema} a partir de deux ensembles. */
    public static Schema schemaOf(final Set<String> tables, final Map<String, Set<String>> fields) {
        return new Schema() {
            @Override
            public boolean hasTable(final String tableName) {
                return tables.contains(tableName);
            }

            @Override
            public boolean hasField(final String tableName, final String fieldName) {
                final Set<String> tableFields = fields.get(tableName);
                return tableFields != null && tableFields.contains(fieldName);
            }
        };
    }

    /** Lien parent utilise par l'historique pour les tables de lignes. */
    public static final class ParentLink {
        private final String childTable;
        private final String childField;
        private final String parentTable;

        public ParentLink(final String childTable, final String childField, final String parentTable) {
            this.childTable = childTable;
            this.childField = childField;
            this.parentTable = parentTable;
        }

        public String getChildTable() {
            return this.childTable;
        }

        public String getChildField() {
            return this.childField;
        }

        public String getParentTable() {
            return this.parentTable;
        }
    }

    /**
     * Liens parents connus du module, utilises quand une table de lignes ne
     * porte pas (ou plus) {@code ID_AFFAIRE}.
     */
    public static final List<ParentLink> PARENT_LINKS = Collections.unmodifiableList(Arrays.asList(
            new ParentLink("COMMANDE_ELEMENT", "ID_COMMANDE", "COMMANDE"),
            new ParentLink("BON_RECEPTION_ELEMENT", "ID_BON_RECEPTION", "BON_RECEPTION"),
            new ParentLink("FACTURE_FOURNISSEUR_ELEMENT", "ID_FACTURE_FOURNISSEUR", "FACTURE_FOURNISSEUR"),
            new ParentLink("DEMANDE_PRIX_ELEMENT", "ID_DEMANDE_PRIX", "DEMANDE_PRIX"),
            new ParentLink("CHIFFRAGE_COMMANDE_CLIENT", "ID_COMMANDE_CLIENT", "COMMANDE_CLIENT")));

    /** Plan de filtrage d'un onglet d'historique. */
    public static final class TabLink {
        private final String tableName;
        private final int kind;
        private final String parentTable;
        private final String parentField;
        private final String reason;

        TabLink(final String tableName, final int kind, final String parentTable, final String parentField, final String reason) {
            this.tableName = tableName;
            this.kind = kind;
            this.parentTable = parentTable;
            this.parentField = parentField;
            this.reason = reason;
        }

        public String getTableName() {
            return this.tableName;
        }

        public int getKind() {
            return this.kind;
        }

        public boolean isAvailable() {
            return this.kind != LINK_UNAVAILABLE;
        }

        public boolean isDirect() {
            return this.kind == LINK_DIRECT;
        }

        public boolean isViaParent() {
            return this.kind == LINK_VIA_PARENT;
        }

        /** Table parente, ou <code>null</code> si le lien est direct. */
        public String getParentTable() {
            return this.parentTable;
        }

        /** Colonne de liaison vers le parent, ou <code>null</code> si le lien est direct. */
        public String getParentField() {
            return this.parentField;
        }

        /** Explication lisible, utilisee dans les avertissements et les rapports. */
        public String getReason() {
            return this.reason;
        }

        @Override
        public String toString() {
            if (this.kind == LINK_DIRECT) {
                return this.tableName + " via " + AFFAIR_FIELD;
            } else if (this.kind == LINK_VIA_PARENT) {
                return this.tableName + " via " + this.parentField + " -> " + this.parentTable;
            }
            return this.tableName + " indisponible (" + this.reason + ")";
        }
    }

    /**
     * Decide comment filtrer un onglet d'historique.
     * <p>
     * Regles, dans l'ordre :
     * <ul>
     * <li>si la table est {@code AFFAIRE} elle-meme : lien direct sur sa cle
     * (l'appelant passe {@code parentLink} a <code>null</code>) ;</li>
     * <li>si la table porte {@code ID_AFFAIRE} : lien direct ;</li>
     * <li>sinon, si un parent connus porte {@code ID_AFFAIRE} : lien via ce
     * parent ({@code fieldLink} de {@code ListeHistoriquePanel}) ;</li>
     * <li>sinon : {@link #LINK_UNAVAILABLE}. L'onglet doit etre ignore, car
     * laisser une exception sortir de la boucle de selection de
     * {@code ListeHistoriquePanel} empeche <b>tous les onglets suivants</b>
     * d'etre filtres — c'est l'un des chemins qui rendent un document
     * invisible dans l'historique.</li>
     * </ul>
     */
    public static TabLink planTab(final String tableName, final Schema schema, final ParentLink parentLink) {
        return planTab(tableName, schema, parentLink, false);
    }

    /**
     * Variante qui force le lien parent meme si la table porte sa propre
     * colonne.
     * <p>
     * Utile pour les tables de <b>lignes</b> : la colonne de ligne est souvent
     * vide (les lignes heritent de l'affaire de leur document), et un filtre
     * direct ferait disparaitre ces lignes de l'historique. C'est la regle
     * « aucune ligne cachee » appliquee aux documents fournisseurs.
     *
     * @param preferParent <code>true</code> pour filtrer via le document parent
     *                     des que le lien existe.
     */
    public static TabLink planTab(final String tableName, final Schema schema, final ParentLink parentLink, final boolean preferParent) {
        if (tableName == null || schema == null) {
            return new TabLink(tableName, LINK_UNAVAILABLE, null, null, "table inconnue");
        }
        if (!schema.hasTable(tableName)) {
            return new TabLink(tableName, LINK_UNAVAILABLE, null, null, "table absente de la base");
        }
        if (preferParent && parentLink != null && schema.hasTable(parentLink.getParentTable()) && schema.hasField(parentLink.getParentTable(), AFFAIR_FIELD)
                && schema.hasField(parentLink.getChildTable(), parentLink.getChildField())) {
            return new TabLink(tableName, LINK_VIA_PARENT, parentLink.getParentTable(), parentLink.getChildField(),
                    "colonne de ligne " + AFFAIR_FIELD + " ignoree au profit du document " + parentLink.getParentTable());
        }
        if (schema.hasField(tableName, AFFAIR_FIELD)) {
            return new TabLink(tableName, LINK_DIRECT, null, null, "colonne " + AFFAIR_FIELD + " presente");
        }
        if (parentLink != null && schema.hasTable(parentLink.getParentTable()) && schema.hasField(parentLink.getParentTable(), AFFAIR_FIELD)
                && schema.hasField(parentLink.getChildTable(), parentLink.getChildField())) {
            return new TabLink(tableName, LINK_VIA_PARENT, parentLink.getParentTable(), parentLink.getChildField(),
                    "colonne " + AFFAIR_FIELD + " absente : filtrage via " + parentLink.getParentTable());
        }
        if (parentLink == null) {
            final ParentLink known = findParentLink(tableName);
            if (known != null && schema.hasField(known.getParentTable(), AFFAIR_FIELD) && schema.hasField(known.getChildTable(), known.getChildField())) {
                return new TabLink(tableName, LINK_VIA_PARENT, known.getParentTable(), known.getChildField(),
                        "colonne " + AFFAIR_FIELD + " absente : filtrage via " + known.getParentTable());
            }
        }
        return new TabLink(tableName, LINK_UNAVAILABLE, null, null, "ni " + AFFAIR_FIELD + " ni parent rattache a une affaire");
    }

    /** Lien parent declare pour cette table, ou <code>null</code>. */
    public static ParentLink findParentLink(final String tableName) {
        if (tableName == null) {
            return null;
        }
        for (final ParentLink link : PARENT_LINKS) {
            if (link.getChildTable().equals(tableName)) {
                return link;
            }
        }
        return null;
    }

    /**
     * Predicat SQL (lisible) construit pour un onglet : il reproduit exactement
     * ce que fait {@code ListeHistoriquePanel} quand l'utilisateur selectionne
     * une affaire.
     *
     * @param tab       le plan de l'onglet.
     * @param affairID  l'identifiant de l'affaire selectionnee.
     * @param alias     alias SQL de la table de l'onglet (ex. {@code "t"}).
     * @param parentKey nom de la cle primaire de la table parente.
     */
    public static String buildSelectionPredicate(final TabLink tab, final int affairID, final String alias, final String parentKey) {
        if (tab == null || !tab.isAvailable()) {
            return null;
        }
        if (tab.isDirect()) {
            return alias + ".\"" + AFFAIR_FIELD + "\" = " + affairID;
        }
        return alias + ".\"" + tab.getParentField() + "\" in (select p.\"" + parentKey + "\" from \"" + tab.getParentTable() + "\" p where p.\"" + AFFAIR_FIELD + "\" = "
                + affairID + ")";
    }

    /**
     * Vrai si la valeur d'affaire designe une affaire « reelle » : ni
     * <code>null</code>, ni la ligne technique « Indefini » (ID 1).
     */
    public static boolean isRealAffair(final Integer affairID) {
        return affairID != null && affairID.intValue() > UNDEFINED_ID;
    }

    /**
     * Colonnes a creer (ou a verifier) au demarrage.
     * <p>
     * Le calcul est idempotent : une table absente de la base, ou qui porte deja
     * la colonne, n'apparait pas dans le resultat. C'est ce qui permet
     * d'auto-reparer les installations existantes, ou {@code install()} n'est
     * plus rejoue.
     */
    public static List<String> getMissingAffairColumns(final Schema schema) {
        final List<String> result = new ArrayList<String>();
        if (schema == null) {
            return result;
        }
        for (final String table : DIRECT_AFFAIR_TABLES) {
            if (schema.hasTable(table) && !schema.hasField(table, AFFAIR_FIELD)) {
                result.add(table);
            }
        }
        return result;
    }

    /**
     * Tables de lignes qui portent <b>leur propre</b> {@code ID_AFFAIRE} alors
     * que leur document parent en porte un aussi.
     * <p>
     * C'est une configuration piegeante : des que la colonne existe sur la table
     * de lignes, {@code ProjectHistory} ne declare plus de lien parent, et
     * l'historique filtre <b>directement</b> sur l'affaire de ligne. Toutes les
     * lignes dont l'affaire de ligne est vide ou indefinie deviennent alors
     * invisibles, alors que leur document est bien rattache a l'affaire. La
     * methode sert aux diagnostics et aux tests de non-regression.
     */
    public static List<String> getAmbiguousLineTables(final Schema schema) {
        final List<String> result = new ArrayList<String>();
        if (schema == null) {
            return result;
        }
        for (final ParentLink link : PARENT_LINKS) {
            if (schema.hasField(link.getChildTable(), AFFAIR_FIELD) && schema.hasField(link.getParentTable(), AFFAIR_FIELD)) {
                result.add(link.getChildTable());
            }
        }
        return result;
    }

    /**
     * Champs supplementaires a exposer dans les ecrans de saisie pour que
     * l'affaire soit visible et enregistrable.
     *
     * @return les tables concernees, dans l'ordre de {@link #DIRECT_AFFAIR_TABLES}.
     */
    public static List<String> getComponentFieldTables(final Schema schema) {
        final List<String> result = new ArrayList<String>();
        if (schema == null) {
            return result;
        }
        for (final String table : DIRECT_AFFAIR_TABLES) {
            if (COMPONENT_FIELD_EXCLUSIONS.contains(table)) {
                continue;
            }
            if (schema.hasTable(table) && schema.hasField(table, AFFAIR_FIELD)) {
                result.add(table);
            }
        }
        return result;
    }

    /**
     * Cible d'enregistrement des champs supplementaires, c'est-a-dire les
     * ecrans de saisie ({@code ComponentsContext.putAdditionalField} en
     * production).
     * <p>
     * L'interface existe pour deux raisons : rendre cette etape testable sans
     * OpenConcerto, et rappeler le contrat reel de
     * {@code ComponentsContext.putAdditionalField}, qui <b>leve
     * {@link IllegalStateException} quand le champ est deja declare</b>. C'est
     * exactement ce qui empechait le module de demarrer (FACTURE_FOURNISSEUR
     * declaree deux fois).
     */
    public interface AdditionalFieldTarget {
        /**
         * @return <code>true</code> si le champ vient d'etre ajoute,
         *         <code>false</code> s'il etait deja declare.
         * @throws IllegalStateException si le champ existait deja et que
         *                               l'implementation ne le signale pas par
         *                               <code>false</code>.
         */
        boolean putAdditionalField(String table, String field);
    }

    /** Compte rendu de {@link #registerComponentFields(Schema, AdditionalFieldTarget)}. */
    public static final class RegistrationReport {
        private final List<String> added = new ArrayList<String>();
        private final List<String> alreadyPresent = new ArrayList<String>();
        private final List<String> refused = new ArrayList<String>();

        public List<String> getAdded() {
            return Collections.unmodifiableList(this.added);
        }

        public List<String> getAlreadyPresent() {
            return Collections.unmodifiableList(this.alreadyPresent);
        }

        /** Tables qui n'ont pas pu etre declarees, avec la raison. */
        public List<String> getRefused() {
            return Collections.unmodifiableList(this.refused);
        }

        /** Vrai si le module a pu declarer tous les champs qu'il voulait. */
        public boolean isComplete() {
            return this.refused.isEmpty();
        }

        public String getSummary() {
            return "ajoutes " + this.added + ", deja presents " + this.alreadyPresent
                    + (this.refused.isEmpty() ? "" : ", refuses " + this.refused);
        }
    }

    /**
     * Declare {@code ID_AFFAIRE} dans les ecrans de saisie, <b>une seule fois
     * par table</b> et sans jamais faire echouer le demarrage.
     * <p>
     * Pourquoi cette methode existe : {@code ComponentsContext.putAdditionalField}
     * leve {@link IllegalStateException} des que le champ est deja declare. Un
     * module qui appelle deux fois la meme declaration (ou qui declare un champ
     * que le cœur a deja pose) ne demarre plus du tout, avec pour seul message
     * « Already added ID_AFFAIRE in ... ». Le demarrage du module ne doit pas
     * dependre d'un champ d'affichage : les erreurs sont collectees dans le
     * compte rendu, pas propagees.
     * <p>
     * Les cas traites :
     * <ul>
     * <li>table presente deux fois dans le plan : ignoree la seconde fois ;</li>
     * <li>champ deja declare ({@link IllegalStateException}, ou
     * <code>false</code>) : compte comme « deja present », ce n'est pas une
     * erreur ;</li>
     * <li>toute autre erreur (champ non cree par le module, table sans
     * element...) : la table est « refusee », les autres sont traitees
     * normalement.</li>
     * </ul>
     */
    public static RegistrationReport registerComponentFields(final Schema schema, final AdditionalFieldTarget target) {
        final RegistrationReport report = new RegistrationReport();
        if (schema == null || target == null) {
            return report;
        }
        final Set<String> done = new LinkedHashSet<String>();
        for (final String table : getComponentFieldTables(schema)) {
            if (!done.add(table)) {
                continue;
            }
            try {
                if (target.putAdditionalField(table, AFFAIR_FIELD)) {
                    report.added.add(table);
                } else {
                    report.alreadyPresent.add(table);
                }
            } catch (IllegalStateException e) {
                // Deja declare (coeur, autre module, version precedente du module).
                report.alreadyPresent.add(table);
            } catch (RuntimeException e) {
                report.refused.add(table + " (" + e.getMessage() + ")");
            }
        }
        return report;
    }

    /**
     * Verifie qu'une liste de tables couvre bien toutes les tables a affaire
     * presentes dans le schema.
     *
     * @return les tables presentes dans le schema mais oubliees par la liste.
     */
    public static List<String> getUncoveredTables(final Schema schema, final List<String> coveredTables) {
        final List<String> result = new ArrayList<String>();
        if (schema == null) {
            return result;
        }
        final Set<String> covered = coveredTables == null ? Collections.<String> emptySet() : new LinkedHashSet<String>(coveredTables);
        for (final String table : DIRECT_AFFAIR_TABLES) {
            if (schema.hasTable(table) && !covered.contains(table)) {
                result.add(table);
            }
        }
        return result;
    }

    /**
     * Ordre des onglets de l'historique des affaires, tel que construit par
     * {@link ProjectHistory}. Cette table de correspondance est aussi utilisee
     * par les tests pour verifier que chaque document rattachable a une affaire
     * possede bien un onglet.
     *
     * @return libelle -&gt; table des documents (les tables de lignes sont
     *         ajoutees par l'appelant avec leur lien parent).
     */
    public static Map<String, String> getDocumentTabs() {
        final Map<String, String> tabs = new LinkedHashMap<String, String>();
        tabs.put("Devis", "DEVIS");
        tabs.put("Bons de commande", "COMMANDE_CLIENT");
        tabs.put("Factures", "SAISIE_VENTE_FACTURE");
        tabs.put("Avoirs", "AVOIR_CLIENT");
        tabs.put("Bons de livraison clients", "BON_DE_LIVRAISON");
        tabs.put("Demandes de prix", "DEMANDE_PRIX");
        tabs.put("Bons de réception fournisseurs", "BON_RECEPTION");
        tabs.put("Commandes fournisseurs", "COMMANDE");
        tabs.put("Achats", "SAISIE_ACHAT");
        tabs.put("Factures fournisseurs", "FACTURE_FOURNISSEUR");
        tabs.put("Avoirs fournisseurs", "AVOIR_FOURNISSEUR");
        tabs.put("Demandes d'achat", "DEMANDE_ACHAT_ELEMENT");
        return tabs;
    }

    /** Tables de documents rattachees a une affaire qui n'ont pas d'onglet. */
    public static List<String> getDocumentTablesWithoutTab() {
        final List<String> covered = new ArrayList<String>(getDocumentTabs().values());
        final List<String> result = new ArrayList<String>();
        for (final String table : DIRECT_AFFAIR_TABLES) {
            if (!covered.contains(table)) {
                result.add(table);
            }
        }
        return result;
    }

}
