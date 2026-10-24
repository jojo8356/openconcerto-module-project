package org.openconcerto.modules.project.panels;

import java.util.ArrayList;
import java.util.List;

/**
 * Un panneau de l'application (liste, onglet d'historique, panneau principal,
 * bilan, export), avec :
 * <ul>
 * <li>la table qu'il affiche ;</li>
 * <li>les colonnes qu'il lit (une colonne absente = panneau casse) ;</li>
 * <li>le chemin qui rattache une ligne a une affaire (colonne ID_AFFAIRE
 * directe, ou suite de tables parentes) ;</li>
 * <li>le filtre propre au panneau (par exemple « etat affaire = en
 * cours »).</li>
 * </ul>
 *
 * <p>
 * Toutes les clauses SQL sont deja « compilees » pour un schema donne, par
 * {@link Catalogue#build(String)}.
 * </p>
 */
public class Panel {

    /** Panneau de liste : toutes les lignes de la table sont affichees. */
    public static final String KIND_LIST = "liste";
    /** Panneau filtre par affaire : l'historique et ses onglets. */
    public static final String KIND_HISTORY = "historique";
    /** Panneau de synthese (bilan, export). */
    public static final String KIND_SUMMARY = "synthese";
    /** Contrat de structure : colonnes exigees par l'application. */
    public static final String KIND_STRUCTURE = "structure";

    /** Une table mere : <code>table</code> est jointe via <code>field</code>. */
    public static final class Link {
        final String table;
        final String field;

        public Link(String table, String field) {
            this.table = table;
            this.field = field;
        }
    }

    /** Une colonne exigee par le panneau. */
    public static final class Req {
        final String table;
        final String column;
        final String reason;

        public Req(String table, String column, String reason) {
            this.table = table;
            this.column = column;
            this.reason = reason;
        }
    }

    private final String id;
    private final String label;
    private final String group;
    private final String kind;
    private final String table;
    private final boolean optional;
    private final List<Req> required = new ArrayList<Req>();
    private final List<Link> chain = new ArrayList<Link>();
    private String extraCondition;
    private String affaireColumn;
    private String notes;
    private String fkColumn;
    private String fkTarget;

    public Panel(String id, String label, String group, String kind, String table, boolean optional) {
        this.id = id;
        this.label = label;
        this.group = group;
        this.kind = kind;
        this.table = table;
        this.optional = optional;
    }

    public String getId() {
        return this.id;
    }

    public String getLabel() {
        return this.label;
    }

    public String getGroup() {
        return this.group;
    }

    public String getKind() {
        return this.kind;
    }

    public String getTable() {
        return this.table;
    }

    public boolean isOptional() {
        return this.optional;
    }

    public List<Req> getRequired() {
        return this.required;
    }

    public List<Link> getChain() {
        return this.chain;
    }

    public String getExtraCondition() {
        return this.extraCondition;
    }

    public String getAffaireColumn() {
        return this.affaireColumn;
    }

    public String getNotes() {
        return this.notes;
    }

    public Panel requires(String table, String... columns) {
        for (String column : columns) {
            this.required.add(new Req(table, column, "colonne lue par le panneau"));
        }
        return this;
    }

    public Panel requiresReason(String table, String reason, String... columns) {
        for (String column : columns) {
            this.required.add(new Req(table, column, reason));
        }
        return this;
    }

    public Panel chain(Link... links) {
        for (Link link : links) {
            this.chain.add(link);
        }
        return this;
    }

    public Panel extra(String condition) {
        this.extraCondition = condition;
        return this;
    }

    public Panel affaireColumn(String column) {
        this.affaireColumn = column;
        return this;
    }

    public Panel notes(String notes) {
        this.notes = notes;
        return this;
    }

    /** Cle etrangere exigee : <code>column</code> de la table du panneau vers <code>targetTable</code>. */
    public Panel foreignKey(String column, String targetTable) {
        this.fkColumn = column;
        this.fkTarget = targetTable;
        return this;
    }

    public String getFkColumn() {
        return this.fkColumn;
    }

    public String getFkTarget() {
        return this.fkTarget;
    }
}
