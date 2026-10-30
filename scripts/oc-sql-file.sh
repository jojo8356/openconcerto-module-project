#!/usr/bin/env sh
# Execute les fichiers SQL du module sur une base jetable.
#
# Trois moteurs, memes fichiers, memes controles :
#
#   --sqlite    (defaut quand Docker n'est pas disponible)
#               SQLite en memoire, via tools/oc_sql_sqlite.py. Aucune
#               installation, quelques secondes : c'est le mode a utiliser pour
#               verifier une modification de sql/*.sql.
#
#   --docker    vrai PostgreSQL, dans un conteneur jetable (postgres:16-alpine).
#               C'est la base reelle du client : ce mode valide le SQL tel qu'il
#               sera execute chez lui, y compris les transactions.
#
#   --postgres  vrai PostgreSQL deja demarre, decrit par les variables libpq
#               standard (PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE).
#               A n'utiliser QUE sur une base jetable : le scenario cree le
#               schema OpenConcerto42 et y ecrit. Jamais sur la base du client.
#
# Exemples
# --------
#   sh scripts/oc-sql-file.sh                       # scenario complet, SQLite
#   sh scripts/oc-sql-file.sh --docker              # scenario complet, PostgreSQL
#   sh scripts/oc-sql-file.sh --sqlite --file sql/diagnostic-affaire-transfert.sql
#   PGHOST=localhost PGUSER=postgres PGDATABASE=oc_test \
#       sh scripts/oc-sql-file.sh --postgres
#   sh scripts/oc-sql-file.sh --dry-run             # montre les commandes
#
# Sortie : chaque controle affiche OK ou ECHEC, code de sortie 1 s'il y a un
# echec. Rien n'est installe, rien n'est conserve : le conteneur est supprime a
# la fin, meme en cas d'erreur.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

MODE=auto
FILE=
DRY_RUN=0
KEEP=0

usage() {
    sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --sqlite) MODE=sqlite ;;
        --docker) MODE=docker ;;
        --postgres) MODE=postgres ;;
        --auto) MODE=auto ;;
        --file)
            [ $# -ge 2 ] || { echo "--file attend un chemin" >&2; exit 2; }
            FILE=$2
            shift
            ;;
        --dry-run) DRY_RUN=1 ;;
        --keep) KEEP=1 ;;
        -h | --help) usage ;;
        *)
            echo "Option inconnue : $1 (voir --help)" >&2
            exit 2
            ;;
    esac
    shift
done

PYTHON=${PYTHON:-python3}
TOOL="$ROOT_DIR/tools/oc_sql_sqlite.py"
DIAGNOSTIC="$ROOT_DIR/sql/diagnostic-affaire-transfert.sql"
REPRISE="$ROOT_DIR/sql/reprise-affaire-transfert.sql"
CONTAINER=oc-sql-affaire-$$

command -v "$PYTHON" >/dev/null 2>&1 || {
    echo "python3 est necessaire (il genere le jeu de donnees)." >&2
    exit 2
}

docker_ready() {
    command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1
}

if [ "$MODE" = auto ]; then
    if [ "$DRY_RUN" = 1 ]; then
        # --dry-run sans moteur explicite : on montre le mode PostgreSQL, le
        # plus complet ; l'equivalent SQLite est rappele a la fin.
        MODE=docker
    elif docker_ready; then
        MODE=docker
    else
        MODE=sqlite
    fi
fi

if [ "$MODE" = docker ] && [ "$DRY_RUN" = 0 ] && ! docker_ready; then
    echo "Docker n'est pas disponible sur cette machine." >&2
    echo "  -> utilisez --sqlite (meme scenario, sans conteneur)" >&2
    echo "  -> ou lancez : sh scripts/oc-sql-file.sh --dry-run" >&2
    exit 2
fi

if [ "$MODE" = postgres ] && ! command -v psql >/dev/null 2>&1 && [ "$DRY_RUN" = 0 ]; then
    echo "psql est necessaire pour --postgres (paquet postgresql-client)." >&2
    exit 2
fi

# --------------------------------------------------------------------------
# Mode SQLite : tout est dans tools/oc_sql_sqlite.py
# --------------------------------------------------------------------------
if [ "$MODE" = sqlite ]; then
    if [ -n "$FILE" ]; then
        echo "=== $FILE (SQLite) ==="
        if [ "$DRY_RUN" = 1 ]; then
            echo "$PYTHON tools/oc_sql_sqlite.py --file $FILE"
            exit 0
        fi
        "$PYTHON" "$TOOL" --file "$FILE"
    else
        if [ "$DRY_RUN" = 1 ]; then
            echo "$PYTHON tools/oc_sql_sqlite.py"
            exit 0
        fi
        "$PYTHON" "$TOOL"
    fi
    exit $?
fi

# --------------------------------------------------------------------------
# Modes PostgreSQL
# --------------------------------------------------------------------------
TMP_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TMP_DIR"
    if [ "$MODE" = docker ] && [ "$KEEP" = 0 ] && [ "$DRY_RUN" = 0 ]; then
        docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT INT TERM

psql_once() {
    # $1 = fichier a executer, $2 = options supplementaires de psql (facultatif)
    extra=${2:-}
    if [ "$MODE" = docker ]; then
        # shellcheck disable=SC2086
        docker exec -i "$CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -q $extra -f - <"$1"
    else
        # shellcheck disable=SC2086
        psql -v ON_ERROR_STOP=1 -q $extra -f "$1"
    fi
}

echo "=== Scenario complet sur PostgreSQL ($MODE) ==="

if [ "$MODE" = docker ]; then
    if [ "$DRY_RUN" = 1 ]; then
        echo "  docker run -d --name $CONTAINER -e POSTGRES_PASSWORD=openconcerto -e POSTGRES_DB=openconcerto postgres:16-alpine"
    else
        docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=openconcerto -e POSTGRES_DB=openconcerto postgres:16-alpine >/dev/null
        printf 'Attente du serveur'
        ready=0
        i=0
        while [ "$i" -lt 90 ]; do
            if docker exec "$CONTAINER" pg_isready -U postgres -q >/dev/null 2>&1; then
                ready=1
                break
            fi
            printf '.'
            sleep 1
            i=$((i + 1))
        done
        printf '\n'
        if [ "$ready" = 0 ]; then
            echo "Le conteneur PostgreSQL n'a pas demarre." >&2
            docker logs --tail 30 "$CONTAINER" >&2 || true
            exit 1
        fi
    fi
else
    echo "  base : ${PGDATABASE:-$USER}@${PGHOST:-localhost}:${PGPORT:-5432}"
    if [ "$DRY_RUN" = 0 ]; then
        if psql -t -A -c "select 1 from pg_tables where schemaname = 'OpenConcerto42' limit 1" 2>/dev/null | grep -q 1; then
            echo "Le schema OpenConcerto42 existe deja dans cette base : le scenario" >&2
            echo "y ecrirait. Utilisez une base jetable (voir --help)." >&2
            exit 2
        fi
    fi
fi

echo
echo "1. Base de test (schema OpenConcerto42, jeu de donnees du module)"
"$PYTHON" "$TOOL" --emit-fixture >"$TMP_DIR/fixture.sql"
if [ "$DRY_RUN" = 1 ]; then
    echo "  $PYTHON tools/oc_sql_sqlite.py --emit-fixture | psql ... -f -"
else
    psql_once "$TMP_DIR/fixture.sql"
fi

echo "2. Diagnostic avant reprise"
if [ -n "$FILE" ]; then
    if [ "$DRY_RUN" = 1 ]; then
        echo "  psql ... -f - < $FILE"
    else
        psql_once "$FILE"
    fi
else
    if [ "$DRY_RUN" = 1 ]; then
        echo "  psql ... -f - < sql/diagnostic-affaire-transfert.sql"
    else
        psql_once "$DIAGNOSTIC"
    fi
fi

if [ -z "$FILE" ]; then
    echo
    echo "3. Reprise"
    if [ "$DRY_RUN" = 1 ]; then
        echo "  psql ... -f - < sql/reprise-affaire-transfert.sql"
        echo
        echo "4. Rejeu (idempotence)"
        echo "  psql ... -f - < sql/reprise-affaire-transfert.sql   # une seconde fois"
    else
        psql_once "$REPRISE"
        echo
        echo "4. Rejeu (idempotence)"
        psql_once "$REPRISE" >/dev/null
    fi

    echo
    echo "5. Controles"
    "$PYTHON" "$TOOL" --emit-checks >"$TMP_DIR/checks.sql"
    if [ "$DRY_RUN" = 1 ]; then
        echo "  $PYTHON tools/oc_sql_sqlite.py --emit-checks | psql ... -t -A -f -"
        echo
        echo "(mode --dry-run : aucune commande n'a ete executee)"
        echo "Equivalent sans Docker :  sh scripts/oc-sql-file.sh --sqlite"
        exit 0
    fi
    results=$(psql_once "$TMP_DIR/checks.sql" "-t -A")
    printf '%s\n' "$results" | while IFS='|' read -r label status; do
        [ -n "$label" ] || continue
        printf '   %-5s %s\n' "$status" "$label"
    done
    echecs=$(printf '%s\n' "$results" | grep -c 'ECHEC' || true)
    total=$(printf '%s\n' "$results" | grep -c 'OK\|ECHEC' || true)
    echo
    echo "Controles : $total | echecs : $echecs"
    if [ "$echecs" != 0 ]; then
        echo "ECHEC : la reprise ne fait pas ce qui est attendu sur PostgreSQL." >&2
        exit 1
    fi
    echo "OK : les fichiers SQL se comportent comme prevu sur PostgreSQL."
fi
