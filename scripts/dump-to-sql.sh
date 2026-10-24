#!/usr/bin/env bash
#
# Convertit un dump OpenConcerto / PostgreSQL en SQL texte lisible.
#
# Formats gérés :
#   - archive custom pg_dump (-Fc)  -> converti avec "pg_restore -f"  (c'est le
#     format des fichiers *.dumpsql d'OpenConcerto 1.7.6)
#   - dump plain SQL (texte)        -> copié tel quel
#   - archive zip / gz              -> décompressé puis traité
#
# Contrôle de version : si l'archive a été créée par un pg_dump plus récent
# que le pg_restore disponible ("unsupported version"), le script le dit
# clairement au lieu d'échouer muetement.
#
# Usage :
#   bash dump-to-sql.sh -f ~/Téléchargements/OC-v1.7.6-Noon_Dump_2026-10-09.dumpsql
#   bash dump-to-sql.sh -f dump.dumpsql -o /tmp/structure.sql --schema-only
#   bash dump-to-sql.sh -f dump.dumpsql --data-only
#   bash dump-to-sql.sh -f dump.dumpsql -n          # dry-run
#
# Options :
#   -f FICHIER   dump à convertir (obligatoire)
#   -o FICHIER   sortie SQL (défaut : <dump> sans extension + ".sql")
#   --schema-only  structure seule (tables, index, contraintes) : PAS de données
#   --data-only    données seules (COPY/INSERT) : PAS de structure
#   --all          tout (défaut)
#   -n           dry-run : affiche les commandes, ne produit rien
#   -h|--help    cette aide
#
# Variables d'environnement : PGPASSWORD (inutile ici, la conversion est locale),
# PATH doit contenir pg_restore (paquet postgresql-client).

set -euo pipefail

DUMP=""
OUTFILE=""
MODE="all"
DRY=0

usage() {
    sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        -f) DUMP="$2"; shift 2 ;;
        -o) OUTFILE="$2"; shift 2 ;;
        --schema-only) MODE="schema"; shift ;;
        --data-only) MODE="data"; shift ;;
        --all) MODE="all"; shift ;;
        -n) DRY=1; shift ;;
        -h|--help) usage 0 ;;
        *) echo "option inconnue : $1" >&2; usage 1 ;;
    esac
done

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

[ -n "$DUMP" ] || die "Précise le dump avec -f FICHIER."
[ -f "$DUMP" ] || die "Fichier introuvable : $DUMP"

if [ -z "$OUTFILE" ]; then
    OUTFILE="${DUMP%.*}.sql"
fi
OUTDIR="$(dirname "$OUTFILE")"
mkdir -p "$OUTDIR" 2>/dev/null || die "Dossier de sortie inaccessible : $OUTDIR"

# ------------------------------------------------------- identification format
TYPE="inconnu"
MAGIC="$(head -c 4 "$DUMP" | tr -c '[:print:]' '.')"
case "$MAGIC" in
    PGDM*) TYPE="custom" ;;
    "PK\003\004"*|PK*) TYPE="zip" ;;
    "BZh"*) TYPE="gzip" ;;
    "\x1f\x8b"*) TYPE="gzip" ;;
    *) TYPE="texte" ;;
esac

log "Dump analysé"
info "fichier : $DUMP"
info "taille  : $(du -h "$DUMP" | cut -f1)"
info "format  : $TYPE (signature «$MAGIC»)"
info "sortie  : $OUTFILE"

case "$MODE" in
    schema) info "contenu : STRUCTURE seule (aucune donnée)" ;;
    data)   info "contenu : DONNEES seules (aucune structure)" ;;
    all)    info "contenu : structure + données" ;;
esac

if [ "$DRY" = "1" ]; then
    echo
    echo "Dry-run — commandes qui seraient exécutées :"
    case "$TYPE" in
        custom)
            printf '  pg_restore -l "%s"            # contrôle de lisibilité\n' "$DUMP"
            case "$MODE" in
                schema) printf '  pg_restore --schema-only -f "%s" "%s"\n' "$OUTFILE" "$DUMP" ;;
                data)   printf '  pg_restore --data-only   -f "%s" "%s"\n' "$OUTFILE" "$DUMP" ;;
                all)    printf '  pg_restore                -f "%s" "%s"\n' "$OUTFILE" "$DUMP" ;;
            esac
            ;;
        zip)
            printf '  unzip -o -d <dossier> "%s"\n' "$DUMP"
            ;;
        gzip)
            printf '  gunzip -c "%s" > "%s"\n' "$DUMP" "$OUTFILE"
            ;;
        texte)
            printf '  cp "%s" "%s"\n' "$DUMP" "$OUTFILE"
            ;;
    esac
    exit 0
fi

# --------------------------------------------------------------- conversion
case "$TYPE" in
    custom)
        command -v pg_restore >/dev/null 2>&1 || die "'pg_restore' introuvable (paquet postgresql-client)."
        PGVER="$(pg_restore --version | awk '{print $3}')"
        info "pg_restore disponible : $PGVER"

        # contrôle de lisibilité + version de l'archive
        if ! TOC="$(pg_restore -l "$DUMP" 2>&1)"; then
            printf '%s\n' "$TOC" >&2
            echo >&2
            echo "L'archive n'est pas lisible par ce pg_restore." >&2
            echo "Cause habituelle : dump créé par un pg_dump PLUS RÉCENT (ex. 18) que le pg_restore présent (17)." >&2
            echo "→ installe le client PostgreSQL de la même version que le pg_dump d'origine :" >&2
            echo "    sudo apt-get install -y postgresql-client-18" >&2
            die "Conversion impossible avec pg_restore $PGVER."
        fi
        ARCHIVER="$(printf '%s\n' "$TOC" | grep -i "Archive created" || true)"
        [ -n "$ARCHIVER" ] && info "$ARCHIVER"

        RESTORE_ARGS=()
        [ "$MODE" = "schema" ] && RESTORE_ARGS+=(--schema-only)
        [ "$MODE" = "data" ] && RESTORE_ARGS+=(--data-only)

        log "Conversion en SQL texte"
        pg_restore "${RESTORE_ARGS[@]}" --file="$OUTFILE" "$DUMP" \
            || die "pg_restore a échoué (voir message ci-dessus)."
        ;;
    zip)
        command -v unzip >/dev/null 2>&1 || die "'unzip' introuvable."
        TMPD=$(mktemp -d)
        trap 'rm -rf "$TMPD"' EXIT
        unzip -o -q "$DUMP" -d "$TMPD"
        INNER="$(find "$TMPD" -type f | head -n 1)"
        [ -n "$INNER" ] || die "Archive zip vide."
        info "contenu de l'archive : $INNER"
        if head -c 4 "$INNER" | grep -q "PGDM"; then
            pg_restore --file="$OUTFILE" "$INNER" || die "pg_restore a échoué."
        else
            cp "$INNER" "$OUTFILE"
        fi
        ;;
    gzip)
        gunzip -c "$DUMP" > "$OUTFILE" || die "Décompression impossible."
        ;;
    texte)
        cp "$DUMP" "$OUTFILE"
        ;;
    *)
        die "Format non reconnu (signature «$MAGIC»)."
        ;;
esac

[ -s "$OUTFILE" ] || die "Fichier de sortie vide : $OUTFILE"

# ------------------------------------------------------------- contrôles
TABLES=$(grep -c '^CREATE TABLE' "$OUTFILE" || true)
INDEXES=$(grep -c '^CREATE INDEX' "$OUTFILE" || true)
INSERTS=$(grep -c '^COPY ' "$OUTFILE" || true)
COLONNE=$(grep -c 'ID_COMMANDE_ELEMENT' "$OUTFILE" || true)

log "Résultat"
info "fichier : $OUTFILE ($(du -h "$OUTFILE" | cut -f1))"
info "CREATE TABLE : $TABLES"
info "CREATE INDEX : $INDEXES"
info "COPY (données) : $INSERTS"
info "occurrences ID_COMMANDE_ELEMENT : $COLONNE"

echo
info "Terminé."
