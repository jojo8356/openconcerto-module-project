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


def empty(table):
    return "(%s IS NULL OR %s = %d)" % (a(table, AFFAIR), a(table, AFFAIR), UNDEFINED)


def real(table):
    return "%s > %d" % (a(table, AFFAIR), UNDEFINED)


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
--   sh scripts/oc-psql.sh -f sql/reprise-affaire-transfert.sql
--
-- Tout est dans une transaction : en cas de doute, remplacer COMMIT par
-- ROLLBACK a la fin.
--
-- Idempotent : rejouable autant de fois que voulu.
--
-- Verifie automatiquement, sans base :  sh scripts/test-affaire-cli.sh

BEGIN;
""" % len(pairs)]

    out.append("\\echo '=== 1. Saisies d achat : SOURCE / IDSOURCE ==='\n")
    for source in ("COMMANDE", "BON_RECEPTION"):
        out.append("-- %s -> saisie d'achat\n" % source.capitalize())
        out.append("\n".join([
            "UPDATE %s" % t("SAISIE_ACHAT"),
            "   SET %s = %s" % (c(AFFAIR), a(source, AFFAIR)),
            "  FROM %s" % t(source),
            " WHERE %s = '%s'" % (a("SAISIE_ACHAT", "SOURCE"), source),
            "   AND %s = %s" % (a("SAISIE_ACHAT", "IDSOURCE"), a(source, "ID")),
            "   AND %s" % empty("SAISIE_ACHAT"),
            "   AND %s;" % real(source),
        ]) + "\n")

    out.append("\\echo '=== 2. Documents : via les tables de transfert du coeur ==='\n")
    for source, destination in pairs:
        transfer = "TR_" + source
        src_key = "ID_" + source
        dest_key = "ID_" + destination
        join = "%s = %s AND %s = %s" % (a(transfer, dest_key), a(destination, "ID"), a(transfer, src_key), a(source, "ID"))
        out.append("-- %s -> %s\n" % (source, destination))
        out.append("\n".join([
            "UPDATE %s" % t(destination),
            "   SET %s = %s" % (c(AFFAIR), a(source, AFFAIR)),
            "  FROM %s" % t(transfer),
            "  JOIN %s ON %s = %s" % (t(source), a(source, "ID"), a(transfer, src_key)),
            " WHERE %s" % join,
            "   AND %s" % empty(destination),
            "   AND %s;" % real(source),
        ]) + "\n")

    out.append("""COMMIT;

\\echo ''
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
            " WHERE %s = %s" % (a(line, link), a(parent, "ID")),
            "   AND %s" % empty(line),
            "   AND %s;" % real(parent),
        ]) + "\n")
        out.append("COMMIT;\n")

    out.append("""\\echo ''
\\echo '=== Termine. Chaque bloc est dans sa propre transaction : un tableau sans la'
\\echo 'colonne n''annule pas les autres. ==='
""")
    return "\n".join(out)


def diagnostic_entetes(pairs):
    out = ["""-- Diagnostic : combien de documents ont perdu leur affaire en transfert ?
--
-- Lecture seule. Aucune ecriture.
--
-- Ce fichier ne regarde que les EN-TETES de documents : il est donc sur sur
-- toute base installee par le module. Les tableaux de lignes sont dans
-- `sql/diagnostic-affaire-lignes.sql`.
--
--   sh scripts/oc-psql.sh -f sql/diagnostic-affaire-transfert.sql
--
-- Les requetes reprennent exactement les regles de AffairBackfillSupport :
-- seules les affaires VIDES (NULL) ou « Indefini » (ID 1) sont comptees, et
-- seulement quand le document source porte une vraie affaire.
--
-- Verifie automatiquement, sans base :  sh scripts/test-affaire-cli.sh

\\echo '=== 0. Schema utilise (adapter si votre societe porte un autre nom) ==='
select current_schema() as schema_courant;
"""]

    out.append("\\echo ''\n\\echo '=== 1. Saisies d achat sans affaire, alors que leur source en a une ==='")
    parts = []
    for source in ("COMMANDE", "BON_RECEPTION"):
        parts.append("\n".join([
            "select '%s' as source, count(*) as documents" % source,
            "  from %s" % t("SAISIE_ACHAT"),
            "  join %s on %s = %s" % (t(source), a(source, "ID"), a("SAISIE_ACHAT", "IDSOURCE")),
            " where %s = '%s'" % (a("SAISIE_ACHAT", "SOURCE"), source),
            "   and %s" % empty("SAISIE_ACHAT"),
            "   and %s" % real(source),
        ]))
    out.append(" union all\n".join(parts) + ";")

    out.append("\n\\echo ''\n\\echo '=== 2. Documents sans affaire, mais leur source (table TR_*) en a une ==='")
    parts = []
    for source, destination in pairs:
        transfer = "TR_" + source
        parts.append("\n".join([
            "select '%s <- %s' as transfert, count(*) as documents" % (destination, source),
            "  from %s" % t(destination),
            "  join %s on %s = %s" % (t(transfer), a(transfer, "ID_" + destination), a(destination, "ID")),
            "  join %s on %s = %s" % (t(source), a(source, "ID"), a(transfer, "ID_" + source)),
            " where %s" % empty(destination),
            "   and %s" % real(source),
        ]))
    out.append(" union all\n".join(parts) + ";")

    out.append("""
\\echo ''
\\echo '=== 3. Tableaux de lignes qui portent la colonne ID_AFFAIRE ==='
\\echo '(les autres lisent l''affaire de leur document : rien a reprendre chez eux)'
select table_name as table_lignes
  from information_schema.columns
 where table_schema = '%s' and column_name = '%s'
   and table_name like '%%_ELEMENT'
 order by 1;
""" % (SCHEMA, AFFAIR))

    out.append("""
\\echo ''
\\echo '=== 4. Les tables de transfert presentes dans cette base ==='
select table_name
  from information_schema.tables
 where table_schema = '%s' and table_name like 'TR%%'
 order by 1;
""" % SCHEMA)

    out.append("\\echo ''\n\\echo '=== 5. Rappel : documents sans affaire, tous cas confondus ==='")
    documents = sorted({pair[0] for pair in pairs} | {pair[1] for pair in pairs} | {"SAISIE_ACHAT"})
    parts = []
    for document in documents:
        parts.append("select '%s' as document, count(*) as sans_affaire from %s where %s" % (document, t(document), empty(document)))
    out.append(" union all\n".join(parts) + "\n order by 2 desc;")
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
            "  join %s on %s = %s" % (t(parent), a(parent, "ID"), a(line, link)),
            " where %s" % empty(line),
            "   and %s" % real(parent),
        ]))
    out.append(" union all\n".join(parts) + ";")
    return "\n".join(out) + "\n"


# --------------------------------------------------------------------------
def build():
    pairs = transfer_pairs()
    lines = line_tables()
    return {
        "sql/reprise-affaire-transfert.sql": reprise_entetes(pairs),
        "sql/reprise-affaire-lignes.sql": reprise_lignes(lines),
        "sql/diagnostic-affaire-transfert.sql": diagnostic_entetes(pairs),
        "sql/diagnostic-affaire-lignes.sql": diagnostic_lignes(lines),
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
