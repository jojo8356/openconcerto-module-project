#!/usr/bin/env sh
# Test en ligne de commande du rattachement d'affaire, sans OpenConcerto.
#
# Trois etages, du plus proche du code au plus proche de la base :
#
#   1. AffairTransferScenario   : simule le transfert d'une commande fournisseur
#                                 vers une facture et verifie que l'affaire est
#                                 recopiee (ou perdue, sans le correctif).
#   2. AffairBackfillSqlDump    : fait ecrire par le module lui-meme le plan de
#                                 reprise (comptages + UPDATE).
#   3. tests/cli/test-affaire-transfert.py
#                               : execute ce plan dans SQLite et verifie le
#                                 resultat, y compris les cas limites.
#   4. tools/oc_sql_sqlite.py   : execute les VRAIS fichiers sql/*.sql du module.
#
# Aucun serveur, aucune base reelle, aucune interface graphique : tout est
# jetable et rejouable. Sortie : OK / ECHEC par controle, code 1 en cas d'echec.
#
#   sh scripts/test-affaire-cli.sh
#   BUILD_DIR=/tmp/oc sh scripts/test-affaire-cli.sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR=${BUILD_DIR:-"$ROOT_DIR/build"}
CLI_DIR="$BUILD_DIR/cli-test"
SOURCES_FILE="$CLI_DIR/sources.txt"
PLAN_FILE="$CLI_DIR/plan-reprise.txt"

rm -rf "$CLI_DIR"
mkdir -p "$CLI_DIR"
cd "$ROOT_DIR"

have_java=1
command -v javac >/dev/null 2>&1 || have_java=0
command -v java >/dev/null 2>&1 || have_java=0

if [ "$have_java" = 1 ]; then
    {
        printf '%s\n' src/org/openconcerto/modules/project/AffairLinkSupport.java
        printf '%s\n' src/org/openconcerto/modules/project/AffairTransferSupport.java
        printf '%s\n' src/org/openconcerto/modules/project/AffairBackfillSupport.java
        printf '%s\n' src/org/openconcerto/modules/project/ItemAffairColumnRules.java
        printf '%s\n' tests/org/openconcerto/modules/project/AffairTransferScenario.java
        printf '%s\n' tests/org/openconcerto/modules/project/AffairBackfillSqlDump.java
        printf '%s\n' tests/org/openconcerto/sql/Configuration.java
        printf '%s\n' tests/org/openconcerto/sql/model/DBRoot.java
        printf '%s\n' tests/org/openconcerto/sql/model/SQLField.java
        printf '%s\n' tests/org/openconcerto/sql/model/SQLInjector.java
        printf '%s\n' tests/org/openconcerto/sql/model/SQLRowAccessor.java
        printf '%s\n' tests/org/openconcerto/sql/model/SQLRowValues.java
        printf '%s\n' tests/org/openconcerto/sql/model/SQLTable.java
    } >"$SOURCES_FILE"

    echo "=== 0. Compilation des tests en ligne de commande ==="
    javac -J-XX:-UsePerfData -proc:none -encoding UTF-8 -cp src -d "$CLI_DIR" @"$SOURCES_FILE"
    echo "   OK    compilation"

    echo
    echo "=== 1. Transfert commande fournisseur -> facture ==="
    java -cp "$CLI_DIR" org.openconcerto.modules.project.AffairTransferScenario
else
    echo "=== 0. JDK absent : les deux premiers etages sont ignores ==="
    echo "   (installez un JDK 8+, ou lancez ce test dans le conteneur OpenConcerto)"
fi

echo
echo "=== 2. Plan de reprise ecrit par le module ==="
if [ "$have_java" = 1 ]; then
    java -cp "$CLI_DIR" org.openconcerto.modules.project.AffairBackfillSqlDump >"$PLAN_FILE" 2>"$CLI_DIR/plan.log"
    reprises=$(grep -c '^UPDATE|' "$PLAN_FILE" || true)
    echo "   OK    $reprises reprises generees ($(grep -c '^TABLE|' "$PLAN_FILE") tables decrites)"

    echo
    echo "=== 3. Plan de reprise execute dans SQLite ==="
    python3 tests/cli/test-affaire-transfert.py "$PLAN_FILE"
else
    echo "   (ignore : pas de JDK)"
fi

echo
echo "=== 4. Fichiers SQL du module (sql/*.sql) ==="
python3 tools/oc_sql_sqlite.py

echo
echo "=== Termine : tous les controles sont verts. ==="
echo
echo "Pour un essai sur la vraie base (lecture seule d'abord) :"
echo "  sh scripts/oc-psql.sh -f sql/diagnostic-affaire-transfert.sql"
echo "  sh scripts/oc-psql.sh -f sql/reprise-affaire-transfert.sql   # ecrit (transactionnel)"
echo "Sur PostgreSQL, sans toucher a votre base :  sh scripts/oc-sql-file.sh --docker"
