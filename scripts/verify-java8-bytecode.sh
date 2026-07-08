#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/module.jar" >&2
    exit 2
fi

case $1 in
    /*) JAR_FILE=$1 ;;
    *) JAR_FILE=$(pwd)/$1 ;;
esac
if [ ! -f "$JAR_FILE" ]; then
    echo "Jar not found: $JAR_FILE" >&2
    exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

(cd "$TMP_DIR" && jar xf "$JAR_FILE")

failed=0
while IFS= read -r class_file; do
    major_hex=$(xxd -p -l 8 "$class_file" | cut -c 13-16)
    major_dec=$(printf '%d' "0x$major_hex")
    if [ "$major_dec" -gt 52 ]; then
        echo "Class bytecode is newer than Java 8: $class_file major=$major_dec" >&2
        failed=1
    fi
done <<EOF
$(find "$TMP_DIR" -name '*.class' | sort)
EOF

if [ "$failed" -ne 0 ]; then
    exit 1
fi

echo "Java bytecode check passed: all classes are major <= 52"
