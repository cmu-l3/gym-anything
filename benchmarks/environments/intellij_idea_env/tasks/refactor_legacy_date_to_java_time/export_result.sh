#!/bin/bash
echo "=== Exporting refactor_legacy_date_to_java_time result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/flight-scheduler"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Run Tests (to verify functionality)
echo "Running Maven tests..."
TEST_RESULT="unknown"
TEST_OUTPUT=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

if [ -f "$PROJECT_DIR/pom.xml" ]; then
    cd "$PROJECT_DIR"
    # Capture both stdout and stderr
    TEST_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean test 2>&1)
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        TEST_RESULT="pass"
    else
        TEST_RESULT="fail"
    fi

    # Parse Maven output for test counts
    # Example: Tests run: 2, Failures: 0, Errors: 0, Skipped: 0
    SUMMARY_LINE=$(echo "$TEST_OUTPUT" | grep "Tests run:" | tail -1)
    if [ -n "$SUMMARY_LINE" ]; then
        TESTS_RUN=$(echo "$SUMMARY_LINE" | grep -oP 'Tests run: \K\d+')
        FAILURES=$(echo "$SUMMARY_LINE" | grep -oP 'Failures: \K\d+')
        ERRORS=$(echo "$SUMMARY_LINE" | grep -oP 'Errors: \K\d+')
        TESTS_FAILED=$((FAILURES + ERRORS))
        TESTS_PASSED=$((TESTS_RUN - TESTS_FAILED))
    fi
fi

# 2. Read File Contents
FLIGHT_CONTENT=""
SCHEDULER_CONTENT=""
TEST_CONTENT=""

if [ -f "$PROJECT_DIR/src/main/java/com/airlines/model/Flight.java" ]; then
    FLIGHT_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/airlines/model/Flight.java")
fi

if [ -f "$PROJECT_DIR/src/main/java/com/airlines/service/FlightScheduler.java" ]; then
    SCHEDULER_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/airlines/service/FlightScheduler.java")
fi

if [ -f "$PROJECT_DIR/src/test/java/com/airlines/service/FlightSchedulerTest.java" ]; then
    TEST_CONTENT=$(cat "$PROJECT_DIR/src/test/java/com/airlines/service/FlightSchedulerTest.java")
fi

# 3. Check for modification (Anti-gaming)
FLIGHT_MODIFIED="false"
SCHEDULER_MODIFIED="false"

CURRENT_FLIGHT_HASH=$(md5sum "$PROJECT_DIR/src/main/java/com/airlines/model/Flight.java" 2>/dev/null | awk '{print $1}')
INITIAL_FLIGHT_HASH=$(cat /tmp/initial_flight_hash.txt 2>/dev/null | awk '{print $1}')

if [ "$CURRENT_FLIGHT_HASH" != "$INITIAL_FLIGHT_HASH" ]; then
    FLIGHT_MODIFIED="true"
fi

# 4. Prepare JSON Result
# Using python to safely escape JSON strings
FLIGHT_ESCAPED=$(echo "$FLIGHT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
SCHEDULER_ESCAPED=$(echo "$SCHEDULER_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
TEST_FILE_ESCAPED=$(echo "$TEST_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OUTPUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -n 50 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "flight_content": $FLIGHT_ESCAPED,
    "scheduler_content": $SCHEDULER_ESCAPED,
    "test_content": $TEST_FILE_ESCAPED,
    "test_result": "$TEST_RESULT",
    "tests_run": ${TESTS_RUN:-0},
    "tests_passed": ${TESTS_PASSED:-0},
    "tests_failed": ${TESTS_FAILED:-0},
    "flight_modified": $FLIGHT_MODIFIED,
    "build_output": $OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="