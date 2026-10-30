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
    printf '%s\n' src/org/openconcerto/modules/project/AffairBackfillSupport.java
    printf '%s\n' src/org/openconcerto/modules/project/AffairLinkSupport.java
    printf '%s\n' src/org/openconcerto/modules/project/AffairTransferSupport.java
    printf '%s\n' src/org/openconcerto/modules/project/ItemAffairColumnRules.java
    printf '%s\n' src/org/openconcerto/modules/project/ColumnLabelRules.java
    printf '%s\n' src/org/openconcerto/modules/project/ColumnLabelStyle.java
    printf '%s\n' src/org/openconcerto/modules/project/HistoryPanelCleanup.java
    printf '%s\n' src/org/openconcerto/modules/project/ProjectMenuSupport.java
    printf '%s\n' src/org/openconcerto/modules/project/SupplierInvoiceAffairComponentSupport.java
    printf '%s\n' src/org/openconcerto/modules/project/SupplierOrderToInvoiceSQLInjector.java
    printf '%s\n' tests/org/openconcerto/modules/project/AffairListSortSupportTest.java
    printf '%s\n' tests/org/openconcerto/modules/project/AffairBackfillSupportTest.java
    printf '%s\n' tests/org/openconcerto/modules/project/AffairLinkSupportTest.java
    printf '%s\n' tests/org/openconcerto/modules/project/AffairTransferSupportTest.java
    printf '%s\n' tests/org/openconcerto/modules/project/ColumnLabelRulesTest.java
    printf '%s\n' tests/org/openconcerto/modules/project/ItemAffairColumnRulesTest.java
    printf '%s\n' tests/org/openconcerto/modules/project/ProjectMenuSupportTest.java
    printf '%s\n' tests/org/openconcerto/modules/project/SupplierOrderToInvoiceSQLInjectorTest.java
    printf '%s\n' tests/org/openconcerto/erp/injector/CommandeFactureFournisseurSQLInjector.java
    printf '%s\n' tests/org/openconcerto/erp/modules/ComponentsContext.java
    printf '%s\n' tests/org/openconcerto/sql/Configuration.java
    printf '%s\n' tests/org/openconcerto/sql/model/DBRoot.java
    printf '%s\n' tests/org/openconcerto/sql/model/SQLField.java
    printf '%s\n' tests/org/openconcerto/sql/model/SQLInjector.java
    printf '%s\n' tests/org/openconcerto/sql/model/SQLRowAccessor.java
    printf '%s\n' tests/org/openconcerto/sql/model/SQLRowValues.java
    printf '%s\n' tests/org/openconcerto/sql/model/SQLTable.java
} > "$SOURCES_FILE"
javac -J-XX:-UsePerfData -proc:none -encoding UTF-8 -cp src -d "$TEST_CLASSES_DIR" @"$SOURCES_FILE"
java -cp "$TEST_CLASSES_DIR" org.openconcerto.modules.project.AffairListSortSupportTest
java -cp "$TEST_CLASSES_DIR" org.openconcerto.modules.project.AffairBackfillSupportTest
java -cp "$TEST_CLASSES_DIR" org.openconcerto.modules.project.AffairLinkSupportTest
java -cp "$TEST_CLASSES_DIR" org.openconcerto.modules.project.AffairTransferSupportTest
java -cp "$TEST_CLASSES_DIR" org.openconcerto.modules.project.ColumnLabelRulesTest
java -cp "$TEST_CLASSES_DIR" org.openconcerto.modules.project.ProjectMenuSupportTest
java -cp "$TEST_CLASSES_DIR" org.openconcerto.modules.project.SupplierOrderToInvoiceSQLInjectorTest
java -cp "$TEST_CLASSES_DIR" org.openconcerto.modules.project.ItemAffairColumnRulesTest
