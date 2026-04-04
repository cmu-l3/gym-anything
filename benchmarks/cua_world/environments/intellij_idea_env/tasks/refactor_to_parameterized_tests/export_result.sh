#!/bin/bash
echo "=== Exporting refactor_to_parameterized_tests result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/security-utils"
TEST_FILE="$PROJECT_DIR/src/test/java/com/security/PasswordValidatorTest.java"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Run tests to verify they pass and get count
echo "Running tests..."
cd "$PROJECT_DIR"
TEST_OUTPUT=$(su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean test" 2>&1)
MVN_EXIT_CODE=$?

TESTS_RUN=0
TESTS_FAILURES=0
TESTS_ERRORS=0

if [ $MVN_EXIT_CODE -eq 0 ]; then
    BUILD_SUCCESS="true"
else
    BUILD_SUCCESS="false"
fi

# Parse surefire report for exact numbers
REPORT_FILE="$PROJECT_DIR/target/surefire-reports/TEST-com.security.PasswordValidatorTest.xml"
if [ -f "$REPORT_FILE" ]; then
    # Extract stats from XML attributes
    TESTS_RUN=$(grep -oP 'tests="\K[0-9]+' "$REPORT_FILE" | head -1)
    TESTS_FAILURES=$(grep -oP 'failures="\K[0-9]+' "$REPORT_FILE" | head -1)
    TESTS_ERRORS=$(grep -oP 'errors="\K[0-9]+' "$REPORT_FILE" | head -1)
else
    # Fallback to parsing stdout
    TESTS_RUN=$(echo "$TEST_OUTPUT" | grep -oP 'Tests run: \K[0-9]+' | tail -1)
    TESTS_FAILURES=$(echo "$TEST_OUTPUT" | grep -oP 'Failures: \K[0-9]+' | tail -1)
    TESTS_ERRORS=$(echo "$TEST_OUTPUT" | grep -oP 'Errors: \K[0-9]+' | tail -1)
fi

# Default to 0 if parsing failed
TESTS_RUN=${TESTS_RUN:-0}
TESTS_FAILURES=${TESTS_FAILURES:-0}
TESTS_ERRORS=${TESTS_ERRORS:-0}
TOTAL_FAILURES=$((TESTS_FAILURES + TESTS_ERRORS))

# 2. Read Test File Content
TEST_CONTENT=""
if [ -f "$TEST_FILE" ]; then
    TEST_CONTENT=$(cat "$TEST_FILE")
fi

# 3. Check for Anti-Gaming (File modification)
FILE_MODIFIED="false"
if [ -f /tmp/initial_test_hash.txt ]; then
    CURRENT_HASH=$(md5sum "$TEST_FILE" | awk '{print $1}')
    INITIAL_HASH=$(awk '{print $1}' /tmp/initial_test_hash.txt)
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Escape content for JSON
TEST_CONTENT_ESCAPED=$(echo "$TEST_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
TEST_OUTPUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -n 50 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "build_success": $BUILD_SUCCESS,
    "tests_run": $TESTS_RUN,
    "tests_failed": $TOTAL_FAILURES,
    "test_content": $TEST_CONTENT_ESCAPED,
    "file_modified": $FILE_MODIFIED,
    "maven_output": $TEST_OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="