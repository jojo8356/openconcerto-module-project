#!/bin/sh
#
# Ouvre psql sur la base OpenConcerto, SANS docker compose.
#
# Pourquoi ce script : `docker compose exec db psql` exige un fichier .env
# (POSTGRES_PASSWORD) ET de se trouver dans le dossier de la stack. Ici on parle
# directement au conteneur PostgreSQL deja demarre : aucun .env, aucun mot de
# passe, aucun `cd`. Le conteneur, le role et la base sont detectes.
#
# Compatible sh et bash (aucune dependance : ni bash, ni psql sur l'hote).
#
# Usage :
#   ./oc-psql.sh                          # invite psql interactive
#   ./oc-psql.sh -c 'select now()'        # une requete
#   ./oc-psql.sh -f requete.sql           # un fichier
#   ./oc-psql.sh -l                       # liste les bases
#   ./oc-psql.sh --no-password abe        # retire le mot de passe d'un utilisateur
#   ./oc-psql.sh --password abe MDP       # (re)met un mot de passe
#
# Options :
#   -c SQL        execute cette requete
#   -f FICHIER    execute ce fichier
#   -d BASE       base (defaut : detectee)
#   -U ROLE       role SQL (defaut : detecte depuis le conteneur)
#   -C CONTENEUR  conteneur (defaut : detecte)
#   -l            liste les bases de donnees
#   -n            dry-run : affiche la commande, n'execute rien
#   -h            cette aide
#
# Variables : OC_CONTAINER, OC_DB, OC_USER
#
# Rappels OpenConcerto :
#   * le mot de passe est Base64(SHA1(mot de passe)) dans
#     "Common"."USER_COMMON" ; « pas de mot de passe » = l'empreinte de la
#     chaine vide ;
#   * `docker exec` tourne en root : on passe toujours -U explicitement.
#
set -eu

CONTAINER="${OC_CONTAINER:-}"
DB="${OC_DB:-}"
DBUSER="${OC_USER:-}"
SQL=""
FILE=""
LIST_DBS=0
DRY=0
ACTION=""
LOGIN=""
NEWPASS=""

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

usage() {
    awk '/^# Usage/{f=1} /^set -eu/{f=0} f { if ($0 ~ /^# / || $0 ~ /^$/) print }' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

need_arg() {
    [ $# -ge 2 ] || die "option $1 : argument manquant"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -c) need_arg "$@"; SQL="$2"; shift 2 ;;
        -f) need_arg "$@"; FILE="$2"; shift 2 ;;
        -d) need_arg "$@"; DB="$2"; shift 2 ;;
        -U) need_arg "$@"; DBUSER="$2"; shift 2 ;;
        -C) need_arg "$@"; CONTAINER="$2"; shift 2 ;;
        -l|--list) LIST_DBS=1; shift ;;
        -n|--dry-run) DRY=1; shift ;;
        --no-password) need_arg "$@"; ACTION="nopass"; LOGIN="$2"; shift 2 ;;
        --password) need_arg "$@"; ACTION="setpass"; LOGIN="$2"; NEWPASS="${3:-}"; shift 2
                     [ $# -gt 0 ] && { NEWPASS="$1"; shift; } ;;
        -h|--help) usage ;;
        *) die "option inconnue : $1 (voir -h)" ;;
    esac
done

command -v docker >/dev/null 2>&1 || die "'docker' introuvable : ce script parle au conteneur PostgreSQL."

# --------------------------------------------------------------- conteneur
# Priorite : un conteneur qui publie 5433 (le port de la stack), sinon le
# premier conteneur PostgreSQL.
find_container() {
    c=$(docker ps --filter "publish=${1:-5433}" --format '{{.Names}}' 2>/dev/null | head -n 1 || true)
    if [ -z "$c" ]; then
        c=$(docker ps --format '{{.Names}}\t{{.Image}}' 2>/dev/null \
            | awk -F'\t' 'tolower($2) ~ /postgres|postgis/ { print $1; exit }')
    fi
    printf '%s' "$c"
}

if [ -z "$CONTAINER" ]; then
    CONTAINER=$(find_container 5433)
    [ -n "$CONTAINER" ] || CONTAINER=$(find_container "")
fi
if [ -z "$CONTAINER" ]; then
    printf '\nAucun conteneur PostgreSQL en cours.\n\n' >&2
    printf 'Conteneurs vus par docker :\n' >&2
    docker ps --format '  {{.Names}}  ({{.Image}})  {{.Status}}' >&2 || true
    printf '\nDemarrez la stack, ou passez le nom avec -C <conteneur>.\n' >&2
    exit 1
fi
docker inspect "$CONTAINER" >/dev/null 2>&1 || die "conteneur introuvable : $CONTAINER"

# ------------------------------------------------------- role et base
container_env() {
    docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" 2>/dev/null \
        | sed -n "s/^$1=//p" | head -n 1
}

if [ -z "$DBUSER" ]; then
    DBUSER=$(container_env POSTGRES_USER)
fi
if [ -z "$DBUSER" ]; then
    DBUSER=$(docker exec -i "$CONTAINER" psql -U postgres -d postgres -Atc \
        'select rolname from pg_roles where rolsuper order by 1' 2>/dev/null | head -n 1 || true)
fi
[ -n "$DBUSER" ] || die "role SQL introuvable : passez-le avec -U (ex. -U openconcerto)."

list_databases() {
    docker exec -i "$CONTAINER" psql -U "$DBUSER" -d postgres -Atc \
        "select datname from pg_database where not datistemplate and datname <> 'postgres' order by 1"
}

if [ -z "$DB" ]; then
    BASES=$(list_databases 2>/dev/null || true)
    [ -n "$BASES" ] || die "aucune base lisible par le role $DBUSER dans $CONTAINER (essayez -U)."
    FROM_ENV=$(container_env POSTGRES_DB)
    if [ -n "$FROM_ENV" ] && printf '%s\n' "$BASES" | grep -qx "$FROM_ENV"; then
        DB="$FROM_ENV"
    else
        CANDIDATES=$(printf '%s\n' "$BASES" | grep -i '^openconcerto' || true)
        COUNT=$(printf '%s\n' "$CANDIDATES" | grep -c . || true)
        if [ "$COUNT" = "1" ]; then
            DB="$CANDIDATES"
        elif [ "$COUNT" = "0" ]; then
            COUNT_ALL=$(printf '%s\n' "$BASES" | grep -c . || true)
            if [ "$COUNT_ALL" = "1" ]; then
                DB="$BASES"
            else
                printf '\nPlusieurs bases et aucune ne commence par "OpenConcerto" :\n' >&2
                printf '%s\n' "$BASES" | sed 's/^/  - /' >&2
                die "choisissez la base avec -d NOM."
            fi
        else
            printf '\nPlusieurs bases OpenConcerto dans ce conteneur :\n' >&2
            printf '%s\n' "$CANDIDATES" | sed 's/^/  - /' >&2
            die "choisissez la base avec -d NOM."
        fi
    fi
fi

# Lance psql dans le conteneur. $1 = mode (exec ou exec -it), le reste = args.
run_psql() {
    tty_flag="$1"; shift
    if [ "$tty_flag" = "tty" ]; then
        docker exec -it "$CONTAINER" psql -U "$DBUSER" -d "$DB" -v ON_ERROR_STOP=1 "$@"
    else
        docker exec -i "$CONTAINER" psql -U "$DBUSER" -d "$DB" -v ON_ERROR_STOP=1 "$@"
    fi
}

if [ "$LIST_DBS" = "1" ]; then
    log "conteneur $CONTAINER"
    info "role : $DBUSER"
    info "bases :"
    list_databases | sed 's/^/    /'
    exit 0
fi

# Empreinte OpenConcerto : Base64(SHA1(mot de passe)).
oc_hash() {
    if command -v openssl >/dev/null 2>&1; then
        printf '%s' "$1" | openssl dgst -sha1 -binary | base64 | tr -d '\n'
    elif command -v shasum >/dev/null 2>&1; then
        printf '%s' "$1" | shasum -a 1 | cut -d' ' -f1 | xxd -r -p | base64 | tr -d '\n'
    else
        printf '%s' "$1" | sha1sum | cut -d' ' -f1 | xxd -r -p | base64 | tr -d '\n'
    fi
}

case "$ACTION" in
    nopass)
        [ -n "$LOGIN" ] || die "--no-password exige un login : --no-password abe"
        EMPTY=$(oc_hash "")
        SQL="update \"Common\".\"USER_COMMON\" set \"PASSWORD\" = '$EMPTY' where lower(\"LOGIN\") = lower('$LOGIN');
select \"LOGIN\", \"PASSWORD\", (\"PASSWORD\" = '$EMPTY') as sans_mot_de_passe from \"Common\".\"USER_COMMON\" where lower(\"LOGIN\") = lower('$LOGIN');"
        ;;
    setpass)
        [ -n "$LOGIN" ] || die "--password exige un login : --password abe MDP"
        [ -n "$NEWPASS" ] || die "--password exige un mot de passe : --password abe MDP"
        HASHED=$(oc_hash "$NEWPASS")
        SQL="update \"Common\".\"USER_COMMON\" set \"PASSWORD\" = '$HASHED' where lower(\"LOGIN\") = lower('$LOGIN');
select \"LOGIN\", \"PASSWORD\" from \"Common\".\"USER_COMMON\" where lower(\"LOGIN\") = lower('$LOGIN');"
        ;;
esac

if [ -n "$FILE" ]; then
    [ -f "$FILE" ] || die "fichier introuvable : $FILE"
fi

if [ "$DRY" = "1" ]; then
    log "conteneur $CONTAINER   role $DBUSER   base $DB"
    info "commande :"
    if [ -n "$FILE" ]; then
        printf '    docker exec -i %s psql -U %s -d %s -v ON_ERROR_STOP=1 < %s\n' "$CONTAINER" "$DBUSER" "$DB" "$FILE"
    elif [ -n "$SQL" ]; then
        printf '    docker exec -i %s psql -U %s -d %s -v ON_ERROR_STOP=1 -c %s\n' "$CONTAINER" "$DBUSER" "$DB" "'<SQL>'"
        info "SQL :"
        printf '%s\n' "$SQL" | sed 's/^/    /'
    else
        printf '    docker exec -it %s psql -U %s -d %s -v ON_ERROR_STOP=1\n' "$CONTAINER" "$DBUSER" "$DB"
    fi
    exit 0
fi

log "conteneur $CONTAINER   role $DBUSER   base $DB"

if [ -n "$FILE" ]; then
    run_psql no-tty < "$FILE"
elif [ -n "$SQL" ]; then
    run_psql no-tty -c "$SQL"
else
    run_psql tty
fi
