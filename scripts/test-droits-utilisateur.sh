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
DRY=0
ASSUME_YES=0

usage() {
    awk '/^# BEGIN_UTILISE/{f=1;next} /^# END_UTILISE/{f=0} f' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while getopts ":1:2:b:H:p:U:P:co:fnyh" opt; do
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
T_USERS=""; T_RIGHTS=""; T_CODES=""; T_ACCES=""
T_USERS_RAW=""; T_RIGHTS_RAW=""; T_CODES_RAW=""; T_ACCES_RAW=""
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
    esac
done <<EOF
$(run_sql_at "select table_schema, table_name, quote_ident(table_schema)||'.'||quote_ident(table_name) from information_schema.tables where table_name in ('USER_COMMON','UTILISATEUR_COMMON','UTILISATEUR','USER','USER_RIGHT','DROIT_UTILISATEUR','UTILISATEUR_DROIT','USER_RIGHTS','RIGHT','DROIT','TYPE_DROIT','ACCES_SOCIETE','ACCES_SOCIETES') order by table_schema, table_name")
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

norm() {
    printf '%s' "$1" | tr 'A-ZÀÂÄÉÈÊËÎÏÔÖÛÜÇŒÆ' 'aazaaeeeeiioouu(coe' | tr -d "'" | tr -s ' '
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

# ---------------------------------------------------------------- droits bruts
log "Droits bruts (table USER_RIGHT, dans l'ordre des ID)"
printf -- "  l'ordre compte : pour un couple (CODE, OBJECT), c'est la ligne d'ID le plus bas qui l'emporte.\n\n"
run_sql "select ur.$C_R_ID as id_ligne, u2.$C_U_LOGIN as login, r.$C_C_CODE as code, r.$C_C_NOM as nom, coalesce('['||ur.$C_R_OBJECT||']','<tous>') as objet, ur.$C_R_HAVE as have_right
         from $T_RIGHTS ur
         join $T_CODES r on r.$C_C_ID = ur.$C_R_RIGHT
         join $T_USERS u2 on u2.$C_U_ID = ur.$C_R_USER
         where ur.$C_R_USER in ($ID1, $ID2)
         order by ur.$C_R_USER, ur.$C_R_ID"

# ---------------------------------------------------------------- droit effectifs
EFF_CTE="with eff as (
    select distinct on (ur.$C_R_USER, r.$C_C_CODE, coalesce(ur.$C_R_OBJECT,''))
           ur.$C_R_USER as id_user_common, ur.$C_R_ID as id, r.$C_C_CODE as code,
           r.$C_C_NOM as nom, ur.$C_R_OBJECT as object, ur.$C_R_HAVE as have_right
    from $T_RIGHTS ur
    join $T_CODES r on r.$C_C_ID = ur.$C_R_RIGHT
    where ur.$C_R_USER in ($ID1, $ID2)
    order by ur.$C_R_USER, r.$C_C_CODE, coalesce(ur.$C_R_OBJECT,''), ur.$C_R_ID
)"

log "Droits effectifs (1re ligne par couple CODE/OBJECT)"
run_sql "$EFF_CTE
         select e.id_user_common as id_user_common, e.id as id_ligne, e.code as code, coalesce('['||e.object||']','<tous>') as objet, e.have_right as have_right
         from eff e order by e.id_user_common, e.code, e.object"

# ---------------------------------------------------------------- différentiel
log "Différentiel des droits effectifs"
DIFF_SQL="$EFF_CTE,
u1 as (select * from eff where id_user_common = $ID1),
u2 as (select * from eff where id_user_common = $ID2)
select coalesce(u1.code, u2.code) as code,
       coalesce('['||u1.object||']','<tous>') as objet_ref,
       u1.have_right as \"droit_$L1\",
       u2.have_right as \"droit_$L2\",
       case when u1.have_right is distinct from u2.have_right then 'DIFFERENT' else '' end as statut
from u1 full outer join u2 on u1.code = u2.code and coalesce(u1.object,'') = coalesce(u2.object,'')
where u1.have_right is distinct from u2.have_right
order by 1, 2"

DIFF=$(run_sql "$DIFF_SQL")
printf '%s\n' "$DIFF"

# ---------------------------------------------------------------- tables du transfert
log "Droits sur les tables du transfert (FACTURE / COMMANDE / FOURNISSEUR / TIERS)"
run_sql "$EFF_CTE
         select e.id_user_common as id_user_common, e.code as code, coalesce('['||e.object||']','<tous>') as objet, e.have_right as have_right
         from eff e
         where e.code in ('TABLE_ALL_RIGHTS','TABLE_ALL_MODIF_RIGHTS','INSERT_ROW','UPDATE_ROW','SELECT_ROW','DELETE_ROW')
           and (coalesce(e.object,'') ~* 'FACTURE|COMMANDE|FOURNISSEUR|TIERS' or coalesce(e.object,'') = '')
         order by e.id_user_common, e.code, e.object"

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
MISSING=$(run_sql_at "$EFF_CTE,
u1 as (select * from eff where id_user_common = $ID1),
u2 as (select * from eff where id_user_common = $ID2)
select count(*) from u1 left join u2 on u1.code = u2.code and coalesce(u1.object,'') = coalesce(u2.object,'')
where u1.have_right = true and (u2.have_right is null or u2.have_right = false)")

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

if [ "${MISSING:-0}" = "0" ] && [ "${SHADOW:-0}" = "0" ]; then
    echo
    echo "  => Les droits effectifs sont identiques sur les couples (CODE, OBJECT) comparés."
    echo "     Le problème n'est donc probablement pas dans USER_RIGHT :"
    echo "     - vérifier le message exact (error2.txt) ;"
    echo "     - vérifier que le tiers/fournisseur existe dans la société de $L2 ;"
    echo "     - vérifier la société courante du compte $L2 au moment de l'opération ;"
    echo "     - faire rejouer l'opération par $L1 pour confirmer le périmètre."
else
    echo
    if [ "${MISSING:-0}" != "0" ]; then
        echo "  => $L2 n'a pas les droits que $L1 a (liste ci-dessus)."
    fi
    if [ "${SHADOW:-0}" != "0" ]; then
        echo "  => $SHADOW ligne(s) de USER_RIGHT pour $L2 sont IGNORÉES par OpenConcerto :"
        echo "     une ligne d'ID plus élevé sur le même couple (CODE, OBJECT) est sans effet."
        echo "     C'est très probablement l'origine du symptôme : les droits semblent"
        echo "     accordés dans l'interface, mais la ligne la plus ancienne l'emporte."
    fi
    echo "  => Le correctif -f aligne les droits effectifs de $L1 sur ceux de $L2."
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
where ref.have_right is distinct from tgt.have_right" | sed '/^$/d')

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
