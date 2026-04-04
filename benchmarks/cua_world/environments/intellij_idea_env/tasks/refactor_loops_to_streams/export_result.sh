#!/bin/bash
echo "=== Exporting refactor_loops_to_streams result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/user-analytics"
TARGET_FILE="$PROJECT_DIR/src/main/java/com/analytics/AnalyticsService.java"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Run Tests (Crucial verification step)
echo "Running tests..."
cd "$PROJECT_DIR"
TEST_OUTPUT=$(su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test" 2>&1)
TEST_EXIT_CODE=$?

# Parse test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_ERRORS=0

if [ -d "$PROJECT_DIR/target/surefire-reports" ]; then
    for report in "$PROJECT_DIR/target/surefire-reports"/*.xml; do
        if [ -f "$report" ]; then
            TR=$(grep -oP 'tests="\K[0-9]+' "$report" | head -1)
            TF=$(grep -oP 'failures="\K[0-9]+' "$report" | head -1)
            TE=$(grep -oP 'errors="\K[0-9]+' "$report" | head -1)
            TESTS_RUN=$((TESTS_RUN + ${TR:-0}))
            TESTS_FAILED=$((TESTS_FAILED + ${TF:-0}))
            TESTS_ERRORS=$((TESTS_ERRORS + ${TE:-0}))
        fi
    done
    TESTS_PASSED=$((TESTS_RUN - TESTS_FAILED - TESTS_ERRORS))
fi

# 2. Read Refactored Code
SERVICE_CONTENT=""
if [ -f "$TARGET_FILE" ]; then
    SERVICE_CONTENT=$(cat "$TARGET_FILE")
fi

# 3. Check for modification
FILE_MODIFIED="false"
if [ -f /tmp/initial_service_hash.txt ]; then
    CURRENT_HASH=$(md5sum "$TARGET_FILE" | awk '{print $1}')
    INITIAL_HASH=$(awk '{print $1}' /tmp/initial_service_hash.txt)
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. JSON Export
# Use Python to safely escape strings for JSON
SERVICE_ESCAPED=$(echo "$SERVICE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
TEST_OUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -n 20 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

RESULT_JSON=$(cat << EOF
{
    "service_content": $SERVICE_ESCAPED,
    "file_modified": $FILE_MODIFIED,
    "test_exit_code": $TEST_EXIT_CODE,
    "tests_run": $TESTS_RUN,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "tests_errors": $TESTS_ERRORS,
    "test_output_snippet": $TEST_OUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="