#!/usr/bin/env python3
"""Genere les fichiers SQL « affaire » a partir des sources Java du module.

Les listes de paires de transfert et de tableaux de lignes vivent dans le code
(`AffairTransferSupport.TRANSFER_PAIRS`, `ItemAffairColumnRules.PARENTS`). Les
fichiers `sql/*.sql` sont ecrits pour etre executes a la main, quand le module
n'est pas disponible : ils doivent donc dire exactement la meme chose. Ce
programme les **genere** en lisant le code, et sait verifier qu'ils n'ont pas
derive :

    python3 tools/genere_sql_affaire.py            # (re)ecrit les fichiers
    python3 tools/genere_sql_affaire.py --check    # code retour 1 si divergence

Pourquoi deux fichiers et non un seul
-------------------------------------
Sur la base du client (mesure du 30/10), seuls **deux** tableaux de lignes
portent la colonne `ID_AFFAIRE` : `FACTURE_FOURNISSEUR_ELEMENT` et
`DEMANDE_ACHAT_ELEMENT`. Les dix autres ne l'ont pas (`colonnes` verifiees dans
`information_schema`). Un `UPDATE ... SET "ID_AFFAIRE"` sur une de ces tables
echoue, et comme tout est dans une transaction, **tout** le fichier est annule.
D'ou la separation :

* `reprise-affaire-transfert.sql` et `diagnostic-affaire-transfert.sql` :
  uniquement les **en-tetes** de documents, surs sur toute base installee par
  le module ;
* `reprise-affaire-lignes.sql` et `diagnostic-affaire-lignes.sql` :
  les tableaux de lignes, a executer **apres** avoir verifie, par la requete
  fournie en tete de fichier, que la colonne existe.
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA = "OpenConcerto42"
AFFAIR = "ID_AFFAIRE"
UNDEFINED = 1

TRANSFER_SOURCE = os.path.join(ROOT, "src/org/openconcerto/modules/project/AffairTransferSupport.java")
ITEM_SOURCE = os.path.join(ROOT, "src/org/openconcerto/modules/project/ItemAffairColumnRules.java")


# --------------------------------------------------------------------------
# Lecture du code
# --------------------------------------------------------------------------
def read(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def transfer_pairs():
    """(source, destination) de AffairTransferSupport.TRANSFER_PAIRS."""
    source = read(TRANSFER_SOURCE)
    start = source.index("TRANSFER_PAIRS")
    end = source.index(";", start)
    block = source[start:end]
    pairs = []
    for match in re.finditer(r'new\s+String\[\]\s*\{\s*"([A-Z_]+)"\s*,\s*"([A-Z_]+)"\s*\}', block):
        pairs.append((match.group(1), match.group(2)))
    if not pairs:
        raise SystemExit("aucune paire trouvee dans AffairTransferSupport")
    return pairs


def line_tables():
    """(tableau de lignes, colonne de lien, document parent)."""
    source = read(ITEM_SOURCE)
    start = source.index("PARENTS")
    end = source.index("Collections.unmodifiableMap", start)
    block = source[start:end]
    lines = []
    for match in re.finditer(r'parents\.put\(\s*"([A-Z_]+)"\s*,\s*new\s+String\[\]\s*\{\s*"([A-Z_]+)"\s*,\s*"([A-Z_]+)"\s*\}\s*\)', block):
        lines.append((match.group(1), match.group(2), match.group(3)))
    if not lines:
        raise SystemExit("aucun tableau de lignes trouve dans ItemAffairColumnRules")
    return lines


# --------------------------------------------------------------------------
# Ecriture du SQL
# --------------------------------------------------------------------------
def t(table):
    return '"%s"."%s"' % (SCHEMA, table)


def c(column):
    return '"%s"' % column


def a(table, column):
    return "%s.%s" % (t(table), c(column))


#: Colonnes de cle connues hors de la base : DEVIS porte ID_DEVIS chez le client.
#: Le generateur ne lit pas la base ; il applique la meme regle que le module
#: (ID, sinon ID_<TABLE>) avec cette table de correspondance explicite.
OWN_KEYS = {"DEVIS": "ID_DEVIS"}


def key(table):
    """Colonne d'identification utilisee dans les jointures."""
    return OWN_KEYS.get(table, "ID")


def real_key(table):
    """La ligne est un vrai document, pas la ligne « Indefini » (ID 1)."""
    return "%s > %d" % (a(table, key(table)), UNDEFINED)


def real_key_alias(alias):
    return "%s.%s > %d" % (alias, c(key_alias(alias)), UNDEFINED)


def key_alias(alias):
    return OWN_KEYS.get(alias, "ID")


def empty(table):
    return "(%s IS NULL OR %s = %d)" % (a(table, AFFAIR), a(table, AFFAIR), UNDEFINED)


def real(table):
    return "%s > %d" % (a(table, AFFAIR), UNDEFINED)


def empty_on(alias):
    """Affaire vide, ecrite avec un alias de table (jointures de lignes)."""
    return "(%s.%s IS NULL OR %s.%s = %d)" % (alias, c(AFFAIR), alias, c(AFFAIR), UNDEFINED)


ROOT_NOTE = """\\echo 'Chaque bloc est independant : une table absente n empeche pas les autres.'
\\echo ''
"""

HEADER = """-- {title}
--
-- {purpose}
--
-- Lecture seule. Aucune ecriture.
{extra}--
--   sh scripts/oc-psql.sh -f {name}
--
-- Verifie automatiquement, sans base :  sh scripts/test-affaire-cli.sh
"""


def reprise_entetes(pairs):
    out = ["""-- Reprise des affaires perdues lors des transferts de documents.
--
-- A executer quand le module n'est pas disponible, ou pour verifier a la main ce
-- que fait le menu « Aide > Reprendre les affaires des documents ». Les regles
-- sont identiques (AffairBackfillSupport) : on ne remplit QUE le vide, jamais
-- une affaire deja renseignee, et seulement quand la source porte une vraie
-- affaire (ID > 1, l'affaire « Indefini » n'en est pas une).
--
-- Ce fichier ne touche que les EN-TETES de documents : les %d transferts et les deux
-- saisies d'achat. Les tableaux de lignes sont dans
-- `sql/reprise-affaire-lignes.sql`, parce que la colonne n'existe pas sur tous.
--
-- Chaque bloc est dans SA PROPRE transaction : sur une base ou une table n'a pas
-- la colonne attendue (constate : DEVIS n'a pas de colonne ID), le bloc
-- concerne signale l'erreur et les autres sont quand meme appliques.
--
--   sh scripts/oc-psql.sh -f sql/reprise-affaire-transfert.sql
--
-- En cas de doute, remplacer un COMMIT par ROLLBACK.
--
-- Idempotent : rejouable autant de fois que voulu.
--
-- Verifie automatiquement, sans base :  sh scripts/test-affaire-cli.sh

""" % len(pairs)]

    out.append("\\echo '=== 1. Saisies d achat : SOURCE / IDSOURCE ==='\n")
    for source in ("COMMANDE", "BON_RECEPTION"):
        out.append("-- %s -> saisie d'achat\n" % source.capitalize())
        out.append("BEGIN;\n")
        out.append("\n".join([
            "UPDATE %s" % t("SAISIE_ACHAT"),
            "   SET %s = %s" % (c(AFFAIR), a(source, AFFAIR)),
            "  FROM %s" % t(source),
            " WHERE %s = '%s'" % (a("SAISIE_ACHAT", "SOURCE"), source),
            "   AND %s = %s" % (a("SAISIE_ACHAT", "IDSOURCE"), a(source, key(source))),
            "   AND %s" % empty("SAISIE_ACHAT"),
            "   AND %s" % real(source),
            "   AND %s > %d" % (a("SAISIE_ACHAT", "IDSOURCE"), UNDEFINED),
            "   AND %s AND %s;" % (real_key("SAISIE_ACHAT"), real_key(source)),
        ]) + "\n")
        out.append("COMMIT;\n")

    out.append("\\echo '=== 2. Documents : via les tables de transfert du coeur ==='\n")
    out.append(ROOT_NOTE)
    for source, destination in pairs:
        transfer = "TR_" + source
        src_key = "ID_" + source
        dest_key = "ID_" + destination
        join = "%s = %s AND %s = %s" % (a(transfer, dest_key), a(destination, key(destination)), a(transfer, src_key), a(source, key(source)))
        out.append("-- %s -> %s\n" % (source, destination))
        out.append("BEGIN;\n")
        out.append("\n".join([
            "UPDATE %s" % t(destination),
            "   SET %s = %s" % (c(AFFAIR), a(source, AFFAIR)),
            "  FROM %s" % t(transfer),
            "  JOIN %s ON %s = %s" % (t(source), a(source, key(source)), a(transfer, src_key)),
            " WHERE %s" % join,
            "   AND %s" % empty(destination),
            "   AND %s" % real(source),
            "   AND %s > %d AND %s > %d" % (a(transfer, dest_key), UNDEFINED, a(transfer, src_key), UNDEFINED),
            "   AND %s AND %s;" % (real_key(destination), real_key(source)),
        ]) + "\n")
        out.append("COMMIT;\n")

    out.append("""\\echo ''
\\echo '=== Termine. Pour les lignes, voir sql/reprise-affaire-lignes.sql ==='
\\echo 'Verifier avec sql/diagnostic-affaire-transfert.sql : les compteurs doivent etre a 0.'
""")
    return "\n".join(out)


def reprise_lignes(lines):
    out = ["""-- Reprise des affaires sur les TABLEAUX DE LIGNES (fichier a part).
--
-- Pourquoi a part : sur la base du client, seuls FACTURE_FOURNISSEUR_ELEMENT et
-- DEMANDE_ACHAT_ELEMENT portent la colonne ID_AFFAIRE ; les dix autres tableaux
-- ne l'ont pas. Un UPDATE sur une table sans la colonne fait echouer toute la
-- transaction, donc les en-tetes de `reprise-affaire-transfert.sql` seraient
-- annules en meme temps. Ici, chaque bloc est independant : executez ceux que
-- la requete ci-dessous autorise.
--
--   sh scripts/oc-psql.sh -f sql/reprise-affaire-lignes.sql
--
-- Regle identique au module : on ne remplit que le vide (NULL ou « Indefini »),
-- et seulement si le document porte une vraie affaire. Idempotent.

\\echo '=== 0. Tableaux de lignes qui portent reellement ID_AFFAIRE ==='
\\echo '(executez seulement les blocs correspondants, ci-dessous)'
select table_name
  from information_schema.columns
 where table_schema = '%s' and column_name = '%s'
   and table_name like '%%_ELEMENT'
 order by 1;
""" % (SCHEMA, AFFAIR)]

    for line, link, parent in lines:
        out.append("\n-- %s (colonne %s requise)\n" % (line, AFFAIR))
        out.append("BEGIN;\n")
        out.append("\n".join([
            "UPDATE %s" % t(line),
            "   SET %s = %s" % (c(AFFAIR), a(parent, AFFAIR)),
            "  FROM %s" % t(parent),
            " WHERE %s = %s" % (a(line, link), a(parent, key(parent))),
            "   AND %s" % empty(line),
            "   AND %s" % real(parent),
            "   AND %s > %d AND %s;" % (a(line, link), UNDEFINED, real_key(parent)),
        ]) + "\n")
        out.append("COMMIT;\n")

    out.append("""\\echo ''
\\echo '=== Termine. Chaque bloc est dans sa propre transaction : un tableau sans la'
\\echo 'colonne n''annule pas les autres. ==='
""")
    return "\n".join(out)


def diagnostic_entetes(pairs):
    """Une requete par cas, jamais de UNION.

    Une grande requete `union all` echoue en entier des qu'une table manque (cas
    reel : `DEVIS` sans colonne `ID`) et l'on perd tous les compteurs. Ici,
    chaque cas est une requete independante : psql signale celui qui echoue et
    affiche les autres.
    """
    documents = sorted({pair[0] for pair in pairs} | {pair[1] for pair in pairs} | {"SAISIE_ACHAT"})
    out = ["""-- Diagnostic : combien de documents ont perdu leur affaire en transfert ?
--
-- Lecture seule. Aucune ecriture.
--
-- Une requete par cas : si une table n'existe pas ou n'a pas la colonne
-- attendue, psql signale CE cas et affiche les autres. Aucun compteur n'est
-- perdu a cause d'une table.
--
-- Ce fichier ne regarde que les EN-TETES de documents. Les tableaux de lignes
-- sont dans `sql/diagnostic-affaire-lignes.sql`.
--
--   sh scripts/oc-psql.sh -f sql/diagnostic-affaire-transfert.sql
--
-- Les requetes reprennent exactement les regles de AffairBackfillSupport :
-- seules les affaires VIDES (NULL) ou « Indefini » (ID 1) sont comptees, et
-- seulement quand le document source porte une vraie affaire.

\\echo '=== 0. Schema utilise (adapter si votre societe porte un autre nom) ==='
select current_schema() as schema_courant;

\\echo ''
\\echo '=== 1. Saisies d achat sans affaire, alors que leur source en a une ==='
"""]

    for source in ("COMMANDE", "BON_RECEPTION"):
        out.append("\\echo '-- %s'" % source)
        out.append("\n".join([
            "select '%s' as cas, count(*) as documents" % ("SAISIE_ACHAT <- %s (SOURCE / IDSOURCE)" % source),
            "  from %s" % t("SAISIE_ACHAT"),
            "  join %s on %s = %s" % (t(source), a(source, key(source)), a("SAISIE_ACHAT", "IDSOURCE")),
            " where %s = '%s'" % (a("SAISIE_ACHAT", "SOURCE"), source),
            "   and %s" % empty("SAISIE_ACHAT"),
            "   and %s" % real(source),
            "   and %s > %d" % (a("SAISIE_ACHAT", "IDSOURCE"), UNDEFINED),
            "   and %s and %s;" % (real_key("SAISIE_ACHAT"), real_key(source)),
        ]) + "\n")

    out.append("\\echo ''\n\\echo '=== 2. Documents sans affaire, mais leur source (table TR_*) en a une ==='\n")
    for source, destination in pairs:
        transfer = "TR_" + source
        out.append("\\echo '-- %s <- %s'" % (destination, source))
        out.append("\n".join([
            "select '%s' as cas, count(*) as documents" % ("%s <- %s (via %s)" % (destination, source, transfer)),
            "  from %s" % t(destination),
            "  join %s on %s = %s" % (t(transfer), a(transfer, "ID_" + destination), a(destination, key(destination))),
            "  join %s on %s = %s" % (t(source), a(source, key(source)), a(transfer, "ID_" + source)),
            " where %s" % empty(destination),
            "   and %s" % real(source),
            "   and %s > %d and %s > %d" % (a(transfer, "ID_" + destination), UNDEFINED, a(transfer, "ID_" + source), UNDEFINED),
            "   and %s and %s;" % (real_key(destination), real_key(source)),
        ]) + "\n")

    out.append("""
\\echo ''
\\echo '=== 3. Tableaux de lignes qui portent la colonne ID_AFFAIRE ==='
\\echo '(les autres lisent l affaire de leur document : rien a reprendre chez eux)'
select table_name as table_lignes
  from information_schema.columns
 where table_schema = '%s' and column_name = '%s'
   and table_name like '%%_ELEMENT'
 order by 1;

\\echo ''
\\echo '=== 4. Les tables de transfert presentes dans cette base ==='
select table_name
  from information_schema.tables
 where table_schema = '%s' and table_name like 'TR%%'
 order by 1;
""" % (SCHEMA, AFFAIR, SCHEMA))

    out.append("\\echo ''\n\\echo '=== 5. Rappel : documents sans affaire, tous cas confondus ==='\n")
    for document in documents:
        out.append("select '%s' as document, count(*) as sans_affaire from %s where %s and %s;"
                   % (document, t(document), empty(document), real_key(document)))
    return "\n".join(out) + "\n"


def diagnostic_lignes(lines):
    out = ["""-- Diagnostic des TABLEAUX DE LIGNES (fichier a part).
--
-- Lecture seule. A executer seulement apres avoir verifie, avec la requete
-- ci-dessous, que le tableau porte bien la colonne ID_AFFAIRE.
--
--   sh scripts/oc-psql.sh -f sql/diagnostic-affaire-lignes.sql

\\echo '=== 0. Tableaux de lignes qui portent la colonne ID_AFFAIRE ==='
select table_name
  from information_schema.columns
 where table_schema = '%s' and column_name = '%s'
   and table_name like '%%_ELEMENT'
 order by 1;

\\echo ''
\\echo '=== 1. Lignes sans affaire, alors que leur document en a une ==='
""" % (SCHEMA, AFFAIR)]

    parts = []
    for line, link, parent in lines:
        parts.append("\n".join([
            "select '%s' as table_lignes, count(*) as lignes" % line,
            "  from %s" % t(line),
            "  join %s on %s = %s" % (t(parent), a(parent, key(parent)), a(line, link)),
            " where %s" % empty(line),
            "   and %s" % real(parent),
        ]))
    out.append(" union all\n".join(parts) + ";")
    return "\n".join(out) + "\n"


def attendu(pairs):
    """Un seul chiffre : ce que le menu doit annoncer avant de confirmer."""
    cases = []
    for source in ("COMMANDE", "BON_RECEPTION"):
        cases.append("\n".join([
            "  select count(*) as documents from %s" % t("SAISIE_ACHAT"),
            "    join %s on %s = %s" % (t(source), a(source, key(source)), a("SAISIE_ACHAT", "IDSOURCE")),
            "   where %s = '%s' and %s and %s" % (a("SAISIE_ACHAT", "SOURCE"), source, empty("SAISIE_ACHAT"), real(source)),
            "     and %s and %s and %s > %d" % (real_key("SAISIE_ACHAT"), real_key(source), a("SAISIE_ACHAT", "IDSOURCE"), UNDEFINED),
        ]))
    for source, destination in pairs:
        transfer = "TR_" + source
        cases.append("\n".join([
            "  select count(*) as documents from %s" % t(destination),
            "    join %s on %s = %s" % (t(transfer), a(transfer, "ID_" + destination), a(destination, key(destination))),
            "    join %s on %s = %s" % (t(source), a(source, key(source)), a(transfer, "ID_" + source)),
            "   where %s and %s" % (empty(destination), real(source)),
            "     and %s > %d and %s > %d" % (a(transfer, "ID_" + destination), UNDEFINED, a(transfer, "ID_" + source), UNDEFINED),
            "     and %s and %s" % (real_key(destination), real_key(source)),
        ]))
    return """-- Le nombre que « Aide > Reprendre les affaires des documents » doit annoncer.
--
-- Lecture seule. A executer AVANT la reprise, puis a comparer avec le nombre
-- affiche par la fenetre de confirmation. Les deux doivent etre egaux : s'ils
-- different, c'est la lecture du schema par le module qui est en cause.
--
-- Ne sont comptes que les documents dont l'affaire est VIDE (NULL ou
-- « Indefini » = 1) alors que leur source porte une VRAIE affaire (> 1).
-- Un document saisi a la main, sans document d'origine, n'est jamais compte.
--
--   sh scripts/oc-psql.sh -f sql/attendu-reprise.sql
--   docker exec -i NOM_DU_CONTENEUR sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < sql/attendu-reprise.sql
--
-- Le detail, cas par cas, est dans sql/diagnostic-affaire-transfert.sql.

select sum(documents) as total_a_reprendre from (
%s
) x;
""" % "\n  union all\n".join(cases)


def historique(pairs, lines):
    """Ce que la fenetre « Historique affaires » devrait afficher pour une affaire."""
    documents = ["DEVIS", "COMMANDE", "BON_RECEPTION", "SAISIE_ACHAT", "FACTURE_FOURNISSEUR",
                 "AVOIR_FOURNISSEUR", "DEMANDE_PRIX", "DEMANDE_ACHAT",
                 "COMMANDE_CLIENT", "BON_DE_LIVRAISON", "SAISIE_VENTE_FACTURE", "AVOIR_CLIENT"]
    counts = []
    for document in documents:
        counts.append("select '%s' as tableau, count(*) as documents from %s where %s and %s"
                      % (document, t(document), empty(document), real_key(document)))
    for line, link, parent in lines:
        counts.append("select '%s' as tableau, count(*) as documents\n  from %s d join %s l on d.%s = l.%s\n where %s and d.%s > %d and l.%s > %d"
                      % (line, t(parent), t(line), c(key(parent)), c(link), empty_on("d"),
                         c(key(parent)), UNDEFINED, c(link), UNDEFINED))

    details = []
    for document in documents:
        details.append("select '%s' as tableau, cast(%s as text) as id, cast(coalesce(\"NUMERO\", '') as text) as numero\n  from %s\n where %s and %s"
                       % (document, c(key(document)), t(document), empty(document), real_key(document)))
    for line, link, parent in lines:
        details.append("select '%s' as tableau, cast(l.\"ID\" as text) as id, cast(d.%s as text) as numero\n  from %s d join %s l on d.%s = l.%s\n where %s and d.%s > %d and l.%s > %d"
                       % (line, c(key(parent)), t(parent), t(line), c(key(parent)), c(link), empty_on("d"),
                          c(key(parent)), UNDEFINED, c(link), UNDEFINED))

    return """-- Historique affaires : ce que la fenetre DEVRAIT afficher pour une affaire.
--
-- Lecture seule. Sert a comparer, onglet par onglet, ce que montre
-- « Historique affaires » avec ce que contient la base. Si un onglet est vide
-- alors que la table correspondante a des lignes ici, c'est un defaut
-- d'affichage ou de lien, pas une absence de donnees.
--
--   sh scripts/oc-psql.sh -f sql/historique-affaire.sql
--
-- >>> Remplacez le numero d'affaire ci-dessous (une seule ligne a changer). <<<
--
-- Les deux requetes ci-dessous regroupent 24 tableaux. Si votre base n'a pas
-- l'une de ces tables, psql nomme la table en erreur : retirez la ligne
-- correspondante, le reste s'affiche quand meme. La cle utilisee est %s,
-- sauf pour DEVIS (%s), mesure sur la base du client.

drop table if exists cible;
create temp table cible as select 11874 as numero;

\\echo '=== 0. Affaire visee ==='
select a."ID" as id_affaire, a."NUMERO", a."NOM"
  from %s a
 where a."ID" = (select numero from cible);

\\echo ''
\\echo '=== 1. Nombre de documents par tableau (les onglets de la fenetre) ==='
%s
 order by 2 desc, 1;

\\echo ''
\\echo '=== 2. Detail des documents de l affaire ==='
%s
 order by 1, 3;
""" % (c("ID"), c(key("DEVIS")), t("AFFAIRE"),
       " union all\n".join(counts),
       " union all\n".join(details))


# --------------------------------------------------------------------------
def build():
    pairs = transfer_pairs()
    lines = line_tables()
    return {
        "sql/reprise-affaire-transfert.sql": reprise_entetes(pairs),
        "sql/reprise-affaire-lignes.sql": reprise_lignes(lines),
        "sql/diagnostic-affaire-transfert.sql": diagnostic_entetes(pairs),
        "sql/diagnostic-affaire-lignes.sql": diagnostic_lignes(lines),
        "sql/historique-affaire.sql": historique(pairs, lines),
        "sql/attendu-reprise.sql": attendu(pairs),
    }


def main():
    parser = argparse.ArgumentParser(description="Genere les fichiers SQL de l'affaire depuis le code.")
    parser.add_argument("--check", action="store_true", help="verifie sans ecrire (code 1 si divergence)")
    args = parser.parse_args()

    differents = []
    for name, content in build().items():
        path = os.path.join(ROOT, name)
        existing = read(path) if os.path.exists(path) else None
        if args.check:
            if existing != content:
                differents.append(name)
        else:
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(content)
            print("ecrit %s" % name)

    if args.check:
        if differents:
            print("SQL desynchronise du code : " + ", ".join(differents))
            print("corrigez avec : python3 tools/genere_sql_affaire.py")
            return 1
        print("   OK    les fichiers SQL correspondent au code (%d fichiers)" % len(build()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
