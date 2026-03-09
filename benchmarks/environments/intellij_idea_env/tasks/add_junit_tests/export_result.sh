#!/bin/bash
echo "=== Exporting add_junit_tests result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/calculator-test"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Read pom.xml
POM_CONTENT=""
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    POM_CONTENT=$(cat "$PROJECT_DIR/pom.xml" 2>/dev/null)
fi

# Find test files
TEST_FILE=""
TEST_CONTENT=""
TEST_FILE_PATH=""

# Look for test files in expected and common locations
for candidate in \
    "$PROJECT_DIR/src/test/java/com/kranonit/calculator/CalculatorTest.java" \
    "$PROJECT_DIR/src/test/java/com/kranonit/calculator/CalculatorTests.java" \
    $(find "$PROJECT_DIR/src/test" -name "*Test*.java" -o -name "*test*.java" 2>/dev/null | head -3); do
    if [ -f "$candidate" ]; then
        TEST_FILE_PATH="$candidate"
        TEST_CONTENT=$(cat "$candidate" 2>/dev/null)
        break
    fi
done

TEST_FILE_EXISTS="false"
if [ -n "$TEST_FILE_PATH" ]; then
    TEST_FILE_EXISTS="true"
fi

# Count @Test annotations
TEST_COUNT=0
if [ -n "$TEST_CONTENT" ]; then
    TEST_COUNT=$(echo "$TEST_CONTENT" | grep -c '@Test' 2>/dev/null || echo "0")
fi

# Run Maven tests
TEST_RESULT="unknown"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

if [ -f "$PROJECT_DIR/pom.xml" ]; then
    cd "$PROJECT_DIR"
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test 2>&1 > /tmp/maven_test_output.log
    if [ $? -eq 0 ]; then
        TEST_RESULT="pass"
    else
        TEST_RESULT="fail"
    fi

    # Parse surefire reports
    REPORT_DIR="$PROJECT_DIR/target/surefire-reports"
    if [ -d "$REPORT_DIR" ]; then
        for report in "$REPORT_DIR"/*.xml; do
            if [ -f "$report" ]; then
                TR=$(grep -oP 'tests="\K[0-9]+' "$report" 2>/dev/null | head -1)
                TF=$(grep -oP 'failures="\K[0-9]+' "$report" 2>/dev/null | head -1)
                TE=$(grep -oP 'errors="\K[0-9]+' "$report" 2>/dev/null | head -1)
                TESTS_RUN=$((TESTS_RUN + ${TR:-0}))
                TESTS_FAILED=$((TESTS_FAILED + ${TF:-0} + ${TE:-0}))
            fi
        done
        TESTS_PASSED=$((TESTS_RUN - TESTS_FAILED))
    fi
fi

# Escape content for JSON
POM_ESCAPED=$(echo "$POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
TEST_ESCAPED=$(echo "$TEST_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "pom_content": $POM_ESCAPED,
    "test_file_exists": $TEST_FILE_EXISTS,
    "test_file_path": "$(echo "$TEST_FILE_PATH" | sed "s|$PROJECT_DIR/||")",
    "test_content": $TEST_ESCAPED,
    "test_annotation_count": $TEST_COUNT,
    "test_result": "$TEST_RESULT",
    "tests_run": $TESTS_RUN,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
