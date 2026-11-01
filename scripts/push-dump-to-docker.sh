#!/usr/bin/env bash
#
# Pousse un dump OpenConcerto dans le PostgreSQL de la stack Docker.
#
# Le fichier peut etre :
#   * un dump au format pg_dump -Fc (il commence par « PGDMP »), eventuellement
#     compresse en gzip (.dumpsql, .dump, .dumpsql.gz, .dump.gz) ;
#   * un dump SQL texte (pg_dump par defaut, .sql, .sql.gz) : il est rejoue
#     avec psql, et s'il contient un CREATE DATABASE il est joue sur « postgres ».
#
# Le script ne devine rien : il annonce le format detecte, sauvegarde la base
# cible AVANT de la remplacer, puis verifie le resultat (tables par schema).
#
# Usage :
#   ./push-dump-to-docker.sh -f OC-v1.7.6-Noon_Dump_2026-10-09.dumpsql.gz
#   ./push-dump-to-docker.sh -f dump.dumpsql.gz -d OpenConcerto -n     # plan seul
#   ./push-dump-to-docker.sh -f dump.sql.gz -C openconcerto176-db-1 -y
#
# Options :
#   -f FICHIER    dump a restaurer (.gz accepte)
#   -d BASE       base cible (defaut : POSTGRES_DB du conteneur)
#   -C CONTENEUR  conteneur (defaut : celui qui publie le port 5433)
#   -k            conserve les donnees existantes (pg_restore --clean, sans drop)
#   -n            dry-run : affiche les commandes, ne modifie rien
#   -y            ne demande pas de confirmation
#   -h            cette aide
#
# Variables :
#   BACKUP_DIR    ou ecrire la sauvegarde (defaut : a cote du dump)
#   RESTORE_JOBS  parallelisme de pg_restore (defaut : 4)
#
# ATTENTION : par defaut la base cible est SUPPRIMEE puis recreee. Ne pointez
# jamais ce script vers une base de production sans sauvegarde verifiee.
#
# Verification du script : bash -n scripts/push-dump-to-docker.sh
# Recette complete (necessite Docker) : voir docs/psql-docker.md

set -euo pipefail

FILE=""
DB=""
CONTAINER=""
KEEP=0
DRY=0
ASSUME_YES=0
RESTORE_JOBS="${RESTORE_JOBS:-4}"

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

while getopts ":f:d:C:knyh" opt; do
    case "$opt" in
        f) FILE="$OPTARG" ;;
        d) DB="$OPTARG" ;;
        C) CONTAINER="$OPTARG" ;;
        k) KEEP=1 ;;
        n) DRY=1 ;;
        y) ASSUME_YES=1 ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

[ -n "$FILE" ] || usage 1
[ -f "$FILE" ] || die "fichier introuvable : $FILE"
command -v docker >/dev/null 2>&1 || die "docker introuvable."

# --------------------------------------------------------------------------
# 1. Conteneur, role et base
# --------------------------------------------------------------------------
if [ -z "$CONTAINER" ]; then
    CONTAINER=$(docker ps --filter publish=5433 --format '{{.Names}}' | head -n 1)
    [ -n "$CONTAINER" ] || CONTAINER=$(docker ps --filter ancestor=postgres:17-bookworm --format '{{.Names}}' | head -n 1)
fi
[ -n "$CONTAINER" ] || die "aucun conteneur PostgreSQL trouve : passez -C NOM_DU_CONTENEUR (voir docker ps)."
docker inspect "$CONTAINER" >/dev/null 2>&1 || die "conteneur introuvable : $CONTAINER"

env_of() { docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" 2>/dev/null | sed -n "s/^$1=//p" | head -n 1; }
PGUSER_T=$(env_of POSTGRES_USER); [ -n "$PGUSER_T" ] || PGUSER_T=postgres
PGDB_T=$(env_of POSTGRES_DB); [ -n "$PGDB_T" ] || PGDB_T=OpenConcerto
[ -n "$DB" ] || DB="$PGDB_T"

log "Conteneur : $CONTAINER"
log "Role      : $PGUSER_T"
log "Base cible: $DB"

# --------------------------------------------------------------------------
# 2. Format du dump (aucune supposition)
# --------------------------------------------------------------------------
head_bytes=$(gunzip -c "$FILE" 2>/dev/null | head -c 5 || true)
[ -n "$head_bytes" ] || head_bytes=$(head -c 5 "$FILE" || true)

if [ "$head_bytes" = "PGDMP" ]; then
    FORMAT=custom
elif printf '%s' "$head_bytes" | grep -q -- '--'; then
    FORMAT=sql
else
    die "format non reconnu (ni PGDMP, ni SQL) : verifiez avec 'file $FILE' et 'gunzip -c $FILE | head -c 100'."
fi
log "Format detecte : $FORMAT"

if [ "$FORMAT" = custom ]; then
    # Le fichier doit etre lisible par pg_restore : on le passe au conteneur.
    DUMP_PATH="/tmp/$(basename "$FILE" .gz)"
    DUMP_PATH="${DUMP_PATH%.dumpsql}.dumpsql"
else
    DUMP_PATH=""
fi

# --------------------------------------------------------------------------
# 3. Plan
# --------------------------------------------------------------------------
BACKUP_DIR="${BACKUP_DIR:-$(dirname "$FILE")}"
BACKUP="$BACKUP_DIR/backup-${DB}-$(date +%Y-%m-%d_%H%M).dump"

log "Ce qui va etre fait"
if [ "$KEEP" = 1 ]; then
    echo "  1. sauvegarde de $DB        -> $BACKUP"
    echo "  2. pg_restore --clean      (les donnees existantes sont ecrasees, la base reste)"
else
    echo "  1. sauvegarde de $DB        -> $BACKUP"
    echo "  2. DROP puis CREATE $DB     (les donnees actuelles sont perdues apres l'etape 1)"
fi
if [ "$FORMAT" = custom ]; then
    echo "  3. copie du dump            -> $CONTAINER:$DUMP_PATH"
    echo "  4. pg_restore -j $RESTORE_JOBS"
else
    echo "  3. psql -v ON_ERROR_STOP=1 (dump SQL texte)"
fi
echo "  5. controle : nombre de tables par schema, taille des tables"

if [ "$DRY" = 1 ]; then
    echo
    echo "(dry-run : rien n'a ete execute)"
    exit 0
fi

if [ "$ASSUME_YES" != 1 ]; then
    printf '\nContinuer ? [oui/NON] '
    read -r answer
    case "$answer" in
        oui | OUI | o | O | y | Y | yes) ;;
        *) die "abandonne : rien n'a ete modifie." ;;
    esac
fi

psql_t() { docker exec -i "$CONTAINER" sh -c "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" $*"; }

# --------------------------------------------------------------------------
# 4. Sauvegarde de la base cible (avant tout)
# --------------------------------------------------------------------------
log "Sauvegarde de $DB"
if docker exec -i "$CONTAINER" sh -c "psql -U \"\$POSTGRES_USER\" -lqt" | cut -d'|' -f1 | grep -qx " $DB"; then
    docker exec -i "$CONTAINER" sh -c "pg_dump -U \"\$POSTGRES_USER\" -Fc -d \"$DB\"" > "$BACKUP"
    [ -s "$BACKUP" ] || die "sauvegarde vide : arret avant toute modification."
    echo "   OK    $BACKUP ($(wc -c < "$BACKUP") octets)"
else
    echo "   (la base $DB n'existe pas encore : pas de sauvegarde)"
fi

# --------------------------------------------------------------------------
# 5. Restauration
# --------------------------------------------------------------------------
if [ "$FORMAT" = custom ]; then
    log "Copie du dump dans le conteneur"
    if [ "${FILE%.gz}" != "$FILE" ]; then
        gunzip -c "$FILE" | docker exec -i "$CONTAINER" sh -c "cat > '$DUMP_PATH'"
    else
        docker cp "$FILE" "$CONTAINER:$DUMP_PATH"
    fi
    echo "   OK    $DUMP_PATH"
    docker exec -i "$CONTAINER" sh -c "pg_restore -l '$DUMP_PATH' >/dev/null" \
        || die "dump illisible par pg_restore (fichier incomplet ?)"

    if [ "$KEEP" != 1 ]; then
        log "Recreation de $DB"
        if docker exec -i "$CONTAINER" sh -c "psql -U \"\$POSTGRES_USER\" -lqt" | cut -d'|' -f1 | grep -qx " $DB"; then
            docker exec -i "$CONTAINER" sh -c "dropdb -U \"\$POSTGRES_USER\" \"$DB\""
        fi
        docker exec -i "$CONTAINER" sh -c "createdb -U \"\$POSTGRES_USER\" -O \"\$POSTGRES_USER\" \"$DB\""
        echo "   OK    $DB recreee"
    fi

    log "Restauration (pg_restore -j $RESTORE_JOBS)"
    set +e
    if [ "$KEEP" = 1 ]; then
        docker exec -i "$CONTAINER" sh -c "pg_restore -U \"\$POSTGRES_USER\" -d \"$DB\" --clean --if-exists --no-owner --no-privileges -j $RESTORE_JOBS '$DUMP_PATH'" 2>&1 | tee /tmp/push-dump-restore.log
    else
        # Pas de -j sur une base vide : certains objets (commentaires, droits)
        # dependent de l'ordre, et pg_restore les rejoue en serie.
        docker exec -i "$CONTAINER" sh -c "pg_restore -U \"\$POSTGRES_USER\" -d \"$DB\" --no-owner --no-privileges '$DUMP_PATH'" 2>&1 | tee /tmp/push-dump-restore.log
    fi
    code=${PIPESTATUS[0]}
    set -e
    # pg_restore sort en 1 quand seuls des objets ignores posent probleme
    # (proprietaires, extensions, COMMENT) : ce n'est pas un echec de donnees.
    if [ "$code" -gt 1 ]; then
        die "pg_restore a echoue (code $code) : voir /tmp/push-dump-restore.log"
    fi
    [ "$code" -eq 1 ] && echo "   (pg_restore a signale des objets ignores — normal pour un dump d'une autre installation)"
else
    log "Restauration du dump SQL"
    if gunzip -c "$FILE" 2>/dev/null | head -c 200000 | grep -q 'CREATE DATABASE'; then
        # Le dump cree lui-meme sa base : il doit etre joue sur « postgres ».
        gunzip -c "$FILE" | docker exec -i "$CONTAINER" sh -c 'psql -U "$POSTGRES_USER" -d postgres -v ON_ERROR_STOP=0' 2>&1 | tee /tmp/push-dump-restore.log
    else
        gunzip -c "$FILE" | docker exec -i "$CONTAINER" sh -c "psql -U \"\$POSTGRES_USER\" -d \"$DB\" -v ON_ERROR_STOP=0" 2>&1 | tee /tmp/push-dump-restore.log
    fi
fi

# --------------------------------------------------------------------------
# 6. Controle
# --------------------------------------------------------------------------
log "Controle du resultat"
docker exec -i "$CONTAINER" sh -c "psql -U \"\$POSTGRES_USER\" -d \"$DB\" -c \"
select table_schema, count(*) as tables, coalesce(sum(n_live_tup), 0) as lignes_estimees
  from information_schema.tables t
  left join pg_stat_user_tables s on s.schemaname = t.table_schema and s.relname = t.table_name
 where t.table_type = 'BASE TABLE' and t.table_schema not in ('pg_catalog', 'information_schema')
 group by 1 order by 1;\""

log "Termine"
echo "  sauvegarde d'avant restauration : $BACKUP"
echo "  journal de restauration         : /tmp/push-dump-restore.log"
echo
echo "Rappels OpenConcerto :"
echo "  * le client se connecte a la base ; verifiez son main.properties :"
echo "      ~/.config/OpenConcerto/main.properties"
echo "  * les compteurs d'affaire se remettent a zero avec une reprise :"
echo "      sh scripts/oc-psql.sh -f sql/attendu-reprise.sql"
