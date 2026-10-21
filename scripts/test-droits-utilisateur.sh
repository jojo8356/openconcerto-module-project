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
T_USERS=""; T_RIGHTS=""; T_CODES=""; T_ACCES=""
while IFS='|' read -r sch tab; do
    [ -n "$tab" ] || continue
    case "$tab" in
        USER_COMMON|UTILISATEUR_COMMON|UTILISATEUR|USER)
            [ -n "$T_USERS" ] || T_USERS="$sch.$tab" ;;
        USER_RIGHT|DROIT_UTILISATEUR|UTILISATEUR_DROIT|USER_RIGHTS)
            [ -n "$T_RIGHTS" ] || T_RIGHTS="$sch.$tab" ;;
        RIGHT|DROIT|TYPE_DROIT)
            [ -n "$T_CODES" ] || T_CODES="$sch.$tab" ;;
        ACCES_SOCIETE|ACCES_SOCIETES)
            [ -n "$T_ACCES" ] || T_ACCES="$sch.$tab" ;;
    esac
done <<EOF
$(run_sql_at "select table_schema, table_name from information_schema.tables where table_name in ('USER_COMMON','UTILISATEUR_COMMON','UTILISATEUR','USER','USER_RIGHT','DROIT_UTILISATEUR','UTILISATEUR_DROIT','USER_RIGHTS','RIGHT','DROIT','TYPE_DROIT','ACCES_SOCIETE','ACCES_SOCIETES') order by table_schema, table_name")
EOF

[ -n "$T_USERS" ] || die "Table des utilisateurs introuvable (USER_COMMON attendu)."
[ -n "$T_RIGHTS" ] || die "Table des droits par utilisateur introuvable (USER_RIGHT attendue)."
[ -n "$T_CODES" ] || die "Table des codes de droits introuvable (RIGHT attendue)."

log "Tables utilisées"
printf '  utilisateurs : %s\n' "$T_USERS"
printf '  droits       : %s\n' "$T_RIGHTS"
printf '  codes        : %s\n' "$T_CODES"
[ -n "$T_ACCES" ] && printf '  accès societe: %s\n' "$T_ACCES"

# Les colonnes doivent exister
COLS=$(run_sql_at "select string_agg(column_name, ',' order by column_name) from information_schema.columns where table_schema||'.'||table_name = '$T_RIGHTS'")
case "$COLS" in
    *ID_USER_COMMON*) ;;
    *) die "La table $T_RIGHTS n'a pas de colonne ID_USER_COMMON (colonnes : $COLS)." ;;
esac
case "$COLS" in
    *HAVE_RIGHT*) ;;
    *) die "La table $T_RIGHTS n'a pas de colonne HAVE_RIGHT (colonnes : $COLS)." ;;
esac

# ---------------------------------------------------------------- utilisateurs
# On récupère tous les utilisateurs, on filtre en bash (insensible aux accents).
USERS=$(run_sql_at "select id, login, coalesce(nom,''), coalesce(prenom,'') from $T_USERS order by id")

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
run_sql "select id, login, nom, prenom from $T_USERS order by id"

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
UCOLS=$(run_sql_at "select string_agg(column_name, ',' order by column_name) from information_schema.columns where table_schema||'.'||table_name = '$T_USERS'")
FLAG_ADMIN=""
FLAG_SUPER=""
case "$UCOLS" in
    *ADMIN*) FLAG_ADMIN="ADMIN" ;;
esac
case "$UCOLS" in
    *SUPERUSER*) FLAG_SUPER="SUPERUSER" ;;
esac

SQL_FLAGS="u.id"
[ -n "$FLAG_ADMIN" ] && SQL_FLAGS="$SQL_FLAGS, coalesce(u.$FLAG_ADMIN::text,'?')"
[ -n "$FLAG_SUPER" ] && SQL_FLAGS="$SQL_FLAGS, coalesce(u.$FLAG_SUPER::text,'?')"

log "Utilisateurs comparés"
printf '  référence   : id=%s  %s  (%s)\n' "$ID1" "$L1" "$U1"
printf '  concerné    : id=%s  %s  (%s)\n' "$ID2" "$L2" "$U2"
run_sql "select $SQL_FLAGS from $T_USERS u where u.id in ($ID1, $ID2)"

# ---------------------------------------------------------------- droits bruts
log "Droits bruts (table USER_RIGHT, dans l'ordre des ID)"
printf -- "  l'ordre compte : pour un couple (CODE, OBJECT), c'est la ligne d'ID le plus bas qui l'emporte.\n\n"
run_sql "select ur.id as id_ligne, u2.login, r.code, r.nom, coalesce('['||ur.object||']','<tous>') as objet, ur.have_right
         from $T_RIGHTS ur
         join $T_CODES r on r.id = ur.id_right
         join $T_USERS u2 on u2.id = ur.id_user_common
         where ur.id_user_common in ($ID1, $ID2)
         order by ur.id_user_common, ur.id"

# ---------------------------------------------------------------- droit effectifs
EFF_CTE="with eff as (
    select distinct on (ur.id_user_common, r.code, coalesce(ur.object,''))
           ur.id_user_common, ur.id, r.code, r.nom, ur.object, ur.have_right
    from $T_RIGHTS ur
    join $T_CODES r on r.id = ur.id_right
    where ur.id_user_common in ($ID1, $ID2)
    order by ur.id_user_common, r.code, coalesce(ur.object,''), ur.id
)"

log "Droits effectifs (1re ligne par couple CODE/OBJECT)"
run_sql "$EFF_CTE
         select e.id_user_common, e.id as id_ligne, e.code, coalesce('['||e.object||']','<tous>') as objet, e.have_right
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
         select e.id_user_common, e.code, coalesce('['||e.object||']','<tous>') as objet, e.have_right
         from eff e
         where e.code in ('TABLE_ALL_RIGHTS','TABLE_ALL_MODIF_RIGHTS','INSERT_ROW','UPDATE_ROW','SELECT_ROW','DELETE_ROW')
           and (coalesce(e.object,'') ~* 'FACTURE|COMMANDE|FOURNISSEUR|TIERS' or coalesce(e.object,'') = '')
         order by e.id_user_common, e.code, e.object"

# ---------------------------------------------------------------- sociétés
if [ -n "$T_ACCES" ]; then
    log "Accès aux sociétés"
    run_sql "select acc.id_user_common, u.login, acc.id_societe_common
             from $T_ACCES acc join $T_USERS u on u.id = acc.id_user_common
             where acc.id_user_common in ($ID1, $ID2)
             order by acc.id_user_common"
    ACC_DIFF=$(run_sql_at "select count(*) from (
        select id_societe_common from $T_ACCES where id_user_common = $ID1
        except
        select id_societe_common from $T_ACCES where id_user_common = $ID2) x")
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
join $T_CODES r on r.id = ur.id_right
join tgt on tgt.code = r.code and coalesce(tgt.object,'') = coalesce(ur.object,'')
where ur.id_user_common = $ID2
  and ur.id <> tgt.id
  and ur.have_right is distinct from tgt.have_right")

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
    run_sql_at "select 'INSERT INTO $T_RIGHTS (id_user_common, id_right, object, have_right) VALUES (' ||
                       ur.id_user_common || ', ' || ur.id_right || ', ' ||
                       case when ur.object is null then 'NULL' else quote_literal(ur.object) end || ', ' ||
                       case when ur.have_right then 'true' else 'false' end || ');'
                from $T_RIGHTS ur where ur.id_user_common = $ID2 order by ur.id" \
        > "$BACKUP_SQL.INSERT"
    {
        echo "-- Restauration des droits de $L2 (id $ID2) — état avant le correctif"
        echo "-- Généré le $(date '+%Y-%m-%d %H:%M:%S')"
        echo "BEGIN;"
        echo "DELETE FROM $T_RIGHTS WHERE id_user_common = $ID2;"
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
           'INSERT INTO $T_RIGHTS (id_user_common, id_right, object, have_right) VALUES ($ID2, (select id from $T_CODES where code = ' || quote_literal(ref.code) || '), ' ||
           case when ref.object is null then 'NULL' else quote_literal(ref.object) end || ', ' ||
           case when ref.have_right then 'true' else 'false' end || ');'
         when ref.have_right is distinct from tgt.have_right then
           'UPDATE $T_RIGHTS SET have_right = ' || case when ref.have_right then 'true' else 'false' end ||
           ' WHERE id = ' || tgt.id || ';'
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
select 'DELETE FROM $T_RIGHTS WHERE id = ' || ur.id || ';'
from $T_RIGHTS ur
join $T_CODES r on r.id = ur.id_right
join ref on ref.code = r.code and coalesce(ref.object,'') = coalesce(ur.object,'')
join tgt on tgt.code = ref.code and coalesce(tgt.object,'') = coalesce(ref.object,'')
where ur.id_user_common = $ID2
  and ref.have_right is distinct from tgt.have_right
  and exists (select 1 from $T_RIGHTS ur2
              where ur2.id_user_common = $ID2
                and ur2.id_right = ur.id_right
                and coalesce(ur2.object,'') = coalesce(ur.object,'')
                and ur2.id < ur.id)" | sed '/^$/d')

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
