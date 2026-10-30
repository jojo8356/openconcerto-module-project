#!/usr/bin/env python3
"""Test bout-en-bout de la reprise des affaires, SANS OpenConcerto.

Le SQL execute ici est **exactement** celui que le module produit : il est
ecrit par `AffairBackfillSqlDump` (qui appelle `AffairBackfillSupport.plan()`),
puis execute dans une base SQLite jetable. Aucun serveur, aucune interface,
aucune donnee reelle : on peut donc le lancer autant de fois que voulu.

Ce que le test verifie
----------------------
1. les documents transferes sans affaire recoivent l'affaire de leur source
   (table de transfert `TR_*` ou `SOURCE`/`IDSOURCE`) ;
2. une affaire **deja renseignee n'est jamais ecrasee** ;
3. une source sans affaire, ou avec l'affaire « Indefini » (ID 1), ne produit
   aucune ecriture ;
4. les lignes reprennent l'affaire de leur document ;
5. le plan est **idempotent** : une seconde execution ne change plus rien ;
6. les compteurs du diagnostic tombent bien a zero apres la reprise.

Usage
-----
    sh scripts/test-affaire-cli.sh
    # ou, en deux temps :
    java -cp build/test-classes org.openconcerto.modules.project.AffairBackfillSqlDump > /tmp/plan.txt
    python3 tests/cli/test-affaire-transfert.py /tmp/plan.txt
"""

import os
import sqlite3
import subprocess
import sys

SCHEMA = "OpenConcerto42"

passed = 0
failed = 0
failures = []


# --------------------------------------------------------------------------
# Verification elementaire
# --------------------------------------------------------------------------
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sql_scope  # noqa: E402  (controle de portee des requetes)


# --------------------------------------------------------------------------
# Verification elementaire
# --------------------------------------------------------------------------
def check(label, expected, actual):
    global passed, failed
    if expected == actual:
        passed += 1
        print("   OK    %s" % label)
    else:
        failed += 1
        message = "%s : attendu <%s>, obtenu <%s>" % (label, expected, actual)
        failures.append(message)
        print("   ECHEC %s" % message)


# --------------------------------------------------------------------------
# Plan produit par le module
# --------------------------------------------------------------------------
def load_plan(path):
    tables = []
    counts = []
    updates = []
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("|")
            if parts[0] == "TABLE" and len(parts) == 3:
                tables.append((parts[1], parts[2].split(",")))
            elif parts[0] == "COUNT" and len(parts) == 3:
                counts.append((parts[1], parts[2]))
            elif parts[0] == "UPDATE" and len(parts) == 3:
                updates.append((parts[1], parts[2]))
    return tables, counts, updates


def build_database(tables):
    db = sqlite3.connect(":memory:")
    db.execute("ATTACH ':memory:' AS %s" % SCHEMA)
    for name, columns in tables:
        ddl = ", ".join('"%s" integer' % column for column in columns)
        db.execute('CREATE TABLE "%s"."%s" (%s)' % (SCHEMA, name, ddl))
    return db


# --------------------------------------------------------------------------
# Jeu de donnees : il reproduit la base du client
# --------------------------------------------------------------------------
def insert(db, table, **values):
    columns = ", ".join('"%s"' % key for key in values)
    marks = ", ".join("?" for _ in values)
    db.execute('INSERT INTO "%s"."%s" (%s) VALUES (%s)' % (SCHEMA, table, columns, marks),
               list(values.values()))


def fixture(db):
    """Scenarios presents dans la base."""
    # Affaires
    insert(db, "COMMANDE", ID=251, ID_AFFAIRE=11870, NUMERO="11870-PO-007-Avt1", ID_FOURNISSEUR=12)
    insert(db, "COMMANDE", ID=252, ID_AFFAIRE=1, NUMERO="SANS-AFFAIRE", ID_FOURNISSEUR=13)
    insert(db, "COMMANDE", ID=253, ID_AFFAIRE=None, NUMERO="AFFAIRE-NULLE", ID_FOURNISSEUR=14)
    insert(db, "BON_RECEPTION", ID=400, ID_AFFAIRE=300, ID_FOURNISSEUR=12)

    # F1 – facture fournisseur nee de la commande 251 (affaire 11870) : a reparer
    insert(db, "FACTURE_FOURNISSEUR", ID=900, ID_AFFAIRE=None, ID_FOURNISSEUR=12)
    insert(db, "TR_COMMANDE", ID=1, ID_COMMANDE=251, ID_FACTURE_FOURNISSEUR=900)

    # F2 – facture deja rattachee a une AUTRE affaire : ne doit jamais bouger
    insert(db, "FACTURE_FOURNISSEUR", ID=901, ID_AFFAIRE=555, ID_FOURNISSEUR=12)
    insert(db, "TR_COMMANDE", ID=2, ID_COMMANDE=251, ID_FACTURE_FOURNISSEUR=901)

    # F3 – facture nee du bon de reception 400 (affaire 300) : a reparer
    insert(db, "FACTURE_FOURNISSEUR", ID=902, ID_AFFAIRE=1, ID_FOURNISSEUR=12)
    insert(db, "TR_BON_RECEPTION", ID=3, ID_BON_RECEPTION=400, ID_FACTURE_FOURNISSEUR=902)

    # F4 – saisie d'achat nee de la commande 251 (SOURCE / IDSOURCE) : a reparer
    insert(db, "SAISIE_ACHAT", ID=700, ID_AFFAIRE=None, SOURCE="COMMANDE", IDSOURCE=251, ID_FOURNISSEUR=12)
    # F5 – saisie d'achat nee de la commande 252 (affaire indefinie) : rien a faire
    insert(db, "SAISIE_ACHAT", ID=701, ID_AFFAIRE=None, SOURCE="COMMANDE", IDSOURCE=252, ID_FOURNISSEUR=13)
    # F6 – saisie d'achat saisie a la main, sans source : rien a faire
    insert(db, "SAISIE_ACHAT", ID=702, ID_AFFAIRE=None, SOURCE=None, IDSOURCE=None, ID_FOURNISSEUR=13)

    # F7 – lignes de la commande 251, sans affaire de ligne : a reparer
    insert(db, "COMMANDE_ELEMENT", ID=5000, ID_AFFAIRE=None, ID_COMMANDE=251)
    insert(db, "COMMANDE_ELEMENT", ID=5001, ID_AFFAIRE=None, ID_COMMANDE=251)
    # ligne avec une affaire propre : ne doit pas bouger
    insert(db, "COMMANDE_ELEMENT", ID=5002, ID_AFFAIRE=777, ID_COMMANDE=251)

    # F8 – facture sans aucun lien de transfert : doit rester intacte
    insert(db, "FACTURE_FOURNISSEUR", ID=903, ID_AFFAIRE=None, ID_FOURNISSEUR=12)


def value(db, table, row_id):
    row = db.execute('SELECT "ID_AFFAIRE" FROM "%s"."%s" WHERE "ID" = ?' % (SCHEMA, table), (row_id,)).fetchone()
    return None if row is None else row[0]


def total_counts(db, counts):
    return {description: db.execute(sql).fetchone()[0] for description, sql in counts}


# --------------------------------------------------------------------------
# Scenario
# --------------------------------------------------------------------------
def main():
    plan_path = sys.argv[1] if len(sys.argv) > 1 else None
    if plan_path is None or not os.path.exists(plan_path):
        print("usage : test-affaire-transfert.py <plan.sql>")
        print("        (le plan est produit par AffairBackfillSqlDump)")
        return 2

    tables, counts, updates = load_plan(plan_path)
    print("=== Reprise des affaires : test bout-en-bout (SQLite) ===")
    print("plan : %d tables, %d reprises" % (len(tables), len(updates)))
    print()

    check("un comptage par reprise", len(updates), len(counts))
    check("tables du plan presentes", True, len(tables) > 10)

    # ---- 0. portee des requetes : les regles que PostgreSQL impose ---------
    # SQLite accepte ce que PostgreSQL refuse ; sans ce controle, une requete
    # refusee en production passait ici sans bruit (c'est arrive : les 19
    # comptages echouaient sur la base du client).
    print()
    print("0. Portee des requetes (regles PostgreSQL)")
    _, problems = sql_scope.check_plan(counts)
    for problem in problems:
        print("   ECHEC %s" % problem)
    check("aucune table citee avant sa jointure, aucune colonne non qualifiee", 0, len(problems))

    db = build_database(tables)
    fixture(db)

    # ---- 1. diagnostic : ce que le module annonce avant d'ecrire ----------
    print()
    print("1. Diagnostic (aucune ecriture)")
    before = total_counts(db, counts)
    for description, number in before.items():
        print("   %-58s %d" % (description, number))
    check("factures depuis commande a reparer", 1, before.get("FACTURE_FOURNISSEUR <- COMMANDE (via TR_COMMANDE)", -1))
    check("factures depuis bon de reception a reparer", 1, before.get("FACTURE_FOURNISSEUR <- BON_RECEPTION (via TR_BON_RECEPTION)", -1))
    check("saisies d'achat a reparer", 1, before.get("SAISIE_ACHAT <- COMMANDE (SOURCE / IDSOURCE)", -1))
    check("lignes de commande a reparer", 2, before.get("COMMANDE_ELEMENT <- COMMANDE (lignes)", -1))
    check("facture deja renseignee non comptee", 1, value(db, "FACTURE_FOURNISSEUR", 901) == 555 and 1 or 0)

    # ---- 2. reprise -------------------------------------------------------
    print()
    print("2. Reprise (dans l'ordre : documents, puis lignes)")
    changed = 0
    for description, sql in updates:
        cursor = db.execute(sql)
        if cursor.rowcount and cursor.rowcount > 0:
            changed += cursor.rowcount
    print("   %d ligne(s) mise(s) a jour" % changed)

    # ---- 3. resultats attendus -------------------------------------------
    print()
    print("3. Resultat sur les donnees")
    check("facture 900 recoit l'affaire de la commande", 11870, value(db, "FACTURE_FOURNISSEUR", 900))
    check("facture 901 conserve SON affaire", 555, value(db, "FACTURE_FOURNISSEUR", 901))
    check("facture 902 recoit l'affaire du bon de reception", 300, value(db, "FACTURE_FOURNISSEUR", 902))
    check("facture 903 sans source reste vide", None, value(db, "FACTURE_FOURNISSEUR", 903))
    check("saisie d'achat 700 recoit l'affaire", 11870, value(db, "SAISIE_ACHAT", 700))
    check("saisie d'achat 701 (affaire indefinie) reste vide", None, value(db, "SAISIE_ACHAT", 701))
    check("saisie d'achat 702 (sans source) reste vide", None, value(db, "SAISIE_ACHAT", 702))
    check("ligne 5000 recoit l'affaire de la commande", 11870, value(db, "COMMANDE_ELEMENT", 5000))
    check("ligne 5001 recoit l'affaire de la commande", 11870, value(db, "COMMANDE_ELEMENT", 5001))
    check("ligne 5002 conserve SON affaire", 777, value(db, "COMMANDE_ELEMENT", 5002))

    # ---- 4. idempotence ---------------------------------------------------
    print()
    print("4. Seconde execution (idempotence)")
    after = total_counts(db, counts)
    for description, number in after.items():
        check("plus rien a reprendre : %s" % description, 0, number)
    changed_again = 0
    for _description, sql in updates:
        cursor = db.execute(sql)
        if cursor.rowcount and cursor.rowcount > 0:
            changed_again += cursor.rowcount
    check("aucune ecriture au second passage", 0, changed_again)
    check("affaire de la facture inchangee", 11870, value(db, "FACTURE_FOURNISSEUR", 900))

    # ---- 5. affaire inexistante -------------------------------------------
    print()
    print("5. Cas limite : la source pointe une affaire supprimee")
    insert(db, "COMMANDE", ID=254, ID_AFFAIRE=999999, NUMERO="AFFAIRE-SUPPRIMEE", ID_FOURNISSEUR=12)
    insert(db, "FACTURE_FOURNISSEUR", ID=904, ID_AFFAIRE=None, ID_FOURNISSEUR=12)
    insert(db, "TR_COMMANDE", ID=4, ID_COMMANDE=254, ID_FACTURE_FOURNISSEUR=904)
    for _description, sql in updates:
        db.execute(sql)
    # 999999 > 1 : c'est une valeur « renseignee » ; la reprise la reprend, comme
    # le module (elle n'invente rien, elle recopie ce que la source porte).
    check("affaire de la source recopiee meme si elle n'existe plus", 999999, value(db, "FACTURE_FOURNISSEUR", 904))

    # ---- bilan ------------------------------------------------------------
    db.close()
    print()
    print("Controles : %d | echecs : %d" % (passed + failed, failed))
    if failed:
        print()
        for message in failures:
            print("  - " + message)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
