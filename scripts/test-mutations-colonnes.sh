#!/usr/bin/env sh
#
# Tests de mutation des « libelles de colonnes ».
#
# Un test ne vaut que s'il sait echouer. Ce script introduit volontairement des
# regressions dans une COPIE du depot, puis verifie que la suite les detecte.
# Si une mutation passe inapercue, le script sort en erreur : cela signifie que
# le test correspondant ne protege rien.
#
# Mutations appliquees :
#   1. le libelle automatique ne retire plus le prefixe ID_ (le cas Gisèle)
#   2. le mode AUTO est ignore
#   3. les superutilisateurs ne sont plus prioritaires pour le menu
#   4. la requete SQL du module derive de la reference SQL
#   5. l'index unique des libelles devient un index simple (doublons possibles)
#   6. l'enregistrement n'est plus transactionnel
#   7. un utilisateur inconnu n'est plus traite comme « a reessayer » (le menu
#      des libelles disparait pour tout le monde, y compris l'administrateur)
#   8. la case « Libellé affiché » redevient vide quand aucune regle n'existe
#      (c'est ce que voyait l'utilisateur avant le correctif d'edition)
#   9. une edition sans changement cree quand meme une regle (table polluee)
#  10. le libelle affiche repasse en gris pale (illisible a l'ecran)
#
# Prerequis : un JDK (javac/java) pour les mutations 1 a 4 et 6 ; node + pglite
# pour la mutation 5. Les mutations non executables sont sautees proprement.
#
# Usage : sh scripts/test-mutations-colonnes.sh
#
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK_DIR=${WORK_DIR:-$(mktemp -d)}
CONTROLES=0
ECHECS=0

ok() { CONTROLES=$((CONTROLES + 1)); printf 'OK     %s\n' "$1"; }
ko() { CONTROLES=$((CONTROLES + 1)); ECHECS=$((ECHECS + 1)); printf 'ECHEC  %s\n' "$1"; }

prepare() {
    rm -rf "$WORK_DIR/copie"
    mkdir -p "$WORK_DIR/copie"
    for item in src tests scripts node_modules package.json; do
        if [ -e "$ROOT_DIR/$item" ]; then
            cp -R "$ROOT_DIR/$item" "$WORK_DIR/copie/"
        fi
    done
}

replace() {
    python3 - "$WORK_DIR/copie/$1" "$2" "$3" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding='utf-8', newline='') as handle:
    content = handle.read()
if content.count(old) != 1:
    sys.stderr.write("motif introuvable ou ambigu dans %s\n" % path)
    sys.exit(2)
with open(path, 'w', encoding='utf-8', newline='') as handle:
    handle.write(content.replace(old, new, 1))
PY
}

expect_java_failure() {
    if (cd "$WORK_DIR/copie" && sh scripts/run-tests.sh > "$WORK_DIR/java.log" 2>&1); then
        ko "$1 (la suite Java passe alors qu'elle devrait echouer)"
        grep -m3 "ECHEC" "$WORK_DIR/java.log" | sed 's/^/       /' || true
    else
        ok "$1"
    fi
}

expect_sql_failure() {
    if (cd "$WORK_DIR/copie" && WORK_DIR="$WORK_DIR/pglite-mut" sh tests/sql/e2e-colonnes.sh > "$WORK_DIR/sql.log" 2>&1); then
        ko "$1 (le test SQL passe alors qu'il devrait echouer)"
        grep -m3 "ECHEC" "$WORK_DIR/sql.log" | sed 's/^/       /' || true
    else
        ok "$1"
    fi
}

AVEC_JAVA=1
if ! command -v javac >/dev/null 2>&1 || ! command -v java >/dev/null 2>&1; then
    AVEC_JAVA=0
    echo "(javac/java absents : mutations Java 1 a 4 et 6 ignorees)"
fi
AVEC_NODE=1
if ! command -v node >/dev/null 2>&1; then
    AVEC_NODE=0
    echo "(node absent : mutation 5 ignoree)"
fi

if [ "$AVEC_JAVA" -eq 1 ]; then
    echo "== 0. controle : la copie non modifiee doit passer =="
    prepare
    if (cd "$WORK_DIR/copie" && sh scripts/run-tests.sh > "$WORK_DIR/java.log" 2>&1); then
        ok "copie non modifiee : tests au vert"
    else
        ko "copie non modifiee : la suite Java echoue deja"
        sed -n '1,10p' "$WORK_DIR/java.log" | sed 's/^/       /'
    fi

    echo "== 1. le prefixe ID_ n'est plus retire =="
    prepare
    replace src/org/openconcerto/modules/project/ColumnLabelRules.java \
        "        return name.substring(3).replace('_', ' ');" \
        "        return name;"
    expect_java_failure "ID_CLIENT n'est plus transforme en CLIENT : detecte"

    echo "== 2. le mode AUTO est ignore =="
    prepare
    replace src/org/openconcerto/modules/project/ColumnLabelRules.java \
        "        if (MODE_AUTO.equals(normalizedMode) && isIdColumn(column)) {" \
        "        if (false && isIdColumn(column)) {"
    expect_java_failure "mode AUTO sans effet : detecte"

    echo "== 3. les superutilisateurs ne sont plus prioritaires =="
    prepare
    replace src/org/openconcerto/modules/project/ColumnLabelRules.java \
        "        if (!superUsers.isEmpty()) {" \
        "        if (false && !superUsers.isEmpty()) {"
    expect_java_failure "role le plus haut mal choisi : detecte"

    echo "== 4. derive entre le Java et le SQL de reference =="
    prepare
    replace tests/sql/migration-colonnes.sql \
        'order by 3 desc, 4 desc, 5 desc, 1' \
        'order by 1'
    expect_java_failure "requete de droits differente du fichier SQL : detectee"

    echo "== 7. utilisateur inconnu traite comme un refus (menu invisible) =="
    prepare
    replace src/org/openconcerto/modules/project/ColumnLabelRules.java \
        'return reason.startsWith("utilisateur de la session inconnu") || reason.startsWith("aucun utilisateur lisible");' \
        'return false;'
    expect_java_failure "utilisateur inconnu traite comme un refus : detecte"

    echo "== 8. la case « Libelle affiche » redevient vide sans regle =="
    prepare
    replace src/org/openconcerto/modules/project/ColumnLabelRules.java \
        "        if (MODE_AUTO.equals(normalizedMode)) {
            return suggestLabel(column);
        }
        return column;" \
        "        return \"\";"
    expect_java_failure "case vide au lieu du libelle affiche : detecte"

    echo "== 9. une edition sans changement cree une regle inutile =="
    prepare
    replace src/org/openconcerto/modules/project/ColumnLabelRules.java \
        "        if (cleaned.equals(before)) {
            return cleanLabel(currentRule);
        }" \
        "        if (false) {
            return cleanLabel(currentRule);
        }"
    expect_java_failure "regle inutile creee par un simple clic : detectee"

    echo "== 10. le libelle affiche repasse en gris pale =="
    prepare
    replace src/org/openconcerto/modules/project/ColumnLabelStyle.java \
        '        return Color.BLACK;' \
        '        return new Color(0x77, 0x77, 0x77);'
    expect_java_failure "libelle gris pale (illisible) : detecte"

    echo "== 6. enregistrement non transactionnel =="
    prepare
    replace src/org/openconcerto/modules/project/ColumnLabelRules.java \
        'sb.append("begin;");' \
        'sb.append("");'
    expect_java_failure "enregistrement sans transaction : detecte"
fi

if [ "$AVEC_NODE" -eq 1 ]; then
    echo "== 5. l'index unique devient un index simple =="
    prepare
    replace tests/sql/migration-colonnes.sql \
        'create unique index if not exists "PROJECT_COLUMN_LABEL_UNQ"' \
        'create index if not exists "PROJECT_COLUMN_LABEL_UNQ"'
    expect_sql_failure "doublons de libelles acceptes : detecte"
fi

echo
echo "Controles : $CONTROLES | echecs : $ECHECS"
if [ "$ECHECS" -ne 0 ]; then
    echo "RESULTAT : ECHEC"
    exit 1
fi
echo "RESULTAT : OK"
