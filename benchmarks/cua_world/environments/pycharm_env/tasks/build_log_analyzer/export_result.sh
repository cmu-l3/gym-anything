#!/bin/bash
echo "=== Exporting build_log_analyzer result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="build_log_analyzer"
PROJECT_DIR="/home/ga/PycharmProjects/log_analyzer"
RESULT_FILE="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Run Tests ---
# We run pytest and capture the output to parsing
echo "Running tests..."
cd "$PROJECT_DIR"
# Install dependencies first just in case
pip3 install -r requirements.txt -q 2>/dev/null || true

# Run pytest using python module to ensure correct python environment
PYTEST_OUTPUT=$(python3 -m pytest tests/ -v 2>&1)
PYTEST_EXIT_CODE=$?

# --- Parse Results ---

# Count passes/fails
TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TESTS_ERROR=$(echo "$PYTEST_OUTPUT" | grep -c " ERROR" || true)
TESTS_TOTAL=$((TESTS_PASSED + TESTS_FAILED + TESTS_ERROR))

# Check specific modules (by looking for test names in output)
PARSER_PASSED=0
STATS_PASSED=0
ANOMALY_PASSED=0

# Parser tests
echo "$PYTEST_OUTPUT" | grep "test_parser.py" | grep " PASSED" && PARSER_PASSED=$(echo "$PYTEST_OUTPUT" | grep "test_parser.py" | grep -c " PASSED")
# Stats tests
echo "$PYTEST_OUTPUT" | grep "test_stats.py" | grep " PASSED" && STATS_PASSED=$(echo "$PYTEST_OUTPUT" | grep "test_stats.py" | grep -c " PASSED")
# Anomaly tests
echo "$PYTEST_OUTPUT" | grep "test_anomaly.py" | grep " PASSED" && ANOMALY_PASSED=$(echo "$PYTEST_OUTPUT" | grep "test_anomaly.py" | grep -c " PASSED")

# --- Anti-Gaming Checks ---

# Check if implementation files were modified
MODIFIED_PARSER="false"
MODIFIED_STATS="false"
MODIFIED_ANOMALY="false"

[ $(stat -c %Y "$PROJECT_DIR/analyzer/parser.py") -gt "$TASK_START" ] && MODIFIED_PARSER="true"
[ $(stat -c %Y "$PROJECT_DIR/analyzer/stats.py") -gt "$TASK_START" ] && MODIFIED_STATS="true"
[ $(stat -c %Y "$PROJECT_DIR/analyzer/anomaly.py") -gt "$TASK_START" ] && MODIFIED_ANOMALY="true"

# Check if files still contain NotImplementedError
STUBS_REMAINING="false"
grep -r "NotImplementedError" "$PROJECT_DIR/analyzer/" > /dev/null && STUBS_REMAINING="true"

# Check if tests were modified (Anti-cheat)
TESTS_MODIFIED="false"
for f in "$PROJECT_DIR/tests/"*.py; do
    if [ $(stat -c %Y "$f") -gt "$TASK_START" ]; then
        TESTS_MODIFIED="true"
        break
    fi
done

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_total": $TESTS_TOTAL,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "tests_error": $TESTS_ERROR,
    "parser_tests_passed": $PARSER_PASSED,
    "stats_tests_passed": $STATS_PASSED,
    "anomaly_tests_passed": $ANOMALY_PASSED,
    "modified_parser": $MODIFIED_PARSER,
    "modified_stats": $MODIFIED_STATS,
    "modified_anomaly": $MODIFIED_ANOMALY,
    "stubs_remaining": $STUBS_REMAINING,
    "tests_modified": $TESTS_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with permissions
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="