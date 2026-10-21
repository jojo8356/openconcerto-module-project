#!/usr/bin/env bash
#
# Bascule le client OpenConcerto 1.7.6 entre la base native et la copie Docker.
#
# BEGIN_UTILISE
# Pourquoi un script et pas l'assistant graphique ?
#   Dans OpenConcerto 1.7, le panneau "Configuration" (ServerFinderPanel) :
#     - n'expose aucun champ identifiant / mot de passe ;
#     - affiche "Base de données" dans un champ en lecture seule
#       (textBase.setEditable(false)) : il est rempli depuis la propriété
#       "systemRoot" du fichier de configuration existant, puis réinjecté
#       tel quel à l'enregistrement => l'assistant ne peut PAS changer de base ;
#     - son bouton "Tester la connexion" utilise toujours les identifiants
#       openconcerto / openconcerto (ServerFinderConfig.dbLogin / dbPassword,
#       jamais modifiés par l'interface).
#   D'où l'option -r : le rôle SQL du conteneur doit porter ce mot de passe.
#
# Usage :
#   ./switch-openconcerto-client-db.sh -t docker [-r] [-n] [-y]
#   ./switch-openconcerto-client-db.sh -t podman [-r] [-n] [-y]
#   ./switch-openconcerto-client-db.sh -t native [-n] [-y]
#   ./switch-openconcerto-client-db.sh -t remote -H IP[:PORT] [-n] [-y]
#
# Options :
#   -t CIBLE    docker | podman | native | remote
#   -H HOTE     hote du serveur distant (obligatoire avec -t remote),
#               avec ou sans port : 192.168.1.20  ou  192.168.1.20:5434
#   -r          conteneur (docker/podman) : aligner le mot de passe du rôle
#               SQL sur celui utilisé par le client (ALTER ROLE + .env)
#   -c FICHIER  main.properties (défaut : ~/.config/OpenConcerto/main.properties)
#   -p PORT     port de la cible (défaut : 5433 pour docker/podman, 5432 natif)
#   -d BASE     base de la cible (défaut : OpenConcerto pour docker/podman,
#               OpenConcertoKineticTherm pour native)
#   -U ROLE     rôle SQL (défaut : openconcerto)
#   -P MDP      mot de passe (défaut : openconcerto, la valeur par défaut
#               d'OpenConcerto)
#   -o DOSSIER  dossier de la stack (défaut : ~/oc-176-docker pour docker,
#               ~/oc-176-podman pour podman)
#   -n          dry-run : affiche le résultat, ne touche à rien
#   -y          pas de confirmation
#
# Variables : OC_CONF
# END_UTILISE

set -euo pipefail

TARGET=""
CONF="${OC_CONF:-$HOME/.config/OpenConcerto/main.properties}"
PORT=""
DB=""
SQL_USER="openconcerto"
SQL_PASSWORD="openconcerto"
STACK_DIR=""
ALIGN_ROLE=0
DRY=0
ASSUME_YES=0
REMOTE_HOST=""

usage() {
    awk '/^# BEGIN_UTILISE/{f=1;next} /^# END_UTILISE/{f=0} f' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while getopts ":t:rc:p:d:U:P:o:H:nyh" opt; do
    case "$opt" in
        t) TARGET="$OPTARG" ;;
        H) REMOTE_HOST="$OPTARG" ;;
        r) ALIGN_ROLE=1 ;;
        c) CONF="$OPTARG" ;;
        p) PORT="$OPTARG" ;;
        d) DB="$OPTARG" ;;
        U) SQL_USER="$OPTARG" ;;
        P) SQL_PASSWORD="$OPTARG" ;;
        o) STACK_DIR="$OPTARG" ;;
        n) DRY=1 ;;
        y) ASSUME_YES=1 ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

[ -n "$TARGET" ] || usage 1
case "$TARGET" in
    docker|podman|native|remote) ;;
    *) die "Cible inconnue : '$TARGET' (attendu : docker, podman, native ou remote)" ;;
esac

if [ "$TARGET" = "docker" ] || [ "$TARGET" = "podman" ] || [ "$TARGET" = "remote" ]; then
    PORT="${PORT:-5433}"
    DB="${DB:-OpenConcerto}"
else
    PORT="${PORT:-5432}"
    DB="${DB:-OpenConcertoKineticTherm}"
fi

# Le dossier de la stack dépend du runtime, sauf si -o a été fourni.
if [ -z "$STACK_DIR" ]; then
    if [ "$TARGET" = "podman" ]; then
        STACK_DIR="$HOME/oc-176-podman"
    else
        STACK_DIR="$HOME/oc-176-docker"
    fi
fi

[ -f "$CONF" ] || die "Fichier de configuration introuvable : $CONF"

get_prop() {
    sed -n "s/^$1=//p" "$CONF" | head -n 1
}

CURRENT_IP=$(get_prop "server.ip")
CURRENT_DB=$(get_prop "systemRoot")
CURRENT_DRIVER=$(get_prop "server.driver")
[ -n "$CURRENT_DRIVER" ] || CURRENT_DRIVER="postgresql"

# Le client range hôte et port dans une seule propriété, deux-points échappé
# (\:) — c'est le format écrit par OpenConcerto (Properties : "\:" -> ":").
# 127.0.0.1 et non "localhost" : le conteneur n'écoute que sur 127.0.0.1 et
# "localhost" peut résoudre en ::1 (IPv6), où rien n'écoute.
if [ "$TARGET" = "remote" ]; then
    [ -n "$REMOTE_HOST" ] || die "-t remote exige -H HOTE[:PORT] (adresse du serveur PostgreSQL)."
    [ "$ALIGN_ROLE" = "0" ] || die "-r n'a pas de sens avec -t remote (le rôle est sur l'autre machine)."
    case "$REMOTE_HOST" in
        *:*) NEW_IP=$(printf '%s' "$REMOTE_HOST" | sed 's/:/\\:/g') ;;
        *)   NEW_IP="${REMOTE_HOST}\\:$PORT" ;;
    esac
    # hote/port reellement testes par le controle de connexion
    CHK_HOST=$(printf '%s' "$REMOTE_HOST" | cut -d: -f1)
    case "$REMOTE_HOST" in
        *:*) CHK_PORT=$(printf '%s' "$REMOTE_HOST" | awk -F: '{print $NF}') ;;
        *)   CHK_PORT="$PORT" ;;
    esac
elif [ "$TARGET" = "docker" ] || [ "$TARGET" = "podman" ]; then
    NEW_IP="127.0.0.1\\:$PORT"
    CHK_HOST="127.0.0.1"
    CHK_PORT="$PORT"
else
    NEW_IP="localhost\\:$PORT"
    CHK_HOST="127.0.0.1"
    CHK_PORT="$PORT"
fi

log "Configuration actuelle"
printf '  fichier          : %s\n' "$CONF"
printf '  server.ip        : %s\n' "${CURRENT_IP:-<absent>}"
printf '  systemRoot       : %s\n' "${CURRENT_DB:-<absent>}"
printf '  server.driver    : %s\n' "$CURRENT_DRIVER"

log "Cible $TARGET"
printf '  server.ip        : %s\n' "$NEW_IP"
printf '  systemRoot       : %s\n' "$DB"
printf '  server.driver    : %s\n' "$CURRENT_DRIVER"
if [ "$TARGET" = "remote" ]; then
    printf '  server.login     : %s\n' "$SQL_USER"
    printf '  server.password  : %s\n' "<${#SQL_PASSWORD} caractères, masqué>"
    printf '  serveur distant  : %s (les identifiants sont écrits dans le fichier)\n' "$REMOTE_HOST"
elif [ "$TARGET" = "docker" ] || [ "$TARGET" = "podman" ]; then
    printf '  server.login     : %s\n' "$SQL_USER"
    printf '  server.password  : %s\n' "<${#SQL_PASSWORD} caractères, masqué>"
    if [ "$ALIGN_ROLE" = "1" ]; then
        printf '  rôle conteneur   : %s (mot de passe aligné sur le client)\n' "$SQL_USER"
    else
        printf '  rôle conteneur   : %s (mot de passe inchangé)\n' "$SQL_USER"
    fi
else
    printf '  server.login     : %s\n' "<retiré>"
    printf '  server.password  : %s\n' "<retiré>"
fi

if [ "$DRY" = "1" ]; then
    echo
    echo "Dry-run : rien n'a été modifié. Pour appliquer :"
    if [ "$TARGET" = "remote" ]; then
        printf '  bash %s -t remote -H %s\n' "$0" "$REMOTE_HOST"
    elif [ "$TARGET" != "native" ] && [ "$ALIGN_ROLE" = "1" ]; then
        printf '  bash %s -t %s -r\n' "$0" "$TARGET"
    else
        printf '  bash %s -t %s\n' "$0" "$TARGET"
    fi
    exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
    printf '\nAppliquer ? [o/N] '
    read -r answer
    case "$answer" in
        o|O|oui|OUI|y|Y) ;;
        *) echo "Annulé."; exit 0 ;;
    esac
fi

# ------------------------------------------------- alignement du rôle conteneur
if [ "$TARGET" != "native" ] && [ "$ALIGN_ROLE" = "1" ]; then
    log "Mot de passe du rôle '$SQL_USER' dans le conteneur"
    # Le socket local du conteneur est en 'trust' : ALTER ROLE ne demande pas
    # de mot de passe. On tente d'abord le socket, puis le port publié.
    # Les apostrophes du mot de passe sont doublées pour rester un littéral
    # SQL valide.
    SQL_PASSWORD_SQL="${SQL_PASSWORD//\'/\'\'}"
    ALTER_SQL="ALTER ROLE \"$SQL_USER\" WITH PASSWORD '$SQL_PASSWORD_SQL';"

    if [ "$TARGET" = "podman" ]; then
        COMPOSE_FILE="$STACK_DIR/compose.yaml"
        [ -f "$COMPOSE_FILE" ] || COMPOSE_FILE="$STACK_DIR/compose.yml"
        [ -f "$COMPOSE_FILE" ] || die "Fichier de composition introuvable : $STACK_DIR/compose.yaml"
        command -v podman >/dev/null 2>&1 || die "'podman' introuvable dans le PATH."
        if podman compose version >/dev/null 2>&1; then
            COMPOSE_CMD=(podman compose)
        elif command -v podman-compose >/dev/null 2>&1; then
            COMPOSE_CMD=(podman-compose)
        else
            die "Aucun fournisseur compose pour Podman : installe 'podman-compose'."
        fi
        DB_CID=$("${COMPOSE_CMD[@]}" -p openconcerto176 -f "$COMPOSE_FILE" ps -q db 2>/dev/null | head -n 1)
        [ -n "$DB_CID" ] || die "Conteneur PostgreSQL introuvable : la stack est-elle démarrée ?"
        ALTER_CMD=(podman exec -i "$DB_CID" psql -U "$SQL_USER" -d postgres -v ON_ERROR_STOP=1 -c "$ALTER_SQL")
    else
        COMPOSE="$STACK_DIR/docker-compose.yml"
        [ -f "$COMPOSE" ] || die "Fichier de composition introuvable : $COMPOSE"
        command -v docker >/dev/null 2>&1 || die "'docker' introuvable dans le PATH."
        ALTER_CMD=(docker compose -f "$COMPOSE" exec -T db psql -U "$SQL_USER" -d postgres -v ON_ERROR_STOP=1 -c "$ALTER_SQL")
    fi

    if ! "${ALTER_CMD[@]}"; then
        echo "  (socket direct impossible, nouvel essai via le port publié)"
        PGPASSWORD="$SQL_PASSWORD" psql -h 127.0.0.1 -p "$PORT" -U "$SQL_USER" \
            -d postgres -v ON_ERROR_STOP=1 -c "$ALTER_SQL" \
            || die "ALTER ROLE a échoué : le rôle '$SQL_USER' du conteneur n'a pas pu être aligné."
    fi
    echo "  rôle '$SQL_USER' : mot de passe aligné sur celui du client."

    # Le .env alimente POSTGRES_PASSWORD : il doit suivre, sinon les scripts
    # d'aide (copie, restauration) ne se connecteraient plus.
    # awk + ENVIRON : un mot de passe contenant &, / ou \ ne casse rien.
    if [ -f "$STACK_DIR/.env" ]; then
        cp -p "$STACK_DIR/.env" "$STACK_DIR/.env.bak-$(date +%Y-%m-%d_%H%M%S)"
        ENV_PW="$SQL_PASSWORD" awk '
            /^POSTGRES_PASSWORD=/ { print "POSTGRES_PASSWORD=" ENVIRON["ENV_PW"]; next }
            { print }
        ' "$STACK_DIR/.env" > "$STACK_DIR/.env.tmp"
        # On écrase le fichier d'origine (et non mv) pour conserver ses droits.
        cat "$STACK_DIR/.env.tmp" > "$STACK_DIR/.env"
        rm -f "$STACK_DIR/.env.tmp"
        echo "  .env : POSTGRES_PASSWORD aligné (sauvegarde à côté)."
    fi
fi

# ------------------------------------------------- écriture du main.properties
BACKUP="$CONF.bak-$(date +%Y-%m-%d_%H%M%S)"
cp -p "$CONF" "$BACKUP"
log "Sauvegarde : $BACKUP"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# On repart du fichier existant : les clés gérées sont remplacées à leur
# place, les autres lignes sont conservées telles quelles.
# ENVIRON est utilisé pour que le mot de passe ne soit pas réinterprété par awk.
SERVER_IP="$NEW_IP" SYSTEM_ROOT="$DB" SERVER_DRIVER="$CURRENT_DRIVER" \
SERVER_LOGIN="$SQL_USER" SERVER_PASSWORD="$SQL_PASSWORD" TARGET_KIND="$TARGET" \
awk '
    /^[[:space:]]*#/ { print; next }
    {
        eq = index($0, "=")
        if (eq == 0) { print; next }
        k = substr($0, 1, eq - 1)
        gsub(/[[:space:]]/, "", k)
        if (k == "server.ip") {
            if (!seen_ip) { print "server.ip=" ENVIRON["SERVER_IP"]; seen_ip = 1 }
            next
        }
        if (k == "systemRoot") {
            if (!seen_root) { print "systemRoot=" ENVIRON["SYSTEM_ROOT"]; seen_root = 1 }
            next
        }
        if (k == "server.driver") {
            if (!seen_drv) { print "server.driver=" ENVIRON["SERVER_DRIVER"]; seen_drv = 1 }
            next
        }
        if (k == "server.login") {
            if (ENVIRON["TARGET_KIND"] != "native" && !seen_log) {
                print "server.login=" ENVIRON["SERVER_LOGIN"]; seen_log = 1
            }
            next
        }
        if (k == "server.password") {
            if (ENVIRON["TARGET_KIND"] != "native" && !seen_pwd) {
                print "server.password=" ENVIRON["SERVER_PASSWORD"]; seen_pwd = 1
            }
            next
        }
        print
    }
    END {
        if (!seen_ip)   print "server.ip=" ENVIRON["SERVER_IP"]
        if (!seen_root) print "systemRoot=" ENVIRON["SYSTEM_ROOT"]
        if (!seen_drv)  print "server.driver=" ENVIRON["SERVER_DRIVER"]
        if (ENVIRON["TARGET_KIND"] != "native") {
            if (!seen_log) print "server.login=" ENVIRON["SERVER_LOGIN"]
            if (!seen_pwd) print "server.password=" ENVIRON["SERVER_PASSWORD"]
        }
    }
' "$CONF" > "$TMP"

cp "$TMP" "$CONF"

log "Fichier écrit"
grep -v '^[[:space:]]*server\.password=' "$CONF" | sed 's/^/  /'
if grep -q '^[[:space:]]*server\.password=' "$CONF"; then
    printf '  server.password  : %s\n' "<masqué, présent dans $CONF>"
fi

# ------------------------------------------------- contrôle de la connexion
if command -v psql >/dev/null 2>&1; then
    log "Contrôle de la connexion avec les identifiants du client"
    if OUT=$(PGPASSWORD="$SQL_PASSWORD" psql -h "$CHK_HOST" -p "$CHK_PORT" -U "$SQL_USER" \
                -d "$DB" -tAc "select current_user || '|' || current_database()" 2>&1); then
        echo "  OK : connexion réussie -> $OUT"
    else
        printf '  ECHEC : %s\n' "$OUT"
        if [ "$TARGET" = "podman" ]; then
            echo "  La cible est-elle démarrée (podman-openconcerto.sh up) ?"
        else
            echo "  La cible est-elle démarrée (docker compose up -d) ?"
        fi
        echo "  Le client OpenConcerto n'arrivera pas à se connecter non plus."
    fi
else
    echo
    echo "  (psql absent : contrôle de connexion non effectué)"
fi

if [ "$TARGET" = "remote" ]; then
    cat <<EOF

Prochaine étape :

  1. Redémarrer COMPLETEMENT le client (les droits et les métadonnées
     sont chargés à la connexion) :

       cd /opt/openconcerto && sh OpenConcerto.sh

     Le journal doit indiquer Ip:$REMOTE_HOST (base $DB).

  2. Se reconnecter avec le compte concerné, puis rejouer le transfert.
EOF
elif [ "$TARGET" = "docker" ] || [ "$TARGET" = "podman" ]; then
    cat <<EOF

Prochaine étape :

  1. Redémarrer le client et vérifier la ligne "Ip:" du journal :

       cd /opt/openconcerto && sh OpenConcerto.sh

     Le journal doit indiquer Ip:127.0.0.1:$PORT (base $DB).

  2. Revenir à la base native :

       bash $0 -t native
EOF
else
    cat <<EOF

Prochaine étape :

  1. Redémarrer le client :

       cd /opt/openconcerto && sh OpenConcerto.sh

  2. Revenir à la copie conteneur :

       bash $0 -t docker -r
EOF
fi
