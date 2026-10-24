#!/usr/bin/env bash
#
# OpenConcerto 1.7.6 sous Podman — SANS Docker.
#
# BEGIN_UTILISE
# Un seul script pour toute la chaîne, équivalent à ce qui est fait avec
# Docker, mais en n'utilisant que podman / podman-compose :
#
#   ./podman-openconcerto.sh up [--fr]         démarre la stack (PostgreSQL + Adminer)
#   ./podman-openconcerto.sh down [--volumes]  arrête la stack
#   ./podman-openconcerto.sh status            état des conteneurs
#   ./podman-openconcerto.sh logs [-f]         journaux
#   ./podman-openconcerto.sh copy               copie la base native dans le conteneur
#   ./podman-openconcerto.sh dump [fichier]     dump de la base du conteneur
#   ./podman-openconcerto.sh restore fichier    restauration d'un dump dans le conteneur
#   ./podman-openconcerto.sh client container  bascule le client vers la base du conteneur
#   ./podman-openconcerto.sh client native     revient à la base native
#   ./podman-openconcerto.sh sql "SELECT 1"    exécute du SQL dans le conteneur
#   ./podman-openconcerto.sh diagnose [args]   batterie de tests (droits + structure)
#   ./podman-openconcerto.sh help
#
# Options communes :
#   --dir DOSSIER   dossier de la stack (défaut : ~/oc-176-podman)
#   --port PORT     port publié de PostgreSQL (défaut : 5433)
#   --base BASE     base cible (défaut : OpenConcerto)
#   --user ROLE     rôle SQL (défaut : openconcerto)
#   --password MDP  mot de passe du rôle (défaut : lu dans .env)
#   --source BASE   base native source pour « copy » (défaut : OpenConcertoKineticTherm)
#   --fr            utilise l'image compilée avec la locale fr_FR.UTF-8
#   --no-role       ne pas aligner le mot de passe du rôle SQL sur celui du client
#   --no-root       fonctionne SANS droits administrateur : ni plage d'UID/GID
#                   secondaires (/etc/subuid) ni sudo ne sont nécessaires
#   --volumes       (down) supprime aussi les volumes de la stack
#   --dry-run       affiche les commandes, n'en exécute aucune
#   --yes           pas de confirmation
#
# Variables : PGPASSWORD
#
# Prérequis : podman (>= 4) et podman-compose, ou « podman compose ».
# Aucun paquet Docker n'est requis, et le binaire « docker » n'est jamais
# appelé.
# END_UTILISE

set -uo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

STACK_DIR="$HOME/oc-176-podman"
PROJECT="openconcerto176"
DB_PORT="5433"
PORT_SET=0
ADMINER_PORT="8082"
DB_NAME="OpenConcerto"
DB_USER="openconcerto"
DB_PASSWORD=""
SOURCE_DB="OpenConcertoKineticTherm"
USE_FR=0
ALIGN_ROLE=1
NO_ROOT=0
VOLUMES=0
DRY=0
ASSUME_YES=0
FOLLOW=0
COMMAND=""
COMPOSE=()
COMPOSE_FILES=()
NOROOT_CONTAINER="openconcerto176-db"
# Fichiers de plages d'UID/GID secondaires (surchargeables pour les tests)
SUBUID_FILE="${SUBUID_FILE:-/etc/subuid}"
SUBGID_FILE="${SUBGID_FILE:-/etc/subgid}"

# ------------------------------------------------------------------ utils
log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

run() {
    if [ "$DRY" = "1" ]; then
        printf '  [dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

confirm() {
    local question="$1" answer
    if [ "$ASSUME_YES" = "1" ]; then
        return 0
    fi
    printf '\n%s [o/N] ' "$question"
    read -r answer || answer=""
    case "$answer" in
        o|O|oui|OUI|y|Y) return 0 ;;
        *) echo "Annulé."; return 1 ;;
    esac
}

usage() {
    awk '/^# BEGIN_UTILISE/{f=1;next} /^# END_UTILISE/{f=0} f' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# ------------------------------------------------------------------ arguments
ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --dir)      STACK_DIR="$2"; shift 2 ;;
        --port)     DB_PORT="$2"; PORT_SET=1; shift 2 ;;
        --adminer-port) ADMINER_PORT="$2"; shift 2 ;;
        --base)     DB_NAME="$2"; shift 2 ;;
        --user)     DB_USER="$2"; shift 2 ;;
        --password) DB_PASSWORD="$2"; shift 2 ;;
        --source)   SOURCE_DB="$2"; shift 2 ;;
        --fr)       USE_FR=1; shift ;;
        --no-root)  NO_ROOT=1; shift ;;
        --volumes)  VOLUMES=1; shift ;;
        --no-role)  ALIGN_ROLE=0; shift ;;
        --dry-run)  DRY=1; shift ;;
        --yes|-y)   ASSUME_YES=1; shift ;;
        -f|--follow) FOLLOW=1; shift ;;
        -h|--help)  usage 0 ;;
        --)         shift; ARGS=("$@"); break ;;
        -*)         die "option inconnue : $1" ;;
        *)          ARGS+=("$1"); shift ;;
    esac
done

COMMAND="${ARGS[0]:-help}"
[ "${#ARGS[@]}" -gt 0 ] && shift_args=("${ARGS[@]:1}") || shift_args=()

# ------------------------------------------------------------------ environnement
need_podman() {
    command -v podman >/dev/null 2>&1 \
        || die "'podman' est introuvable dans le PATH. Installe Podman (paquet 'podman' sur Debian/Ubuntu, 'podman' sur Fedora)."
    if podman compose version >/dev/null 2>&1; then
        COMPOSE=(podman compose)
    elif command -v podman-compose >/dev/null 2>&1; then
        COMPOSE=(podman-compose)
    else
        die "Aucun fournisseur compose pour Podman : installe 'podman-compose' (apt install podman-compose)."
    fi
    COMPOSE_FILES=(-f "$STACK_DIR/compose.yaml")
    if [ "$USE_FR" = "1" ] && [ -f "$STACK_DIR/compose.fr_FR.yaml" ]; then
        COMPOSE_FILES+=(-f "$STACK_DIR/compose.fr_FR.yaml")
    fi
    if [ ! -f "$STACK_DIR/compose.yaml" ]; then
        die "Fichier de composition introuvable : $STACK_DIR/compose.yaml"
    fi
}

load_env() {
    if [ -z "$DB_PASSWORD" ] && [ -n "${PGPASSWORD:-}" ]; then
        DB_PASSWORD="$PGPASSWORD"
    fi
    if [ -z "$DB_PASSWORD" ] && [ -f "$STACK_DIR/.env" ]; then
        DB_PASSWORD=$(sed -n 's/^POSTGRES_PASSWORD=//p' "$STACK_DIR/.env" | head -n 1)
    fi
    # Le port publié fait foi : s'il est défini dans .env (PG_HOST_PORT), on
    # l'utilise, sauf si --port a été passé explicitement. C'est ce qui évite
    # que la stack Podman et la stack Docker se marchent dessus sur 5433.
    if [ "$PORT_SET" = "0" ] && [ -f "$STACK_DIR/.env" ]; then
        local env_port
        env_port=$(sed -n 's/^PG_HOST_PORT=//p' "$STACK_DIR/.env" | head -n 1)
        [ -n "$env_port" ] && DB_PORT="$env_port"
    fi
}

# Identifiant du conteneur PostgreSQL : on ne suppose rien du nommage
# (podman-compose a changé de convention), on demande au provider.
db_container() {
    local cid
    cid=$("${COMPOSE[@]}" -p "$PROJECT" "${COMPOSE_FILES[@]}" ps -q db 2>/dev/null | head -n 1)
    if [ -z "$cid" ]; then
        # Mode sans root : le conteneur n'est pas géré par compose.
        cid=$(podman ps -q --filter "name=^${NOROOT_CONTAINER}$" 2>/dev/null | head -n 1)
    fi
    [ -n "$cid" ] || die "Conteneur PostgreSQL introuvable. La stack est-elle démarrée ? (podman-openconcerto.sh up)"
    printf '%s' "$cid"
}

# psql dans le conteneur, en passant par podman exec : aucun port publié
# n'est nécessaire, et le rôle est déjà connu du serveur.
db_psql() {
    local cid
    cid=$(db_container)
    podman exec -i "$cid" psql -X -U "$DB_USER" "$@"
}

db_psql_at() {
    local cid
    cid=$(db_container)
    podman exec -i "$cid" psql -X -A -t -U "$DB_USER" "$@"
}

# ------------------------------------------------------------------ rootless
# En rootless, Podman a besoin d'une plage d'UID/GID secondaires
# (/etc/subuid, /etc/subgid) pour extraire les images : les fichiers
# appartenant à root:shadow (gid 42) n'ont sinon pas d'identifiant
# correspondant dans le namespace de l'utilisateur et l'extraction echoue :
#   "potentially insufficient UIDs or GIDs available in user namespace".
check_rootless_ids() {
    local user rootless subuid subgid
    user=$(id -un)
    rootless=$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null | tr -d '[:space:]')
    [ "$rootless" = "true" ] || return 0
    subuid=$(grep -E "^${user}:" "$SUBUID_FILE" 2>/dev/null | head -n 1)
    subgid=$(grep -E "^${user}:" "$SUBGID_FILE" 2>/dev/null | head -n 1)
    if [ -z "$subuid" ] || [ -z "$subgid" ]; then
        echo
        echo "  ERREUR : aucune plage d'UID/GID secondaires pour l'utilisateur '$user'."
        echo "  L'extraction des images échouera avec :"
        echo "    potentially insufficient UIDs or GIDs available in user namespace"
        echo
        echo "  Correctif (à faire une fois, avec les droits administrateur) :"
        echo
        echo "    sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $user"
        echo "    podman system migrate"
        echo
        echo "  Si 'usermod' ne connaît pas --add-subuids (shadow ancien), éditer à la main :"
        echo
        echo "    sudo tee -a /etc/subuid >/dev/null <<EOF"
        echo "    $user:100000:65536"
        echo "    EOF"
        echo "    sudo tee -a /etc/subgid >/dev/null <<EOF"
        echo "    $user:100000:65536"
        echo "    EOF"
        echo "    podman system migrate"
        echo
        return 1
    fi
    info "plage d'UID/GID secondaires : $subuid"
    return 0
}

# ------------------------------------------------------------------ sans root
# Sur une machine où l'utilisateur n'a pas de plage d'UID/GID secondaires
# (/etc/subuid), l'extraction des images échoue sur les fichiers root:shadow.
# containers-storage sait ignorer ces erreurs : il suffit de l'activer pour
# son propre utilisateur, dans ~/.config/containers/storage.conf.
prepare_storage_conf() {
    local conf="$HOME/.config/containers/storage.conf"
    mkdir -p "$HOME/.config/containers" || return 1
    if [ -f "$conf" ] && grep -q "ignore_chown_errors" "$conf"; then
        info "storage.conf : ignore_chown_errors déjà activé"
        return 0
    fi
    if [ -f "$conf" ] && grep -q "^\[storage\.options\]" "$conf"; then
        awk '/^\[storage\.options\]/{print; if(!d){print "ignore_chown_errors = \"true\""; d=1} next} {print}' \
            "$conf" > "$conf.tmp" && mv "$conf.tmp" "$conf"
    else
        {
            echo
            echo "[storage.options]"
            echo "ignore_chown_errors = \"true\""
        } >> "$conf"
    fi
    # Podman avertit si le pilote de stockage n'est pas explicite : on l'écrit,
    # sinon chaque commande affiche le WARN.
    if ! grep -q "^\[storage\]" "$conf"; then
        {
            echo
            echo "[storage]"
            echo "driver = \"overlay\""
        } > "$conf.storage.tmp"
        cat "$conf" >> "$conf.storage.tmp"
        mv "$conf.storage.tmp" "$conf"
    fi
    info "storage.conf : ignore_chown_errors activé ($conf)"
}

# Démarrage sans compose et sans root : le conteneur tourne avec
# --userns=keep-id, donc le processus PostgreSQL s'exécute avec l'UID de
# l'utilisateur (le seul mappable faute de plage secondaire) et le répertoire
# de données est un dossier de l'hôte, déjà possédé par l'utilisateur.
cmd_up_noroot() {
    log "Démarrage de PostgreSQL (mode sans root)"
    if [ "$DRY" = "1" ]; then
        echo "  [dry-run] activation de ignore_chown_errors dans $HOME/.config/containers/storage.conf"
    else
        prepare_storage_conf
    fi
    mkdir -p "$STACK_DIR/pgdata"
    if podman ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$NOROOT_CONTAINER"; then
        info "suppression du conteneur précédent (les données sont dans $STACK_DIR/pgdata)"
        run podman rm -f "$NOROOT_CONTAINER"
    fi
    local image="docker.io/library/postgres:17-bookworm"
    if [ "$USE_FR" = "1" ]; then
        if [ "$DRY" != "1" ]; then
            podman build -t openconcerto176-db-fr -f "$STACK_DIR/Containerfile" "$STACK_DIR" >/dev/null
        else
            printf '  [dry-run] podman build -t openconcerto176-db-fr -f %s %s\n' "$STACK_DIR/Containerfile" "$STACK_DIR"
        fi
        image="openconcerto176-db-fr"
    fi
    local out rc=0
    if [ "$DRY" = "1" ]; then
        out=$(podman run -d --name "$NOROOT_CONTAINER" \
        --userns=keep-id --user "$(id -u):$(id -g)" \
        -e POSTGRES_USER="$DB_USER" \
        -e POSTGRES_PASSWORD="$DB_PASSWORD" \
        -e POSTGRES_DB="$DB_NAME" \
        -e POSTGRES_INITDB_ARGS="--encoding=UTF8" \
        -p "127.0.0.1:$DB_PORT:5432" \
        -v "$STACK_DIR/pgdata:/var/lib/postgresql/data" \
        "$image" postgres -c unix_socket_directories=/tmp 2>&1) || rc=$?
        printf '  [dry-run] podman run -d --name %s --userns=keep-id --user %s:%s ... %s postgres -c unix_socket_directories=/tmp\n' \
            "$NOROOT_CONTAINER" "$(id -u)" "$(id -g)" "$image"
        return 0
    fi
    out=$(podman run -d --name "$NOROOT_CONTAINER" \
        --userns=keep-id --user "$(id -u):$(id -g)" \
        -e POSTGRES_USER="$DB_USER" \
        -e POSTGRES_PASSWORD="$DB_PASSWORD" \
        -e POSTGRES_DB="$DB_NAME" \
        -e POSTGRES_INITDB_ARGS="--encoding=UTF8" \
        -p "127.0.0.1:$DB_PORT:5432" \
        -v "$STACK_DIR/pgdata:/var/lib/postgresql/data" \
        "$image" postgres -c unix_socket_directories=/tmp 2>&1) || rc=$?
    printf '%s\n' "$out"
    if printf '%s' "$out" | grep -q "ID-mapped copy"; then
        echo
        echo "  ERREUR : Podman rootless doit creer une copie ID-mappee de l'image"
        echo "  (les fichiers de l'image appartiennent a des UID/GID non mappables)."
        echo "  Sans plage d'UID/GID secondaires dans /etc/subuid, cette copie est"
        echo "  impossible : le mode --no-root ne peut pas aller plus loin."
        echo
        echo "  Solution : faire ajouter la plage par l'administrateur du poste :"
        echo
        echo "    sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $(id -un)"
        echo "    podman system migrate"
        echo
        echo "  En attendant, les tests (droits, structure) peuvent etre lances"
        echo "  directement sur la base native, sans conteneur."
        return 1
    fi
    [ "$rc" = "0" ] || return "$rc"
    log "Attente de PostgreSQL"
    local cid i=0
    cid=$(db_container)
    while [ "$i" -lt 120 ]; do
        if podman exec "$cid" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
            info "base '$DB_NAME' prête."
            break
        fi
        i=$((i + 1))
        sleep 1
    done
    [ "$i" -lt 120 ] || die "PostgreSQL ne répond pas après 120 s. Voir : podman logs $NOROOT_CONTAINER"
    echo
    info "PostgreSQL : 127.0.0.1:$DB_PORT (base $DB_NAME, rôle $DB_USER)"
    info "données     : $STACK_DIR/pgdata"
}

# ------------------------------------------------------------------ commandes

cmd_up() {
    need_podman
    load_env
    log "Démarrage de la stack Podman ($PROJECT)"
    if [ "$USE_FR" = "1" ]; then
        info "image avec locale fr_FR.UTF-8 : compilation du Containerfile"
        run podman build -t openconcerto176-db-fr -f "$STACK_DIR/Containerfile" "$STACK_DIR"
    fi
    if [ "$NO_ROOT" = "1" ]; then
        cmd_up_noroot
        return $?
    fi
    if [ "$DRY" != "1" ]; then
        check_rootless_ids || die "Plage d'UID/GID secondaires manquante : corrige-la puis relance, ou utilise « up --no-root »."
    fi
    if [ "$DRY" = "1" ]; then
        run "${COMPOSE[@]}" -p "$PROJECT" "${COMPOSE_FILES[@]}" up -d
        echo "  (dry-run : pas d'attente de la base)"
        return 0
    fi
    local out rc=0
    out=$("${COMPOSE[@]}" -p "$PROJECT" "${COMPOSE_FILES[@]}" up -d 2>&1) || rc=$?
    printf '%s\n' "$out"
    if printf '%s' "$out" | grep -q "insufficient UIDs or GIDs"; then
        echo
        echo "  ERREUR : Podman rootless n'a pas assez d'UID/GID secondaires pour"
        echo "  extraire les images (fichiers root:shadow dans l'image)."
        echo "  Correctif :"
        echo
        echo "    sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $(id -un)"
        echo "    podman system migrate"
        echo
        echo "  (ou, pour le conteneur seul, ajouter 'ignore_chown_errors = \"true\"'"
        echo "   dans [storage.options] de ~/.config/containers/storage.conf)"
        return 1
    fi
    [ "$rc" = "0" ] || return "$rc"
    log "Attente de PostgreSQL"
    local cid i=0
    cid=$(db_container)
    while [ "$i" -lt 90 ]; do
        if podman exec "$cid" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; then
            info "base '$DB_NAME' prête."
            break
        fi
        i=$((i + 1))
        sleep 1
    done
    [ "$i" -lt 90 ] || die "PostgreSQL ne répond pas après 90 s."
    echo
    info "PostgreSQL : 127.0.0.1:$DB_PORT (base $DB_NAME, rôle $DB_USER)"
    info "Adminer    : http://127.0.0.1:$ADMINER_PORT"
}

cmd_down() {
    need_podman
    log "Arrêt de la stack Podman"
    if [ "$VOLUMES" = "1" ]; then
        info "les volumes sont supprimés : les données de la stack sont perdues"
        if [ "$DRY" != "1" ]; then
            confirm "Supprimer aussi les volumes ?" || exit 0
        fi
        run "${COMPOSE[@]}" -p "$PROJECT" "${COMPOSE_FILES[@]}" down -v
    else
        run "${COMPOSE[@]}" -p "$PROJECT" "${COMPOSE_FILES[@]}" down
    fi
    if podman ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$NOROOT_CONTAINER"; then
        run podman rm -f "$NOROOT_CONTAINER"
    fi
}

cmd_status() {
    need_podman
    load_env
    log "État de la stack ($PROJECT)"
    "${COMPOSE[@]}" -p "$PROJECT" "${COMPOSE_FILES[@]}" ps
    echo
    info "port publié PostgreSQL : 127.0.0.1:$DB_PORT"
    info "port publié Adminer    : 127.0.0.1:$ADMINER_PORT"
    if podman ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$NOROOT_CONTAINER"; then
        info "conteneur (mode sans root) : $NOROOT_CONTAINER"
    fi
}

cmd_logs() {
    need_podman
    local extra=()
    [ "$FOLLOW" = "1" ] && extra=(-f)
    "${COMPOSE[@]}" -p "$PROJECT" "${COMPOSE_FILES[@]}" logs "${extra[@]}"
}

cmd_sql() {
    need_podman
    local sql="${shift_args[0]:-}"
    [ -n "$sql" ] || die "Précise la requête : podman-openconcerto.sh sql \"SELECT 1\""
    db_psql -d "$DB_NAME" -c "$sql"
}

# --- copie de la base native dans le conteneur -------------------------
cmd_copy() {
    need_podman
    load_env
    local restore="$SCRIPT_DIR/restore-openconcerto-dump.sh"
    local fixschemas="$SCRIPT_DIR/fix-facture-fournisseur-all-schemas.sh"
    [ -f "$restore" ] || die "Script absent : $restore"
    [ -f "$fixschemas" ] || die "Script absent : $fixschemas"

    local stamp dump_name dump
    stamp=$(date +%Y%m%d_%H%M)
    dump_name="${SOURCE_DB}_${stamp}.dumpsql"
    dump="$STACK_DIR/dumps/$dump_name"

    log "Collation de la base source"
    local src_collate
    if [ "$DRY" != "1" ]; then
        command -v sudo >/dev/null 2>&1 || die "'sudo' est introuvable dans le PATH."
        command -v pg_dump >/dev/null 2>&1 || die "'pg_dump' est introuvable dans le PATH."
    fi
    src_collate=$(sudo -u postgres psql -d "$SOURCE_DB" -tAc \
        "SELECT datcollate FROM pg_database WHERE datname = '$SOURCE_DB'") \
        || die "Base source illisible : '$SOURCE_DB' (serveur natif)."
    [ -n "$src_collate" ] || die "La base source '$SOURCE_DB' n'existe pas sur le serveur natif."
    info "source : $SOURCE_DB ($src_collate)"

    echo
    info "cible  : $DB_NAME (conteneur Podman, 127.0.0.1:$DB_PORT)"
    info "dump   : $dump"
    info "la base '$DB_NAME' du conteneur sera SUPPRIMÉE puis recréée"

    if [ "$DRY" = "1" ]; then
        echo
        echo "Plan en dry-run :"
        run sudo -u postgres pg_dump -Fc --no-owner --no-privileges -d "$SOURCE_DB" -f "/tmp/$dump_name"
        run mkdir -p "$STACK_DIR/dumps"
        run sudo mv "/tmp/$dump_name" "$STACK_DIR/dumps/"
        run bash "$restore" -f "$dump" -d "$DB_NAME" -U "$DB_USER" -h 127.0.0.1 -p "$DB_PORT" -y
        run bash "$fixschemas" -d "$DB_NAME" -y
        echo
        echo "Dry-run : rien n'a été modifié."
        return 0
    fi

    confirm "Continuer ?" || exit 0

    log "Dump de la base native"
    run sudo -u postgres pg_dump -Fc --no-owner --no-privileges -d "$SOURCE_DB" -f "/tmp/$dump_name"
    [ -s "/tmp/$dump_name" ] || die "Dump vide ou absent : /tmp/$dump_name"
    run mkdir -p "$STACK_DIR/dumps"
    run sudo mv "/tmp/$dump_name" "$STACK_DIR/dumps/"
    run sudo chown "$(id -un):" "$dump"
    [ -s "$dump" ] || die "Dump introuvable après déplacement : $dump"

    log "Restauration dans le conteneur Podman"
    LOCALE="$src_collate" run bash "$restore" -f "$dump" -d "$DB_NAME" \
        -U "$DB_USER" -h 127.0.0.1 -p "$DB_PORT" -y

    log "Correctif multi-schémas (ID_COMMANDE_ELEMENT)"
    local cid
    cid=$(db_container)
    PSQL_CMD="podman exec -i $cid psql -U $DB_USER" \
        run bash "$fixschemas" -d "$DB_NAME" -y

    log "Contrôle"
    info "colonne ID_COMMANDE_ELEMENT par schéma :"
    db_psql_at -d "$DB_NAME" -c \
        "SELECT table_schema || ' | ' || bool_or(column_name = 'ID_COMMANDE_ELEMENT')
           FROM information_schema.columns
          WHERE table_name = 'FACTURE_FOURNISSEUR_ELEMENT'
          GROUP BY 1 ORDER BY 1" | sed 's/^/    /'

    echo
    echo "Terminé. Dump conservé dans $dump"
    echo "Pour brancher le client : podman-openconcerto.sh client container"
}

# --- dump de la base du conteneur ---------------------------------------
cmd_dump() {
    need_podman
    local out="${shift_args[0]:-$STACK_DIR/dumps/$(date +%Y%m%d_%H%M)-${DB_NAME}.dumpsql}"
    local cid
    cid=$(db_container)
    log "Dump de la base '$DB_NAME' (conteneur Podman)"
    if [ "$DRY" = "1" ]; then
        printf '  [dry-run] podman exec %s pg_dump -U %s -Fc --no-owner --no-privileges -d %s > %s\n' \
            "$cid" "$DB_USER" "$DB_NAME" "$out"
        return 0
    fi
    mkdir -p "$(dirname "$out")"
    podman exec "$cid" pg_dump -U "$DB_USER" -Fc --no-owner --no-privileges -d "$DB_NAME" > "$out"
    [ -s "$out" ] || die "Dump vide : $out"
    info "dump : $out"
}

# --- restauration d'un dump dans le conteneur ----------------------------
cmd_restore() {
    local dump="${shift_args[0]:-}"
    [ -n "$dump" ] || die "Précise le dump : podman-openconcerto.sh restore fichier.dumpsql"
    need_podman
    local restore="$SCRIPT_DIR/restore-openconcerto-dump.sh"
    [ -f "$restore" ] || die "Script absent : $restore"
    log "Restauration de $dump dans '$DB_NAME'"
    run bash "$restore" -f "$dump" -d "$DB_NAME" -U "$DB_USER" -h 127.0.0.1 -p "$DB_PORT" -y
}

# --- bascule du client --------------------------------------------------
cmd_client() {
    local target="${shift_args[0]:-container}"
    local switch="$SCRIPT_DIR/switch-openconcerto-client-db.sh"
    load_env
    [ -f "$switch" ] || die "Script absent : $switch (télécharge-le dans le même dossier)."
    local dryopt=""
    [ "$DRY" = "1" ] && dryopt="-n"
    local roleopt=""
    [ "$ALIGN_ROLE" = "1" ] && roleopt="-r"
    case "$target" in
        container|podman)
            run bash "$switch" -t podman -o "$STACK_DIR" -p "$DB_PORT" -d "$DB_NAME" -U "$DB_USER" $roleopt $dryopt
            ;;
        native)
            run bash "$switch" -t native $dryopt
            ;;
        *) die "Cible inconnue : '$target' (attendu : container ou native)" ;;
    esac
}

# --- batterie de tests --------------------------------------------------
cmd_diagnose() {
    local script="$SCRIPT_DIR/diagnostic-transfert-fournisseur.sh"
    [ -f "$script" ] || die "Script absent : $script (télécharge-le dans le même dossier)."
    need_podman
    load_env
    local extra=()
    [ -n "$DB_PASSWORD" ] && extra=(-P "$DB_PASSWORD")
    # Le correctif de structure doit viser le conteneur : on le dit explicitement.
    local dryopt=""
    [ "$DRY" = "1" ] && dryopt="-n"
    if [ "$DRY" != "1" ]; then
        local cid
        cid=$(db_container)
        export PSQL_CMD="podman exec -i $cid psql -U $DB_USER"
    fi
    run bash "$script" -1 erp -2 abe -b "$DB_NAME" -H 127.0.0.1 -p "$DB_PORT" \
         -U "$DB_USER" "${extra[@]}" $dryopt "${shift_args[@]}"
}

# ------------------------------------------------------------------ dispatch
case "$COMMAND" in
    up)       cmd_up ;;
    down)     cmd_down "${shift_args[@]}" ;;
    status)   cmd_status ;;
    logs)     cmd_logs ;;
    sql)      cmd_sql ;;
    copy)     cmd_copy ;;
    dump)     cmd_dump ;;
    restore)  cmd_restore ;;
    client)   cmd_client ;;
    diagnose) cmd_diagnose ;;
    help|-h|--help) usage 0 ;;
    *) die "Commande inconnue : '$COMMAND' (voir « $0 help »)" ;;
esac
