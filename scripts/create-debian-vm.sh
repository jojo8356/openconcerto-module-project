#!/usr/bin/env bash
#
# Crée une machine virtuelle Debian minimale, sans root et sans ISO à
# fabriquer : l'installateur est téléchargé au format « netboot » (noyau +
# initrd), et l'installation est entièrement automatisée grâce à un fichier
# preseed servi en HTTP par la machine hôte.
#
# Le système obtenu est volontairement minimal :
#   - aucune interface graphique, aucun « environmental recommend » ;
#   - seulement la base + SSH + sudo ;
#   - locale fr_FR.UTF-8 (indispensable pour OpenConcerto) ;
#   - swap et / sur un seul disque qcow2 extensible.
#
# Usage :
#   ./create-debian-vm.sh install        installe Debian (automatique)
#   ./create-debian-vm.sh start          démarre la VM installée
#   ./create-debian-vm.sh ssh            ouvre une session SSH
#   ./create-debian-vm.sh status         état de la VM
#   ./create-debian-vm.sh check          vérifie les prérequis
#   ./create-debian-vm.sh stop           arrête la VM
#
# Options :
#   --dist bookworm|trixie   version de Debian (défaut : trixie, sinon bookworm)
#   --dir DOSSIER           dossier de la VM (défaut : ~/debian-vm)
#   --disk TAILLE            taille du disque (défaut : 8G)
#   --ram MO                 mémoire (défaut : 2048)
#   --cpus N                 cœurs (défaut : 2)
#   --ssh-port PORT          port SSH publié sur l'hôte (défaut : 2222)
#   --user UTILISATEUR       compte à créer (défaut : oc)
#   --password MOT_DE_PASSE  mot de passe du compte (défaut : oc)
#   --headless               console série dans le terminal (pas de fenêtre)
#   --no-kvm                 forcer l'émulation logicielle (plus lent)
#   --keep-http              ne pas arrêter le serveur HTTP après l'installation
#
# Prérequis : qemu-system-x86_64, qemu-img, python3, curl ou wget.
# Aucun droit administrateur n'est nécessaire.
#
set -euo pipefail

# Si QEMU a ete installe « a cote » (sans root) par install-qemu-noroot.sh,
# on reprend son PATH et ses LD_LIBRARY_PATH.
for envf in "$HOME/qemu-local/qemu-env.sh" "/opt/qemu-local/qemu-env.sh"; do
    if [ -f "$envf" ]; then
        # shellcheck disable=SC1090
        . "$envf"
        break
    fi
done

VM_DIR="${VM_DIR:-$HOME/debian-vm}"
DIST=""
DISK_SIZE="8G"
RAM="2048"
CPUS="2"
SSH_PORT="2222"
VM_USER="oc"
VM_PASSWORD="oc"
HEADLESS=0
FORCE_TCG=0
KEEP_HTTP=0
HTTP_PORT="8099"
TIMEOUT_MIN=30
WAIT_SSH=1
FRESH=0
GUI=0

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }
warn() { printf '  ATTENTION : %s\n' "$*" >&2; }

usage() {
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

COMMAND=""
EXTRA=()
while [ $# -gt 0 ]; do
    case "$1" in
        --dist)     DIST="$2"; shift 2 ;;
        --dir)      VM_DIR="$2"; shift 2 ;;
        --disk)     DISK_SIZE="$2"; shift 2 ;;
        --ram)      RAM="$2"; shift 2 ;;
        --cpus)     CPUS="$2"; shift 2 ;;
        --ssh-port) SSH_PORT="$2"; shift 2 ;;
        --user)     VM_USER="$2"; shift 2 ;;
        --password) VM_PASSWORD="$2"; shift 2 ;;
        --headless) HEADLESS=1; shift ;;
        --no-kvm)   FORCE_TCG=1; shift ;;
        --keep-http) KEEP_HTTP=1; shift ;;
        --timeout)   TIMEOUT_MIN="$2"; shift 2 ;;
        --no-wait)   WAIT_SSH=0; shift ;;
        --fresh)     FRESH=1; shift ;;
        --gui)       GUI=1; shift ;;
        -h|--help)  usage 0 ;;
        *)
            if [ -z "$COMMAND" ]; then
                COMMAND="$1"
            else
                EXTRA+=("$1")
            fi
            shift
            ;;
    esac
done

COMMAND="${COMMAND:-install}"

# ------------------------------------------------------------------ outils
qemu_hint() {
    cat <<'HINT'

  QEMU n'est pas installé. Sans droits administrateur, le script
  install-qemu-noroot.sh l'installe « a cote » : il telecharge les
  paquets avec « apt download », les extrait dans ~/qemu-local/root, puis
  resout les bibliotheques manquantes (libcapstone.so.5, libfdt.so.1, ...).

    bash install-qemu-noroot.sh
    source ~/qemu-local/qemu-env.sh

  Une AppImage QEMU convient aussi (extraction avec --appimage-extract).

HINT
}

need() {
    if command -v "$1" >/dev/null 2>&1; then
        return 0
    fi
    case "$1" in
        qemu-system-x86_64|qemu-img) die "'$1' est introuvable dans le PATH.$(qemu_hint)" ;;
        *) die "'$1' est introuvable dans le PATH." ;;
    esac
}

download() {
    local url="$1" dest="$2"
    if [ -s "$dest" ]; then
        info "déjà téléchargé : $(basename "$dest")"
        return 0
    fi
    info "téléchargement : $url"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar -o "$dest" "$url" || die "téléchargement impossible : $url"
    else
        wget -q --show-progress -O "$dest" "$url" || die "téléchargement impossible : $url"
    fi
}

have_kvm() {
    [ "$FORCE_TCG" = "1" ] && return 1
    [ -r /dev/kvm ] && [ -w /dev/kvm ]
}

# ------------------------------------------------------------------ distro
detect_dist() {
    if [ -n "$DIST" ]; then
        return
    fi
    # « current » pointe sur la version stable : on tente la plus récente,
    # puis la précédente.
    for candidate in trixie bookworm; do
        local url
        url="https://deb.debian.org/debian/dists/${candidate}/main/installer-amd64/current/images/netboot/debian-installer/amd64/"
        if command -v curl >/dev/null 2>&1; then
            if curl -fsI "$url" >/dev/null 2>&1; then
                DIST="$candidate"
                return
            fi
        fi
    done
    DIST="bookworm"
}

netboot_urls() {
    printf 'https://deb.debian.org/debian/dists/%s/main/installer-amd64/current/images/netboot/debian-installer/amd64/linux\n' "$DIST"
    printf 'https://deb.debian.org/debian/dists/%s/main/installer-amd64/current/images/netboot/debian-installer/amd64/initrd.gz\n' "$DIST"
}

# ------------------------------------------------------------------ preseed
write_preseed() {
    local file="$1"
    cat > "$file" <<PRESEED
# Installation Debian minimale et non interactive (OpenConcerto 1.7.6).
d-i debian-installer/locale string en_US
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string debian-vm
d-i netcfg/get_domain string local
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string
d-i clock-setup/utc boolean true
d-i time/zone string Europe/Paris
d-i localechooser/supported-locales multiselect fr_FR.UTF-8 UTF-8
d-i locales/default_environment string fr_FR.UTF-8
d-i passwd/root-login boolean false
d-i passwd/make-user boolean true
d-i passwd/user-fullname string OpenConcerto
d-i passwd/username string ${VM_USER}
d-i passwd/user-password password ${VM_PASSWORD}
d-i passwd/user-password-again password ${VM_PASSWORD}
d-i user-setup/allow-password-weak boolean true
d-i user-setup/encrypt-home boolean false
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
d-i apt-setup/non-free boolean false
d-i apt-setup/contrib boolean false
d-i apt-setup/non-free-firmware boolean false
d-i apt-setup/services-select multiselect security,updates
d-i apt-setup/security_host string security.debian.org
d-i tasksel/task string standard
d-i tasksel/tasksel multiselect standard, ssh-server
d-i pkgsel/include string openssh-server sudo
d-i pkgsel/upgrade select none
popularity-contest popularity-contest/participate boolean false
d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string /dev/vda
d-i grub-installer/with_other_os boolean false
d-i finish-install/keep-consoles boolean false
d-i cdrom-detect/eject boolean true
d-i preseed/late_command string \\
    echo '${VM_USER} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${VM_USER}; \\
    chmod 440 /etc/sudoers.d/${VM_USER}
PRESEED
    info "preseed écrit : $file"
}

# ------------------------------------------------------------------ qemu
qemu_args() {
    local mode="$1"   # install | start
    QEMU_ARGS=(
        -name debian-vm
        -m "$RAM"
        -smp "$CPUS"
        -drive "file=${VM_DIR}/debian.qcow2,if=virtio,format=qcow2,cache=writeback"
        -netdev "user,id=net0,hostfwd=tcp:${SSH_PORT}-:22"
        -device virtio-net-pci,netdev=net0
        -device virtio-rng-pci
    )
    if have_kvm; then
        QEMU_ARGS+=(-enable-kvm -cpu host)
    else
        QEMU_ARGS+=(-cpu max)
        info "KVM indisponible : émulation logicielle, l'installation sera nettement plus lente."
    fi
    # Par defaut : aucune fenetre, tout passe par la console serie
    # (necessaire quand seul qemu-system-x86 est installe : le module
    # graphique GTK n'est pas fourni par ce paquet).
    if [ "$HEADLESS" = "1" ] || [ "$GUI" = "0" ] || [ -z "${DISPLAY:-}" ]; then
        QEMU_ARGS+=(-display none -serial stdio)
        HEADLESS=1
    elif qemu-system-x86_64 -display help 2>&1 | grep -q "gtk"; then
        QEMU_ARGS+=(-display gtk)
    else
        QEMU_ARGS+=(-display none -serial stdio)
        HEADLESS=1
        info "pas d'affichage GTK disponible : la console serie est utilisee."
    fi
    if [ "$mode" = "install" ]; then
        QEMU_ARGS+=(
            -kernel "${VM_DIR}/netboot/linux"
            -initrd "${VM_DIR}/netboot/initrd.gz"
            -append "console=ttyS0,115200n8 auto=true priority=critical debconf/frontend=noninteractive preseed/url=http://10.0.2.2:${HTTP_PORT}/preseed.cfg"
            -no-reboot
        )
    fi
}

# ------------------------------------------------------------------ actions
cmd_install() {
    need qemu-system-x86_64
    need qemu-img
    need python3
    detect_dist
    log "Préparation ($DIST, dossier $VM_DIR)"
    mkdir -p "$VM_DIR/netboot"

    local url
    while IFS= read -r url; do
        download "$url" "$VM_DIR/netboot/$(basename "$url")"
    done <<EOF
$(netboot_urls)
EOF

    if [ "$FRESH" = "1" ] && [ -f "$VM_DIR/debian.qcow2" ]; then
        info "disque supprimé (--fresh) : $VM_DIR/debian.qcow2"
        rm -f "$VM_DIR/debian.qcow2"
    fi
    if [ ! -f "$VM_DIR/debian.qcow2" ]; then
        qemu-img create -f qcow2 "$VM_DIR/debian.qcow2" "$DISK_SIZE" >/dev/null
        [ -f "$VM_DIR/debian.qcow2" ] || die "qemu-img n'a pas créé le disque $VM_DIR/debian.qcow2"
        info "disque créé : $VM_DIR/debian.qcow2 ($DISK_SIZE)"
    else
        info "disque déjà présent : $VM_DIR/debian.qcow2"
    fi

    write_preseed "$VM_DIR/preseed.cfg"

    log "Serveur HTTP local (preseed)"
    # 10.0.2.2 est l'adresse de l'hôte vue depuis le réseau « user » de QEMU.
    (cd "$VM_DIR" && exec python3 -m http.server "$HTTP_PORT" --bind 0.0.0.0) \
        > "$VM_DIR/http.log" 2>&1 &
    HTTP_PID=$!
    sleep 1
    if ! kill -0 "$HTTP_PID" 2>/dev/null; then
        die "le serveur HTTP n'a pas démarré (port $HTTP_PORT déjà utilisé ?)"
    fi
    info "preseed : http://10.0.2.2:$HTTP_PORT/preseed.cfg (pid $HTTP_PID)"

    log "Installation de Debian (sans interface, tout est pré-rempli)"
    info "l'installateur écrit dans ce terminal (console série) ; Ctrl-A X pour quitter."
    qemu_args install
    set +e
    qemu-system-x86_64 "${QEMU_ARGS[@]}" 2>&1 | tee "$VM_DIR/install.log"
    RC=${PIPESTATUS[0]}
    set -e
    if [ "$KEEP_HTTP" = "0" ]; then
        kill "$HTTP_PID" 2>/dev/null || true
    fi
    if [ "$RC" != "0" ]; then
        printf '\n'
        tail -20 "$VM_DIR/install.log" 2>/dev/null || true
        die "l'installateur s'est arrêté avec le code $RC. Journal : $VM_DIR/install.log"
    fi

    log "Premier démarrage depuis le disque"
    cmd_start_daemon
    if [ "$WAIT_SSH" = "1" ]; then
        wait_ssh || true
    fi
}

# Demarre la VM en arriere-plan (le terminal reste libre).
cmd_start_daemon() {
    [ -f "$VM_DIR/debian.qcow2" ] || die "Aucun disque dans $VM_DIR (lance d'abord « install »)."
    qemu_args start
    log "Démarrage de la VM (en arrière-plan)"
    nohup qemu-system-x86_64 "${QEMU_ARGS[@]}" > "$VM_DIR/console.log" 2>&1 &
    echo $! > "$VM_DIR/qemu.pid"
    info "pid : $(cat "$VM_DIR/qemu.pid")"
    info "console de la VM : tail -f $VM_DIR/console.log"
}

# Attend que le serveur SSH de la VM réponde : c'est le signal fiable de
# fin d'installation.
wait_ssh() {
    local waited=0 limit=$(( TIMEOUT_MIN * 60 ))
    log "Attente du serveur SSH (port $SSH_PORT)"
    while [ "$waited" -lt "$limit" ]; do
        if (exec 3<>/dev/tcp/127.0.0.1/"$SSH_PORT") 2>/dev/null; then
            exec 3<&- 2>/dev/null || true
            info "SSH répond : l'installation est terminée."
            info "connexion : ssh -p $SSH_PORT ${VM_USER}@127.0.0.1   (mot de passe : $VM_PASSWORD)"
            return 0
        fi
        if [ -f "$VM_DIR/qemu.pid" ] && ! kill -0 "$(cat "$VM_DIR/qemu.pid")" 2>/dev/null; then
            warn "QEMU s'est arrêté."
            tail -20 "$VM_DIR/console.log" 2>/dev/null || true
            return 1
        fi
        sleep 10
        waited=$(( waited + 10 ))
        if [ $(( waited % 60 )) -eq 0 ]; then
            info "encore en cours... ($(( waited / 60 )) min)"
        fi
    done
    warn "delai depasse : le port $SSH_PORT ne repond pas."
    info "consulte la console : tail -f $VM_DIR/console.log"
    return 1
}

cmd_start() {
    [ -f "$VM_DIR/debian.qcow2" ] || die "Aucun disque dans $VM_DIR (lance d'abord « install »)."
    qemu_args start
    log "Démarrage de la VM"
    info "SSH : ssh -p $SSH_PORT ${VM_USER}@127.0.0.1"
    info "mot de passe : $VM_PASSWORD"
    info "arrêt : Ctrl-A puis X (ou « qemu-system-x86_64 -name debian-vm ... » dans un autre terminal)"
    qemu-system-x86_64 "${QEMU_ARGS[@]}"
}

cmd_ssh() {
    need ssh
    ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${VM_USER}@127.0.0.1"
}

cmd_status() {
    if pgrep -f "qemu-system-x86_64.*debian-vm" >/dev/null 2>&1; then
        info "VM en cours d'exécution"
        pgrep -af "qemu-system-x86_64.*debian-vm" | sed 's/^/    /'
    else
        info "VM arrêtée"
    fi
    [ -f "$VM_DIR/debian.qcow2" ] && info "disque : $VM_DIR/debian.qcow2 ($(du -h "$VM_DIR/debian.qcow2" | cut -f1) réellement utilisés)"
    return 0
}

cmd_check() {
    log "Vérification de l'environnement"
    local missing=0
    for c in qemu-system-x86_64 qemu-img python3 curl wget ssh; do
        if command -v "$c" >/dev/null 2>&1; then
            info "OK   $c ($(command -v "$c"))"
        else
            info "MANQUE $c"
            case "$c" in
                qemu-system-x86_64|qemu-img) missing=1 ;;
            esac
        fi
    done
    if have_kvm; then
        info "OK   KVM (/dev/kvm accessible) : vitesse native"
    else
        info "KVM inaccessible : émulation logicielle, l'installation sera plus lente."
        info "  (accès rootless à /dev/kvm : groupe 'kvm' — à demander à l'administrateur)"
    fi
    if [ "$missing" = "1" ]; then
        qemu_hint
        return 1
    fi
    return 0
}

cmd_stop() {
    if pkill -f "qemu-system-x86_64.*debian-vm"; then
        info "VM arrêtée"
    else
        info "aucune VM à arrêter"
    fi
}

case "$COMMAND" in
    install) cmd_install ;;
    start)   cmd_start ;;
    ssh)     cmd_ssh ;;
    status)  cmd_status ;;
    check)   cmd_check ;;
    stop)    cmd_stop ;;
    help|-h|--help) usage 0 ;;
    *) die "commande inconnue : '$COMMAND'" ;;
esac
