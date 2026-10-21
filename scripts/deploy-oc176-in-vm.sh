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
PURGE_X11=0
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
  --purge-x11     supprimer les bibliotheques X11 clientes (sans X ni bureau)
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
        --purge-x11)    PURGE_X11=1; shift ;;
        -h|--help) usage ;;
        *) die "option inconnue : $1" ;;
    esac
done

# Session SSH multiplexee : le mot de passe n'est demande qu'UNE fois,
# toutes les commandes suivantes reutilisent la meme connexion.
CONTROL_PATH="/tmp/oc176-ssh-%r@%h:%p"
KEY_FILE="$HOME/.ssh/id_ed25519_oc176"

SSH_OPTS=(-p "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=10
          -o ControlMaster=auto -o ControlPath="$CONTROL_PATH" -o ControlPersist=60)
if [ -f "$KEY_FILE" ]; then
    SSH_OPTS+=(-i "$KEY_FILE")
fi

# ssh dans la VM
vssh() { ssh "${SSH_OPTS[@]}" "${VM_USER}@${VM_HOST}" "$@"; }

# Ferme la session multiplexee a la fin (et en cas d'erreur).
close_session() {
    ssh -p "$VM_PORT" -o ControlPath="$CONTROL_PATH" -O exit \
        "${VM_USER}@${VM_HOST}" >/dev/null 2>&1 || true
}
trap close_session EXIT

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
# UNE seule invocation de sudo pour toute la chaine : sans cela, seul le
# premier « sudo -n » serait elveve, les suivants tourneraient en simple
# utilisateur (dpkg lock, systemctl, usermod...).
vsudo() {
    local quoted
    quoted=$(printf '%q' "$1")
    if [ "$SUDO_FLAG" = "-n" ]; then
        vssh "sudo -n sh -c $quoted"
    else
        vssh "printf '%s\n' '$VM_PASSWORD' | sudo -S sh -c $quoted"
    fi
}
# scp vers la VM
vscp() { scp -P "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
              -o LogLevel=ERROR -o ControlPath="$CONTROL_PATH" "$@"; }

# Le port est sonde AVANT toute connexion ssh : on ne demande le mot de
# passe que lorsque la VM ecoute vraiment.
port_ready() {
    (exec 3<>"/dev/tcp/$VM_HOST/$VM_PORT") 2>/dev/null || return 1
    exec 3<&- 2>/dev/null || true
    return 0
}

log "Attente de la VM (ssh -p $VM_PORT ${VM_USER}@$VM_HOST)"
ok=0
for _ in $(seq 1 30); do
    if port_ready; then
        if vssh true >/dev/null 2>&1; then
            ok=1
            break
        fi
    fi
    sleep 5
done
[ "$ok" = "1" ] || die "la VM ne repond pas sur le port $VM_PORT."

info "VM joignable : $(vssh 'hostname' 2>/dev/null || echo '?')"

# Cle SSH : creee au premier passage, puis installee dans la VM. Les
# executions suivantes n'affichent plus aucun mot de passe.
setup_key() {
    command -v ssh-keygen >/dev/null 2>&1 || return 1
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    if [ ! -f "$KEY_FILE" ]; then
        ssh-keygen -t ed25519 -N '' -f "$KEY_FILE" -C "openconcerto-1.7.6-vm" >/dev/null 2>&1 || return 1
        info "cle SSH creee : $KEY_FILE"
    fi
    [ -f "$KEY_FILE.pub" ] || return 1
    local pub
    pub=$(cat "$KEY_FILE.pub")
    if vssh "grep -qF '$pub' ~/.ssh/authorized_keys 2>/dev/null"; then
        info "cle SSH deja installee dans la VM"
        return 0
    fi
    info "installation de la cle SSH dans la VM"
    vssh "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && grep -qF '$pub' ~/.ssh/authorized_keys || echo '$pub' >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys" >/dev/null 2>&1 || true
    if vssh "grep -qF '$pub' ~/.ssh/authorized_keys 2>/dev/null"; then
        info "cle SSH installee : les prochains lancements ne demanderont plus de mot de passe"
    else
        info "cle SSH non installee (pas grave : le mot de passe sera demande une fois par lancement)"
    fi
}
setup_key

detect_sudo

# ------------------------------------------------------------------ purge
if [ "$PURGE_DESKTOP" = "1" ]; then
    log "Suppression des paquets de bureau et de LibreOffice"
    vsudo 'DEBIAN_FRONTEND=noninteractive apt-get purge -y "libreoffice*" "libreoffice-core" "gnome-desktop*" "task-*-desktop" "xfce*" "lxde*" "lxqt*" 2>/dev/null; DEBIAN_FRONTEND=noninteractive apt-get autoremove -y --purge; apt-get clean' || true
    info "purge terminé"
fi

if [ "$PURGE_X11" = "1" ]; then
    log "Suppression des bibliotheques X11 clientes"
    vsudo 'DEBIAN_FRONTEND=noninteractive apt-get purge -y libx11-6 libx11-data libxau6 libxcb1 libxdmcp6 libxext6 xauth xdg-user-dirs 2>/dev/null; DEBIAN_FRONTEND=noninteractive apt-get autoremove -y --purge' || true
    info "purge X11 terminé"
fi

# ------------------------------------------------------------------ docker
log "Installation de Docker dans la VM (sans recommends)"
vsudo 'DEBIAN_FRONTEND=noninteractive apt-get update -qq; DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker.io docker-cli || DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io || exit 1; DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker-compose-v2 || DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends docker-compose || true; systemctl enable --now docker; /usr/sbin/usermod -aG docker '"$VM_USER"' 2>/dev/null || true'

info "docker  : $(vssh 'docker --version' 2>/dev/null || echo '?')"
if ! vssh 'command -v docker' >/dev/null 2>&1; then
    info "diagnostic : $(vssh 'echo PATH=$PATH; ls -l /usr/bin/docker 2>&1; dpkg -l docker.io docker-cli 2>&1 | tail -3' 2>&1 | tr '\n' ' ')"
    die "l'installation de Docker a echoue dans la VM"
fi
info "compose : $(vssh 'docker compose version' 2>/dev/null || vssh 'docker-compose --version' 2>/dev/null || echo 'aucun')"

# ------------------------------------------------------------------ stack
# La stack est demarree avec le fichier d'override fr_FR : l'image postgres
# d'origine n'a pas la locale francaise, et la restauration cree la base
# avec « createdb -l fr_FR.UTF-8 » (collation de la base source).
compose() {
    vsudo "cd '$VM_DIR/docker/openconcerto-1.7.6' && docker compose -f docker-compose.yml -f docker-compose.fr_FR.yml $1"
}
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

# Mot de passe PostgreSQL : on CONSERVE celui deja ecrit dans le .env.
# Important : le conteneur postgres ne lit POSTGRES_PASSWORD qu'a la
# creation du volume ; changer la valeur ne change donc pas le mot de
# passe reel de la base. On ne regenere jamais un mot de passe existant.
ENV_FILE="$VM_DIR/docker/openconcerto-1.7.6/.env"
if [ -z "$PG_PASSWORD" ]; then
    PG_PASSWORD=$(vssh "sed -n 's/^POSTGRES_PASSWORD=//p' '$ENV_FILE' 2>/dev/null | head -1" 2>/dev/null | tr -d '\r\n')
fi
if [ -z "$PG_PASSWORD" ]; then
    PG_PASSWORD=$(vssh 'head -c 18 /dev/urandom | od -An -tx1 | tr -d " \n"' 2>/dev/null || echo "oc176secret")
    info "nouveau mot de passe PostgreSQL genere"
else
    info "mot de passe PostgreSQL existant conserve"
fi
vssh "printf '%s\n' 'POSTGRES_USER=openconcerto' 'POSTGRES_PASSWORD=$PG_PASSWORD' 'POSTGRES_DB=OpenConcerto' 'PG_HOST_PORT=5433' 'ADMINER_PORT=8082' > '$ENV_FILE'"
info "mot de passe PostgreSQL : $PG_PASSWORD"

# ------------------------------------------------------------------ démarrage
if [ "$NO_START" = "0" ]; then
    log "Démarrage de la stack (PostgreSQL + Adminer)"
    compose "up -d --build" || die "le démarrage de la stack a échoué"
    compose "ps" || true

    # Test reel de connexion : le mot de passe du .env n'est pris en compte
    # par postgres qu'a la creation du volume.
    log "Test de connexion a la base"
    db_ok=$(compose "exec -T db psql -U openconcerto -d OpenConcerto -tAc 'select 1'" 2>/dev/null | tr -d '\r\n ')
    if [ "$db_ok" = "1" ]; then
        info "connexion OK : base OpenConcerto accessible avec le mot de passe ci-dessus"
    else
        info "ATTENTION : connexion impossible avec ce mot de passe."
        info "  (le volume a peut-etre ete cree avec un autre mot de passe)"
        info "  test : ssh -p $VM_PORT $VM_USER@$VM_HOST \"cd $VM_DIR/docker/openconcerto-1.7.6 && docker compose -f docker-compose.yml -f docker-compose.fr_FR.yml exec db psql -U openconcerto -d OpenConcerto\""
    fi
fi

# ------------------------------------------------------------------ dump
if [ -n "$DUMP" ]; then
    [ -f "$DUMP" ] || die "dump introuvable : $DUMP"
    log "Transfert du dump dans la VM"
    vscp "$DUMP" "${VM_USER}@${VM_HOST}:$VM_DIR/dumps/"
    remote_dump="$VM_DIR/dumps/$(basename "$DUMP")"
    info "restauration de $remote_dump"
    info "installation du client PostgreSQL dans la VM"
    vsudo 'DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends postgresql-client' || true
    vssh "cd '$VM_DIR' && PGPASSWORD='$PG_PASSWORD' bash scripts/restore-openconcerto-dump.sh -f '$remote_dump' -d OpenConcerto -U openconcerto -h 127.0.0.1 -p 5433 -y" \
        || die "la restauration a échoué"
fi

# ------------------------------------------------------------------ controle
log "Contrôle : la VM ne contient que le strict nécessaire"
# grep -c renvoie 1 quand le compte est 0 : on neutralise pour garder le « 0 ».
nb_graph=$(vssh "dpkg -l 2>/dev/null | awk '/^ii/{print \$2}' | grep -c -E '^(libreoffice|task-.*-desktop|gnome-desktop|xfce|lxde|lxqt|cinnamon|mate|plasma|xserver-xorg|xinit|mesa-.*-drivers)' || true" 2>/dev/null | tr -d '\n')
nb_x11=$(vssh "dpkg -l 2>/dev/null | awk '/^ii/{print \$2}' | grep -c -E '^(libx11|libxcb|libxau|libxdmcp|libxext|libxkbcommon|xauth|xdg-user-dirs)' || true" 2>/dev/null | tr -d '\n')
if [ "${nb_graph:-0}" = "0" ]; then
    info "OK : aucun bureau, aucun environnement graphique, aucun LibreOffice dans la VM"
else
    info "ATTENTION : ${nb_graph} paquet(s) de bureau/graphique presents."
    info "  purge : bash deploy-oc176-in-vm.sh --purge-desktop"
fi
if [ "${nb_x11:-0}" != "0" ]; then
    info "${nb_x11} bibliotheque(s) X11 clientes (sans X, sans bureau) :"
    info "  purifiables (si aucune dependance) : bash deploy-oc176-in-vm.sh --purge-x11"
fi
info "paquets installes (hors base) :"
vssh "dpkg -l 2>/dev/null | awk '/^ii/{print \$2}' | tr '\n' ' '" | fold -s -w 78 | sed 's/^/  /' || true
info "images docker :"
vsudo "docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}'" 2>/dev/null | sed 's/^/  /' || true

log "Récapitulatif"
info "PostgreSQL : 127.0.0.1:5433 dans la VM (base OpenConcerto, role openconcerto)"
info "Adminer    : http://127.0.0.1:8082 dans la VM"
info "pour y acceder depuis l'hote :"
info "  ssh -p $VM_PORT -L 8082:127.0.0.1:8082 -L 5433:127.0.0.1:5433 ${VM_USER}@${VM_HOST}"
info "connexion  : ssh -p $VM_PORT ${VM_USER}@${VM_HOST}"
info "stack      : cd $VM_DIR/docker/openconcerto-1.7.6 && docker compose ps"
close_session
info "session SSH fermee"
