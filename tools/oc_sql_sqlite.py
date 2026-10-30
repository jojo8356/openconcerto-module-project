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

#: Table des affaires elle-meme (jamais mise a jour par la reprise).
AFFAIR_COLUMNS = ["ID", "NUMERO", "NOM"]
DOCUMENT_COLUMNS = {
    "COMMANDE": ["ID", "ID_AFFAIRE", "NUMERO"],
    "BON_RECEPTION": ["ID", "ID_AFFAIRE", "NUMERO"],
    "SAISIE_ACHAT": ["ID", "ID_AFFAIRE", "SOURCE", "IDSOURCE", "NUMERO"],
    "FACTURE_FOURNISSEUR": ["ID", "ID_AFFAIRE", "NUMERO"],
    "AVOIR_FOURNISSEUR": ["ID", "ID_AFFAIRE", "NUMERO"],
    "DEVIS": ["ID", "ID_AFFAIRE", "NUMERO"],
    "COMMANDE_CLIENT": ["ID", "ID_AFFAIRE", "NUMERO"],
    "SAISIE_VENTE_FACTURE": ["ID", "ID_AFFAIRE", "NUMERO"],
    "AVOIR_CLIENT": ["ID", "ID_AFFAIRE", "NUMERO"],
    "BON_DE_LIVRAISON": ["ID", "ID_AFFAIRE", "NUMERO"],
    "DEMANDE_PRIX": ["ID", "ID_AFFAIRE", "NUMERO"],
    "DEMANDE_ACHAT": ["ID", "ID_AFFAIRE", "NUMERO"],
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

#: Tableaux de lignes qui portent REELLEMENT la colonne sur la base du client
#: (mesure du 30/10/2026, information_schema.columns). Les dix autres lisent
#: l'affaire de leur document : c'est le module qui decide, pas le SQL.
LINE_TABLES_WITH_AFFAIR = frozenset(["FACTURE_FOURNISSEUR_ELEMENT", "DEMANDE_ACHAT_ELEMENT"])

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
def create_database(line_columns="client", devis_key="ID_DEVIS"):
    """Cree la base jetable avec le schema du client et ses tables.

    @param line_columns "client" : seuls les tableaux mesures portent
                        ID_AFFAIRE ; "all" : les douze, comme apres une
                        installation complete du module.
    """
    db = sqlite3.connect(":memory:")
    # autocommit : le fichier de reprise porte son propre BEGIN / COMMIT
    db.isolation_level = None
    db.execute("ATTACH ':memory:' AS %s" % SCHEMA)
    db.execute("ATTACH ':memory:' AS information_schema")
    db.execute("CREATE TABLE information_schema.tables (table_schema text, table_name text)")
    # les fichiers SQL du module interrogent aussi information_schema.columns
    db.execute("CREATE TABLE information_schema.columns (table_schema text, table_name text, column_name text)")
    db.create_function("current_schema", 0, lambda: SCHEMA)

    _create(db, "AFFAIRE", AFFAIR_COLUMNS)
    for table, columns in DOCUMENT_COLUMNS.items():
        if table == "DEVIS":
            # cas reel mesure : la table DEVIS du client porte ID_DEVIS, pas ID
            columns = [devis_key] + [column for column in columns if column not in ("ID", "ID_DEVIS")] if devis_key else \
                [column for column in columns if column not in ("ID", "ID_DEVIS")]
        _create(db, table, columns)
    for table, link in LINE_TABLES.items():
        columns = ["ID", link]
        if line_columns == "all" or table in LINE_TABLES_WITH_AFFAIR:
            columns = ["ID", "ID_AFFAIRE", link]
        _create(db, table, columns)
    for table, columns in TRANSFER_TABLES.items():
        _create(db, table, columns)
    return db


def _create(db, table, columns):
    ddl = ", ".join('"%s" integer' % column for column in columns)
    db.execute('CREATE TABLE "%s"."%s" (%s)' % (SCHEMA, table, ddl))
    db.execute("INSERT INTO information_schema.tables VALUES (?, ?)", (SCHEMA, table))
    for column in columns:
        db.execute("INSERT INTO information_schema.columns VALUES (?, ?, ?)", (SCHEMA, table, column))


def insert(db, table, **values):
    # une colonne absente du schema de test est ignoree : cela permet d'utiliser
    # le meme jeu de donnees pour les deux variantes de schema
    try:
        existing = {row[1] for row in db.execute('PRAGMA "%s".table_info("%s")' % (SCHEMA, table)).fetchall()}
    except sqlite3.Error:
        existing = set(values)
    if "ID" in values and "ID" not in existing and ("ID_" + table) in existing:
        values["ID_" + table] = values.pop("ID")
    values = {key: value for key, value in values.items() if key in existing}
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
    ("AFFAIRE", dict(ID=11870, NUMERO="11870-PO-007", NOM="KINETIC-THERM")),
    ("AFFAIRE", dict(ID=300, NUMERO="300", NOM="AFFAIRE 300")),
    ("AFFAIRE", dict(ID=555, NUMERO="555", NOM="AFFAIRE 555")),
    ("AFFAIRE", dict(ID=777, NUMERO="777", NOM="AFFAIRE 777")),
    ("AFFAIRE", dict(ID=888, NUMERO="888", NOM="AFFAIRE 888")),
    # --- documents sources -------------------------------------------------
    ("COMMANDE", dict(ID=251, ID_AFFAIRE=11870)),
    ("COMMANDE", dict(ID=252, ID_AFFAIRE=1)),
    ("COMMANDE", dict(ID=253, ID_AFFAIRE=None)),
    ("COMMANDE", dict(ID=254, ID_AFFAIRE=999999)),
    ("COMMANDE", dict(ID=255, ID_AFFAIRE=None)),
    ("COMMANDE", dict(ID=256, ID_AFFAIRE=None)),
    ("COMMANDE", dict(ID=257, ID_AFFAIRE=None)),
    ("AFFAIRE", dict(ID=777, NUMERO="777", NOM="AFFAIRE 777")),
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
]

#: Attentes sur les tableaux de lignes : seulement ceux qui portent la colonne.
AFTER_REPRISE_LIGNES = [
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
def all_tables(line_columns="client", devis_key="ID_DEVIS"):
    """(nom, colonnes) de toutes les tables du schema de test."""
    tables = [("AFFAIRE", AFFAIR_COLUMNS)]
    for table, columns in DOCUMENT_COLUMNS.items():
        if table == "DEVIS":
            columns = ([devis_key] if devis_key else []) + [column for column in columns if column not in ("ID", "ID_DEVIS")]
        tables.append((table, columns))
    for table, link in LINE_TABLES.items():
        if line_columns == "all" or table in LINE_TABLES_WITH_AFFAIR:
            tables.append((table, ["ID", "ID_AFFAIRE", link]))
        else:
            tables.append((table, ["ID", link]))
    for table, columns in TRANSFER_TABLES.items():
        tables.append((table, columns))
    return tables


#: Colonnes qui ne sont pas des identifiants.
TEXT_COLUMNS = ("SOURCE", "NUMERO", "NOM")


def column_type(name):
    return "text" if name in TEXT_COLUMNS else "integer"


def emit_fixture(line_columns="client", devis_key="ID_DEVIS"):
    """DDL + donnees, en PostgreSQL : cree la base de test de toutes pieces."""
    print("-- Base de test jetable pour sql/*.sql (PostgreSQL).")
    print('CREATE SCHEMA IF NOT EXISTS "%s";' % SCHEMA)
    for table, columns in all_tables(line_columns, devis_key):
        ddl = ", ".join('"%s" %s' % (column, column_type(column)) for column in columns)
        print('CREATE TABLE "%s"."%s" (%s);' % (SCHEMA, table, ddl))
    for table, values in transfert_rows():
        values = dict(values)
        if "ID" in values and table == "DEVIS" and devis_key != "ID":
            values[devis_key] = values.pop("ID")
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


def _emit_expectations(rows, title):
    print("-- %s" % title)
    for table, row_id, affair, label in rows:
        expected = "NULL" if affair is None else str(affair)
        print("select '%s' as controle, case when (select \"ID_AFFAIRE\" from \"%s\".\"%s\" where \"ID\" = %d) is not distinct from %s then 'OK' else 'ECHEC' end as resultat;"
              % (label.replace("'", "''"), SCHEMA, table, row_id, expected))


def emit_checks():
    """Verifications finales, apres reprise : 'OK' / 'ECHEC' ligne par ligne."""
    _emit_expectations(AFTER_REPRISE + AFTER_REPRISE_LIGNES,
                       "Verifications apres reprise (en-tetes et lignes) : tout doit afficher OK.")


def emit_before_checks():
    """Verifications de la base de test, avant toute reprise."""
    _emit_expectations(BEFORE_REPRISE, "Le jeu de donnees doit reproduire la panne : tout doit afficher OK.")


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


def execute(db, statements, verbose=False, skip_errors=False):
    """Execute une suite d'ordres ; renvoie les resultats des SELECT.

    @param skip_errors continue apres une erreur (comme psql sans
                       ON_ERROR_STOP) et la renvoie dans la liste des erreurs.
    """
    results = []
    for statement in statements:
        upper = statement.lstrip().upper()
        try:
            cursor = db.execute(normalize(statement))
        except sqlite3.Error as error:
            if not skip_errors:
                raise
            execute.errors.append("%s : %s" % (upper.split()[0], error))
            continue
        if upper.startswith("SELECT") or upper.startswith("WITH"):
            headers = [column[0] for column in cursor.description]
            results.append((statement, headers, cursor.fetchall()))
        elif verbose:
            print("   %s ... %s ligne(s)" % (upper.split()[0], cursor.rowcount if cursor.rowcount >= 0 else "?"))
    return results


execute.errors = []


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


def collect(results, header):
    """Fusionne les lignes de toutes les requetes dont la 1re colonne est `header`."""
    merged = {}
    for _statement, headers, rows in results:
        if headers[0] != header:
            continue
        for row in rows:
            merged[row[0]] = row[-1]
    return merged


def scenario_transfert(checker):
    """Les fichiers SQL du module, executes sur deux schemas."""
    diagnostic = os.path.join(ROOT, "sql", "diagnostic-affaire-transfert.sql")
    reprise = os.path.join(ROOT, "sql", "reprise-affaire-transfert.sql")
    diagnostic_lignes = os.path.join(ROOT, "sql", "diagnostic-affaire-lignes.sql")
    reprise_lignes = os.path.join(ROOT, "sql", "reprise-affaire-lignes.sql")
    attendu = os.path.join(ROOT, "sql", "attendu-reprise.sql")

    print("=== Fichiers SQL du module, executes dans SQLite ===")
    for path in (diagnostic, reprise, diagnostic_lignes, reprise_lignes, attendu):
        print("    %s" % os.path.relpath(path, ROOT))
    print()

    # ------------------------------------------------------------------ 1
    print("1. Schema du client : DEVIS porte ID_DEVIS, deux tableaux de lignes avec la colonne")
    db = create_database("client")
    fixture_transfert(db)
    print()
    print("2. Le jeu de donnees reproduit bien la panne")
    for table, row_id, affair, label in BEFORE_REPRISE:
        checker.check(label, affair, affair_of(db, table, row_id))

    print()
    print("3. Diagnostic AVANT reprise (lecture seule)")
    statements = read_script(diagnostic)
    results = execute(db, statements)
    checker.check("une requete par cas : aucune requete en echec", len(statements), len(results))
    cas = collect(results, "cas")
    for label, nombre in sorted(cas.items()):
        print("   %-58s %d" % (label, nombre))
    checker.check("§1 : deux saisies d'achat a reparer", 2,
                  cas.get("SAISIE_ACHAT <- COMMANDE (SOURCE / IDSOURCE)"))
    checker.check("§1 : une saisie depuis un bon de reception", 1,
                  cas.get("SAISIE_ACHAT <- BON_RECEPTION (SOURCE / IDSOURCE)"))
    checker.check("§2 : deux factures depuis une commande", 2, cas.get("FACTURE_FOURNISSEUR <- COMMANDE (via TR_COMMANDE)"))
    checker.check("§2 : une facture depuis un bon de reception", 1, cas.get("FACTURE_FOURNISSEUR <- BON_RECEPTION (via TR_BON_RECEPTION)"))
    checker.check("§2 : une commande depuis un devis", 1, cas.get("COMMANDE <- DEVIS (via TR_DEVIS)"))
    checker.check("§2 : la jointure du devis utilise ID_DEVIS", True,
                  any("DEVIS\".\"ID_DEVIS\"" in statement
                      for statement in read_script(diagnostic)))
    checker.check("§2 : dix-sept transferts testes", 17, len(cas) - 2)
    checker.check("§3 : tableaux de lignes avec la colonne",
                  ["DEMANDE_ACHAT_ELEMENT", "FACTURE_FOURNISSEUR_ELEMENT"],
                  [row[0] for _s, h, rows in results if h[0] == "table_lignes" for row in rows])
    checker.check("§4 : sept tables de transfert", 7,
                  len([row for _s, h, rows in results if h[0] == "table_name" for row in rows]))
    documents = collect(results, "document")
    checker.check("§5 : factures fournisseur sans affaire", 4, documents.get("FACTURE_FOURNISSEUR"))
    checker.check("§5 : commandes sans affaire", 5, documents.get("COMMANDE"))
    checker.check("le diagnostic n'a rien ecrit", None, affair_of(db, "FACTURE_FOURNISSEUR", 900))

    print()
    print("4. Reprise des en-tetes")
    statements = read_script(reprise)
    checker.check("une transaction par bloc", 19,
                  len([statement for statement in statements if statement.upper().startswith("BEGIN")]))
    checker.check("la reprise ne touche aucun tableau de lignes", 0,
                  len([statement for statement in statements if "_ELEMENT" in statement]))
    execute(db, statements)
    print()
    print("5. Resultat")
    for table, row_id, affair, label in AFTER_REPRISE:
        checker.check(label, affair, affair_of(db, table, row_id))
    checker.check("les lignes n'ont pas ete touchees par ce fichier", None,
                  affair_of(db, "FACTURE_FOURNISSEUR_ELEMENT", 5100))

    print()
    print("6. Rejeu (idempotence)")
    state = snapshot(db)
    execute(db, read_script(reprise))
    checker.check("aucune valeur modifiee au second passage", state, snapshot(db))
    results = execute(db, read_script(diagnostic))
    cas = collect(results, "cas")
    restant = {label: nombre for label, nombre in cas.items() if nombre}
    checker.check("plus aucun document a reprendre", {}, restant)
    documents = collect(results, "document")
    checker.check("il ne reste que les documents sans source",
                  {"COMMANDE": 2, "BON_RECEPTION": 2, "SAISIE_ACHAT": 2, "FACTURE_FOURNISSEUR": 1,
                   "AVOIR_FOURNISSEUR": 0, "DEVIS": 0, "COMMANDE_CLIENT": 0,
                   "SAISIE_VENTE_FACTURE": 0, "AVOIR_CLIENT": 0, "BON_DE_LIVRAISON": 0},
                  documents)
    db.close()

    # ------------------------------------------------------------------ 7
    print()
    print("7. Fichiers lignes, sur une base ou les 12 tableaux ont la colonne")
    db = create_database("all")
    fixture_transfert(db)
    execute(db, read_script(reprise))
    results = execute(db, read_script(diagnostic_lignes))
    checker.check("diagnostic lignes : 12 tableaux listes", 12,
                  len([row for _s, h, rows in results if h[0] == "table_name" for row in rows]))
    a_reprendre = collect(results, "table_lignes")
    checker.check("lignes a reprendre : 12 tableaux", 12, len(a_reprendre))
    checker.check("la ligne de commande 251 est a reprendre", 2, a_reprendre.get("COMMANDE_ELEMENT"))
    checker.check("une seule ligne de facture a reprendre (5100)", 1,
                  a_reprendre.get("FACTURE_FOURNISSEUR_ELEMENT"))
    execute(db, read_script(reprise_lignes))
    for table, row_id, affair, label in AFTER_REPRISE_LIGNES:
        checker.check(label, affair, affair_of(db, table, row_id))
    state = snapshot(db)
    execute(db, read_script(reprise_lignes))
    checker.check("reprise des lignes idempotente", state, snapshot(db))
    results = execute(db, read_script(diagnostic_lignes))
    checker.check("plus une seule ligne a reprendre", {},
                  {label: nombre for label, nombre in collect(results, "table_lignes").items() if nombre})
    db.close()

    # ------------------------------------------------------------------ 8
    print()
    print("8. sql/attendu-reprise.sql (ce que le menu doit annoncer)")
    db = create_database("client")
    fixture_transfert(db)
    results = execute(db, read_script(attendu))
    total = [row[0] for _s, _h, rows in results for row in rows][0]
    # detail : 2 saisies d'achat depuis une commande + 2 factures + 1 bon de
    # reception + 4 transferts du devis + 2 depuis la commande client + 2 depuis
    # la facture de vente + 1 avoir = 13 (dont 10 hors devis)
    checker.check("13 documents reparables, devis compris", 13, total)
    db.close()

    # ------------------------------------------------------------------ 9
    print()
    print("9. Base ou DEVIS n'a aucune colonne de cle")
    db = create_database("client", devis_key=None)
    fixture_transfert(db)
    execute.errors = []
    results = execute(db, read_script(diagnostic), skip_errors=True)
    cas = collect(results, "cas")
    checker.check("quatre cas en echec (les quatre transferts du devis)", 4, len(execute.errors))
    checker.check("tous les autres cas sont affiches", 15, len(cas))
    checker.check("les factures depuis une commande restent diagnostiquees", 2,
                  cas.get("FACTURE_FOURNISSEUR <- COMMANDE (via TR_COMMANDE)"))
    execute.errors = []
    execute(db, read_script(reprise), skip_errors=True)
    checker.check("seuls les blocs du devis echouent", 4, len(execute.errors))
    checker.check("les factures sont reprises malgre l'erreur sur DEVIS", 11870,
                  affair_of(db, "FACTURE_FOURNISSEUR", 900))
    checker.check("la saisie d'achat est reprise", 11870, affair_of(db, "SAISIE_ACHAT", 700))
    db.close()

    print()
    print("9 bis. La cle du devis est bien celle de la base mesuree")
    contenu = "\n".join(read_script(reprise))
    # 4 blocs du devis, chacun citant DEVIS.ID_DEVIS dans le JOIN et dans le WHERE
    checker.check("les blocs du devis joignent ID_DEVIS", 8, contenu.count('"DEVIS"."ID_DEVIS"'))
    checker.check("aucun bloc ne joint DEVIS.ID", 0, contenu.count('"DEVIS"."ID" ='))
    db = create_database("client", devis_key="ID_DEVIS")
    fixture_transfert(db)
    execute.errors = []
    execute(db, read_script(reprise), skip_errors=True)
    checker.check("aucune erreur sur la base du client", 0, len(execute.errors))
    checker.check("la commande issue du devis est reprise", 777, affair_of(db, "COMMANDE", 255))
    checker.check("la commande client issue du devis est reprise", 777, affair_of(db, "COMMANDE_CLIENT", 800))
    db.close()

    # ------------------------------------------------------------------ 10
    print()
    print("10. Cas limite : base sans aucune table de transfert")
    db = create_database("client")
    for table in TRANSFER_TABLES:
        db.execute('DROP TABLE "%s"."%s"' % (SCHEMA, table))
        db.execute("DELETE FROM information_schema.tables WHERE table_name = ?", (table,))
        db.execute("DELETE FROM information_schema.columns WHERE table_name = ?", (table,))
    fixture_sans_transfert(db)
    execute.errors = []
    execute(db, read_script(reprise), skip_errors=True)
    checker.check("seuls les blocs des tables de transfert echouent", 17, len(execute.errors))
    checker.check("la saisie d'achat (SOURCE / IDSOURCE) est quand meme reprise", 11870,
                  affair_of(db, "SAISIE_ACHAT", 700))
    db.close()

    return checker.report()


def fixture_sans_transfert(db):
    """Base minimale : une commande, une saisie d'achat nee de cette commande."""
    insert(db, "COMMANDE", ID=251, ID_AFFAIRE=11870)
    insert(db, "SAISIE_ACHAT", ID=700, ID_AFFAIRE=None, SOURCE="COMMANDE", IDSOURCE=251)
def check_zero(checker, section, rows):
    remaining = {row[0]: row[-1] for row in rows if row[-1] != 0}
    checker.check("%s : plus rien a reprendre" % section, {}, remaining)


# --------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="Execute les fichiers SQL du module dans SQLite.")
    parser.add_argument("--file", help="fichier SQL a executer (au lieu du scenario complet)")
    parser.add_argument("--fixture", default="affaire-transfert", help="jeu de donnees a charger")
    parser.add_argument("--keep", action="store_true", help="affiche toutes les lignes produites")
    parser.add_argument("--affaire", type=int, help="numero d'affaire a substituer dans le fichier (--file)")
    parser.add_argument("--devis-key", default="ID_DEVIS", help="colonne de cle de DEVIS (ID_DEVIS sur la base du client)")
    parser.add_argument("--line-columns", choices=("client", "all"), default="client",
                        help="colonnes ID_AFFAIRE des tableaux de lignes (defaut : comme la base du client)")
    parser.add_argument("--emit-fixture", action="store_true", help="ecrit le jeu de donnees en SQL PostgreSQL")
    parser.add_argument("--emit-checks", action="store_true", help="ecrit les verifications finales en SQL PostgreSQL")
    parser.add_argument("--emit-before-checks", action="store_true", help="ecrit les verifications de la base de test")
    args = parser.parse_args()

    if args.emit_fixture:
        emit_fixture(args.line_columns, args.devis_key)
        return 0
    if args.emit_checks:
        emit_checks()
        return 0
    if args.emit_before_checks:
        emit_before_checks()
        return 0

    if args.file:
        db = create_database(args.line_columns)
        FIXTURES[args.fixture](db)
        statements = read_script(args.file)
        if args.affaire is not None:
            # les fichiers SQL du module portent le numero d'affaire en clair
            statements = [re.sub(r"select\s+\d+\s+as\s+numero", "select %d as numero" % args.affaire, statement)
                          for statement in statements]
        results = execute(db, statements)
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
