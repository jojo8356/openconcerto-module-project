#!/usr/bin/env bash
#
# Correctif OpenConcerto 1.7.6 : ajoute FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT
#
# Erreur corrigée :
#   "ID_COMMANDE_ELEMENT is not in table /FACTURE_FOURNISSEUR_ELEMENT/"
#   (transfert des commandes fournisseur vers les factures fournisseur)
#
# 1. Vérifie les outils et la connexion à la base
# 2. Sauvegarde la base (avant modification)
# 3. Applique sql/fix-facture-fournisseur-element-id-commande-element.sql
# 4. Vérifie la colonne
# 5. Crée un dump complet à jour, à donner à une autre installation
#
# Usage :
#   ./fix-facture-fournisseur-element.sh [-d base] [-s schema] [-U role] [-y]
#   ./fix-facture-fournisseur-element.sh -D CONTENEUR [-d base] [-s schema] [-y]
#   ./fix-facture-fournisseur-element.sh --check [-D CONTENEUR] [-d base] [-s schema]
#
# Options :
#   -D CONTENEUR  faire tourner psql et pg_dump DANS le conteneur Docker
#                 (aucun client PostgreSQL à installer sur l'hôte ; les
#                 sauvegardes sont écrites sur l'hôte)
#   -d BASE       base de données (défaut : $PGDATABASE ou OpenConcerto)
#   -s SCHEMA     schéma OpenConcerto (défaut : OpenConcerto42)
#   -U ROLE       rôle SQL (défaut : PGUSER, sinon openconcerto)
#   -h HOTE       hôte PostgreSQL  (mode hôte uniquement)
#   -p PORT       port PostgreSQL  (mode hôte uniquement)
#   -o DOSSIER    dossier de sortie (défaut : oc-update-AAAA-MM-JJ)
#   -y            aucune confirmation
#   --check       ne modifie rien : dit seulement si la colonne est là
#                 (code 0 = présente, 3 = absente). À lancer AVANT et APRÈS.
#
# Exemples :
#   # base dans un conteneur Docker (le cas courant d'une installation 1.7.6)
#   ./fix-facture-fournisseur-element.sh --check -D openconcerto176-db-1 -d dump1009
#   ./fix-facture-fournisseur-element.sh -D openconcerto176-db-1 -d dump1009 -y
#
#   # base joignable directement (variables PG* ou ~/.pgpass)
#   ./fix-facture-fournisseur-element.sh -d OpenConcerto -U postgres -y
#
# Le SQL appliqué est exactement le fichier livré sql/fix-…-id-commande-element.sql :
# ce script ne fait que l'entourer (sauvegarde, vérifications, dump final).

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
FIX_SOURCE="$ROOT_DIR/sql/fix-facture-fournisseur-element-id-commande-element.sql"

DB="${PGDATABASE:-OpenConcerto}"
SCHEMA="OpenConcerto42"
SQL_USER="${PGUSER:-openconcerto}"
CONTAINER=""
OUTDIR=""
ASSUME_YES=0
CHECK_ONLY=0

usage() {
    sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# Les options longues sont retirees avant getopts, qui les lirait caractere par
# caractere (« --check » devient six options inconnues).
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        --help) usage 0 ;;
        *) ARGS+=("$arg") ;;
    esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}

while getopts ":D:d:s:U:h:p:o:y" opt; do
    case "$opt" in
        D) CONTAINER="$OPTARG" ;;
        d) DB="$OPTARG" ;;
        s) SCHEMA="$OPTARG" ;;
        U) SQL_USER="$OPTARG" ;;
        h) export PGHOST="$OPTARG" ;;
        p) export PGPORT="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        y) ASSUME_YES=1 ;;
        *) usage 1 ;;
    esac
done
shift $((OPTIND - 1))
[ $# -eq 0 ] || { echo "Argument inattendu : $1" >&2; usage 1; }

[ -n "$OUTDIR" ] || OUTDIR="oc-update-$(date +%Y-%m-%d)"

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------------ exécution
# Deux modes : client PostgreSQL local, ou psql/pg_dump dans le conteneur.
# Dans les deux cas le SQL passe par l'entrée standard : un fichier de l'hôte
# n'est pas lisible depuis le conteneur.
if [ -n "$CONTAINER" ]; then
    psql_run() { docker exec -i "$CONTAINER" psql -U "$SQL_USER" -d "$DB" "$@" ; }
else
    export PGUSER="$SQL_USER"
    psql_run() { psql -d "$DB" "$@" ; }
fi

# Sauvegarde la base dans un fichier, en refusant un fichier vide.
# Dans un conteneur, pg_dump ecrit dans le conteneur puis on copie : passer par
# la sortie standard du conteneur a produit un fichier de 0 octet en CI.
# Usage : dump_database FICHIER [options pg_dump...]
dump_database() {
    out="$1"
    shift
    err=$(mktemp)
    if [ -n "$CONTAINER" ]; then
        tmp="/tmp/oc-dump-$$.dmp"
        if ! docker exec "$CONTAINER" pg_dump -U "$SQL_USER" -d "$DB" "$@" -f "$tmp" 2>"$err"; then
            sed 's/^/  pg_dump : /' "$err" >&2
            rm -f "$err" "$out"
            die "pg_dump a échoué (message ci-dessus)."
        fi
        docker cp "$CONTAINER:$tmp" "$out" >/dev/null 2>&1 \
            || { docker exec "$CONTAINER" rm -f "$tmp"; rm -f "$err" "$out"; die "Copie du dump depuis '$CONTAINER' impossible."; }
        docker exec "$CONTAINER" rm -f "$tmp" >/dev/null 2>&1 || true
    else
        if ! pg_dump -d "$DB" "$@" -f "$out" 2>"$err"; then
            sed 's/^/  pg_dump : /' "$err" >&2
            rm -f "$err" "$out"
            die "pg_dump a échoué (message ci-dessus)."
        fi
    fi
    rm -f "$err"
    [ -s "$out" ] || die "Sauvegarde vide ($out) : arrêt, aucune modification."
}

# ---------------------------------------------------------------- 1. Vérifications
log "Vérification des outils"
if [ -n "$CONTAINER" ]; then
    command -v docker >/dev/null 2>&1 || die "docker introuvable."
    docker inspect -f '{{.State.Running}}' "$CONTAINER" >/dev/null 2>&1 \
        || die "Conteneur '$CONTAINER' introuvable ou arrêté (docker ps)."
    for cmd in psql pg_dump; do
        docker exec "$CONTAINER" sh -c "command -v $cmd" >/dev/null 2>&1 \
            || die "'$cmd' absent du conteneur '$CONTAINER'."
    done
    echo "mode conteneur : $CONTAINER"
else
    for cmd in psql pg_dump; do
        command -v "$cmd" >/dev/null 2>&1 \
            || die "'$cmd' introuvable. Installe le client PostgreSQL 15+, ou utilise -D CONTENEUR."
    done
    pg_dump --version
fi

log "Connexion à la base '$DB' (rôle $SQL_USER)"
echo "SELECT current_database();" | psql_run -v ON_ERROR_STOP=1 -tA \
    || die "Impossible de se connecter à '$DB' (vérifie -d, -U, -h, -p ou -D)."

TABLE_OK=$(echo "SELECT count(*) FROM information_schema.tables WHERE table_schema='$SCHEMA' AND table_name='FACTURE_FOURNISSEUR_ELEMENT'" | psql_run -tA)
CMD_OK=$(echo "SELECT count(*) FROM information_schema.tables WHERE table_schema='$SCHEMA' AND table_name='COMMANDE_ELEMENT'" | psql_run -tA)
[ "$TABLE_OK" = "1" ] || die "Table $SCHEMA.FACTURE_FOURNISSEUR_ELEMENT introuvable. Vérifie -d et -s."
[ "$CMD_OK" = "1" ] || die "Table $SCHEMA.COMMANDE_ELEMENT introuvable. Vérifie -d et -s."

COLUMN_STATE() {
    echo "SELECT coalesce((SELECT data_type || '|' || coalesce(column_default, '') FROM information_schema.columns WHERE table_schema='$SCHEMA' AND table_name='FACTURE_FOURNISSEUR_ELEMENT' AND column_name='ID_COMMANDE_ELEMENT'), 'ABSENTE')" | psql_run -tA
}

# ------------------------------------------------------------------- 2. Contrôle
STATE=$(COLUMN_STATE)
log "État de $SCHEMA.FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT"
echo "ID_COMMANDE_ELEMENT : $STATE"

if [ "$CHECK_ONLY" -eq 1 ]; then
    case "$STATE" in
        ABSENTE) echo "RÉSULTAT : colonne absente -> le transfert échouera. Lancer ce script sans --check." ; exit 3 ;;
        *) echo "RÉSULTAT : colonne présente -> le transfert est possible." ; exit 0 ;;
    esac
fi

[ -f "$FIX_SOURCE" ] || die "Fichier SQL introuvable : $FIX_SOURCE"

FIXED=0
if [ "$STATE" != "ABSENTE" ]; then
    echo "La colonne est déjà là : rien à modifier (le script reste sans effet)."
else
    if [ "$ASSUME_YES" -ne 1 ]; then
        printf '\nLe script va sauvegarder la base "%s", appliquer le correctif sur le schéma "%s"\net créer un dump dans "%s".\nContinuer ? [o/N] ' "$DB" "$SCHEMA" "$OUTDIR"
        read -r answer
        case "$answer" in
            o | O | oui | OUI | y | Y) ;;
            *) echo "Annulé." ; exit 0 ;;
        esac
    fi

    mkdir -p "$OUTDIR"
    DATE_TAG=$(date +%Y-%m-%d_%H%M)
    BACKUP="$OUTDIR/backup_avant_fix_${DATE_TAG}.dumpsql"
    FIXSQL="$OUTDIR/fix_${DATE_TAG}.sql"

    # ------------------------------------------------------------ 3. Sauvegarde
    log "Sauvegarde avant correctif : $BACKUP"
    dump_database "$BACKUP" -Fc
    echo "Sauvegarde : $(wc -c < "$BACKUP") octets"

    # -------------------------------------------------------------- 4. Correctif
    log "Application de $FIX_SOURCE"
    # Le nom de schéma apparaît en identifiant ("OpenConcerto42"), en littéral
    # ('OpenConcerto42') et dans les messages d'erreur : un seul remplacement.
    sed "s/OpenConcerto42/$SCHEMA/g" "$FIX_SOURCE" > "$FIXSQL"
    psql_run -v ON_ERROR_STOP=1 -q < "$FIXSQL" \
        || die "Le correctif a échoué. La transaction a été annulée ; la sauvegarde est dans $BACKUP."
    FIXED=1
fi

# -------------------------------------------------------------- 5. Vérification
log "Vérification de la colonne"
STATE=$(COLUMN_STATE)
echo "ID_COMMANDE_ELEMENT : $STATE"
case "$STATE" in
    integer\|1 | integer\|1::integer) echo "OK : la colonne est en place." ;;
    *) die "Vérification échouée (attendu : integer|1, obtenu : $STATE)." ;;
esac

# -------------------------------------------------------------- 6. Dump à jour
if [ "$FIXED" -eq 1 ]; then
    FINAL_DUMP="$OUTDIR/OpenConcerto-1.7.6-a-jour_${DATE_TAG}.dumpsql"
    log "Création du dump complet à jour : $FINAL_DUMP"
    dump_database "$FINAL_DUMP" -Fc --no-owner --no-privileges
    if command -v sha256sum >/dev/null 2>&1; then
        (cd "$OUTDIR" && sha256sum "$(basename "$FINAL_DUMP")" > "$(basename "$FINAL_DUMP").sha256")
        echo "Empreinte : $FINAL_DUMP.sha256"
    fi
    cat <<EOF

Terminé.

- Base corrigée              : $DB (schéma $SCHEMA)
- Sauvegarde avant correctif : $BACKUP
- Dump à jour à transmettre  : $FINAL_DUMP

Ce dump contient toutes les données de la société : transmets-le par un canal sûr.
EOF
fi

cat <<EOF

Étape suivante : redémarre le client OpenConcerto (il lit le schéma au
démarrage), puis refais le transfert de la commande fournisseur vers la facture
fournisseur. La facture doit porter le lien vers sa commande (colonne
« N° commande » remplie).
EOF
