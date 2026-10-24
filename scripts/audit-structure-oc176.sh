#!/usr/bin/env bash
#
# Audit de la STRUCTURE de la base OpenConcerto 1.7.6 : compare les tables
# reelles avec ce qu'attend le code OC 1.7.6, et produit si besoin un patch
# SQL idempotent.
#
# Pourquoi : dans la base de production KINETIC-THERM, la colonne
# ID_COMMANDE_ELEMENT n'existait dans AUCUN schema (verifie sur le dump) ->
# le "Transfert vers saisie achat" / "Transfert vers facture" ne pouvait pas
# fonctionner. Cette commande liste TOUS les ecarts de structure, par schema.
#
# Reference : InstallationPanel (addHAElementField), Updater_1_5, et le
# correctif applique a FACTURE_FOURNISSEUR_ELEMENT.
#
# Usage :
#   bash audit-structure-oc176.sh                       # audit (lecture seule)
#   bash audit-structure-oc176.sh -o patch.sql          # + ecrit le patch
#   bash audit-structure-oc176.sh -o patch.sql --apply  # + applique le patch
#   bash audit-structure-oc176.sh -n                    # dry-run
#
# Options :
#   -b BASE     base      (defaut : OpenConcerto)
#   -H HOTE     hote      (defaut : 127.0.0.1)
#   -p PORT     port      (defaut : 5433)
#   -U USER     role      (defaut : openconcerto)
#   -P MDP      mot de passe (defaut : POSTGRES_PASSWORD du .env de la stack)
#   -o FICHIER  fichier de patch SQL a ecrire
#   --apply     applique le patch genere (demande confirmation)
#   -y          pas de confirmation
#   -n          dry-run : n'ecrit et n'applique rien
#   -h|--help   cette aide

set -euo pipefail

BASE="OpenConcerto"
HOST="127.0.0.1"
PORT="5433"
USER_PG="openconcerto"
PASSWORD="${PGPASSWORD:-}"
OUTFILE=""
APPLY=0
ASSUME_YES=0
DRY=0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STACK_DIR="${OC176_STACK_DIR:-$SCRIPT_DIR/../docker/openconcerto-1.7.6}"
ENV_FILE="${OC176_ENV_FILE:-$STACK_DIR/.env}"

usage() {
    sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
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
        --apply) APPLY=1; shift ;;
        -y) ASSUME_YES=1; shift ;;
        -n) DRY=1; shift ;;
        -h|--help) usage 0 ;;
        *) echo "option inconnue : $1" >&2; usage 1 ;;
    esac
done

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

command -v psql >/dev/null 2>&1 || die "'psql' introuvable (paquet postgresql-client)."

if [ -z "$PASSWORD" ] && [ -f "$ENV_FILE" ]; then
    PASSWORD="$(sed -n 's/^POSTGRES_PASSWORD=//p' "$ENV_FILE" | head -n 1)"
    [ -n "$PASSWORD" ] && info "mot de passe lu dans $ENV_FILE"
fi
[ -n "$PASSWORD" ] || die "Mot de passe inconnu : donne -P MDP ou renseigne PGPASSWORD."
export PGPASSWORD="$PASSWORD"

# --------------------------------------------------------------------------
# Structure attendue par OC 1.7.6.
#   "TABLE|COLONNE|type|table-ref|priorite"
# priorite : CRITIQUE = bloque le transfert, IMPORTANT = attendu par OC,
#            OPTIONNEL = workflow 1.5 (RECU...)
# --------------------------------------------------------------------------
EXPECTED="
FACTURE_FOURNISSEUR_ELEMENT|ID_COMMANDE_ELEMENT|integer DEFAULT 1|COMMANDE_ELEMENT|CRITIQUE
BON_RECEPTION_ELEMENT|ID_COMMANDE_ELEMENT|integer DEFAULT 1|COMMANDE_ELEMENT|CRITIQUE
FACTURE_FOURNISSEUR_ELEMENT|QTE_ACHAT|integer DEFAULT 1||IMPORTANT
FACTURE_FOURNISSEUR_ELEMENT|QTE_UNITAIRE|numeric(16,6) DEFAULT 1||IMPORTANT
FACTURE_FOURNISSEUR_ELEMENT|ID_UNITE_VENTE|integer|UNITE_VENTE|IMPORTANT
FACTURE_FOURNISSEUR_ELEMENT|ID_ARTICLE|integer|ARTICLE|IMPORTANT
FACTURE_FOURNISSEUR_ELEMENT|PA_DEVISE|bigint DEFAULT 0||IMPORTANT
FACTURE_FOURNISSEUR_ELEMENT|ID_DEVISE|integer|DEVISE|IMPORTANT
FACTURE_FOURNISSEUR_ELEMENT|PA_DEVISE_T|bigint DEFAULT 0||IMPORTANT
FACTURE_FOURNISSEUR_ELEMENT|DESCRIPTIF|varchar(2048)||IMPORTANT
BON_RECEPTION_ELEMENT|QTE_ACHAT|integer DEFAULT 1||IMPORTANT
BON_RECEPTION_ELEMENT|QTE_UNITAIRE|numeric(16,6) DEFAULT 1||IMPORTANT
BON_RECEPTION_ELEMENT|ID_UNITE_VENTE|integer|UNITE_VENTE|IMPORTANT
BON_RECEPTION_ELEMENT|ID_ARTICLE|integer|ARTICLE|IMPORTANT
BON_RECEPTION_ELEMENT|PA_DEVISE|bigint DEFAULT 0||IMPORTANT
BON_RECEPTION_ELEMENT|ID_DEVISE|integer|DEVISE|IMPORTANT
BON_RECEPTION_ELEMENT|PA_DEVISE_T|bigint DEFAULT 0||IMPORTANT
BON_RECEPTION_ELEMENT|DESCRIPTIF|varchar(2048)||IMPORTANT
COMMANDE_ELEMENT|QTE_ACHAT|integer DEFAULT 1||IMPORTANT
COMMANDE_ELEMENT|QTE_UNITAIRE|numeric(16,6) DEFAULT 1||IMPORTANT
COMMANDE_ELEMENT|ID_UNITE_VENTE|integer|UNITE_VENTE|IMPORTANT
COMMANDE_ELEMENT|ID_ARTICLE|integer|ARTICLE|IMPORTANT
COMMANDE_ELEMENT|PA_DEVISE|bigint DEFAULT 0||IMPORTANT
COMMANDE_ELEMENT|ID_DEVISE|integer|DEVISE|IMPORTANT
COMMANDE_ELEMENT|PA_DEVISE_T|bigint DEFAULT 0||IMPORTANT
COMMANDE_ELEMENT|DESCRIPTIF|varchar(2048)||IMPORTANT
DEMANDE_PRIX_ELEMENT|QTE_ACHAT|integer DEFAULT 1||IMPORTANT
DEMANDE_PRIX_ELEMENT|QTE_UNITAIRE|numeric(16,6) DEFAULT 1||IMPORTANT
DEMANDE_PRIX_ELEMENT|ID_UNITE_VENTE|integer|UNITE_VENTE|IMPORTANT
DEMANDE_PRIX_ELEMENT|ID_ARTICLE|integer|ARTICLE|IMPORTANT
DEMANDE_PRIX_ELEMENT|PA_DEVISE|bigint DEFAULT 0||IMPORTANT
DEMANDE_PRIX_ELEMENT|ID_DEVISE|integer|DEVISE|IMPORTANT
DEMANDE_PRIX_ELEMENT|PA_DEVISE_T|bigint DEFAULT 0||IMPORTANT
DEMANDE_PRIX_ELEMENT|DESCRIPTIF|varchar(2048)||IMPORTANT
COMMANDE_ELEMENT|RECU|boolean DEFAULT true||OPTIONNEL
COMMANDE_ELEMENT|RECU_FORCED|boolean DEFAULT false||OPTIONNEL
COMMANDE_ELEMENT|QTE_RECUE|numeric(16,6) DEFAULT 0||OPTIONNEL
"

log "Audit de structure"
info "base    : $BASE"
info "serveur : $HOST:$PORT (role $USER_PG)"

# ------------------------------------------------- etat reel des colonnes
COLS=$(psql -h "$HOST" -p "$PORT" -U "$USER_PG" -d "$BASE" -At -F'|' -c \
    "SELECT table_schema, table_name, column_name
       FROM information_schema.columns
      WHERE table_name IN ('FACTURE_FOURNISSEUR_ELEMENT','BON_RECEPTION_ELEMENT','COMMANDE_ELEMENT','DEMANDE_PRIX_ELEMENT')
        AND table_schema NOT IN ('pg_catalog','information_schema')
      ORDER BY 1,2,3") || die "Lecture de information_schema impossible."

[ -n "$COLS" ] || die "Aucune table de ligne 'achat' trouvee dans $BASE."

SCHEMAS=$(printf '%s\n' "$COLS" | cut -d'|' -f1 | sort -u)
TABLES=$(printf '%s\n' "$COLS" | cut -d'|' -f2 | sort -u)

info "schemas analyses : $(printf '%s' "$SCHEMAS" | tr '\n' ' ')"
info "tables analysees : $(printf '%s' "$TABLES" | tr '\n' ' ')"

# --------------------------------------------------------------- la matrice
MANQUANTS=""      # schema|table|colonne|type|reftable|priorite
NB_CRIT=0
NB_IMP=0
NB_OPT=0

printf '\n%-16s %-30s %-18s %s\n' "SCHEMA" "TABLE" "COLONNE" "STATUT"
printf '%s\n' "--------------------------------------------------------------------------"

# Une entree de EXPECTED = table|colonne|type|table-ref|priorite
# La matrice est construite schema par schema : chaque table attendue est
# verifiee dans TOUS les schemas qui la possedent.
while IFS='|' read -r tab col typ reftab prio; do
    [ -n "$tab" ] || continue
    while IFS= read -r sch; do
        [ -n "$sch" ] || continue
        # la table existe-t-elle dans ce schema ?
        if ! printf '%s\n' "$COLS" | awk -F'[|]' -v s="$sch" -v t="$tab" '$1==s && $2==t {found=1} END{exit !found}'; then
            continue
        fi
        # la colonne existe-t-elle ?
        if printf '%s\n' "$COLS" | awk -F'[|]' -v s="$sch" -v t="$tab" -v c="$col" '$1==s && $2==t && $3==c {found=1} END{exit !found}'; then
            printf '%-16s %-30s %-18s %s\n' "$sch" "$tab" "$col" "present"
        else
            printf '%-16s %-30s %-18s %s\n' "$sch" "$tab" "$col" "ABSENT  <-- $prio"
            MANQUANTS="${MANQUANTS}${sch}|${tab}|${col}|${typ}|${reftab}|${prio}"$'\n'
            case "$prio" in
                CRITIQUE) NB_CRIT=$((NB_CRIT + 1)) ;;
                IMPORTANT) NB_IMP=$((NB_IMP + 1)) ;;
                *) NB_OPT=$((NB_OPT + 1)) ;;
            esac
        fi
    done <<< "$SCHEMAS"
done <<< "$EXPECTED"

echo
info "manquants CRITIQUES  : $NB_CRIT"
info "manquants IMPORTANTS : $NB_IMP"
info "manquants OPTIONNELS : $NB_OPT"

if [ "$NB_CRIT" = "0" ] && [ "$NB_IMP" = "0" ] && [ "$NB_OPT" = "0" ]; then
    echo
    info "Structure conforme a OC 1.7.6 : rien a corriger."
    exit 0
fi

# ------------------------------------------------------------ generation patch
gen_sql() {
    local cur_sch="" cur_tab=""
    printf -- '-- Correctif de structure OpenConcerto 1.7.6\n'
    printf -- '-- Genere le %s sur %s (%s:%s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$BASE" "$HOST" "$PORT"
    printf -- '-- Idempotent : peut etre rejoue sans risque.\n\n'
    while IFS='|' read -r sch tab col typ reftab prio; do
        [ -n "$sch" ] || continue
        if [ "$sch" != "$cur_sch" ] || [ "$tab" != "$cur_tab" ]; then
            [ -n "$cur_sch" ] && printf 'COMMIT;\n\n'
            printf 'BEGIN;\nSET LOCAL search_path TO "%s";\n\n' "$sch"
            cur_sch="$sch"
            cur_tab="$tab"
        fi
        printf -- '-- %s : %s.%s\n' "$prio" "$tab" "$col"
        printf 'ALTER TABLE "%s" ADD COLUMN IF NOT EXISTS "%s" %s;\n' "$tab" "$col" "$typ"
        if [ -n "$reftab" ]; then
            printf 'DO $$\nBEGIN\n    IF NOT EXISTS (\n        SELECT 1 FROM pg_constraint c\n        JOIN pg_class t ON t.oid = c.conrelid\n        JOIN pg_namespace n ON n.oid = t.relnamespace\n        WHERE n.nspname = '"'"'%s'"'"'\n          AND t.relname = '"'"'%s'"'"'\n          AND c.conname = '"'"'%s_%s_fkey'"'"'\n    ) THEN\n        ALTER TABLE "%s" ADD CONSTRAINT "%s_%s_fkey"\n            FOREIGN KEY ("%s") REFERENCES "%s" ("ID");\n    END IF;\nEND $$;\n' \
                "$sch" "$tab" "$tab" "$col" "$tab" "$tab" "$col" "$col" "$reftab"
            printf 'CREATE INDEX IF NOT EXISTS "%s_%s_fki" ON "%s" ("%s");\n' "$tab" "$col" "$tab" "$col"
        fi
        printf '\n'
    done <<< "$MANQUANTS"
    [ -n "$cur_sch" ] && printf 'COMMIT;\n'
}

if [ -n "$OUTFILE" ]; then
    OUTDIR="$(dirname "$OUTFILE")"
    mkdir -p "$OUTDIR" 2>/dev/null || die "Dossier de sortie inaccessible : $OUTDIR"
    if [ "$DRY" = "1" ]; then
        echo
        info "Dry-run : patch NON ecrit (il le serait dans $OUTFILE)."
    else
        gen_sql > "$OUTFILE"
        info "patch ecrit : $OUTFILE"
    fi
else
    if [ "$APPLY" = "1" ]; then
        die "-o FICHIER est obligatoire pour --apply."
    fi
    log "Patch SQL qui serait applique"
    gen_sql
fi

# ------------------------------------------------------------------ application
if [ "$APPLY" = "1" ]; then
    if [ "$DRY" = "1" ]; then
        echo
        info "Dry-run : rien n'a ete applique."
        exit 0
    fi
    if [ "$ASSUME_YES" -ne 1 ]; then
        printf '\nAppliquer ce correctif a %s ? [o/N] ' "$BASE"
        read -r answer
        case "$answer" in
            o|O|oui|OUI|y|Y) ;;
            *) echo "Annule."; exit 0 ;;
        esac
    fi
    log "Application du correctif"
    psql -h "$HOST" -p "$PORT" -U "$USER_PG" -d "$BASE" -v ON_ERROR_STOP=1 -q -f "$OUTFILE" \
        || die "Le patch a echoue (transaction annulee, rien de modifie)."
    info "correctif applique."
    echo
    info "Relance l'audit pour verifier :"
    printf '  bash %s -b %s -H %s -p %s -U %s\n' "$0" "$BASE" "$HOST" "$PORT" "$USER_PG"
fi

echo
info "Termine."
