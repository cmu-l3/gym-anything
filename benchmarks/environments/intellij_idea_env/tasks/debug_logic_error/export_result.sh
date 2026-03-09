#!/bin/bash
echo "=== Exporting debug_logic_error result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/debug-logic-error"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run tests and capture results
TEST_OUTPUT=$(su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn -q test -f '$PROJECT_DIR/pom.xml' 2>&1" || true)
BUILD_EXIT=$?
BUILD_SUCCESS="false"
[ $BUILD_EXIT -eq 0 ] && BUILD_SUCCESS="true"

# Read surefire XML report
SUREFIRE_DIR="$PROJECT_DIR/target/surefire-reports"
TESTS_RUN=0
TESTS_FAILED=0
TESTS_ERROR=0

if [ -d "$SUREFIRE_DIR" ]; then
    for xml in "$SIREFIRE_DIR"/TEST-*.xml "$SUREFIRE_DIR"/TEST-*.xml; do
        [ -f "$xml" ] || continue
        run=$(grep -o 'tests="[0-9]*"' "$xml" | grep -o '[0-9]*' | head -1)
        fail=$(grep -o 'failures="[0-9]*"' "$xml" | grep -o '[0-9]*' | head -1)
        err=$(grep -o 'errors="[0-9]*"' "$xml" | grep -o '[0-9]*' | head -1)
        TESTS_RUN=$((TESTS_RUN + ${run:-0}))
        TESTS_FAILED=$((TESTS_FAILED + ${fail:-0}))
        TESTS_ERROR=$((TESTS_ERROR + ${err:-0}))
    done
fi

# Read source file content
IMPL_SOURCE=""
TEST_SOURCE=""
if [ -f "$PROJECT_DIR/src/main/java/com/search/BinarySearch.java" ]; then
    IMPL_SOURCE=$(cat "$PROJECT_DIR/src/main/java/com/search/BinarySearch.java")
fi
if [ -f "$PROJECT_DIR/src/test/java/com/search/BinarySearchTest.java" ]; then
    TEST_SOURCE=$(cat "$PROJECT_DIR/src/test/java/com/search/BinarySearchTest.java")
fi

# Check class files exist
CLASS_EXISTS="false"
[ -f "$PROJECT_DIR/target/classes/com/search/BinarySearch.class" ] && CLASS_EXISTS="true"

# Compute checksums for integrity check
CURRENT_TEST_CHECKSUM=$(md5sum "$PROJECT_DIR/src/test/java/com/search/BinarySearchTest.java" 2>/dev/null | cut -d' ' -f1 || echo "")
INITIAL_TEST_CHECKSUM=$(cat /tmp/initial_test_checksum.txt 2>/dev/null | cut -d' ' -f1 || echo "")

# JSON-escape
IMPL_ESCAPED=$(echo "$IMPL_SOURCE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
TEST_ESCAPED=$(echo "$TEST_SOURCE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OUTPUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -30 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "build_success": $BUILD_SUCCESS,
    "tests_run": $TESTS_RUN,
    "tests_failed": $TESTS_FAILED,
    "tests_error": $TESTS_ERROR,
    "class_exists": $CLASS_EXISTS,
    "impl_source": $IMPL_ESCAPED,
    "test_source": $TEST_ESCAPED,
    "test_checksum_initial": "$INITIAL_TEST_CHECKSUM",
    "test_checksum_current": "$CURRENT_TEST_CHECKSUM",
    "mvn_output": $OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "tests_run=$TESTS_RUN failures=$TESTS_FAILED errors=$TESTS_ERROR"
echo "=== Export complete ==="
