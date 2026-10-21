#!/usr/bin/env bash
#
# Diagnostic complet du transfert « commande fournisseur » -> « facture
# fournisseur » d'OpenConcerto 1.7.6, pour un compte utilisateur donne.
#
# Ce script enchaine TOUS les tests a faire sur le compte concerne (par defaut
# l'utilisateur « abe ») :
#
#   1. la configuration reellement utilisee par le client OpenConcerto
#      (main.properties) : base, port, racine ;
#   2. la structure du transfert dans TOUS les schemas de la base : presence
#      de la table FACTURE_FOURNISSEUR_ELEMENT et de sa colonne
#      ID_COMMANDE_ELEMENT (c'est la cause du message
#      « ID_COMMANDE_ELEMENT is not in table /FACTURE_FOURNISSEUR_ELEMENT/ »,
#      qui depend du schema — donc de la societe — et pas des droits) ;
#   3. les droits effectifs de l'utilisateur de reference et du compte
#      concerne, et leur differentiel (delegue a test-droits-utilisateur.sh,
#      qui doit etre dans le meme dossier) ;
#   4. la societe memorisee par le client (User.properties / LastSociete) ;
#   5. un verdict global.
#
# Par defaut, ce script ne modifie RIEN. Avec -f, il applique :
#   - le correctif de structure (ajout de la colonne ID_COMMANDE_ELEMENT
#     dans les schemas qui ne l'ont pas) ;
#   - le correctif de droits (si un ecart existe).
#
# Where the rights live (OpenConcerto 1.7) :
#   USER_COMMON   ID, LOGIN, NOM, PRENOM, ADMIN, SUPERUSER, PASSWORD
#   RIGHT         ID, CODE, NOM, DESCRIPTION
#   USER_RIGHT    ID, ID_USER_COMMON, ID_RIGHT, OBJECT, HAVE_RIGHT
#   ACCES_SOCIETE ID_USER_COMMON, ID_SOCIETE_COMMON
#
# BEGIN_UTILISE
# Exemples :
#   ./diagnostic-transfert-fournisseur.sh                 # rapport complet (erp vs abe)
#   ./diagnostic-transfert-fournisseur.sh -1 yves -2 gis  # par prenom
#   ./diagnostic-transfert-fournisseur.sh -n              # simulation complete
#   ./diagnostic-transfert-fournisseur.sh -f              # applique les correctifs
#   ./diagnostic-transfert-fournisseur.sh -c              # via docker compose exec
#   ./diagnostic-transfert-fournisseur.sh -b OpenConcertoKineticTherm -p 5432
# END_UTILISE
#
set -u

HERE=$(cd "$(dirname "$0")" && pwd)

REF="erp"
CIBLE="abe"
BASE=""
HOST="127.0.0.1"
PORT="5433"
ROLE="openconcerto"
PASSWORD=""
FORCE_DOCKER=0
STACK_DIR="${STACK_DIR:-$HOME/oc-176-docker}"
APPLY=0
DRYRUN=0
ASSUME_YES=0
CLIENT_CONF="${CLIENT_CONF:-$HOME/.config/OpenConcerto/main.properties}"

die() {
    echo "ERREUR : $*" >&2
    exit 1
}

log() {
    echo
    echo "==> $*"
}

while getopts "1:2:b:H:p:U:P:o:cfnyh" opt; do
    case "$opt" in
        1) REF="$OPTARG" ;;
        2) CIBLE="$OPTARG" ;;
        b) BASE="$OPTARG" ;;
        H) HOST="$OPTARG" ;;
        p) PORT="$OPTARG" ;;
        U) ROLE="$OPTARG" ;;
        P) PASSWORD="$OPTARG" ;;
        o) STACK_DIR="$OPTARG" ;;
        c) FORCE_DOCKER=1 ;;
        f) APPLY=1 ;;
        n) DRYRUN=1 ;;
        y) ASSUME_YES=1 ;;
        h)
            sed -n 's/^# \(Usage\|Exemples\|Options\).*/&/p' "$0" | sed -n '1,60p'
            exit 0
            ;;
        *) die "option inconnue : -$OPTARG" ;;
    esac
done

command -v psql >/dev/null 2>&1 || die "'psql' introuvable. Installe le client PostgreSQL."

# Le mot de passe vient de -P, sinon de l'environnement PGPASSWORD.
# (la chaine "||" precedente laissait PASSWORD vide quand PGPASSWORD etait defini)
if [ -z "$PASSWORD" ]; then
    PASSWORD="${PGPASSWORD:-}"
fi
if [ -z "$PASSWORD" ] && [ -f "$STACK_DIR/.env" ]; then
    PASSWORD=$(sed -n 's/^POSTGRES_PASSWORD=//p' "$STACK_DIR/.env" | head -n 1)
fi

COMPOSE="$STACK_DIR/docker-compose.yml"
USE_DOCKER=0
if [ "$FORCE_DOCKER" = "1" ]; then
    USE_DOCKER=1
    [ -f "$COMPOSE" ] || die "Fichier de composition introuvable : $COMPOSE"
    command -v docker >/dev/null 2>&1 || die "'docker' introuvable dans le PATH."
    BASE="${BASE:-OpenConcerto}"
else
    if PGPASSWORD="$PASSWORD" psql -X -h "$HOST" -p "$PORT" -U "$ROLE" -d postgres -tAc "select 1" >/dev/null 2>&1; then
        BASE="${BASE:-OpenConcerto}"
    elif [ -f "$COMPOSE" ] && command -v docker >/dev/null 2>&1 \
         && docker compose -f "$COMPOSE" exec -T db psql -U "$ROLE" -d postgres -tAc "select 1" >/dev/null 2>&1; then
        USE_DOCKER=1
        BASE="${BASE:-OpenConcerto}"
    else
        die "Aucune connexion possible sur $HOST:$PORT (base $BASE, role $ROLE). Verifie que le conteneur tourne et que le mot de passe est le bon."
    fi
fi

run_sql_at() {
    if [ "$USE_DOCKER" = "1" ]; then
        docker compose -f "$COMPOSE" exec -T db psql -X -A -t -U "$ROLE" -d "$BASE" -v ON_ERROR_STOP=1 -c "$1"
    else
        PGPASSWORD="$PASSWORD" psql -X -A -t -h "$HOST" -p "$PORT" -U "$ROLE" -d "$BASE" -v ON_ERROR_STOP=1 -c "$1"
    fi
}

run_sql() {
    if [ "$USE_DOCKER" = "1" ]; then
        docker compose -f "$COMPOSE" exec -T db psql -X -U "$ROLE" -d "$BASE" -v ON_ERROR_STOP=1 -c "$1"
    else
        PGPASSWORD="$PASSWORD" psql -X -h "$HOST" -p "$PORT" -U "$ROLE" -d "$BASE" -v ON_ERROR_STOP=1 -c "$1"
    fi
}

PROBLEMES=0

# ------------------------------------------------------------------ 1. client
log "1. Configuration du client OpenConcerto ($CLIENT_CONF)"
if [ -f "$CLIENT_CONF" ]; then
    C_IP=$(sed -n 's/^server\.ip=//p' "$CLIENT_CONF" | tail -n 1 | tr -d '\\')
    C_PORT=$(sed -n 's/^server\.port=//p' "$CLIENT_CONF" | tail -n 1 | tr -d '\\')
    C_HOST=$(printf '%s' "$C_IP" | cut -d: -f1)
    C_IPPORT=$(printf '%s' "$C_IP" | cut -d: -f2)
    C_ROOT=$(sed -n 's/^systemRoot=//p' "$CLIENT_CONF" | tail -n 1)
    C_BASE=$(sed -n 's/^server\.base=//p' "$CLIENT_CONF" | tail -n 1)
    C_LOGIN=$(sed -n 's/^server\.login=//p' "$CLIENT_CONF" | tail -n 1)
    [ -n "$C_PORT" ] || C_PORT="$C_IPPORT"
    printf '  server.ip      : %s\n' "$C_IP"
    printf '  server.port    : %s\n' "$C_PORT"
    printf '  systemRoot     : %s\n' "$C_ROOT"
    printf '  server.base    : %s\n' "$C_BASE"
    printf '  server.login   : %s\n' "$C_LOGIN"
    if [ "$C_HOST" != "$HOST" ] || [ "$C_PORT" != "$PORT" ]; then
        echo
        echo "  ATTENTION : le client se connecte sur ${C_HOST}:${C_PORT}, mais les tests"
        echo "  ci-dessous portent sur ${HOST}:${PORT}. Les resultats ne sont valables"
        echo "  que si les deux designent la meme base."
        echo "  Relance avec : -H ${C_HOST} -p ${C_PORT} (et la base correspondante)."
        PROBLEMES=$((PROBLEMES + 1))
    fi
else
    echo "  (fichier introuvable : $CLIENT_CONF)"
    echo "  Les tests porte sur la base indiquee par les options (-H/-p/-b)."
fi

# --------------------------------------------------------- 2. structure par schema
log "2. Structure du transfert, schema par schema"
STRUCT=$(run_sql_at "select t.table_schema || '|' || case when exists (select 1 from information_schema.columns c where c.table_schema = t.table_schema and c.table_name = t.table_name and upper(c.column_name) = 'ID_COMMANDE_ELEMENT') then 'colonne presente' else 'COLONNE MANQUANTE' end from information_schema.tables t where upper(t.table_name) = 'FACTURE_FOURNISSEUR_ELEMENT' and t.table_schema not in ('pg_catalog','information_schema') order by t.table_schema")
SCHEMAS_MANQUANTS=0
if [ -z "$STRUCT" ]; then
    echo "  (aucune table FACTURE_FOURNISSEUR_ELEMENT dans cette base)"
else
    while IFS='|' read -r sch state; do
        [ -n "$sch" ] || continue
        printf '  %-24s %s\n' "$sch" "$state"
        case "$state" in
            *MANQUANTE*) SCHEMAS_MANQUANTS=$((SCHEMAS_MANQUANTS + 1)) ;;
        esac
    done <<EOF
$STRUCT
EOF
fi
echo
echo "  Societes declarees :"
SOCIETES_RAW=$(run_sql_at "select table_schema || '.' || table_name from information_schema.tables where upper(table_name) in ('SOCIETE_COMMON','SOCIETE','SOCIETES') order by table_schema limit 1")
SOCIETES_Q=$(run_sql_at "select quote_ident(table_schema) || '.' || quote_ident(table_name) from information_schema.tables where upper(table_name) in ('SOCIETE_COMMON','SOCIETE','SOCIETES') order by table_schema limit 1")
if [ -n "$SOCIETES_RAW" ]; then
    SC_ID=$(run_sql_at "select quote_ident(column_name) from information_schema.columns where table_schema||'.'||table_name = '$SOCIETES_RAW' and lower(column_name) = 'id' limit 1")
    SC_NOM=$(run_sql_at "select quote_ident(column_name) from information_schema.columns where table_schema||'.'||table_name = '$SOCIETES_RAW' and lower(column_name) in ('nom','name','libelle') limit 1")
    if [ -n "$SC_ID" ] && [ -n "$SC_NOM" ]; then
        run_sql_at "select $SC_ID || ' | ' || coalesce($SC_NOM,'(sans nom)') from $SOCIETES_Q order by $SC_ID" | sed 's/^/    /'
    else
        echo "    (colonnes non identifiees)"
    fi
else
    echo "    (table des societes introuvable)"
fi

# ------------------------------------------------------------------ 3. droits
log "3. Droits : $REF (reference) vs $CIBLE (compte concerne)"
DROITS_SCRIPT="$HERE/test-droits-utilisateur.sh"
if [ ! -f "$DROITS_SCRIPT" ]; then
    echo "  (test-droits-utilisateur.sh absent de $HERE : etape ignoree)"
    PROBLEMES=$((PROBLEMES + 1))
else
    set -- -1 "$REF" -2 "$CIBLE" -b "$BASE" -H "$HOST" -p "$PORT" -U "$ROLE"
    [ -n "$PASSWORD" ] && set -- "$@" -P "$PASSWORD"
    [ "$FORCE_DOCKER" = "1" ] && set -- "$@" -c
    [ "$APPLY" = "1" ] && set -- "$@" -f
    [ "$DRYRUN" = "1" ] && set -- "$@" -n
    [ "$ASSUME_YES" = "1" ] && set -- "$@" -y
    bash "$DROITS_SCRIPT" "$@"
    DROITS_RC=$?
    if [ "$DROITS_RC" != "0" ]; then
        echo
        echo "  (le script de droits a rendu le code $DROITS_RC : voir le message ci-dessus)"
    fi
fi

# ------------------------------------------------- 4. societe memorisee (client)
log "4. Societe memorisee par le client (User.properties / LastSociete)"
if [ -d "$HOME/.config/OpenConcerto" ]; then
    FOUND=0
    while IFS= read -r f; do
        FOUND=1
        printf '  %s\n' "$f"
        if grep -qi "LastSociete" "$f" 2>/dev/null; then
            grep -i "LastSociete" "$f" | sed 's/^/    /'
        else
            echo "    (aucune propriete LastSociete)"
        fi
    done <<EOF
$(find "$HOME/.config/OpenConcerto" -maxdepth 3 -name 'User.properties' 2>/dev/null)
EOF
    if [ "$FOUND" = "0" ]; then
        echo "  (aucun User.properties dans ~/.config/OpenConcerto)"
    fi
else
    echo "  (pas de ~/.config/OpenConcerto sur cette machine)"
fi
echo "  Rappel : le client memorise la derniere societe utilisee et la propose"
echo "  par defaut a la connexion ; c'est elle qui determine le schema employe."

# ------------------------------------------------------------------ 5. verdict
log "5. Verdict"
if [ "$SCHEMAS_MANQUANTS" != "0" ]; then
    echo "  [1] $SCHEMAS_MANQUANTS schema(s) ont la table du transfert SANS la colonne"
    echo "      ID_COMMANDE_ELEMENT : le transfert echoue dans ces schemas, quels que"
    echo "      soient les droits. A corriger en priorite."
    PROBLEMES=$((PROBLEMES + 1))
else
    echo "  [1] ID_COMMANDE_ELEMENT est presente dans tous les schemas : OK"
fi

if [ "$APPLY" = "1" ]; then
    echo "  [2] correctifs demandes (mode $([ "$DRYRUN" = "1" ] && echo 'simulation' || echo 'application'))"
    FIXER="$HERE/fix-facture-fournisseur-all-schemas.sh"
    if [ -f "$FIXER" ]; then
        echo
        echo "  --- correction de structure (ID_COMMANDE_ELEMENT) ---"
        if [ -z "${PSQL_CMD:-}" ]; then
            # Le correctif de structure doit viser la base que l'on teste :
            # le conteneur (port publie 5433) ou le serveur natif.
            if [ "$USE_DOCKER" = "1" ]; then
                export PSQL_CMD="docker compose -f $COMPOSE exec -T db psql -U $ROLE"
            elif [ "$PORT" = "5433" ] && [ -f "$COMPOSE" ] && command -v docker >/dev/null 2>&1; then
                export PSQL_CMD="docker compose -f $COMPOSE exec -T db psql -U $ROLE"
            else
                export PSQL_CMD="psql -h $HOST -p $PORT -U $ROLE"
            fi
        fi
        echo "  commande SQL : $PSQL_CMD"
        bash "$FIXER" -d "$BASE" -n 2>&1 | sed 's/^/  /'
        if [ "$DRYRUN" != "1" ]; then
            bash "$FIXER" -d "$BASE" -y 2>&1 | sed 's/^/  /'
        fi
    else
        echo "  (fix-facture-fournisseur-all-schemas.sh absent de $HERE)"
    fi
else
    echo "  [2] aucun correctif applique (mode rapport). Relance avec -f pour corriger."
fi

echo
if [ "$PROBLEMES" = "0" ]; then
    echo "  => Aucun probleme detecte par les tests automatiques."
    echo "     Si le transfert echoue encore pour $CIBLE, verifier :"
    echo "     - la societe courante au moment de l'operation (etape 4) ;"
    echo "     - le message exact de l'erreur ;"
    echo "     - que l'operation est rejouee apres une nouvelle connexion (les droits"
    echo "       sont charges a la connexion)."
else
    echo "  => $PROBLEMES point(s) a traiter (voir ci-dessus)."
fi
exit 0
