#!/usr/bin/env python3
"""Controle de portee des requetes SQL produites par le module.

PostgreSQL refuse deux choses que SQLite accepte, et qui ont fait echouer les
19 comptages de la reprise sur la base du client :

1. **une reference a une table dans un ON avant qu'elle soit jointe** :

       ... INNER JOIN "TR_COMMANDE" ON "TR_COMMANDE"."ID_SAISIE_ACHAT" = "SAISIE_ACHAT"."ID"
                                       AND "TR_COMMANDE"."ID_COMMANDE" = "COMMANDE"."ID"
           INNER JOIN "COMMANDE" ON "TR_COMMANDE"."ID_COMMANDE" = "COMMANDE"."ID"

   PostgreSQL repond « invalid reference to FROM-clause entry for table
   "commande" ». Les 17 comptages de transfert echouaient donc tous, le menu
   annoncait 0 et concluait « rien a reprendre ».

2. **une colonne non qualifiee** des que deux tables jointes ont une colonne du
   meme nom :

       ... WHERE "SOURCE" = 'COMMANDE'

   PostgreSQL repond « column reference "SOURCE" is ambiguous » (mesure faite
   sur PostgreSQL 16 : c'est exactement ce que repond la sonde).

Ce fichier verifie les deux regles sur les requetes du plan, sans base :

    python3 tests/cli/sql_scope.py --selftest        # les 2 pieges + 2 cas sains
    python3 tests/cli/sql_scope.py plan.txt          # un plan produit par le module
"""
import re
import sys

# Une reference entre guillemets : "T", "S"."T" ou "S"."T"."C".
IDENT = r'"(?:[A-Za-z0-9_]+"\.")*[A-Za-z0-9_]+"'
IDENT_RE = re.compile(IDENT)
LITERAL_RE = re.compile(r"'[^']*'")


def identifiers(chain):
    """Les morceaux d'une reference : '"S"."T"."C"' -> ['S', 'T', 'C']."""
    return re.findall(r"[A-Za-z0-9_]+", chain)


def table_in_from(chain):
    """Nom de table d'une reference de FROM/JOIN : le dernier morceau."""
    parts = identifiers(chain)
    return parts[-1] if parts else None


def analyse_condition(condition):
    """(tables citees, colonnes non qualifiees) d'un ON ou d'un WHERE."""
    condition = LITERAL_RE.sub("''", condition)
    tables = set()
    unqualified = []
    for chain in IDENT_RE.findall(condition):
        parts = identifiers(chain)
        if len(parts) == 1:
            unqualified.append(parts[0])
        else:
            tables.add(parts[-2])
    return tables, unqualified


def check_query(sql):
    """Liste des problemes de portee d'une requete de comptage."""
    problems = []
    parts = re.split(r"\s+(INNER JOIN|JOIN|WHERE)\s+", sql)
    if len(parts) < 3:
        return problems

    # Premiere partie : « SELECT count(*) FROM <table> »
    tables, unqualified = analyse_condition(parts[0])
    scope = set()
    froms = IDENT_RE.findall(parts[0])
    if froms:
        scope.add(table_in_from(froms[-1]))
    for name in unqualified:
        problems.append("table non lisible dans le FROM : %s" % name)

    index = 1
    while index + 1 < len(parts):
        keyword = parts[index]
        clause = parts[index + 1]
        index += 2
        if keyword == "WHERE":
            cited, unqualified = analyse_condition(clause)
            for table in sorted(cited - scope):
                problems.append("WHERE cite la table %s, non jointe" % table)
            for column in unqualified:
                problems.append("colonne %s non qualifiee dans le WHERE" % column)
            continue
        # INNER JOIN <table> ON <condition>
        on_split = re.split(r"\s+ON\s+", clause, 1)
        joined = table_in_from(on_split[0])
        condition = on_split[1] if len(on_split) > 1 else ""
        cited, unqualified = analyse_condition(condition)
        for table in sorted(cited - scope - {joined}):
            problems.append("le ON de %s cite %s, table pas encore jointe" % (joined, table))
        for column in unqualified:
            problems.append("colonne %s non qualifiee dans le ON de %s" % (column, joined))
        scope.add(joined)
    return problems


def check_plan(counts):
    """Verifie toutes les requetes d'un plan. Retourne (controles, problemes)."""
    problems = []
    for description, sql in counts:
        for problem in check_query(sql):
            problems.append("%s : %s" % (description, problem))
    return len(counts), problems


# --------------------------------------------------------------------------
# Cas de reference : les deux requetes cassees, et leurs equivalents corrects
# --------------------------------------------------------------------------
T = '"OpenConcerto"."OpenConcerto42"'

CASE_BROKEN_SCOPE = (
    'SELECT count(*) FROM %(t)s."SAISIE_ACHAT" INNER JOIN %(t)s."TR_COMMANDE" ON %(t)s."TR_COMMANDE"."ID_SAISIE_ACHAT" = %(t)s."SAISIE_ACHAT"."ID"'
    ' AND %(t)s."TR_COMMANDE"."ID_COMMANDE" = %(t)s."COMMANDE"."ID"'
    ' INNER JOIN %(t)s."COMMANDE" ON %(t)s."TR_COMMANDE"."ID_COMMANDE" = %(t)s."COMMANDE"."ID"'
    ' WHERE (%(t)s."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR %(t)s."SAISIE_ACHAT"."ID_AFFAIRE" = 1)' % {"t": T}
)

CASE_FIXED_SCOPE = (
    'SELECT count(*) FROM %(t)s."SAISIE_ACHAT" INNER JOIN %(t)s."TR_COMMANDE" ON %(t)s."TR_COMMANDE"."ID_SAISIE_ACHAT" = %(t)s."SAISIE_ACHAT"."ID"'
    ' INNER JOIN %(t)s."COMMANDE" ON %(t)s."TR_COMMANDE"."ID_COMMANDE" = %(t)s."COMMANDE"."ID"'
    ' WHERE (%(t)s."SAISIE_ACHAT"."ID_AFFAIRE" IS NULL OR %(t)s."SAISIE_ACHAT"."ID_AFFAIRE" = 1)' % {"t": T}
)

CASE_BROKEN_COLUMN = (
    'SELECT count(*) FROM %(t)s."SAISIE_ACHAT" INNER JOIN %(t)s."COMMANDE" ON %(t)s."SAISIE_ACHAT"."IDSOURCE" = %(t)s."COMMANDE"."ID"'
    " WHERE \"SOURCE\" = 'COMMANDE' AND %(t)s." % {"t": T} + '"SAISIE_ACHAT"."ID" > 1'
)

CASE_FIXED_COLUMN = (
    'SELECT count(*) FROM %(t)s."SAISIE_ACHAT" INNER JOIN %(t)s."COMMANDE" ON %(t)s."SAISIE_ACHAT"."IDSOURCE" = %(t)s."COMMANDE"."ID"'
    ' WHERE %(t)s."SAISIE_ACHAT"."SOURCE" = \'COMMANDE\' AND %(t)s."SAISIE_ACHAT"."ID" > 1' % {"t": T}
)


def selftest():
    passed = 0
    failed = 0

    def check(label, expected, actual):
        nonlocal passed, failed
        if expected == actual:
            passed += 1
            print("   OK    %s" % label)
        else:
            failed += 1
            print("   ECHEC %s : attendu <%s>, obtenu <%s>" % (label, expected, actual))

    print("=== Portee des requetes SQL du module (sans base) ===")

    problems = check_query(CASE_BROKEN_SCOPE)
    print("   requete 1 (ON avant la jointure) : %s" % (problems or "aucun probleme"))
    check("la reference avant jointure est detectee", 1, len(problems))
    check("le probleme nomme la table", True, any("COMMANDE" in p for p in problems))

    problems = check_query(CASE_FIXED_SCOPE)
    print("   requete 1 corrigee : %s" % (problems or "aucun probleme"))
    check("la requete corrigee est acceptee", [], problems)

    problems = check_query(CASE_BROKEN_COLUMN)
    print("   requete 2 (SOURCE non qualifiee) : %s" % (problems or "aucun probleme"))
    check("la colonne non qualifiee est detectee", 1, len(problems))
    check("le probleme nomme la colonne", True, any("SOURCE" in p for p in problems))

    problems = check_query(CASE_FIXED_COLUMN)
    print("   requete 2 corrigee : %s" % (problems or "aucun probleme"))
    check("la colonne qualifiee est acceptee", [], problems)

    check("une colonne qualifiee n'est pas signalee", [], check_query(
        'SELECT count(*) FROM "S"."T" WHERE "S"."T"."ID_AFFAIRE" IS NULL'))
    check("une table jointe peut etre citee dans le WHERE", [], check_query(
        'SELECT count(*) FROM "S"."T" INNER JOIN "S"."C" ON "S"."T"."IDSOURCE" = "S"."C"."ID"'
        ' WHERE "S"."C"."ID_AFFAIRE" > 1'))

    print()
    print("Controles : %d | echecs : %d" % (passed, failed))
    return 1 if failed else 0


def main(argv):
    if len(argv) > 1 and argv[1] == "--selftest":
        return selftest()
    if len(argv) < 2:
        print(__doc__)
        return 2
    counts = []
    with open(argv[1], "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if line.startswith("COUNT|"):
                parts = line.split("|")
                if len(parts) == 3:
                    counts.append((parts[1], parts[2]))
    total, problems = check_plan(counts)
    print("=== Portee des %d requetes de comptage du plan ===" % total)
    for problem in problems:
        print("   ECHEC %s" % problem)
    print("Controles : %d | problemes : %d" % (total, len(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
