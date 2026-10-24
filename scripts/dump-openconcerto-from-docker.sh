#!/usr/bin/env bash
#
# Extrait un dump SQL d'un conteneur PostgreSQL (Docker) vers l'hôte.
#
# pg_dump est lancé DANS le conteneur : le client a donc exactement la même
# version majeure que le serveur (évite "server version mismatch" quand le
# pg_dump de l'hôte est plus ancien que le serveur, ex. client 15 vs serveur 18).
# Le flux sort sur stdout du conteneur et est écrit sur l'hôte : le fichier ne
# reste pas dans le système de fichiers éphémère du conteneur.
#
# Usage :
#   ./dump-openconcerto-from-docker.sh [-c conteneur] [-d base] [-U user] [-o dossier]
#                                      [-f custom|plain|schema|data] [-n schema]... [-t table]... [-y]
#
# Exemples :
#   ./dump-openconcerto-from-docker.sh                                   # dump complet -Fc
#   ./dump-openconcerto-from-docker.sh -f schema                         # DDL seulement
#   ./dump-openconcerto-from-docker.sh -f plain -n OpenConcerto42        # SQL texte, 1 schéma
#
# Base et utilisateur sont détectés depuis le conteneur (POSTGRES_DB / POSTGRES_USER)
# puis contrôlés dans pg_database / pg_roles ; en cas d'erreur le script affiche les
# valeurs réellement disponibles. Forcer avec -d <base> -U <rôle> si besoin.
#
# Le format "custom" produit un dump compatible avec restore-openconcerto-dump.sh.

set -euo pipefail

CONTAINER="${CONTAINER:-openconcerto18-test-db-1}"
# Base et utilisateur : non fixés par défaut. S'ils ne sont pas donnés par -d/-U
# (ou PGDATABASE/PGUSER), ils sont lus dans le conteneur (POSTGRES_DB / POSTGRES_USER
# de l'image officielle postgres), puis vérifiés contre pg_database / pg_roles.
DB="${PGDATABASE:-}"
DBUSER="${PGUSER:-}"
OUTDIR="${OUTDIR:-oc-dump-$(date +%Y-%m-%d_%H%M)}"
FORMAT="custom"
SCHEMAS=()
TABLES=()
ASSUME_YES=0

usage() {
    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while getopts ":c:d:U:o:f:n:t:hy" opt; do
    case "$opt" in
        c) CONTAINER="$OPTARG" ;;
        d) DB="$OPTARG" ;;
        U) DBUSER="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        f) FORMAT="$OPTARG" ;;
        n) SCHEMAS+=("$OPTARG") ;;
        t) TABLES+=("$OPTARG") ;;
        y) ASSUME_YES=1 ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "'docker' introuvable dans le PATH."
docker inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -qx true \
    || die "Conteneur '$CONTAINER' absent ou arrêté. Liste : docker ps -a"

# ---------------------------------------------------------------- résolution
# On ne devine jamais base/utilisateur : on les lit dans le conteneur, puis on
# les vérifie dans pg_roles / pg_database. Une erreur de nom donne ici la liste
# des valeurs possibles au lieu de l'échec obscur de pg_dump.
if [ -z "$DBUSER" ]; then
    DBUSER=$(docker exec -i "$CONTAINER" sh -c 'printf %s "${POSTGRES_USER:-}"')
    [ -n "$DBUSER" ] || DBUSER="postgres"
    echo "Utilisateur non précisé : '$DBUSER' (POSTGRES_USER du conteneur)."
fi
if [ -z "$DB" ]; then
    DB=$(docker exec -i "$CONTAINER" sh -c 'printf %s "${POSTGRES_DB:-}"')
    [ -n "$DB" ] || DB="$DBUSER"
    echo "Base non précisée : '$DB' (POSTGRES_DB du conteneur)."
fi

log "Vérification des identifiants dans le conteneur"
ADMIN=""
for u in "$DBUSER" postgres; do
    if docker exec -i "$CONTAINER" psql -U "$u" -d postgres -Atc "SELECT 1" >/dev/null 2>&1; then
        ADMIN="$u"; break
    fi
done
[ -n "$ADMIN" ] || die "Connexion sans mot de passe impossible (essayé : '$DBUSER', 'postgres'). Passe -U <rôle> ou exporte PGPASSWORD."

ROLES=$(docker exec -i "$CONTAINER" psql -U "$ADMIN" -d postgres -Atc \
    "SELECT string_agg(rolname, ', ' ORDER BY rolname) FROM pg_roles")
case ",$ROLES," in
    *",$DBUSER,"*) ;;
    *) die "Rôle '$DBUSER' inexistant. Rôles disponibles : $ROLES" ;;
esac

DBS=$(docker exec -i "$CONTAINER" psql -U "$ADMIN" -d postgres -Atc \
    "SELECT string_agg(datname, ', ' ORDER BY datname) FROM pg_database WHERE NOT datistemplate")
case ",$DBS," in
    *",$DB,"*) ;;
    *) die "Base '$DB' inexistante. Bases disponibles : $DBS" ;;
esac
echo "Rôle '$DBUSER' : OK (rôles : $ROLES)"
echo "Base '$DB' : OK (bases : $DBS)"

case "$FORMAT" in
    custom) ARGS=(-Fc);            EXT="dumpsql" ;;
    plain)  ARGS=();               EXT="sql" ;;
    schema) ARGS=(--schema-only);  EXT="structure.sql" ;;
    data)   ARGS=(--data-only);    EXT="data.sql" ;;
    *) die "Format inconnu : '$FORMAT' (custom | plain | schema | data)." ;;
esac

ARGS=(pg_dump -U "$DBUSER" -d "$DB" --no-owner --no-privileges "${ARGS[@]}")
for s in ${SCHEMAS[@]+"${SCHEMAS[@]}"}; do ARGS+=(-n "$s"); done
for t in ${TABLES[@]+"${TABLES[@]}"};  do ARGS+=(-t "$t"); done

mkdir -p "$OUTDIR"
DATE_TAG=$(date +%Y-%m-%d_%H%M)
OUT="$OUTDIR/${DB}_${FORMAT}_${DATE_TAG}.${EXT}"

if [ "$ASSUME_YES" -ne 1 ]; then
    printf '\nConteneur : %s\nBase      : %s\nUtilisateur : %s\nCommande  : %s\nSortie    : %s\nContinuer ? [o/N] ' \
        "$CONTAINER" "$DB" "$DBUSER" "${ARGS[*]}" "$OUT"
    read -r answer
    case "$answer" in
        o|O|oui|OUI|y|Y) ;;
        *) echo "Annulé."; exit 0 ;;
    esac
fi

log "Version du client pg_dump du conteneur"
docker exec -i "$CONTAINER" pg_dump --version

log "Extraction du dump"
# -i sans -t : pas de TTY, donc pas d'altération du flux binaire (-Fc)
if ! docker exec -i "$CONTAINER" "${ARGS[@]}" > "$OUT"; then
    rm -f "$OUT"
    die "pg_dump a échoué. Vérifie la base, l'utilisateur et les options de schéma/table."
fi

[ -s "$OUT" ] || die "Fichier vide : $OUT"

log "Contrôle du fichier"
case "$FORMAT" in
    custom)
        MAGIC=$(head -c 5 "$OUT")
        [ "$MAGIC" = "PGDMP" ] || die "Signature attendue 'PGDMP' absente : le fichier n'est pas un dump -Fc."
        echo "Signature PGDMP : OK"
        ;;
    *)
        head -n 3 "$OUT"
        ;;
esac
echo "Taille : $(wc -c < "$OUT") octets"

if command -v sha256sum >/dev/null 2>&1; then
    (cd "$OUTDIR" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")
    echo "Empreinte : $OUT.sha256"
fi

cat <<EOF

Terminé.

- Dump              : $OUT
- Conteneur source  : $CONTAINER (base '$DB')

Pour restaurer ce dump sur une autre installation :
  ./scripts/restore-openconcerto-dump.sh -f $OUT -d OpenConcerto

Ce dump contient toutes les données des sociétés : transmets-le par un canal sûr.
EOF
