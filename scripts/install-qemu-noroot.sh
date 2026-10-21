#!/usr/bin/env bash
#
# Installe QEMU « à côté » dans ~/qemu-local, SANS droits administrateur.
#
# On ne peut pas faire « apt install qemu-system-x86 » sans root : on
# télécharge donc les paquets avec « apt download » (qui n'a pas besoin de
# root) et on les extrait avec « dpkg-deb -x » dans ~/qemu-local/root.
#
# Le piège : « apt download qemu-system-x86 » ne récupère PAS les
# dépendances. qemu-system-x86_64 charge alors des bibliothèques absentes
# (libcapstone.so.5, libfdt.so.1, ...) et refuse de démarrer. Ce script
# boucle : il lance « ldd », récupère les .so manquants, retrouve le
# paquet Debian correspondant, le télécharge et l'extrait, jusqu'à ce que
# plus rien ne manque.
#
# Finally, it writes ~/qemu-local/qemu-env.sh, to be sourced before using
# QEMU.
#
#   bash install-qemu-noroot.sh
#   source ~/qemu-local/qemu-env.sh
#   qemu-system-x86_64 --version
#
set -euo pipefail

PREFIX="${PREFIX:-$HOME/qemu-local}"
ROOT="$PREFIX/root"
DEBS="$PREFIX/debs"
ENVFILE="$PREFIX/qemu-env.sh"
MAX_ROUNDS=8

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '  %s\n' "$*"; }
die()  { printf '\nERREUR : %s\n' "$*" >&2; exit 1; }

command -v apt >/dev/null 2>&1 || die "« apt » est necessaire (Debian/Ubuntu)."
command -v dpkg-deb >/dev/null 2>&1 || die "« dpkg-deb » est necessaire."

mkdir -p "$ROOT" "$DEBS"

# ---------------------------------------------------------------- paquets
# Paquets de base : le binaire, les fichiers communs, les utilitaires
# (qemu-img) et les firmwares/BIOS.
BASE_PKGS="qemu-system-x86 qemu-system-common qemu-system-data qemu-utils"

# Bibliotheques de base du systeme : elles sont normalement deja la ;
# on ne les extrait JAMAIS (sinon on casse l'hote).
SYSTEM_LIBS="libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 librt.so.1
libstdc++.so.6 libgcc_s.so.1 ld-linux-x86-64.so.2 linux-vdso.so.1"

# Table de correspondance « soname -> paquet Debian » pour les
# dependances de QEMU les plus courantes.
soname_to_pkg() {
    case "$1" in
        libcapstone.so.5)      echo libcapstone5 ;;
        libfdt.so.1)           echo libfdt1 ;;
        libpixman-1.so.0)      echo libpixman-1-0 ;;
        libusbredirparser.so.1) echo libusbredirparser1 ;;
        libvdeplug.so.4)       echo libvdeplug4 ;;
        libspice-server.so.0)  echo libspice-server1 ;;
        libslirp.so.0)         echo libslirp0 ;;
        liburing.so.2)         echo liburing2 ;;
        libvulkan.so.1)        echo libvulkan1 ;;
        liblua5.3.so.0)        echo liblua5.3-0 ;;
        liblua5.4.so.0)        echo liblua5.4-0 ;;
        liblzo2.so.2)          echo liblzo2-2 ;;
        libglib-2.0.so.0)      echo libglib2.0-0 ;;
        libgobject-2.0.so.0)   echo libglib2.0-0 ;;
        libgio-2.0.so.0)       echo libglib2.0-0 ;;
        libgmodule-2.0.so.0)   echo libglib2.0-0 ;;
        libepoxy.so.0)         echo libepoxy0 ;;
        libgbm.so.1)           echo libgbm1 ;;
        libdrm.so.2)           echo libdrm2 ;;
        libxkbcommon.so.0)     echo libxkbcommon0 ;;
        libwayland-client.so.0) echo libwayland-client0 ;;
        libSDL2-2.0.so.0)      echo libsdl2-2.0-0 ;;
        libpulse.so.0)         echo libpulse0 ;;
        libpulse-simple.so.0)  echo libpulse0 ;;
        libasound.so.2)         echo libasound2 ;;
        libjack.so.0)          echo libjack-jackd2-0 ;;
        libz.so.1)             echo zlib1g ;;
        libpng16.so.16)        echo libpng16-16 ;;
        libjpeg.so.62)         echo libjpeg62-turbo ;;
        libsnappy.so.1)        echo libsnappy1v5 ;;
        libbrotlidec.so.1)     echo libbrotli1 ;;
        libbrotlicommon.so.1)  echo libbrotli1 ;;
        libexpat.so.1)         echo libexpat1 ;;
        libffi.so.8)           echo libffi8 ;;
        libpcre2-8.so.0)       echo libpcre2-8-0 ;;
        libmount.so.1)         echo libmount1 ;;
        libblkid.so.1)         echo libblkid1 ;;
        libselinux.so.1)       echo libselinux1 ;;
        libsystemd.so.0)       echo libsystemd0 ;;
        libudev.so.1)          echo libudev1 ;;
        libcap.so.2)           echo libcap2 ;;
        libgcrypt.so.20)       echo libgcrypt20 ;;
        libgpg-error.so.0)     echo libgpg-error0 ;;
        libassuan.so.6)        echo libassuan6 ;;
        libgpg.so.20)          echo libgpg20 ;;
        liblz4.so.1)           echo liblz4-1 ;;
        libzstd.so.1)          echo libzstd1 ;;
        liblzma.so.5)          echo liblzma5 ;;
        libbz2.so.1.0)         echo libbz2-1.0 ;;
        libncurses.so.6)       echo libncurses6 ;;
        libtinfo.so.6)         echo libtinfo6 ;;
        libbsd.so.0)           echo libbsd0 ;;
        libmd.so.0)            echo libmd0 ;;
        libsodium.so.23)       echo libsodium23 ;;
        libnuma.so.1)          echo libnuma1 ;;
        libseccomp.so.2)       echo libseccomp2 ;;
        libtasn1.so.6)         echo libtasn1-6 ;;
        libgnutls.so.30)       echo libgnutls30 ;;
        libp11-kit.so.0)       echo libp11-kit0 ;;
        libidn2.so.0)          echo libidn2-0 ;;
        libunistring.so.2)     echo libunistring2 ;;
        libssh2.so.1)          echo libssh2-1 ;;
        libcurl.so.4)          echo libcurl4 ;;
        libsasl2.so.2)         echo libsasl2-2 ;;
        libldap.so.2)          echo libldap-2.5-0 ;;
        liblber.so.2)          echo libldap-2.5-0 ;;
        libgssapi_krb5.so.2)   echo libgssapi-krb5-2 ;;
        libkrb5.so.3)          echo libkrb5-3 ;;
        libk5crypto.so.3)      echo libk5crypto3 ;;
        libkrb5support.so.0)  echo libkrb5support0 ;;
        libcom_err.so.2)       echo libcom-err2 ;;
        libkeyutils.so.1)      echo libkeyutils1 ;;
        libresolv.so.2)        echo libglib2.0-0 ;;
        libgio-2.0.so.0)       echo libglib2.0-0 ;;
        libX11.so.6)           echo libx11-6 ;;
        libXext.so.6)          echo libxext6 ;;
        libGL.so.1)            echo libgl1 ;;
        libGLX.so.0)           echo libglx0 ;;
        libEGL.so.1)           echo libegl1 ;;
        libudev.so.1)          echo libudev1 ;;
        *)                     echo "" ;;
    esac
}

is_system_lib() {
    local so="$1" s
    for s in $SYSTEM_LIBS; do
        [ "$so" = "$s" ] && return 0
    done
    return 1
}

# Devine le paquet a partir du nom de la bibliotheque : libfoo.so.3 ->
# libfoo3, libfoo-1.0, libfoo0, libfoo...
guess_pkg() {
    local so="$1" base stem i
    base=${so%%.so.*}
    stem=${base#lib}
    local cands="lib${stem}3 lib${stem}-1.0 lib${stem}0 lib${stem}1 lib${stem}2 lib${stem} ${stem}"
    for c in $cands; do
        if apt-cache show "$c" >/dev/null 2>&1; then
            printf '%s' "$c"
            return 0
        fi
    done
    return 1
}

# Telecharge et extrait un paquet dans $ROOT.
fetch_pkg() {
    local pkg="$1" before after deb
    apt-cache show "$pkg" >/dev/null 2>&1 || return 1
    before=$(ls -1 "$DEBS" 2>/dev/null || true)
    ( cd "$DEBS" && apt download "$pkg" ) >/dev/null 2>&1 || return 1
    after=$(ls -1 "$DEBS" 2>/dev/null || true)
    for deb in $after; do
        case " $before " in
            *" $deb "*) continue ;;
        esac
        dpkg-deb -x "$DEBS/$deb" "$ROOT" 2>/dev/null || true
    done
    return 0
}

# Liste les bibliotheques non resolues pour un binaire.
missing_libs() {
    local bin="$1" out
    [ -x "$bin" ] || return 0
    out=$(LD_LIBRARY_PATH="$ROOT/usr/lib/x86_64-linux-gnu:$ROOT/usr/lib/x86_64-linux-gnu:$ROOT/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}" \
          ldd "$bin" 2>/dev/null | awk '/not found/{print $1}')
    printf '%s' "$out"
}

LIBPATHS="$ROOT/usr/lib/x86_64-linux-gnu:$ROOT/usr/lib/x86_64-linux-gnu:$ROOT/lib/x86_64-linux-gnu"

log "Paquets de base"
for p in $BASE_PKGS; do
    if fetch_pkg "$p"; then
        info "telecharge : $p"
    else
        info "ignore (indisponible) : $p"
    fi
done

QEMU_BIN="$ROOT/usr/bin/qemu-system-x86_64"
[ -x "$QEMU_BIN" ] || die "qemu-system-x86_64 n'a pas ete extrait dans $ROOT."

round=1
while [ "$round" -le "$MAX_ROUNDS" ]; do
    missing=""
    for bin in "$ROOT/usr/bin/qemu-system-x86_64" "$ROOT/usr/bin/qemu-img"; do
        m=$(missing_libs "$bin")
        [ -n "$m" ] && missing="$missing $m"
    done
    [ -n "$(printf '%s' "$missing" | tr ' ' '\n' | grep -v '^$')" ] || break

    log "Bibliotheques manquantes (tour $round)"
    todo=""
    for so in $(printf '%s' "$missing" | tr ' ' '\n' | sort -u); do
        [ -n "$so" ] || continue
        if is_system_lib "$so"; then
            info "$so : bibliotheque systeme, on ne l'extrait pas"
            continue
        fi
        pkg=$(soname_to_pkg "$so")
        if [ -z "$pkg" ]; then
            pkg=$(guess_pkg "$so" || true)
        fi
        if [ -z "$pkg" ]; then
            info "$so : paquet introuvable automatiquement"
            continue
        fi
        info "$so -> $pkg"
        todo="$todo $pkg"
    done

    [ -n "$(printf '%s' "$todo" | tr ' ' '\n' | grep -v '^$')" ] || break

    progress=0
    for p in $(printf '%s' "$todo" | tr ' ' '\n' | sort -u); do
        if fetch_pkg "$p"; then
            info "extrait : $p"
            progress=1
        fi
    done
    [ "$progress" = "1" ] || break
    round=$(( round + 1 ))
done

# ------------------------------------------------------------- verification
log "Verification"
cat > "$ENVFILE" <<EOF
# Source this file before using QEMU (no root required).
export PATH="$ROOT/usr/bin:\$PATH"
export LD_LIBRARY_PATH="$LIBPATHS:\${LD_LIBRARY_PATH:-}"
EOF
info "environnement ecrit : $ENVFILE"

# shellcheck disable=SC1090
. "$ENVFILE"

if ! qemu-system-x86_64 --version >/dev/null 2>&1; then
    printf '\n'
    qemu-system-x86_64 --version 2>&1 | head -5 || true
    die "qemu-system-x86_64 ne demarre toujours pas (voir les .so manquants ci-dessus)."
fi
qemu-system-x86_64 --version | head -2 | sed 's/^/  /'
qemu-img --version | head -1 | sed 's/^/  /'

log "Acceleration materielle"
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    info "/dev/kvm est accessible : KVM sera utilise (demarrage rapide)."
elif [ -e /dev/kvm ]; then
    info "/dev/kvm existe mais n'est pas accessible par votre session."
    info "il faut l'ajouter au groupe « kvm » (droits administrateur) ou lancer :"
    info "  sudo chmod 666 /dev/kvm   # provisoire, a vos risques"
else
    info "/dev/kvm absent : pas d'acceleration, QEMU emulera le processeur."
    info "l'installation de Debian sera tres lente ; c'est le signe que votre"
    info "hote est une VM sans virtualisation imbriquee."
fi

printf '\n'
info "Pour utiliser QEMU dans un autre terminal :"
info "  source $ENVFILE"
info "Pour creer la VM Debian (sans root) :"
info "  bash ~/oc-176-podman/create-debian-vm.sh install"
