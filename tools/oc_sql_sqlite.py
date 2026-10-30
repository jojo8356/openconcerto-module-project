#!/usr/bin/env python3
"""Execute les fichiers SQL du module dans SQLite, sans serveur ni OpenConcerto.

Les fichiers `sql/diagnostic-affaire-transfert.sql` et
`sql/reprise-affaire-transfert.sql` sont ecrits pour PostgreSQL. Ils
n'utilisent que du SQL standard (`UPDATE ... FROM ... JOIN`, `UNION ALL`,
`INFORMATION_SCHEMA`), donc ils s'executent tels quels dans SQLite pour peu
qu'on fournisse :

* le schema `"OpenConcerto42"` (ATTACH d'une base en memoire) ;
* une fausse `INFORMATION_SCHEMA.TABLES` qui liste les tables creees ;
* la fonction `current_schema()`.

C'est exactement ce que fait ce script. Il permet de verifier les livrables SQL
en quelques secondes, sans Docker, puis de rejouer la meme chose sur un vrai
PostgreSQL (`scripts/oc-sql-file.sh --docker`).

    python3 tools/oc_sql_sqlite.py --fixture affaire-transfert
    python3 tools/oc_sql_sqlite.py --file sql/diagnostic-affaire-transfert.sql
"""

import argparse
import os
import re
import sqlite3
import sys

SCHEMA = "OpenConcerto42"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# --------------------------------------------------------------------------
# Schema minimal : uniquement les colonnes utilisees par les scripts SQL.
# --------------------------------------------------------------------------
DOCUMENT_COLUMNS = {
    "COMMANDE": ["ID", "ID_AFFAIRE"],
    "BON_RECEPTION": ["ID", "ID_AFFAIRE"],
    "SAISIE_ACHAT": ["ID", "ID_AFFAIRE", "SOURCE", "IDSOURCE"],
    "FACTURE_FOURNISSEUR": ["ID", "ID_AFFAIRE"],
    "AVOIR_FOURNISSEUR": ["ID", "ID_AFFAIRE"],
    "DEVIS": ["ID", "ID_AFFAIRE"],
    "COMMANDE_CLIENT": ["ID", "ID_AFFAIRE"],
    "SAISIE_VENTE_FACTURE": ["ID", "ID_AFFAIRE"],
    "AVOIR_CLIENT": ["ID", "ID_AFFAIRE"],
    "BON_DE_LIVRAISON": ["ID", "ID_AFFAIRE"],
    "DEMANDE_PRIX": ["ID", "ID_AFFAIRE"],
    "DEMANDE_ACHAT": ["ID", "ID_AFFAIRE"],
}

LINE_TABLES = {
    "COMMANDE_ELEMENT": "ID_COMMANDE",
    "BON_RECEPTION_ELEMENT": "ID_BON_RECEPTION",
    "FACTURE_FOURNISSEUR_ELEMENT": "ID_FACTURE_FOURNISSEUR",
    "SAISIE_ACHAT_ELEMENT": "ID_SAISIE_ACHAT",
    "COMMANDE_CLIENT_ELEMENT": "ID_COMMANDE_CLIENT",
    "SAISIE_VENTE_FACTURE_ELEMENT": "ID_SAISIE_VENTE_FACTURE",
    "AVOIR_CLIENT_ELEMENT": "ID_AVOIR_CLIENT",
    "AVOIR_FOURNISSEUR_ELEMENT": "ID_AVOIR_FOURNISSEUR",
    "BON_DE_LIVRAISON_ELEMENT": "ID_BON_DE_LIVRAISON",
    "DEVIS_ELEMENT": "ID_DEVIS",
    "DEMANDE_PRIX_ELEMENT": "ID_DEMANDE_PRIX",
    "DEMANDE_ACHAT_ELEMENT": "ID_DEMANDE_ACHAT",
}

TRANSFER_TABLES = {
    "TR_COMMANDE": ["ID", "ID_COMMANDE", "ID_BON_RECEPTION", "ID_SAISIE_ACHAT", "ID_FACTURE_FOURNISSEUR"],
    "TR_BON_RECEPTION": ["ID", "ID_BON_RECEPTION", "ID_SAISIE_ACHAT", "ID_FACTURE_FOURNISSEUR"],
    "TR_SAISIE_ACHAT": ["ID", "ID_SAISIE_ACHAT", "ID_AVOIR_FOURNISSEUR"],
    "TR_DEVIS": ["ID", "ID_DEVIS", "ID_COMMANDE", "ID_COMMANDE_CLIENT", "ID_SAISIE_VENTE_FACTURE", "ID_BON_DE_LIVRAISON"],
    "TR_COMMANDE_CLIENT": ["ID", "ID_COMMANDE_CLIENT", "ID_SAISIE_VENTE_FACTURE", "ID_BON_DE_LIVRAISON", "ID_COMMANDE"],
    "TR_SAISIE_VENTE_FACTURE": ["ID", "ID_SAISIE_VENTE_FACTURE", "ID_AVOIR_CLIENT", "ID_BON_DE_LIVRAISON", "ID_COMMANDE"],
    "TR_BON_DE_LIVRAISON": ["ID", "ID_BON_DE_LIVRAISON", "ID_SAISIE_VENTE_FACTURE"],
}


# --------------------------------------------------------------------------
# Base
# --------------------------------------------------------------------------
def create_database():
    """Cree la base jetable avec le schema du client et ses tables."""
    db = sqlite3.connect(":memory:")
    # autocommit : le fichier de reprise porte son propre BEGIN / COMMIT
    db.isolation_level = None
    db.execute("ATTACH ':memory:' AS %s" % SCHEMA)
    db.execute("ATTACH ':memory:' AS information_schema")
    db.execute("CREATE TABLE information_schema.tables (table_schema text, table_name text)")
    db.create_function("current_schema", 0, lambda: SCHEMA)

    for table, columns in DOCUMENT_COLUMNS.items():
        _create(db, table, columns)
    for table, link in LINE_TABLES.items():
        _create(db, table, ["ID", "ID_AFFAIRE", link])
    for table, columns in TRANSFER_TABLES.items():
        _create(db, table, columns)
    return db


def _create(db, table, columns):
    ddl = ", ".join('"%s" integer' % column for column in columns)
    db.execute('CREATE TABLE "%s"."%s" (%s)' % (SCHEMA, table, ddl))
    db.execute("INSERT INTO information_schema.tables VALUES (?, ?)", (SCHEMA, table))


def insert(db, table, **values):
    columns = ", ".join('"%s"' % key for key in values)
    marks = ", ".join("?" for _ in values)
    db.execute('INSERT INTO "%s"."%s" (%s) VALUES (%s)' % (SCHEMA, table, columns, marks),
               list(values.values()))


def affair_of(db, table, row_id):
    row = db.execute('SELECT "ID_AFFAIRE" FROM "%s"."%s" WHERE "ID" = ?' % (SCHEMA, table), (row_id,)).fetchone()
    return None if row is None else row[0]


# --------------------------------------------------------------------------
# Jeu de donnees
# --------------------------------------------------------------------------
def transfert_rows():
    """Les cas de test, sous forme de lignes a inserer."""
    return [
    # --- documents sources -------------------------------------------------
    ("COMMANDE", dict(ID=251, ID_AFFAIRE=11870)),
    ("COMMANDE", dict(ID=252, ID_AFFAIRE=1)),
    ("COMMANDE", dict(ID=253, ID_AFFAIRE=None)),
    ("COMMANDE", dict(ID=254, ID_AFFAIRE=999999)),
    ("COMMANDE", dict(ID=255, ID_AFFAIRE=None)),
    ("COMMANDE", dict(ID=256, ID_AFFAIRE=None)),
    ("COMMANDE", dict(ID=257, ID_AFFAIRE=None)),
    ("DEVIS", dict(ID=600, ID_AFFAIRE=777)),
    ("BON_RECEPTION", dict(ID=400, ID_AFFAIRE=300)),
    ("BON_RECEPTION", dict(ID=401, ID_AFFAIRE=1)),
    ("BON_RECEPTION", dict(ID=402, ID_AFFAIRE=None)),
    ("BON_RECEPTION", dict(ID=403, ID_AFFAIRE=None)),
    ("DEMANDE_PRIX", dict(ID=1400, ID_AFFAIRE=11870)),
    ("DEMANDE_ACHAT", dict(ID=1500, ID_AFFAIRE=300)),

    # --- achats : saisies d'achat (SOURCE / IDSOURCE) ----------------------
    ("SAISIE_ACHAT", dict(ID=700, ID_AFFAIRE=None, SOURCE="COMMANDE", IDSOURCE=251)),
    ("SAISIE_ACHAT", dict(ID=701, ID_AFFAIRE=None, SOURCE="COMMANDE", IDSOURCE=252)),
    ("SAISIE_ACHAT", dict(ID=702, ID_AFFAIRE=None, SOURCE="BON_RECEPTION", IDSOURCE=400)),
    ("SAISIE_ACHAT", dict(ID=703, ID_AFFAIRE=555, SOURCE="COMMANDE", IDSOURCE=251)),
    ("SAISIE_ACHAT", dict(ID=704, ID_AFFAIRE=None, SOURCE=None, IDSOURCE=None)),
    ("SAISIE_ACHAT", dict(ID=705, ID_AFFAIRE=1, SOURCE="COMMANDE", IDSOURCE=254)),
    # celles-ci ne passent que par les tables TR_*
    ("SAISIE_ACHAT", dict(ID=706, ID_AFFAIRE=None, SOURCE=None, IDSOURCE=None)),
    ("SAISIE_ACHAT", dict(ID=707, ID_AFFAIRE=None, SOURCE=None, IDSOURCE=None)),

    # --- achats : factures et avoirs --------------------------------------
    ("FACTURE_FOURNISSEUR", dict(ID=900, ID_AFFAIRE=None)),
    ("FACTURE_FOURNISSEUR", dict(ID=901, ID_AFFAIRE=555)),
    ("FACTURE_FOURNISSEUR", dict(ID=902, ID_AFFAIRE=1)),
    ("FACTURE_FOURNISSEUR", dict(ID=903, ID_AFFAIRE=None)),
    ("FACTURE_FOURNISSEUR", dict(ID=904, ID_AFFAIRE=None)),
    ("AVOIR_FOURNISSEUR", dict(ID=1300, ID_AFFAIRE=None)),

    # --- ventes ------------------------------------------------------------
    ("COMMANDE_CLIENT", dict(ID=800, ID_AFFAIRE=None)),
    ("COMMANDE_CLIENT", dict(ID=801, ID_AFFAIRE=888)),
    ("SAISIE_VENTE_FACTURE", dict(ID=1000, ID_AFFAIRE=None)),
    ("SAISIE_VENTE_FACTURE", dict(ID=1001, ID_AFFAIRE=None)),
    ("SAISIE_VENTE_FACTURE", dict(ID=1002, ID_AFFAIRE=None)),
    ("BON_DE_LIVRAISON", dict(ID=1100, ID_AFFAIRE=None)),
    ("BON_DE_LIVRAISON", dict(ID=1101, ID_AFFAIRE=None)),
    ("BON_DE_LIVRAISON", dict(ID=1102, ID_AFFAIRE=None)),
    ("AVOIR_CLIENT", dict(ID=1200, ID_AFFAIRE=None)),

    # --- tables de transfert du coeur -------------------------------------
    ("TR_COMMANDE", dict(ID=1, ID_COMMANDE=251, ID_BON_RECEPTION=400, ID_SAISIE_ACHAT=None, ID_FACTURE_FOURNISSEUR=900)),
    ("TR_COMMANDE", dict(ID=2, ID_COMMANDE=251, ID_BON_RECEPTION=None, ID_SAISIE_ACHAT=None, ID_FACTURE_FOURNISSEUR=901)),
    ("TR_COMMANDE", dict(ID=3, ID_COMMANDE=254, ID_BON_RECEPTION=None, ID_SAISIE_ACHAT=None, ID_FACTURE_FOURNISSEUR=904)),
    ("TR_COMMANDE", dict(ID=4, ID_COMMANDE=252, ID_BON_RECEPTION=402, ID_SAISIE_ACHAT=None, ID_FACTURE_FOURNISSEUR=None)),
    ("TR_COMMANDE", dict(ID=5, ID_COMMANDE=251, ID_BON_RECEPTION=403, ID_SAISIE_ACHAT=706, ID_FACTURE_FOURNISSEUR=None)),
    ("TR_BON_RECEPTION", dict(ID=1, ID_BON_RECEPTION=400, ID_SAISIE_ACHAT=707, ID_FACTURE_FOURNISSEUR=902)),
    ("TR_SAISIE_ACHAT", dict(ID=1, ID_SAISIE_ACHAT=700, ID_AVOIR_FOURNISSEUR=1300)),
    ("TR_DEVIS", dict(ID=1, ID_DEVIS=600, ID_COMMANDE=255, ID_COMMANDE_CLIENT=800,
                      ID_SAISIE_VENTE_FACTURE=1000, ID_BON_DE_LIVRAISON=1100)),
    ("TR_COMMANDE_CLIENT", dict(ID=1, ID_COMMANDE_CLIENT=800, ID_SAISIE_VENTE_FACTURE=1001,
                                ID_BON_DE_LIVRAISON=1101, ID_COMMANDE=256)),
    ("TR_SAISIE_VENTE_FACTURE", dict(ID=1, ID_SAISIE_VENTE_FACTURE=1000, ID_AVOIR_CLIENT=1200,
                                     ID_BON_DE_LIVRAISON=1102, ID_COMMANDE=257)),
    ("TR_BON_DE_LIVRAISON", dict(ID=1, ID_BON_DE_LIVRAISON=1100, ID_SAISIE_VENTE_FACTURE=1002)),

    # --- lignes ------------------------------------------------------------
    ("COMMANDE_ELEMENT", dict(ID=5000, ID_AFFAIRE=None, ID_COMMANDE=251)),
    ("COMMANDE_ELEMENT", dict(ID=5001, ID_AFFAIRE=None, ID_COMMANDE=251)),
    ("COMMANDE_ELEMENT", dict(ID=5002, ID_AFFAIRE=777, ID_COMMANDE=251)),
    ("FACTURE_FOURNISSEUR_ELEMENT", dict(ID=5100, ID_AFFAIRE=None, ID_FACTURE_FOURNISSEUR=900)),
    ("FACTURE_FOURNISSEUR_ELEMENT", dict(ID=5101, ID_AFFAIRE=777, ID_FACTURE_FOURNISSEUR=900)),
    ("SAISIE_ACHAT_ELEMENT", dict(ID=5200, ID_AFFAIRE=None, ID_SAISIE_ACHAT=700)),
    ("BON_RECEPTION_ELEMENT", dict(ID=5300, ID_AFFAIRE=None, ID_BON_RECEPTION=400)),
    ("COMMANDE_CLIENT_ELEMENT", dict(ID=5400, ID_AFFAIRE=None, ID_COMMANDE_CLIENT=800)),
    ("SAISIE_VENTE_FACTURE_ELEMENT", dict(ID=5500, ID_AFFAIRE=None, ID_SAISIE_VENTE_FACTURE=1000)),
    ("DEMANDE_PRIX_ELEMENT", dict(ID=5600, ID_AFFAIRE=None, ID_DEMANDE_PRIX=1400)),
    ("DEMANDE_ACHAT_ELEMENT", dict(ID=5700, ID_AFFAIRE=None, ID_DEMANDE_ACHAT=1500)),
    ("DEVIS_ELEMENT", dict(ID=5800, ID_AFFAIRE=None, ID_DEVIS=600)),
    ("AVOIR_CLIENT_ELEMENT", dict(ID=5900, ID_AFFAIRE=None, ID_AVOIR_CLIENT=1200)),
    ("AVOIR_FOURNISSEUR_ELEMENT", dict(ID=6000, ID_AFFAIRE=None, ID_AVOIR_FOURNISSEUR=1300)),
    ("BON_DE_LIVRAISON_ELEMENT", dict(ID=6100, ID_AFFAIRE=None, ID_BON_DE_LIVRAISON=1100)),
    ]


def fixture_transfert(db):
    for table, values in transfert_rows():
        insert(db, table, **values)


FIXTURES = {"affaire-transfert": fixture_transfert}

AFTER_REPRISE = [
    ("SAISIE_ACHAT", 700, 11870, "saisie d'achat : affaire de la commande"),
    ("SAISIE_ACHAT", 701, None, "saisie d'achat : source « Indefini », rien"),
    ("SAISIE_ACHAT", 702, 300, "saisie d'achat : affaire du bon de reception"),
    ("SAISIE_ACHAT", 703, 555, "saisie d'achat : affaire propre conservee"),
    ("SAISIE_ACHAT", 704, None, "saisie d'achat : sans source, rien"),
    ("SAISIE_ACHAT", 705, 999999, "saisie d'achat : affaire de la source recopiee"),
    ("FACTURE_FOURNISSEUR", 900, 11870, "facture : affaire de la commande"),
    ("SAISIE_ACHAT", 706, 11870, "saisie d'achat : affaire de la commande via TR_COMMANDE"),
    ("SAISIE_ACHAT", 707, 300, "saisie d'achat : affaire du bon de reception via TR_BON_RECEPTION"),
    ("FACTURE_FOURNISSEUR", 901, 555, "facture : affaire propre conservee"),
    ("FACTURE_FOURNISSEUR", 902, 300, "facture : affaire du bon de reception"),
    ("FACTURE_FOURNISSEUR", 903, None, "facture : sans table TR_*, rien"),
    ("FACTURE_FOURNISSEUR", 904, 999999, "facture : affaire de la source recopiee"),
    ("BON_RECEPTION", 402, None, "bon de reception : source « Indefini », rien"),
    ("BON_RECEPTION", 403, 11870, "bon de reception : affaire de la commande"),
    ("COMMANDE_CLIENT", 800, 777, "commande client : affaire du devis"),
    ("COMMANDE_CLIENT", 801, 888, "commande client : affaire propre conservee"),
    ("SAISIE_VENTE_FACTURE", 1000, 777, "facture de vente : affaire du devis"),
    ("SAISIE_VENTE_FACTURE", 1001, 777, "facture de vente : affaire de la commande client"),
    ("COMMANDE", 255, 777, "commande : affaire du devis"),
    ("COMMANDE", 256, 777, "commande : affaire de la commande client"),
    ("COMMANDE", 257, 777, "commande : affaire de la facture de vente"),
    ("BON_DE_LIVRAISON", 1100, 777, "bon de livraison : affaire du devis"),
    ("BON_DE_LIVRAISON", 1101, 777, "bon de livraison : affaire de la commande client"),
    ("BON_DE_LIVRAISON", 1102, 777, "bon de livraison : affaire de la facture de vente"),
    ("SAISIE_VENTE_FACTURE", 1002, 777, "facture de vente : affaire du bon de livraison"),
    ("AVOIR_CLIENT", 1200, 777, "avoir client : affaire de la facture"),
    ("AVOIR_FOURNISSEUR", 1300, 11870, "avoir fournisseur : affaire de la saisie d'achat"),
    ("COMMANDE_ELEMENT", 5000, 11870, "ligne de commande"),
    ("COMMANDE_ELEMENT", 5002, 777, "ligne de commande : affaire propre conservee"),
    ("FACTURE_FOURNISSEUR_ELEMENT", 5100, 11870, "ligne de facture"),
    ("SAISIE_ACHAT_ELEMENT", 5200, 11870, "ligne de saisie d'achat"),
    ("BON_RECEPTION_ELEMENT", 5300, 300, "ligne de bon de reception"),
    ("COMMANDE_CLIENT_ELEMENT", 5400, 777, "ligne de commande client"),
    ("SAISIE_VENTE_FACTURE_ELEMENT", 5500, 777, "ligne de facture de vente"),
    ("DEMANDE_PRIX_ELEMENT", 5600, 11870, "ligne de demande de prix"),
    ("DEMANDE_ACHAT_ELEMENT", 5700, 300, "ligne de demande d'achat"),
    ("DEVIS_ELEMENT", 5800, 777, "ligne de devis"),
    ("AVOIR_CLIENT_ELEMENT", 5900, 777, "ligne d'avoir client"),
    ("AVOIR_FOURNISSEUR_ELEMENT", 6000, 11870, "ligne d'avoir fournisseur"),
    ("BON_DE_LIVRAISON_ELEMENT", 6100, 777, "ligne de bon de livraison"),
]




# --------------------------------------------------------------------------
# Sortie pour PostgreSQL (mode --docker / CI)
# --------------------------------------------------------------------------
def all_tables():
    """(nom, colonnes) de toutes les tables du schema de test."""
    tables = []
    for table, columns in DOCUMENT_COLUMNS.items():
        tables.append((table, columns))
    for table, link in LINE_TABLES.items():
        tables.append((table, ["ID", "ID_AFFAIRE", link]))
    for table, columns in TRANSFER_TABLES.items():
        tables.append((table, columns))
    return tables


#: Colonnes qui ne sont pas des identifiants.
TEXT_COLUMNS = ("SOURCE", "NUMERO")


def column_type(name):
    return "text" if name in TEXT_COLUMNS else "integer"


def emit_fixture():
    """DDL + donnees, en PostgreSQL : cree la base de test de toutes pieces."""
    print("-- Base de test jetable pour sql/*.sql (PostgreSQL).")
    print('CREATE SCHEMA IF NOT EXISTS "%s";' % SCHEMA)
    for table, columns in all_tables():
        ddl = ", ".join('"%s" %s' % (column, column_type(column)) for column in columns)
        print('CREATE TABLE "%s"."%s" (%s);' % (SCHEMA, table, ddl))
    for table, values in transfert_rows():
        columns = ", ".join('"%s"' % key for key in values)
        rendered = []
        for value in values.values():
            if value is None:
                rendered.append("NULL")
            elif isinstance(value, str):
                rendered.append("'" + value.replace("'", "''") + "'")
            else:
                rendered.append(str(value))
        print('INSERT INTO "%s"."%s" (%s) VALUES (%s);' % (SCHEMA, table, columns, ", ".join(rendered)))
    print()
    print("-- Le bloc ci-dessous doit rester coherent avec les attentes du test SQLite.")


#: Etat attendu AVANT la reprise : il prouve que le jeu de donnees reproduit
#: bien la panne (une facture vide alors que sa commande porte une affaire).
BEFORE_REPRISE = [
    ("FACTURE_FOURNISSEUR", 900, None, "avant : facture issue d'une commande, sans affaire"),
    ("FACTURE_FOURNISSEUR", 901, 555, "avant : facture deja rattachee conserve son affaire"),
    ("SAISIE_ACHAT", 700, None, "avant : saisie d'achat sans affaire"),
    ("COMMANDE", 255, None, "avant : commande issue d'un devis, sans affaire"),
    ("BON_DE_LIVRAISON", 1100, None, "avant : bon de livraison sans affaire"),
]


def emit_checks():
    """Verifications finales, en SQL : 'OK' / 'ECHEC' ligne par ligne."""
    print("-- Verifications du jeu de donnees et de la reprise : tout doit afficher OK.")
    for table, row_id, affair, label in AFTER_REPRISE + BEFORE_REPRISE:
        expected = "NULL" if affair is None else str(affair)
        print("select '%s' as controle, case when (select \"ID_AFFAIRE\" from \"%s\".\"%s\" where \"ID\" = %d) is not distinct from %s then 'OK' else 'ECHEC' end as resultat;"
              % (label.replace("'", "''"), SCHEMA, table, row_id, expected))


# --------------------------------------------------------------------------
# Execution d'un fichier psql dans SQLite
# --------------------------------------------------------------------------
def read_script(path):
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    statements = []
    for line in text.splitlines():
        stripped = line.strip()
        # commandes psql (\\echo, \\set, ...) : sans effet hors psql
        if stripped.startswith("\\"):
            continue
        # commentaires : inutiles, et ils peuvent contenir des ';'
        if stripped.startswith("--"):
            continue
        statements.append(line)
    sql = "\n".join(statements)
    return [part.strip() for part in split_statements(sql) if part.strip()]


def split_statements(sql):
    """Decoupe sur les ';' hors chaines de caracteres."""
    parts = []
    current = []
    quote = None
    for char in sql:
        if quote:
            current.append(char)
            if char == quote:
                quote = None
            continue
        if char in ("'", '"'):
            quote = char
            current.append(char)
            continue
        if char == ";":
            parts.append("".join(current))
            current = []
            continue
        current.append(char)
    parts.append("".join(current))
    return parts


def normalize(statement):
    """Seule adaptation de compatibilite : l'echappement de LIKE.

    PostgreSQL considere la barre oblique inverse comme caractere
    d'echappement par defaut dans LIKE, SQLite non. On rend l'echappement
    explicite, sans changer le sens de la requete.
    """
    bs = chr(92)
    needle = "like 'TR" + bs + "_%'"
    return statement.replace(needle, "like 'TR!_%' escape '!'").replace(needle.upper(), "like 'TR!_%' escape '!'")


def execute(db, statements, verbose=False):
    """Execute une suite d'ordres ; renvoie les resultats des SELECT."""
    results = []
    for statement in statements:
        upper = statement.lstrip().upper()
        cursor = db.execute(normalize(statement))
        if upper.startswith("SELECT") or upper.startswith("WITH"):
            headers = [column[0] for column in cursor.description]
            results.append((statement, headers, cursor.fetchall()))
        elif verbose:
            print("   %s ... %s ligne(s)" % (upper.split()[0], cursor.rowcount if cursor.rowcount >= 0 else "?"))
    return results


def snapshot(db):
    """Photographie des affaires, pour prouver l'idempotence."""
    state = {}
    for table in list(DOCUMENT_COLUMNS) + list(LINE_TABLES):
        rows = db.execute('SELECT "ID", "ID_AFFAIRE" FROM "%s"."%s" ORDER BY "ID"' % (SCHEMA, table)).fetchall()
        for row_id, affair in rows:
            state[(table, row_id)] = affair
    return state


# --------------------------------------------------------------------------
# Scenarios
# --------------------------------------------------------------------------
class Checker:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.failures = []

    def check(self, label, expected, actual):
        if expected == actual:
            self.passed += 1
            print("   OK    %s" % label)
        else:
            self.failed += 1
            message = "%s : attendu <%s>, obtenu <%s>" % (label, expected, actual)
            self.failures.append(message)
            print("   ECHEC %s" % message)

    def report(self):
        print()
        print("Controles : %d | echecs : %d" % (self.passed + self.failed, self.failed))
        if self.failed:
            print()
            for message in self.failures:
                print("  - " + message)
            return 1
        return 0


def as_dict(result):
    """Transforme (headers, rows) en {premiere colonne: derniere colonne}."""
    return {row[0]: row[-1] for row in result[2]}


def scenario_transfert(checker):
    diagnostic = os.path.join(ROOT, "sql", "diagnostic-affaire-transfert.sql")
    reprise = os.path.join(ROOT, "sql", "reprise-affaire-transfert.sql")

    print("=== Fichiers SQL du module, executes dans SQLite ===")
    print("    %s" % os.path.relpath(diagnostic, ROOT))
    print("    %s" % os.path.relpath(reprise, ROOT))
    print()

    db = create_database()
    fixture_transfert(db)

    print("0. Le jeu de donnees reproduit bien la panne")
    for table, row_id, affair, label in BEFORE_REPRISE:
        checker.check(label, affair, affair_of(db, table, row_id))

    print("1. Diagnostic AVANT reprise (lecture seule)")
    diagnostic_statements = read_script(diagnostic)
    checker.check("le fichier de diagnostic contient des requetes", True, len(diagnostic_statements) >= 5)
    results = execute(db, diagnostic_statements)
    checker.check("toutes les requetes de diagnostic s'executent", len(diagnostic_statements), len(results))
    sections = {}
    for _statement, headers, rows in results:
        sections[headers[0]] = rows
        for row in rows:
            print("   %-40s %s" % (row[0], row[-1]))

    checker.check("§0 : schema courant", SCHEMA, sections.get("schema_courant", [[None]])[0][0])
    checker.check("§1 : saisies d'achat a reparer", {"COMMANDE": 2, "BON_RECEPTION": 1},
                  {row[0]: row[-1] for row in sections.get("source", [])})
    checker.check("§2 : documents via TR_* a reparer (17 transferts)",
                  {"SAISIE_ACHAT <- COMMANDE": 1, "BON_RECEPTION <- COMMANDE": 1,
                   "FACTURE_FOURNISSEUR <- COMMANDE": 2, "SAISIE_ACHAT <- BON_RECEPTION": 1,
                   "FACTURE_FOURNISSEUR <- BON_RECEPTION": 1, "COMMANDE <- DEVIS": 1,
                   "AVOIR_FOURNISSEUR <- SAISIE_ACHAT": 0, "COMMANDE_CLIENT <- DEVIS": 1,
                   "SAISIE_VENTE_FACTURE <- DEVIS": 1, "BON_DE_LIVRAISON <- DEVIS": 1,
                   "SAISIE_VENTE_FACTURE <- COMMANDE_CLIENT": 0, "BON_DE_LIVRAISON <- COMMANDE_CLIENT": 0,
                   "COMMANDE <- COMMANDE_CLIENT": 0, "SAISIE_VENTE_FACTURE <- BON_DE_LIVRAISON": 0,
                   "AVOIR_CLIENT <- SAISIE_VENTE_FACTURE": 0, "BON_DE_LIVRAISON <- SAISIE_VENTE_FACTURE": 0,
                   "COMMANDE <- SAISIE_VENTE_FACTURE": 0},
                  {row[0]: row[-1] for row in sections.get("transfert", [])})
    # Seules les lignes dont le document porte DEJA une affaire sont comptees :
    # les autres le seront au passage des lignes, apres la reprise des documents.
    checker.check("§3 : lignes a reparer (12 tableaux)",
                  {"COMMANDE_ELEMENT": 2, "BON_RECEPTION_ELEMENT": 1, "FACTURE_FOURNISSEUR_ELEMENT": 0,
                   "SAISIE_ACHAT_ELEMENT": 0, "AVOIR_FOURNISSEUR_ELEMENT": 0, "DEMANDE_PRIX_ELEMENT": 1,
                   "DEMANDE_ACHAT_ELEMENT": 1, "COMMANDE_CLIENT_ELEMENT": 0,
                   "SAISIE_VENTE_FACTURE_ELEMENT": 0, "DEVIS_ELEMENT": 1,
                   "AVOIR_CLIENT_ELEMENT": 0, "BON_DE_LIVRAISON_ELEMENT": 0},
                  {row[0]: row[-1] for row in sections.get("table_lignes", [])})
    checker.check("§4 : tables de transfert listees", 7, len(sections.get("table_name", [])))
    checker.check("§5 : compteur global des documents sans affaire",
                  {"COMMANDE": 5, "BON_RECEPTION": 3, "SAISIE_ACHAT": 7, "FACTURE_FOURNISSEUR": 4,
                   "COMMANDE_CLIENT": 1, "SAISIE_VENTE_FACTURE": 3},
                  {row[0]: row[-1] for row in sections.get("document", [])})
    checker.check("le diagnostic n'a rien ecrit", None, affair_of(db, "FACTURE_FOURNISSEUR", 900))

    print()
    print("2. Reprise")
    reprise_statements = read_script(reprise)
    checker.check("le fichier de reprise est transactionnel", True,
                  any(s.upper().startswith("BEGIN") for s in reprise_statements)
                  and any(s.upper().startswith("COMMIT") for s in reprise_statements))
    execute(db, reprise_statements)

    print()
    print("3. Resultat")
    for table, row_id, affair, label in AFTER_REPRISE:
        checker.check(label, affair, affair_of(db, table, row_id))

    print()
    print("4. Rejeu : le script doit etre idempotent")
    state = snapshot(db)
    execute(db, read_script(reprise))
    checker.check("aucune valeur modifiee au second passage", state, snapshot(db))

    results = execute(db, read_script(diagnostic))
    sections = {headers[0]: rows for _statement, headers, rows in results}
    check_zero(checker, "§1", sections.get("source", []))
    check_zero(checker, "§2", sections.get("transfert", []))
    check_zero(checker, "§3", sections.get("table_lignes", []))
    checker.check("§5 : il ne reste que les documents sans source",
                  {"COMMANDE": 2, "BON_RECEPTION": 2, "SAISIE_ACHAT": 2, "FACTURE_FOURNISSEUR": 1,
                   "COMMANDE_CLIENT": 0, "SAISIE_VENTE_FACTURE": 0},
                  {row[0]: row[-1] for row in sections.get("document", [])})

    print()
    print("5. Cas limite : base sans aucune table de transfert")
    db2 = create_database()
    for table in TRANSFER_TABLES:
        db2.execute('DROP TABLE "%s"."%s"' % (SCHEMA, table))
        db2.execute("DELETE FROM information_schema.tables WHERE table_name = ?", (table,))
    fixture_sans_transfert(db2)
    # Sans table TR_*, la reprise echoue. Le fichier etant transactionnel, rien
    # ne doit rester ecrit : c'est le comportement de PostgreSQL, et c'est ce que
    # protege le BEGIN / COMMIT du fichier.
    try:
        execute(db2, read_script(reprise))
        checker.check("reprise sans TR_* refusee", "erreur", "aucune erreur")
    except sqlite3.Error as error:
        checker.check("reprise sans TR_* refusee avec un message clair", True, "no such table" in str(error))
        db2.execute("ROLLBACK")
    checker.check("reprise sans TR_* : transaction annulee, rien d'ecrit", None, affair_of(db2, "SAISIE_ACHAT", 700))

    db.close()
    db2.close()
    return checker.report()


def fixture_sans_transfert(db):
    ("COMMANDE", dict(ID=251, ID_AFFAIRE=11870)),
    ("SAISIE_ACHAT", dict(ID=700, ID_AFFAIRE=None, SOURCE="COMMANDE", IDSOURCE=251)),
    ("COMMANDE_ELEMENT", dict(ID=5000, ID_AFFAIRE=None, ID_COMMANDE=251)),
def check_zero(checker, section, rows):
    remaining = {row[0]: row[-1] for row in rows if row[-1] != 0}
    checker.check("%s : plus rien a reprendre" % section, {}, remaining)


# --------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Execute les fichiers SQL du module dans SQLite.")
    parser.add_argument("--file", help="fichier SQL a executer (au lieu du scenario complet)")
    parser.add_argument("--fixture", default="affaire-transfert", help="jeu de donnees a charger")
    parser.add_argument("--keep", action="store_true", help="affiche toutes les lignes produites")
    parser.add_argument("--emit-fixture", action="store_true", help="ecrit le jeu de donnees en SQL PostgreSQL")
    parser.add_argument("--emit-checks", action="store_true", help="ecrit les verifications en SQL PostgreSQL")
    args = parser.parse_args()

    if args.emit_fixture:
        emit_fixture()
        return 0
    if args.emit_checks:
        emit_checks()
        return 0

    if args.file:
        db = create_database()
        FIXTURES[args.fixture](db)
        results = execute(db, read_script(args.file))
        for _statement, headers, rows in results:
            print(" | ".join(headers))
            for row in rows:
                print(" | ".join("-" if value is None else str(value) for value in row))
            print()
        db.close()
        return 0

    return scenario_transfert(Checker())


if __name__ == "__main__":
    sys.exit(main())
