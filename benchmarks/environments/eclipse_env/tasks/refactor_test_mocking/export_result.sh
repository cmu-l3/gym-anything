#!/bin/bash
echo "=== Exporting Refactor Test Mocking Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/PaymentSystem"
TEST_FILE="$PROJECT_DIR/src/test/java/com/example/payment/OrderServiceTest.java"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Check source code content
TEST_FILE_EXISTS="false"
TEST_CONTENT=""

if [ -f "$TEST_FILE" ]; then
    TEST_FILE_EXISTS="true"
    TEST_CONTENT=$(cat "$TEST_FILE")
fi

# 3. Run Maven tests to verify code actually works (Ground Truth)
# We run this in the background to not interfere with agent, but capturing output
echo "Running maven test verification..."
cd "$PROJECT_DIR"
MAVEN_OUTPUT=$(mvn test -B 2>&1 || true)

# Parse Maven output for pass/fail
TESTS_PASSED="false"
if echo "$MAVEN_OUTPUT" | grep -q "BUILD SUCCESS"; then
    TESTS_PASSED="true"
fi

# Extract test counts
TESTS_RUN_COUNT=$(echo "$MAVEN_OUTPUT" | grep -o "Tests run: [0-9]*" | head -1 | awk '{print $3}' || echo "0")
FAILURES_COUNT=$(echo "$MAVEN_OUTPUT" | grep -o "Failures: [0-9]*" | head -1 | awk '{print $2}' || echo "0")
ERRORS_COUNT=$(echo "$MAVEN_OUTPUT" | grep -o "Errors: [0-9]*" | head -1 | awk '{print $2}' || echo "0")

# Check if file was modified timestamp
FILE_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
if [ -f "$TEST_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$TEST_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Escape content for JSON safely
ESCAPED_TEST_CONTENT=$(echo "$TEST_CONTENT" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
ESCAPED_MAVEN_OUTPUT=$(echo "$MAVEN_OUTPUT" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")

# Create result JSON
RESULT_JSON=$(cat << EOF
{
    "test_file_exists": $TEST_FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "tests_passed": $TESTS_PASSED,
    "tests_run_count": "$TESTS_RUN_COUNT",
    "failures_count": "$FAILURES_COUNT",
    "errors_count": "$ERRORS_COUNT",
    "test_content": $ESCAPED_TEST_CONTENT,
    "maven_output": $ESCAPED_MAVEN_OUTPUT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="