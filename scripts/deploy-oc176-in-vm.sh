#!/usr/bin/env bash
#
# Déploie la stack OpenConcerto 1.7.6 (Docker) DANS la VM Debian.
#
# Le script est exécuté depuis l'hôte et pilote la VM par SSH (port
# redirigé). Dans la VM, il n'installe QUE le nécessaire :
#   - docker.io (+ plugin compose)
#   - la stack : PostgreSQL 17 + Adminer
# Aucun bureau, aucun LibreOffice, aucun autre logiciel.
#
#   bash deploy-oc176-in-vm.sh
#   bash deploy-oc176-in-vm.sh --dump /chemin/vers/base.dumpsql
#   bash deploy-oc176-in-vm.sh --purge-desktop
#
set -euo pipefail

VM_HOST="127.0.0.1"
VM_PORT="2222"
VM_USER="oc"
VM_PASSWORD="oc"
GITHUB_REPO="jojo8356/openconcerto-module-project"
GITHUB_REF="arena/61954a71-openconcerto-module-project"
VM_DIR="/home/$VM_USER/oc-176"
DUMP=""
NO_START=0
PURGE_DESKTOP=0
PG_PASSWORD=""

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'USAGE'
Déploie la stack OpenConcerto 1.7.6 (Docker) dans la VM Debian.

  --port PORT      port SSH de la VM (défaut : 2222)
  --host HOTE      adresse de la VM (défaut : 127.0.0.1)
  --user UTIL      compte de la VM (défaut : oc)
  --password MDE   mot de passe du compte (défaut : oc)
  --ref BRANCHE    branche GitHub de la stack
  --dump FICHIER   dump à restaurer dans le conteneur après démarrage
  --no-start       ne pas démarrer la stack
  --purge-desktop  supprimer les paquets de bureau et LibreOffice de la VM
USAGE
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --port)    VM_PORT="$2"; shift 2 ;;
        --host)    VM_HOST="$2"; shift 2 ;;
        --user)    VM_USER="$2"; shift 2 ;;
        --password) VM_PASSWORD="$2"; shift 2 ;;
        --ref)     GITHUB_REF="$2"; shift 2 ;;
        --dump)    DUMP="$2"; shift 2 ;;
        --no-start) NO_START=1; shift ;;
        --purge-desktop) PURGE_DESKTOP=1; shift ;;
        -h|--help) usage ;;
        *) die "option inconnue : $1" ;;
    esac
done

SSH_OPTS=(-p "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=10)

# ssh dans la VM
vssh() { ssh "${SSH_OPTS[@]}" "${VM_USER}@${VM_HOST}" "$@"; }

# sudo : sans mot de passe si possible, sinon avec celui du compte
SUDO_FLAG="-n"
detect_sudo() {
    if vssh 'sudo -n true' >/dev/null 2>&1; then
        SUDO_FLAG="-n"
    else
        SUDO_FLAG="-S"
        info "sudo sans mot de passe indisponible : le mot de passe du compte sera utilise"
    fi
}
vsudo() {
    if [ "$SUDO_FLAG" = "-n" ]; then
        vssh "sudo -n $1"
    else
        vssh "printf '%s\n' '$VM_PASSWORD' | sudo -S $1"
    fi
}
# scp vers la VM
vscp() { scp -P "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
              -o LogLevel=ERROR "$@"; }

log "Attente de la VM (ssh -p $VM_PORT ${VM_USER}@$VM_HOST)"
ok=0
for _ in $(seq 1 30); do
    if vssh true >/dev/null 2>&1; then
        ok=1
        break
    fi
    sleep 5
done
[ "$ok" = "1" ] || die "la VM ne repond pas sur le port $VM_PORT."

info "VM joignable : $(vssh 'hostname' 2>/dev/null || echo '?')"
detect_sudo

# ------------------------------------------------------------------ purge
if [ "$PURGE_DESKTOP" = "1" ]; then
    log "Suppression des paquets de bureau et de LibreOffice"
    vsudo 'DEBIAN_FRONTEND=noninteractive apt-get purge -y "libreoffice*" "libreoffice-core" "gnome-desktop*" "task-*-desktop" "xfce*" "lxde*" "lxqt*" 2>/dev/null; DEBIAN_FRONTEND=noninteractive apt-get autoremove -y --purge; apt-get clean' || true
    info "purge terminé"
fi

# ------------------------------------------------------------------ docker
log "Installation de Docker dans la VM (sans recommends)"
vsudo 'DEBIAN_FRONTEND=noninteractive apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker.io; DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker-compose-v2 || DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker-compose || true; systemctl enable --now docker; usermod -aG docker '"$VM_USER"

info "docker  : $(vssh 'docker --version' 2>/dev/null || echo '?')"
info "compose : $(vssh 'docker compose version' 2>/dev/null || vssh 'docker-compose --version' 2>/dev/null || echo 'aucun')"

# ------------------------------------------------------------------ stack
log "Copie de la stack dans la VM"
vssh "mkdir -p '$VM_DIR/docker/openconcerto-1.7.6' '$VM_DIR/dumps' '$VM_DIR/scripts'"

for f in docker/openconcerto-1.7.6/docker-compose.yml \
         docker/openconcerto-1.7.6/docker-compose.fr_FR.yml \
         docker/openconcerto-1.7.6/Dockerfile \
         scripts/restore-openconcerto-dump.sh \
         scripts/fix-facture-fournisseur-all-schemas.sh \
         scripts/diagnostic-transfert-fournisseur.sh \
         scripts/test-droits-utilisateur.sh; do
    if ! vssh "curl -fsSL -H 'Accept: application/vnd.github.raw' 'https://api.github.com/repos/$GITHUB_REPO/contents/$f?ref=$GITHUB_REF' -o '$VM_DIR/$f'" >/dev/null 2>&1; then
        die "téléchargement impossible : $f"
    fi
    info "téléchargé : $f"
done
vssh "chmod +x '$VM_DIR'/scripts/*.sh"

# Mot de passe PostgreSQL : généré s'il n'est pas fourni.
if [ -z "$PG_PASSWORD" ]; then
    PG_PASSWORD=$(vssh 'head -c 18 /dev/urandom | od -An -tx1 | tr -d " \n"' 2>/dev/null || echo "oc176secret")
fi
vssh "printf '%s\n' 'POSTGRES_USER=openconcerto' 'POSTGRES_PASSWORD=$PG_PASSWORD' 'POSTGRES_DB=OpenConcerto' 'PG_HOST_PORT=5433' 'ADMINER_PORT=8082' > '$VM_DIR/docker/openconcerto-1.7.6/.env'"
info "mot de passe PostgreSQL : $PG_PASSWORD"

# ------------------------------------------------------------------ démarrage
if [ "$NO_START" = "0" ]; then
    log "Démarrage de la stack (PostgreSQL + Adminer)"
    vssh "cd '$VM_DIR/docker/openconcerto-1.7.6' && docker compose up -d" \
        || die "le démarrage de la stack a échoué"
    vssh "cd '$VM_DIR/docker/openconcerto-1.7.6' && docker compose ps" || true
fi

# ------------------------------------------------------------------ dump
if [ -n "$DUMP" ]; then
    [ -f "$DUMP" ] || die "dump introuvable : $DUMP"
    log "Transfert du dump dans la VM"
    vscp "$DUMP" "${VM_USER}@${VM_HOST}:$VM_DIR/dumps/"
    remote_dump="$VM_DIR/dumps/$(basename "$DUMP")"
    info "restauration de $remote_dump"
    vssh "cd '$VM_DIR' && bash scripts/restore-openconcerto-dump.sh -f '$remote_dump' -d OpenConcerto -U openconcerto -h 127.0.0.1 -p 5433 -y" \
        || die "la restauration a échoué"
fi

# ------------------------------------------------------------------ controle
log "Contrôle : la VM ne contient que le strict nécessaire"
nb_paquets=$(vssh "dpkg -l 2>/dev/null | awk '/^ii/{print \$2}' | grep -c -E '^(libreoffice|task-.*-desktop|gnome-desktop|xfce|lxde|lxqt)'" 2>/dev/null || echo "?")
if [ "$nb_paquets" = "0" ]; then
    info "OK : aucun paquet de bureau ni LibreOffice dans la VM"
else
    info "ATTENTION : $nb_paquets paquet(s) de bureau/LibreOffice encore presents."
    info "  purge : bash deploy-oc176-in-vm.sh --purge-desktop"
fi
info "paquets installes (hors base) :"
vssh "dpkg -l 2>/dev/null | awk '/^ii/{print \$2}' | tr '\n' ' '" | fold -s -w 78 | sed 's/^/  /' || true
info "images docker :"
vssh "docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}'" 2>/dev/null | sed 's/^/  /' || true

log "Récapitulatif"
info "PostgreSQL : 127.0.0.1:5433 dans la VM (base OpenConcerto, role openconcerto)"
info "Adminer    : http://127.0.0.1:8082 dans la VM"
info "pour y acceder depuis l'hote :"
info "  ssh -p $VM_PORT -L 8082:127.0.0.1:8082 -L 5433:127.0.0.1:5433 ${VM_USER}@${VM_HOST}"
info "connexion  : ssh -p $VM_PORT ${VM_USER}@${VM_HOST}"
info "stack      : cd $VM_DIR/docker/openconcerto-1.7.6 && docker compose ps"
