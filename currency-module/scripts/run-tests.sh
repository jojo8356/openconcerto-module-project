#!/usr/bin/env sh
set -eu

MODULE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR=${BUILD_DIR:-"$MODULE_DIR/build"}
TEST_CLASSES_DIR="$BUILD_DIR/test-classes"

rm -rf "$TEST_CLASSES_DIR"
mkdir -p "$TEST_CLASSES_DIR"
cd "$MODULE_DIR"
javac -encoding UTF-8 -d "$TEST_CLASSES_DIR" \
    src/org/openconcerto/modules/currency/CurrencyTemplateSupport.java \
    src/org/openconcerto/modules/currency/CurrencySelectionSupport.java \
    src/org/openconcerto/modules/currency/Iso4217CurrencyCatalog.java \
    tests/org/openconcerto/modules/currency/CurrencyTemplateSupportTest.java \
    tests/org/openconcerto/modules/currency/CurrencySelectionSupportTest.java \
    tests/org/openconcerto/modules/currency/Iso4217CurrencyCatalogTest.java
java -cp "$TEST_CLASSES_DIR" org.openconcerto.modules.currency.CurrencyTemplateSupportTest
java -cp "$TEST_CLASSES_DIR" org.openconcerto.modules.currency.CurrencySelectionSupportTest
java -cp "$TEST_CLASSES_DIR" org.openconcerto.modules.currency.Iso4217CurrencyCatalogTest
