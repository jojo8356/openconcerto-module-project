#!/usr/bin/env bash
# Construit le jar du module "project" avec le JDK de ce poste, puis
# l'installe dans le dossier Modules du client OpenConcerto de ce poste.
#
# usage :
#   bash scripts/build-module-client.sh              # compile + installe
#   bash scripts/build-module-client.sh --no-install # compile seulement
#   bash scripts/build-module-client.sh --jar /chemin/OpenConcerto.jar
#
# Le jar OpenConcerto et le dossier Modules du client sont detectes
# automatiquement ; ils peuvent aussi etre forces par les variables
# d'environnement OPENCONCERTO_JAR et CLIENT_MODULES_DIR.

set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR=${BUILD_DIR:-"$ROOT_DIR/build"}
INSTALL=1
OC_JAR=${OPENCONCERTO_JAR:-}
CLIENT_MODULES=${CLIENT_MODULES_DIR:-}

log() { printf '%s\n' "$*"; }
die() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-install) INSTALL=0; shift ;;
    --jar) OC_JAR=${2:-}; shift 2 ;;
    --modules) CLIENT_MODULES=${2:-}; shift 2 ;;
    --help|-h) sed -n '2,14p' "$0"; exit 0 ;;
    *) die "option inconnue : $1 (voir --help)" ;;
  esac
done

# ---------------------------------------------------------------- outils
command -v javac >/dev/null 2>&1 || die "javac introuvable : il faut un JDK complet (pas seulement un JRE)."
command -v jar >/dev/null 2>&1 || die "commande 'jar' introuvable : le JDK est incomplet."
log "JDK : $(javac -version 2>&1 | head -1)"

# ------------------------------------------------- 1. jar OpenConcerto
if [ -n "$OC_JAR" ]; then
  [ -f "$OC_JAR" ] || die "jar OpenConcerto introuvable : $OC_JAR"
else
  for candidate in \
    /opt/openconcerto/OpenConcerto.jar \
    /opt/openconcerto/lib/OpenConcerto.jar \
    /opt/openconcerto/OpenConcerto-1.7*.jar \
    /usr/share/openconcerto/OpenConcerto.jar \
    "$HOME"/OpenConcerto*/OpenConcerto.jar \
    "$HOME"/OpenConcerto*/lib/OpenConcerto.jar \
    "$HOME"/OpenConcerto*/OpenConcerto-1.7*.jar \
    "$HOME"/OpenConcerto*/openconcerto-1.7*.jar \
    "$HOME"/OpenConcerto*/oc/OpenConcerto.jar
  do
    if [ -f "$candidate" ]; then
      OC_JAR="$candidate"
      break
    fi
  done
  if [ -z "$OC_JAR" ]; then
    OC_JAR=$(find "$HOME" /opt /usr/share -maxdepth 5 -iname 'openconcerto*.jar' -size +2M 2>/dev/null | head -1 || true)
  fi
  [ -n "$OC_JAR" ] || die "jar OpenConcerto introuvable. Cherche-le avec :
  find \"\$HOME\" -maxdepth 5 -iname 'openconcerto*.jar' -size +2M
  puis relance avec : --jar /chemin/du/jar"
fi
log "Jar OpenConcerto  : $OC_JAR"

# ------------------------------------------- 2. dossier Modules client
# OpenConcerto lit ses modules dans le dossier "Modules" RELATIF au
# repertoire de lancement du client (Gestion.MODULES_DIR). On installe donc
# dans tous les dossiers Modules connus : le bon sera celui du client.
if [ -z "$CLIENT_MODULES" ]; then
  for candidate in \
    "$(dirname -- "$OC_JAR")"/Modules \
    /opt/openconcerto/Modules \
    /usr/share/openconcerto/Modules \
    "$HOME"/OpenConcerto*/Modules \
    "$HOME"/OpenConcerto*/modules
  do
    if [ -d "$candidate" ]; then
      CLIENT_MODULES="$candidate"
      break
    fi
  done
fi
if [ -z "$CLIENT_MODULES" ]; then
  CLIENT_MODULES=$(find "$HOME" -maxdepth 5 -type d -name Modules 2>/dev/null | head -1 || true)
fi
if [ -z "$CLIENT_MODULES" ]; then
  log "Dossier Modules du client introuvable : compilation seulement (pas d'installation)."
  INSTALL=0
else
  log "Dossier Modules   : $CLIENT_MODULES"
fi

# ------------------------------------------------------- 3. compilation
log "Compilation du module (bytecode Java 8)..."
mkdir -p "$BUILD_DIR"
OPENCONCERTO_JAR="$OC_JAR" BUILD_DIR="$BUILD_DIR" sh "$ROOT_DIR/scripts/build-java8-compatible.sh"

JAR_FILE=$(ls -t "$BUILD_DIR"/*.jar 2>/dev/null | head -1 || true)
[ -n "$JAR_FILE" ] || die "aucun jar produit dans $BUILD_DIR"
log "Jar construit      : $JAR_FILE"

# ------------------------------------------------------ 4. installation
if [ "$INSTALL" -eq 1 ]; then
  installed=0
  # Tous les dossiers de modules connus du client (voir la fenetre
  # « Informations » du client OC) : celui du repertoire de lancement et
  # celui du dossier de donnees applicatif.
  for target in "$CLIENT_MODULES" \
    /opt/openconcerto/Modules \
    "$HOME"/.local/share/OpenConcerto/Modules \
    "$HOME"/OpenConcerto*/Modules
  do
    [ -n "$target" ] || continue
    if [ ! -d "$target" ]; then
      mkdir -p "$target" 2>/dev/null || true
    fi
    [ -d "$target" ] || continue
    if cp -f "$JAR_FILE" "$target/" 2>/dev/null; then
      log "Jar installe dans  : $target"
      installed=$((installed + 1))
    else
      log "Ecriture impossible dans $target (droits insuffisants)."
      log "  sudo cp \"$JAR_FILE\" \"$target/\""
    fi
  done
  if [ "$installed" -eq 0 ]; then
    log "Aucun dossier Modules installable : copie manuelle :"
    log "  sudo cp \"$JAR_FILE\" \"<dossier Modules du client>/\""
  fi
  log "Redemarre le client OpenConcerto, puis fais le test graphique."
  log ""
  log "IMPORTANT : la base garde la version du module installe. Si le client refuse"
  log "de demarrer (NO_FACTORY), aligne la base sur la nouvelle version :"
  log "  bash scripts/fix-module-version.* --mode docker --stack ~/oc-176-docker --apply"
else
  log "Installation dans le client non effectuee."
fi
