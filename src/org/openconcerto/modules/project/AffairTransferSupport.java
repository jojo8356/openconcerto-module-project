/*
 * Reprise de l'affaire dans les transferts de documents.
 *
 * Constat mesure dans OpenConcerto 1.7.6 : <b>aucun</b> des injecteurs du c&oelig;ur
 * ne recopie {@code ID_AFFAIRE}. La recherche
 * {@code grep -rn ID_AFFAIRE org/openconcerto/erp/injector/} ne renvoie rien,
 * alors que ces injecteurs decrivent explicitement, champ par champ, ce qui est
 * transfere ({@code map(ID_FOURNISSEUR, ...)}, {@code map(NOM, ...)}...). Un
 * champ non declare n'est pas copie : l'affaire est donc perdue a chaque
 * transfert.
 *
 * Consequence visible : on renseigne l'affaire sur une commande fournisseur,
 * on transfere la commande en facture, et la facture n'a pas d'affaire — donc
 * rien a afficher dans la liste, dans l'historique, ni dans les lignes.
 *
 * Cette classe porte la <b>regle</b> (quelles paires de transfert doivent
 * reprendre l'affaire) sans dependre d'OpenConcerto, afin d'etre testable. Le
 * branchement reel se fait dans {@code Module.installAffairTransferMapping()}.
 */
package org.openconcerto.modules.project;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

public final class AffairTransferSupport {

    /** Champ transportant l'affaire. */
    public static final String AFFAIR_FIELD = AffairLinkSupport.AFFAIR_FIELD;

    /**
     * Paires de transfert (source, destination) qui doivent reprendre
     * l'affaire.
     * <p>
     * La liste est volontairement limitee aux transferts qui <b>creent un
     * document</b> a partir d'un autre document rattachable a une affaire. Les
     * paires de lignes (par exemple {@code COMMANDE_ELEMENT ->
     * SAISIE_ACHAT_ELEMENT}) sont volontairement exclues : quand aucun
     * injecteur n'est enregistre pour elles, le c&oelig;ur en fabrique un qui
     * recopie <b>tous</b> les champs de meme nom ({@code createDefaultMap}), et
     * {@code ID_AFFAIRE} est donc deja transporte.
     * </p>
     */
    public static final List<String[]> TRANSFER_PAIRS = Collections.unmodifiableList(Arrays.asList(
            // Achats : c'est le « Transfert en facture » d'une commande
            // fournisseur (CommandeSQLElement.transfertFacture ouvre une
            // SAISIE_ACHAT via SaisieAchatSQLComponent.loadCommande).
            new String[] { "COMMANDE", "SAISIE_ACHAT" },
            new String[] { "COMMANDE", "BON_RECEPTION" },
            new String[] { "COMMANDE", "FACTURE_FOURNISSEUR" },
            new String[] { "BON_RECEPTION", "SAISIE_ACHAT" },
            new String[] { "BON_RECEPTION", "FACTURE_FOURNISSEUR" },
            new String[] { "DEVIS", "COMMANDE" },
            new String[] { "SAISIE_ACHAT", "AVOIR_FOURNISSEUR" },
            // Ventes
            new String[] { "DEVIS", "COMMANDE_CLIENT" },
            new String[] { "DEVIS", "SAISIE_VENTE_FACTURE" },
            new String[] { "DEVIS", "BON_DE_LIVRAISON" },
            new String[] { "COMMANDE_CLIENT", "SAISIE_VENTE_FACTURE" },
            new String[] { "COMMANDE_CLIENT", "BON_DE_LIVRAISON" },
            new String[] { "COMMANDE_CLIENT", "COMMANDE" },
            new String[] { "BON_DE_LIVRAISON", "SAISIE_VENTE_FACTURE" },
            new String[] { "SAISIE_VENTE_FACTURE", "AVOIR_CLIENT" },
            new String[] { "SAISIE_VENTE_FACTURE", "BON_DE_LIVRAISON" },
            new String[] { "SAISIE_VENTE_FACTURE", "COMMANDE" }));

    private AffairTransferSupport() {
    }

    /** Vrai si cette paire fait partie de celles a reparer. */
    public static boolean isTransferPair(final String src, final String dest) {
        if (src == null || dest == null) {
            return false;
        }
        for (final String[] pair : TRANSFER_PAIRS) {
            if (pair[0].equals(src.trim().toUpperCase(java.util.Locale.ROOT)) && pair[1].equals(dest.trim().toUpperCase(java.util.Locale.ROOT))) {
                return true;
            }
        }
        return false;
    }

    /**
     * Faut-il ajouter la reprise de l'affaire a cette paire ?
     *
     * @param src    table source.
     * @param dest   table destination.
     * @param schema schema de la base (presence des tables et des colonnes).
     * @return vrai si les deux documents portent {@code ID_AFFAIRE}.
     */
    public static boolean shouldMap(final String src, final String dest, final AffairLinkSupport.Schema schema) {
        if (schema == null || !isTransferPair(src, dest)) {
            return false;
        }
        // Un transfert vers une table qui n'a pas la colonne ne doit pas etre
        // touche : la valeur serait perdue de toute facon et la modification
        // du mapping n'apporterait rien.
        return schema.hasTable(src) && schema.hasField(src, AFFAIR_FIELD) && schema.hasTable(dest) && schema.hasField(dest, AFFAIR_FIELD);
    }

    /** Acces aux injecteurs de transfert (implemente par le module en production). */
    public interface InjectorAccess {

        /** Vrai si un injecteur existe pour cette paire (le c&oelig;ur en enregistre un). */
        boolean isRegistered(String src, String dest);

        /** Vrai si l'injecteur transporte deja {@code ID_AFFAIRE}. */
        boolean isMapped(String src, String dest);

        /**
         * Ajoute la reprise de {@code ID_AFFAIRE} a cet injecteur.
         *
         * @return vrai si le mapping a ete ajoute.
         */
        boolean addMapping(String src, String dest);
    }

    /** Compte rendu de {@link #install(AffairLinkSupport.Schema, InjectorAccess)}. */
    public static final class Report {
        private final List<String> added = new ArrayList<String>();
        private final List<String> alreadyMapped = new ArrayList<String>();
        private final List<String> noInjector = new ArrayList<String>();
        private final List<String> noColumn = new ArrayList<String>();
        private final List<String> failed = new ArrayList<String>();

        /** Paires corrigees (ex. {@code COMMANDE -> SAISIE_ACHAT}). */
        public List<String> getAdded() {
            return Collections.unmodifiableList(this.added);
        }

        /** Paires qui transportaient deja l'affaire. */
        public List<String> getAlreadyMapped() {
            return Collections.unmodifiableList(this.alreadyMapped);
        }

        /** Paires declarees mais sans injecteur enregistre dans le c&oelig;ur. */
        public List<String> getNoInjector() {
            return Collections.unmodifiableList(this.noInjector);
        }

        /** Paires dont une des tables n'a pas la colonne d'affaire. */
        public List<String> getNoColumn() {
            return Collections.unmodifiableList(this.noColumn);
        }

        /** Paires dont la modification a echoue (message inclus). */
        public List<String> getFailed() {
            return Collections.unmodifiableList(this.failed);
        }

        /** Vrai si aucun echec technique n'a eu lieu. */
        public boolean isComplete() {
            return this.failed.isEmpty();
        }

        public String getSummary() {
            return "affaire transportee par " + this.added.size() + " transfert(s) " + this.added
                    + (this.alreadyMapped.isEmpty() ? "" : ", deja en place " + this.alreadyMapped)
                    + (this.noColumn.isEmpty() ? "" : ", sans colonne " + this.noColumn)
                    + (this.noInjector.isEmpty() ? "" : ", sans injecteur " + this.noInjector)
                    + (this.failed.isEmpty() ? "" : ", en echec " + this.failed);
        }
    }

    /**
     * Installe la reprise de l'affaire sur toutes les paires possibles.
     * <p>
     * Idempotent : une paire deja mappee est signalee, pas retouchee. Aucune
     * exception ne remonte : le demarrage du module ne doit pas dependre de
     * cette reparation.
     * </p>
     */
    public static Report install(final AffairLinkSupport.Schema schema, final InjectorAccess access) {
        final Report report = new Report();
        if (schema == null || access == null) {
            return report;
        }
        for (final String[] pair : TRANSFER_PAIRS) {
            final String src = pair[0];
            final String dest = pair[1];
            final String label = src + " -> " + dest;
            if (!shouldMap(src, dest, schema)) {
                report.noColumn.add(label);
                continue;
            }
            try {
                if (!access.isRegistered(src, dest)) {
                    report.noInjector.add(label);
                    continue;
                }
                if (access.isMapped(src, dest)) {
                    report.alreadyMapped.add(label);
                    continue;
                }
                if (access.addMapping(src, dest)) {
                    report.added.add(label);
                } else {
                    report.failed.add(label + " (mapping refuse)");
                }
            } catch (RuntimeException e) {
                report.failed.add(label + " (" + e + ")");
            }
        }
        return report;
    }
}
