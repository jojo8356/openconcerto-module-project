#!/usr/bin/env bash
#
# Reproduit l'operation qui echouait pour Gisele :
# l'ecriture d'une ligne FACTURE_FOURNISSEUR_ELEMENT avec ID_COMMANDE_ELEMENT
# renseigne (le transfert commande fournisseur -> facture fournisseur).
#
# Le test est NON DESTRUCTIF : tout se passe dans une transaction annulee
# (BEGIN ... ROLLBACK). Aucune donnee n'est modifiee, aucun droit n'est
# touche. Pour chaque schema contenant la table, on verifie :
#   1. la presence de la colonne ID_COMMANDE_ELEMENT (la cause historique) ;
#   2. que l'ecriture d'une ligne complete avec ID_COMMANDE_ELEMENT passe
#      (contraintes, cle etrangere, valeurs obligatoires).
#
# Usage :
#   ./test-transfert-fournisseur.sh                 # rapport (lecture seule)
#   ./test-transfert-fournisseur.sh -n              # affiche le SQL, n'execute pas
#   ./test-transfert-fournisseur.sh -H 127.0.0.1 -p 5433 -b OpenConcerto
#
# Options :
#   -b BASE      base (defaut : OpenConcerto)
#   -H HOTE      hote (defaut : 127.0.0.1)
#   -p PORT      port (defaut : 5433)
#   -U ROLE      role SQL (defaut : openconcerto)
#   -P MDP       mot de passe (defaut : $PGPASSWORD, sinon POSTGRES_PASSWORD du .env)
#   -o DOSSIER   dossier de la stack (defaut : ~/oc-176-docker)
#   -n           dry-run : affiche le SQL sans l'executer
#   -h           cette aide
#
set -euo pipefail

BASE="OpenConcerto"
HOST="127.0.0.1"
PORT="5433"
ROLE="openconcerto"
PASSWORD="${PGPASSWORD:-}"
STACK_DIR="$HOME/oc-176-docker"
DRY=0

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

usage() {
    awk '/^# Usage/{f=1} /^# Options/{o=1} (f||o) { if ($0 ~ /^# / || $0 ~ /^$/) print }' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while getopts ":b:H:p:U:P:o:nh" opt; do
    case "$opt" in
        b) BASE="$OPTARG" ;;
        H) HOST="$OPTARG" ;;
        p) PORT="$OPTARG" ;;
        U) ROLE="$OPTARG" ;;
        P) PASSWORD="$OPTARG" ;;
        o) STACK_DIR="$OPTARG" ;;
        n) DRY=1 ;;
        h) usage ;;
        *) die "option inconnue : -$OPTARG" ;;
    esac
done

command -v psql >/dev/null 2>&1 || die "'psql' introuvable."

if [ -z "$PASSWORD" ] && [ -f "$STACK_DIR/.env" ]; then
    PASSWORD=$(sed -n 's/^POSTGRES_PASSWORD=//p' "$STACK_DIR/.env" | head -n 1)
fi

run_sql() {
    PGPASSWORD="$PASSWORD" psql -X -h "$HOST" -p "$PORT" -U "$ROLE" -d "$BASE" -tAc "$1"
}

log "Connexion"
info "base : $BASE  |  $HOST:$PORT  |  role $ROLE"

log "Schemas contenant FACTURE_FOURNISSEUR_ELEMENT"
SCHEMAS=$(run_sql "select table_schema from information_schema.tables where table_name = 'FACTURE_FOURNISSEUR_ELEMENT' order by table_schema")
if [ -z "$SCHEMAS" ]; then
    die "table FACTURE_FOURNISSEUR_ELEMENT introuvable dans la base $BASE."
fi
printf '%s\n' "$SCHEMAS" | sed 's/^/  /'

OK_COUNT=0
KO_COUNT=0
TMPDIR_SQL=$(mktemp -d)
trap 'rm -rf "$TMPDIR_SQL"' EXIT

for SCH in $SCHEMAS; do
    log "Schema $SCH"

    NCOL=$(run_sql "select count(*) from information_schema.columns where table_schema = '$SCH' and table_name = 'FACTURE_FOURNISSEUR_ELEMENT' and column_name = 'ID_COMMANDE_ELEMENT'")
    if [ "$NCOL" = "1" ]; then
        info "colonne ID_COMMANDE_ELEMENT : presente"
    else
        info "colonne ID_COMMANDE_ELEMENT : ABSENTE  <-- c'est l'erreur historique"
        KO_COUNT=$((KO_COUNT + 1))
        continue
    fi

    NCMD=$(run_sql "select count(*) from \"$SCH\".\"COMMANDE_ELEMENT\"")
    NELT=$(run_sql "select count(*) from \"$SCH\".\"FACTURE_FOURNISSEUR_ELEMENT\"")
    info "lignes COMMANDE_ELEMENT : $NCMD | lignes FACTURE_FOURNISSEUR_ELEMENT : $NELT"

    if [ "$NELT" = "0" ]; then
        info "pas de ligne modele : test d'ecriture non realisable (table vide)"
        continue
    fi
    if [ "$NCMD" = "0" ]; then
        info "aucune commande fournisseur : ID_COMMANDE_ELEMENT restera NULL"
    fi

    COLS=$(run_sql "select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
                      from information_schema.columns
                     where table_schema = '$SCH' and table_name = 'FACTURE_FOURNISSEUR_ELEMENT'
                       and column_name <> 'ID'")
    # ORDRE est recale au maximum + 1 : sinon la ligne recopiee viole la
    # contrainte d'unicite (ID_FACTURE_FOURNISSEUR, ORDRE).
    SELS=$(run_sql "select string_agg(case
                                            when column_name = 'ID_COMMANDE_ELEMENT'
                                              then '(select min(\"ID\") from \"$SCH\".\"COMMANDE_ELEMENT\")'
                                            when column_name = 'ORDRE'
                                              then '(select coalesce(max(\"ORDRE\"),0)+1 from \"$SCH\".\"FACTURE_FOURNISSEUR_ELEMENT\")'
                                            else quote_ident(column_name) end, ', ' order by ordinal_position)
                      from information_schema.columns
                     where table_schema = '$SCH' and table_name = 'FACTURE_FOURNISSEUR_ELEMENT'
                       and column_name <> 'ID'")
    if [ -z "$COLS" ]; then
        info "aucune colonne exploitable"
        continue
    fi

    SQL_FILE="$TMPDIR_SQL/transfert-$SCH.sql"
    {
        echo "BEGIN;"
        echo "INSERT INTO \"$SCH\".\"FACTURE_FOURNISSEUR_ELEMENT\" ($COLS)"
        echo "SELECT $SELS FROM \"$SCH\".\"FACTURE_FOURNISSEUR_ELEMENT\" LIMIT 1;"
        echo "ROLLBACK;"
    } > "$SQL_FILE"

    if [ "$DRY" = "1" ]; then
        info "SQL (non execute) :"
        sed 's/^/    /' "$SQL_FILE"
        continue
    fi

    OUT=$(PGPASSWORD="$PASSWORD" psql -X -h "$HOST" -p "$PORT" -U "$ROLE" -d "$BASE" -f "$SQL_FILE" 2>&1) || true
    if printf '%s' "$OUT" | grep -qi "ERROR"; then
        info "ECHEC de l'ecriture (annulee) :"
        printf '%s\n' "$OUT" | grep -i "ERROR" | head -3 | sed 's/^/    /'
        KO_COUNT=$((KO_COUNT + 1))
    else
        info "ecriture d'une ligne FACTURE_FOURNISSEUR_ELEMENT avec ID_COMMANDE_ELEMENT : OK (annulee)"
        OK_COUNT=$((OK_COUNT + 1))
    fi
done

log "Synthese"
info "schemas OK : $OK_COUNT | schemas en echec : $KO_COUNT"
if [ "$KO_COUNT" = "0" ]; then
    echo "  => l'ecriture du transfert ne peut plus echouer pour une raison de STRUCTURE."
    echo "     Si le transfert echoue encore chez Gisele, la cause est ailleurs"
    echo "     (session client, donnees, verrou de ligne, etat du module)."
else
    echo "  => au moins un schema est encore en cause : voir le detail ci-dessus."
fi
