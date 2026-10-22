#!/usr/bin/env bash
# Prepare (and optionally publish) a release of the "project" module:
#   - bumps the version in module.properties
#   - compiles the jar (Java 8 bytecode)
#   - copies it to dist/
#   - with --publish: commit, tag, push and create the GitHub release
#     with the jar attached.
#
# usage:
#   bash scripts/build-release.sh --bump patch            # build only (no push)
#   bash scripts/build-release.sh --version 1.3 --publish # build + tag + GitHub release
#
# options:
#   --bump patch|minor|major  increment the version in module.properties
#   --version X.Y             set an explicit version (digits only, e.g. 1.3)
#   --notes TEXT              release notes (default: the commits since the last tag)
#   --notes-file FILE         read the release notes from a file
#   --publish                 commit + tag + push + create the GitHub release
#   --allow-main              autorise la publication depuis main/master
#   --no-build                do not compile (useful to test the version bump)
#   --no-changelog            do not touch CHANGELOG.md
#   --dry-run                 print what would be done, change nothing
#   --jar FILE                the OpenConcerto jar (default: auto-detected)
#   --help                    show this help
#
# The version format is the one expected by OpenConcerto: major.minor, digits
# only (OC parses "version" in module.properties with (\d+)(?:\.(\d+))? and
# refuses anything else).

set -eu
set -o pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"

MODULE_ID=""
CURRENT_VERSION=""
NEW_VERSION=""
BUMP=""
PUBLISH=0
ALLOW_MAIN=0
DO_BUILD=1
DO_CHANGELOG=1
DRY_RUN=0
OC_JAR=${OPENCONCERTO_JAR:-}
NOTES=""
NOTES_FILE=""
DIST_DIR="$ROOT_DIR/dist"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

log() { printf '%s\n' "$*"; }
die() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,30p' "$0"; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bump) BUMP=${2:-}; shift 2 ;;
    --version) NEW_VERSION=${2:-}; shift 2 ;;
    --notes) NOTES=${2:-}; shift 2 ;;
    --notes-file) NOTES_FILE=${2:-}; shift 2 ;;
    --publish) PUBLISH=1; shift ;;
    --allow-main) ALLOW_MAIN=1; shift ;;
    --no-build) DO_BUILD=0; shift ;;
    --no-changelog) DO_CHANGELOG=0; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --jar) OC_JAR=${2:-}; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) die "option inconnue : $1 (voir --help)" ;;
  esac
done

# --------------------------------------------------------------- version
MODULE_ID=$(awk -F= '/^id=/ { print $2; exit }' module.properties | tr -d '\r')
CURRENT_VERSION=$(awk -F= '/^version=/ { print $2; exit }' module.properties | tr -d '\r')
[ -n "$MODULE_ID" ] || die "id introuvable dans module.properties"
[ -n "$CURRENT_VERSION" ] || die "version introuvable dans module.properties"

valid_version() {
  printf '%s' "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?$'
}

bump_version() {
  # OC n'a que major.minor : "patch" incremente donc le numero mineur.
  local v=$1 kind=$2 major minor
  major=${v%%.*}
  minor=${v#*.}
  [ "$minor" = "$v" ] && minor=0
  case "$kind" in
    major) major=$((major + 1)); minor=0 ;;
    minor|patch) minor=$((minor + 1)) ;;
    *) die "type de bump inconnu : $kind" ;;
  esac
  printf '%s.%s' "$major" "$minor"
}

if [ -n "$BUMP" ]; then
  [ -z "$NEW_VERSION" ] || die "--bump et --version sont exclusifs"
  if [ -n "$(git status --porcelain -- module.properties)" ]; then
    die "module.properties a deja des modifications non commitées (version $CURRENT_VERSION).
  Relance avec --version $CURRENT_VERSION pour publier cette version, ou
  commite d'abord le changement de version."
  fi
  NEW_VERSION=$(bump_version "$CURRENT_VERSION" "$BUMP")
elif [ -z "$NEW_VERSION" ]; then
  NEW_VERSION="$CURRENT_VERSION"
fi

valid_version "$NEW_VERSION" || die "version invalide : '$NEW_VERSION' (chiffres uniquement, ex. 1.3)"
[ "$NEW_VERSION" = "$CURRENT_VERSION" ] && log "Version inchangée : $CURRENT_VERSION"

TAG="v$NEW_VERSION"
JAR_NAME="$MODULE_ID-$NEW_VERSION.jar"

# ------------------------------------------------------- ecriture version
set_module_version() {
  local content
  content=$(cat module.properties)
  case "$content" in
    *"version=$CURRENT_VERSION"*) : ;;
    *) die "version $CURRENT_VERSION introuvable dans module.properties" ;;
  esac
  content=${content//version=$CURRENT_VERSION/version=$NEW_VERSION}
  printf '%s\n' "$content" > module.properties
  log "module.properties : version $CURRENT_VERSION -> $NEW_VERSION"
}

# ------------------------------------------------------- notes de release
default_notes() {
  local last_tag
  last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
  if [ -n "$last_tag" ]; then
    printf 'Module project %s\n\n' "$NEW_VERSION"
    git log --pretty='- %s' "$last_tag"..HEAD | head -40
  else
    printf 'Module project %s\n' "$NEW_VERSION"
    git log --pretty='- %s' -n 20 HEAD
  fi
}

# --------------------------------------------------------------- build
detect_oc_jar() {
  if [ -n "$OC_JAR" ]; then
    [ -f "$OC_JAR" ] || die "jar OpenConcerto introuvable : $OC_JAR"
    return
  fi
  local candidate
  for candidate in \
    /opt/openconcerto/OpenConcerto.jar \
    /opt/openconcerto/lib/OpenConcerto.jar \
    /opt/openconcerto/OpenConcerto-1.7*.jar \
    /usr/share/openconcerto/OpenConcerto.jar \
    "$HOME"/OpenConcerto*/OpenConcerto.jar \
    "$HOME"/OpenConcerto*/lib/OpenConcerto.jar
  do
    if [ -f "$candidate" ]; then
      OC_JAR="$candidate"
      return
    fi
  done
  OC_JAR=$(find "$HOME" /opt /usr/share -maxdepth 5 -iname 'openconcerto*.jar' -size +2M 2>/dev/null | head -1 || true)
  [ -n "$OC_JAR" ] || die "jar OpenConcerto introuvable. Utilise --jar /chemin/OpenConcerto.jar"
}

check_jar_contents() {
  local jar=$1 tmp extracted
  tmp=$(mktemp -d)
  if command -v unzip >/dev/null 2>&1; then
    extracted=$(unzip -p "$jar" META-INF/openConcertoModule.properties 2>/dev/null || true)
  else
    (cd "$tmp" && jar xf "$jar" META-INF/openConcertoModule.properties 2>/dev/null || true)
    if [ -f "$tmp/META-INF/openConcertoModule.properties" ]; then
      extracted=$(cat "$tmp/META-INF/openConcertoModule.properties")
    fi
  fi
  rm -rf "$tmp"
  if [ -z "$extracted" ]; then
    log "ATTENTION : module.properties introuvable dans le jar (verification ignoree)"
    return
  fi
  printf '%s\n' "$extracted" | grep -q "^version=$NEW_VERSION" \
    || die "le jar contient une autre version : $(printf '%s' "$extracted" | tr '\n' ' ')"
  log "Jar verifie : META-INF/openConcertoModule.properties version=$NEW_VERSION"
}

update_changelog() {
  local file="$ROOT_DIR/CHANGELOG.md"
  [ -f "$file" ] || return 0
  if grep -q "^## Module project $NEW_VERSION " "$file"; then
    log "CHANGELOG.md : la section $NEW_VERSION existe deja"
    return 0
  fi
  local section
  section=$(default_notes)
  local tmp
  tmp=$(mktemp)
  {
    printf '## Module project %s - %s\n\n' "$NEW_VERSION" "$(date +%F)"
    printf '%s\n\n' "$section"
    cat "$file"
  } > "$tmp"
  mv "$tmp" "$file"
  log "CHANGELOG.md : section $NEW_VERSION ajoutee"
}

# --------------------------------------------------------------- actions
if [ "$DRY_RUN" -eq 1 ]; then
  log "DRY RUN : version $CURRENT_VERSION -> $NEW_VERSION ; tag $TAG ; jar $DIST_DIR/$JAR_NAME"
  if [ "$PUBLISH" -eq 1 ]; then
    log "DRY RUN : commit + tag + push + release GitHub"
  fi
  exit 0
fi

if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
  set_module_version
fi
if [ "$DO_CHANGELOG" -eq 1 ]; then
  update_changelog
fi

JAR_BUILT=""
if [ "$DO_BUILD" -eq 1 ]; then
  detect_oc_jar
  log "Jar OpenConcerto : $OC_JAR"
  BUILD_DIR="$ROOT_DIR/build" OPENCONCERTO_JAR="$OC_JAR" sh "$ROOT_DIR/scripts/build-java8-compatible.sh" > "$ROOT_DIR/build/release-build.log" 2>&1 \
    || { cat "$ROOT_DIR/build/release-build.log" >&2; die "compilation echouee (voir build/release-build.log)"; }
  JAR_BUILT="$ROOT_DIR/build/$JAR_NAME"
  [ -f "$JAR_BUILT" ] || die "jar attendu introuvable : $JAR_BUILT"
  check_jar_contents "$JAR_BUILT"
  mkdir -p "$DIST_DIR"
  cp -f "$JAR_BUILT" "$DIST_DIR/$JAR_NAME"
  log "Jar de release : $DIST_DIR/$JAR_NAME"
else
  log "Compilation ignoree (--no-build)"
fi

if [ "$PUBLISH" -eq 0 ]; then
  log ""
  log "Release preparee (non publiee). Pour publier :"
  log "  bash scripts/build-release.sh --version $NEW_VERSION --publish"
  exit 0
fi

# ------------------------------------------------------------- publication
[ -n "$BRANCH" ] || die "branche introuvable (HEAD detache ?)"
case "$BRANCH" in
  main|master)
    if [ "$ALLOW_MAIN" -eq 0 ]; then
      die "publier directement sur $BRANCH est interdit (utilise --allow-main si c'est voulu).
  Astuce : git checkout -b release/v$NEW_VERSION puis relance la publication."
    fi
    log "ATTENTION : publication depuis $BRANCH"
    ;;
esac

if [ -n "$(git status --porcelain -- module.properties CHANGELOG.md)" ]; then
  git add module.properties CHANGELOG.md 2>/dev/null || true
  git commit -m "Bump the module to $NEW_VERSION" || die "commit echoue"
fi

if git rev-parse "refs/tags/$TAG" >/dev/null 2>&1; then
  die "le tag $TAG existe deja : incrementez la version (un numero de version ne se reutilise jamais)"
fi

git tag -a "$TAG" -m "Module project $NEW_VERSION"
git push origin "$BRANCH"
git push origin "$TAG"

NOTES_TMP=""
cleanup() { [ -n "$NOTES_TMP" ] && rm -f "$NOTES_TMP"; }
trap cleanup EXIT

if [ -n "$NOTES_FILE" ]; then
  [ -f "$NOTES_FILE" ] || die "fichier de notes introuvable : $NOTES_FILE"
  NOTES_TMP=$(mktemp)
  cp "$NOTES_FILE" "$NOTES_TMP"
elif [ -n "$NOTES" ]; then
  NOTES_TMP=$(mktemp)
  printf '%s\n' "$NOTES" > "$NOTES_TMP"
else
  NOTES_TMP=$(mktemp)
  default_notes > "$NOTES_TMP"
fi

if command -v gh >/dev/null 2>&1; then
  [ -f "$DIST_DIR/$JAR_NAME" ] || die "jar introuvable : $DIST_DIR/$JAR_NAME (relance sans --no-build)"
  gh release create "$TAG" --title "Module project $NEW_VERSION" --notes-file "$NOTES_TMP" "$DIST_DIR/$JAR_NAME"
  log "Release GitHub creee : $TAG"
else
  log "gh absent : cree la release a la main :"
  log "  git push origin $TAG"
  log "  gh release create $TAG --title \"Module project $NEW_VERSION\" --notes-file <fichier> $DIST_DIR/$JAR_NAME"
  log "  (ou : https://github.com/jojo8356/openconcerto-module-project/releases/new)"
fi

log ""
log "Release $NEW_VERSION publiee (tag $TAG)."
log "Installation chez le client : copier $JAR_NAME dans le dossier Modules du client, puis redemarrer le client."
