#!/usr/bin/env sh
# =====================================================================
# Construit le jar du module en récupérant OpenConcerto.jar avec curl.
#
# Usage :
#   sh scripts/build-jar-with-curl.sh
#
# Le script, dans l'ordre :
#   1. réutilise $OPENCONCERTO_JAR s'il est défini et existe ;
#   2. sinon réutilise /opt/openconcerto/OpenConcerto.jar s'il existe ;
#   3. sinon télécharge l'archive officielle OpenConcerto 1.7.6
#      (multiposte, ~100 Mo) avec curl, l'extrait dans
#      build/openconcerto-dist/ et utilise le OpenConcerto.jar extrait ;
#   4. lance scripts/build-java8-compatible.sh.
#
# Résultat : build/org.openconcerto.modules.project-<version>.jar
# (version lue dans module.properties, actuellement 1.1).
#
# Variables optionnelles :
#   OPENCONCERTO_JAR      chemin d'un OpenConcerto.jar déjà présent
#   OPENCONCERTO_VERSION  défaut : 1.7.6
#   OPENCONCERTO_ZIP_URL  URL de l'archive à télécharger (zip)
#   CACHE_DIR             défaut : build/openconcerto-dist
#   SKIP_BUILD=1          télécharge/extrait seulement, sans builder
#
# Prérequis : curl, unzip, et un JDK (javac) pour l'étape de build.
# Le téléchargement n'est fait qu'une fois : l'archive et son contenu
# sont conservés dans build/ (ignoré par Git).
# =====================================================================
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OPENCONCERTO_VERSION=${OPENCONCERTO_VERSION:-1.7.6}
OPENCONCERTO_ZIP_URL=${OPENCONCERTO_ZIP_URL:-"https://www.openconcerto.org/fr/telechargement/1.7/OpenConcerto-${OPENCONCERTO_VERSION}-multiposte.zip"}
CACHE_DIR=${CACHE_DIR:-"$ROOT_DIR/build/openconcerto-dist"}
ZIP_FILE="$CACHE_DIR/$(basename "$OPENCONCERTO_ZIP_URL")"
EXTRACT_DIR="$CACHE_DIR/extracted"

die() {
    echo "ERREUR : $1" >&2
    exit 1
}

if [ -n "${OPENCONCERTO_JAR:-}" ] && [ -f "${OPENCONCERTO_JAR}" ]; then
    echo "OpenConcerto.jar fourni : $OPENCONCERTO_JAR"
elif [ -f /opt/openconcerto/OpenConcerto.jar ]; then
    OPENCONCERTO_JAR=/opt/openconcerto/OpenConcerto.jar
    echo "OpenConcerto.jar trouvé : $OPENCONCERTO_JAR"
else
    command -v curl >/dev/null 2>&1 || die "curl est requis"
    command -v unzip >/dev/null 2>&1 || die "unzip est requis"

    mkdir -p "$CACHE_DIR"
    if [ ! -f "$ZIP_FILE" ]; then
        echo "Téléchargement de $OPENCONCERTO_ZIP_URL ..."
        curl -fL --retry 3 --connect-timeout 30 -o "$ZIP_FILE.part" "$OPENCONCERTO_ZIP_URL" \
            || die "téléchargement impossible (vérifie l'URL ou la connexion)"
        mv "$ZIP_FILE.part" "$ZIP_FILE"
    else
        echo "Archive déjà téléchargée : $ZIP_FILE"
    fi

    if [ ! -d "$EXTRACT_DIR" ]; then
        echo "Extraction de $(basename "$ZIP_FILE") ..."
        rm -rf "$EXTRACT_DIR.tmp"
        mkdir -p "$EXTRACT_DIR.tmp"
        unzip -q "$ZIP_FILE" -d "$EXTRACT_DIR.tmp" || die "extraction impossible"
        mv "$EXTRACT_DIR.tmp" "$EXTRACT_DIR"
    fi

    OPENCONCERTO_JAR=$(find "$EXTRACT_DIR" -name OpenConcerto.jar -type f 2>/dev/null | head -n 1)
    [ -n "$OPENCONCERTO_JAR" ] || die "OpenConcerto.jar introuvable dans l'archive extraite ($EXTRACT_DIR)"
    echo "OpenConcerto.jar extrait : $OPENCONCERTO_JAR"
fi

export OPENCONCERTO_JAR

if [ "${SKIP_BUILD:-0}" = "1" ]; then
    echo "SKIP_BUILD=1 : build non lancé. OPENCONCERTO_JAR=$OPENCONCERTO_JAR"
    exit 0
fi

command -v javac >/dev/null 2>&1 || die "javac est requis pour builder (installer un JDK 8+)"

echo "Build du module..."
sh "$ROOT_DIR/scripts/build-java8-compatible.sh"
