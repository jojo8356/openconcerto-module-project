#!/usr/bin/env bash
#
# Installe le CLIENT OpenConcerto 1.7.6 sur ce poste, sans root et sans sudo,
# et le branche sur la base PostgreSQL qui tourne dans la VM Debian.
#
# Le poste n'a ni root ni sudo : le JRE est donc déployé dans $HOME (Temurin 11,
# archive officielle GitHub) et le client est extrait dans $HOME.
#
#   bash install-oc176-client.sh            # tout (JRE + client + configuration)
#   bash install-oc176-client.sh -n         # plan : n'écrit rien
#   bash install-oc176-client.sh --jre-only
#   bash install-oc176-client.sh --client-only
#
# Options :
#   -H HOTE[:PORT]  serveur PostgreSQL vu par le client
#                   (défaut : 127.0.0.1:5434 = le tunnel SSH vers la VM)
#   -d BASE         base (défaut : OpenConcerto)
#   -U ROLE         rôle SQL (défaut : openconcerto)
#   -P MDP          mot de passe (défaut : lu dans le .env de la stack, sinon
#                   dans la VM via SSH)
#   -c CONF         main.properties (défaut : ~/.config/OpenConcerto/main.properties)
#   -o DOSSIER      dossier d'installation (défaut : $HOME)
#   -n              dry-run
#   -h              cette aide
#
set -euo pipefail

OC_VERSION="1.7.6"
OC_URL="https://www.openconcerto.org/fr/telechargement/1.7/OpenConcerto-${OC_VERSION}-multiposte.tar.gz"
JRE_URL="https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.32.1%2B1/OpenJDK11U-jre_x64_linux_hotspot_11.0.32.1_1.tar.gz"

HOST_PORT="127.0.0.1:5434"
DB="OpenConcerto"
ROLE="openconcerto"
PASSWORD=""
CONF="${OC_CONF:-$HOME/.config/OpenConcerto/main.properties}"
INSTALL_DIR="$HOME"
DRY=0
JRE_ONLY=0
CLIENT_ONLY=0

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '/^# Options/,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        -H) HOST_PORT="$2"; shift 2 ;;
        -d) DB="$2"; shift 2 ;;
        -U) ROLE="$2"; shift 2 ;;
        -P) PASSWORD="$2"; shift 2 ;;
        -c) CONF="$2"; shift 2 ;;
        -o) INSTALL_DIR="$2"; shift 2 ;;
        -n) DRY=1; shift ;;
        --jre-only) JRE_ONLY=1; shift ;;
        --client-only) CLIENT_ONLY=1; shift ;;
        -h|--help) usage ;;
        *) die "option inconnue : $1" ;;
    esac
done

if [ "$JRE_ONLY" = "1" ] && [ "$CLIENT_ONLY" = "1" ]; then
    die "--jre-only et --client-only sont exclusifs."
fi

[ -n "$HOST_PORT" ] || die "-H vide."

# --------------------------------------------------------------- environnement
log "Environnement"
info "poste     : $(uname -srm)"
info "java      : $(command -v java >/dev/null 2>&1 && java -version 2>&1 | head -1 || echo 'ABSENT')"
info "affichage : DISPLAY=${DISPLAY:-<vide>}  (le client est une application graphique)"
if [ -z "${DISPLAY:-}" ]; then
    info "ATTENTION : pas de DISPLAY => le client ne demarrera pas en mode fenetre."
    info "           (sous X11 : 'export DISPLAY=:0' apres 'xhost +local:')"
fi

# ------------------------------------------------------------------ mot de passe
if [ -z "$PASSWORD" ]; then
    for f in "$INSTALL_DIR/oc-176-podman/docker/openconcerto-1.7.6/.env" \
             "$INSTALL_DIR/oc-176-docker/docker/openconcerto-1.7.6/.env" \
             "$HOME/oc-176/docker/openconcerto-1.7.6/.env"; do
        if [ -f "$f" ]; then
            PASSWORD=$(sed -n 's/^POSTGRES_PASSWORD=//p' "$f" | head -n 1)
            [ -n "$PASSWORD" ] && { info "mot de passe lu dans $f"; break; }
        fi
    done
fi
if [ -z "$PASSWORD" ]; then
    # Dernier recours : le .env de la stack dans la VM.
    if command -v ssh >/dev/null 2>&1; then
        PASSWORD=$(ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                        -o LogLevel=ERROR -o ConnectTimeout=8 \
                        oc@127.0.0.1 "sed -n 's/^POSTGRES_PASSWORD=//p' ~/oc-176/docker/openconcerto-1.7.6/.env" 2>/dev/null | head -n 1)
        [ -n "$PASSWORD" ] && info "mot de passe lu dans le .env de la VM"
    fi
fi
[ -n "$PASSWORD" ] || die "mot de passe inconnu : passe-le avec -P (il doit correspondre au role '$ROLE' de la base)."

# ------------------------------------------------------------------ JRE (Temurin 11)
JRE_DIR=""
OC_DIR=""
if [ "$CLIENT_ONLY" = "0" ]; then
    if command -v java >/dev/null 2>&1; then
        log "Java deja present : on ne touche a rien"
    else
        log "Installation d'un JRE Temurin 11 (sans root) dans $INSTALL_DIR/java"
        mkdir -p "$INSTALL_DIR/java"
        cd "$INSTALL_DIR/java"
        if [ "$DRY" = "1" ]; then
            info "telecarge : $JRE_URL"
            info "extrait dans : $INSTALL_DIR/java"
        else
            curl -fL --retry 3 -o jre11.tar.gz "$JRE_URL" || die "telechargement du JRE impossible."
            tar xzf jre11.tar.gz || die "extraction du JRE impossible."
            rm -f jre11.tar.gz
            JRE_DIR=$(find "$INSTALL_DIR/java" -maxdepth 1 -type d -name 'jdk-11*' | head -n 1)
            [ -n "$JRE_DIR" ] || die "JRE non trouve apres extraction."
            info "JRE : $JRE_DIR"
            if [ -f "$HOME/.zshrc" ]; then
                grep -q 'JAVA_HOME' "$HOME/.zshrc" || printf '\nexport JAVA_HOME="%s"\n' "$JRE_DIR" >> "$HOME/.zshrc"
            fi
            info "JAVA_HOME exporte (et ajoute a ~/.zshrc si le fichier existe)"
        fi
    fi
fi
[ "$JRE_ONLY" = "1" ] && { log "JRE uniquement : termine"; exit 0; }

# ------------------------------------------------------------------ client OC
log "Telechargement du client OpenConcerto $OC_VERSION (multiposte, ~83 Mo)"
cd "$INSTALL_DIR"
if [ "$DRY" = "1" ]; then
    info "telecarge : $OC_URL"
    info "extrait dans : $INSTALL_DIR"
else
    curl -fL --retry 3 -o "oc-$OC_VERSION.tar.gz" "$OC_URL" || die "telechargement du client impossible."
    tar xzf "oc-$OC_VERSION.tar.gz" || die "extraction du client impossible."
    rm -f "oc-$OC_VERSION.tar.gz"
    OC_DIR=$(find "$INSTALL_DIR" -maxdepth 2 -type d -name "OpenConcerto-$OC_VERSION*" | head -n 1)
    [ -n "$OC_DIR" ] || die "dossier du client introuvable apres extraction."
    info "client : $OC_DIR"
    chmod +x "$OC_DIR"/*.sh 2>/dev/null || true
fi

# ------------------------------------------------------- configuration du client
log "Configuration du client ($CONF)"
mkdir -p "$(dirname "$CONF")"
if [ -f "$CONF" ]; then
    if [ "$DRY" = "1" ]; then
        info "sauvegarde : $CONF.bak-* (sauvegarde reelle en mode normal)"
    else
        cp -p "$CONF" "$CONF.bak-$(date +%Y-%m-%d_%H%M%S)"
        info "sauvegarde : $CONF.bak-*"
    fi
else
    info "nouveau fichier"
fi

# server.ip contient l'hote ET le port, le deux-points echappe (\:) : c'est le
# format qu'ecrit OpenConcerto (Properties : "\:" -> ":").
HOST_ESC=$(printf '%s' "$HOST_PORT" | sed 's/:/\\:/g')
{
    grep -v -E '^[[:space:]]*(server\.ip|systemRoot|server\.login|server\.password|server\.driver)[[:space:]]*=' "$CONF" 2>/dev/null || true
    printf 'server.ip=%s\n' "$HOST_ESC"
    printf 'systemRoot=%s\n' "$DB"
    printf 'server.driver=postgresql\n'
    printf 'server.login=%s\n' "$ROLE"
    printf 'server.password=%s\n' "$PASSWORD"
} > "$CONF.tmp"
if [ "$DRY" = "1" ]; then
    info "ecrirait dans $CONF :"
    sed 's/^server\.password=.*/server.password=<masque>/' "$CONF.tmp" | sed 's/^/    /'
    rm -f "$CONF.tmp"
else
    cat "$CONF.tmp" > "$CONF"
    rm -f "$CONF.tmp"
    info "ecrit :"
    sed 's/^server\.password=.*/server.password=<masque>/' "$CONF" | sed 's/^/    /'
fi

# ------------------------------------------------------------------ lancement
log "Prochaines etapes"
if [ -n "${OC_DIR:-}" ]; then
    info "1. lancer le client :"
    info "     cd \"$OC_DIR\" && sh OpenConcerto.sh"
else
    info "1. cd <dossier du client> && sh OpenConcerto.sh"
fi
info "2. se connecter avec le compte 'abe' (Gisele) sur la societe KINETIC-THERM (42)"
info "3. rejouer le transfert commande fournisseur -> facture fournisseur"
info
info "Le client doit joindre la base par le tunnel SSH :"
info "     ssh -p 2222 -N -L 127.0.0.1:5434:127.0.0.1:5433 oc@127.0.0.1 &"
