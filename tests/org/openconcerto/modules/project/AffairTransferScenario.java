package org.openconcerto.modules.project;

import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

import org.openconcerto.sql.model.DBRoot;
import org.openconcerto.sql.model.SQLField;
import org.openconcerto.sql.model.SQLInjector;
import org.openconcerto.sql.model.SQLRowValues;
import org.openconcerto.sql.model.SQLTable;

/**
 * Scenario executable en ligne de commande : « je mets l'affaire sur une
 * commande fournisseur, je la transfere en facture, et l'affaire disparait ».
 *
 * <p>
 * Ce programme ne se contente pas de tester une fonction : il <b>reproduit le
 * bug</b> avec les memes regles que le c&oelig;ur d'OpenConcerto (injecteur qui
 * declare explicitement ses champs, comme les 26 injecteurs de 1.7.6), puis
 * applique le correctif du module et rejoue le meme transfert.
 * </p>
 *
 * <p>
 * Aucune base de donnees, aucune interface : uniquement les classes de regles du
 * module et des doublures de test. Sortie lisible, code retour 0 si tout est
 * conforme.
 * </p>
 *
 * <pre>
 *   sh scripts/test-affaire-cli.sh
 * </pre>
 */
public final class AffairTransferScenario {

    private static int passed = 0;
    private static int failed = 0;

    /** Paires enregistrees « comme par le c&oelig;ur » (registre du faux SQLInjector). */
    private static final Set<String> registered = new LinkedHashSet<String>();

    public static void main(final String[] args) {
        final DBRoot root = new DBRoot();
        final SQLTable commande = table(root, "COMMANDE", "ID", "ID_AFFAIRE", "NUMERO", "ID_FOURNISSEUR", "NOM", "INFOS");
        final SQLTable saisie = table(root, "SAISIE_ACHAT", "ID", "ID_AFFAIRE", "ID_FOURNISSEUR", "NOM", "NUMERO_COMMANDE", "IDSOURCE", "SOURCE");
        final SQLTable facture = table(root, "FACTURE_FOURNISSEUR", "ID", "ID_AFFAIRE", "ID_FOURNISSEUR", "NOM", "INFOS");
        final SQLTable bonReception = table(root, "BON_RECEPTION", "ID", "ID_AFFAIRE", "ID_FOURNISSEUR", "NOM");

        final AffairLinkSupport.Schema schema = schemaOf(root);

        System.out.println("=== Affaire et transfert : commande fournisseur -> facture ===");
        System.out.println("Regles du module : AffairTransferSupport (" + AffairTransferSupport.TRANSFER_PAIRS.size() + " paires declarees)");
        System.out.println();

        // ---------------------------------------------------------------- 1
        final SQLRowValues commandeRow = new SQLRowValues(commande).put("ID", Integer.valueOf(251)).put("NUMERO", "11870-PO-007-Avt1").put("NOM", "LYONDELL")
                .put("ID_AFFAIRE", Integer.valueOf(11870));
        System.out.println("1. Commande fournisseur 251 « 11870-PO-007-Avt1 » : affaire = " + commandeRow.getObject("ID_AFFAIRE"));

        // ---------------------------------------------------------------- 2
        // Injecteurs du coeur : champs declares un par un, ID_AFFAIRE absent.
        newCoreInjector(commande, saisie);
        newCoreInjector(commande, facture);
        newCoreInjector(commande, bonReception);

        System.out.println();
        System.out.println("2. Transfert AVANT correctif (regles du coeur 1.7.6)");
        final SQLInjector before = SQLInjector.getInjector(commande, saisie);
        System.out.println("   injecteur COMMANDE -> SAISIE_ACHAT : champs copies " + names(before.getFrom()));
        final SQLRowValues factureAvant = before.createRowValuesFrom(commandeRow);
        System.out.println("   facture creee : affaire = " + show(factureAvant.getObject("ID_AFFAIRE")) + "   <-- le bug");

        check("avant correctif, le coeur perd l'affaire", null, factureAvant.getObject("ID_AFFAIRE"));
        check("avant correctif, les autres champs sont bien copies", "LYONDELL", factureAvant.getObject("NOM"));

        // ---------------------------------------------------------------- 3
        System.out.println();
        System.out.println("3. Application du correctif du module");
        final AffairTransferSupport.Report report = AffairTransferSupport.install(schema, new FakeAccess(root));
        System.out.println("   " + report.getSummary());
        // Trois injecteurs sont enregistres dans ce schema (commande vers saisie
        // d'achat, facture et bon de reception) : les trois doivent etre corriges.
        check("trois paires corrigees", Integer.valueOf(3), Integer.valueOf(report.getAdded().size()));
        check("aucun echec", Boolean.TRUE, Boolean.valueOf(report.isComplete()));

        // ---------------------------------------------------------------- 4
        System.out.println();
        System.out.println("4. Transfert APRES correctif (meme commande, meme injecteur)");
        final SQLInjector after = SQLInjector.getInjector(commande, saisie);
        System.out.println("   injecteur COMMANDE -> SAISIE_ACHAT : champs copies " + names(after.getFrom()));
        final SQLRowValues factureApres = after.createRowValuesFrom(commandeRow);
        System.out.println("   facture creee : affaire = " + show(factureApres.getObject("ID_AFFAIRE")) + "   <-- corrige");
        check("apres correctif, l'affaire est transportee", Integer.valueOf(11870), factureApres.getObject("ID_AFFAIRE"));
        check("les autres champs sont intacts", "LYONDELL", factureApres.getObject("NOM"));

        // ---------------------------------------------------------------- 5
        System.out.println();
        System.out.println("5. Robustesse");
        // deuxieme application : aucun doublon de mapping
        final int champsAvant = after.getFrom().size();
        final AffairTransferSupport.Report again = AffairTransferSupport.install(schema, new FakeAccess(root));
        check("seconde application idempotente", Integer.valueOf(0), Integer.valueOf(again.getAdded().size()));
        check("aucun champ duplique", Integer.valueOf(champsAvant), Integer.valueOf(SQLInjector.getInjector(commande, saisie).getFrom().size()));
        check("paires deja en place signalees", Integer.valueOf(3), Integer.valueOf(again.getAlreadyMapped().size()));

        // commande sans affaire : rien n'est invente
        final SQLRowValues sansAffaire = new SQLRowValues(commande).put("ID", Integer.valueOf(252)).put("NUMERO", "SANS-AFFAIRE").put("NOM", "X");
        final SQLRowValues factureSansAffaire = SQLInjector.getInjector(commande, saisie).createRowValuesFrom(sansAffaire);
        System.out.println("   commande sans affaire -> facture : affaire = " + show(factureSansAffaire.getObject("ID_AFFAIRE")));
        check("aucune affaire inventee", null, factureSansAffaire.getObject("ID_AFFAIRE"));

        // affaire « Indefini » (1) : transportee telle quelle, pas inventee
        final SQLRowValues indefinie = new SQLRowValues(commande).put("ID", Integer.valueOf(253)).put("NUMERO", "INDEF").put("NOM", "Y").put("ID_AFFAIRE", Integer.valueOf(1));
        final SQLRowValues factureIndef = SQLInjector.getInjector(commande, saisie).createRowValuesFrom(indefinie);
        check("affaire indefinie transportee sans erreur", Integer.valueOf(1), factureIndef.getObject("ID_AFFAIRE"));

        // une paire dont une table est absente du schema n'est pas inventee
        check("paire hors schema signalee, pas inventee", Boolean.TRUE,
                Boolean.valueOf(report.getNoColumn().contains("DEVIS -> COMMANDE_CLIENT")));
        check("aucune paire inventee", Boolean.FALSE,
                Boolean.valueOf(report.getAdded().contains("DEVIS -> COMMANDE_CLIENT")));

        // le correctif n'est pas limite a une paire : les deux autres transferts
        // de la commande transportent aussi l'affaire
        for (final String[] pair : new String[][] { { "COMMANDE", "FACTURE_FOURNISSEUR" }, { "COMMANDE", "BON_RECEPTION" } }) {
            final SQLRowValues copie = SQLInjector.getInjector(root.getTable(pair[0]), root.getTable(pair[1])).createRowValuesFrom(commandeRow);
            check("affaire transportee par " + pair[0] + " -> " + pair[1], Integer.valueOf(11870), copie.getObject("ID_AFFAIRE"));
        }

        // ---------------------------------------------------------------- bilan
        System.out.println();
        System.out.println("Controles : " + (passed + failed) + " | echecs : " + failed);
        if (failed > 0) {
            System.exit(1);
        }
    }

    /** Injecteur « du coeur » : quelques champs declares, ID_AFFAIRE absent. */
    private static void newCoreInjector(final SQLTable source, final SQLTable destination) {
        final SQLInjector injector = new SQLInjector(source, destination, true) {
        };
        if (source.contains("ID_FOURNISSEUR") && destination.contains("ID_FOURNISSEUR")) {
            map(injector, source, destination, "ID_FOURNISSEUR");
        }
        map(injector, source, destination, "NOM");
        if (destination.contains("NUMERO_COMMANDE")) {
            map(injector, source, destination, "NUMERO");
        }
        registered.add(source.getName() + "->" + destination.getName());
    }

    private static void map(final SQLInjector injector, final SQLTable source, final SQLTable destination, final String field) {
        if (!source.contains(field) || !destination.contains(field)) {
            return;
        }
        final SQLField from = source.getField(field);
        final SQLField to = destination.getField(field);
        // map() est protected dans les deux implementations : on passe par les
        // listes, comme le module le fait pour son propre champ.
        injector.getFrom().add(from);
        injector.getTo().add(to);
    }

    /** Acces aux injecteurs, adosse au registre des doublures de test. */
    private static final class FakeAccess implements AffairTransferSupport.InjectorAccess {

        private final DBRoot root;

        FakeAccess(final DBRoot root) {
            this.root = root;
        }

        @Override
        public boolean isRegistered(final String src, final String dest) {
            return registered.contains(src + "->" + dest);
        }

        @Override
        public boolean isMapped(final String src, final String dest) {
            final SQLInjector injector = SQLInjector.getInjector(this.root.getTable(src), this.root.getTable(dest));
            return injector.getFrom().contains(this.root.getTable(src).getField(AffairLinkSupport.AFFAIR_FIELD));
        }

        @Override
        public boolean addMapping(final String src, final String dest) {
            final SQLInjector injector = SQLInjector.getInjector(this.root.getTable(src), this.root.getTable(dest));
            final SQLField from = this.root.getTable(src).getField(AffairLinkSupport.AFFAIR_FIELD);
            final SQLField to = this.root.getTable(dest).getField(AffairLinkSupport.AFFAIR_FIELD);
            if (injector.getFrom().contains(from)) {
                return false;
            }
            injector.getFrom().add(from);
            injector.getTo().add(to);
            return true;
        }
    }

    private static SQLTable table(final DBRoot root, final String name, final String... fields) {
        final SQLTable table = new SQLTable(root, name);
        for (final String field : fields) {
            table.addField(field);
        }
        root.addTable(table);
        return table;
    }

    /** Schema vu par les regles : les tables reellement construites ci-dessus. */
    private static AffairLinkSupport.Schema schemaOf(final DBRoot root) {
        final Set<String> names = new LinkedHashSet<String>();
        final Map<String, Set<String>> fields = new HashMap<String, Set<String>>();
        for (final String name : new String[] { "COMMANDE", "SAISIE_ACHAT", "FACTURE_FOURNISSEUR", "BON_RECEPTION" }) {
            names.add(name);
            fields.put(name, new HashSet<String>(root.getTable(name).getFieldsName()));
        }
        return AffairLinkSupport.schemaOf(names, fields);
    }

    private static String names(final java.util.List<SQLField> fields) {
        final StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < fields.size(); i++) {
            if (i > 0) {
                sb.append(", ");
            }
            sb.append(fields.get(i).getName());
        }
        return sb.append(']').toString();
    }

    private static String show(final Object value) {
        return value == null ? "<vide>" : value.toString();
    }

    private static void check(final String label, final Object expected, final Object actual) {
        final boolean ok = expected == null ? actual == null : expected.equals(actual);
        System.out.println((ok ? "   OK   " : "   ECHEC") + " " + label + (ok ? "" : " : attendu <" + expected + ">, obtenu <" + actual + ">"));
        if (ok) {
            passed++;
        } else {
            failed++;
        }
    }

    private AffairTransferScenario() {
    }
}
