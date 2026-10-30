#!/usr/bin/env sh
# Test en ligne de commande du rattachement d'affaire, sans OpenConcerto.
#
# Quatre etages, du plus proche du code au plus proche de la base :
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
# Sans JDK sur la machine, les deux premiers etages tournent dans un conteneur
# jetable (eclipse-temurin:8-jdk) si Docker est disponible. Sinon ils sont
# ignores : les etages SQL restent verifiables.
#
#   sh scripts/test-affaire-cli.sh
#   sh scripts/test-affaire-cli.sh --dry-run        # montre les commandes
#   JAVA_MODE=docker sh scripts/test-affaire-cli.sh
#   BUILD_DIR=/tmp/oc sh scripts/test-affaire-cli.sh
set -eu

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h | --help)
            sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Option inconnue : $arg (voir --help)" >&2
            exit 2
            ;;
    esac
done

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

# Sans JDK sur la machine, on utilise celui d'un conteneur jetable (Docker).
# Variable d'environnement : JAVA_MODE=native, docker ou auto (defaut).
JAVA_MODE=${JAVA_MODE:-auto}
JAVA_IMAGE=${JAVA_IMAGE:-eclipse-temurin:8-jdk}
if [ "$JAVA_MODE" = auto ]; then
    if [ "$have_java" = 1 ]; then
        JAVA_MODE=native
    elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        JAVA_MODE=docker
    else
        JAVA_MODE=none
    fi
fi
if [ "$JAVA_MODE" = docker ]; then
    have_java=1
fi

# Execution de javac / java, sur la machine ou dans le conteneur.
run_javac() {
    if [ "$DRY_RUN" = 1 ]; then
        echo "  javac [$JAVA_MODE] $*"
        return 0
    fi
    if [ "$JAVA_MODE" = docker ]; then
        # --user : les classes compilees appartiennent a l'utilisateur, pas a root
        docker run --rm --user "$(id -u):$(id -g)" -v "$ROOT_DIR":"$ROOT_DIR" -w "$ROOT_DIR" "$JAVA_IMAGE" javac "$@"
    else
        javac -J-XX:-UsePerfData "$@"
    fi
}

run_java() {
    if [ "$DRY_RUN" = 1 ]; then
        echo "  java [$JAVA_MODE] $*"
        return 0
    fi
    if [ "$JAVA_MODE" = docker ]; then
        docker run --rm --user "$(id -u):$(id -g)" -v "$ROOT_DIR":"$ROOT_DIR" -w "$ROOT_DIR" "$JAVA_IMAGE" java "$@"
    else
        java "$@"
    fi
}

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
    run_javac -proc:none -encoding UTF-8 -cp src -d "$CLI_DIR" @"$SOURCES_FILE"
    echo "   OK    compilation"

    echo
    echo "=== 1. Transfert commande fournisseur -> facture ==="
    run_java -cp "$CLI_DIR" org.openconcerto.modules.project.AffairTransferScenario
else
    echo "=== 0. Ni JDK ni Docker : les deux premiers etages sont ignores ==="
    echo "   (installez un JDK 8+ : apt install default-jdk, ou Docker)"
fi

if [ "$have_java" = 1 ]; then
    echo "   (compilation et execution : $JAVA_MODE${JAVA_MODE:+ }$( [ "$JAVA_MODE" = docker ] && echo "$JAVA_IMAGE" || true ))"
fi

echo
echo "=== 2. Plan de reprise ecrit par le module ==="
if [ "$have_java" = 1 ]; then
    if [ "$DRY_RUN" = 1 ]; then
        run_java -cp "$CLI_DIR" org.openconcerto.modules.project.AffairBackfillSqlDump
        echo
        echo "(mode --dry-run : rien n'a ete compile ni execute)"
        exit 0
    fi
    run_java -cp "$CLI_DIR" org.openconcerto.modules.project.AffairBackfillSqlDump >"$PLAN_FILE" 2>"$CLI_DIR/plan.log"
    reprises=$(grep -c '^UPDATE|' "$PLAN_FILE" || true)
    echo "   OK    $reprises reprises generees ($(grep -c '^TABLE|' "$PLAN_FILE") tables decrites)"

    echo
    echo "=== 3. Plan de reprise execute dans SQLite ==="
    python3 tests/cli/test-affaire-transfert.py "$PLAN_FILE"
else
    echo "   (ignore : ni JDK ni Docker)"
fi

echo
echo "=== 4. Fichiers SQL du module (sql/*.sql) ==="
python3 tools/oc_sql_sqlite.py

echo
echo "=== 5. sql/historique-affaire.sql (fenetre « Historique affaires ») ==="
# Le fichier porte un numero d'affaire en clair ; on le remplace par une affaire
# du jeu de donnees pour verifier qu'il liste bien les documents.
if python3 tools/oc_sql_sqlite.py --file sql/historique-affaire.sql --affaire 11870 | grep -qF 'COMMANDE | 1'; then
    echo "   OK    liste les documents de l'affaire 11870 (commande + 3 lignes)"
else
    echo "   ECHEC le fichier n'a pas liste la commande de l'affaire 11870"
    exit 1
fi

echo
echo "=== Termine : tous les controles sont verts. ==="
echo
echo "Pour un essai sur la vraie base (lecture seule d'abord) :"
echo "  sh scripts/oc-psql.sh -f sql/diagnostic-affaire-transfert.sql"
echo "  sh scripts/oc-psql.sh -f sql/reprise-affaire-transfert.sql   # ecrit (transactionnel)"
echo "Sur PostgreSQL, sans toucher a votre base :  sh scripts/oc-sql-file.sh --docker"
