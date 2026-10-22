#!/usr/bin/env bash
#
# RAPPORT DETAILLE des lignes qui ne sont PAS affichees par les panneaux du
# module org.openconcerto.modules.project (v1.1).
#
# Pour chaque table lue par un panneau, le script liste TOUTES les lignes
# invisibles, ligne par ligne, avec leurs identifiants (cle primaire, numero,
# date, montants, ID_AFFAIRE, mere) et la raison precise :
#
#   SANS AFFAIRE           la ligne n'a pas d'ID_AFFAIRE
#   MERE SANS AFFAIRE      la ligne est rattachee a une mere sans ID_AFFAIRE
#   MERE ABSENTE           la ligne est rattachee a une mere disparue
#   AFFAIRE INEXISTANTE    l'ID_AFFAIRE ne correspond a aucune AFFAIRE
#   AFFAIRE TECHNIQUE      l'ID_AFFAIRE vaut 1 (ligne « Indefini » du module)
#
# Le rapport est un fichier texte, il peut etre lu, envoye par mail ou
# archive tel quel.
#
# Lecture seule : aucune ecriture n'est faite dans la base.
#
# Usage :
#   bash scripts/rapport-lignes-manquantes.sh [options]
#
# Options :
#   --mode MODE     docker | local | vm   (defaut : docker)
#                   docker : la base du poste (stack Docker/Podman), via le
#                            socket local du conteneur (aucun mot de passe)
#                   local  : psql du poste vers --host/--port
#                   vm     : le rapport est produit DANS la VM (la ou est la
#                            base), puis rapatrie sur le poste
#   --stack DIR     dossier de la stack    (defaut : ~/oc-176-podman)
#   --host HOTE     hote PostgreSQL        (defaut : 127.0.0.1)
#   --port PORT     port                   (defaut : 5433)
#   --db BASE       base                   (defaut : OpenConcerto)
#   --user ROLE     role SQL               (defaut : openconcerto)
#   --password MDP  mot de passe           (defaut : PGPASSWORD, .env de la
#                                          stack, config du client OC, ou
#                                          environnement du conteneur)
#   --schema SCHEMA schema a analyser      (defaut : tous les schemas avec
#                                          une table AFFAIRE)
#   --out FICHIER   fichier du rapport     (defaut : rapport-lignes-manquantes-<date>.txt)
#   --limit N       nombre de lignes detaillees par table (defaut : 0 = toutes)
#   --vm-host HOTE  adresse de la VM        (defaut : 127.0.0.1)
#   --vm-port PORT  port SSH de la VM       (defaut : 2222)
#   --vm-user UTIL  compte de la VM         (defaut : oc)
#   --vm-password MDP mot de passe du compte de la VM (defaut : oc)
#   -h|--help       cette aide
#
# Exemples :
#   bash scripts/rapport-lignes-manquantes.sh
#   bash scripts/rapport-lignes-manquantes.sh --mode vm --out rapport.txt
#   bash scripts/rapport-lignes-manquantes.sh --mode local --password secret
#
set -uo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

MODE=docker
STACK_DIR=${STACK_DIR:-$HOME/oc-176-podman}
DB_HOST=127.0.0.1
DB_PORT=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
SCHEMA=""
OUT=""
LIMIT=0
VM_HOST=127.0.0.1
VM_PORT=2222
VM_USER=oc
VM_PASSWORD=oc
REMOTE_SCRIPT="scripts/rapport-lignes-manquantes.sh"

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '  ATTENTION : %s\n' "$*" >&2; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '/^# Options/,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --mode) MODE="$2"; shift 2 ;;
        --stack) STACK_DIR="$2"; shift 2 ;;
        --host) DB_HOST="$2"; shift 2 ;;
        --port) DB_PORT="$2"; shift 2 ;;
        --db) DB_NAME="$2"; shift 2 ;;
        --user) DB_USER="$2"; shift 2 ;;
        --password) DB_PASSWORD="$2"; shift 2 ;;
        --schema) SCHEMA="$2"; shift 2 ;;
        --out) OUT="$2"; shift 2 ;;
        --limit) LIMIT="$2"; shift 2 ;;
        --vm-host) VM_HOST="$2"; shift 2 ;;
        --vm-port) VM_PORT="$2"; shift 2 ;;
        --vm-user) VM_USER="$2"; shift 2 ;;
        --vm-password) VM_PASSWORD="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "option inconnue : $1" >&2; usage >&2 ;;
    esac
done

case "$MODE" in
    docker|local|vm) ;;
    *) die "mode invalide : $MODE (docker, local ou vm)" ;;
esac

# ===========================================================================
# Mode « vm » : le rapport est produit dans la VM (la ou vit la base), puis
# rapatrie sur le poste.
# ===========================================================================
if [ "$MODE" = "vm" ]; then
    command -v ssh >/dev/null 2>&1 || die "'ssh' introuvable."
    command -v scp >/dev/null 2>&1 || die "'scp' introuvable."
    VM_DIR="/home/$VM_USER/oc-176"
    SSH_OPTS=(-p "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10)
    [ -f "$HOME/.ssh/id_ed25519_oc176" ] && SSH_OPTS+=(-i "$HOME/.ssh/id_ed25519_oc176")
    REMOTE_REPORT="$VM_DIR/rapport-lignes-manquantes.txt"

    log "Envoi du script dans la VM ($VM_USER@$VM_HOST:$VM_PORT)"
    ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "mkdir -p '$VM_DIR/scripts'" || die "acces a la VM impossible"
    scp "${SSH_OPTS[@]}" "$SCRIPT_DIR/rapport-lignes-manquantes.sh" "$VM_USER@$VM_HOST:$VM_DIR/scripts/rapport-lignes-manquantes.sh" \
        || die "envoi du script impossible"

    log "Mot de passe de la base dans la VM"
    VM_DB_PASSWORD=""
    VM_DB_PASSWORD=$(ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "sed -n 's/^POSTGRES_PASSWORD=//p' '$VM_DIR/docker/openconcerto-1.7.6/.env' 2>/dev/null | head -1" 2>/dev/null | tr -d '\r\n')
    if [ -z "$VM_DB_PASSWORD" ]; then
        VM_DB_PASSWORD=$(ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "docker exec \$(docker ps --format '{{.Names}}' | grep -E 'db' | head -1) printenv POSTGRES_PASSWORD 2>/dev/null" 2>/dev/null | tr -d '\r\n')
    fi
    [ -n "$VM_DB_PASSWORD" ] || die "mot de passe PostgreSQL introuvable dans la VM"

    log "Production du rapport dans la VM"
    VM_OPTS="${SCHEMA:+--schema '$SCHEMA'} ${LIMIT:+--limit $LIMIT} --out '$REMOTE_REPORT'"
    set +e
    # 1) connexion TCP (avec le mot de passe de la stack)
    ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "cd '$VM_DIR' && bash scripts/rapport-lignes-manquantes.sh --mode local --host 127.0.0.1 --port 5433 \
--db ${DB_NAME:-OpenConcerto} --user ${DB_USER:-openconcerto} --password '$VM_DB_PASSWORD' \
$VM_OPTS"
    CODE=$?
    if [ "$CODE" -ne 0 ]; then
        # 2) repli : lecture directe dans le conteneur PostgreSQL (socket local)
        warn "la connexion TCP a echoue, nouvelle tentative dans le conteneur PostgreSQL"
        ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "cd '$VM_DIR' && bash scripts/rapport-lignes-manquantes.sh --mode docker \
--stack '$VM_DIR/docker/openconcerto-1.7.6' $VM_OPTS"
        CODE=$?
    fi
    set -e
    [ "$CODE" -eq 0 ] || die "la production du rapport dans la VM a echoue (code $CODE). Verifie que la stack PostgreSQL tourne dans la VM (commande indiquee dans docs/tests-panneaux-module-project.md, section 4.1)"

    LOCAL_OUT="$OUT"
    [ -n "$LOCAL_OUT" ] || LOCAL_OUT="rapport-lignes-manquantes-$(date +%Y%m%d-%H%M%S).txt"
    scp "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST:$REMOTE_REPORT" "$LOCAL_OUT" || die "recuperation du rapport impossible"
    echo
    echo "Rapport : $LOCAL_OUT"
    exit 0
fi

# ===========================================================================
# Connexion a la base
# ===========================================================================
RUNTIME=""
CID=""
WRAPPER_DIR=""

compose_cmd() {
    if [ "$RUNTIME" = podman ] && $RUNTIME compose version >/dev/null 2>&1; then
        printf '%s' "podman compose"
    elif [ "$RUNTIME" = docker ] && $RUNTIME compose version >/dev/null 2>&1; then
        printf '%s' "docker compose"
    elif [ "$RUNTIME" = podman ] && command -v podman-compose >/dev/null 2>&1; then
        printf '%s' podman-compose
    elif [ "$RUNTIME" = docker ] && command -v docker-compose >/dev/null 2>&1; then
        printf '%s' docker-compose
    else
        printf '%s' ""
    fi
}

db_container_id() {
    local cid cc
    cid=$($RUNTIME ps -q --filter "name=openconcerto176-db" 2>/dev/null | head -n 1)
    if [ -z "$cid" ]; then
        cc=$(compose_cmd)
        if [ -n "$cc" ] && [ -n "$COMPOSE_FILE" ]; then
            cid=$(cd "$(dirname "$COMPOSE_FILE")" && $cc -p openconcerto176 -f "$COMPOSE_FILE" ps -q db 2>/dev/null | head -n 1)
        fi
    fi
    if [ -z "$cid" ]; then
        cid=$($RUNTIME ps -q --filter "ancestor=postgres" 2>/dev/null | head -n 1)
    fi
    printf '%s' "$cid"
}

db_container_id_stopped() {
    local cid
    cid=$($RUNTIME ps -a -q --filter "name=openconcerto176-db" 2>/dev/null | head -n 1)
    if [ -z "$cid" ]; then
        cid=$($RUNTIME ps -a -q --filter "ancestor=postgres" 2>/dev/null | head -n 1)
    fi
    printf '%s' "$cid"
}

container_env() {
    $RUNTIME inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CID" 2>/dev/null
}

env_value() {
    [ -n "$ENV_FILE" ] || return 1
    sed -n "s/^$1=//p" "$ENV_FILE" | head -1 | tr -d '\r'
}

container_value() {
    container_env | sed -n "s/^$1=//p" | head -1 | tr -d '\r'
}

if [ "$MODE" = docker ]; then
    if command -v podman >/dev/null 2>&1; then
        RUNTIME=podman
    elif command -v docker >/dev/null 2>&1; then
        RUNTIME=docker
    else
        die "ni podman ni docker n'est disponible sur ce poste (utilisez --mode local ou --mode vm)."
    fi
    COMPOSE_FILE=""
    for candidate in \
        "$STACK_DIR/compose.yaml" \
        "$STACK_DIR/compose.yml" \
        "$STACK_DIR/docker-compose.yml" \
        "$STACK_DIR/docker-compose.yaml" \
        "$STACK_DIR"/docker/openconcerto-1.7.6/docker-compose.yml \
        "$STACK_DIR"/docker/openconcerto-1.7.6/docker-compose.yaml; do
        [ -f "$candidate" ] || continue
        COMPOSE_FILE="$candidate"
        break
    done
    CID=$(db_container_id)
    if [ -z "$CID" ]; then
        STOPPED_CID=$(db_container_id_stopped)
        if [ -n "$STOPPED_CID" ]; then
            STOPPED_NAME=$($RUNTIME inspect -f '{{.Name}}' "$STOPPED_CID" 2>/dev/null | sed 's|^/||')
            die "le conteneur PostgreSQL '$STOPPED_NAME' existe mais est ARRETE.
  Demarre la stack :
      bash scripts/podman-openconcerto.* up
  (ou, si la base est dans la VM : bash scripts/rapport-lignes-manquantes.* --mode vm)"
        fi
        die "aucun conteneur PostgreSQL trouve (stack $STACK_DIR).
  Etat de la stack :
      bash scripts/podman-openconcerto.* status
  Si la stack n'existe pas encore, cree-la puis demarre-la :
      bash scripts/podman-openconcerto.* up
  Si la base est dans la VM, utilise :
      bash scripts/rapport-lignes-manquantes.* --mode vm"
    fi
    info "runtime   : $RUNTIME"
    info "conteneur : $($RUNTIME inspect -f '{{.Name}}' "$CID" 2>/dev/null | sed 's|^/||')"
fi

ENV_FILE=""
for candidate in \
    "$STACK_DIR/.env" \
    "$STACK_DIR"/docker/openconcerto-1.7.6/.env \
    "$STACK_DIR"/*/.env; do
    [ -f "$candidate" ] || continue
    ENV_FILE="$candidate"
    break
done

if [ -z "$DB_PORT" ]; then DB_PORT=$(env_value PG_HOST_PORT 2>/dev/null || true); fi
[ -n "$DB_PORT" ] || DB_PORT=$(container_value PG_HOST_PORT 2>/dev/null || true)
if [ -z "$DB_NAME" ]; then DB_NAME=$(env_value POSTGRES_DB 2>/dev/null || true); fi
[ -n "$DB_NAME" ] || DB_NAME=$(container_value POSTGRES_DB 2>/dev/null || true)
if [ -z "$DB_USER" ]; then DB_USER=$(env_value POSTGRES_USER 2>/dev/null || true); fi
[ -n "$DB_USER" ] || DB_USER=$(container_value POSTGRES_USER 2>/dev/null || true)
if [ -z "$DB_PASSWORD" ] && [ -n "${PGPASSWORD:-}" ]; then
    DB_PASSWORD=$PGPASSWORD
elif [ -z "$DB_PASSWORD" ]; then
    DB_PASSWORD=$(env_value POSTGRES_PASSWORD 2>/dev/null || true)
fi
if [ -z "$DB_PASSWORD" ]; then
    for conf in "${OC_CONF:-}" "$HOME/.config/OpenConcerto/main.properties" "$HOME/.openconcerto/main.properties"; do
        [ -n "$conf" ] && [ -f "$conf" ] || continue
        cand=$(sed -n 's/^server\.password=//p' "$conf" | head -1 | tr -d '\r')
        if [ -n "$cand" ]; then
            DB_PASSWORD=$cand
            break
        fi
    done
fi
[ -z "$DB_PASSWORD" ] || true
[ -n "$DB_PASSWORD" ] || DB_PASSWORD=$(container_value POSTGRES_PASSWORD 2>/dev/null || true)

DB_PORT=${DB_PORT:-5433}
DB_NAME=${DB_NAME:-OpenConcerto}
DB_USER=${DB_USER:-openconcerto}

if [ "$MODE" = docker ]; then
    # Le conteneur PostgreSQL accepte les connexions locales (socket unix)
    # sans mot de passe : c'est le moyen le plus sur de lire la base.
    WRAPPER_DIR=$(mktemp -d 2>/dev/null) || die "impossible de creer un repertoire temporaire"
    # le mot de passe n'est passe au conteneur que s'il est connu
    if [ -n "$DB_PASSWORD" ]; then
        PGPASS_ENV="-e PGPASSWORD=$DB_PASSWORD"
    else
        PGPASS_ENV=""
    fi
    cat > "$WRAPPER_DIR/psql" <<EOF
#!/usr/bin/env bash
ARGS=()
while [ \$# -gt 0 ]; do
  case "\$1" in
    -h|--host) shift 2 ;;
    -p|--port) shift 2 ;;
    *) ARGS+=("\$1"); shift ;;
  esac
done
exec $RUNTIME exec -i $PGPASS_ENV $CID psql "\${ARGS[@]}"
EOF
    chmod +x "$WRAPPER_DIR/psql" || die "impossible de creer le wrapper psql"
    export PATH="$WRAPPER_DIR:$PATH"
    # -w : jamais de invite interactive (le script ne doit pas se bloquer)
    PSQL=(psql -X -w -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME")
    info "transport : psql dans le conteneur (socket local)"
else
    command -v psql >/dev/null 2>&1 || die "psql est introuvable."
    export PGPASSWORD="$DB_PASSWORD"
    # -w : jamais de invite interactive (le script ne doit pas se bloquer)
    PSQL=(psql -X -w -v ON_ERROR_STOP=1 -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME")
    info "transport : psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME"
fi

# ===========================================================================
# Outils SQL
# ===========================================================================
sql_tsv()   { if [ -n "${REPORT_DEBUG:-}" ]; then "${PSQL[@]}" -A -t -c "$1"; else "${PSQL[@]}" -A -t -c "$1" 2>/dev/null; fi; }
sql_table() { if [ -n "${REPORT_DEBUG:-}" ]; then "${PSQL[@]}" -c "$1"; else "${PSQL[@]}" -c "$1" 2>/dev/null; fi; }

# Identifiant SQL (table, colonne, schema) : guillemets doubles.
lit() { printf '"%s"' "$(printf '%s' "$1" | sed 's/"/""/g')"; }
# Valeur SQL (comparaison a une chaine) : apostrophes.
sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"; }

declare -A PK_CACHE
declare -A COLS_CACHE

pk_of() {
    local key="$1|$2"
    if [ -n "${PK_CACHE[$key]+x}" ]; then
        printf '%s' "${PK_CACHE[$key]}"
        return 0
    fi
    local v
    v=$(sql_tsv "select a.attname from pg_index i
 join pg_class c on c.oid = i.indrelid
 join pg_namespace n on n.oid = c.relnamespace
 join pg_attribute a on a.attrelid = c.oid and a.attnum = any(i.indkey)
 where i.indisprimary and n.nspname = $(sq "$1") and c.relname = $(sq "$2")
 order by a.attnum limit 1")
    [ -n "$v" ] || v="ID"
    PK_CACHE[$key]="$v"
    printf '%s' "$v"
}

cols_of() {
    local key="$1|$2"
    if [ -n "${COLS_CACHE[$key]+x}" ]; then
        printf '%s' "${COLS_CACHE[$key]}"
        return 0
    fi
    local v
    v=$(sql_tsv "select column_name from information_schema.columns where table_schema = $(sq "$1") and table_name = $(sq "$2") order by ordinal_position" | tr '\n' ',')
    COLS_CACHE[$key]="$v"
    printf '%s' "$v"
}

table_exists() {
    local v
    v=$(sql_tsv "select count(*) from information_schema.tables where table_schema = $(sq "$1") and table_name = $(sq "$2")")
    [ "${v:-0}" -gt 0 ]
}

has_col() {
    case ",$(cols_of "$1" "$2")," in
        *,"$3",*) return 0 ;;
        *) return 1 ;;
    esac
}

# ===========================================================================
# Catalogue des tables lues par les panneaux du module.
#   TABLE | CHAIN | PANNEAUX
#   CHAIN : vide = la table porte elle-meme ID_AFFAIRE ;
#           sinon, liste "PARENT:CHAMP" du fils vers la mere, separee par
#           des virgules (ex. COMMANDE_CLIENT_ELEMENT:ID_COMMANDE_CLIENT).
# ===========================================================================
CATALOGUE='
DEVIS||liste.devis,historique.devis
COMMANDE_CLIENT||liste.commandes_clients,historique.commandes_clients,bilan.marche
CHIFFRAGE_COMMANDE_CLIENT|COMMANDE_CLIENT:ID_COMMANDE_CLIENT|historique.chiffrage,bilan.marche
SAISIE_VENTE_FACTURE||liste.saisie_vente_facture,historique.factures,bilan.facture
AVOIR_CLIENT||liste.avoirs_clients,historique.avoirs,bilan.facture
DEMANDE_ACHAT_ELEMENT||liste.demandes_achat,historique.demandes_achat
DEMANDE_PRIX||liste.demandes_prix,historique.demandes_prix
BON_DE_LIVRAISON||liste.bons_livraison,historique.bons_livraison
COMMANDE||liste.commandes_fournisseurs,historique.commandes_fournisseurs,bilan.commandes_fournisseurs
COMMANDE_ELEMENT|COMMANDE:ID_COMMANDE|historique.articles_commandes,bilan.commandes_fournisseurs
BON_RECEPTION||historique.bons_reception
BON_RECEPTION_ELEMENT|BON_RECEPTION:ID_BON_RECEPTION|historique.articles_receptionnes
SAISIE_ACHAT||liste.saisie_achat,historique.achats,bilan.achats
FACTURE_FOURNISSEUR||historique.factures_fournisseurs,bilan.achats
FACTURE_FOURNISSEUR_ELEMENT|FACTURE_FOURNISSEUR:ID_FACTURE_FOURNISSEUR|historique.factures_fournisseurs_elements,bilan.achats
AVOIR_FOURNISSEUR||liste.avoirs_fournisseurs,historique.avoirs_fournisseurs,bilan.achats
COMMANDE_CLIENT_ELEMENT|COMMANDE_CLIENT:ID_COMMANDE_CLIENT|onglet.commandes_en_cours
DEVIS_ELEMENT|DEVIS:ID_DEVIS|onglet.devis_en_attente
AFFAIRE_TEMPS|COMMANDE_CLIENT_ELEMENT:ID_COMMANDE_CLIENT_ELEMENT,COMMANDE_CLIENT:ID_COMMANDE_CLIENT|historique.temps
MOUVEMENT_STOCK||historique.stock
NOTE_DE_FRAIS_ELEMENT|NOTE_DE_FRAIS:ID_NOTE_DE_FRAIS|historique.notes_de_frais
POINTAGE_ELEMENT|POINTAGE:ID_POINTAGE|historique.pointage
'

# Tableau des totaux du bilan : libelle | SQL « comme le panneau » | SQL « table »
BILAN='
marche|select coalesce(sum(c."T_HT"),0) from %SCHEMA%."COMMANDE_CLIENT" c where c."ID_AFFAIRE" is not null and c."ID_AFFAIRE" <> 1 and exists (select 1 from %SCHEMA%."AFFAIRE" a where a."%AFF_PK%" = c."ID_AFFAIRE")|select coalesce(sum("T_HT"),0) from %SCHEMA%."COMMANDE_CLIENT"
budget|select coalesce(sum(h."T_PA_HT"),0) from %SCHEMA%."CHIFFRAGE_COMMANDE_CLIENT" h join %SCHEMA%."COMMANDE_CLIENT" c on c."%CC_PK%" = h."ID_COMMANDE_CLIENT" where c."ID_AFFAIRE" is not null and c."ID_AFFAIRE" <> 1 and exists (select 1 from %SCHEMA%."AFFAIRE" a where a."%AFF_PK%" = c."ID_AFFAIRE")|select coalesce(sum("T_PA_HT"),0) from %SCHEMA%."CHIFFRAGE_COMMANDE_CLIENT"
facture|select coalesce(sum(f."T_HT"),0) from %SCHEMA%."SAISIE_VENTE_FACTURE" f where f."ID_AFFAIRE" is not null and f."ID_AFFAIRE" <> 1 and exists (select 1 from %SCHEMA%."AFFAIRE" a where a."%AFF_PK%" = f."ID_AFFAIRE")|select coalesce(sum("T_HT"),0) from %SCHEMA%."SAISIE_VENTE_FACTURE"
avoirs_clients|select coalesce(sum(v."MONTANT_HT"),0) from %SCHEMA%."AVOIR_CLIENT" v where v."A_DEDUIRE" and v."ID_AFFAIRE" is not null and v."ID_AFFAIRE" <> 1 and exists (select 1 from %SCHEMA%."AFFAIRE" a where a."%AFF_PK%" = v."ID_AFFAIRE")|select coalesce(sum("MONTANT_HT"),0) from %SCHEMA%."AVOIR_CLIENT" where "A_DEDUIRE"
achats|select coalesce(sum(s."MONTANT_HT"),0) from %SCHEMA%."SAISIE_ACHAT" s where s."ID_AFFAIRE" is not null and s."ID_AFFAIRE" <> 1 and exists (select 1 from %SCHEMA%."AFFAIRE" a where a."%AFF_PK%" = s."ID_AFFAIRE")|select coalesce(sum("MONTANT_HT"),0) from %SCHEMA%."SAISIE_ACHAT"
factures_fournisseurs|select coalesce(sum(f."T_HT"),0) from %SCHEMA%."FACTURE_FOURNISSEUR" f where f."ID_AFFAIRE" is not null and f."ID_AFFAIRE" <> 1 and exists (select 1 from %SCHEMA%."AFFAIRE" a where a."%AFF_PK%" = f."ID_AFFAIRE")|select coalesce(sum("T_HT"),0) from %SCHEMA%."FACTURE_FOURNISSEUR"
articles_facture_fournisseur|select coalesce(sum(e."T_PA_HT"),0) from %SCHEMA%."FACTURE_FOURNISSEUR_ELEMENT" e join %SCHEMA%."FACTURE_FOURNISSEUR" f on f."%FF_PK%" = e."ID_FACTURE_FOURNISSEUR" where f."ID_AFFAIRE" is not null and f."ID_AFFAIRE" <> 1 and exists (select 1 from %SCHEMA%."AFFAIRE" a where a."%AFF_PK%" = f."ID_AFFAIRE")|select coalesce(sum("T_PA_HT"),0) from %SCHEMA%."FACTURE_FOURNISSEUR_ELEMENT"
avoirs_fournisseurs|select coalesce(sum(v."MONTANT_HT"),0) from %SCHEMA%."AVOIR_FOURNISSEUR" v where v."ID_AFFAIRE" is not null and v."ID_AFFAIRE" <> 1 and exists (select 1 from %SCHEMA%."AFFAIRE" a where a."%AFF_PK%" = v."ID_AFFAIRE")|select coalesce(sum("MONTANT_HT"),0) from %SCHEMA%."AVOIR_FOURNISSEUR"
commandes_fournisseurs|select coalesce(sum(c."T_HT"),0) from %SCHEMA%."COMMANDE" c where c."ID_AFFAIRE" is not null and c."ID_AFFAIRE" <> 1 and exists (select 1 from %SCHEMA%."AFFAIRE" a where a."%AFF_PK%" = c."ID_AFFAIRE")|select coalesce(sum("T_HT"),0) from %SCHEMA%."COMMANDE"
articles_commandes|select coalesce(sum(e."T_PA_HT"),0) from %SCHEMA%."COMMANDE_ELEMENT" e join %SCHEMA%."COMMANDE" c on c."%CMD_PK%" = e."ID_COMMANDE" where c."ID_AFFAIRE" is not null and c."ID_AFFAIRE" <> 1 and exists (select 1 from %SCHEMA%."AFFAIRE" a where a."%AFF_PK%" = c."ID_AFFAIRE")|select coalesce(sum("T_PA_HT"),0) from %SCHEMA%."COMMANDE_ELEMENT"
'

# ===========================================================================
# Schemas
# ===========================================================================
if [ -n "$SCHEMA" ]; then
    SCHEMAS="$SCHEMA"
else
    SCHEMAS=$(sql_tsv "select distinct table_schema from information_schema.tables where table_name = 'AFFAIRE' and table_schema not in ('pg_catalog','information_schema') order by 1")
fi
[ -n "$SCHEMAS" ] || die "aucun schema contenant une table AFFAIRE"

REPORT=$(mktemp) || die "impossible de creer le fichier de rapport"
OUT=${OUT:-rapport-lignes-manquantes-$(date +%Y%m%d-%H%M%S).txt}

{
printf '================================================================================\n'
printf 'RAPPORT DETAILLE : LIGNES NON AFFICHEES PAR LES PANNEAUX\n'
printf 'module  : org.openconcerto.modules.project (v1.1)\n'
printf 'base    : %s@%s:%s/%s\n' "$DB_USER" "$DB_HOST" "$DB_PORT" "$DB_NAME"
printf 'schemas : %s\n' "$(printf '%s' "$SCHEMAS" | tr '\n' ' ')"
printf 'genere  : %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
printf 'mode    : %s - LECTURE SEULE (aucune ecriture dans la base)\n' "$MODE"
printf '================================================================================\n'
printf '\n'
printf 'Chaque ligne invisible est listee ci-dessous avec sa cle primaire, son numero,\n'
printf 'sa date, son montant, son ID_AFFAIRE et, si elle en a une, sa mere.\n'
printf 'Motifs : SANS AFFAIRE | MERE SANS AFFAIRE | MERE ABSENTE | AFFAIRE INEXISTANTE\n'
printf '         | AFFAIRE TECHNIQUE (ligne « Indefini » du module)\n'
printf '         | SANS LIEN AVEC UNE AFFAIRE (table non rattachee a une affaire)\n'
} >> "$REPORT"

SUMMARY_ROWS=""
TOTAL_ALL=0

for schema in $SCHEMAS; do
    schema=$(printf '%s' "$schema" | tr -d '\r')
    [ -n "$schema" ] || continue
    if ! table_exists "$schema" "AFFAIRE"; then
        continue
    fi
    AFF_PK=$(pk_of "$schema" "AFFAIRE")
    CC_PK=$(pk_of "$schema" "COMMANDE_CLIENT")
    FF_PK=$(pk_of "$schema" "FACTURE_FOURNISSEUR")
    CMD_PK=$(pk_of "$schema" "COMMANDE")

    {
    printf '%s\n' '--------------------------------------------------------------------------------'
    printf 'SCHEMA %s\n' "$schema"
    printf '%s\n' '--------------------------------------------------------------------------------'
    } >> "$REPORT"

    SECTION=0
    while IFS='|' read -r table chain panels; do
        [ -n "$table" ] || continue
        table_exists "$schema" "$table" || continue

        # ---- jointures de la chaine de rattachement
        joins=""
        prev="t"
        n=0
        deepest=""
        deepest_pk=""
        deepest_has_aff=0
        IFS=',' read -r -a levels <<< "$chain"
        # une table qui porte elle-meme ID_AFFAIRE est traitee directement :
        # la chaine de la mere n'est alors pas necessaire.
        if has_col "$schema" "$table" "ID_AFFAIRE"; then
            levels=()
        fi
        for level in "${levels[@]}"; do
            [ -n "$level" ] || continue
            parent="${level%%:*}"
            field="${level##*:}"
            table_exists "$schema" "$parent" || continue
            ppk=$(pk_of "$schema" "$parent")
            n=$((n + 1))
            joins="$joins left join $(lit "$schema").$(lit "$parent") p$n on p$n.$(lit "$ppk") = $prev.$(lit "$field")"
            prev="p$n"
            deepest="p$n"
            deepest_pk="$ppk"
            if has_col "$schema" "$parent" "ID_AFFAIRE"; then
                deepest_has_aff=1
            fi
        done

        # ---- expression de l'affaire effective
        if [ -n "$deepest" ]; then
            if [ "$deepest_has_aff" -eq 1 ]; then
                aff_expr="$deepest.$(lit "ID_AFFAIRE")"
                aff_kind=child
            else
                aff_expr="null"
                aff_kind=none
            fi
        elif has_col "$schema" "$table" "ID_AFFAIRE"; then
            aff_expr="t.$(lit "ID_AFFAIRE")"
            aff_kind=direct
        else
            aff_expr="null"
            aff_kind=none
        fi

        # ---- categorie de chaque ligne
        if [ "$aff_kind" = child ]; then
            etat="case when $deepest.$(lit "$deepest_pk") is null then 'MERE ABSENTE'"
            etat="$etat when $aff_expr is null then 'MERE SANS AFFAIRE'"
        elif [ "$aff_kind" = direct ]; then
            etat="case when $aff_expr is null then 'SANS AFFAIRE'"
        else
            etat="case when true then 'SANS LIEN AVEC UNE AFFAIRE'"
        fi
        etat="$etat when $aff_expr = 1 then 'AFFAIRE TECHNIQUE'"
        etat="$etat when $aff_expr is not null and not exists (select 1 from $(lit "$schema").$(lit "AFFAIRE") aff where aff.$(lit "$AFF_PK") = $aff_expr) then 'AFFAIRE INEXISTANTE'"
        etat="$etat else 'OK' end"

        # ---- colonnes affichees
        sel="t.$(lit "$(pk_of "$schema" "$table")") as cle"
        has_col "$schema" "$table" "NUMERO" && sel="$sel, t.$(lit "NUMERO") as numero"
        has_col "$schema" "$table" "DATE" && sel="$sel, t.$(lit "DATE") as date"
        amount_expr=""
        for c in T_HT T_TTC T_PA_HT MONTANT_HT T_PV_HT; do
            if has_col "$schema" "$table" "$c"; then
                sel="$sel, t.$(lit "$c") as $c"
                [ -n "$amount_expr" ] || amount_expr="t.$(lit "$c")"
            fi
        done
        has_col "$schema" "$table" "ID_AFFAIRE" && sel="$sel, t.$(lit "ID_AFFAIRE") as id_affaire"
        if [ -n "$deepest" ]; then
            sel="$sel, $deepest.$(lit "$deepest_pk") as cle_mere"
        fi
        # colonnes de la mere (table mere = derniere de la chaine)
        if [ -n "$deepest" ]; then
            last_parent=""
            IFS=',' read -r -a levels <<< "$chain"
            for level in "${levels[@]}"; do
                [ -n "$level" ] || continue
                last_parent="${level%%:*}"
            done
            has_col "$schema" "$last_parent" "NUMERO" && sel="$sel, $deepest.$(lit "NUMERO") as numero_mere"
            has_col "$schema" "$last_parent" "ID_AFFAIRE" && sel="$sel, $deepest.$(lit "ID_AFFAIRE") as id_affaire_mere"
        fi
        sel="$sel, $etat as etat"

        from="from $(lit "$schema").$(lit "$table") t$joins"
        where="$etat <> 'OK'"

        # ---- requete de synthese
        if [ -n "$amount_expr" ]; then
            amount_sum="coalesce(sum(case when $etat <> 'OK' then $amount_expr end), 0)"
        else
            # pas de colonne de montant sur cette table
            amount_sum="0"
        fi
        agg=$(sql_tsv "select count(*) filter (where $etat = 'SANS AFFAIRE') as c_sans,
       count(*) filter (where $etat = 'MERE SANS AFFAIRE') as c_mere,
       count(*) filter (where $etat = 'MERE ABSENTE') as c_abs,
       count(*) filter (where $etat = 'AFFAIRE INEXISTANTE') as c_inex,
       count(*) filter (where $etat = 'AFFAIRE TECHNIQUE') as c_tech,
       count(*) filter (where $etat = 'SANS LIEN AVEC UNE AFFAIRE') as c_lien,
       count(*) filter (where $etat <> 'OK') as c_total,
       $amount_sum as c_montant
 from $(lit "$schema").$(lit "$table") t$joins")
        c_sans=$(printf '%s' "$agg" | cut -d'|' -f1)
        c_mere=$(printf '%s' "$agg" | cut -d'|' -f2)
        c_abs=$(printf '%s' "$agg" | cut -d'|' -f3)
        c_inex=$(printf '%s' "$agg" | cut -d'|' -f4)
        c_tech=$(printf '%s' "$agg" | cut -d'|' -f5)
        c_lien=$(printf '%s' "$agg" | cut -d'|' -f6)
        c_all=$(printf '%s' "$agg" | cut -d'|' -f7)
        c_montant=$(printf '%s' "$agg" | cut -d'|' -f8)
        c_sans=${c_sans:-0}; c_mere=${c_mere:-0}; c_abs=${c_abs:-0}
        c_inex=${c_inex:-0}; c_tech=${c_tech:-0}; c_lien=${c_lien:-0}
        c_all=${c_all:-0}; c_montant=${c_montant:-0}

        SUMMARY_ROWS="$SUMMARY_ROWS$table|$c_sans|$c_mere|$c_abs|$c_inex|$c_tech|$c_lien|$c_all|$c_montant|$panels
"

        if [ "${c_all:-0}" -eq 0 ]; then
            continue
        fi
        TOTAL_ALL=$((TOTAL_ALL + c_all))

        SECTION=$((SECTION + 1))
        {
        printf '\n### %d.%s  —  %s ligne(s) invisible(s)\n' "$SECTION" "$table" "$c_all"
        printf '    Panneaux concernes : %s\n' "$panels"
        case "$aff_kind" in
            direct) printf '    Colonne de rattachement : ID_AFFAIRE (directement sur la ligne)\n' ;;
            child)  printf '    Colonne de rattachement : ID_AFFAIRE de la table mere\n' ;;
            *)      printf '    Colonne de rattachement : aucune (table sans lien d affaires)\n' ;;
        esac
        } >> "$REPORT"

        limit_clause=""
        if [ "${LIMIT:-0}" -gt 0 ]; then
            limit_clause=" limit $LIMIT"
        fi
        detail=$(sql_table "select $sel $from where $where order by 1$limit_clause")
        if [ -n "$detail" ]; then
            printf '%s\n' "$detail" >> "$REPORT"
        else
            printf '    (aucune ligne)\n' >> "$REPORT"
        fi
    done <<EOF
$CATALOGUE
EOF
done

# ------------------------------------------------------------------ synthese
{
printf '\n================================================================================\n'
printf 'SYNTHESE\n'
printf '================================================================================\n'
printf '%-30s %9s %9s %9s %9s %9s %9s %9s %16s\n' "table" "sans_aff" "mere_sans" "mere_abs" "aff_inex" "aff_tech" "sans_lien" "total" "montant_cache"
printf '%s\n' '-----------------------------------------------------------------------------------------------'
} >> "$REPORT"

TOTAL_HIDDEN=0
while IFS='|' read -r table c_sans c_mere c_abs c_inex c_tech c_lien c_all c_montant panels; do
    [ -n "$table" ] || continue
    printf '%-30s %9s %9s %9s %9s %9s %9s %9s %16s\n' "$table" "$c_sans" "$c_mere" "$c_abs" "$c_inex" "$c_tech" "$c_lien" "$c_all" "$c_montant" >> "$REPORT"
    TOTAL_HIDDEN=$((TOTAL_HIDDEN + ${c_all:-0}))
done <<EOF
$SUMMARY_ROWS
EOF

{
printf '%s\n' '-----------------------------------------------------------------------------------------------'
printf 'TOTAL : %s ligne(s) invisible(s)\n' "$TOTAL_HIDDEN"
printf '\nLignes concernees (panneaux) :\n'
while IFS='|' read -r table c_sans c_mere c_abs c_inex c_tech c_lien c_all c_montant panels; do
    [ -n "$table" ] || continue
    [ "${c_all:-0}" -eq 0 ] && continue
    printf '  %-30s %s ligne(s)  [%s]\n' "$table" "$c_all" "$panels"
done <<EOF
$SUMMARY_ROWS
EOF
} >> "$REPORT"

# ------------------------------------------------------------------ bilan
for schema in $SCHEMAS; do
    schema=$(printf '%s' "$schema" | tr -d '\r')
    [ -n "$schema" ] || continue
    table_exists "$schema" "AFFAIRE" || continue
    AFF_PK=$(pk_of "$schema" "AFFAIRE")
    CC_PK=$(pk_of "$schema" "COMMANDE_CLIENT")
    FF_PK=$(pk_of "$schema" "FACTURE_FOURNISSEUR")
    CMD_PK=$(pk_of "$schema" "COMMANDE")
    {
    printf '\n================================================================================\n'
    printf 'ECARTS DE BILAN (schema %s)\n' "$schema"
    printf '================================================================================\n'
    printf 'Un ecart signifie que des montants existent en base mais ne sont affiches par\n'
    printf 'aucun panneau (les lignes non rattachees a une affaire).\n\n'
    printf '%-32s %18s %18s %18s\n' "total" "affiche (panneau)" "table" "ecart"
    printf '%s\n' '---------------------------------------------------------------------------------'
    } >> "$REPORT"
    while IFS='|' read -r label panel_sql total_sql; do
        [ -n "$label" ] || continue
        psql_panel=${panel_sql//%SCHEMA%/$(lit "$schema")}
        psql_panel=${psql_panel//%AFF_PK%/$AFF_PK}
        psql_panel=${psql_panel//%CC_PK%/$CC_PK}
        psql_panel=${psql_panel//%FF_PK%/$FF_PK}
        psql_panel=${psql_panel//%CMD_PK%/$CMD_PK}
        psql_total=${total_sql//%SCHEMA%/$(lit "$schema")}
        v_panel=$(sql_tsv "$psql_panel")
        v_total=$(sql_tsv "$psql_total")
        [ -n "$v_panel" ] || v_panel=0
        [ -n "$v_total" ] || v_total=0
        v_diff=$(sql_tsv "select coalesce(($v_total)::numeric - ($v_panel)::numeric, 0)")
        [ -n "$v_diff" ] || v_diff=0
        printf '%-32s %18s %18s %18s\n' "$label" "$v_panel" "$v_total" "$v_diff" >> "$REPORT"
    done <<EOF
$BILAN
EOF
done

# ------------------------------------------------------------------ conclusion
{
printf '\n================================================================================\n'
printf "CE QU'IL FAUT CORRIGER\n"
printf '================================================================================\n'
printf '1. Les lignes « SANS AFFAIRE » et « MERE SANS AFFAIRE » ont une colonne\n'
printf "   ID_AFFAIRE vide : elles n'apparaissent dans AUCUN onglet de l'historique\n"
printf "   d'une affaire et ne comptent pas dans le bilan. Il faut soit les rattacher\n"
printf "   a une affaire (UPDATE ... SET \"ID_AFFAIRE\" = <id>), soit les exclure\n"
printf '   explicitement si elles sont des lignes techniques.\n'
printf "2. Les lignes « MERE ABSENTE » pointent vers une ligne mere qui n'existe plus :\n"
printf '   la cle etrangere est cassee, les donnees sont incoherentes.\n'
printf '3. Les lignes « AFFAIRE INEXISTANTE » pointent vers une affaire supprimee :\n'
printf '   la cle etrangere est cassee elle aussi.\n'
printf "4. Les lignes « AFFAIRE TECHNIQUE » sont rattachees a l'affaire 1 (ligne\n"
printf "   « Indefini » du module) : elles sont exclues de l'historique par choix\n"
printf "   du module, ce n'est pas une anomalie.\n"
printf "5. Les lignes « SANS LIEN AVEC UNE AFFAIRE » appartiennent a une table\n"
printf "   qui n'est pas rattachee a une affaire (ni directement, ni par sa mere) :\n"
printf "   elles n'apparaissent dans aucun onglet d'historique. Il faut soit\n"
printf "   rattacher la table a une affaire, soit la retirer du perimetre du\n"
printf "   module.\n"
printf '\nRapport genere par scripts/rapport-lignes-manquantes.sh (lecture seule).\n'
} >> "$REPORT"

cp "$REPORT" "$OUT" 2>/dev/null || cp "$REPORT" "./$OUT"
rm -f "$REPORT"
[ -n "$WRAPPER_DIR" ] && rm -rf "$WRAPPER_DIR"

echo
echo "Rapport : $OUT"
echo "Lignes invisibles : $TOTAL_HIDDEN"
exit 0
