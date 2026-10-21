#!/usr/bin/env bash
#
# Crée une machine virtuelle Debian minimale avec VirtualBox, en
# installation entièrement automatique (mode « unattended » de VirtualBox),
# sans droits administrateur et sans construire d'ISO.
#
# Le système obtenu est volontairement minimal :
#   - aucune interface graphique, aucun paquet recommandé ;
#   - seulement la base + SSH + sudo ;
#   - locale fr_FR.UTF-8 (indispensable pour OpenConcerto) ;
#   - un seul disque VDI extensible, réseau NAT avec redirection SSH.
#
# Usage :
#   ./create-debian-vm-vbox.sh check     vérifie les prérequis
#   ./create-debian-vm-vbox.sh install   crée la VM et lance l'installation
#   ./create-debian-vm-vbox.sh start     démarre la VM
#   ./create-debian-vm-vbox.sh ssh       ouvre une session SSH
#   ./create-debian-vm-vbox.sh status    état de la VM
#   ./create-debian-vm-vbox.sh stop      arrête la VM
#   ./create-debian-vm-vbox.sh delete    supprime la VM (et son disque)
#
# Options :
#   --name NOM          nom de la VM (défaut : debian-vm)
#   --dir DOSSIER       dossier de la VM (défaut : ~/debian-vm)
#   --iso CHEMIN|URL    ISO netinst à utiliser (téléchargé si absent)
#   --dist bookworm|trixie   version de Debian (défaut : trixie)
#   --disk TAILLE       taille du disque (défaut : 8G)
#   --ram MO            mémoire (défaut : 2048)
#   --cpus N            cœurs (défaut : 2)
#   --ssh-port PORT     port SSH publié sur l'hôte (défaut : 2222)
#   --user UTILISATEUR  compte à créer (défaut : oc)
#   --password MDP      mot de passe du compte (défaut : oc)
#   --timeout MINUTES   attente maximale pendant l'installation (defaut : 45)
#   --no-wait           ne pas attendre la fin de l'installation
#
# Prérequis : VBoxManage (VirtualBox 6.1 ou plus), curl, ssh.
#
set -euo pipefail

VM_NAME="${VM_NAME:-debian-vm}"
VM_DIR="${VM_DIR:-$HOME/debian-vm}"
ISO=""
DIST=""
DISK_SIZE="8G"
RAM="2048"
CPUS="2"
SSH_PORT="2222"
VM_USER="oc"
VM_PASSWORD="oc"
TIMEOUT_MIN=45
WAIT_SSH=1

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

COMMAND=""
EXTRA=()
while [ $# -gt 0 ]; do
    case "$1" in
        --name)     VM_NAME="$2"; shift 2 ;;
        --dir)      VM_DIR="$2"; shift 2 ;;
        --iso)      ISO="$2"; shift 2 ;;
        --dist)     DIST="$2"; shift 2 ;;
        --disk)     DISK_SIZE="$2"; shift 2 ;;
        --ram)      RAM="$2"; shift 2 ;;
        --cpus)     CPUS="$2"; shift 2 ;;
        --ssh-port) SSH_PORT="$2"; shift 2 ;;
        --user)     VM_USER="$2"; shift 2 ;;
        --password) VM_PASSWORD="$2"; shift 2 ;;
        --timeout)  TIMEOUT_MIN="$2"; shift 2 ;;
        --no-wait)  WAIT_SSH=0; shift ;;
        -h|--help)  usage 0 ;;
        *)
            if [ -z "$COMMAND" ]; then COMMAND="$1"; else EXTRA+=("$1"); fi
            shift
            ;;
    esac
done
COMMAND="${COMMAND:-check}"

# ------------------------------------------------------------------ outils
vbox() {
    if command -v VBoxManage >/dev/null 2>&1; then
        VBoxManage "$@"
    elif [ -x "/usr/bin/VBoxManage" ]; then
        /usr/bin/VBoxManage "$@"
    elif [ -x "/opt/VirtualBox/VBoxManage" ]; then
        /opt/VirtualBox/VBoxManage "$@"
    else
        die "VBoxManage introuvable. Installe VirtualBox (paquet 'virtualbox')."
    fi
}

need_vbox() {
    command -v VBoxManage >/dev/null 2>&1 \
        || [ -x /usr/bin/VBoxManage ] \
        || [ -x /opt/VirtualBox/VBoxManage ] \
        || die "VBoxManage introuvable (paquet 'virtualbox')."
    local ver vnum major minor
    ver=$(vbox --version 2>/dev/null | head -n 1)
    info "VirtualBox : ${ver:-inconnu}"
    vnum=$(printf '%s' "$ver" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)
    [ -n "$vnum" ] || die "version de VirtualBox illisible : ${ver:-?}"
    major=${vnum%%.*}
    minor=$(printf '%s' "$vnum" | cut -d. -f2)
    if [ "$major" -lt 6 ] || { [ "$major" -eq 6 ] && [ "$minor" -lt 1 ]; }; then
        die "VirtualBox 6.1 ou plus est requis pour l'installation unattended (version detectee : $vnum)."
    fi
}

download() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar -o "$dest" "$url" || die "téléchargement impossible : $url"
    else
        wget -q --show-progress -O "$dest" "$url" || die "téléchargement impossible : $url"
    fi
}

# ISO netinst de la version demandée : on va chercher le nom exact dans
# l'annuaire du miroir plutôt que de coder une version.
resolve_iso() {
    local name="" base url page
    for base in "https://deb.debian.org/debian-cd/current/amd64/iso-cd/" \
                "https://cdimage.debian.org/cdimage/release/current/amd64/iso-cd/"; do
        page=$(curl -fsL "$base" 2>/dev/null) || continue
        name=$(printf '%s' "$page" | grep -o 'debian-[0-9][^"]*-amd64-netinst\.iso' | sort -u | tail -n 1)
        [ -n "$name" ] || continue
        if [ -n "$DIST" ]; then
            case "$name" in
                *"$DIST"*) ;;
                *) name="" ; continue ;;
            esac
        fi
        [ -n "$name" ] || continue
        printf '%s%s' "$base" "$name"
        return 0
    done
    if [ -n "$DIST" ]; then
        echo "ERREUR : aucun ISO netinst pour '$DIST' trouvé" >&2
    else
        echo "ERREUR : aucun ISO netinst trouvé" >&2
    fi
    return 1
}

ensure_iso() {
    if [ -n "$ISO" ] && [ -f "$ISO" ]; then
        printf '%s' "$ISO"
        return 0
    fi
    mkdir -p "$VM_DIR"
    if [ -z "$ISO" ]; then
        log "Recherche de l'ISO netinst"
        ISO=$(resolve_iso) || die "aucun ISO netinst trouvé"
    fi
    case "$ISO" in
        http*)
            local dest="$VM_DIR/$(basename "$ISO")"
            if [ ! -s "$dest" ]; then
                info "téléchargement : $ISO"
                download "$ISO" "$dest"
            else
                info "ISO déjà téléchargé : $dest"
            fi
            printf '%s' "$dest"
            ;;
        *)
            [ -f "$ISO" ] || die "ISO introuvable : $ISO"
            printf '%s' "$ISO"
            ;;
    esac
}

vm_exists() {
    vbox list vms 2>/dev/null | grep -q "\"$VM_NAME\""
}

vm_state() {
    vbox showvminfo "$VM_NAME" --machinereadable 2>/dev/null \
        | sed -n 's/^VMState="\(.*\)"$/\1/p' | head -n 1
}

# ------------------------------------------------------------------ commandes
cmd_check() {
    log "Vérification de l'environnement"
    need_vbox
    local c
    for c in curl ssh; do
        command -v "$c" >/dev/null 2>&1 && info "OK   $c" || info "MANQUE $c"
    done
    info "OSTypes Debian disponibles :"
    vbox list ostypes 2>/dev/null | grep -i debian | sed 's/^/    /' | head -5
    info "VM existante : $(vm_exists && echo oui || echo non)"
    return 0
}

cmd_install() {
    need_vbox
    local iso_path
    iso_path=$(ensure_iso)
    info "ISO : $iso_path"

    if vm_exists; then
        info "la VM '$VM_NAME' existe déjà : elle va être supprimée"
        vbox controlvm "$VM_NAME" poweroff >/dev/null 2>&1 || true
        sleep 2
        vbox unregistervm "$VM_NAME" --delete >/dev/null
    fi
    mkdir -p "$VM_DIR"

    log "Création de la VM '$VM_NAME'"
    local ostype="Debian_12"
    if ! vbox list ostypes | grep -q "^Debian_12"; then
        ostype=$(vbox list ostypes | grep -i "^Debian" | head -n 1 | awk '{print $1}')
    fi
    info "type d'OS : $ostype"
    vbox createvm --name "$VM_NAME" --ostype "$ostype" --register >/dev/null

    vbox modifyvm "$VM_NAME" \
        --memory "$RAM" \
        --cpus "$CPUS" \
        --vram 16 \
        --boot1 dvd --boot2 disk \
        --nic1 nat \
        --natpf1 "ssh,tcp,,${SSH_PORT},,22" \
        --natpf1 "web,tcp,,8083,,80" \
        --audio none \
        --usb off \
        --clipboard off \
        --draganddrop off >/dev/null

    local size_mb=$(( ${DISK_SIZE%G} * 1024 ))
    vbox modifymedium disk --filename "$VM_DIR/${VM_NAME}.vdi" --format VDI --resize "$size_mb" >/dev/null
    vbox storagectl "$VM_NAME" --name SATA --add sata --controller IntelAhci --portcount 1 >/dev/null
    vbox storageattach "$VM_NAME" --storagectl SATA --port 0 --device 0 --type hdd \
        --medium "$VM_DIR/${VM_NAME}.vdi" >/dev/null
    info "disque : $VM_DIR/${VM_NAME}.vdi ($DISK_SIZE)"

    log "Installation automatique (mode unattended de VirtualBox)"
    vbox unattended "$VM_NAME" detect --iso "$iso_path" || info "(détection de l'ISO : information seulement)"
    vbox unattended "$VM_NAME" install \
        --iso "$iso_path" \
        --user "$VM_USER" \
        --password "$VM_PASSWORD" \
        --fullname "OpenConcerto" \
        --locale fr_FR \
        --country FR \
        --keyboard fr \
        --timezone Europe/Paris \
        --install-basic-package \
        --package openssh-server \
        --package sudo \
        --image dvd >/dev/null
    info "preseed généré, l'installation démarre au prochain lancement."

    cmd_start
    if [ "$WAIT_SSH" = "1" ]; then
        cmd_wait || true
    fi
}

cmd_start() {
    vm_exists || die "la VM '$VM_NAME' n'existe pas (lance d'abord « install »)."
    local state
    state=$(vm_state)
    if [ "$state" = "running" ]; then
        info "la VM est déjà démarrée"
        return 0
    fi
    log "Démarrage de la VM"
    vbox startvm "$VM_NAME" --type headless >/dev/null
    info "SSH : ssh -p $SSH_PORT ${VM_USER}@127.0.0.1"
    info "mot de passe : $VM_PASSWORD"
    info "l'installation se poursuit en arrière-plan ; suis-la avec :"
    info "  VBoxManage showvminfo $VM_NAME | grep -E 'State|Logged'"
    info "  tail -f ~/.config/VirtualBox/Logs/$VM_NAME/VBox.log"
    info "et connecte-toi dès que le port $SSH_PORT répond :"
    info "  bash $0 ssh"
}

# Attend que la VM reponde sur le port SSH : c'est le signal fiable de fin
# d'installation (l'installateur ne le demarre qu'a la fin).
cmd_wait() {
    log "Attente de l'installation (port SSH $SSH_PORT)"
    local waited=0 limit=$(( TIMEOUT_MIN * 60 ))
    while [ "$waited" -lt "$limit" ]; do
        if (exec 3<>/dev/tcp/127.0.0.1/"$SSH_PORT") 2>/dev/null; then
            exec 3<&- 2>/dev/null || true
            info "SSH repond : l'installation est terminee."
            info "connexion : bash $0 ssh  (utilisateur $VM_USER, mot de passe $VM_PASSWORD)"
            return 0
        fi
        sleep 15
        waited=$(( waited + 15 ))
        if [ $(( waited % 120 )) -eq 0 ]; then
            info "encore en cours... ($(( waited / 60 )) min)"
        fi
    done
    info "delai depasse : l'installation n'est peut-etre pas terminee."
    info "consulte : VBoxManage showvminfo $VM_NAME | grep State"
    return 1
}

cmd_ssh() {
    command -v ssh >/dev/null 2>&1 || die "'ssh' introuvable."
    ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${VM_USER}@127.0.0.1"
}

cmd_status() {
    if vm_exists; then
        log "État de la VM '$VM_NAME'"
        vbox showvminfo "$VM_NAME" | grep -E "Name:|State:|Guest OS|Storage Controller Name|SATA.*\.vdi" | sed 's/^/  /'
    else
        info "la VM '$VM_NAME' n'existe pas"
    fi
    if [ -f "$VM_DIR/${VM_NAME}.vdi" ]; then
        info "disque : $(du -h "$VM_DIR/${VM_NAME}.vdi" | cut -f1) réellement utilisés"
    fi
    return 0
}

cmd_stop() {
    vm_exists || die "la VM '$VM_NAME' n'existe pas."
    log "Arrêt de la VM"
    vbox controlvm "$VM_NAME" acpipowerbutton >/dev/null 2>&1 || true
    sleep 3
    vbox controlvm "$VM_NAME" poweroff >/dev/null 2>&1 || true
    info "arrêtée"
}

cmd_delete() {
    if vm_exists; then
        log "Suppression de la VM '$VM_NAME'"
        vbox controlvm "$VM_NAME" poweroff >/dev/null 2>&1 || true
        sleep 2
        vbox unregistervm "$VM_NAME" --delete >/dev/null
    fi
    [ -f "$VM_DIR/${VM_NAME}.vdi" ] && rm -f "$VM_DIR/${VM_NAME}.vdi"
    info "supprimée (dossier $VM_DIR conservé pour l'ISO)"
    return 0
}

case "$COMMAND" in
    check)   cmd_check ;;
    install) cmd_install ;;
    start)   cmd_start ;;
    ssh)     cmd_ssh ;;
    wait)    cmd_wait ;;
    status)  cmd_status ;;
    stop)    cmd_stop ;;
    delete)  cmd_delete ;;
    help|-h|--help) usage 0 ;;
    *) die "commande inconnue : '$COMMAND'" ;;
esac
