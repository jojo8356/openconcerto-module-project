#!/usr/bin/env sh
set -eu

MODULE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OPENCONCERTO_JAR=${OPENCONCERTO_JAR:-/opt/openconcerto/OpenConcerto.jar}
BUILD_DIR=${BUILD_DIR:-"$MODULE_DIR/build"}
MODULE_VERSION=$(awk -F= '/^version=/ { print $2; exit }' "$MODULE_DIR/module.properties")
CLASSES_DIR="$BUILD_DIR/classes"
STAGING_DIR="$BUILD_DIR/jar-staging"
SOURCES_FILE="$BUILD_DIR/currency-module-sources.txt"
JAR_FILE="$BUILD_DIR/org.openconcerto.modules.currency-$MODULE_VERSION.jar"

if [ ! -f "$OPENCONCERTO_JAR" ]; then
    echo "OpenConcerto jar not found: $OPENCONCERTO_JAR" >&2
    echo "Set OPENCONCERTO_JAR=/path/to/OpenConcerto.jar" >&2
    exit 1
fi

JAVAC_VERSION_OUTPUT=$(javac -J-XX:-UsePerfData -version 2>&1)
JAVAC_VERSION=$(printf '%s\n' "$JAVAC_VERSION_OUTPUT" | awk '/^javac / { print $2; exit }')
if [ -z "$JAVAC_VERSION" ]; then
    echo "Unable to detect javac version from: $JAVAC_VERSION_OUTPUT" >&2
    exit 1
fi
JAVAC_MAJOR=$(printf '%s\n' "$JAVAC_VERSION" | awk -F. '{ if ($1 == "1") print $2; else print $1 }')

rm -rf "$CLASSES_DIR" "$STAGING_DIR"
mkdir -p "$CLASSES_DIR" "$STAGING_DIR/META-INF"
cd "$MODULE_DIR"
find src -name '*.java' | sort > "$SOURCES_FILE"

if [ "$JAVAC_MAJOR" -ge 9 ]; then
    javac -J-XX:-UsePerfData -proc:none -encoding UTF-8 --release 8 -Xlint:-options -cp "$OPENCONCERTO_JAR" -d "$CLASSES_DIR" @"$SOURCES_FILE"
else
    javac -J-XX:-UsePerfData -proc:none -encoding UTF-8 -source 8 -target 8 -cp "$OPENCONCERTO_JAR" -d "$CLASSES_DIR" @"$SOURCES_FILE"
fi

cp -R "$CLASSES_DIR"/. "$STAGING_DIR"/
find "$MODULE_DIR/src" -type f \( -name '*.xml' -o -name '*.properties' -o -name '*.png' -o -name '*.ods' -o -name '*.odt' \) | while IFS= read -r source_file; do
    relative_path=${source_file#"$MODULE_DIR/src/"}
    destination="$STAGING_DIR/$relative_path"
    mkdir -p "$(dirname -- "$destination")"
    cp "$source_file" "$destination"
done
cp "$MODULE_DIR/module.properties" "$STAGING_DIR/META-INF/openConcertoModule.properties"

jar cf "$JAR_FILE" -C "$STAGING_DIR" .
"$MODULE_DIR/../scripts/verify-java8-bytecode.sh" "$JAR_FILE"

echo "$JAR_FILE"
