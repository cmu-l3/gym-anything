#!/bin/bash
echo "=== Exporting fix_failing_tests result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/fix-failing-tests"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run the tests and capture results
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
    for xml in "$SUREFIRE_DIR"/TEST-*.xml; do
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
TEST_SOURCE=""
IMPL_SOURCE=""
if [ -f "$PROJECT_DIR/src/test/java/com/sorts/BubbleSortTest.java" ]; then
    TEST_SOURCE=$(cat "$PROJECT_DIR/src/test/java/com/sorts/BubbleSortTest.java")
fi
if [ -f "$PROJECT_DIR/src/main/java/com/sorts/BubbleSort.java" ]; then
    IMPL_SOURCE=$(cat "$PROJECT_DIR/src/main/java/com/sorts/BubbleSort.java")
fi

# Compute current checksum of BubbleSort.java
CURRENT_CHECKSUM=""
if [ -f "$PROJECT_DIR/src/main/java/com/sorts/BubbleSort.java" ]; then
    CURRENT_CHECKSUM=$(md5sum "$PROJECT_DIR/src/main/java/com/sorts/BubbleSort.java" | cut -d' ' -f1)
fi
INITIAL_CHECKSUM=$(cat /tmp/initial_bubblesort_checksum.txt 2>/dev/null | cut -d' ' -f1 || echo "")

# JSON-escape source content
TEST_ESCAPED=$(echo "$TEST_SOURCE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
IMPL_ESCAPED=$(echo "$IMPL_SOURCE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OUTPUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -30 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "build_success": $BUILD_SUCCESS,
    "tests_run": $TESTS_RUN,
    "tests_failed": $TESTS_FAILED,
    "tests_error": $TESTS_ERROR,
    "bubblesort_checksum_initial": "$INITIAL_CHECKSUM",
    "bubblesort_checksum_current": "$CURRENT_CHECKSUM",
    "test_source": $TEST_ESCAPED,
    "impl_source": $IMPL_ESCAPED,
    "mvn_output": $OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "tests_run=$TESTS_RUN failures=$TESTS_FAILED errors=$TESTS_ERROR"
echo "=== Export complete ==="
