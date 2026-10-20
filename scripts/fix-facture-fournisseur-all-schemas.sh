#!/usr/bin/env bash
#
# Applique le correctif FACTURE_FOURNISSEUR_ELEMENT.ID_COMMANDE_ELEMENT à TOUS
# les schémas d'une base qui contiennent la table — y compris le schéma modèle
# "Default", sans quoi les sociétés créées ensuite repartent sans la colonne.
#
# Contrairement à fix-facture-fournisseur-element.sh (un schéma à la fois, avec
# sauvegarde complète), ce script découvre les schémas tout seul et enchaîne.
# Le SQL est passé sur stdin de psql : aucun fichier temporaire à faire lire par
# l'utilisateur postgres.
#
# Usage :
#   ./fix-facture-fournisseur-all-schemas.sh -d BASE [-n] [-y]
#   ./fix-facture-fournisseur-all-schemas.sh -A [-n] [-y]
#
# Options :
#   -d BASE   base à traiter
#   -A        toutes les bases connectables du serveur
#   -n        dry-run : affiche ce qui serait corrigé, ne modifie rien
#   -y        pas de confirmation
#   -t TABLE  autre table (défaut FACTURE_FOURNISSEUR_ELEMENT)
#   -c COL    autre colonne (défaut ID_COMMANDE_ELEMENT)
#
# Variables :
#   PSQL_CMD  commande de connexion (défaut : "sudo -u postgres psql")

set -euo pipefail

DB=""
ALL=0
DRY=0
ASSUME_YES=0
TABLE="FACTURE_FOURNISSEUR_ELEMENT"
COLUMN="ID_COMMANDE_ELEMENT"
PSQL_CMD="${PSQL_CMD:-sudo -u postgres psql}"

usage() {
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while getopts ":d:Aynt:c:h" opt; do
    case "$opt" in
        d) DB="$OPTARG" ;;
        A) ALL=1 ;;
        n) DRY=1 ;;
        y) ASSUME_YES=1 ;;
        t) TABLE="$OPTARG" ;;
        c) COLUMN="$OPTARG" ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

[ -n "$DB" ] || [ "$ALL" = "1" ] || die "Précise une base avec -d BASE, ou -A pour toutes."
[ -n "$DB" ] && [ "$ALL" = "1" ] && die "-d et -A sont exclusifs."

# shellcheck disable=SC2206  # découpage volontaire de PSQL_CMD en mots
PSQL=($PSQL_CMD)

# ---------------------------------------------------------------- découverte
if [ "$ALL" = "1" ]; then
    BASES=$("${PSQL[@]}" -Atc \
        "SELECT datname FROM pg_database WHERE NOT datistemplate AND datallowconn ORDER BY 1") \
        || die "Impossible de lister les bases avec : ${PSQL[*]}"
else
    BASES="$DB"
fi

verif_colonne() {
    "${PSQL[@]}" -d "$1" -tAc \
        "SELECT data_type || '|' || column_default
           FROM information_schema.columns
          WHERE table_schema = '$2' AND table_name = '$TABLE' AND column_name = '$COLUMN'" \
        2>/dev/null || true
}

# ---------------------------------------------------------------- correctif
# Même SQL que sql/fix-facture-fournisseur-element-id-commande-element.sql,
# avec __SCHEMA__ remplacé. Idempotent, dans une transaction.
sql_pour() {
    sed "s/__SCHEMA__/$1/g" <<'EOSQL'
BEGIN;

SET LOCAL search_path TO "__SCHEMA__";

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema = '__SCHEMA__' AND table_name = 'FACTURE_FOURNISSEUR_ELEMENT') THEN
        RAISE EXCEPTION 'Table __SCHEMA__.FACTURE_FOURNISSEUR_ELEMENT introuvable';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables
                   WHERE table_schema = '__SCHEMA__' AND table_name = 'COMMANDE_ELEMENT') THEN
        RAISE EXCEPTION 'Table __SCHEMA__.COMMANDE_ELEMENT introuvable';
    END IF;
END $$;

ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT"
    ADD COLUMN IF NOT EXISTS "ID_COMMANDE_ELEMENT" int DEFAULT 1;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = '__SCHEMA__'
          AND t.relname = 'FACTURE_FOURNISSEUR_ELEMENT'
          AND c.conname = 'FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey'
    ) THEN
        ALTER TABLE "FACTURE_FOURNISSEUR_ELEMENT"
            ADD CONSTRAINT "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fkey"
            FOREIGN KEY ("ID_COMMANDE_ELEMENT") REFERENCES "COMMANDE_ELEMENT" ("ID");
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS "FACTURE_FOURNISSEUR_ELEMENT_ID_COMMANDE_ELEMENT_fki"
    ON "FACTURE_FOURNISSEUR_ELEMENT" ("ID_COMMANDE_ELEMENT");

COMMIT;
EOSQL
}

# ---------------------------------------------------------------- collecte
# Une base dont la lecture échoue est SIGNALÉE, jamais ignorée en silence :
# un scan muet ferait croire à tort qu'il n'y a rien à corriger.
PLAN=""       # lignes "base|schema" à corriger
IGNOREES=""   # bases non analysées, avec la première ligne d'erreur
ERRTMP=$(mktemp)
trap 'rm -f "$ERRTMP"' EXIT

while IFS= read -r base; do
    [ -n "$base" ] || continue
    RC=0
    ROWS=$("${PSQL[@]}" -d "$base" -At -F'|' -c \
        "SELECT table_schema, bool_or(column_name = '$COLUMN')
           FROM information_schema.columns
          WHERE table_name = '$TABLE'
          GROUP BY 1 ORDER BY 1" 2>"$ERRTMP") || RC=$?
    if [ "$RC" -ne 0 ]; then
        IGNOREES="${IGNOREES}  ${base} : $(head -n 1 "$ERRTMP")"$'\n'
        continue
    fi
    [ -n "$ROWS" ] || continue
    while IFS='|' read -r schema present; do
        [ -n "$schema" ] || continue
        [ "$present" = "f" ] || continue
        # le schéma modèle "Default" est traité comme les autres : sans lui,
        # les sociétés créées ensuite repartiraient sans la colonne
        PLAN="${PLAN}${base}|${schema}"$'\n'
    done <<< "$ROWS"
done <<< "$BASES"

if [ -n "$IGNOREES" ]; then
    printf '\nATTENTION — bases NON ANALYSÉES (psql en échec) :\n' >&2
    printf '%s' "$IGNOREES" >&2
    echo "Le bilan ci-dessous est donc INCOMPLET." >&2
fi

if [ -z "$PLAN" ]; then
    if [ -n "$IGNOREES" ]; then
        echo "Impossible de conclure : au moins une base n'a pas pu être lue." >&2
        exit 1
    fi
    echo "Rien à faire : la colonne '$COLUMN' est présente partout où '$TABLE' existe."
    exit 0
fi

echo
printf '%-30s %-18s %s\n' "BASE" "SCHEMA" "ACTION"
printf '%s\n' "--------------------------------------------------------------------------"
printf '%s' "$PLAN" | while IFS='|' read -r base schema; do
    [ -n "$base" ] || continue
    printf '%-30s %-18s %s\n' "$base" "$schema" \
        "$([ "$DRY" = "1" ] && echo 'à corriger (dry-run)' || echo 'correction')"
done

if [ "$DRY" = "1" ]; then
    echo
    echo "Dry-run : rien n'a été modifié. Commandes prêtes à copier-coller :"
    printf '%s' "$PLAN" | cut -d'|' -f1 | sort -u | while IFS= read -r b; do
        [ -n "$b" ] || continue
        printf '  bash %s -d %s\n' "$0" "$b"
    done
    printf '  bash %s -A      # toutes les bases d un coup\n' "$0"
    # bilan incomplet si des bases n'ont pas pu être lues : le signaler par le code retour
    [ -z "$IGNOREES" ] || exit 1
    exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
    printf '\nAppliquer le correctif à ces schémas ? [o/N] '
    read -r answer
    case "$answer" in
        o|O|oui|OUI|y|Y) ;;
        *) echo "Annulé."; exit 0 ;;
    esac
fi

# ---------------------------------------------------------------- application
ERREURS=0
while IFS='|' read -r base schema; do
    [ -n "$base" ] || continue
    log "$base / $schema"
    if ! sql_pour "$schema" | "${PSQL[@]}" -d "$base" -v ON_ERROR_STOP=1 -q; then
        printf 'ECHEC sur %s / %s (transaction annulée, rien de modifié)\n' "$base" "$schema" >&2
        ERREURS=$((ERREURS + 1))
        continue
    fi
    RESULT=$(verif_colonne "$base" "$schema")
    if [ "$RESULT" = "integer|1" ]; then
        echo "OK : $base / $schema -> $RESULT"
    else
        printf 'VERIFICATION ECHEE sur %s / %s (attendu integer|1, obtenu "%s")\n' \
            "$base" "$schema" "$RESULT" >&2
        ERREURS=$((ERREURS + 1))
    fi
done <<< "$PLAN"

echo
if [ "$ERREURS" != "0" ]; then
    echo "Terminé avec $ERREURS échec(s) : voir les messages ci-dessus."
    exit 1
fi
if [ -n "$IGNOREES" ]; then
    echo "Correctif appliqué, mais le bilan de départ était INCOMPLET : règle les bases"
    echo "non analysées ci-dessus, puis relance un dry-run."
    exit 1
fi
echo "Terminé sans erreur. Pense à relancer OpenConcerto pour recharger la structure."
