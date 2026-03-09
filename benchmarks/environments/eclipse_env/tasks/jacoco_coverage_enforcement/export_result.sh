#!/bin/bash
echo "=== Exporting JaCoCo Coverage Enforcement Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/jacoco_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_TEST_COUNT=$(cat /tmp/initial_test_count 2>/dev/null || echo "0")
INITIAL_JACOCO=$(cat /tmp/initial_jacoco_count 2>/dev/null || echo "0")

PROJECT_DIR="/home/ga/transaction-service"

# ---- JaCoCo in pom.xml ----
JACOCO_POM_COUNT=$(grep -c "jacoco" "$PROJECT_DIR/pom.xml" 2>/dev/null)
[ -z "$JACOCO_POM_COUNT" ] && JACOCO_POM_COUNT=0

# ---- Test files ----
CURRENT_TEST_COUNT=$(find "$PROJECT_DIR/src/test" -name "*.java" 2>/dev/null | wc -l)
NEW_TEST_COUNT=$((CURRENT_TEST_COUNT - INITIAL_TEST_COUNT))

# ---- Mockito usage ----
MOCKITO_COUNT=$(grep -r "Mockito\|@Mock\|@ExtendWith(MockitoExtension\|mock(" \
    "$PROJECT_DIR/src/test/" 2>/dev/null | wc -l)

# ---- Build ----
BUILD_SUCCESS="false"
BUILD_EXIT=1
if [ -d "$PROJECT_DIR" ]; then
    cd "$PROJECT_DIR"
    mvn clean test -q --no-transfer-progress 2>/tmp/mvn_jacoco_output.txt
    BUILD_EXIT=$?
    [ $BUILD_EXIT -eq 0 ] && BUILD_SUCCESS="true"
fi

# ---- JaCoCo report ----
REPORT_HTML_EXISTS="false"
REPORT_XML_EXISTS="false"
COVERAGE_PCT=0

HTML_REPORT="$PROJECT_DIR/target/site/jacoco/index.html"
XML_REPORT="$PROJECT_DIR/target/site/jacoco/jacoco.xml"

[ -f "$HTML_REPORT" ] && REPORT_HTML_EXISTS="true"
[ -f "$XML_REPORT" ] && REPORT_XML_EXISTS="true"

# Parse coverage from XML report
if [ -f "$XML_REPORT" ]; then
    # Extract LINE covered/missed from jacoco.xml for all classes
    # jacoco.xml has: <counter type="LINE" missed="X" covered="Y"/>
    MISSED=$(grep -o 'type="LINE" missed="[0-9]*"' "$XML_REPORT" | grep -o 'missed="[0-9]*"' | grep -o '[0-9]*' | awk '{s+=$1} END {print s}')
    COVERED=$(grep -o 'covered="[0-9]*"' "$XML_REPORT" | grep -o '[0-9]*' | awk '{s+=$1} END {print s}')
    if [ -n "$MISSED" ] && [ -n "$COVERED" ]; then
        TOTAL=$((MISSED + COVERED))
        if [ "$TOTAL" -gt 0 ]; then
            COVERAGE_PCT=$((COVERED * 100 / TOTAL))
        fi
    fi
fi

# Also check HTML report for coverage percentage (backup)
HTML_COVERAGE=0
if [ -f "$HTML_REPORT" ]; then
    # Look for total line coverage in HTML (e.g., "72%")
    HTML_COVERAGE=$(grep -o 'Total[^%]*%' "$HTML_REPORT" 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d '%' || echo "0")
fi

cat > /tmp/jacoco_result.json << EOF
{
  "task_start": $TASK_START,
  "initial_test_count": $INITIAL_TEST_COUNT,
  "initial_jacoco_count": $INITIAL_JACOCO,
  "jacoco_pom_count": $JACOCO_POM_COUNT,
  "current_test_count": $CURRENT_TEST_COUNT,
  "new_test_count": $NEW_TEST_COUNT,
  "mockito_count": $MOCKITO_COUNT,
  "build_success": $BUILD_SUCCESS,
  "build_exit_code": $BUILD_EXIT,
  "report_html_exists": $REPORT_HTML_EXISTS,
  "report_xml_exists": $REPORT_XML_EXISTS,
  "coverage_pct": $COVERAGE_PCT,
  "html_coverage": $HTML_COVERAGE
}
EOF

echo "Result saved to /tmp/jacoco_result.json"
cat /tmp/jacoco_result.json

echo "=== Export Complete ==="
