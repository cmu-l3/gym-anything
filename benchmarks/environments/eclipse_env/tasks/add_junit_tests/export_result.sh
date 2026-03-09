#!/bin/bash
echo "=== Exporting add_junit_tests result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/calculator"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Check for test class
TEST_FILE="$PROJECT_DIR/src/test/java/com/example/calculator/CalculatorTest.java"
TEST_EXISTS="false"
TEST_CONTENT=""
TEST_METHOD_COUNT=0
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

if [ -f "$TEST_FILE" ]; then
    TEST_EXISTS="true"
    TEST_CONTENT=$(cat "$TEST_FILE" 2>/dev/null)

    # Count test methods (methods with @Test annotation)
    TEST_METHOD_COUNT=$(echo "$TEST_CONTENT" | grep -c "@Test" 2>/dev/null || echo "0")
fi

# DO NOT run Maven tests - the agent must run them via Eclipse
# We only collect evidence of what the agent did

# Check for surefire reports (indicates agent ran tests)
if [ -d "$PROJECT_DIR/target/surefire-reports" ]; then
    # Parse test results from surefire XML reports
    SUREFIRE_XML="$PROJECT_DIR/target/surefire-reports/TEST-com.example.calculator.CalculatorTest.xml"
    if [ -f "$SUREFIRE_XML" ]; then
        TESTS_RUN=$(grep -oP 'tests="\K[0-9]+' "$SUREFIRE_XML" 2>/dev/null | head -1 || echo "0")
        TESTS_FAILED=$(grep -oP 'failures="\K[0-9]+' "$SUREFIRE_XML" 2>/dev/null | head -1 || echo "0")
        TESTS_PASSED=$((TESTS_RUN - TESTS_FAILED))
    fi
fi

# Check for compiled test class (indicates tests were at least compiled)
TEST_CLASS_EXISTS="false"
if [ -f "$PROJECT_DIR/target/test-classes/com/example/calculator/CalculatorTest.class" ]; then
    TEST_CLASS_EXISTS="true"
fi

MAVEN_OUTPUT=""

# Escape content for JSON
TEST_ESCAPED=$(echo "$TEST_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
MAVEN_ESCAPED=$(echo "$MAVEN_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Write result JSON
RESULT_JSON=$(cat << EOF
{
    "test_file_exists": $TEST_EXISTS,
    "test_method_count": $TEST_METHOD_COUNT,
    "tests_run": $TESTS_RUN,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "test_content": $TEST_ESCAPED,
    "maven_output": $MAVEN_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
