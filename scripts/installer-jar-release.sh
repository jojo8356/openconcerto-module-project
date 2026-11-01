#!/usr/bin/env sh
#
# Installe (ou met a jour) le jar du module « project » dans le client
# OpenConcerto de ce poste.
#
# Le piege principal : OpenConcerto lit ses modules dans le dossier « Modules »
# (majuscule) RELATIF au repertoire de lancement du client
# (Gestion.MODULES_DIR = new File("Modules")). Un jar copie ailleurs est
# ignore SILENCIEUSEMENT : pas d'erreur, le module n'apparait simplement pas.
# Ce script copie donc dans tous les dossiers « Modules » connus, et retire
# l'ancien jar du meme module pour n'en laisser qu'un seul actif.
#
# Usage :
#   sh scripts/installer-jar-release.sh                       # dernier jar de ~/Downloads
#   sh scripts/installer-jar-release.sh --jar ~/Downloads/org.openconcerto.modules.project-1.1.jar
#   sh scripts/installer-jar-release.sh --modules-dir /opt/openconcerto/Modules
#   sh scripts/installer-jar-release.sh --liste               # ou sont les dossiers ?
#   sh scripts/installer-jar-release.sh --dry-run             # montre sans ecrire
#
# Options :
#   --jar FILE          jar a installer (defaut : le plus recent de ~/Downloads
#                       ou du dossier courant, motif org.openconcerto.modules.project-*.jar)
#   --modules-dir DIR   dossier « Modules » cible (repetable) ; sinon detection
#   --liste             affiche les dossiers detectes et les jars du module, puis sort
#   --sans-remplacement ne deplace pas l'ancien jar (les deux resteront presents)
#   --backup-dir DIR    ou deplacer les anciens jars (defaut : <dir>/_backup_modules)
#   --dry-run           n'ecrit rien, affiche les actions
#
# Ce script ne touche PAS a la base de donnees : il ne fait que poser le jar.
# Si le client refuse de demarrer (NO_FACTORY), voir docs/release-process.md §5.1
# et scripts/fix-module-version.sh.
#
set -eu

MODULE_ID=org.openconcerto.modules.project
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
JAR=""
LISTE=0
REMPLACER=1
DRY=0
BACKUP_DIR=""
MODULES_DIRS=""

die() { printf 'ERREUR : %s\n' "$1" >&2; exit 1; }
info() { printf '  %s\n' "$1"; }
log() { printf '\n== %s\n' "$1"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --jar) JAR=${2:-}; shift 2 ;;
        --modules-dir) MODULES_DIRS="$MODULES_DIRS $(printf '%s' "${2:-}")"; shift 2 ;;
        --liste|--list) LISTE=1; shift ;;
        --sans-remplacement) REMPLACER=0; shift ;;
        --backup-dir) BACKUP_DIR=${2:-}; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) awk 'NR > 1 && $0 == "set -eu" { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
        *) die "option inconnue : $1 (--help pour l'aide)" ;;
    esac
done

# ------------------------------------------------- 1. dossiers « Modules »
# Ordre : ceux du client (relatifs au jar d'OpenConcerto), puis les
# emplacements standards, puis le dossier de donnees applicatif.
detect_dirs() {
    for candidate in \
        ${MODULES_DIRS:-} \
        /opt/openconcerto/Modules \
        /usr/share/openconcerto/Modules \
        /usr/local/openconcerto/Modules \
        "$HOME"/.local/share/OpenConcerto/Modules \
        "$HOME"/OpenConcerto*/Modules \
        "$HOME"/OpenConcerto*/modules \
        "$HOME"/Bureau/OpenConcerto*/Modules \
        "$HOME"/Desktop/OpenConcerto*/Modules \
        "$HOME"/Downloads/OpenConcerto*/Modules \
        "$HOME"/Telechargements/OpenConcerto*/Modules
    do
        [ -n "$candidate" ] || continue
        [ -d "$candidate" ] && printf '%s\n' "$candidate"
    done | awk '!seen[$0]++'
}

# Dossier Modules a cote du jar d'OpenConcerto, s'il est trouvable.
detect_from_oc_jar() {
    for jar in \
        /opt/openconcerto/OpenConcerto.jar \
        /usr/share/openconcerto/OpenConcerto.jar \
        "$HOME"/OpenConcerto*/OpenConcerto.jar \
        "$HOME"/OpenConcerto*/lib/OpenConcerto.jar \
        "$HOME"/Bureau/OpenConcerto*/OpenConcerto.jar \
        "$HOME"/Downloads/OpenConcerto*/OpenConcerto.jar
    do
        if [ -f "$jar" ]; then
            dir=$(dirname -- "$jar")
            [ -d "$dir/Modules" ] && printf '%s\n' "$dir/Modules"
        fi
    done
}

DIRS=$( { detect_from_oc_jar; detect_dirs; } | awk '!seen[$0]++')

if [ -z "$DIRS" ]; then
    printf 'Aucun dossier « Modules » detecte automatiquement.\n\n' >&2
    printf 'Lis le bon chemin DANS le client : menu « ? / Aide » -> « Informations »\n' >&2
    printf '-> ligne « Dossiers des modules ». Puis :\n\n' >&2
    printf '  sh %s --jar <le jar telecharge> --modules-dir=/le/chemin/Modules\n\n' "$0" >&2
    exit 1
fi

# ------------------------------------------------------------- 2. le jar
if [ "$LISTE" -eq 0 ] && [ -z "$JAR" ]; then
    for base in "$HOME/Downloads" "$HOME/Telechargements" "$HOME/Bureau" "$HOME/Desktop" "$ROOT_DIR" "$ROOT_DIR/build" "$(pwd)"; do
        [ -d "$base" ] || continue
        found=$(ls -t "$base"/${MODULE_ID}-*.jar 2>/dev/null | head -n 1 || true)
        if [ -n "$found" ]; then
            JAR=$found
            break
        fi
    done
fi

if [ "$LISTE" -eq 0 ]; then
    [ -n "$JAR" ] || die "jar introuvable : passe --jar /chemin/org.openconcerto.modules.project-1.1.jar"
    [ -f "$JAR" ] || die "jar absent : $JAR"
fi

log "Dossiers « Modules » detectes"
printf '%s\n' "$DIRS" | while IFS= read -r dir; do
    info "$dir"
    jars=$(ls "$dir"/${MODULE_ID}-*.jar 2>/dev/null || true)
    if [ -n "$jars" ]; then
        printf '%s\n' "$jars" | while IFS= read -r old; do
            info "    present : $(basename -- "$old")"
        done
    else
        info "    (aucun jar ${MODULE_ID})"
    fi
done

if [ "$LISTE" -eq 1 ]; then
    exit 0
fi

# ------------------------------------------------- 3. controle du jar
log "Controle du jar"
info "$JAR"

VERSION_IN_JAR=""
if command -v unzip >/dev/null 2>&1; then
    VERSION_IN_JAR=$(unzip -p "$JAR" META-INF/openConcertoModule.properties 2>/dev/null | tr -d '\r' | awk -F= '/^version=/ { print $2; exit }' || true)
    MODULE_IN_JAR=$(unzip -p "$JAR" META-INF/openConcertoModule.properties 2>/dev/null | tr -d '\r' | awk -F= '/^id=/ { print $2; exit }' || true)
    if [ -z "$MODULE_IN_JAR" ]; then
        die "$(basename -- "$JAR") ne contient pas META-INF/openConcertoModule.properties : ce n'est pas un module OpenConcerto."
    fi
    info "module declare dans le jar : $MODULE_IN_JAR"
    case "$MODULE_IN_JAR" in
        "$MODULE_ID") : ;;
        *) die "le jar declare le module « $MODULE_IN_JAR », attendu « $MODULE_ID »." ;;
    esac
    info "version declaree           : ${VERSION_IN_JAR:-inconnue}"
fi

# Bytecode Java 8 : le client tourne sur JRE 8 ou plus.
if [ -x "$ROOT_DIR/scripts/verify-java8-bytecode.sh" ] && command -v jar >/dev/null 2>&1; then
    if sh "$ROOT_DIR/scripts/verify-java8-bytecode.sh" "$JAR" >/dev/null 2>&1; then
        info "bytecode Java 8            : OK"
    else
        printf '  ATTENTION : le controle de bytecode Java 8 a echoue (jar recent ?).\n'
    fi
else
    info "bytecode Java 8            : non verifie (jar/JDK absent)"
fi

# ------------------------------------------------------- 4. installation
# Nom d'arrivee : la convention du client et de tous les scripts du depot est
# <id du module>-<version>.jar. On renomme donc si la version est connue.
if [ -n "${VERSION_IN_JAR:-}" ]; then
    JAR_NAME="${MODULE_ID}-${VERSION_IN_JAR}.jar"
else
    JAR_NAME=$(basename -- "$JAR")
fi
if [ "$JAR_NAME" != "$(basename -- "$JAR")" ]; then
    info "nom d'arrivee             : $JAR_NAME (convention du client)"
fi
TOTAL=0
while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    log "Installation dans $dir"

    if [ "$REMPLACER" -eq 1 ]; then
        backup=${BACKUP_DIR:-"$dir/_backup_modules"}
        for old in "$dir"/${MODULE_ID}-*.jar; do
            [ -f "$old" ] || continue
            case "$(basename -- "$old")" in
                "$JAR_NAME") continue ;;
            esac
            if [ "$DRY" -eq 1 ]; then
                info "[dry-run] deplacerait $(basename -- "$old") vers $backup/"
            else
                mkdir -p "$backup" 2>/dev/null || true
                if mv -f "$old" "$backup/" 2>/dev/null; then
                    info "ancien jar deplace : $(basename -- "$old") -> $backup/"
                else
                    info "ATTENTION : impossible de deplacer $(basename -- "$old") (droits ?)"
                fi
            fi
        done
    fi

    if [ "$DRY" -eq 1 ]; then
        info "[dry-run] copierait $JAR_NAME dans $dir/"
        TOTAL=$((TOTAL + 1))
    elif cp -f "$JAR" "$dir/$JAR_NAME" 2>/dev/null; then
        info "installe : $dir/$JAR_NAME"
        TOTAL=$((TOTAL + 1))
    else
        info "ecriture impossible (droits insuffisants). Relancer avec :"
        info "  sudo cp \"$JAR\" \"$dir/\""
    fi
done <<EOF
$DIRS
EOF

log "Resultat"
if [ "$TOTAL" -eq 0 ]; then
    printf 'Aucune copie effectuee.\n' >&2
    exit 1
fi
if [ "$DRY" -eq 1 ]; then
    info "[dry-run] rien n'a ete ecrit : $TOTAL dossier(s) seraient mis a jour avec $JAR_NAME"
    printf '\nRelancer sans --dry-run pour installer reellement.\n'
    exit 0
fi
info "jar installe dans $TOTAL dossier(s) : $JAR_NAME"
info "version du module : ${VERSION_IN_JAR:-voir module.properties}"
printf '\nEtapes suivantes :\n'
printf '  1. Redemarrer le client OpenConcerto (le module est lu au demarrage).\n'
printf '  2. Verifier dans « Informations » -> « Gestion des modules » que le\n'
printf '     module est liste en %s, et lire la ligne « Dossiers des modules ».\n' "${VERSION_IN_JAR:-1.1}"
printf '  3. Verifier la console du client :\n'
printf '       [module project] colonnes ID_AFFAIRE creees : [...]   <- normal\n'
printf '     puis tester : Achats > Commandes fournisseurs (colonne « Affaire »).\n'
printf '\nSi le client refuse de demarrer (NO_FACTORY) : la base epingle une autre\n'
printf 'version du module. Voir docs/release-process.md section 5.1 :\n'
printf '  bash scripts/fix-module-version.sh --mode docker --stack ~/oc-176-docker\n'
printf '\nRecette graphique : docs/recette-graphique-affaire-fournisseur.md\n'
