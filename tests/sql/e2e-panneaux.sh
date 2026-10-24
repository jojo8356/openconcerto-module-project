#!/usr/bin/env sh
#
# Test de bout en bout de la suite « panneaux » du module project, sans
# PostgreSQL : le moteur pglite (npm) joue le role du serveur.
#
# Le scenario comporte deux etats de la meme base :
#
#   1. la base « analysee » contient des anomalies volontaires (colonne
#      ID_COMMANDE_ELEMENT absente, ligne rattachee a une affaire
#      inexistante, ligne sans affaire, refus de lecture pour un
#      utilisateur) : la suite doit les DETECTER (code de sortie 1) ;
#   2. la base « propre » (tests/sql/fixture-panneaux-nettoye.sql) ne
#      contient plus aucune anomalie : la suite doit PASSER (code de
#      sortie 0).
#
# Lecture seule pour la base analysee : les scripts de fixture creent une
# base jetable dans un repertoire temporaire.
#
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
WORK_DIR=${WORK_DIR:-$(mktemp -d)}
DATA_DIR="$WORK_DIR/pglite"
BIN_DIR="$WORK_DIR/bin"
CLASSES_DIR="$WORK_DIR/classes"
PSQL="$BIN_DIR/psql"

cd "$ROOT_DIR"

echo "== 1. preparation =="
mkdir -p "$BIN_DIR" "$CLASSES_DIR"
if [ ! -d "$ROOT_DIR/node_modules/@electric-sql/pglite" ]; then
    echo "installation des dependances node (pglite) ..."
    npm install --silent
fi
cat > "$PSQL" <<EOF
#!/usr/bin/env bash
exec node "$ROOT_DIR/tests/sql/pglite-psql.mjs" "\$@"
EOF
chmod +x "$PSQL"
export PATH="$BIN_DIR:$PATH"
export PGLITE_DIR="$DATA_DIR"

echo "== 2. compilation des tests =="
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    JAVA="$JAVA_HOME/bin/java"
else
    JAVA=java
fi
if [ -n "${PANEL_TEST_CLASSES:-}" ]; then
    # classes deja compilees (utile quand javac n'est pas disponible)
    CLASSES_DIR=$PANEL_TEST_CLASSES
    echo "classes precompilees : $CLASSES_DIR"
else
    if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/javac" ]; then
        JAVAC="$JAVA_HOME/bin/javac"
    else
        JAVAC=javac
    fi
    find "$ROOT_DIR/tests/org/openconcerto/modules/project/panels" -name '*.java' -type f | sort > "$WORK_DIR/sources.txt"
    "$JAVAC" -proc:none -encoding UTF-8 -d "$CLASSES_DIR" "@$WORK_DIR/sources.txt"
fi

echo "== 3. base avec anomalies (la suite doit echouer) =="
rm -rf "$DATA_DIR"
"$PSQL" -X -v ON_ERROR_STOP=1 -f "$ROOT_DIR/tests/sql/fixture-panneaux.sql" > /dev/null
set +e
"$JAVA" -cp "$CLASSES_DIR" org.openconcerto.modules.project.panels.TestRunner --db OpenConcerto --user openconcerto --schemas OpenConcerto42
CODE=$?
set -e
if [ "$CODE" -eq 0 ]; then
    echo "ECHEC du test : la suite aurait du detecter les anomalies plantees." >&2
    exit 1
fi
echo "OK : les anomalies plantees sont detectees (code $CODE)."

echo "== 4. base propre (la suite doit passer) =="
"$PSQL" -X -v ON_ERROR_STOP=1 -f "$ROOT_DIR/tests/sql/fixture-panneaux-nettoye.sql" > /dev/null
set +e
"$JAVA" -cp "$CLASSES_DIR" org.openconcerto.modules.project.panels.TestRunner --db OpenConcerto --user openconcerto --schemas OpenConcerto42
CODE=$?
set -e
if [ "$CODE" -ne 0 ]; then
    echo "ECHEC du test : la suite aurait du passer sur une base propre (code $CODE)." >&2
    exit 1
fi
echo "OK : la suite passe sur une base propre."

rm -rf "$WORK_DIR"
echo
echo "RESULTAT : e2e panneaux OK"
