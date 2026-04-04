#!/bin/bash
echo "=== Exporting implement_annotation_validator result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/chinook-validator"
VALIDATION_PKG="$PROJECT_DIR/src/main/java/com/chinook/validation"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Check if test file was modified (Anti-gaming)
TEST_MODIFIED="false"
if [ -f /tmp/initial_test_hash.txt ]; then
    CURRENT_HASH=$(md5sum "$PROJECT_DIR/src/test/java/com/chinook/validation/ValidatorTest.java" | awk '{print $1}')
    INITIAL_HASH=$(awk '{print $1}' /tmp/initial_test_hash.txt)
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        TEST_MODIFIED="true"
    fi
fi

# 2. Run Tests
echo "Running tests..."
cd "$PROJECT_DIR"
TEST_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -Dmaven.test.failure.ignore=true 2>&1)
COMPILE_STATUS=$?

# 3. Parse Test Results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_ERROR=0

REPORT_DIR="$PROJECT_DIR/target/surefire-reports"
if [ -d "$REPORT_DIR" ]; then
    for xml in "$REPORT_DIR"/*.xml; do
        if [ -f "$xml" ]; then
            TR=$(grep -oP 'tests="\K[0-9]+' "$xml" | head -1)
            TF=$(grep -oP 'failures="\K[0-9]+' "$xml" | head -1)
            TE=$(grep -oP 'errors="\K[0-9]+' "$xml" | head -1)
            
            TESTS_RUN=$((TESTS_RUN + ${TR:-0}))
            TESTS_FAILED=$((TESTS_FAILED + ${TF:-0}))
            TESTS_ERROR=$((TESTS_ERROR + ${TE:-0}))
        fi
    done
    TESTS_PASSED=$((TESTS_RUN - TESTS_FAILED - TESTS_ERROR))
fi

# 4. Read Source Files for Verification (Check for reflection usage)
VALIDATOR_CONTENT=""
NOTNULL_CONTENT=""
RANGE_CONTENT=""

if [ -f "$VALIDATION_PKG/Validator.java" ]; then
    VALIDATOR_CONTENT=$(cat "$VALIDATION_PKG/Validator.java")
fi
if [ -f "$VALIDATION_PKG/NotNull.java" ]; then
    NOTNULL_CONTENT=$(cat "$VALIDATION_PKG/NotNull.java")
fi
if [ -f "$VALIDATION_PKG/Range.java" ]; then
    RANGE_CONTENT=$(cat "$VALIDATION_PKG/Range.java")
fi

# Escape content for JSON
V_ESC=$(echo "$VALIDATOR_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
N_ESC=$(echo "$NOTNULL_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
R_ESC=$(echo "$RANGE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

# Create Result JSON
RESULT_JSON=$(cat << EOF
{
    "compile_status": $COMPILE_STATUS,
    "tests_run": $TESTS_RUN,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "tests_error": $TESTS_ERROR,
    "test_file_modified": $TEST_MODIFIED,
    "validator_content": $V_ESC,
    "notnull_content": $N_ESC,
    "range_content": $R_ESC,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="