#!/usr/bin/env bash
#
# Contrôle complet des droits utilisateurs OpenConcerto 1.7.6.
#
# BEGIN_UTILISE
# Contexte : le transfert « commande fournisseur » vers « facture fournisseur »
# fonctionne pour Yves (et Administrateur) mais échoue pour Gisèle, y compris
# après lui avoir accordé les mêmes droits qu'à Yves.
#
# Ce script :
#   1. trouve les deux utilisateurs (par motif sur LOGIN / NOM / PRENOM) ;
#   2. affiche leurs droits bruts (table USER_RIGHT, dans l'ordre des ID) ;
#   3. calcule leurs droits effectifs, avec la règle exacte d'OpenConcerto :
#      pour un couple (CODE, OBJECT), c'est la ligne d'ID le plus bas qui
#      l'emporte (UserRightsManager.expand() : la première occurrence gagne) ;
#      un OBJECT NULL vaut « tous les objets » ;
#   4. affiche le DIFFérentiel des droits effectifs entre les deux comptes ;
#   5. isole les tables du transfert (FACTURE_FOURNISSEUR, COMMANDE, TIERS) ;
#   6. vérifie les drapeaux ADMIN / SUPERUSER et l'accès aux sociétés ;
#   7. peutgénérer et appliquer le correctif SQL (-f) : copie des droits
#      effectifs de l'utilisateur de référence vers l'utilisateur concerné.
#
# Where the rights live (OpenConcerto 1.7) :
#   USER_COMMON   ID, LOGIN, NOM, PRENOM, ADMIN, SUPERUSER, PASSWORD
#   RIGHT         ID, CODE, NOM, DESCRIPTION
#   USER_RIGHT    ID, ID_USER_COMMON, ID_RIGHT, OBJECT, HAVE_RIGHT
#   ACCES_SOCIETE ID_USER_COMMON, ID_SOCIETE_COMMON
#
# Usage :
#   ./test-droits-utilisateur.sh -1 yves -2 gisele              # rapport
#   ./test-droits-utilisateur.sh -1 yves -2 gisele -f -n        # correctif (plan)
#   ./test-droits-utilisateur.sh -1 yves -2 gisele -f           # correctif (appliqué)
#
# Options :
#   -1 MOTIF     utilisateur de référence  (défaut : yves)
#   -2 MOTIF     utilisateur à comparer    (défaut : gis)
#   -b BASE      base (défaut : OpenConcerto en conteneur, OpenConcertoKineticTherm en natif)
#   -H HOTE      hôte        (défaut : 127.0.0.1)
#   -p PORT      port        (défaut : 5433, le port publié du conteneur)
#   -U ROLE      rôle SQL    (défaut : openconcerto)
#   -P MDP       mot de passe (défaut : $PGPASSWORD, sinon POSTGRES_PASSWORD du .env)
#   -c           forcer le conteneur (docker compose exec) au lieu du port publié
#   -o DOSSIER   dossier de la stack (défaut : ~/oc-176-docker)
#   -f           générer et appliquer le correctif SQL
#   -x           avec -f : supprimer aussi les droits EN TROP de la cible
#                 (les lignes absentes des droits de la reference)
#   -n           dry-run : n'applique rien
#   -y           pas de confirmation
#   -h           cette aide
#
# Variables : PGPASSWORD, OC_CONF
#
# Test : tests/sql/e2e-droits.sh execute ce script de bout en bout contre un
# vrai PostgreSQL (pglite) avec des tables creees comme OpenConcerto les
# cree (noms en MAJUSCULES, entre guillemets).
# END_UTILISE

set -euo pipefail

PAT1="yves"
PAT2="gis"
BASE=""
HOST="127.0.0.1"
PORT="5433"
ROLE="openconcerto"
PASSWORD="${PGPASSWORD:-}"
STACK_DIR="$HOME/oc-176-docker"
FORCE_DOCKER=0
APPLY=0
STRICT=0
DRY=0
ASSUME_YES=0

usage() {
    awk '/^# BEGIN_UTILISE/{f=1;next} /^# END_UTILISE/{f=0} f' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while getopts ":1:2:b:H:p:U:P:co:fnxyh" opt; do
    case "$opt" in
        1) PAT1="$OPTARG" ;;
        2) PAT2="$OPTARG" ;;
        b) BASE="$OPTARG" ;;
        H) HOST="$OPTARG" ;;
        p) PORT="$OPTARG" ;;
        U) ROLE="$OPTARG" ;;
        P) PASSWORD="$OPTARG" ;;
        c) FORCE_DOCKER=1 ;;
        o) STACK_DIR="$OPTARG" ;;
        f) APPLY=1 ;;
        x) STRICT=1 ;;
        n) DRY=1 ;;
        y) ASSUME_YES=1 ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

command -v psql >/dev/null 2>&1 || die "'psql' introuvable. Installe le client PostgreSQL."

# ---------------------------------------------------------------- transport
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
    # Le conteneur est joignable sur son port publié ; on le tente d'abord.
    if PGPASSWORD="$PASSWORD" psql -X -h "$HOST" -p "$PORT" -U "$ROLE" -d postgres \
            -tAc "select 1" >/dev/null 2>&1; then
        BASE="${BASE:-OpenConcerto}"
    elif [ -f "$COMPOSE" ] && command -v docker >/dev/null 2>&1 \
         && docker compose -f "$COMPOSE" exec -T db psql -U "$ROLE" -d postgres -tAc "select 1" >/dev/null 2>&1; then
        USE_DOCKER=1
        BASE="${BASE:-OpenConcerto}"
    else
        die "Aucune connexion possible sur $HOST:$PORT (base $BASE, rôle $ROLE). Vérifie que le conteneur tourne et que le mot de passe est le bon."
    fi
fi

# psql <sql>  : sortie brute, séparateur '|'
run_sql() {
    if [ "$USE_DOCKER" = "1" ]; then
        docker compose -f "$COMPOSE" exec -T db psql -X -U "$ROLE" -d "$BASE" -v ON_ERROR_STOP=1 -c "$1"
    else
        PGPASSWORD="$PASSWORD" psql -X -h "$HOST" -p "$PORT" -U "$ROLE" -d "$BASE" -v ON_ERROR_STOP=1 -c "$1"
    fi
}

run_sql_at() {
    if [ "$USE_DOCKER" = "1" ]; then
        docker compose -f "$COMPOSE" exec -T db psql -X -A -t -U "$ROLE" -d "$BASE" -v ON_ERROR_STOP=1 -c "$1"
    else
        PGPASSWORD="$PASSWORD" psql -X -A -t -h "$HOST" -p "$PORT" -U "$ROLE" -d "$BASE" -v ON_ERROR_STOP=1 -c "$1"
    fi
}

# ---------------------------------------------------------------- découverte
log "Connexion"
printf '  base      : %s\n' "$BASE"
printf '  mode      : %s\n' "$([ "$USE_DOCKER" = "1" ] && echo 'conteneur (docker compose exec)' || echo "port publié $HOST:$PORT")"
printf '  rôle      : %s\n' "$ROLE"
run_sql "select version()"

# Tables des droits : on les cherche, elles ne s'appellent pas forcément pareil
# selon la version (USER_COMMON en 1.5/1.7, d'autres noms ailleurs).
#
# Deux formes sont conservées pour chaque table :
#   T_*_RAW : schema.table  -> pour les recherches dans information_schema
#   T_*     : "schema"."table" -> pour les requêtes. Les guillemets sont
#             indispensables : sans eux PostgreSQL replie l'identifiant en
#             minuscules (common.user_common) et RIGHT est un mot réservé.
T_USERS=""; T_RIGHTS=""; T_CODES=""; T_ACCES=""; T_SOCIETES=""
T_USERS_RAW=""; T_RIGHTS_RAW=""; T_CODES_RAW=""; T_ACCES_RAW=""; T_SOCIETES_RAW=""
while IFS='|' read -r sch tab quoted; do
    [ -n "$tab" ] || continue
    [ -n "$quoted" ] || quoted="$sch.$tab"
    case "$tab" in
        USER_COMMON|UTILISATEUR_COMMON|UTILISATEUR|USER)
            if [ -z "$T_USERS" ]; then T_USERS="$quoted"; T_USERS_RAW="$sch.$tab"; fi ;;
        USER_RIGHT|DROIT_UTILISATEUR|UTILISATEUR_DROIT|USER_RIGHTS)
            if [ -z "$T_RIGHTS" ]; then T_RIGHTS="$quoted"; T_RIGHTS_RAW="$sch.$tab"; fi ;;
        RIGHT|DROIT|TYPE_DROIT)
            if [ -z "$T_CODES" ]; then T_CODES="$quoted"; T_CODES_RAW="$sch.$tab"; fi ;;
        ACCES_SOCIETE|ACCES_SOCIETES)
            if [ -z "$T_ACCES" ]; then T_ACCES="$quoted"; T_ACCES_RAW="$sch.$tab"; fi ;;
        SOCIETE_COMMON|SOCIETE|SOCIETES)
            if [ -z "$T_SOCIETES" ]; then T_SOCIETES="$quoted"; T_SOCIETES_RAW="$sch.$tab"; fi ;;
    esac
done <<EOF
$(run_sql_at "select table_schema, table_name, quote_ident(table_schema)||'.'||quote_ident(table_name) from information_schema.tables where table_name in ('USER_COMMON','UTILISATEUR_COMMON','UTILISATEUR','USER','USER_RIGHT','DROIT_UTILISATEUR','UTILISATEUR_DROIT','USER_RIGHTS','RIGHT','DROIT','TYPE_DROIT','ACCES_SOCIETE','ACCES_SOCIETES','SOCIETE_COMMON','SOCIETE','SOCIETES') order by table_schema, table_name")
EOF

[ -n "$T_USERS" ] || die "Table des utilisateurs introuvable (USER_COMMON attendu)."
[ -n "$T_RIGHTS" ] || die "Table des droits par utilisateur introuvable (USER_RIGHT attendue)."
[ -n "$T_CODES" ] || die "Table des codes de droits introuvable (RIGHT attendue)."

log "Tables utilisées"
printf '  utilisateurs : %s\n' "$T_USERS_RAW"
printf '  droits       : %s\n' "$T_RIGHTS_RAW"
printf '  codes        : %s\n' "$T_CODES_RAW"
[ -n "$T_ACCES_RAW" ] && printf '  accès societe: %s\n' "$T_ACCES_RAW"

# Les colonnes doivent exister
COLS=$(run_sql_at "select string_agg(column_name, ',' order by column_name) from information_schema.columns where table_schema||'.'||table_name = '$T_RIGHTS_RAW'")
case "$COLS" in
    *ID_USER_COMMON*) ;;
    *) die "La table $T_RIGHTS_RAW n'a pas de colonne ID_USER_COMMON (colonnes : $COLS)." ;;
esac
case "$COLS" in
    *HAVE_RIGHT*) ;;
    *) die "La table $T_RIGHTS_RAW n'a pas de colonne HAVE_RIGHT (colonnes : $COLS)." ;;
esac

# ---------------------------------------------------------------- colonnes
# Les colonnes d'OpenConcerto sont en MAJUSCULES et doivent être citées :
# sans guillemets, PostgreSQL replie l'identifiant en minuscules et la
# requête échoue (column "id" does not exist). On va donc chercher le nom
# réel de chaque colonne, puis le citer.
col() {
    run_sql_at "select quote_ident(column_name) from information_schema.columns where table_schema||'.'||table_name = '$1' and lower(column_name) = lower('$2') limit 1"
}
req_col() {
    local v
    v=$(col "$1" "$2")
    [ -n "$v" ] || die "Colonne '$2' introuvable dans $1."
    printf '%s' "$v"
}
C_U_ID=$(req_col "$T_USERS_RAW" id)
C_U_LOGIN=$(req_col "$T_USERS_RAW" login)
C_U_NOM=$(req_col "$T_USERS_RAW" nom)
C_U_PRENOM=$(req_col "$T_USERS_RAW" prenom)
C_U_ADMIN=$(col "$T_USERS_RAW" admin)
C_U_SUPER=$(col "$T_USERS_RAW" superuser)
C_R_ID=$(req_col "$T_RIGHTS_RAW" id)
C_R_USER=$(req_col "$T_RIGHTS_RAW" id_user_common)
C_R_RIGHT=$(req_col "$T_RIGHTS_RAW" id_right)
C_R_OBJECT=$(req_col "$T_RIGHTS_RAW" object)
C_R_HAVE=$(req_col "$T_RIGHTS_RAW" have_right)
C_C_ID=$(req_col "$T_CODES_RAW" id)
C_C_CODE=$(req_col "$T_CODES_RAW" code)
C_C_NOM=$(req_col "$T_CODES_RAW" nom)
C_A_USER=""; C_A_SOC=""
if [ -n "$T_ACCES_RAW" ]; then
    C_A_USER=$(col "$T_ACCES_RAW" id_user_common)
    C_A_SOC=$(col "$T_ACCES_RAW" id_societe_common)
fi

# ---------------------------------------------------------------- utilisateurs
# On récupère tous les utilisateurs, on filtre en bash (insensible aux accents).
USERS=$(run_sql_at "select $C_U_ID as id, $C_U_LOGIN as login, coalesce($C_U_NOM,'') as nom, coalesce($C_U_PRENOM,'') as prenom from $T_USERS order by $C_U_ID")

# Normalisation pour la recherche : minuscules, puis suppression des accents.
# Les substitutions sont faites en bash (et non avec tr) : tr travaille sur
# des octets et ne remplace pas correctement les caractères accentués quand
# la locale n'est pas en UTF-8.
norm() {
    local s="${1,,}"
    local pairs="à:a á:a â:a ã:a ä:a å:a è:e é:e ê:e ë:e ì:i í:i î:i ï:i ò:o ó:o ô:o õ:o ö:o ù:u ú:u û:u ü:u ý:y ÿ:y ç:c ñ:n æ:o œ:o š:s ž:z"
    local p
    for p in $pairs; do
        s="${s//${p%:*}/${p#*:}}"
    done
    printf '%s' "$s" | tr -d "'" | tr -s ' '
}

find_user() {
    local pattern="$1" id login nom prenom label
    local pat_n
    pat_n=$(norm "$pattern")
    while IFS='|' read -r id login nom prenom; do
        [ -n "$id" ] || continue
        label=$(norm "$login $nom $prenom")
        case "$label" in
            *"$pat_n"*) printf '%s|%s|%s|%s\n' "$id" "$login" "$nom" "$prenom" ;;
        esac
    done <<EOF
$USERS
EOF
}

log "Utilisateurs"
run_sql "select $C_U_ID as id, $C_U_LOGIN as login, $C_U_NOM as nom, $C_U_PRENOM as prenom from $T_USERS order by $C_U_ID"

MATCH1=$(find_user "$PAT1" || true)
MATCH2=$(find_user "$PAT2" || true)

pick_user() {
    local matches="$1" pattern="$2"
    local n
    n=$(printf '%s\n' "$matches" | grep -c . || true)
    if [ "$n" -eq 0 ]; then
        die "Aucun utilisateur ne correspond au motif '$pattern'."
    elif [ "$n" -gt 1 ]; then
        echo "ERREUR : '$pattern' correspond à $n utilisateurs :" >&2
        printf '%s\n' "$matches" | sed 's/^/    /' >&2
        die "Précisez avec un motif plus précis (-1 / -2)."
    fi
    printf '%s' "$matches"
}

U1=$(pick_user "$MATCH1" "$PAT1")
U2=$(pick_user "$MATCH2" "$PAT2")

ID1=$(printf '%s' "$U1" | cut -d'|' -f1)
ID2=$(printf '%s' "$U2" | cut -d'|' -f1)
L1=$(printf '%s' "$U1" | cut -d'|' -f2)
L2=$(printf '%s' "$U2" | cut -d'|' -f2)
[ "$ID1" != "$ID2" ] || die "Les deux motifs désignent le même utilisateur ($L1)."

# Drapeaux ADMIN / SUPERUSER (colonnes facultatives)
SQL_FLAGS="u.$C_U_ID as id"
[ -n "$C_U_ADMIN" ] && SQL_FLAGS="$SQL_FLAGS, coalesce(u.$C_U_ADMIN::text,'?') as admin"
[ -n "$C_U_SUPER" ] && SQL_FLAGS="$SQL_FLAGS, coalesce(u.$C_U_SUPER::text,'?') as superuser"

log "Utilisateurs comparés"
printf '  référence   : id=%s  %s  (%s)\n' "$ID1" "$L1" "$U1"
printf '  concerné    : id=%s  %s  (%s)\n' "$ID2" "$L2" "$U2"
run_sql "select $SQL_FLAGS from $T_USERS u where u.$C_U_ID in ($ID1, $ID2)"

# ------------------------------------------------- utilisateur par defaut
# OpenConcerto applique un REPLI : lorsqu'un compte n'a AUCUN droit pour un
# code donne, les droits de l'utilisateur « par defaut » sont utilises
# (UserRightsManager.haveRight -> getDefaultUserId).  Cet utilisateur est la
# ligne non definie de USER_COMMON : on la retrouve dans FWK_UNDEFINED_IDS,
# sinon par le login « Indéfini ».
DEF_ID=""
DEF_WHY=""
# (a) table FWK_UNDEFINED_IDS : c'est la source de verite d'OpenConcerto.
USERS_SCHEMA=$(run_sql_at "select table_schema from information_schema.tables where table_schema||'.'||table_name = '$T_USERS_RAW' limit 1")
UNDEF_Q=$(run_sql_at "select quote_ident(table_schema)||'.'||quote_ident(table_name) from information_schema.tables where upper(table_name) = 'FWK_UNDEFINED_IDS' order by (case when table_schema = '$USERS_SCHEMA' then 0 else 1 end), table_schema limit 1")
if [ -n "$UNDEF_Q" ]; then
    DEF_ID=$(run_sql_at "select \"UNDEFINED_ID\" from $UNDEF_Q where upper(\"TABLENAME\") like '%USER_COMMON%' limit 1")
    [ -n "$DEF_ID" ] && DEF_WHY="table FWK_UNDEFINED_IDS"
fi
# (b) le compte « Indéfini » (comparaison insensible aux accents).
if [ -z "$DEF_ID" ]; then
    while IFS='|' read -r did dlogin dnom dprenom; do
        [ -n "$did" ] || continue
        dlabel=$(norm "$dlogin $dnom")
        case "$dlabel" in
            *indefini*|*undefined*) DEF_ID="$did"; DEF_WHY="login « Indéfini »"; break ;;
        esac
    done <<EOF
$USERS
EOF
fi
# (c) dernier recours : le plus petit identifiant.
if [ -z "$DEF_ID" ]; then
    DEF_ID=$(run_sql_at "select min($C_U_ID) from $T_USERS")
    DEF_WHY="plus petit identifiant"
fi
[ -n "$DEF_ID" ] || die "Impossible d'identifier l'utilisateur par defaut (repli OpenConcerto)."

log "Utilisateur par defaut (repli OpenConcerto)"
DEF_FLAGS="u.$C_U_ID as id, u.$C_U_LOGIN as login"
[ -n "$C_U_ADMIN" ] && DEF_FLAGS="$DEF_FLAGS, coalesce(u.$C_U_ADMIN::text,'?') as admin"
[ -n "$C_U_SUPER" ] && DEF_FLAGS="$DEF_FLAGS, coalesce(u.$C_U_SUPER::text,'?') as superuser"
run_sql "select $DEF_FLAGS from $T_USERS u where u.$C_U_ID = $DEF_ID"
echo "  (source : $DEF_WHY)"

# ---------------------------------------------------------------- droits bruts
log "Droits bruts (table USER_RIGHT, dans l'ordre des ID)"
printf -- "  l'ordre compte : pour un couple (CODE, OBJECT), c'est la ligne d'ID le plus bas qui l'emporte.\n\n"
run_sql "select ur.$C_R_ID as id_ligne, u2.$C_U_LOGIN as login, r.$C_C_CODE as code, r.$C_C_NOM as nom, coalesce('['||ur.$C_R_OBJECT||']','<tous>') as objet, ur.$C_R_HAVE as have_right
         from $T_RIGHTS ur
         join $T_CODES r on r.$C_C_ID = ur.$C_R_RIGHT
         join $T_USERS u2 on u2.$C_U_ID = ur.$C_R_USER
         where ur.$C_R_USER in ($ID1, $ID2, $DEF_ID)
         order by ur.$C_R_USER, ur.$C_R_ID"

# ---------------------------------------------------------------- droit effectifs
# Couples (CODE, OBJECT) bruts : 1re ligne l'emporte, sans expansion ni repli.
EFF_CTE="with eff as (
    select distinct on (ur.$C_R_USER, r.$C_C_CODE, coalesce(ur.$C_R_OBJECT,''))
           ur.$C_R_USER as id_user_common, ur.$C_R_ID as id, r.$C_C_CODE as code,
           r.$C_C_NOM as nom, ur.$C_R_OBJECT as object, ur.$C_R_HAVE as have_right
    from $T_RIGHTS ur
    join $T_CODES r on r.$C_C_ID = ur.$C_R_RIGHT
    where ur.$C_R_USER in ($ID1, $ID2)
    order by ur.$C_R_USER, r.$C_C_CODE, coalesce(ur.$C_R_OBJECT,''), ur.$C_R_ID
)"

# Modele fidele au moteur de droits d'OpenConcerto 1.7 (UserRightsManager) :
#   * les lignes USER_RIGHT sont lues par ID croissant, la 1re l'emporte ;
#   * un OBJECT NULL est un « joker » : il vaut pour tout objet demande ;
#   * les droits « macro » sont decomposes :
#       TABLE_ALL_RIGHTS       -> DELETE/UPDATE/INSERT/SELECT_ROW
#       TABLE_ALL_MODIF_RIGHTS -> DELETE/UPDATE/INSERT_ROW
#       LOCK_ADMIN             -> LOCK_MENU_ADMIN + TABLE_ALL_RIGHTS sur
#                                 les tables USER_COMMON et USER_RIGHT ;
#   * si le compte n'a AUCUN droit pour un code, OpenConcerto se replie sur
#     l'utilisateur par defaut : ses droits a lui sont alors accordes ;
#   * un SUPERUSER a tous les droits, meme sans ligne en base.
OC_CTE="with base as (
    select ur.$C_R_USER as uid, ur.$C_R_ID as id_ligne, r.$C_C_CODE as code,
           ur.$C_R_OBJECT as object, ur.$C_R_HAVE as have
    from $T_RIGHTS ur
    join $T_CODES r on r.$C_C_ID = ur.$C_R_RIGHT
    where ur.$C_R_USER in ($ID1, $ID2, $DEF_ID)
), exp as (
    select uid, id_ligne, 1 as rang, code, object, have from base
    union all select uid, id_ligne, 2, 'DELETE_ROW', object, have from base where code = 'TABLE_ALL_RIGHTS'
    union all select uid, id_ligne, 3, 'UPDATE_ROW', object, have from base where code = 'TABLE_ALL_RIGHTS'
    union all select uid, id_ligne, 4, 'INSERT_ROW', object, have from base where code = 'TABLE_ALL_RIGHTS'
    union all select uid, id_ligne, 5, 'SELECT_ROW', object, have from base where code = 'TABLE_ALL_RIGHTS'
    union all select uid, id_ligne, 2, 'DELETE_ROW', object, have from base where code = 'TABLE_ALL_MODIF_RIGHTS'
    union all select uid, id_ligne, 3, 'UPDATE_ROW', object, have from base where code = 'TABLE_ALL_MODIF_RIGHTS'
    union all select uid, id_ligne, 4, 'INSERT_ROW', object, have from base where code = 'TABLE_ALL_MODIF_RIGHTS'
    union all select uid, id_ligne, 2, 'LOCK_MENU_ADMIN', null::varchar, have from base where code = 'LOCK_ADMIN'
), dedup as (
    select distinct on (uid, code, object) uid, id_ligne, rang, code, object, have
    from exp order by uid, code, object, id_ligne, rang
), pairs as (
    -- Couples compares : les droits BRUTS, tels qu'ils s'affichent dans
    -- l'administration d'OpenConcerto.  La decomposition des droits macro
    -- (TABLE_ALL_RIGHTS -> INSERT_ROW...) est traitee plus bas, dans la vue
    -- operationnelle par table : on evite ainsi de compter 5 fois le meme
    -- ecart.
    select distinct code, object from base
), uflag as (
    select u.$C_U_ID as uid,
           coalesce(u.$C_U_SUPER::text,'false') = 'true' as is_super
    from $T_USERS u
)"

# Valeur effective d'un couple (CODE, OBJECT) pour un compte, en tenant compte
# du repli sur l'utilisateur par defaut.
VALS_SQL="$OC_CTE,
vals as (
    select p.code as code, p.object as object, u.uid as uid,
           case when f.is_super then true else
             (select e.have from dedup e
               where e.uid = u.uid and e.code = p.code
                 and (case when p.object is null
                          then (e.object is null or e.have = false)
                          else (e.object is null or e.object = p.object) end)
               order by e.id_ligne, e.rang limit 1)
           end as propre,
           case when df.is_super then true else
             (select e.have from dedup e
               where e.uid = $DEF_ID and e.code = p.code
                 and (case when p.object is null
                          then (e.object is null or e.have = false)
                          else (e.object is null or e.object = p.object) end)
                 and not exists (select 1 from dedup du
                                 where du.uid = u.uid and du.code = e.code
                                   and du.object is not distinct from e.object)
               order by e.id_ligne, e.rang limit 1)
           end as repli
    from pairs p
    cross join (values ($ID1),($ID2)) as u(uid)
    join uflag f on f.uid = u.uid
    join uflag df on df.uid = $DEF_ID
)"

log "Droits effectifs (repli sur l'utilisateur par defaut inclus)"
run_sql "$VALS_SQL
         select v.uid as id_user_common, v.code as code,
                coalesce('['||v.object||']','<tous>') as objet,
                coalesce(v.propre::text,'-') as \"propre\",
                coalesce(v.repli::text,'-') as \"repli_defaut\",
                coalesce(v.propre, v.repli, false)::text as \"effectif\",
                case when v.propre is not null then 'propre'
                     when v.repli is not null then 'repli'
                     else 'aucun' end as origine
         from vals v order by v.uid, v.code, coalesce(v.object,'')"

# ---------------------------------------------------------------- différentiel
log "Différentiel des droits effectifs"
DIFF=$(run_sql "$VALS_SQL
select v1.code as code,
       coalesce('['||v1.object||']','<tous>') as objet,
       coalesce(v1.propre, v1.repli, false) as \"droit_$L1\",
       case when v1.propre is not null then 'propre' when v1.repli is not null then 'repli' else 'aucun' end as \"origine_$L1\",
       coalesce(v2.propre, v2.repli, false) as \"droit_$L2\",
       case when v2.propre is not null then 'propre' when v2.repli is not null then 'repli' else 'aucun' end as \"origine_$L2\",
       case when coalesce(v1.propre, v1.repli, false) is distinct from coalesce(v2.propre, v2.repli, false) then 'DIFFERENT' else '' end as statut
from vals v1 join vals v2 on v1.code = v2.code and coalesce(v1.object,'') = coalesce(v2.object,'')
where v1.uid = $ID1 and v2.uid = $ID2
order by 1, 2")
printf '%s\n' "$DIFF"

# Les refus explicites meritent une section a part : ce sont les lignes
# « HAVE_RIGHT = false » posees par la cible sur un droit que la reference
# accorde.  Elles se distinguent des droits simplement ABSENTS, et le moteur
# d'OpenConcerto les traite differemment (une ligne refusee l'emporte sur le
# repli vers l'utilisateur par defaut).
log "Refus explicites de $L2 (droits accordés à $L1 mais refusés par $L2)"
REFUS=$(run_sql "$VALS_SQL
select v1.code as code,
       coalesce('['||v1.object||']','<tous>') as objet,
       coalesce(v1.propre, v1.repli, false) as "droit_$L1",
       v2.propre as "droit_$L2",
       case when v2.propre is null then 'ligne absente' else 'ligne en refus' end as nature
from vals v1 join vals v2 on v1.code = v2.code and coalesce(v1.object,'') = coalesce(v2.object,'')
where v1.uid = $ID1 and v2.uid = $ID2
  and coalesce(v1.propre, v1.repli, false) = true
  and coalesce(v2.propre, v2.repli, false) = false
order by 1, 2")
printf '%s\n' "$REFUS"

# ---------------------------------------------------------------- tables du transfert
# Les droits de tables sont stockes avec l'objet « schema"."table » ; le
# moteur compare les NOMS, donc un droit sur « FACTURE » (sans schema) vaut
# pour tous les schemas.  On calcule ici, pour chaque table du transfert et
# chaque droit (INSERT/UPDATE/DELETE/SELECT), la valeur EFFECTIVE, repli sur
# l'utilisateur par defaut compris.
TABLES_CTE="$OC_CTE,
norm as (
    select uid, id_ligne, rang, code, object, have,
           case when object is null then null
                when position('.' in replace(object, chr(34), '')) > 0
                     then split_part(replace(object, chr(34), ''), '.', 2)
                else replace(object, chr(34), '') end as tbl,
           case when object is null then null
                when position('.' in replace(object, chr(34), '')) > 0
                     then split_part(replace(object, chr(34), ''), '.', 1)
                else null end as sch
    from dedup
), tabs as (
    select table_schema as sch, table_name as tab
    from information_schema.tables
    where table_schema not in ('pg_catalog','information_schema')
      and upper(table_name) in ('FACTURE','FACTURE_ELEMENT','FACTURE_FOURNISSEUR','FACTURE_FOURNISSEUR_ELEMENT',
                                 'COMMANDE','COMMANDE_ELEMENT','COMMANDE_FOURNISSEUR','COMMANDE_FOURNISSEUR_ELEMENT',
                                 'TIERS','FOURNISSEUR','FOURNISSEUR_ELEMENT')
    union
    select split_part(replace(object, chr(34), ''), '.', 1),
           split_part(replace(object, chr(34), ''), '.', 2)
    from base
    where object is not null
      and position('.' in object) > 0
      and upper(replace(object, chr(34), '')) ~ '(FACTURE|COMMANDE|FOURNISSEUR|TIERS)'
), codes(code) as (values ('INSERT_ROW'),('UPDATE_ROW'),('DELETE_ROW'),('SELECT_ROW'))"

TABLES_Q="select t.sch||'.'||t.tab as tab, c.code as code,
       x1.have as \"droit_$L1\",
       case when x1.uid = $ID1 then 'propre' when x1.uid = $DEF_ID then 'repli' else 'aucun' end as \"origine_$L1\",
       x2.have as \"droit_$L2\",
       case when x2.uid = $ID1 then 'propre' when x2.uid = $DEF_ID then 'repli' else 'aucun' end as \"origine_$L2\"
from tabs t
cross join codes c
left join lateral (
   select e.have as have, e.uid as uid
   from norm e
   where e.code = c.code and e.uid in ($ID1, $DEF_ID)
     and (e.object is null or (e.tbl = t.tab and (e.sch is null or e.sch = t.sch)))
     and (e.uid = $ID1 or not exists (select 1 from norm du
                                     where du.uid = $ID1 and du.code = e.code
                                       and du.object is not distinct from e.object))
   order by (case when e.uid = $ID1 then 0 else 1 end), e.id_ligne, e.rang
   limit 1
) x1 on true
left join lateral (
   select e.have as have, e.uid as uid
   from norm e
   where e.code = c.code and e.uid in ($ID2, $DEF_ID)
     and (e.object is null or (e.tbl = t.tab and (e.sch is null or e.sch = t.sch)))
     and (e.uid = $ID2 or not exists (select 1 from norm du
                                     where du.uid = $ID2 and du.code = e.code
                                       and du.object is not distinct from e.object))
   order by (case when e.uid = $ID2 then 0 else 1 end), e.id_ligne, e.rang
   limit 1
) x2 on true
order by 1, 2"

log "Droits effectifs sur les tables du transfert (INSERT / UPDATE / DELETE / SELECT)"
TABLES_OUT=$(run_sql "$TABLES_CTE $TABLES_Q")
printf '%s\n' "$TABLES_OUT"

# Comptage des droits d'ECRITURE accordes a la reference et manquants a la cible.
ECRITURE_MANQUANTE=$(run_sql_at "$TABLES_CTE
select count(*) from ( $TABLES_Q ) z
where z.code in ('INSERT_ROW','UPDATE_ROW')
  and z.\"droit_$L1\" = true and z.\"droit_$L2\" is distinct from true")
if [ "${ECRITURE_MANQUANTE:-0}" != "0" ]; then
    echo
    echo "  ATTENTION : $ECRITURE_MANQUANTE droit(s) d'ECRITURE accordés à $L1"
    echo "  manquent à $L2 sur les tables du transfert (INSERT_ROW / UPDATE_ROW)."
    echo "  C'est une cause directe de l'echec du transfert."
fi

# ------------------------------------------------- structure du transfert
# Le message « ID_COMMANDE_ELEMENT is not in table /FACTURE_FOURNISSEUR_ELEMENT/ »
# ne depend pas des droits : il depend du SCHEMA utilise par la session, donc
# de la societe courante. On controle donc, pour chaque schema de la base, si
# la table du transfert existe et si elle porte la colonne ID_COMMANDE_ELEMENT.
log "Structure du transfert par schema (table FACTURE_FOURNISSEUR_ELEMENT)"
STRUCT=$(run_sql_at "select t.table_schema || '|' || t.table_name || '|' || case when exists (select 1 from information_schema.columns c where c.table_schema = t.table_schema and c.table_name = t.table_name and upper(c.column_name) = 'ID_COMMANDE_ELEMENT') then 'colonne presente' else 'COLONNE MANQUANTE' end from information_schema.tables t where upper(t.table_name) = 'FACTURE_FOURNISSEUR_ELEMENT' and t.table_schema not in ('pg_catalog','information_schema') order by t.table_schema")
STRUCT_MISSING=0
if [ -z "$STRUCT" ]; then
    echo "  (aucune table FACTURE_FOURNISSEUR_ELEMENT trouvee dans cette base)"
else
    while IFS='|' read -r sch tab state; do
        [ -n "$sch" ] || continue
        printf '  %-24s %-30s %s\n' "$sch" "$tab" "$state"
        case "$state" in
            *MANQUANTE*) STRUCT_MISSING=$((STRUCT_MISSING + 1)) ;;
        esac
    done <<EOF
$STRUCT
EOF
fi
if [ "$STRUCT_MISSING" != "0" ]; then
    echo
    echo "  ATTENTION : $STRUCT_MISSING schema(s) ont la table du transfert SANS la colonne"
    echo "  ID_COMMANDE_ELEMENT. Toute operation de transfert dans ces schemas echoue avec"
    echo "  « ID_COMMANDE_ELEMENT is not in table /FACTURE_FOURNISSEUR_ELEMENT/ »."
    echo "  Correctif : scripts/fix-facture-fournisseur-all-schemas.sh"
fi

# ---------------------------------------------------------------- societes declarees
if [ -n "$T_SOCIETES_RAW" ]; then
    SC_ID=$(col "$T_SOCIETES_RAW" id)
    SC_NOM=$(col "$T_SOCIETES_RAW" nom)
    SC_SCHEMA=$(run_sql_at "select quote_ident(column_name) from information_schema.columns where table_schema||'.'||table_name = '$T_SOCIETES_RAW' and upper(column_name) like '%SCHEMA%' limit 1")
    log "Societes declarees"
    if [ -n "$SC_SCHEMA" ]; then
        run_sql_at "select $SC_ID || ' | ' || coalesce($SC_NOM,'(sans nom)') || ' | schema: ' || coalesce($SC_SCHEMA::text,'') from $T_SOCIETES order by $SC_ID" | sed 's/^/  /'
    else
        run_sql_at "select $SC_ID || ' | ' || coalesce($SC_NOM,'(sans nom)') from $T_SOCIETES order by $SC_ID" | sed 's/^/  /'
    fi
    echo "  (la societe courante est choisie a la connexion, puis memorisee par le client)"
fi


# ---------------------------------------------------------------- sociétés
if [ -n "$T_ACCES" ]; then
    log "Accès aux sociétés"
    run_sql "select acc.$C_A_USER as id_user_common, u.$C_U_LOGIN as login, acc.$C_A_SOC as id_societe_common
             from $T_ACCES acc join $T_USERS u on u.$C_U_ID = acc.$C_A_USER
             where acc.$C_A_USER in ($ID1, $ID2)
             order by acc.$C_A_USER"
    ACC_DIFF=$(run_sql_at "select count(*) from (
        select $C_A_SOC from $T_ACCES where $C_A_USER = $ID1
        except
        select $C_A_SOC from $T_ACCES where $C_A_USER = $ID2) x")
    if [ "$ACC_DIFF" != "0" ]; then
        echo
        echo "  ATTENTION : $L2 a accès à des sociétés que $L1 n'a pas (ou inversement)."
        echo "  Une société manquante provoque exactement ce type d'erreur à la création d'un document."
    fi
fi

# ---------------------------------------------------------------- verdict
log "Verdict"
MISSING=$(run_sql_at "$VALS_SQL
select count(*) from vals v1 join vals v2 on v1.code = v2.code and coalesce(v1.object,'') = coalesce(v2.object,'')
where v1.uid = $ID1 and v2.uid = $ID2
  and coalesce(v1.propre, v1.repli, false) = true
  and coalesce(v2.propre, v2.repli, false) = false")

MISSING_EXPLICIT=$(run_sql_at "$VALS_SQL
select count(*) from vals v1 join vals v2 on v1.code = v2.code and coalesce(v1.object,'') = coalesce(v2.object,'')
where v1.uid = $ID1 and v2.uid = $ID2
  and coalesce(v1.propre, v1.repli, false) = true
  and v2.propre = false")

MISSING_ABSENT=$(run_sql_at "$VALS_SQL
select count(*) from vals v1 join vals v2 on v1.code = v2.code and coalesce(v1.object,'') = coalesce(v2.object,'')
where v1.uid = $ID1 and v2.uid = $ID2
  and coalesce(v1.propre, v1.repli, false) = true
  and v2.propre is null and coalesce(v2.repli, false) = false")

SHADOW=$(run_sql_at "$EFF_CTE,
tgt as (select * from eff where id_user_common = $ID2)
select count(*) from $T_RIGHTS ur
join $T_CODES r on r.$C_C_ID = ur.$C_R_RIGHT
join tgt on tgt.code = r.$C_C_CODE and coalesce(tgt.object,'') = coalesce(ur.$C_R_OBJECT,'')
where ur.$C_R_USER = $ID2
  and ur.$C_R_ID <> tgt.id
  and ur.$C_R_HAVE is distinct from tgt.have_right")

printf '  droits accordés à %s mais absents ou refusés pour %s : %s\n' "$L1" "$L2" "${MISSING:-0}"
printf '  lignes de %s ignorées par OpenConcerto (masquées)     : %s\n' "$L2" "${SHADOW:-0}"
printf '  dont refus EXPLICITES (ligne en « false » chez %s)  : %s\n' "$L2" "${MISSING_EXPLICIT:-0}"
printf '  dont droits simplement ABSENTS chez %s           : %s\n' "$L2" "${MISSING_ABSENT:-0}"
echo "  droits d'écriture manquants sur les tables du transfert : ${ECRITURE_MANQUANTE:-0}"
echo "  SYNTHESE droits_manquants=${MISSING:-0} lignes_masquees=${SHADOW:-0} ecriture_refusee=${ECRITURE_MANQUANTE:-0} refus_explicites=${MISSING_EXPLICIT:-0} droits_absents=${MISSING_ABSENT:-0}"

if [ "${MISSING:-0}" = "0" ] && [ "${SHADOW:-0}" = "0" ]; then
    echo
    echo "  => Les droits effectifs sont identiques sur les couples (CODE, OBJECT) comparés."
    echo "     Le problème n'est donc probablement pas dans USER_RIGHT :"
    echo "     - vérifier le message exact (error2.txt) ;"
    echo "     - vérifier que le tiers/fournisseur existe dans la société de $L2 ;"
    echo "     - vérifier la société courante du compte $L2 au moment de l'opération ;"
    if [ "${STRUCT_MISSING:-0}" = "0" ]; then
        echo "     - la colonne ID_COMMANDE_ELEMENT est présente dans tous les schémas ;"
    else
        echo "     - ATTENTION : $STRUCT_MISSING schéma(s) sans ID_COMMANDE_ELEMENT (voir plus haut) ;"
    fi
    echo "     - faire rejouer l'opération par $L1 pour confirmer le périmètre."
else
    echo
    if [ "${MISSING:-0}" != "0" ]; then
        echo "  => $L2 n'a pas les droits que $L1 a (liste ci-dessus)."
        echo "     Le repli sur l'utilisateur par défaut a été pris en compte :"
        echo "     ces droits sont vraiment absents pour $L2."
        if [ "${MISSING_EXPLICIT:-0}" != "0" ]; then
            echo "     dont ${MISSING_EXPLICIT} REFUS EXPLICITE(S) : une ligne"
            echo "     « HAVE_RIGHT = false » posee par $L2. Ces lignes priment"
            echo "     sur le repli : l'option -x du correctif les supprime."
        fi
    fi
    if [ "${SHADOW:-0}" != "0" ]; then
        echo "  => $SHADOW ligne(s) de USER_RIGHT pour $L2 sont IGNORÉES par OpenConcerto :"
        echo "     une ligne d'ID plus élevé sur le même couple (CODE, OBJECT) est sans effet."
        echo "     C'est très probablement l'origine du symptôme : les droits semblent"
        echo "     accordés dans l'interface, mais la ligne la plus ancienne l'emporte."
    fi
    if [ "${ECRITURE_MANQUANTE:-0}" != "0" ]; then
        echo "  => $ECRITURE_MANQUANTE droit(s) d'ECRITURE sur les tables du transfert"
        echo "     accordés à $L1 et manquants pour $L2 : cause directe de l'échec."
    fi
    echo "  => Le correctif -f donne à $L2 les droits de $L1 (référence) ;"
    echo "     l'option -x supprime en plus les droits en trop de $L2."
fi

# ---------------------------------------------------------------- correctif
if [ "$APPLY" = "1" ]; then
    log "Correctif : copie des droits effectifs de $L1 vers $L2"
    TMPDIR_SQL=$(mktemp -d)
    BACKUP_SQL="$TMPDIR_SQL/rollback-${L2}-$(date +%Y-%m-%d_%H%M%S).sql"

    # Sauvegarde exécutable : on rejoue les lignes d'origine (sans l'ID, pour
    # ne pas désynchroniser la séquence) dans leur ordre d'origine, qui compte.
    run_sql_at "select 'INSERT INTO $T_RIGHTS ($C_R_USER, $C_R_RIGHT, $C_R_OBJECT, $C_R_HAVE) VALUES (' ||
                       ur.$C_R_USER || ', ' || ur.$C_R_RIGHT || ', ' ||
                       case when ur.$C_R_OBJECT is null then 'NULL' else quote_literal(ur.$C_R_OBJECT) end || ', ' ||
                       case when ur.$C_R_HAVE then 'true' else 'false' end || ');'
                from $T_RIGHTS ur where ur.$C_R_USER = $ID2 order by ur.$C_R_ID" \
        > "$BACKUP_SQL.INSERT"
    {
        echo "-- Restauration des droits de $L2 (id $ID2) — état avant le correctif"
        echo "-- Généré le $(date '+%Y-%m-%d %H:%M:%S')"
        echo "BEGIN;"
        echo "DELETE FROM $T_RIGHTS WHERE $C_R_USER = $ID2;"
        cat "$BACKUP_SQL.INSERT"
        echo "COMMIT;"
    } > "$BACKUP_SQL"
    rm -f "$BACKUP_SQL.INSERT"
    echo "  Script de restauration : $BACKUP_SQL"

    # Option -x : suppression des droits EN TROP de la cible, c'est-a-dire les
    # lignes dont le couple (CODE, OBJECT) n'existe pas chez la reference.
    # Ces lignes sont listees AVANT le SQL de copie, et exclues de celui-ci :
    # une ligne supprimee ne doit pas aussi etre UPDATEe.
    DEL_EXTRA=""
    EXTRA_IDS=""
    if [ "$STRICT" = "1" ]; then
        DEL_EXTRA=$(run_sql_at "$EFF_CTE,
ref as (select * from eff where id_user_common = $ID1)
select 'DELETE FROM $T_RIGHTS WHERE $C_R_ID = ' || ur.$C_R_ID || ';'
from $T_RIGHTS ur
join $T_CODES r on r.$C_C_ID = ur.$C_R_RIGHT
where ur.$C_R_USER = $ID2
  and not exists (select 1 from ref
                  where ref.code = r.$C_C_CODE
                    and coalesce(ref.object,'') = coalesce(ur.$C_R_OBJECT,''))
order by ur.$C_R_ID" | sed '/^$/d')
        EXTRA_IDS=$(run_sql_at "$EFF_CTE,
ref as (select * from eff where id_user_common = $ID1)
select string_agg(ur.$C_R_ID::text, ',')
from $T_RIGHTS ur
join $T_CODES r on r.$C_C_ID = ur.$C_R_RIGHT
where ur.$C_R_USER = $ID2
  and not exists (select 1 from ref
                  where ref.code = r.$C_C_CODE
                    and coalesce(ref.object,'') = coalesce(ur.$C_R_OBJECT,''))")
    fi

    # SQL généré : on repart de l'état effectif de la référence
    FIX_SQL=$(run_sql_at "$EFF_CTE,
ref as (select * from eff where id_user_common = $ID1),
tgt as (select * from eff where id_user_common = $ID2)
select case
         when tgt.code is null then
           'INSERT INTO $T_RIGHTS ($C_R_USER, $C_R_RIGHT, $C_R_OBJECT, $C_R_HAVE) VALUES ($ID2, (select $C_C_ID from $T_CODES where $C_C_CODE = ' || quote_literal(ref.code) || '), ' ||
           case when ref.object is null then 'NULL' else quote_literal(ref.object) end || ', ' ||
           case when ref.have_right then 'true' else 'false' end || ');'
         when ref.have_right is distinct from tgt.have_right then
           'UPDATE $T_RIGHTS SET $C_R_HAVE = ' || case when ref.have_right then 'true' else 'false' end ||
           ' WHERE $C_R_ID = ' || tgt.id || ';'
         else null
       end
from ref full outer join tgt on ref.code = tgt.code and coalesce(ref.object,'') = coalesce(tgt.object,'')
where ref.have_right is distinct from tgt.have_right
  and (tgt.id is null or tgt.id not in (select unnest(string_to_array('$EXTRA_IDS', ','))::int))" | sed '/^$/d')

    # Les doublons (même couple, plusieurs lignes) sont neutralisés : seule
    # la ligne d'ID le plus bas compte, les suivantes sont ignorées par
    # OpenConcerto. On supprime donc les lignes d'ID SUPÉRIEUR, uniquement
    # pour les couples réellement synchronisés ci-dessus.
    DUP_SQL=$(run_sql_at "$EFF_CTE,
ref as (select * from eff where id_user_common = $ID1),
tgt as (select * from eff where id_user_common = $ID2)
select 'DELETE FROM $T_RIGHTS WHERE $C_R_ID = ' || ur.$C_R_ID || ';'
from $T_RIGHTS ur
join $T_CODES r on r.$C_C_ID = ur.$C_R_RIGHT
join ref on ref.code = r.$C_C_CODE and coalesce(ref.object,'') = coalesce(ur.$C_R_OBJECT,'')
join tgt on tgt.code = ref.code and coalesce(tgt.object,'') = coalesce(ref.object,'')
where ur.$C_R_USER = $ID2
  and ref.have_right is distinct from tgt.have_right
  and exists (select 1 from $T_RIGHTS ur2
              where ur2.$C_R_USER = $ID2
                and ur2.$C_R_RIGHT = ur.$C_R_RIGHT
                and coalesce(ur2.$C_R_OBJECT,'') = coalesce(ur.$C_R_OBJECT,'')
                and ur2.$C_R_ID < ur.$C_R_ID)" | sed '/^$/d')

    FIX_FILE="$TMPDIR_SQL/correctif-${L2}.sql"
    {
        echo "-- Correctif des droits OpenConcerto"
        echo "-- Utilisateur source : $L1 (id $ID1)"
        echo "-- Utilisateur cible  : $L2 (id $ID2)"
        echo "-- Généré le $(date '+%Y-%m-%d %H:%M:%S')"
        echo "BEGIN;"
        if [ -n "$FIX_SQL" ]; then
            echo "$FIX_SQL"
        else
            echo "-- (aucun droit à ajouter ou à corriger)"
        fi
        if [ -n "$DUP_SQL" ]; then
            echo "-- suppression des lignes en doublon (seule la plus ancienne compte)"
            echo "$DUP_SQL"
        fi
        if [ -n "$DEL_EXTRA" ]; then
            echo "-- suppression des droits en trop de $L2 (option -x)"
            echo "$DEL_EXTRA"
        fi
        echo "COMMIT;"
    } > "$FIX_FILE"

    echo
    echo "  SQL généré :"
    sed 's/^/    /' "$FIX_FILE"

    if [ "$DRY" = "1" ]; then
        echo
        echo "  Dry-run : rien n'a été appliqué. Pour appliquer :"
        printf '    bash %s -1 %s -2 %s -f -y\n' "$0" "$PAT1" "$PAT2"
        exit 0
    fi

    if [ "$ASSUME_YES" -ne 1 ]; then
        printf '\nAppliquer ce correctif ? [o/N] '
        read -r answer
        case "$answer" in
            o|O|oui|OUI|y|Y) ;;
            *) echo "Annulé."; exit 0 ;;
        esac
    fi

    if [ "$USE_DOCKER" = "1" ]; then
        docker compose -f "$COMPOSE" exec -T db psql -X -U "$ROLE" -d "$BASE" -v ON_ERROR_STOP=1 -f - < "$FIX_FILE"
    else
        PGPASSWORD="$PASSWORD" psql -X -h "$HOST" -p "$PORT" -U "$ROLE" -d "$BASE" -v ON_ERROR_STOP=1 -f - < "$FIX_FILE"
    fi
    echo
    echo "  Correctif appliqué."
    echo "  IMPORTANT : l'utilisateur '$L2' doit se reconnecter (fermer la session"
    echo "  OpenConcerto et se reconnecter). Les droits sont mis en cache côté"
    echo "  client : sans reconnexion, le problème semblera toujours présent."
    echo "  Fichier de sauvegarde des droits précédents : $BACKUP_SQL"
fi
