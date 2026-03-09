#!/bin/bash
echo "=== Exporting increase_test_coverage Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="increase_test_coverage"
PROJECT_DIR="/home/ga/PycharmProjects/clinical_validator"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

# Run pytest with coverage
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ --cov=validator --cov-report=term-missing -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# Extract total coverage percentage from pytest-cov report
# The line looks like: TOTAL    245     67    73%
COVERAGE_LINE=$(echo "$PYTEST_OUTPUT" | grep "^TOTAL" | tail -1)
COVERAGE_PCT=0
if [ -n "$COVERAGE_LINE" ]; then
    # Last field is the coverage percentage (e.g. "73%")
    COVERAGE_STR=$(echo "$COVERAGE_LINE" | awk '{print $NF}' | tr -d '%')
    if echo "$COVERAGE_STR" | grep -qE '^[0-9]+$'; then
        COVERAGE_PCT=$COVERAGE_STR
    fi
fi

# Also try to get individual module coverages
DEMOGRAPHICS_COV=0
LABS_COV=0
MEDICATIONS_COV=0

DEM_LINE=$(echo "$PYTEST_OUTPUT" | grep "validator/demographics" | tail -1)
LAB_LINE=$(echo "$PYTEST_OUTPUT" | grep "validator/labs" | tail -1)
MED_LINE=$(echo "$PYTEST_OUTPUT" | grep "validator/medications" | tail -1)

extract_cov() {
    echo "$1" | awk '{print $NF}' | tr -d '%'
}

[ -n "$DEM_LINE" ] && DEMOGRAPHICS_COV=$(extract_cov "$DEM_LINE")
[ -n "$LAB_LINE" ] && LABS_COV=$(extract_cov "$LAB_LINE")
[ -n "$MED_LINE" ] && MEDICATIONS_COV=$(extract_cov "$MED_LINE")

# Validate they are integers
echo "$DEMOGRAPHICS_COV" | grep -qE '^[0-9]+$' || DEMOGRAPHICS_COV=0
echo "$LABS_COV" | grep -qE '^[0-9]+$' || LABS_COV=0
echo "$MEDICATIONS_COV" | grep -qE '^[0-9]+$' || MEDICATIONS_COV=0

# Check coverage thresholds
COVERAGE_AT_75=false
COVERAGE_AT_50=false
[ "$COVERAGE_PCT" -ge 75 ] && COVERAGE_AT_75=true
[ "$COVERAGE_PCT" -ge 50 ] && COVERAGE_AT_50=true

# Check that the source code hasn't been modified (test file only approach)
SOURCE_MODIFIED=false
SOURCE_HASH=$(md5sum "$PROJECT_DIR/validator/demographics.py" "$PROJECT_DIR/validator/labs.py" \
    "$PROJECT_DIR/validator/medications.py" 2>/dev/null | md5sum | awk '{print $1}')

# Count lines in test file (agent should have added substantial tests)
TEST_FILE_LINES=$(wc -l < "$PROJECT_DIR/tests/test_validator.py" 2>/dev/null || echo "0")

cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "total_coverage_pct": $COVERAGE_PCT,
    "demographics_coverage_pct": $DEMOGRAPHICS_COV,
    "labs_coverage_pct": $LABS_COV,
    "medications_coverage_pct": $MEDICATIONS_COV,
    "coverage_at_75": $COVERAGE_AT_75,
    "coverage_at_50": $COVERAGE_AT_50,
    "test_file_lines": $TEST_FILE_LINES,
    "source_hash": "$SOURCE_HASH"
}
EOF

echo "Pytest: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "Total coverage: ${COVERAGE_PCT}%"
echo "  demographics: ${DEMOGRAPHICS_COV}%"
echo "  labs: ${LABS_COV}%"
echo "  medications: ${MEDICATIONS_COV}%"
echo "Coverage >= 75%: $COVERAGE_AT_75"
echo "=== Export Complete ==="
