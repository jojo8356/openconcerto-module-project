#!/usr/bin/env sh
#
# Tests de scripts/installer-jar-release.sh.
#
# Le script d'installation pose le jar du module dans le dossier « Modules » du
# client. Un jar pose au mauvais endroit est ignore SILENCIEUSEMENT par
# OpenConcerto : ces tests verifient donc que le script
#   1. detecte un dossier Modules (y compris hors emplacements standards) ;
#   2. refuse un fichier qui n'est pas un module OpenConcerto ;
#   3. refuse un jar qui declare un autre module ;
#   4. n'ecrit rien en --dry-run ;
#   5. installe le jar et deplace l'ancien (un seul jar actif a la fin) ;
#   6. accepte --sans-remplacement (les deux jars restent) ;
#   7. sort en erreur quand aucun dossier Modules n'est trouve ;
#   8. --liste n'ecrit rien.
#
# Aucun OpenConcerto, aucune base de donnees, aucun JDK requis.
#
# Usage : sh tests/installer/test-installer-jar.sh
#
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SCRIPT="$ROOT_DIR/scripts/installer-jar-release.sh"
WORK_DIR=${WORK_DIR:-$(mktemp -d)}
MODULE_ID=org.openconcerto.modules.project

CONTROLES=0
ECHECS=0

ok() { CONTROLES=$((CONTROLES + 1)); printf 'OK     %s\n' "$1"; }
ko() { CONTROLES=$((CONTROLES + 1)); ECHECS=$((ECHECS + 1)); printf 'ECHEC  %s\n' "$1"; }

check() {
    description=$1
    expected=$2
    actual=$3
    if [ "$actual" = "$expected" ]; then
        ok "$description"
    else
        ko "$description (attendu : '$expected', obtenu : '$actual')"
    fi
}

command -v zip >/dev/null 2>&1 || { echo "zip est requis pour ces tests" >&2; exit 2; }
command -v unzip >/dev/null 2>&1 || { echo "unzip est requis pour ces tests" >&2; exit 2; }

# Fabrique un jar de module minimal : jar <fichier> <id> <version>
fabriquer_jar() {
    dir="$WORK_DIR/src-$3-$2"
    mkdir -p "$dir/META-INF"
    printf 'id=%s\nversion=%s\n' "$2" "$3" > "$dir/META-INF/openConcertoModule.properties"
    ( cd "$dir" && zip -q "$1" META-INF/openConcertoModule.properties )
}

# Fabrique un jar qui n'est pas un module (pas de META-INF/openConcertoModule.properties).
fabriquer_jar_quelconque() {
    dir="$WORK_DIR/src-quelconque"
    mkdir -p "$dir"
    printf 'hello\n' > "$dir/README.txt"
    ( cd "$dir" && zip -q "$1" README.txt )
}

# Prepare un dossier « Modules » propre.
preparer() {
    rm -rf "$WORK_DIR/$1"
    mkdir -p "$WORK_DIR/$1"
    printf '%s\n' "$WORK_DIR/$1"
}

echo "== 1. jar correct : installation et remplacement de l'ancien =="
MODULES=$(preparer modules-ok)
fabriquer_jar "$WORK_DIR/mod-1.0.jar" "$MODULE_ID" 1.0
fabriquer_jar "$WORK_DIR/mod-1.1.jar" "$MODULE_ID" 1.1
cp "$WORK_DIR/mod-1.0.jar" "$MODULES/${MODULE_ID}-1.0.jar"

sortie=$(sh "$SCRIPT" --jar "$WORK_DIR/mod-1.1.jar" --modules-dir "$MODULES" 2>&1) || true
check "le jar 1.1 est installe" "1" "$(ls "$MODULES"/${MODULE_ID}-1.1.jar 2>/dev/null | wc -l | tr -d ' ')"
check "il ne reste qu'un seul jar actif du module" "1" "$(ls "$MODULES"/${MODULE_ID}-*.jar 2>/dev/null | wc -l | tr -d ' ')"
check "l'ancien jar est sauvegarde, pas supprime" "1" "$(ls "$MODULES"/_backup_modules/${MODULE_ID}-1.0.jar 2>/dev/null | wc -l | tr -d ' ')"
case "$sortie" in
    *"version declaree           : 1.1"*) ok "la version lue dans le jar est affichee" ;;
    *) ko "la version du jar n'est pas affichee (sortie : $sortie)" ;;
esac

echo "== 2. --dry-run n'ecrit rien =="
MODULES=$(preparer modules-dry)
cp "$WORK_DIR/mod-1.0.jar" "$MODULES/${MODULE_ID}-1.0.jar"
sortie=$(sh "$SCRIPT" --jar "$WORK_DIR/mod-1.1.jar" --modules-dir "$MODULES" --dry-run 2>&1) || true
check "aucun jar 1.1 copie en dry-run" "0" "$(ls "$MODULES"/${MODULE_ID}-1.1.jar 2>/dev/null | wc -l | tr -d ' ')"
check "l'ancien jar est toujours en place" "1" "$(ls "$MODULES"/${MODULE_ID}-1.0.jar 2>/dev/null | wc -l | tr -d ' ')"
case "$sortie" in
    *"rien n'a ete ecrit"*) ok "le dry-run l'annonce clairement" ;;
    *) ko "le dry-run ne precise pas qu'il n'a rien ecrit" ;;
esac

echo "== 3. --sans-remplacement conserve les deux jars =="
MODULES=$(preparer modules-sans-remplacement)
cp "$WORK_DIR/mod-1.0.jar" "$MODULES/${MODULE_ID}-1.0.jar"
sh "$SCRIPT" --jar "$WORK_DIR/mod-1.1.jar" --modules-dir "$MODULES" --sans-remplacement >/dev/null 2>&1 || true
check "les deux jars sont presents" "2" "$(ls "$MODULES"/${MODULE_ID}-*.jar 2>/dev/null | wc -l | tr -d ' ')"

echo "== 4. --liste affiche sans installer =="
MODULES=$(preparer modules-liste)
cp "$WORK_DIR/mod-1.0.jar" "$MODULES/${MODULE_ID}-1.0.jar"
sortie=$(sh "$SCRIPT" --modules-dir "$MODULES" --liste 2>&1) || true
check "--liste signale le jar present" "1" "$(printf '%s' "$sortie" | grep -c "${MODULE_ID}-1.0.jar" | tr -d ' ')"
check "--liste n'installe rien" "0" "$(ls "$MODULES"/${MODULE_ID}-1.1.jar 2>/dev/null | wc -l | tr -d ' ')"

echo "== 5. fichiers refuses =="
MODULES=$(preparer modules-refus)
fabriquer_jar_quelconque "$WORK_DIR/pas-un-module.jar"
set +e
sortie=$(sh "$SCRIPT" --jar "$WORK_DIR/pas-un-module.jar" --modules-dir "$MODULES" 2>&1)
code=$?
set -e
if [ "$code" -ne 0 ] && printf '%s' "$sortie" | grep -q "pas un module OpenConcerto"; then
    ok "un jar sans metadonnees de module est refuse"
else
    ko "un jar sans metadonnees devrait etre refuse (code $code, sortie : $sortie)"
fi

fabriquer_jar "$WORK_DIR/autre-module.jar" org.openconcerto.modules.autre 1.1
set +e
sortie=$(sh "$SCRIPT" --jar "$WORK_DIR/autre-module.jar" --modules-dir "$MODULES" 2>&1)
code=$?
set -e
if [ "$code" -ne 0 ] && printf '%s' "$sortie" | grep -q "attend"; then
    ok "un jar d'un autre module est refuse"
else
    ko "un jar d'un autre module devrait etre refuse (code $code)"
fi
check "aucun jar n'a ete copie dans les cas refuses" "0" "$(ls "$MODULES"/*.jar 2>/dev/null | wc -l | tr -d ' ')"

echo "== 6. jar absent et dossier introuvable =="
set +e
sortie=$(sh "$SCRIPT" --jar "$WORK_DIR/inexistant.jar" --modules-dir "$MODULES" 2>&1)
code=$?
set -e
if [ "$code" -ne 0 ]; then ok "un jar inexistant provoque une erreur claire"; else ko "un jar inexistant devrait echouer"; fi

mkdir -p "$WORK_DIR/ailleurs"
set +e
sortie=$(sh "$SCRIPT" --jar "$WORK_DIR/mod-1.1.jar" --modules-dir "$WORK_DIR/ailleurs/pas-la" 2>&1)
code=$?
set -e
if [ "$code" -ne 0 ]; then ok "un dossier Modules inexistant provoque une erreur claire"; else ko "un dossier inexistant devrait echouer"; fi

echo "== 7. deux dossiers Modules : les deux sont servis =="
M1=$(preparer modules-multi-a)
M2=$(preparer modules-multi-b)
sh "$SCRIPT" --jar "$WORK_DIR/mod-1.1.jar" --modules-dir "$M1" --modules-dir "$M2" >/dev/null 2>&1 || true
check "jar present dans le premier dossier" "1" "$(ls "$M1"/${MODULE_ID}-1.1.jar 2>/dev/null | wc -l | tr -d ' ')"
check "jar present dans le second dossier" "1" "$(ls "$M2"/${MODULE_ID}-1.1.jar 2>/dev/null | wc -l | tr -d ' ')"

echo "== 8. le script ne touche pas la base =="
if grep -qE "(^|[|;&][[:space:]]*)psql([[:space:]]|$)|PGPASSWORD=" "$SCRIPT"; then
    ko "le script d'installation ne doit pas executer de SQL"
else
    ok "aucune commande SQL dans le script d'installation"
fi
case "$(grep -cE '^[[:space:]]*fix-module-version' "$SCRIPT")" in
    0) ok "le script ne lance pas fix-module-version (il ne fait que le conseiller)" ;;
    *) ko "le script ne doit pas lancer fix-module-version" ;;
esac

echo
echo "Controles : $CONTROLES | echecs : $ECHECS"
if [ "$ECHECS" -ne 0 ]; then
    echo "RESULTAT : ECHEC"
    exit 1
fi
echo "RESULTAT : OK"
