#!/usr/bin/env bash
#
# STRUCTURE de la demande de prix et des tables de transfert (TR_*)
#
# Questions auxquelles ce script repond :
#   - quelles colonnes ont DEMANDE_PRIX / DEMANDE_PRIX_ELEMENT / COMMANDE ?
#   - un transfert vers COMMANDE est-il deja prevu (tables TR_*) ?
#   - une demande de prix porte-t-elle un fournisseur, et a quel niveau ?
#   - a quoi ressemblent reellement une demande de prix et ses lignes ?
#
# LECTURE SEULE : uniquement des SELECT sur le catalogue PostgreSQL
# (pg_catalog / information_schema) et des COUNT(*). Aucune ecriture.
#
# Usage :
#   bash scripts/structure-demande-prix.sh
#   bash scripts/structure-demande-prix.sh --mode vm
#   bash scripts/structure-demande-prix.sh --mode local --host 127.0.0.1 --port 5433
#
# Options :
#   --mode MODE     docker | local | vm   (defaut : docker)
#   --stack DIR     dossier de la stack    (defaut : ~/oc-176-podman)
#   --host HOTE     hote PostgreSQL        (defaut : 127.0.0.1)
#   --port PORT     port                   (defaut : 5433)
#   --db BASE       base                   (defaut : OpenConcerto)
#   --user ROLE     role SQL               (defaut : openconcerto)
#   --password MDP  mot de passe
#   --out FICHIER   fichier de sortie      (defaut : sortie standard)
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
        --host) DB_HOST="$2"; shift 2 ;;
        --port) DB_PORT="$2"; shift 2 ;;
        --db) DB_NAME="$2"; shift 2 ;;
        --user) DB_USER="$2"; shift 2 ;;
        --password) DB_PASSWORD="$2"; shift 2 ;;
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

# ---------------------------------------------------------------- mode vm
if [ "$MODE" = "vm" ]; then
    command -v ssh >/dev/null 2>&1 || die "'ssh' introuvable."
    SSH_OPTS=(-p "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10)
    SCP_OPTS=(-P "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10)
    [ -f "$HOME/.ssh/id_ed25519_oc176" ] && SSH_OPTS+=(-i "$HOME/.ssh/id_ed25519_oc176")
    [ -f "$HOME/.ssh/id_ed25519_oc176" ] && SCP_OPTS+=(-i "$HOME/.ssh/id_ed25519_oc176")

    log "Envoi du script dans la VM"
    ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "mkdir -p '$VM_DIR/scripts'" || die "acces a la VM impossible"
    scp "${SCP_OPTS[@]}" "$SCRIPT_DIR/structure-demande-prix.sh" "$VM_USER@$VM_HOST:$VM_DIR/scripts/structure-demande-prix.sh" \
        || die "envoi du script impossible"

    VM_DB_PASSWORD=$(ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "sed -n 's/^POSTGRES_PASSWORD=//p' '$VM_DIR/docker/openconcerto-1.7.6/.env' 2>/dev/null | head -1" 2>/dev/null | tr -d '\r\n')
    if [ -z "$VM_DB_PASSWORD" ]; then
        VM_DB_PASSWORD=$(ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "docker exec \$(docker ps --format '{{.Names}}' | grep -E 'db' | head -1) printenv POSTGRES_PASSWORD 2>/dev/null" 2>/dev/null | tr -d '\r\n')
    fi
    [ -n "$VM_DB_PASSWORD" ] || die "mot de passe PostgreSQL introuvable dans la VM"

    log "Analyse dans la VM"
    ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "cd '$VM_DIR' && bash scripts/structure-demande-prix.sh --mode local --host 127.0.0.1 --port 5433 \
--db ${DB_NAME:-OpenConcerto} --user ${DB_USER:-openconcerto} --password '$VM_DB_PASSWORD'"
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
        [ -n "$CID" ] && die "le conteneur PostgreSQL existe mais est ARRETE : bash scripts/podman-openconcerto.* up"
    fi
    [ -n "$CID" ] || die "conteneur PostgreSQL introuvable (stack $STACK_DIR). Lance la stack, ou utilise --mode vm."
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
    PSQL=(psql -X -w -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME")
    info "transport : psql dans le conteneur (socket local)"
else
    command -v psql >/dev/null 2>&1 || die "psql est introuvable."
    export PGPASSWORD="$DB_PASSWORD"
    PSQL=(psql -X -w -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME")
    info "transport : psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME"
fi

# ---------------------------------------------------------------- helpers
# q <sql> : execute et affiche (mode aligne)
q() { "${PSQL[@]}" -c "$1" 2>&1; }
# q1 <sql> : execute et affiche une seule colonne par ligne
q1() { "${PSQL[@]}" -A -t -c "$1" 2>&1; }
# dump <schema> <table> <limit> : ecrit toutes les colonnes des premieres lignes
dump() {
    local sc="$1" tb="$2" lim="${3:-5}"
    local exists
    exists=$(q1 "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = '$sc' and c.relname = '$tb'")
    if [ "${exists:-0}" = "0" ]; then
        echo "  (table $tb absente dans $sc)"
        return 0
    fi
    q1 "select t.\"ID\" || ' | ' || coalesce((select string_agg(j.k || '=' || coalesce(j.v,'(vide)'), ' ; ')
              from jsonb_each_text(to_jsonb(t)) as j(k,v) where j.k <> 'ID'), '')
        from \"$sc\".\"$tb\" t order by t.\"ID\" limit $lim" 2>/dev/null
}

TABLES="('DEMANDE_PRIX','DEMANDE_PRIX_ELEMENT','DEMANDE_ACHAT_ELEMENT','COMMANDE','COMMANDE_ELEMENT')"

echo "================================================================================"
echo "STRUCTURE : DEMANDE DE PRIX / COMMANDE FOURNISSEUR  et  tables de transfert TR_*"
echo "================================================================================"
echo
echo "base : $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
echo

SCHEMAS=$(q1 "select distinct table_schema from information_schema.tables where table_name = 'AFFAIRE' and table_schema not in ('pg_catalog','information_schema') order by 1")
[ -n "$SCHEMAS" ] || { echo "aucun schema contenant une table AFFAIRE"; exit 1; }

for schema in $SCHEMAS; do
    schema=$(printf '%s' "$schema" | tr -d '\r')
    [ -n "$schema" ] || continue
    echo "================================================================================"
    echo "SCHEMA $schema"
    echo "================================================================================"

    echo
    echo "---- COLONNES (table | colonne | type | contrainte) ----"
    q1 "select c.relname || ' | ' || a.attname || ' | ' || format_type(a.atttypid, a.atttypmod)
          || case when a.attnotnull then ' | NOT NULL' else '' end
          || case when a.attidentity = 'i' then ' | SERIAL' else '' end
          || case when a.attnum = any (select unnest(cn.conkey) from pg_constraint cn where cn.conrelid = c.oid and cn.contype = 'p')
                  then ' | CLE PRIMAIRE' else '' end
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
        where n.nspname = '$schema' and c.relname in $TABLES
        order by c.relname, a.attnum"

    echo
    echo "---- CLES ETRANGERES (colonne -> table cible) ----"
    q1 "select c.relname || '.' || a.attname || ' -> ' || c2.relname || '.' || a2.attname
        from pg_constraint con
        join pg_class c on c.oid = con.conrelid
        join pg_namespace n on n.oid = c.relnamespace
        join pg_class c2 on c2.oid = con.confrelid
        join unnest(con.conkey) with ordinality k(attnum, ord) on true
        join pg_attribute a on a.attrelid = con.conrelid and a.attnum = k.attnum
        join unnest(con.confkey) with ordinality k2(attnum, ord) on k2.ord = k.ord
        join pg_attribute a2 on a2.attrelid = con.confrelid and a2.attnum = k2.attnum
        where con.contype = 'f' and n.nspname = '$schema' and c.relname in $TABLES
        order by c.relname, a.attname"

    echo
    echo "---- TABLES DE TRANSFERT TR_* (colonnes et cibles) ----"
    q1 "select t.relname || ' : ' || coalesce(string_agg(a.attname || ' ' || format_type(a.atttypid, a.atttypmod)
              || coalesce(' -> ' || (select c2.relname from pg_constraint con
                    join pg_class c2 on c2.oid = con.confrelid
                    where con.conrelid = t.oid and con.contype = 'f'
                      and a.attnum = any (con.conkey) limit 1), ''), ', '), '(aucune colonne)')
        from pg_class t
        join pg_namespace n on n.oid = t.relnamespace
        left join pg_attribute a on a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped
        where n.nspname = '$schema' and t.relname like 'TR!_%' escape '!'
        group by t.relname order by t.relname"

    echo
    echo "---- EFFECTIFS ----"
    for t in DEMANDE_PRIX DEMANDE_PRIX_ELEMENT DEMANDE_ACHAT_ELEMENT COMMANDE COMMANDE_ELEMENT; do
        exists=$(q1 "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = '$schema' and c.relname = '$t'")
        if [ "${exists:-0}" = "0" ]; then
            n="table absente"
        else
            n=$(q1 "select count(*) from \"$schema\".\"$t\"")
        fi
        printf '  %-24s : %s\n' "$t" "$n"
    done

    echo
    echo "---- EXEMPLE : EN-TETES DE DEMANDE DE PRIX (toutes colonnes) ----"
    dump "$schema" DEMANDE_PRIX 5

    echo
    echo "---- EXEMPLE : LIGNES DE DEMANDE DE PRIX (toutes colonnes) ----"
    dump "$schema" DEMANDE_PRIX_ELEMENT 10

    echo
    echo "---- EXEMPLE : LIGNES DE COMMANDE FOURNISSEUR (pour comparer) ----"
    dump "$schema" COMMANDE_ELEMENT 5

    echo
done

echo "================================================================================"
echo "FIN"
echo "================================================================================"
