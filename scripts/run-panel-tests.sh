#!/usr/bin/env sh
#
# Compile et execute la suite de tests des panneaux du module
# org.openconcerto.modules.project (version 1.1).
#
# La suite verifie, sur TOUS les panneaux du module, que les donnees
# affichees sont bien TOUTES les donnees de la base, et qu'aucune ligne
# n'est cachee (colonne manquante, lien casse vers une affaire, filtre
# restrictif, droit utilisateur, ecart entre un total affiche et le total
# reel de la table).
#
# Lecture seule : aucune ecriture n'est faite dans la base.
#
# Usage :
#   sh scripts/run-panel-tests.sh [options]
#
# Options :
#   --host HOTE      serveur PostgreSQL      (defaut : $PGHOST ou 127.0.0.1)
#   --port PORT      port                    (defaut : $PGPORT ou 5432)
#   --db BASE        base                    (defaut : $PGDATABASE ou OpenConcertoKineticTherm)
#   --user ROLE      role SQL                (defaut : $PGUSER ou openconcerto)
#   --password MDP   mot de passe            (defaut : $PGPASSWORD)
#   --schemas LIST   schemas a controler, separes par des virgules
#                    (defaut : tous les schemas contenant une table AFFAIRE)
#   --url URL        URL JDBC complete (prioritaire sur host/port/db)
#   --jdbc JAR       pilote PostgreSQL (postgresql-*.jar) a mettre dans le classpath
#   --skip-build     ne pas recompiler les tests
#   -h, --help       cette aide
#
# Sortie : 0 si tous les controles passent, 1 sinon.
#
# Exemples :
#   sh scripts/run-panel-tests.sh --host 127.0.0.1 --port 5433 --db OpenConcerto --user openconcerto
#   PGPASSWORD=secret sh scripts/run-panel-tests.sh --schemas OpenConcerto42
#
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR=${BUILD_DIR:-"$ROOT_DIR/build"}
CLASSES_DIR="$BUILD_DIR/panel-test-classes"
SRC_DIR="$ROOT_DIR/tests/org/openconcerto/modules/project/panels"
MAIN_CLASS=org.openconcerto.modules.project.panels.TestRunner

HOST=${PGHOST:-127.0.0.1}
PORT=${PGPORT:-5432}
DB=${PGDATABASE:-OpenConcertoKineticTherm}
DB_USER=${PGUSER:-openconcerto}
DB_PASSWORD=${PGPASSWORD:-}
SCHEMAS=${PANEL_TEST_SCHEMAS:-}
JDBC_URL=${PANEL_TEST_JDBC_URL:-}
JDBC_JAR=${PANEL_TEST_JDBC:-}
SKIP_BUILD=0

usage() {
    sed -n '3,40p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --host)
            HOST=$2
            shift 2
            ;;
        --port)
            PORT=$2
            shift 2
            ;;
        --db | --database)
            DB=$2
            shift 2
            ;;
        --user)
            DB_USER=$2
            shift 2
            ;;
        --password)
            DB_PASSWORD=$2
            shift 2
            ;;
        --schemas)
            SCHEMAS=$2
            shift 2
            ;;
        --url)
            JDBC_URL=$2
            shift 2
            ;;
        --jdbc)
            JDBC_JAR=$2
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Option inconnue : $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# ---------------------------------------------------------------- compilation
if [ "$SKIP_BUILD" -eq 0 ]; then
    if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/javac" ]; then
        JAVAC="$JAVA_HOME/bin/javac"
        JAVA="$JAVA_HOME/bin/java"
    elif command -v javac >/dev/null 2>&1; then
        JAVAC=javac
        JAVA=java
    else
        echo "ERREUR : aucun compilateur javac trouve." >&2
        echo "       Installez un JDK 8 ou superieur, ou definissez JAVA_HOME." >&2
        exit 2
    fi

    echo "Compilation des tests dans $CLASSES_DIR ..."
    rm -rf "$CLASSES_DIR"
    mkdir -p "$CLASSES_DIR"
    SOURCES_FILE="$BUILD_DIR/panel-test-sources.txt"
    mkdir -p "$BUILD_DIR"
    find "$SRC_DIR" -name '*.java' -type f | sort > "$SOURCES_FILE"
    "$JAVAC" -proc:none -encoding UTF-8 -d "$CLASSES_DIR" "@$SOURCES_FILE"
else
    if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
        JAVA="$JAVA_HOME/bin/java"
    else
        JAVA=java
    fi
fi

if [ ! -d "$CLASSES_DIR" ]; then
    echo "ERREUR : $CLASSES_DIR est absent (lancez sans --skip-build)." >&2
    exit 2
fi

# ------------------------------------------------------------------ classpath
CLASSPATH="$CLASSES_DIR"
if [ -z "$JDBC_JAR" ]; then
    for candidate in \
        "$HOME"/.m2/repository/org/postgresql/postgresql/*/postgresql-*.jar \
        /usr/share/java/postgresql*.jar \
        /usr/share/java/*/postgresql*.jar; do
        if [ -f "$candidate" ]; then
            JDBC_JAR=$candidate
            break
        fi
    done
fi
if [ -n "$JDBC_JAR" ]; then
    if [ ! -f "$JDBC_JAR" ]; then
        echo "ERREUR : pilote JDBC introuvable : $JDBC_JAR" >&2
        exit 2
    fi
    echo "Pilote JDBC : $JDBC_JAR"
    CLASSPATH="$CLASSPATH:$JDBC_JAR"
else
    echo "Aucun pilote JDBC trouve : transport psql (postgresql-client)."
    echo "Pour le JDBC : apt install libpostgresql-jdbc-java, ou --jdbc /chemin/postgresql.jar"
fi

# ------------------------------------------------------------------ execution
set -- --host "$HOST" --port "$PORT" --db "$DB" --user "$DB_USER"
if [ -n "$DB_PASSWORD" ]; then
    set -- "$@" --password "$DB_PASSWORD"
fi
if [ -n "$SCHEMAS" ]; then
    set -- "$@" --schemas "$SCHEMAS"
fi
if [ -n "$JDBC_URL" ]; then
    set -- "$@" --url "$JDBC_URL"
fi

export PGPASSWORD="$DB_PASSWORD"
export PGHOST="$HOST"
export PGPORT="$PORT"
export PGDATABASE="$DB"
export PGUSER="$DB_USER"

echo
exec "$JAVA" -cp "$CLASSPATH" "$MAIN_CLASS" "$@"
