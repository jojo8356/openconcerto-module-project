#!/usr/bin/env bash
#
# Execute la suite de tests des panneaux du module project DANS la VM
# Debian (la ou PostgreSQL et psql sont disponibles), sans passer par le
# poste de l'utilisateur.
#
# La suite est en lecture seule : elle n'ecrit rien dans la base.
#
# Le script :
#   1. verifie l'acces SSH a la VM ;
#   2. prepare un JDK dans la VM : javac deja present, sinon apt si sudo
#      fonctionne, sinon un JDK extrait d'une image Docker (aucun droit
#      administrateur requis) ;
#   3. telecharge les sources de tests et le lanceur depuis GitHub ;
#   4. compile et execute la suite contre la base de la VM (127.0.0.1:5433).
#
# Usage :
#   bash scripts/panel-tests-in-vm.sh [options]
#
# Options :
#   --host HOTE      adresse de la VM  (defaut : 127.0.0.1)
#   --port PORT      port SSH de la VM (defaut : 2222)
#   --user UTIL      compte de la VM  (defaut : oc)
#   --password MDP   mot de passe du compte de la VM (defaut : oc)
#   --db BASE        base              (defaut : OpenConcerto)
#   --db-password MDP mot de passe PostgreSQL (defaut : lu dans le .env de la stack)
#   --schemas LIST   schemas a controler (defaut : tous ceux qui ont une table AFFAIRE)
#   --ref BRANCHE    branche GitHub    (defaut : arena/61954a71-openconcerto-module-project)
#   --jdk-image IMG  image JDK du mode sans root
#                    (defaut : docker.io/library/eclipse-temurin:17-jdk)
#   -h|--help        cette aide
#
set -euo pipefail

VM_HOST="127.0.0.1"
VM_PORT="2222"
VM_USER="oc"
VM_PASSWORD="oc"
DB_NAME="OpenConcerto"
DB_USER_SQL="openconcerto"
DB_PASSWORD=""
DB_PORT="5433"
SCHEMAS=""
GITHUB_REPO="jojo8356/openconcerto-module-project"
GITHUB_REF="arena/61954a71-openconcerto-module-project"
JDK_IMAGE="docker.io/library/eclipse-temurin:17-jdk"

PANEL_SOURCES=(
    SqlClient
    JdbcSqlClient
    PsqlSqlClient
    Db
    Panel
    PanelSql
    Catalogue
    Report
    Suite
    StructureSuite
    VisibilitySuite
    AggregateSuite
    RightsSuite
    TestRunner
)

usage() {
    sed -n '/^# Options/,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --host) VM_HOST="$2"; shift 2 ;;
        --port) VM_PORT="$2"; shift 2 ;;
        --user) VM_USER="$2"; shift 2 ;;
        --password) VM_PASSWORD="$2"; shift 2 ;;
        --db) DB_NAME="$2"; shift 2 ;;
        --db-password) DB_PASSWORD="$2"; shift 2 ;;
        --schemas) SCHEMAS="$2"; shift 2 ;;
        --ref) GITHUB_REF="$2"; shift 2 ;;
        --jdk-image) JDK_IMAGE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "option inconnue : $1" >&2; exit 1 ;;
    esac
done

VM_DIR="/home/$VM_USER/oc-176"
STACK_DIR="$VM_DIR/docker/openconcerto-1.7.6"
TEST_DIR="$VM_DIR/tests/org/openconcerto/modules/project/panels"
JDK_DIR="$VM_DIR/jdk"

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
warn() { printf '  ATTENTION : %s\n' "$*" >&2; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

command -v ssh >/dev/null 2>&1 || die "'ssh' introuvable."

CONTROL_PATH="/tmp/oc176-panels-ssh-%r@%h:%p"
KEY_FILE="$HOME/.ssh/id_ed25519_oc176"
SSH_OPTS=(-p "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=10
          -o ControlMaster=auto -o ControlPath="$CONTROL_PATH" -o ControlPersist=60)
if [ -f "$KEY_FILE" ]; then
    SSH_OPTS+=(-i "$KEY_FILE")
fi

vssh() { ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "$@"; }

# Execution avec privileges : sudo sans mot de passe (NOPASSWD), sinon sudo
# avec le mot de passe du compte, sinon echec (le script bascule alors sur une
# methode sans root).
vsudo() {
    local quoted
    quoted=$(printf '%q' "$1")
    if vssh "sudo -n sh -c $quoted" >/dev/null 2>&1; then
        return 0
    fi
    if [ -n "$VM_PASSWORD" ]; then
        if vssh "printf '%s\n' '$VM_PASSWORD' | sudo -S sh -c $quoted" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

log "Verification de l'acces a la VM ($VM_USER@$VM_HOST:$VM_PORT)"
vssh "true" || die "connexion SSH impossible sur $VM_HOST:$VM_PORT"

log "JDK dans la VM"
JAVA_HOME_IN_VM=""
if vssh "command -v javac >/dev/null 2>&1"; then
    info "javac deja present : $(vssh 'javac -version 2>&1 | head -1')"
elif vssh "test -x '$JDK_DIR/bin/javac'"; then
    info "JDK deja extrait : $JDK_DIR"
    JAVA_HOME_IN_VM="$JDK_DIR"
else
    info "tentative d'installation (default-jdk-headless) ..."
    if vsudo "DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends default-jdk-headless"; then
        info "JDK installe"
    else
        warn "sudo indisponible : on extrait un JDK de l'image $JDK_IMAGE (sans root)"
        vssh "docker pull -q '$JDK_IMAGE'" >/dev/null 2>&1 || die "image JDK inaccessible depuis la VM"
        vssh "cid=\$(docker create '$JDK_IMAGE') && docker cp \"\$cid:/opt/java/openjdk\" '$JDK_DIR' && docker rm -f \"\$cid\"" >/dev/null 2>&1 \
            || die "extraction du JDK impossible"
        vssh "test -x '$JDK_DIR/bin/javac'" || die "JDK incomplet dans $JDK_DIR"
        info "JDK extrait : $JDK_DIR"
        JAVA_HOME_IN_VM="$JDK_DIR"
    fi
fi

log "Telechargement des sources de tests dans la VM"
vssh "mkdir -p '$TEST_DIR' '$VM_DIR/scripts'" || die "creation des repertoires impossible"
for name in "${PANEL_SOURCES[@]}"; do
    if vssh "curl -fsSL -H 'Accept: application/vnd.github.raw' \
'https://api.github.com/repos/$GITHUB_REPO/contents/tests/org/openconcerto/modules/project/panels/$name.java?ref=$GITHUB_REF' \
-o '$TEST_DIR/$name.java'"; then
        info "telecharge : $name.java"
    else
        die "telechargement impossible : $name.java"
    fi
done
if vssh "curl -fsSL -H 'Accept: application/vnd.github.raw' \
'https://api.github.com/repos/$GITHUB_REPO/contents/scripts/run-panel-tests.sh?ref=$GITHUB_REF' \
-o '$VM_DIR/scripts/run-panel-tests.sh'"; then
    info "telecharge : run-panel-tests.sh"
else
    die "telechargement impossible : run-panel-tests.sh"
fi
vssh "chmod +x '$VM_DIR/scripts/run-panel-tests.sh'" || true

log "Mot de passe de la base"
if [ -z "$DB_PASSWORD" ]; then
    DB_PASSWORD=$(vssh "sed -n 's/^POSTGRES_PASSWORD=//p' '$STACK_DIR/.env' 2>/dev/null | head -1" 2>/dev/null | tr -d '\r\n')
fi
if [ -z "$DB_PASSWORD" ]; then
    DB_PASSWORD=$(vssh "docker exec \$(docker ps --format '{{.Names}}' | grep -E 'db' | head -1) printenv POSTGRES_PASSWORD 2>/dev/null" 2>/dev/null | tr -d '\r\n')
fi
[ -n "$DB_PASSWORD" ] || die "mot de passe PostgreSQL introuvable (utilisez --db-password)"
info "base : $DB_NAME / $DB_USER_SQL (mot de passe trouve)"

log "Execution de la suite dans la VM (lecture seule)"
SCHEMA_ARG=""
if [ -n "$SCHEMAS" ]; then
    SCHEMA_ARG="--schemas '$SCHEMAS'"
fi
JAVA_ARG=""
if [ -n "$JAVA_HOME_IN_VM" ]; then
    JAVA_ARG="export JAVA_HOME='$JAVA_HOME_IN_VM'; export PATH=\"\$JAVA_HOME/bin:\$PATH\";"
fi
set +e
vssh "cd '$VM_DIR' && $JAVA_ARG sh scripts/run-panel-tests.sh --host 127.0.0.1 --port $DB_PORT --db $DB_NAME --user $DB_USER_SQL --password '$DB_PASSWORD' $SCHEMA_ARG"
CODE=$?
set -e

echo
if [ "$CODE" -eq 0 ]; then
    echo "RESULTAT : la suite passe (aucune donnee cachee detectee)."
else
    echo "RESULTAT : la suite a detecte des problemes (code $CODE) : voir le detail ci-dessus."
fi
exit "$CODE"
