#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR=${BUILD_DIR:-"$ROOT_DIR/build"}
TEST_CLASSES_DIR="$BUILD_DIR/test-classes"
SOURCES_FILE="$BUILD_DIR/test-sources.txt"

rm -rf "$TEST_CLASSES_DIR"
mkdir -p "$TEST_CLASSES_DIR"
cd "$ROOT_DIR"

{
    printf '%s\n' src/org/openconcerto/modules/project/AffairListSortSupport.java
    printf '%s\n' tests/org/openconcerto/modules/project/AffairListSortSupportTest.java
} > "$SOURCES_FILE"
javac -J-XX:-UsePerfData -proc:none -encoding UTF-8 -cp src -d "$TEST_CLASSES_DIR" @"$SOURCES_FILE"
java -cp "$TEST_CLASSES_DIR" org.openconcerto.modules.project.AffairListSortSupportTest
