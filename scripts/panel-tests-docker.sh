#!/usr/bin/env bash
#
# Suite de tests des panneaux du module project contre la base DOCKER/PODMAN
# du poste (la stack ~/oc-176-podman), et non contre la VM.
#
# La base est publiee sur 127.0.0.1:5433 par la stack : le poste y accede
# directement, aucun tunnel SSH n'est necessaire.
#
# Si le poste n'a pas de JDK, la compilation ET l'execution se font dans un
# conteneur JDK (image docker.io/library/eclipse-temurin:17-jdk) qui partage
# l'espace de reseau du conteneur PostgreSQL : la connexion se fait alors sur
# 127.0.0.1:5432, vue de l'interieur de ce reseau.
#
# Lecture seule : aucune ecriture n'est faite dans la base.
#
# Usage :
#   bash scripts/panel-tests-docker.sh [options]
#
# Options :
#   --stack DIR     dossier de la stack  (defaut : ~/oc-176-podman)
#   --host HOTE     hote PostgreSQL      (defaut : 127.0.0.1)
#   --port PORT     port publie          (defaut : PG_HOST_PORT du .env, sinon 5433)
#   --db BASE       base                 (defaut : POSTGRES_DB du .env, sinon OpenConcerto)
#   --user ROLE     role SQL             (defaut : POSTGRES_USER du .env, sinon openconcerto)
#   --schemas LIST  schemas a controler, separes par des virgules
#   --mode MODE     auto | local | container   (defaut : auto)
#   --jdk IMAGE     image JDK du mode conteneur
#                   (defaut : docker.io/library/eclipse-temurin:17-jdk)
#   --jdbc JAR      pilote JDBC a utiliser (sinon recherche automatique)
#   --no-start      ne pas demarrer la stack si elle est arretee
#   -h|--help       cette aide
#
# Sortie : 0 si tous les controles passent, 1 sinon (comme la suite elle-meme).
#
set -uo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SRC_DIR="$REPO_DIR/tests/org/openconcerto/modules/project/panels"
BUILD_DIR="$REPO_DIR/build"
CLASSES_DIR="$BUILD_DIR/panel-test-classes"
MAIN_CLASS=org.openconcerto.modules.project.panels.TestRunner
NEED_TOOLS=97

STACK_DIR=${STACK_DIR:-$HOME/oc-176-podman}
DB_HOST=127.0.0.1
DB_PORT=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
SCHEMAS=""
MODE=auto
JDK_IMAGE=docker.io/library/eclipse-temurin:17-jdk
JDBC_JAR=""
ALLOW_START=1

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '  ATTENTION : %s\n' "$*" >&2; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '/^# Options/,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --stack) STACK_DIR="$2"; shift 2 ;;
        --host) DB_HOST="$2"; shift 2 ;;
        --port) DB_PORT="$2"; shift 2 ;;
        --db) DB_NAME="$2"; shift 2 ;;
        --user) DB_USER="$2"; shift 2 ;;
        --schemas) SCHEMAS="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --jdk) JDK_IMAGE="$2"; shift 2 ;;
        --jdbc) JDBC_JAR="$2"; shift 2 ;;
        --no-start) ALLOW_START=0; shift ;;
        -h|--help) usage ;;
        *) echo "option inconnue : $1" >&2; usage >&2 ;;
    esac
done

case "$MODE" in
    auto|local|container) ;;
    *) die "mode invalide : $MODE (auto, local ou container)" ;;
esac

# ------------------------------------------------- configuration de la stack
ENV_FILE="$STACK_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    [ -n "$DB_PORT" ] || DB_PORT=$(sed -n 's/^PG_HOST_PORT=//p' "$ENV_FILE" | head -1 | tr -d '\r')
    [ -n "$DB_NAME" ] || DB_NAME=$(sed -n 's/^POSTGRES_DB=//p' "$ENV_FILE" | head -1 | tr -d '\r')
    [ -n "$DB_USER" ] || DB_USER=$(sed -n 's/^POSTGRES_USER=//p' "$ENV_FILE" | head -1 | tr -d '\r')
    [ -n "$DB_PASSWORD" ] || DB_PASSWORD=$(sed -n 's/^POSTGRES_PASSWORD=//p' "$ENV_FILE" | head -1 | tr -d '\r')
else
    warn "pas de .env dans $STACK_DIR : les valeurs par defaut sont utilisees"
fi
DB_PORT=${DB_PORT:-5433}
DB_NAME=${DB_NAME:-OpenConcerto}
DB_USER=${DB_USER:-openconcerto}

info "stack      : $STACK_DIR"
info "base       : $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"

# ------------------------------------------------------------------ runtime
command -v podman >/dev/null 2>&1 \
    || die "podman est introuvable. Cette cible est la stack Podman du poste (~/oc-176-podman)."
PODMAN=podman

# --------------------------------------------------- conteneur PostgreSQL
db_container_id() {
    local cid
    cid=$($PODMAN ps -q --filter "name=^openconcerto176-db\$" 2>/dev/null | head -n 1)
    if [ -z "$cid" ]; then
        cid=$($PODMAN ps -q --filter "name=openconcerto176-db" 2>/dev/null | head -n 1)
    fi
    if [ -z "$cid" ] && [ -f "$STACK_DIR/compose.yaml" ]; then
        cid=$(cd "$STACK_DIR" && $PODMAN compose -p openconcerto176 -f compose.yaml ps -q db 2>/dev/null | head -n 1)
    fi
    printf '%s' "$cid"
}

CID=$(db_container_id)
if [ -z "$CID" ]; then
    if [ "$ALLOW_START" -eq 0 ]; then
        die "le conteneur PostgreSQL n'est pas demarre (stack $STACK_DIR)."
    fi
    log "Stack arretee : demarrage"
    if [ -f "$SCRIPT_DIR/podman-openconcerto.sh" ]; then
        bash "$SCRIPT_DIR/podman-openconcerto.sh" --dir "$STACK_DIR" up || die "demarrage de la stack impossible"
    else
        (cd "$STACK_DIR" && $PODMAN compose -p openconcerto176 -f compose.yaml up -d) || die "demarrage de la stack impossible"
    fi
    CID=$(db_container_id)
    [ -n "$CID" ] || die "conteneur PostgreSQL introuvable apres demarrage"
fi
info "conteneur  : $($PODMAN inspect -f '{{.Name}}' "$CID" 2>/dev/null | sed 's|^/||')"

log "Attente de PostgreSQL"
ready=0
i=0
while [ "$i" -lt 60 ]; do
    if $PODMAN exec -i "$CID" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
        ready=1
        break
    fi
    i=$((i + 1))
    sleep 1
done
[ "$ready" -eq 1 ] || die "PostgreSQL ne repond pas (voir : $PODMAN logs openconcerto176-db)"
info "PostgreSQL pret"

# ---------------------------------------------------------- outils locaux
find_javac() {
    if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/javac" ]; then
        printf '%s' "$JAVA_HOME/bin/javac"
        return 0
    fi
    if command -v javac >/dev/null 2>&1; then
        command -v javac
        return 0
    fi
    return 1
}

find_java() {
    if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
        printf '%s' "$JAVA_HOME/bin/java"
        return 0
    fi
    if command -v java >/dev/null 2>&1; then
        command -v java
        return 0
    fi
    return 1
}

# Cherche un pilote PostgreSQL utilisable : JAR explicite, ~/.m2, /usr/share/java,
# ou un JAR du client OpenConcerto qui contient org/postgresql/Driver.class.
find_driver() {
    if [ -n "$JDBC_JAR" ] && [ -f "$JDBC_JAR" ]; then
        printf '%s' "$JDBC_JAR"
        return 0
    fi
    local candidate
    for candidate in \
        "$HOME"/.m2/repository/org/postgresql/postgresql/*/postgresql-*.jar \
        /usr/share/java/postgresql*.jar \
        /usr/share/java/*/postgresql*.jar; do
        if [ -f "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    for candidate in "$HOME"/OpenConcerto*/lib/*.jar "$HOME"/OpenConcerto*/*.jar; do
        if [ -f "$candidate" ] && grep -q -a "org/postgresql/Driver.class" "$candidate" 2>/dev/null; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

DRIVER=$(find_driver || true)

# ------------------------------------------------------------- mode local
run_local() {
    local javac java
    javac=$(find_javac || true)
    java=$(find_java || true)
    if [ -z "$javac" ] || [ -z "$java" ]; then
        info "aucun JDK (javac) sur ce poste"
        return "$NEED_TOOLS"
    fi

    log "Compilation locale ($("$javac" -version 2>&1 | head -1))"
    rm -rf "$CLASSES_DIR"
    mkdir -p "$CLASSES_DIR"
    local sources="$BUILD_DIR/panel-test-sources.txt"
    mkdir -p "$BUILD_DIR"
    find "$SRC_DIR" -name '*.java' -type f | sort > "$sources"
    "$javac" -proc:none -encoding UTF-8 -d "$CLASSES_DIR" "@$sources" || return "$NEED_TOOLS"

    local cp="$CLASSES_DIR"
    if [ -n "$DRIVER" ]; then
        info "pilote JDBC : $DRIVER"
        cp="$cp:$DRIVER"
    elif command -v psql >/dev/null 2>&1; then
        info "transport psql : $(command -v psql)"
    else
        info "ni pilote JDBC ni psql sur ce poste : execution en mode conteneur"
        return "$NEED_TOOLS"
    fi

    log "Execution de la suite (lecture seule)"
    export PGPASSWORD="$DB_PASSWORD"
    export PGHOST="$DB_HOST"
    export PGPORT="$DB_PORT"
    export PGDATABASE="$DB_NAME"
    export PGUSER="$DB_USER"
    local args=(--host "$DB_HOST" --port "$DB_PORT" --db "$DB_NAME" --user "$DB_USER")
    [ -n "$SCHEMAS" ] && args+=(--schemas "$SCHEMAS")
    "$java" -cp "$cp" "$MAIN_CLASS" "${args[@]}"
    return $?
}

# ----------------------------------------------------------- mode conteneur
run_container() {
    log "Compilation et execution dans un conteneur JDK ($JDK_IMAGE)"
    local mount_driver=()
    if [ -n "$DRIVER" ]; then
        info "pilote JDBC monte : $DRIVER"
        mount_driver=(--volume "$DRIVER:/driver/driver.jar:ro")
    else
        info "pas de pilote JDBC : postgresql-client sera installe dans le conteneur"
    fi
    # L'espace de reseau du conteneur PostgreSQL est partage : 127.0.0.1:5432
    # y est la base, quel que soit le port publie sur le poste.
    local script='set -e
DB_NAME=$1
DB_USER=$2
SCHEMAS=$3
if [ ! -f /driver/driver.jar ]; then
  apt-get update -qq >/dev/null 2>&1 || true
  apt-get install -y --no-install-recommends postgresql-client >/dev/null 2>&1 || true
fi
mkdir -p /src/build/panel-test-classes
find /src/tests/org/openconcerto/modules/project/panels -name "*.java" -type f | sort > /src/build/panel-test-sources.txt
javac -proc:none -encoding UTF-8 -d /src/build/panel-test-classes @/src/build/panel-test-sources.txt
CP=/src/build/panel-test-classes
if [ -f /driver/driver.jar ]; then CP="$CP:/driver/driver.jar"; fi
export PGPASSWORD="$PGPASSWORD" PGHOST=127.0.0.1 PGPORT=5432 PGDATABASE="$DB_NAME" PGUSER="$DB_USER"
if [ -f /driver/driver.jar ]; then
  java -cp "$CP" org.openconcerto.modules.project.panels.TestRunner --url "jdbc:postgresql://127.0.0.1:5432/$DB_NAME" --user "$DB_USER" --password "$PGPASSWORD" ${SCHEMAS:+--schemas $SCHEMAS}
else
  java -cp "$CP" org.openconcerto.modules.project.panels.TestRunner --host 127.0.0.1 --port 5432 --db "$DB_NAME" --user "$DB_USER" --password "$PGPASSWORD" ${SCHEMAS:+--schemas $SCHEMAS}
fi'
    $PODMAN run --rm \
        --network "container:$CID" \
        --volume "$REPO_DIR:/src" \
        "${mount_driver[@]}" \
        --workdir /src \
        --env "PGPASSWORD=$DB_PASSWORD" \
        "$JDK_IMAGE" \
        sh -c "$script" sh "$DB_NAME" "$DB_USER" "$SCHEMAS"
    return $?
}

case "$MODE" in
    local)
        run_local
        CODE=$?
        ;;
    container)
        run_container
        CODE=$?
        ;;
    auto)
        run_local
        CODE=$?
        if [ "$CODE" -eq "$NEED_TOOLS" ]; then
            warn "bascule en mode conteneur"
            run_container
            CODE=$?
        fi
        ;;
esac

echo
if [ "$CODE" -eq 0 ]; then
    echo "RESULTAT : la suite passe (aucune donnee cachee detectee) sur $DB_HOST:$DB_PORT/$DB_NAME."
else
    echo "RESULTAT : la suite a detecte des problemes (code $CODE) sur $DB_HOST:$DB_PORT/$DB_NAME : voir le detail ci-dessus."
fi
exit "$CODE"
