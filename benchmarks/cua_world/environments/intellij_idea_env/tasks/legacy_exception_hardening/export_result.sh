#!/bin/bash
echo "=== Exporting legacy_exception_hardening result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/legacy-service"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run the tests and capture results
TEST_OUTPUT=$(timeout 120 su - ga -c \
    "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -f '$PROJECT_DIR/pom.xml' 2>&1" || true)
BUILD_EXIT=$?
BUILD_SUCCESS="false"
[ $BUILD_EXIT -eq 0 ] && BUILD_SUCCESS="true"

# Read surefire XML reports
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
PARSER_SOURCE=""
LOGGER_SOURCE=""
CONFIG_SOURCE=""
BATCH_SOURCE=""
if [ -f "$PROJECT_DIR/src/main/java/com/legacy/RecordParser.java" ]; then
    PARSER_SOURCE=$(cat "$PROJECT_DIR/src/main/java/com/legacy/RecordParser.java")
fi
if [ -f "$PROJECT_DIR/src/main/java/com/legacy/EventLogger.java" ]; then
    LOGGER_SOURCE=$(cat "$PROJECT_DIR/src/main/java/com/legacy/EventLogger.java")
fi
if [ -f "$PROJECT_DIR/src/main/java/com/legacy/ConfigLoader.java" ]; then
    CONFIG_SOURCE=$(cat "$PROJECT_DIR/src/main/java/com/legacy/ConfigLoader.java")
fi
if [ -f "$PROJECT_DIR/src/main/java/com/legacy/BatchProcessor.java" ]; then
    BATCH_SOURCE=$(cat "$PROJECT_DIR/src/main/java/com/legacy/BatchProcessor.java")
fi

# Compute test file checksum
TEST_CHECKSUM=$(md5sum "$PROJECT_DIR/src/test/java/com/legacy/ExceptionHandlingTest.java" \
    2>/dev/null | cut -d' ' -f1 || echo "")
INITIAL_TEST_CHECKSUM=$(cat /tmp/initial_test_checksum.txt 2>/dev/null | awk '{print $1}' || echo "")

# JSON-escape content
PARSER_ESCAPED=$(echo "$PARSER_SOURCE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
LOGGER_ESCAPED=$(echo "$LOGGER_SOURCE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
CONFIG_ESCAPED=$(echo "$CONFIG_SOURCE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BATCH_ESCAPED=$(echo "$BATCH_SOURCE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OUTPUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -50 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "build_success": $BUILD_SUCCESS,
    "tests_run": $TESTS_RUN,
    "tests_failed": $TESTS_FAILED,
    "tests_error": $TESTS_ERROR,
    "test_checksum_initial": "$INITIAL_TEST_CHECKSUM",
    "test_checksum_current": "$TEST_CHECKSUM",
    "parser_source": $PARSER_ESCAPED,
    "logger_source": $LOGGER_ESCAPED,
    "config_source": $CONFIG_ESCAPED,
    "batch_source": $BATCH_ESCAPED,
    "mvn_output": $OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "tests_run=$TESTS_RUN failures=$TESTS_FAILED errors=$TESTS_ERROR"
echo "=== Export complete ==="
