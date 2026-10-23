#!/usr/bin/env bash
#
# VERSIONS DES MODULES : diagnostic et correction
#
# Probleme : OpenConcerto refuse de se connecter quand la version du module
# "enregistree" dans la base n'a pas de jar correspondant sur le poste.
#   Exception : "Impossible de creer les modules, not solved :
#                SetMap {NO_FACTORY=[Module <id> v1.1]}"
#
# Pourquoi : la base epingle la version du module a deux endroits
#   1. FWK_MODULE_METADATA : ligne "module" (TABLE et FIELD a NULL)
#      -> version du module installe dans CETTE base ;
#   2. PREF_VALUE, noeud "modules/required" : "modules requis"
#      -> version exigee par l'administrateur.
# Au demarrage, OpenConcerto exige une correspondance EXACTE entre ces
# versions et un jar present dans le dossier Modules du client. Un simple
# remplacement du jar (sans mise a jour de la base) suffit a bloquer le
# client.
#
# Ce script :
#   - sans option : DIAGNOSTIC (lecture seule)
#   - avec --fix   : montre la correction proposee (toujours sans ecrire)
#   - avec --apply  : applique la correction (transaction SQL)
#
# Usage :
#   bash scripts/fix-module-version.sh --mode docker --stack ~/oc-176-docker
#   bash scripts/fix-module-version.sh --mode docker --stack ~/oc-176-docker --apply
#   bash scripts/fix-module-version.sh --mode local --host 127.0.0.1 --port 5433 --apply
#
# Options :
#   --mode MODE     docker | local | vm   (defaut : docker)
#   --stack DIR     dossier de la stack    (defaut : ~/oc-176-podman)
#   --host HOTE     hote PostgreSQL        (defaut : 127.0.0.1)
#   --port PORT     port                   (defaut : 5433)
#   --db BASE       base                   (defaut : OpenConcerto)
#   --user ROLE     role SQL               (defaut : openconcerto)
#   --password MDP  mot de passe
#   --module ID     id du module           (defaut : org.openconcerto.modules.project)
#   --version X.Y   version a enregistrer  (defaut : version du jar trouve sur le poste)
#   --modules-dir D dossier Modules du client a inspecter
#   --fix           affiche la correction proposee
#   --apply         applique la correction
#   -h|--help       cette aide
#
set -uo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

MODE=docker
STACK_DIR=${STACK_DIR:-$HOME/oc-176-podman}
DB_HOST=127.0.0.1
DB_PORT=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
OUT=""
VM_HOST=127.0.0.1
VM_PORT=2222
VM_USER=oc
VM_PASSWORD=oc
VM_DIR="/home/$VM_USER/oc-176"
MODULE_ID="org.openconcerto.modules.project"
TARGET_VERSION=""
MODULES_DIR=""
DO_FIX=0
DO_APPLY=0
HOST_GIVEN=0
PORT_GIVEN=0
DB_GIVEN=0

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '/^# Usage/,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --mode) MODE="$2"; shift 2 ;;
        --stack) STACK_DIR="$2"; shift 2 ;;
        --host) DB_HOST="$2"; HOST_GIVEN=1; shift 2 ;;
        --port) DB_PORT="$2"; PORT_GIVEN=1; shift 2 ;;
        --db) DB_NAME="$2"; DB_GIVEN=1; shift 2 ;;
        --user) DB_USER="$2"; shift 2 ;;
        --password) DB_PASSWORD="$2"; shift 2 ;;
        --module) MODULE_ID="$2"; shift 2 ;;
        --version) TARGET_VERSION="$2"; shift 2 ;;
        --modules-dir) MODULES_DIR="$2"; shift 2 ;;
        --fix) DO_FIX=1; shift ;;
        --apply) DO_FIX=1; DO_APPLY=1; shift ;;
        --out) OUT="$2"; shift 2 ;;
        --vm-host) VM_HOST="$2"; shift 2 ;;
        --vm-port) VM_PORT="$2"; shift 2 ;;
        --vm-user) VM_USER="$2"; shift 2 ;;
        --vm-password) VM_PASSWORD="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "option inconnue : $1" >&2; usage >&2 ;;
    esac
done

case "$MODE" in
    docker|local|vm) ;;
    *) die "mode invalide : $MODE (docker, local ou vm)" ;;
esac

# En mode local, on peut deduire hote/port/base de la configuration du client
# OpenConcerto (server.url=jdbc:postgresql://hote:port/base).
if [ "$MODE" = "local" ] && { [ "$HOST_GIVEN" -eq 0 ] || [ "$PORT_GIVEN" -eq 0 ] || [ "$DB_GIVEN" -eq 0 ]; }; then
    for conf in "$HOME/.config/OpenConcerto/main.properties" "$HOME/.openconcerto/main.properties"; do
        [ -f "$conf" ] || continue
        url=$(sed -n 's/^server\.url=//p' "$conf" | head -1 | tr -d '\r')
        [ -n "$url" ] || continue
        case "$url" in
            *//*) : ;;
            *) continue ;;
        esac
        rest=${url#*//}
        hostport=${rest%%/*}
        dbase=${rest#*/}
        dbase=${dbase%%\?*}
        if [ "$HOST_GIVEN" -eq 0 ]; then
            h=${hostport%%:*}
            [ -n "$h" ] && DB_HOST="$h"
        fi
        if [ "$PORT_GIVEN" -eq 0 ]; then
            p=${hostport##*:}
            [ "$p" != "$hostport" ] && DB_PORT="$p"
        fi
        if [ "$DB_GIVEN" -eq 0 ] && [ -n "$dbase" ]; then
            DB_NAME="$dbase"
        fi
        break
    done
fi

# ---------------------------------------------------------------- mode vm
if [ "$MODE" = "vm" ]; then
    command -v ssh >/dev/null 2>&1 || die "'ssh' introuvable."
    SSH_OPTS=(-p "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10)
    SCP_OPTS=(-P "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10)
    [ -f "$HOME/.ssh/id_ed25519_oc176" ] && SSH_OPTS+=(-i "$HOME/.ssh/id_ed25519_oc176")
    [ -f "$HOME/.ssh/id_ed25519_oc176" ] && SCP_OPTS+=(-i "$HOME/.ssh/id_ed25519_oc176")

    log "Envoi du script dans la VM"
    ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "mkdir -p '$VM_DIR/scripts'" || die "acces a la VM impossible"
    scp "${SCP_OPTS[@]}" "$SCRIPT_DIR/fix-module-version.sh" "$VM_USER@$VM_HOST:$VM_DIR/scripts/fix-module-version.sh" \
        || die "envoi du script impossible"

    VM_DB_PASSWORD=$(ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "sed -n 's/^POSTGRES_PASSWORD=//p' '$VM_DIR/docker/openconcerto-1.7.6/.env' 2>/dev/null | head -1" 2>/dev/null | tr -d '\r\n')
    if [ -z "$VM_DB_PASSWORD" ]; then
        VM_DB_PASSWORD=$(ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "docker exec \$(docker ps --format '{{.Names}}' | grep -E 'db' | head -1) printenv POSTGRES_PASSWORD 2>/dev/null" 2>/dev/null | tr -d '\r\n')
    fi
    [ -n "$VM_DB_PASSWORD" ] || die "mot de passe PostgreSQL introuvable dans la VM"

    # Dans la VM, on utilise psql s'il est installe, sinon le conteneur Docker
    # de la stack (le script sait parler aux deux).
    if ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "command -v psql >/dev/null 2>&1"; then
        VM_MODE=local
    else
        VM_MODE=docker
        log "psql absent dans la VM : passage par le conteneur Docker de la stack"
    fi

    EXTRA=""
    [ "$DB_GIVEN" -eq 1 ] && EXTRA="$EXTRA --db '$DB_NAME'"
    [ -n "$TARGET_VERSION" ] && EXTRA="$EXTRA --version '$TARGET_VERSION'"
    [ "$DO_APPLY" -eq 1 ] && EXTRA="$EXTRA --apply" || EXTRA="$EXTRA --fix"

    log "Diagnostic dans la VM (mode $VM_MODE)"
    if [ "$VM_MODE" = local ]; then
        ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "cd '$VM_DIR' && bash scripts/fix-module-version.sh --mode local \
--host 127.0.0.1 --port 5433 --user ${DB_USER:-openconcerto} --password '$VM_DB_PASSWORD' \
--module '$MODULE_ID'$EXTRA"
    else
        ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "cd '$VM_DIR' && bash scripts/fix-module-version.sh --mode docker \
--stack '$VM_DIR' --user ${DB_USER:-openconcerto} --module '$MODULE_ID'$EXTRA"
    fi
    exit $?
fi

# ---------------------------------------------------------------- transport
RUNTIME=""
CID=""
ENV_FILE=""
COMPOSE_FILE=""

if [ "$MODE" = docker ]; then
    if command -v podman >/dev/null 2>&1; then
        RUNTIME=podman
    elif command -v docker >/dev/null 2>&1; then
        RUNTIME=docker
    else
        die "ni podman ni docker n'est disponible (utilisez --mode local ou --mode vm)."
    fi
    for candidate in \
        "$STACK_DIR/compose.yaml" "$STACK_DIR/compose.yml" \
        "$STACK_DIR/docker-compose.yml" "$STACK_DIR/docker-compose.yaml" \
        "$STACK_DIR"/docker/openconcerto-1.7.6/docker-compose.yml; do
        [ -f "$candidate" ] || continue
        COMPOSE_FILE="$candidate"
        break
    done
    CID=$($RUNTIME ps -q --filter "name=openconcerto176-db" 2>/dev/null | head -n 1)
    if [ -z "$CID" ] && [ -n "$COMPOSE_FILE" ]; then
        CID=$(cd "$(dirname "$COMPOSE_FILE")" && $RUNTIME compose -p openconcerto176 -f "$COMPOSE_FILE" ps -q db 2>/dev/null | head -n 1)
    fi
    if [ -z "$CID" ]; then
        CID=$($RUNTIME ps -a -q --filter "name=openconcerto176-db" 2>/dev/null | head -n 1)
        [ -n "$CID" ] && die "le conteneur PostgreSQL existe mais est ARRETE : relancez la stack"
    fi
    [ -n "$CID" ] || die "conteneur PostgreSQL introuvable (stack $STACK_DIR)."
fi

for candidate in "$STACK_DIR/.env" "$STACK_DIR"/docker/openconcerto-1.7.6/.env; do
    [ -f "$candidate" ] || continue
    ENV_FILE="$candidate"
    break
done

env_value() { [ -n "$ENV_FILE" ] || return 1; sed -n "s/^$1=//p" "$ENV_FILE" | head -1 | tr -d '\r'; }
container_value() {
    [ -n "$CID" ] || return 1
    $RUNTIME inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CID" 2>/dev/null | sed -n "s/^$1=//p" | head -1 | tr -d '\r'
}

[ -n "$DB_PORT" ] || DB_PORT=$(env_value PG_HOST_PORT 2>/dev/null || true)
[ -n "$DB_PORT" ] || DB_PORT=$(container_value PG_HOST_PORT 2>/dev/null || true)
[ -n "$DB_NAME" ] || DB_NAME=$(env_value POSTGRES_DB 2>/dev/null || true)
[ -n "$DB_NAME" ] || DB_NAME=$(container_value POSTGRES_DB 2>/dev/null || true)
[ -n "$DB_USER" ] || DB_USER=$(env_value POSTGRES_USER 2>/dev/null || true)
[ -n "$DB_USER" ] || DB_USER=$(container_value POSTGRES_USER 2>/dev/null || true)
if [ -z "$DB_PASSWORD" ]; then
    for conf in "$HOME/.config/OpenConcerto/main.properties" "$HOME/.openconcerto/main.properties"; do
        [ -f "$conf" ] || continue
        cand=$(sed -n 's/^server\.password=//p' "$conf" | head -1 | tr -d '\r')
        if [ -n "$cand" ]; then DB_PASSWORD="$cand"; break; fi
    done
fi
[ -n "$DB_PASSWORD" ] || DB_PASSWORD=$(container_value POSTGRES_PASSWORD 2>/dev/null || true)

DB_PORT=${DB_PORT:-5433}
DB_NAME=${DB_NAME:-OpenConcerto}
DB_USER=${DB_USER:-openconcerto}

if [ "$MODE" = docker ]; then
    WRAPPER_DIR=$(mktemp -d 2>/dev/null) || die "impossible de creer un repertoire temporaire"
    if [ -n "$DB_PASSWORD" ]; then PGPASS_ENV="-e PGPASSWORD=$DB_PASSWORD"; else PGPASS_ENV=""; fi
    cat > "$WRAPPER_DIR/psql" <<EOF
#!/usr/bin/env bash
ARGS=()
while [ \$# -gt 0 ]; do
  case "\$1" in
    -h|--host) shift 2 ;;
    -p|--port) shift 2 ;;
    *) ARGS+=("\$1"); shift ;;
  esac
done
exec $RUNTIME exec -i $PGPASS_ENV $CID psql "\${ARGS[@]}"
EOF
    chmod +x "$WRAPPER_DIR/psql" || die "impossible de creer le wrapper psql"
    export PATH="$WRAPPER_DIR:$PATH"
    info "transport : psql dans le conteneur (socket local)"
else
    command -v psql >/dev/null 2>&1 || die "psql est introuvable."
    export PGPASSWORD="$DB_PASSWORD"
    info "transport : psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d <base>"
fi

# psql <base> [args...] : execute sur la base demandee
psql_db() {
    local db="$1"; shift
    if [ "$MODE" = docker ]; then
        psql -X -w -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$db" "$@"
    else
        psql -X -w -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$db" "$@"
    fi
}

# ---------------------------------------------------------------- helpers
q()  { psql_db "$CUR_DB" -c "$1" 2>&1; }
q1() { psql_db "$CUR_DB" -A -t -c "$1" 2>&1; }
CUR_DB="$DB_NAME"

# merged (major * 10000 + minor) -> "major.minor"
decode_version() {
    local m="${1:-}"
    [ -n "$m" ] || { echo "(inconnue)"; return 0; }
    printf '%s.%s' "$((m / 10000))" "$((m % 10000))"
}
# "major.minor" -> merged
encode_version() {
    local v="$1" major minor
    major=${v%%.*}
    minor=${v#*.}
    [ "$minor" = "$v" ] && minor=0
    printf '%s' "$((major * 10000 + minor))"
}

# ---------------------------------------------------------------- jars du poste
detect_client_jars() {
    local dirs=() d jar version
    if [ -n "$MODULES_DIR" ]; then
        dirs=("$MODULES_DIR")
    else
        for d in /opt/openconcerto/Modules \
                 "$HOME"/.local/share/OpenConcerto/Modules \
                 "$HOME"/OpenConcerto*/Modules \
                 /usr/share/openconcerto/Modules; do
            [ -d "$d" ] && dirs+=("$d")
        done
    fi
    for d in "${dirs[@]}"; do
        [ -d "$d" ] || continue
        for jar in "$d"/*.jar; do
            [ -f "$jar" ] || continue
            version=""
            if command -v unzip >/dev/null 2>&1; then
                version=$(unzip -p "$jar" META-INF/openConcertoModule.properties 2>/dev/null \
                          | sed -n 's/^version=//p' | tr -d '\r' | head -1)
            fi
            if [ -z "$version" ]; then
                # le nom du jar encode la version : <id>-<version>.jar
                version=$(basename "$jar" .jar | sed 's/.*-//')
            fi
            if [ -z "$version" ]; then
                version="(inconnue)"
            fi
            info "$(basename "$jar")  ->  version $version   [$d]"
            LAST_JAR_VERSION="$version"
        done
    done
}

LAST_JAR_VERSION=""

echo "================================================================================"
echo "VERSIONS DES MODULES : diagnostic"
echo "================================================================================"
echo
echo "module : $MODULE_ID"
echo "base   : $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
echo

log "Jars du client (dossier Modules lu par OpenConcerto)"
detect_client_jars
if [ -n "$LAST_JAR_VERSION" ]; then
    info "derniere version trouvee sur le poste : $LAST_JAR_VERSION"
    [ -n "$TARGET_VERSION" ] || TARGET_VERSION="$LAST_JAR_VERSION"
fi
echo

# Toutes les bases du serveur (la base de production peut porter un nom
# different de « OpenConcerto ») ; --db permet de cibler une seule base.
if [ "$DB_GIVEN" -eq 1 ]; then
    DATABASES="$DB_NAME"
else
    DATABASES=$(psql_db postgres -A -t -c "select datname from pg_database where datallowconn and not datistemplate order by 1" 2>/dev/null | tr -d '\r' | grep -v '^$')
    [ -n "$DATABASES" ] || DATABASES="$DB_NAME"
fi
info "bases inspectees : $(printf '%s' "$DATABASES" | tr '\n' ' ')"

for CUR_DB in $DATABASES; do
    CUR_DB=$(printf '%s' "$CUR_DB" | tr -d '\r')
    [ -n "$CUR_DB" ] || continue

    echo
    echo "################################################################################"
    echo "# BASE $CUR_DB"
    echo "################################################################################"

SCHEMAS=$(q1 "select distinct table_schema from information_schema.tables where table_name = 'FWK_MODULE_METADATA' order by 1")
if [ -z "$SCHEMAS" ]; then
    info "aucun schema avec une table FWK_MODULE_METADATA dans $CUR_DB"
    continue
fi

for schema in $SCHEMAS; do
    schema=$(printf '%s' "$schema" | tr -d '\r')
    [ -n "$schema" ] || continue
    echo "================================================================================"
    echo "SCHEMA $schema"
    echo "================================================================================"

    log "1. version installee dans la base (FWK_MODULE_METADATA)"
    q "select \"MODULE_NAME\", \"MODULE_VERSION\",
       case when \"MODULE_VERSION\" is null then null else \"MODULE_VERSION\"/10000 || '.' || \"MODULE_VERSION\"%10000 end as version
       from \"$schema\".\"FWK_MODULE_METADATA\"
       where \"MODULE_NAME\" = '$MODULE_ID' and \"TABLE\" is null and \"FIELD\" is null;"
    DB_MERGED=$(q1 "select \"MODULE_VERSION\" from \"$schema\".\"FWK_MODULE_METADATA\" where \"MODULE_NAME\" = '$MODULE_ID' and \"TABLE\" is null and \"FIELD\" is null;" 2>/dev/null | head -1 | tr -d '\r' || true)
    info "version en base : $(decode_version "$DB_MERGED")"

    log "2. modules requis (preference SQL 'modules/required')"
    HAS_PREFS=$(q1 "select count(*) from information_schema.tables where table_schema = '$schema' and table_name in ('PREF_VALUE','PREF_NODE');" 2>/dev/null | head -1 | tr -d '\r' || true)
    REQ_MERGED=""
    if [ "${HAS_PREFS:-0}" = "0" ]; then
        info "ce schema n'a pas de preferences SQL (PREF_VALUE) : rien a epingler de ce cote"
    else
        q "select v.\"NAME\" as module, v.\"VALUE\" as valeur,
       case when cast(v.\"VALUE\" as bigint) is null then null else cast(v.\"VALUE\" as bigint)/10000 || '.' || cast(v.\"VALUE\" as bigint)%10000 end as version
       from \"$schema\".\"PREF_VALUE\" v
       join \"$schema\".\"PREF_NODE\" n on n.\"ID\" = v.\"ID_NODE\"
       join \"$schema\".\"PREF_NODE\" p on p.\"ID\" = n.\"ID_PARENT\"
       where n.\"NAME\" = 'required' and p.\"NAME\" = 'modules'
       order by v.\"NAME\";"
        REQ_MERGED=$(q1 "select v.\"VALUE\" from \"$schema\".\"PREF_VALUE\" v
       join \"$schema\".\"PREF_NODE\" n on n.\"ID\" = v.\"ID_NODE\"
       join \"$schema\".\"PREF_NODE\" p on p.\"ID\" = n.\"ID_PARENT\"
       where n.\"NAME\" = 'required' and p.\"NAME\" = 'modules' and v.\"NAME\" = '$MODULE_ID';" 2>/dev/null | head -1 | tr -d '\r' || true)
        if [ -n "$REQ_MERGED" ]; then
            info "version requise par l'admin : $(decode_version "$REQ_MERGED")"
        else
            info "ce module n'est pas dans la liste des 'modules requis' : rien a epingler de ce cote"
        fi
    fi
    echo

    if [ "$DO_FIX" -eq 0 ]; then
        continue
    fi

    if [ -z "$TARGET_VERSION" ]; then
        info "AUCUNE CORRECTION : version cible inconnue (--version X.Y ou jar du poste)"
        continue
    fi
    NEW_MERGED=$(encode_version "$TARGET_VERSION")
    info "version cible : $TARGET_VERSION (valeur $NEW_MERGED)"
    if [ "$NEW_MERGED" = "$DB_MERGED" ] && [ "$NEW_MERGED" = "$REQ_MERGED" ]; then
        info "rien a corriger : la base et deja alignee sur $TARGET_VERSION"
        continue
    fi

    if [ "$DO_APPLY" -eq 0 ]; then
        info "correction prevue (relance avec --apply pour l'ecrire) :"
        info "  UPDATE $schema.FWK_MODULE_METADATA ... MODULE_VERSION -> $NEW_MERGED"
        info "  UPDATE $schema.PREF_VALUE ... 'modules/required' -> $NEW_MERGED"
        continue
    fi

    log "Application de la correction sur $schema"
    OUT1=$(q "begin;
       update \"$schema\".\"FWK_MODULE_METADATA\" set \"MODULE_VERSION\" = $NEW_MERGED
        where \"MODULE_NAME\" = '$MODULE_ID' and \"TABLE\" is null and \"FIELD\" is null;
       commit;" 2>&1)
    if printf '%s' "$OUT1" | grep -q "ERROR"; then
        info "ECHEC sur FWK_MODULE_METADATA : $OUT1"
    else
        info "FWK_MODULE_METADATA : version passee a $TARGET_VERSION"
    fi
    if [ "${HAS_PREFS:-0}" != "0" ]; then
        OUT2=$(q "begin;
       update \"$schema\".\"PREF_VALUE\" v set \"VALUE\" = '$NEW_MERGED'
        from \"$schema\".\"PREF_NODE\" n, \"$schema\".\"PREF_NODE\" p
        where v.\"ID_NODE\" = n.\"ID\" and n.\"ID_PARENT\" = p.\"ID\"
          and n.\"NAME\" = 'required' and p.\"NAME\" = 'modules'
          and v.\"NAME\" = '$MODULE_ID';
       commit;" 2>&1)
        if printf '%s' "$OUT2" | grep -q "ERROR"; then
            info "ECHEC sur PREF_VALUE : $OUT2"
        else
            info "PREF_VALUE (modules/required) : version passee a $TARGET_VERSION"
        fi
    fi
    info "base $schema alignee sur $TARGET_VERSION"
done
done

echo
echo "================================================================================"
if [ "$DO_APPLY" -eq 1 ]; then
    echo "Correction appliquee. Redemarrer le client OpenConcerto."
else
    echo "Diagnostic termine (aucune ecriture). Relance avec --apply pour corriger."
fi
echo "================================================================================"
