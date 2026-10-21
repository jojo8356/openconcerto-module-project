package org.openconcerto.modules.project.panels;

import java.util.ArrayList;
import java.util.List;

/**
 * Catalogue des panneaux du module <code>org.openconcerto.modules.project</code>
 * (version 1.1), d'apres le code source du module :
 * <ul>
 * <li><code>Module.setupMenu</code> : « Liste des affaires », « Historique des
 * affaires », « Saisie affaire », import/export ;</li>
 * <li><code>Module.start</code> : onglets « Commandes en cours », « Devis en
 * attente », « Affaires » ;</li>
 * <li><code>ProjectHistory</code> : les onglets de l'historique (une liste par
 * table) ;</li>
 * <li><code>Module.setupElements</code> : les colonnes « Affaire » ajoutees
 * aux listes, et les actions « Historique affaire » ;</li>
 * <li><code>HistoriqueAffaireBilanPanel</code> : les totaux du bilan ;</li>
 * <li><code>ProjectImportExport</code> : l'export des affaires ;</li>
 * <li>les injecteurs SQL du module : ils exigent la colonne ID_AFFAIRE sur
 * les tables qu'ils relient.</li>
 * </ul>
 */
public final class Catalogue {

    private Catalogue() {
    }

    /** Tables dont le module ajoute la colonne ID_AFFAIRE (Module.install). */
    public static final String[] TABLES_WITH_AFFAIRE = { "DEMANDE_PRIX", "BON_RECEPTION", "DEMANDE_ACHAT_ELEMENT", "SAISIE_VENTE_FACTURE", "AVOIR_CLIENT", "BON_DE_LIVRAISON", "COMMANDE_CLIENT",
            "DEVIS", "COMMANDE", "SAISIE_ACHAT", "AVOIR_FOURNISSEUR" };

    /**
     * Tables principales du module : leur presence dans un schema indique
     * que le module y est installe. Un schema qui n'a pas ces tables n'est
     * pas controle (sinon chaque panneau serait signale « table
     * absente »).
     */
    public static final String[] CORE_TABLES = { "AFFAIRE", "DEVIS", "COMMANDE_CLIENT", "COMMANDE", "SAISIE_VENTE_FACTURE", "SAISIE_ACHAT", "FACTURE_FOURNISSEUR" };

    /**
     * Le module project est-il installe dans ce schema ?
     */
    public static boolean isModuleInstalled(final Db db, final String schema) throws Exception {
        int found = 0;
        for (int i = 0; i < CORE_TABLES.length; i++) {
            if (db.tableExists(schema, CORE_TABLES[i])) {
                found++;
            }
        }
        // AFFAIRE + au moins deux autres tables principales
        return found >= 3;
    }

    /** Etat « dossier clos » (ProjectStateSQLElement). */
    public static final int DOSSIER_CLOS = 6;
    /** Etat « en cours » (ProjectStateSQLElement). */
    public static final int EN_COURS = 3;
    /** Etat devis « en attente » (EtatDevisSQLElement). */
    public static final int DEVIS_EN_ATTENTE = 2;

    /**
     * Construit le catalogue pour un schema donne.
     */
    public static List<Panel> build(String schema) {
        final List<Panel> panels = new ArrayList<Panel>();

        // ------------------------------------------------------------------
        // Groupe « Listes » : panneaux de liste que le module enrichit.
        // ------------------------------------------------------------------
        panels.add(list("liste.affaires", "Liste des affaires", "Listes", "AFFAIRE")
                .requiresReason("AFFAIRE", "champs de la fiche affaire (ProjectSQLElement)", "NUMERO", "NOM", "INFOS", "ID_CLIENT", "ID_DEVIS", "DATE", "ID_COMMERCIAL",
                        "ID_ETAT_AFFAIRE", "ID_TYPE_AFFAIRE")
                .notes("Module.setupMenu : liste des affaires. Le module ajoute le bouton de modification."));

        panels.add(list("liste.devis", "Liste des devis", "Listes", "DEVIS")
                .requiresReason("DEVIS", "liste des devis + colonne « Affaire » + colonne « Temps Total »", "NUMERO", "DATE", "T_HT", "T_HA", "ID_CLIENT", "ID_AFFAIRE",
                        "ID_ETAT_DEVIS")
                .affaireColumn("ID_AFFAIRE"));

        panels.add(list("liste.commandes_clients", "Liste des commandes clients", "Listes", "COMMANDE_CLIENT")
                .requiresReason("COMMANDE_CLIENT", "liste des commandes clients + colonne « Affaire » + colonne « Temps Total »", "NUMERO", "DATE", "T_HT", "ID_CLIENT",
                        "ID_AFFAIRE")
                .affaireColumn("ID_AFFAIRE"));

        panels.add(list("liste.demandes_prix", "Liste des demandes de prix", "Listes", "DEMANDE_PRIX")
                .requiresReason("DEMANDE_PRIX", "colonne « Affaire » ajoutee par le module", "NUMERO", "ID_AFFAIRE")
                .affaireColumn("ID_AFFAIRE"));

        panels.add(list("liste.demandes_achat", "Liste des demandes d'achat", "Listes", "DEMANDE_ACHAT_ELEMENT")
                .requiresReason("DEMANDE_ACHAT_ELEMENT", "colonne « Affaire » ajoutee par le module", "ID_AFFAIRE")
                .affaireColumn("ID_AFFAIRE"));

        panels.add(list("liste.saisie_vente_facture", "Liste des factures clients", "Listes", "SAISIE_VENTE_FACTURE")
                .requiresReason("SAISIE_VENTE_FACTURE", "colonne « Affaire » + totaux du bilan", "NUMERO", "T_HT", "T_TTC", "ID_AFFAIRE")
                .affaireColumn("ID_AFFAIRE"));

        panels.add(list("liste.avoirs_clients", "Liste des avoirs clients", "Listes", "AVOIR_CLIENT")
                .requiresReason("AVOIR_CLIENT", "colonne « Affaire » + avoir deduits du bilan", "NUMERO", "MONTANT_HT", "A_DEDUIRE", "ID_AFFAIRE")
                .affaireColumn("ID_AFFAIRE"));

        panels.add(list("liste.bons_livraison", "Liste des bons de livraison", "Listes", "BON_DE_LIVRAISON")
                .requiresReason("BON_DE_LIVRAISON", "colonne « Affaire » + bouton de modification", "NUMERO", "ID_AFFAIRE")
                .affaireColumn("ID_AFFAIRE"));

        panels.add(list("liste.commandes_fournisseurs", "Liste des commandes fournisseurs", "Listes", "COMMANDE")
                .requiresReason("COMMANDE", "colonne « Affaire » + bouton de modification", "NUMERO", "T_HT", "ID_AFFAIRE")
                .affaireColumn("ID_AFFAIRE"));

        panels.add(list("liste.saisie_achat", "Liste des achats", "Listes", "SAISIE_ACHAT")
                .requiresReason("SAISIE_ACHAT", "colonne « Affaire » ajoutee par le module + total achats du bilan", "MONTANT_HT", "ID_AFFAIRE")
                .affaireColumn("ID_AFFAIRE"));

        panels.add(list("liste.avoirs_fournisseurs", "Liste des avoirs fournisseurs", "Listes", "AVOIR_FOURNISSEUR")
                .requiresReason("AVOIR_FOURNISSEUR", "colonne « Affaire » + avoir fournisseurs du bilan", "NUMERO", "MONTANT_HT", "ID_AFFAIRE")
                .affaireColumn("ID_AFFAIRE"));

        // ------------------------------------------------------------------
        // Groupe « Historique » : l'onglet « Historique des affaires ».
        // ------------------------------------------------------------------
        panels.add(history("historique.liste_affaires", "Historique : liste des affaires", "Historique", "AFFAIRE", new Panel.Link[0])
                .requiresReason("AFFAIRE", "combo de selection d'affaire (NUMERO, ID_CLIENT, NOM, DATE)", "NUMERO", "ID_CLIENT", "NOM", "DATE", "ID_ETAT_AFFAIRE")
                .extra("t.\"ID_ETAT_AFFAIRE\" <> " + DOSSIER_CLOS)
                .notes("La ligne « Indefini » (ID 1) est retiree, et les dossiers clos sont masques par defaut."));

        panels.add(history("historique.devis", "Historique : Devis", "Historique", "DEVIS", new Panel.Link[0]).affaireColumn("ID_AFFAIRE"));
        panels.add(history("historique.commandes_clients", "Historique : Bons de commande", "Historique", "COMMANDE_CLIENT", new Panel.Link[0]).affaireColumn("ID_AFFAIRE"));
        panels.add(history("historique.chiffrage", "Historique : Chiffrage", "Historique", "CHIFFRAGE_COMMANDE_CLIENT",
                new Panel.Link[] { new Panel.Link("COMMANDE_CLIENT", "ID_COMMANDE_CLIENT") })
                .requiresReason("CHIFFRAGE_COMMANDE_CLIENT", "budget chiffre du bilan", "T_PA_HT", "ID_COMMANDE_CLIENT"));
        panels.add(history("historique.factures", "Historique : Factures", "Historique", "SAISIE_VENTE_FACTURE", new Panel.Link[0]).affaireColumn("ID_AFFAIRE"));
        panels.add(history("historique.avoirs", "Historique : Avoirs", "Historique", "AVOIR_CLIENT", new Panel.Link[0]).affaireColumn("ID_AFFAIRE"));
        panels.add(history("historique.demandes_achat", "Historique : Demandes d'achat", "Historique", "DEMANDE_ACHAT_ELEMENT", new Panel.Link[0]).affaireColumn("ID_AFFAIRE"));
        panels.add(history("historique.demandes_prix", "Historique : Demandes de prix", "Historique", "DEMANDE_PRIX", new Panel.Link[0]).affaireColumn("ID_AFFAIRE"));
        panels.add(history("historique.bons_livraison", "Historique : Bons de livraison clients", "Historique", "BON_DE_LIVRAISON", new Panel.Link[0]).affaireColumn("ID_AFFAIRE"));
        panels.add(history("historique.commandes_fournisseurs", "Historique : Commandes fournisseurs", "Historique", "COMMANDE", new Panel.Link[0]).affaireColumn("ID_AFFAIRE"));
        panels.add(history("historique.articles_commandes", "Historique : Articles commandes", "Historique", "COMMANDE_ELEMENT",
                new Panel.Link[] { new Panel.Link("COMMANDE", "ID_COMMANDE") })
                .requiresReason("COMMANDE_ELEMENT", "montant des commandes fournisseurs (T_PA_HT)", "T_PA_HT", "ID_COMMANDE"));
        panels.add(history("historique.bons_reception", "Historique : Bons de reception fournisseurs", "Historique", "BON_RECEPTION", new Panel.Link[0]).affaireColumn("ID_AFFAIRE"));
        panels.add(history("historique.articles_receptionnes", "Historique : Articles receptionnes", "Historique", "BON_RECEPTION_ELEMENT",
                new Panel.Link[] { new Panel.Link("BON_RECEPTION", "ID_BON_RECEPTION") })
                .requiresReason("BON_RECEPTION_ELEMENT", "articles receptionnes rattaches au bon de reception", "ID_BON_RECEPTION"));
        panels.add(history("historique.achats", "Historique : Achats", "Historique", "SAISIE_ACHAT", new Panel.Link[0]).affaireColumn("ID_AFFAIRE"));
        panels.add(history("historique.factures_fournisseurs", "Historique : Factures fournisseurs", "Historique", "FACTURE_FOURNISSEUR", new Panel.Link[0]).affaireColumn("ID_AFFAIRE"));
        panels.add(history("historique.factures_fournisseurs_elements", "Historique : Elements de facture fournisseur", "Historique", "FACTURE_FOURNISSEUR_ELEMENT",
                new Panel.Link[] { new Panel.Link("FACTURE_FOURNISSEUR", "ID_FACTURE_FOURNISSEUR") })
                .requiresReason("FACTURE_FOURNISSEUR_ELEMENT", "colonne « nom fournisseur » ajoutee par le module", "ID_FACTURE_FOURNISSEUR")
                .notes("Colonne ID_COMMANDE_ELEMENT verifiee par le contrat de structure (transfert)."));
        panels.add(history("historique.avoirs_fournisseurs", "Historique : Avoirs fournisseurs", "Historique", "AVOIR_FOURNISSEUR", new Panel.Link[0]).affaireColumn("ID_AFFAIRE"));
        panels.add(history("historique.temps", "Historique : Temps", "Historique", "AFFAIRE_TEMPS",
                new Panel.Link[] { new Panel.Link("COMMANDE_CLIENT_ELEMENT", "ID_COMMANDE_CLIENT_ELEMENT"), new Panel.Link("COMMANDE_CLIENT", "ID_COMMANDE_CLIENT") }, true)
                .requiresReason("AFFAIRE_TEMPS", "temps realises par affaire", "TEMPS", "ID_COMMANDE_CLIENT_ELEMENT"));
        panels.add(history("historique.stock", "Historique : Stock", "Historique", "MOUVEMENT_STOCK", new Panel.Link[0], true)
                .notes("Table optionnelle : le module ne l'affiche que si AFFAIRE contient ID_DEPOT_STOCK."));
        panels.add(history("historique.note_frais", "Historique : Note de frais", "Historique", "NOTE_DE_FRAIS_ELEMENT", new Panel.Link[0], true)
                .notes("Table optionnelle : le lien avec l'affaire depend de l'installation."));
        panels.add(history("historique.pointage", "Historique : Pointage", "Historique", "POINTAGE_ELEMENT", new Panel.Link[0], true)
                .notes("Table optionnelle : le lien avec l'affaire depend de l'installation."));

        // ------------------------------------------------------------------
        // Groupe « Onglets » : les trois onglets ajoutes par le module.
        // ------------------------------------------------------------------
        panels.add(list("onglet.affaires", "Onglet « Affaires »", "Onglets", "AFFAIRE")
                .requiresReason("AFFAIRE", "ListeAddPanel de l'onglet Affaires", "NUMERO", "NOM", "DATE", "ID_CLIENT", "ID_ETAT_AFFAIRE"));

        panels.add(history("onglet.commandes_en_cours", "Onglet « Commandes en cours »", "Onglets", "COMMANDE_CLIENT_ELEMENT",
                new Panel.Link[] { new Panel.Link("COMMANDE_CLIENT", "ID_COMMANDE_CLIENT") })
                .requiresReason("COMMANDE_CLIENT_ELEMENT", "colonnes du panneau « Commandes en cours »", "NOM", "T_PV_HT", "ID_COMMANDE_CLIENT", "ID_UNITE_VENTE", "QTE",
                        "QTE_UNITAIRE", "ID_ARTICLE", "ID_FAMILLE_ARTICLE")
                .requiresReason("COMMANDE_CLIENT", "numero, date et montant de la commande", "NUMERO", "DATE", "T_HT", "ID_AFFAIRE")
                .requiresReason("AFFAIRE", "numero et date de l'affaire, et son etat", "NUMERO", "DATE", "ID_ETAT_AFFAIRE")
                .extra("a.\"ID_ETAT_AFFAIRE\" = " + EN_COURS)
                .notes("Seules les commandes dont l'affaire est « en cours » sont affichees."));

        panels.add(history("onglet.devis_en_attente", "Onglet « Devis en attente »", "Onglets", "DEVIS_ELEMENT",
                new Panel.Link[] { new Panel.Link("DEVIS", "ID_DEVIS") })
                .requiresReason("DEVIS_ELEMENT", "colonnes du panneau « Devis en attente »", "NOM", "T_PV_HT", "ID_DEVIS", "ID_UNITE_VENTE", "QTE", "QTE_UNITAIRE", "ID_ARTICLE",
                        "ID_FAMILLE_ARTICLE")
                .requiresReason("DEVIS", "numero, date, montant et etat du devis", "NUMERO", "DATE", "T_HT", "ID_CLIENT", "ID_ETAT_DEVIS")
                .requiresReason("CLIENT", "raison sociale du client", "NOM")
                .extra("p1.\"ID_ETAT_DEVIS\" = " + DEVIS_EN_ATTENTE)
                .notes("Seuls les devis « en attente » sont affiches."));

        // ------------------------------------------------------------------
        // Groupe « Bilan » : les totaux affiches en bas de l'historique.
        // ------------------------------------------------------------------
        panels.add(history("bilan.marche", "Bilan : montant du marche et budget chiffre", "Bilan", "COMMANDE_CLIENT", new Panel.Link[0])
                .affaireColumn("ID_AFFAIRE")
                .requiresReason("COMMANDE_CLIENT", "montant du marche (T_HT)", "T_HT")
                .requiresReason("CHIFFRAGE_COMMANDE_CLIENT", "budget chiffre (T_PA_HT)", "T_PA_HT"));
        panels.add(history("bilan.facture", "Bilan : montant facture et avoirs", "Bilan", "SAISIE_VENTE_FACTURE", new Panel.Link[0])
                .affaireColumn("ID_AFFAIRE")
                .requiresReason("SAISIE_VENTE_FACTURE", "montant facture (T_HT)", "T_HT")
                .requiresReason("AVOIR_CLIENT", "avoirs deduits (MONTANT_HT, A_DEDUIRE)", "MONTANT_HT", "A_DEDUIRE"));
        panels.add(history("bilan.achats", "Bilan : total des achats", "Bilan", "SAISIE_ACHAT", new Panel.Link[0])
                .affaireColumn("ID_AFFAIRE")
                .requiresReason("SAISIE_ACHAT", "achats (MONTANT_HT)", "MONTANT_HT")
                .requiresReason("FACTURE_FOURNISSEUR", "factures fournisseurs (T_HT)", "T_HT")
                .requiresReason("FACTURE_FOURNISSEUR_ELEMENT", "montant des articles de facture fournisseur (T_PA_HT)", "T_PA_HT")
                .requiresReason("AVOIR_FOURNISSEUR", "avoirs fournisseurs (MONTANT_HT)", "MONTANT_HT"));
        panels.add(history("bilan.commandes_fournisseurs", "Bilan : total des commandes fournisseurs", "Bilan", "COMMANDE", new Panel.Link[0])
                .affaireColumn("ID_AFFAIRE")
                .requiresReason("COMMANDE", "commandes fournisseurs (T_HT)", "T_HT")
                .requiresReason("COMMANDE_ELEMENT", "articles commandes (T_PA_HT)", "T_PA_HT"));

        // ------------------------------------------------------------------
        // Groupe « Export » : l'export des affaires (ProjectImportExport).
        // ------------------------------------------------------------------
        panels.add(list("export.affaires", "Export des affaires", "Export", "AFFAIRE")
                .requiresReason("AFFAIRE", "colonnes exportees par ProjectImportExport", "NUMERO", "INFOS", "ID_CLIENT", "DATE", "ID_COMMERCIAL", "ID_ETAT_AFFAIRE",
                        "ID_DEVIS")
                .requiresReason("DEVIS", "numeros de devis rattaches", "NUMERO")
                .requiresReason("COMMANDE", "numeros de commande fournisseur rattaches", "NUMERO")
                .requiresReason("AVOIR_CLIENT", "numeros d'avoir client rattaches", "NUMERO")
                .requiresReason("COMMANDE_CLIENT", "numeros de commande client rattaches", "NUMERO")
                .requiresReason("BON_DE_LIVRAISON", "numeros de bon de livraison rattaches", "NUMERO")
                .requiresReason("SAISIE_VENTE_FACTURE", "numeros de facture client rattaches", "NUMERO")
                .notes("L'export ecrit un fichier : NUMERO, INFOS, ID_CLIENT, DATE, ID_COMMERCIAL, ID_ETAT_AFFAIRE, ID_DEVIS puis les listes de numeros."));

        return panels;
    }

    /**
     * Colonnes exigees par l'application, hors panneau : c'est le contrat de
     * structure. Une colonne manquante ne fait pas disparaitre une ligne,
     * mais casse une operation (transfert, injection) — c'est exactement le
     * bug ID_COMMANDE_ELEMENT rencontre en production.
     */
    public static List<Panel> structureContract() {
        final List<Panel> panels = new ArrayList<Panel>();

        final Panel transfertFactureFournisseur = new Panel("structure.transfert.facture_fournisseur",
                "Transfert commande fournisseur -> facture fournisseur : colonne ID_COMMANDE_ELEMENT", "Structure", Panel.KIND_STRUCTURE, "FACTURE_FOURNISSEUR_ELEMENT",
                false);
        transfertFactureFournisseur.requiresReason("FACTURE_FOURNISSEUR_ELEMENT", "colonne de rattachement de la ligne de facture a la ligne de commande",
                "ID_COMMANDE_ELEMENT");
        transfertFactureFournisseur.notes("Colonne + cle etrangere vers COMMANDE_ELEMENT + index. Son absence provoque « X is not in table /T/FACTURE_FOURNISSEUR_ELEMENT/ ».");
        transfertFactureFournisseur.foreignKey("ID_COMMANDE_ELEMENT", "COMMANDE_ELEMENT");
        panels.add(transfertFactureFournisseur);

        final Panel transfertBonReception = new Panel("structure.transfert.bon_reception", "Transfert commande -> bon de reception : colonne ID_COMMANDE_ELEMENT",
                "Structure", Panel.KIND_STRUCTURE, "BON_RECEPTION_ELEMENT", false);
        transfertBonReception.requiresReason("BON_RECEPTION_ELEMENT", "colonne de rattachement de la ligne de reception a la ligne de commande", "ID_COMMANDE_ELEMENT");
        panels.add(transfertBonReception);

        final Panel liensAffaire = new Panel("structure.liens.affaire", "Colonne ID_AFFAIRE ajoutee par le module sur les tables rattachees", "Structure",
                Panel.KIND_STRUCTURE, "AFFAIRE", false);
        for (String table : TABLES_WITH_AFFAIRE) {
            liensAffaire.requiresReason(table, "colonne ID_AFFAIRE ajoutee par Module.install()", "ID_AFFAIRE");
        }
        liensAffaire.notes("Sans ID_AFFAIRE, les lignes n'apparaissent dans aucun onglet de l'historique : les donnees sont cachees.");
        panels.add(liensAffaire);

        return panels;
    }

    private static Panel list(String id, String label, String group, String table) {
        return new Panel(id, label, group, Panel.KIND_LIST, table, false);
    }

    private static Panel history(String id, String label, String group, String table, Panel.Link[] chain) {
        return history(id, label, group, table, chain, false);
    }

    private static Panel history(String id, String label, String group, String table, Panel.Link[] chain, boolean optional) {
        final Panel panel = new Panel(id, label, group, Panel.KIND_HISTORY, table, optional);
        panel.chain(chain);
        return panel;
    }
}
