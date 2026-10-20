#!/usr/bin/env bash
#
# Recopie une base OpenConcerto native dans la stack Docker 1.7.6, puis y
# applique le correctif FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT.
#
# Enchaîne, dans l'ordre :
#   1. lecture des collations source et cible (un écart fait échouer createdb)
#   2. pg_dump natif vers /tmp, puis déplacement dans le dossier de la stack
#      (l'utilisateur postgres ne peut pas écrire dans un home utilisateur)
#   3. restauration dans le conteneur via restore-openconcerto-dump.sh
#   4. correctif multi-schémas via fix-facture-fournisseur-all-schemas.sh
#   5. contrôle : présence de la colonne et nombre de tables par schéma
#
# Usage :
#   ./copy-openconcerto-db-to-docker.sh [-s base-source] [-t base-cible] [-p port]
#                                       [-U rôle] [-o dossier-stack] [-n] [-y]
#
# Le mot de passe du conteneur est lu dans PGPASSWORD, sinon dans
# POSTGRES_PASSWORD du fichier .env du dossier de la stack.

set -euo pipefail

SOURCE_DB="OpenConcertoKineticTherm"
TARGET_DB="OpenConcerto"
PORT="5433"
TARGET_USER="openconcerto"
STACK_DIR="$HOME/oc-176-docker"
DRY=0
ASSUME_YES=0

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RESTORE="$SCRIPT_DIR/restore-openconcerto-dump.sh"
FIXSCHEMAS="$SCRIPT_DIR/fix-facture-fournisseur-all-schemas.sh"

usage() {
    sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while getopts ":s:t:p:U:o:nyh" opt; do
    case "$opt" in
        s) SOURCE_DB="$OPTARG" ;;
        t) TARGET_DB="$OPTARG" ;;
        p) PORT="$OPTARG" ;;
        U) TARGET_USER="$OPTARG" ;;
        o) STACK_DIR="$OPTARG" ;;
        n) DRY=1 ;;
        y) ASSUME_YES=1 ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }
run() {
    if [ "$DRY" = "1" ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi
}

SUDO_PSQL=(sudo -u postgres psql)
SUDO_DUMP=(sudo -u postgres pg_dump)

# ---------------------------------------------------------------- contrôles
for cmd in sudo pg_dump psql; do
    command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' introuvable dans le PATH."
done
[ -x "$RESTORE" ] || [ -f "$RESTORE" ] || die "Script absent : $RESTORE"
[ -x "$FIXSCHEMAS" ] || [ -f "$FIXSCHEMAS" ] || die "Script absent : $FIXSCHEMAS"
[ -d "$STACK_DIR" ] || die "Dossier de la stack introuvable : $STACK_DIR"

if [ -z "${PGPASSWORD:-}" ] && [ -f "$STACK_DIR/.env" ]; then
    PGPASSWORD=$(sed -n 's/^POSTGRES_PASSWORD=//p' "$STACK_DIR/.env" | head -n 1)
    export PGPASSWORD
fi
[ -n "${PGPASSWORD:-}" ] || die "Mot de passe du conteneur introuvable : exporte PGPASSWORD ou renseigne POSTGRES_PASSWORD dans $STACK_DIR/.env."

log "Collations"
SRC_COLLATE=$("${SUDO_PSQL[@]}" -d "$SOURCE_DB" -tAc \
    "SELECT datcollate FROM pg_database WHERE datname = '$SOURCE_DB'") \
    || die "Base source illisible : '$SOURCE_DB' (serveur natif)."
[ -n "$SRC_COLLATE" ] || die "La base source '$SOURCE_DB' n'existe pas sur le serveur natif."

TGT_COLLATE=$(psql -h 127.0.0.1 -p "$PORT" -U "$TARGET_USER" -d postgres -tAc \
    "SELECT datcollate FROM pg_database WHERE datname = 'postgres'") \
    || die "Conteneur PostgreSQL injoignable sur 127.0.0.1:$PORT (utilisateur '$TARGET_USER')."
echo "  source ($SOURCE_DB, native)  : $SRC_COLLATE"
echo "  cible  ($TARGET_DB, conteneur) : $TGT_COLLATE"
if [ "$SRC_COLLATE" != "$TGT_COLLATE" ]; then
    echo "  ATTENTION : collations différentes. createdb -l '$SRC_COLLATE' échouera si"
    echo "  cette locale n'existe pas dans le conteneur (voir docker/openconcerto-1.7.6)."
fi

# ---------------------------------------------------------------- résumé
DATE_TAG=$(date +%Y%m%d_%H%M)
DUMP_NAME="${SOURCE_DB}_${DATE_TAG}.dumpsql"
DUMP="$STACK_DIR/dumps/$DUMP_NAME"

echo
echo "  source      : $SOURCE_DB (native, port 5432)"
echo "  cible       : $TARGET_DB (conteneur, 127.0.0.1:$PORT)"
echo "  dump        : $DUMP"
echo "  restauration: la base '$TARGET_DB' du conteneur sera SUPPRIMÉE puis recréée"

if [ "$DRY" = "1" ]; then
    echo
    echo "Plan en dry-run :"
    run sudo -u postgres pg_dump -Fc --no-owner --no-privileges -d "$SOURCE_DB" -f "/tmp/$DUMP_NAME"
    run mkdir -p "$STACK_DIR/dumps"
    run sudo mv "/tmp/$DUMP_NAME" "$STACK_DIR/dumps/"
    run bash "$RESTORE" -f "$DUMP" -d "$TARGET_DB" -U "$TARGET_USER" -h 127.0.0.1 -p "$PORT" -y
    run bash "$FIXSCHEMAS" -d "$TARGET_DB" -y
    echo
    echo "Dry-run : rien n'a été modifié."
    exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
    printf '\nContinuer ? [o/N] '
    read -r answer
    case "$answer" in
        o|O|oui|OUI|y|Y) ;;
        *) echo "Annulé."; exit 0 ;;
    esac
fi

# ---------------------------------------------------------------- 1. dump
log "Dump de la base native '$SOURCE_DB'"
run "${SUDO_DUMP[@]}" -Fc --no-owner --no-privileges -d "$SOURCE_DB" -f "/tmp/$DUMP_NAME"
[ -s "/tmp/$DUMP_NAME" ] || die "Dump vide ou absent : /tmp/$DUMP_NAME"
run mkdir -p "$STACK_DIR/dumps"
run sudo mv "/tmp/$DUMP_NAME" "$STACK_DIR/dumps/"
run sudo chown "$(id -un):" "$DUMP"
[ -s "$DUMP" ] || die "Dump introuvable après déplacement : $DUMP"

# ---------------------------------------------------------------- 2. restauration
log "Restauration dans le conteneur"
LOCALE="$SRC_COLLATE" run bash "$RESTORE" -f "$DUMP" -d "$TARGET_DB" \
    -U "$TARGET_USER" -h 127.0.0.1 -p "$PORT" -y

# ---------------------------------------------------------------- 3. correctif
log "Correctif multi-schémas sur '$TARGET_DB'"
PSQL_CMD="psql -h 127.0.0.1 -p $PORT -U $TARGET_USER" \
    run bash "$FIXSCHEMAS" -d "$TARGET_DB" -y

# ---------------------------------------------------------------- 4. contrôle
log "Contrôle"
QUERY_COLS="SELECT table_schema, bool_or(column_name = 'ID_COMMANDE_ELEMENT')
              FROM information_schema.columns
             WHERE table_name = 'FACTURE_FOURNISSEUR_ELEMENT'
             GROUP BY 1 ORDER BY 1"
echo "  colonne ID_COMMANDE_ELEMENT dans la cible :"
psql -h 127.0.0.1 -p "$PORT" -U "$TARGET_USER" -d "$TARGET_DB" -At -F' | ' -c "$QUERY_COLS" \
    | sed 's/^/    /'

QUERY_TABLES="SELECT table_schema, count(*)
                FROM information_schema.tables
               WHERE table_schema NOT LIKE 'pg\_%' AND table_schema <> 'information_schema'
               GROUP BY 1 ORDER BY 1"
echo "  nombre de tables — native :"
"${SUDO_PSQL[@]}" -d "$SOURCE_DB" -At -F' | ' -c "$QUERY_TABLES" | sed 's/^/    /'
echo "  nombre de tables — conteneur :"
psql -h 127.0.0.1 -p "$PORT" -U "$TARGET_USER" -d "$TARGET_DB" -At -F' | ' -c "$QUERY_TABLES" \
    | sed 's/^/    /'

echo
echo "Terminé. Dump conservé dans $DUMP"
echo "Pour brancher le client : hôte 127.0.0.1, port $PORT, base $TARGET_DB, utilisateur $TARGET_USER."
