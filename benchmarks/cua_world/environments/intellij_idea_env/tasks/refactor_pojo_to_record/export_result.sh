#!/bin/bash
echo "=== Exporting refactor_pojo_to_record result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/banking-events"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Run Tests to verify compilation and behavior
echo "Running Maven tests..."
TEST_RESULT="unknown"
TEST_OUTPUT=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

if [ -f "$PROJECT_DIR/pom.xml" ]; then
    cd "$PROJECT_DIR"
    # Capture output
    TEST_OUTPUT=$(su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean test" 2>&1)
    MVN_EXIT_CODE=$?
    
    if [ $MVN_EXIT_CODE -eq 0 ]; then
        TEST_RESULT="pass"
    else
        TEST_RESULT="fail"
    fi

    # Parse simplified results
    TESTS_RUN=$(echo "$TEST_OUTPUT" | grep "Tests run:" | tail -1 | grep -oP "Tests run: \K\d+" || echo "0")
    TESTS_FAILED=$(echo "$TEST_OUTPUT" | grep "Tests run:" | tail -1 | grep -oP "Failures: \K\d+" || echo "0")
    TESTS_ERRORS=$(echo "$TEST_OUTPUT" | grep "Tests run:" | tail -1 | grep -oP "Errors: \K\d+" || echo "0")
    TESTS_FAILED=$((TESTS_FAILED + TESTS_ERRORS))
    TESTS_PASSED=$((TESTS_RUN - TESTS_FAILED))
fi

# 2. Read File Contents for verification
EVENT_FILE="$PROJECT_DIR/src/main/java/com/bank/events/TransactionEvent.java"
SERVICE_FILE="$PROJECT_DIR/src/main/java/com/bank/service/AuditService.java"
TEST_FILE="$PROJECT_DIR/src/test/java/com/bank/events/TransactionEventTest.java"

EVENT_CONTENT=""
SERVICE_CONTENT=""
TEST_CONTENT=""
EVENT_MTIME="0"

if [ -f "$EVENT_FILE" ]; then
    EVENT_CONTENT=$(cat "$EVENT_FILE")
    EVENT_MTIME=$(stat -c %Y "$EVENT_FILE")
fi
if [ -f "$SERVICE_FILE" ]; then
    SERVICE_CONTENT=$(cat "$SERVICE_FILE")
fi
if [ -f "$TEST_FILE" ]; then
    TEST_CONTENT=$(cat "$TEST_FILE")
fi

# 3. Check anti-gaming (was file actually modified?)
FILE_MODIFIED="false"
INITIAL_MTIME=$(cat /tmp/initial_file_mtime.txt 2>/dev/null || echo "0")
if [ "$EVENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$EVENT_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# 4. Check App Status
APP_RUNNING=$(pgrep -f "idea" > /dev/null && echo "true" || echo "false")

# 5. Escape content for JSON
EVENT_ESCAPED=$(echo "$EVENT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
SERVICE_ESCAPED=$(echo "$SERVICE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
TEST_ESCAPED=$(echo "$TEST_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OUTPUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -30 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# 6. Write Result JSON
RESULT_JSON=$(cat << EOF
{
    "test_result": "$TEST_RESULT",
    "tests_run": $TESTS_RUN,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "file_modified": $FILE_MODIFIED,
    "app_running": $APP_RUNNING,
    "event_content": $EVENT_ESCAPED,
    "service_content": $SERVICE_ESCAPED,
    "test_content": $TEST_ESCAPED,
    "build_output": $OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="