#!/usr/bin/env bash
#
# Suite de tests des panneaux du module project contre la base DOCKER (ou
# Podman) du poste, et non contre la VM.
#
# La base est publiee sur 127.0.0.1:5433 par la stack : le poste y accede
# directement, aucun tunnel SSH n'est necessaire.
#
# Le runtime est detecte : podman s'il est present, sinon docker. Les deux ne
# sont jamais melanges (podman n'appelle jamais le binaire docker).
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
#   --port PORT     port publie          (defaut : PG_HOST_PORT du .env ou du conteneur, sinon 5433)
#   --db BASE       base                 (defaut : POSTGRES_DB du .env ou du conteneur, sinon OpenConcerto)
#   --user ROLE     role SQL             (defaut : POSTGRES_USER du .env ou du conteneur, sinon openconcerto)
#   --password MDP  mot de passe         (defaut : PGPASSWORD, sinon le .env, sinon l'environnement du conteneur)
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
PASSWORD_SOURCE=""
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
        --password) DB_PASSWORD="$2"; shift 2 ;;
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

# ------------------------------------------------------------------ runtime
# Podman si present, sinon docker. On n'utilise jamais les deux en meme temps.
if command -v podman >/dev/null 2>&1; then
    RUNTIME=podman
elif command -v docker >/dev/null 2>&1; then
    RUNTIME=docker
else
    die "ni podman ni docker n'est disponible sur ce poste."
fi

# Fichier de composition de la stack (s'il existe).
COMPOSE_FILE=""
for candidate in \
    "$STACK_DIR/compose.yaml" \
    "$STACK_DIR/compose.yml" \
    "$STACK_DIR/docker-compose.yml" \
    "$STACK_DIR/docker-compose.yaml" \
    "$STACK_DIR"/docker/openconcerto-1.7.6/docker-compose.yml \
    "$STACK_DIR"/docker/openconcerto-1.7.6/docker-compose.yaml; do
    if [ -f "$candidate" ]; then
        COMPOSE_FILE="$candidate"
        break
    fi
done

compose_cmd() {
    if $RUNTIME compose version >/dev/null 2>&1; then
        printf '%s' "$RUNTIME compose"
    elif [ "$RUNTIME" = podman ] && command -v podman-compose >/dev/null 2>&1; then
        printf '%s' podman-compose
    elif [ "$RUNTIME" = docker ] && command -v docker-compose >/dev/null 2>&1; then
        printf '%s' docker-compose
    else
        printf '%s' ""
    fi
}

# --------------------------------------------------- conteneur PostgreSQL
db_container_id() {
    local cid
    cid=$($RUNTIME ps -q --filter "name=openconcerto176-db" 2>/dev/null | head -n 1)
    if [ -z "$cid" ] && [ -n "$COMPOSE_FILE" ]; then
        local cc
        cc=$(compose_cmd)
        if [ -n "$cc" ]; then
            cid=$(cd "$(dirname "$COMPOSE_FILE")" && $cc -p openconcerto176 -f "$COMPOSE_FILE" ps -q db 2>/dev/null | head -n 1)
        fi
    fi
    if [ -z "$cid" ]; then
        # dernier recours : n'importe quel conteneur postgres qui tourne
        cid=$($RUNTIME ps -q --filter "ancestor=postgres" 2>/dev/null | head -n 1)
    fi
    printf '%s' "$cid"
}

CID=$(db_container_id)
if [ -z "$CID" ]; then
    if [ "$ALLOW_START" -eq 0 ]; then
        die "le conteneur PostgreSQL n'est pas demarre (stack $STACK_DIR)."
    fi
    log "Stack arretee : demarrage"
    started=0
    if [ -n "$COMPOSE_FILE" ]; then
        cc=$(compose_cmd)
        if [ -n "$cc" ]; then
            (cd "$(dirname "$COMPOSE_FILE")" && $cc -p openconcerto176 -f "$COMPOSE_FILE" up -d) && started=1
        fi
    fi
    if [ "$started" -eq 0 ] && [ "$RUNTIME" = podman ] && [ -f "$SCRIPT_DIR/podman-openconcerto.sh" ]; then
        bash "$SCRIPT_DIR/podman-openconcerto.sh" --dir "$STACK_DIR" up && started=1
    fi
    [ "$started" -eq 1 ] || die "demarrage de la stack impossible (stack $STACK_DIR)"
    CID=$(db_container_id)
    [ -n "$CID" ] || die "conteneur PostgreSQL introuvable apres demarrage"
fi

container_env() {
    $RUNTIME inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CID" 2>/dev/null
}

info "runtime    : $RUNTIME"
info "stack      : $STACK_DIR"
info "conteneur  : $($RUNTIME inspect -f '{{.Name}}' "$CID" 2>/dev/null | sed 's|^/||')"

# --------------------------------------------- configuration de la base
# Ordre : option --password, variable PGPASSWORD, .env de la stack,
# environnement du conteneur (POSTGRES_*).
ENV_FILE=""
for candidate in \
    "$STACK_DIR/.env" \
    "$STACK_DIR"/docker/openconcerto-1.7.6/.env \
    "$STACK_DIR"/*/.env; do
    if [ -f "$candidate" ]; then
        ENV_FILE="$candidate"
        break
    fi
done

env_value() {
    [ -n "$ENV_FILE" ] || return 1
    sed -n "s/^$1=//p" "$ENV_FILE" | head -1 | tr -d '\r'
}

container_value() {
    container_env | sed -n "s/^$1=//p" | head -1 | tr -d '\r'
}

[ -n "$DB_PORT" ] || DB_PORT=$(env_value PG_HOST_PORT 2>/dev/null || true)
[ -n "$DB_PORT" ] || DB_PORT=$(container_value PG_HOST_PORT 2>/dev/null || true)
[ -n "$DB_NAME" ] || DB_NAME=$(env_value POSTGRES_DB 2>/dev/null || true)
[ -n "$DB_NAME" ] || DB_NAME=$(container_value POSTGRES_DB 2>/dev/null || true)
[ -n "$DB_USER" ] || DB_USER=$(env_value POSTGRES_USER 2>/dev/null || true)
[ -n "$DB_USER" ] || DB_USER=$(container_value POSTGRES_USER 2>/dev/null || true)
if [ -z "$DB_PASSWORD" ] && [ -n "${PGPASSWORD:-}" ]; then
    DB_PASSWORD=$PGPASSWORD
    PASSWORD_SOURCE="variable PGPASSWORD"
elif [ -z "$DB_PASSWORD" ]; then
    DB_PASSWORD=$(env_value POSTGRES_PASSWORD 2>/dev/null || true)
    [ -n "$DB_PASSWORD" ] && PASSWORD_SOURCE="fichier $ENV_FILE"
fi
if [ -z "$DB_PASSWORD" ]; then
    # la configuration du client OC contient le mot de passe reellement
    # utilise par l'application (cle server.password)
    for conf in "${OC_CONF:-}" "$HOME/.config/OpenConcerto/main.properties" "$HOME/.openconcerto/main.properties"; do
        [ -n "$conf" ] && [ -f "$conf" ] || continue
        cand=$(sed -n 's/^server\.password=//p' "$conf" | head -1 | tr -d '\r')
        if [ -n "$cand" ]; then
            DB_PASSWORD=$cand
            PASSWORD_SOURCE="configuration du client OC ($conf)"
            break
        fi
    done
fi
if [ -z "$DB_PASSWORD" ]; then
    DB_PASSWORD=$(container_value POSTGRES_PASSWORD 2>/dev/null || true)
    [ -n "$DB_PASSWORD" ] && PASSWORD_SOURCE="environnement du conteneur"
fi
[ -n "$PASSWORD_SOURCE" ] || PASSWORD_SOURCE="aucun (base sans mot de passe ?)"

DB_PORT=${DB_PORT:-5433}
DB_NAME=${DB_NAME:-OpenConcerto}
DB_USER=${DB_USER:-openconcerto}

info "base       : $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
info "mot de passe: $PASSWORD_SOURCE"

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

# ------------------------------------------------- psql dans le conteneur
# Le conteneur PostgreSQL autorise les connexions locales (socket unix) sans
# mot de passe : c'est le moyen le plus sur de lire la base, quel que soit
# l'etat du mot de passe du role. On fabrique un petit « psql » qui appelle
# le binaire du conteneur.
PSQL_WRAPPER_DIR=""
make_psql_wrapper() {
    PSQL_WRAPPER_DIR=$(mktemp -d 2>/dev/null) || return 1
    cat > "$PSQL_WRAPPER_DIR/psql" <<EOF
#!/usr/bin/env bash
# psql execute DANS le conteneur PostgreSQL de la stack.
# La connexion passe par le socket local du conteneur : aucun mot de passe
# n'est necessaire.
file=""
prev=""
for a in "\$@"; do
  if [ "\$prev" = "-f" ]; then file="\$a"; fi
  prev="\$a"
done
PSQL_ARGS=(-X -v ON_ERROR_STOP=1 --csv -U "\${PGUSER:-$DB_USER}" -d "\${PGDATABASE:-$DB_NAME}")
if [ -n "\$file" ]; then
  exec $RUNTIME exec -i $CID psql "\${PSQL_ARGS[@]}" -f - < "\$file"
fi
exec $RUNTIME exec -i $CID psql "\${PSQL_ARGS[@]}"
EOF
    chmod +x "$PSQL_WRAPPER_DIR/psql" 2>/dev/null || { rm -rf "$PSQL_WRAPPER_DIR"; PSQL_WRAPPER_DIR=""; return 1; }
    return 0
}

if [ "$MODE" != "container" ] && make_psql_wrapper; then
    info "transport : psql dans le conteneur $CID (socket local, sans mot de passe)"
    TRANSPORT_LOCAL=1
else
    TRANSPORT_LOCAL=0
fi

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
    local extra_path=""
    if [ "$TRANSPORT_LOCAL" -eq 1 ]; then
        # le « psql » du conteneur passe en premier dans le PATH
        extra_path="$PSQL_WRAPPER_DIR:"
    elif [ -n "$DRIVER" ]; then
        info "pilote JDBC : $DRIVER"
        cp="$cp:$DRIVER"
    elif command -v psql >/dev/null 2>&1; then
        info "transport psql du poste : $(command -v psql)"
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
    PATH="$extra_path$PATH" "$java" -cp "$cp" "$MAIN_CLASS" "${args[@]}"
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
    $RUNTIME run --rm \
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

[ -n "$PSQL_WRAPPER_DIR" ] && rm -rf "$PSQL_WRAPPER_DIR"

echo
if [ "$CODE" -eq 0 ]; then
    echo "RESULTAT : la suite passe (aucune donnee cachee detectee) sur $DB_HOST:$DB_PORT/$DB_NAME."
else
    echo "RESULTAT : la suite a detecte des problemes (code $CODE) sur $DB_HOST:$DB_PORT/$DB_NAME : voir le detail ci-dessus."
fi
exit "$CODE"
