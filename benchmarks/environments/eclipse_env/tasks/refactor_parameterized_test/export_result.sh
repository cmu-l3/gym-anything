#!/bin/bash
echo "=== Exporting Refactor Parameterized Test result ==="

source /workspace/scripts/task_utils.sh

# Configuration
PROJECT_DIR="/home/ga/eclipse-workspace/RadiationPhysics"
TEST_FILE_PATH="src/test/java/com/medtech/physics/DoseCalculatorTest.java"
FULL_TEST_PATH="$PROJECT_DIR/$TEST_FILE_PATH"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Capture File Content & Metadata
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_CONTENT=""
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$FULL_TEST_PATH" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$FULL_TEST_PATH")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$FULL_TEST_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 2. Run Tests via Maven (Headless Verification)
# We trust Maven to tell us if the logic is correct and how many tests passed
echo "Running Maven tests..."
MAVEN_OUTPUT_FILE="/tmp/mvn_test_output.txt"
su - ga -c "cd '$PROJECT_DIR' && mvn test -B" > "$MAVEN_OUTPUT_FILE" 2>&1
MAVEN_EXIT_CODE=$?

TESTS_RUN="0"
TESTS_FAILED="0"
TESTS_ERRORS="0"
BUILD_SUCCESS="false"

if [ $MAVEN_EXIT_CODE -eq 0 ]; then
    BUILD_SUCCESS="true"
    # Parse Surefire output: "Tests run: 5, Failures: 0, Errors: 0, Skipped: 0"
    TEST_LINE=$(grep "Tests run:" "$MAVEN_OUTPUT_FILE" | head -1)
    if [ -n "$TEST_LINE" ]; then
        TESTS_RUN=$(echo "$TEST_LINE" | sed -n 's/.*Tests run: \([0-9]*\).*/\1/p')
        TESTS_FAILED=$(echo "$TEST_LINE" | sed -n 's/.*Failures: \([0-9]*\).*/\1/p')
        TESTS_ERRORS=$(echo "$TEST_LINE" | sed -n 's/.*Errors: \([0-9]*\).*/\1/p')
    fi
else
    # Capture failure details
    grep -A 20 "COMPILATION ERROR" "$MAVEN_OUTPUT_FILE" > /tmp/compile_errors.txt 2>/dev/null || true
fi

# 3. Escape content for JSON
ESCAPED_CONTENT=$(echo "$FILE_CONTENT" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
MAVEN_LOG_TAIL=$(tail -n 20 "$MAVEN_OUTPUT_FILE" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")

# 4. Write Result JSON
RESULT_JSON=$(cat << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "build_success": $BUILD_SUCCESS,
    "tests_run": ${TESTS_RUN:-0},
    "tests_failed": ${TESTS_FAILED:-0},
    "tests_errors": ${TESTS_ERRORS:-0},
    "file_content": $ESCAPED_CONTENT,
    "maven_log": $MAVEN_LOG_TAIL,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="