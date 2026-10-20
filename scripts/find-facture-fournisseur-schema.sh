#!/usr/bin/env bash
#
# Localise la table FACTURE_FOURNISSEUR_ELEMENT et sa colonne ID_COMMANDE_ELEMENT
# dans TOUTES les bases PostgreSQL accessibles, schéma par schéma.
#
# À utiliser quand on ne sait pas quelle base / quel schéma corriger : une
# installation OpenConcerto contient souvent plusieurs bases (prod, père, tests)
# et plusieurs schémas de société (Default, OpenConcerto42, …).
#
# Usage :
#   ./find-facture-fournisseur-schema.sh [-t table] [-c colonne]
#
# Variables :
#   PSQL_CMD   commande de connexion (défaut : "sudo -u postgres psql")
#              ex. PSQL_CMD="psql -h 127.0.0.1 -p 5432 -U postgres"
#
# Sortie : une ligne "base | schéma | t/f" — t = colonne présente,
# f = table présente mais colonne ABSENTE (c'est la cible du correctif
# scripts/fix-facture-fournisseur-element.sh -d <base> -s <schéma>).

set -euo pipefail

TABLE="FACTURE_FOURNISSEUR_ELEMENT"
COLUMN="ID_COMMANDE_ELEMENT"
PSQL_CMD="${PSQL_CMD:-sudo -u postgres psql}"

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while getopts ":t:c:h" opt; do
    case "$opt" in
        t) TABLE="$OPTARG" ;;
        c) COLUMN="$OPTARG" ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

die() { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

# shellcheck disable=SC2206  # découpage volontaire de PSQL_CMD en mots
PSQL=($PSQL_CMD)

DBS=$("${PSQL[@]}" -Atc \
    "SELECT datname FROM pg_database WHERE NOT datistemplate AND datallowconn ORDER BY 1") \
    || die "Impossible de lister les bases avec : ${PSQL[*]}"
[ -n "$DBS" ] || die "Aucune base accessible."

printf '\n%-30s %-18s %s\n' "BASE" "SCHEMA" "COLONNE"
printf '%s\n' "--------------------------------------------------------------------------------"

TARGETS=""
while IFS= read -r db; do
    [ -n "$db" ] || continue
    ROWS=$("${PSQL[@]}" -d "$db" -At -F' | ' -c \
        "SELECT table_schema, bool_or(column_name = '$COLUMN')
           FROM information_schema.columns
          WHERE table_name = '$TABLE'
          GROUP BY 1 ORDER BY 1" 2>/dev/null) || continue
    [ -n "$ROWS" ] || continue
    while IFS= read -r row; do
        [ -n "$row" ] || continue
        printf '%-30s %s\n' "$db" "$row"
        case "$row" in
            *" | f") TARGETS="${TARGETS}  ${db} -> ${row%% | f}"$'\n' ;;
        esac
    done <<< "$ROWS"
done <<< "$DBS"

printf '\n'
if [ -n "$TARGETS" ]; then
    echo "Cibles à corriger (table présente, colonne absente) :"
    printf '%s' "$TARGETS"
    echo
    echo "Correctif (wrapper avec sauvegarde) :"
    printf '%s' "$TARGETS" | sed -n '1p' | sed 's/^  /  .\/scripts\/fix-facture-fournisseur-element.sh -d /; s/ -> / -s /; s/$/ -o \/tmp\/oc-update -y/'
else
    echo "Aucune cible : la colonne '$COLUMN' est partout où la table '$TABLE' existe."
fi
