#!/usr/bin/env bash
#
# Export SQL de la STRUCTURE d'une base OpenConcerto 1.7.6 (schemata, tables,
# colonnes, index, contraintes, sequences, vues, fonctions) SANS les donnees.
#
# Le fichier produit se reapplique tel quel sur une base vide :
#   createdb nouvelle_base && psql -d nouvelle_base -f structure.sql
#
# Usage (dans la VM, ou sur le poste si psql/pg_dump sont installes) :
#   bash dump-structure-sql.sh
#   bash dump-structure-sql.sh -b OpenConcerto -o /tmp/structure.sql
#   bash dump-structure-sql.sh -s OpenConcerto42          # un seul schema
#   bash dump-structure-sql.sh -s OpenConcerto42 -t OpenConcerto42.FACTURE_FOURNISSEUR_ELEMENT
#   bash dump-structure-sql.sh --patch                    # + patch minimal ID_COMMANDE_ELEMENT
#   bash dump-structure-sql.sh --with-data                # dump complet (structure + donnees)
#
# Options :
#   -b BASE      base a dumper           (defaut : OpenConcerto)
#   -H HOTE      hote postgres           (defaut : 127.0.0.1)
#   -p PORT      port postgres           (defaut : 5433, port publie de la stack)
#   -U USER      role postgres           (defaut : openconcerto)
#   -P MDP       mot de passe            (defaut : POSTGRES_PASSWORD du .env de la stack)
#   -o FICHIER   fichier de sortie       (defaut : <dumps>/structure-<base>-schema.sql)
#   -s SCHEMA    ne dumper que ce schema (ex. OpenConcerto42, Default)
#   -t TABLE     ne dumper que cette table (ex. OpenConcerto42.FACTURE_FOURNISSEUR_ELEMENT)
#   --with-data  structure ET donnees (au lieu de la structure seule)
#   --clean      ajoute --clean --if-exists (recreation complete d'une base)
#   --patch      ecrit en plus <sortie>-patch-id-commande-element.sql :
#                le correctif minimal (colonne + contrainte + index) par schema
#                ou la colonne manque. Sert a corriger la production.
#   -n           dry-run : affiche les commandes, n'ecrit rien
#   -h|--help    cette aide
#
# Variables d'environnement reconnues : PGPASSWORD, PGHOST, PGPORT, PGUSER.

set -euo pipefail

BASE="OpenConcerto"
HOST="127.0.0.1"
PORT="5433"
USER_PG="openconcerto"
PASSWORD="${PGPASSWORD:-}"
OUTFILE=""
SCHEMA=""
TABLE=""
WITH_DATA=0
CLEAN=0
PATCH=0
DRY=0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${OC176_STACK_DIR:-$SCRIPT_DIR/../docker/openconcerto-1.7.6}"
ENV_FILE="${OC176_ENV_FILE:-$STACK_DIR/.env}"
DUMP_DIR="${OC176_DUMP_DIR:-$SCRIPT_DIR/../dumps}"

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -b) BASE="$2"; shift 2 ;;
        -H) HOST="$2"; shift 2 ;;
        -p) PORT="$2"; shift 2 ;;
        -U) USER_PG="$2"; shift 2 ;;
        -P) PASSWORD="$2"; shift 2 ;;
        -o) OUTFILE="$2"; shift 2 ;;
        -s) SCHEMA="$2"; shift 2 ;;
        -t) TABLE="$2"; shift 2 ;;
        --with-data) WITH_DATA=1; shift ;;
        --clean) CLEAN=1; shift ;;
        --patch) PATCH=1; shift ;;
        -n) DRY=1; shift ;;
        -h|--help) usage 0 ;;
        *) echo "option inconnue : $1" >&2; usage 1 ;;
    esac
done

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

command -v pg_dump >/dev/null 2>&1 || die "'pg_dump' introuvable (paquet postgresql-client)."

# ------------------------------------------------- mot de passe depuis le .env
if [ -z "$PASSWORD" ] && [ -f "$ENV_FILE" ]; then
    PASSWORD="$(sed -n 's/^POSTGRES_PASSWORD=//p' "$ENV_FILE" | head -n 1)"
    [ -n "$PASSWORD" ] && info "mot de passe lu dans $ENV_FILE"
fi
[ -n "$PASSWORD" ] || die "Mot de passe inconnu : donne -P MDP ou renseigne PGPASSWORD."

# ---------------------------------------------------------- fichier de sortie
if [ -z "$OUTFILE" ]; then
    SUFFIX="schema"
    [ "$WITH_DATA" = "1" ] && SUFFIX="full"
    mkdir -p "$DUMP_DIR"
    OUTFILE="$DUMP_DIR/structure-${BASE}-${SUFFIX}.sql"
fi
OUTDIR="$(dirname "$OUTFILE")"
mkdir -p "$OUTDIR" 2>/dev/null || die "Dossier de sortie inaccessible : $OUTDIR"

# ------------------------------------------------------- construction du dump
DUMP_ARGS=(--host="$HOST" --port="$PORT" --username="$USER_PG" --dbname="$BASE" --no-owner --no-privileges)
[ "$WITH_DATA" = "0" ] && DUMP_ARGS+=(--schema-only)
[ "$CLEAN" = "1" ] && DUMP_ARGS+=(--clean --if-exists)
[ -n "$SCHEMA" ] && DUMP_ARGS+=(--schema="$SCHEMA")
[ -n "$TABLE" ] && DUMP_ARGS+=(--table="$TABLE")

export PGPASSWORD="$PASSWORD"

CMD=(pg_dump "${DUMP_ARGS[@]}" --file="$OUTFILE")

log "Dump de la structure"
info "base    : $BASE"
info "serveur : $HOST:$PORT (role $USER_PG)"
info "portee  : ${SCHEMA:-tous les schemas}${TABLE:+ / table $TABLE}"
info "donnees : $([ "$WITH_DATA" = "1" ] && echo 'incluses' || echo 'EXCLUES (structure seule)')"
info "sortie  : $OUTFILE"

if [ "$DRY" = "1" ]; then
    echo
    echo "Dry-run — commande reellement executee :"
    printf '  %s\n' "${CMD[*]}"
    exit 0
fi

"${CMD[@]}" || die "pg_dump a echoue."

[ -s "$OUTFILE" ] || die "Le fichier de dump est vide : $OUTFILE"

# --------------------------------------------------------------- controles
TABLES=$(grep -c '^CREATE TABLE' "$OUTFILE" || true)
INDEXES=$(grep -c '^CREATE INDEX' "$OUTFILE" || true)
COLONNE=$(grep -c 'ID_COMMANDE_ELEMENT' "$OUTFILE" || true)
info "tables creees : $TABLES"
info "index crees   : $INDEXES"
info "occurrences ID_COMMANDE_ELEMENT : $COLONNE"

if [ "$COLONNE" = "0" ]; then
    echo
    echo "ATTENTION : ID_COMMANDE_ELEMENT n'apparait PAS dans le dump."
    echo "Si la base n'a pas ete corrigee, le correctif n'est pas inclus."
fi

# ------------------------------------------------- patch minimal (option --patch)
if [ "$PATCH" = "1" ]; then
    PATCH_FILE="${OUTFILE%.sql}-patch-id-commande-element.sql"
    log "Patch minimal ID_COMMANDE_ELEMENT"
    info "sortie : $PATCH_FILE"

    SCHEMAS=$(PGPASSWORD="$PASSWORD" psql -h "$HOST" -p "$PORT" -U "$USER_PG" -d "$BASE" -At -F'|' -c \
        "SELECT table_schema,
                bool_or(column_name = 'ID_COMMANDE_ELEMENT')
           FROM information_schema.columns
          WHERE table_name = 'FACTURE_FOURNISSEUR_ELEMENT'
          GROUP BY 1 ORDER BY 1") || die "Lecture information_schema impossible."

    if [ "$DRY" = "1" ]; then
        printf '%s\n' "$SCHEMAS"
        exit 0
    fi

    {
        echo "-- Correctif minimal OpenConcerto 1.7.6 : colonne ID_COMMANDE_ELEMENT"
        echo "-- sur FACTURE_FOURNISSEUR_ELEMENT, pour les schemas qui en sont depourvus."
        echo "-- Genere le $(date '+%Y-%m-%d %H:%M:%S') sur $BASE ($HOST:$PORT)."
        echo
        while IFS='|' read -r sch present; do
            [ -n "$sch" ] || continue
            if [ "$present" = "t" ]; then
                echo "-- Schema $sch : colonne deja presente, rien a faire."
                continue
            fi
            echo "BEGIN;"
            echo "SET LOCAL search_path TO \"$sch\";"
            echo "ALTER TABLE \"FACTURE_FOURNISSEUR_ELEMENT\""
            echo "    ADD COLUMN IF NOT EXISTS \"ID_COMMANDE_ELEMENT\" int DEFAULT 1;"
            echo "DO \$\$"
            echo "BEGIN"
            echo "    IF NOT EXISTS ("
            echo "        SELECT 1 FROM pg_constraint c"
            echo "        JOIN pg_class t ON t.oid = c.conrelid"
            echo "        JOIN pg_namespace n ON n.oid = t.relnamespace"
            echo "        WHERE n.nspname = '$sch'"
            echo "          AND t.relname = 'FACTURE_FOURNISSEUR_ELEMENT'"
            echo "          AND c.conname = 'FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey'"
            echo "    ) THEN"
            echo "        ALTER TABLE \"FACTURE_FOURNISSEUR_ELEMENT\""
            echo "            ADD CONSTRAINT \"FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey\""
            echo "            FOREIGN KEY (\"ID_COMMANDE_ELEMENT\") REFERENCES \"COMMANDE_ELEMENT\" (\"ID\");"
            echo "    END IF;"
            echo "END \$\$;"
            echo "CREATE INDEX IF NOT EXISTS \"FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fki\""
            echo "    ON \"FACTURE_FOURNISSEUR_ELEMENT\" (\"ID_COMMANDE_ELEMENT\");"
            echo "COMMIT;"
            echo
        done <<< "$SCHEMAS"
    } > "$PATCH_FILE"

    info "patch ecrit : $PATCH_FILE"
    grep -c 'ADD COLUMN' "$PATCH_FILE" >/dev/null 2>&1 || true
    echo
    echo "Schemas traites :"
    printf '%s\n' "$SCHEMAS" | sed 's/^/  /'
fi

echo
info "Termine."
