#!/bin/bash
echo "=== Exporting Java 8 to Java 17 Migration Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/java17_migration_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_DATE=$(cat /tmp/initial_date_count 2>/dev/null || echo "0")
INITIAL_RAWTYPE=$(cat /tmp/initial_rawtype_count 2>/dev/null || echo "0")
INITIAL_SB=$(cat /tmp/initial_stringbuffer_count 2>/dev/null || echo "0")

PROJECT_DIR="/home/ga/legacy-hr-system"
MAIN_SRC="$PROJECT_DIR/src/main/java"

# ---- Date/Calendar check ----
DATE_IMPORT_COUNT=$(grep -r "import java\.util\.Date\|import java\.util\.Calendar\|import java\.text\.SimpleDateFormat" \
    "$MAIN_SRC" 2>/dev/null | wc -l)
DATE_USAGE_COUNT=$(grep -r "new Date()\|Date hireDate\|Date dateOfBirth\|Date lastModified\|Calendar\.getInstance\|SimpleDateFormat" \
    "$MAIN_SRC" 2>/dev/null | wc -l)

# ---- java.time usage ----
LOCALDATE_COUNT=$(grep -r "LocalDate\|LocalDateTime\|LocalTime" "$MAIN_SRC" 2>/dev/null | wc -l)
PERIOD_COUNT=$(grep -r "Period\|ChronoUnit\|Duration" "$MAIN_SRC" 2>/dev/null | wc -l)
DATETIMEFORMATTER_COUNT=$(grep -r "DateTimeFormatter" "$MAIN_SRC" 2>/dev/null | wc -l)

# ---- Raw type check ----
# Remaining raw List/Map in main source (excluding @SuppressWarnings test files)
RAW_LIST_COUNT=$(grep -rn "private Map employees\|private Map departments\| List get\| List generate\| List employees\b" \
    "$MAIN_SRC" 2>/dev/null | grep -v "List<\|Map<" | wc -l)
GENERIC_MAP_COUNT=$(grep -r "Map<Integer\|Map<String" "$MAIN_SRC" 2>/dev/null | wc -l)
GENERIC_LIST_COUNT=$(grep -r "List<Employee\|List<Double\|List<String\|List<Department" "$MAIN_SRC" 2>/dev/null | wc -l)

# ---- StringBuffer check ----
STRINGBUFFER_COUNT=$(grep -r "StringBuffer" "$MAIN_SRC" 2>/dev/null | wc -l)
STRINGBUILDER_COUNT=$(grep -r "StringBuilder" "$MAIN_SRC" 2>/dev/null | wc -l)

# ---- pom.xml Java version ----
POM_SOURCE_17=0
grep -q "compiler\.source>17\|compiler\.source> *17" "$PROJECT_DIR/pom.xml" 2>/dev/null && POM_SOURCE_17=1
POM_TARGET_17=0
grep -q "compiler\.target>17\|compiler\.target> *17" "$PROJECT_DIR/pom.xml" 2>/dev/null && POM_TARGET_17=1

# ---- Build check ----
BUILD_SUCCESS="false"
BUILD_EXIT=1
if [ -d "$PROJECT_DIR" ]; then
    cd "$PROJECT_DIR"
    mvn clean test -q --no-transfer-progress 2>/tmp/mvn_java17_output.txt
    BUILD_EXIT=$?
    [ $BUILD_EXIT -eq 0 ] && BUILD_SUCCESS="true"
fi

cat > /tmp/java17_migration_result.json << EOF
{
  "task_start": $TASK_START,
  "initial_date_count": $INITIAL_DATE,
  "initial_rawtype_count": $INITIAL_RAWTYPE,
  "initial_stringbuffer_count": $INITIAL_SB,
  "date_import_count": $DATE_IMPORT_COUNT,
  "date_usage_count": $DATE_USAGE_COUNT,
  "localdate_count": $LOCALDATE_COUNT,
  "period_count": $PERIOD_COUNT,
  "datetimeformatter_count": $DATETIMEFORMATTER_COUNT,
  "raw_list_count": $RAW_LIST_COUNT,
  "generic_map_count": $GENERIC_MAP_COUNT,
  "generic_list_count": $GENERIC_LIST_COUNT,
  "stringbuffer_count": $STRINGBUFFER_COUNT,
  "stringbuilder_count": $STRINGBUILDER_COUNT,
  "pom_source_17": $POM_SOURCE_17,
  "pom_target_17": $POM_TARGET_17,
  "build_success": $BUILD_SUCCESS,
  "build_exit_code": $BUILD_EXIT
}
EOF

echo "Result saved to /tmp/java17_migration_result.json"
cat /tmp/java17_migration_result.json

echo "=== Export Complete ==="
