#!/usr/bin/env bash
#
# Met a jour les scripts d'audit/correctif DANS la VM Debian, depuis GitHub,
# sans toucher a la stack qui tourne (pas de redemarrage, pas de dump).
#
# Les scripts sont telecharges PAR LA VM (elle a Internet) : le poste de
# l'utilisateur n'a besoin que de ssh.
#
#   bash refresh-scripts-in-vm.sh                # les 8 scripts d'audit/dump
#   bash refresh-scripts-in-vm.sh --audit        # + audit des droits (lecture seule)
#   bash refresh-scripts-in-vm.sh --diagnostic   # + diagnostic complet (structure + droits)
#   bash refresh-scripts-in-vm.sh test-droits-utilisateur.sh   # un seul fichier
#
# Options :
#   --host HOTE      adresse de la VM  (defaut : 127.0.0.1)
#   --port PORT      port SSH de la VM (defaut : 2222)
#   --user UTIL      compte de la VM  (defaut : oc)
#   --ref BRANCHE    branche GitHub   (defaut : arena/61954a71-openconcerto-module-project)
#   --audit          enchaîne l'audit des droits (lecture seule) dans la VM
#   --diagnostic     enchaîne le diagnostic complet (lecture seule) dans la VM
#   -h|--help        cette aide
#
set -euo pipefail

VM_HOST="127.0.0.1"
VM_PORT="2222"
VM_USER="oc"
GITHUB_REPO="jojo8356/openconcerto-module-project"
GITHUB_REF="arena/61954a71-openconcerto-module-project"
RUN_AUDIT=0
RUN_DIAGNOSTIC=0
EXTRA_FILES=()

usage() {
    sed -n '/^# Options/,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --host) VM_HOST="$2"; shift 2 ;;
        --port) VM_PORT="$2"; shift 2 ;;
        --user) VM_USER="$2"; shift 2 ;;
        --ref)  GITHUB_REF="$2"; shift 2 ;;
        --audit) RUN_AUDIT=1; shift ;;
        --diagnostic) RUN_DIAGNOSTIC=1; shift ;;
        -h|--help) usage ;;
        -*) echo "option inconnue : $1" >&2; exit 1 ;;
        *) EXTRA_FILES+=("$1"); shift ;;
    esac
done

VM_DIR="/home/$VM_USER/oc-176"
SCRIPT_DIR="$VM_DIR/scripts"
STACK_DIR="$VM_DIR/docker/openconcerto-1.7.6"

DEFAULT_FILES=(
    test-droits-utilisateur.sh
    test-transfert-fournisseur.sh
    trouver-mdp-utilisateur.sh
    diagnostic-transfert-fournisseur.sh
    fix-facture-fournisseur-all-schemas.sh
    restore-openconcerto-dump.sh
    dump-structure-sql.sh
    dump-to-sql.sh
)
if [ "${#EXTRA_FILES[@]}" -gt 0 ]; then
    FILES=("${EXTRA_FILES[@]}")
else
    FILES=("${DEFAULT_FILES[@]}")
fi

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

command -v ssh >/dev/null 2>&1 || die "'ssh' introuvable."

# Une seule demande de mot de passe : session multiplexee.
CONTROL_PATH="/tmp/oc176-refresh-ssh-%r@%h:%p"
KEY_FILE="$HOME/.ssh/id_ed25519_oc176"
SSH_OPTS=(-p "$VM_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=10
          -o ControlMaster=auto -o ControlPath="$CONTROL_PATH" -o ControlPersist=60)
if [ -f "$KEY_FILE" ]; then
    SSH_OPTS+=(-i "$KEY_FILE")
fi

vssh() {
    ssh "${SSH_OPTS[@]}" "$VM_USER@$VM_HOST" "$@"
}

log "Verification de l'acces a la VM"
vssh "true" || die "connexion SSH impossible sur $VM_HOST:$VM_PORT"

log "Mise a jour des scripts dans $SCRIPT_DIR"
vssh "mkdir -p '$SCRIPT_DIR'" || die "creation de $SCRIPT_DIR impossible"

for f in "${FILES[@]}"; do
    if vssh "curl -fsSL -H 'Accept: application/vnd.github.raw' \
'https://api.github.com/repos/$GITHUB_REPO/contents/scripts/$f?ref=$GITHUB_REF' \
-o '$SCRIPT_DIR/$f'"; then
        info "telecharge : scripts/$f"
    else
        die "telechargement impossible : scripts/$f"
    fi
done

vssh "chmod +x '$SCRIPT_DIR'/*.sh" || true
vssh "ls -l '$SCRIPT_DIR'" || true

if [ "$RUN_AUDIT" = "1" ]; then
    log "Audit des droits dans la VM (lecture seule, aucune ecriture)"
    vssh "cd '$VM_DIR' && export PGPASSWORD=\$(sed -n 's/^POSTGRES_PASSWORD=//p' '$STACK_DIR/.env') && \
bash scripts/test-droits-utilisateur.sh -1 erp -2 abe \
     -H 127.0.0.1 -p 5433 -b OpenConcerto -U openconcerto \
     -o '$STACK_DIR' 2>&1 | tee /tmp/droits-audit.txt" || true
    info "sortie complete enregistree dans /tmp/droits-audit.txt (dans la VM)"
fi

if [ "$RUN_DIAGNOSTIC" = "1" ]; then
    log "Diagnostic complet dans la VM (lecture seule, aucune ecriture)"
    vssh "cd '$VM_DIR' && export PGPASSWORD=\$(sed -n 's/^POSTGRES_PASSWORD=//p' '$STACK_DIR/.env') && \
bash scripts/diagnostic-transfert-fournisseur.sh -1 erp -2 abe \
     -H 127.0.0.1 -p 5433 -b OpenConcerto -U openconcerto \
     -o '$STACK_DIR' 2>&1 | tee /tmp/diagnostic-transfert.txt" || true
    info "sortie complete enregistree dans /tmp/diagnostic-transfert.txt (dans la VM)"
fi

log "Termine"
