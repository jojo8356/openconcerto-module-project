package org.openconcerto.modules.project;

import java.awt.event.ActionEvent;
import java.util.List;

import javax.swing.AbstractAction;

import org.openconcerto.erp.core.common.component.TransfertBaseSQLComponent;
import org.openconcerto.erp.core.supplychain.order.component.CommandeSQLComponent;
import org.openconcerto.sql.Configuration;
import org.openconcerto.sql.element.SQLComponent;
import org.openconcerto.sql.element.SQLElement;
import org.openconcerto.sql.element.SQLElementDirectory;
import org.openconcerto.sql.model.SQLRowValues;
import org.openconcerto.sql.view.EditFrame;
import org.openconcerto.sql.view.list.IListe;
import org.openconcerto.sql.view.list.IListeAction;
import org.openconcerto.sql.view.list.IListeAction.IListeEvent;
import org.openconcerto.sql.view.list.RowAction;
import org.openconcerto.sql.view.list.RowAction.PredicateRowAction;
import org.openconcerto.utils.ExceptionHandler;

/**
 * Bouton « Transfert en commande fournisseur » de l'onglet « Demandes de prix »
 * de l'historique des affaires.
 *
 * Le transfert ouvre le formulaire standard d'une commande fournisseur, avec les
 * lignes de la demande de prix deja recopiees (article, designation,
 * quantite). Le prix reste a saisir : c'est une commande « a blanc », prete a
 * etre completee avec les prix recus.
 *
 * Le lien entre la demande de prix et la commande creee est enregistre dans la
 * table de transfert standard {@code TR_DEMANDE_PRIX}, creee automatiquement
 * par OpenConcerto (cf. {@link DemandePrixCommandeSQLInjector}).
 */
public final class TransfertDemandePrixAction {

    private TransfertDemandePrixAction() {
    }

    /**
     * Cree l'action a ajouter aux actions de l'element DEMANDE_PRIX.
     */
    public static RowAction create() {
        final PredicateRowAction action = new PredicateRowAction(new DemandePrixTransfertAction(), true);
        action.setPredicate(IListeEvent.getSingleSelectionPredicate());
        return action;
    }

    /**
     * Enregistre le bouton sur l'element DEMANDE_PRIX (si ce n'est pas deja
     * fait).
     * <p>
     * L'operation est idempotente : elle peut etre appelee plusieurs fois
     * (au demarrage du client et a l'ouverture de l'historique des affaires)
     * sans jamais creer deux fois le meme bouton.
     */
    public static void install() {
        try {
            final SQLElement elt = findElement();
            if (elt == null) {
                return;
            }
            for (IListeAction action : elt.getRowActions()) {
                if (action instanceof RowAction
                        && ((RowAction) action).getAction() instanceof DemandePrixTransfertAction) {
                    // le bouton est deja present
                    return;
                }
            }
            elt.getRowActions().add(create());
        } catch (RuntimeException e) {
            ExceptionHandler.handle("Impossible d'installer le bouton de transfert demande de prix -> commande fournisseur", e);
        }
    }

    /**
     * L'element DEMANDE_PRIX, ou null s'il n'existe pas.
     * <p>
     * La recherche par nom peut echouer (element non enregistre sous ce nom) :
     * on retombe alors sur un parcours de tous les elements connus.
     */
    private static SQLElement findElement() {
        final SQLElementDirectory directory = Configuration.getInstance().getDirectory();
        try {
            return directory.getElement("DEMANDE_PRIX");
        } catch (RuntimeException e) {
            // element inconnu sous ce nom : on cherche par table
            for (SQLElement elt : directory.getElements()) {
                if (elt.getTable() != null && "DEMANDE_PRIX".equalsIgnoreCase(elt.getTable().getName())) {
                    return elt;
                }
            }
            return null;
        }
    }

    /**
     * Vrai si le transfert est possible : la table des lignes de demande de prix
     * doit exister.
     */
    public static boolean isAvailable() {
        try {
            return Configuration.getInstance().getRoot().findTable("DEMANDE_PRIX_ELEMENT") != null;
        } catch (RuntimeException e) {
            return false;
        }
    }

    /**
     * L'action proprement dite (classe a part pour pouvoir la reconnaitre).
     */
    public static final class DemandePrixTransfertAction extends AbstractAction {

        public DemandePrixTransfertAction() {
            super("Transfert en commande fournisseur");
        }

        @Override
        public void actionPerformed(final ActionEvent e) {
            try {
                transferer(e);
            } catch (RuntimeException ex) {
                ExceptionHandler.handle("Impossible de transferer la demande de prix en commande fournisseur", ex);
            }
        }

        private void transferer(final ActionEvent e) {
            final List<SQLRowValues> rows = IListe.get(e).getSelectedRows();
            if (rows == null || rows.isEmpty()) {
                return;
            }
            final SQLElement eltLignes = element("DEMANDE_PRIX_ELEMENT");
            final SQLElement eltDemandePrix = element("DEMANDE_PRIX");
            if (eltDemandePrix == null || eltLignes == null) {
                return;
            }
            // ouvre le formulaire d'une commande fournisseur, pre-rempli
            final EditFrame frame = TransfertBaseSQLComponent.openTransfertFrame(rows, "COMMANDE");
            final SQLComponent comp = frame.getSQLComponent();
            if (comp instanceof CommandeSQLComponent) {
                // on recopie les lignes de la demande de prix
                final CommandeSQLComponent commande = (CommandeSQLComponent) comp;
                commande.loadItem(commande.getRowValuesTablePanel(), eltDemandePrix, rows.get(0).getID(), eltLignes);
            }
        }

        private SQLElement element(final String name) {
            try {
                return Configuration.getInstance().getDirectory().getElement(name);
            } catch (RuntimeException e) {
                return null;
            }
        }
    }
}
