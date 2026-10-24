#!/usr/bin/env bash
#
# Restaure un dump OpenConcerto (format pg_dump -Fc) dans une base PostgreSQL.
#
# Si la base existe déjà, elle est d'abord sauvegardée, puis supprimée après
# confirmation, et recréée avant la restauration.
#
# Usage :
#   ./restore-openconcerto-dump.sh -f OpenConcerto-1.7.6-a-jour_XXXX.dumpsql [-d base] [-U user] [-h hote] [-p port] [-y]
#
# Variables utiles :
#   LOCALE   locale de la base (défaut : fr_FR.UTF-8)

set -euo pipefail

DUMP=""
DB="OpenConcerto"
ASSUME_YES=0
LOCALE_NAME="${LOCALE:-fr_FR.UTF-8}"
BACKUP_DIR="oc-restore-backup-$(date +%Y-%m-%d_%H%M)"

usage() {
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while getopts ":f:d:U:h:p:y" opt; do
    case "$opt" in
        f) DUMP="$OPTARG" ;;
        d) DB="$OPTARG" ;;
        U) export PGUSER="$OPTARG" ;;
        h) export PGHOST="$OPTARG" ;;
        p) export PGPORT="$OPTARG" ;;
        y) ASSUME_YES=1 ;;
        *) usage 1 ;;
    esac
done

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

[ -n "$DUMP" ] || usage 1
[ -f "$DUMP" ] || die "Fichier introuvable : $DUMP"

for cmd in psql pg_restore pg_dump createdb dropdb; do
    command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' introuvable. Installe le client PostgreSQL (version 15 ou plus)."
done

# Vérification d'intégrité si l'empreinte est fournie à côté du dump
if [ -f "$DUMP.sha256" ] && command -v sha256sum >/dev/null 2>&1; then
    log "Vérification de l'empreinte"
    (cd "$(dirname "$DUMP")" && sha256sum -c "$(basename "$DUMP").sha256") || die "L'empreinte ne correspond pas : le fichier est incomplet ou modifié."
fi

log "Contenu du dump (aperçu)"
# Pas de pipe vers head ici : head ferme le tuyau après 15 lignes, pg_restore
# reçoit SIGPIPE et sort en 141, ce qui — avec pipefail — faisait échouer le
# script sur un dump parfaitement valide.
TOC=$(pg_restore -l "$DUMP") || die "Fichier de dump illisible (il doit être au format -Fc)."
head -n 15 <<< "$TOC"

EXISTS=$(psql -d postgres -tAc "SELECT count(*) FROM pg_database WHERE datname='$DB'")
if [ "$EXISTS" = "1" ]; then
    echo
    echo "ATTENTION : la base '$DB' existe déjà."
    echo "Elle va être sauvegardée dans $BACKUP_DIR/, puis supprimée et remplacée par le dump."
    if [ "$ASSUME_YES" -ne 1 ]; then
        printf 'Continuer ? [o/N] '
        read -r answer
        case "$answer" in
            o|O|oui|OUI|y|Y) ;;
            *) echo "Annulé."; exit 0 ;;
        esac
    fi
    mkdir -p "$BACKUP_DIR"
    log "Sauvegarde de l'ancienne base"
    pg_dump -Fc -d "$DB" -f "$BACKUP_DIR/$DB-avant-restauration.dumpsql" \
        || die "Échec de la sauvegarde. Rien n'a été supprimé."
    dropdb "$DB"
fi

log "Création de la base '$DB'"
createdb -T template0 -E UTF8 -l "$LOCALE_NAME" "$DB" \
    || die "Création impossible. Si la locale '$LOCALE_NAME' n'existe pas, relance avec LOCALE=C.UTF-8 (ou une autre locale installée)."

log "Restauration du dump"
pg_restore --no-owner --no-privileges -d "$DB" "$DUMP" || die "La restauration a signalé des erreurs. Vérifie la sortie ci-dessus."

log "Vérification"
# Le nom du schema varie d'un serveur a l'autre (OpenConcerto42, Default,
# ...) : on cherche la colonne dans TOUS les schemas.
COLS=$(psql -d "$DB" -tAc "SELECT table_schema || '|' || data_type || '|' || column_default FROM information_schema.columns WHERE table_name='FACTURE_FOURNISSEUR_ELEMENT' AND column_name='ID_COMMANDE_ELEMENT' ORDER BY table_schema" 2>/dev/null || true)
if [ -z "$COLS" ]; then
    echo "ATTENTION : ID_COMMANDE_ELEMENT est absente de FACTURE_FOURNISSEUR_ELEMENT."
    echo "La base a bien ete restauree ; appliquer le correctif multi-schemas :"
    echo "  bash scripts/fix-facture-fournisseur-all-schemas.sh -d $DB -y"
else
    echo "Colonne ID_COMMANDE_ELEMENT (schema|type|defaut) :"
    printf '%s\n' "$COLS" | sed 's/^/  /'
fi
echo "Schemas contenant la table FACTURE_FOURNISSEUR_ELEMENT :"
psql -d "$DB" -tAc "SELECT DISTINCT table_schema FROM information_schema.tables WHERE table_name='FACTURE_FOURNISSEUR_ELEMENT' ORDER BY 1" 2>/dev/null | sed 's/^/  /' || true

echo
echo "Terminé. Lance OpenConcerto 1.7.6 avec la base '$DB'."
