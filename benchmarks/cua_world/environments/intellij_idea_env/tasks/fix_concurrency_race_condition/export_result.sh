#!/bin/bash
echo "=== Exporting fix_concurrency_race_condition result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/inventory-system"
SERVICE_FILE="$PROJECT_DIR/src/main/java/com/store/inventory/InventoryService.java"
TEST_FILE="$PROJECT_DIR/src/test/java/com/store/inventory/InventoryConcurrencyTest.java"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Capture file contents
SERVICE_CONTENT=""
if [ -f "$SERVICE_FILE" ]; then
    SERVICE_CONTENT=$(cat "$SERVICE_FILE")
fi

# 2. Verify Test File Integrity (Anti-gaming)
TEST_MODIFIED="false"
if [ -f "$TEST_FILE" ] && [ -f /tmp/initial_test_hash.txt ]; then
    CURRENT_HASH=$(md5sum "$TEST_FILE" | awk '{print $1}')
    INITIAL_HASH=$(awk '{print $1}' /tmp/initial_test_hash.txt)
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        TEST_MODIFIED="true"
    fi
fi

# 3. Run the tests to verify the fix
echo "Running tests..."
cd "$PROJECT_DIR"
TEST_OUTPUT=""
TEST_EXIT_CODE=1
TESTS_RUN=0
TESTS_FAILED=0
TESTS_ERRORS=0

if [ -f "pom.xml" ]; then
    # Clean output file
    TEST_LOG="/tmp/maven_test_result.log"
    
    # Run Maven test
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test > "$TEST_LOG" 2>&1
    TEST_EXIT_CODE=$?
    TEST_OUTPUT=$(tail -n 50 "$TEST_LOG")
    
    # Parse results from log or surefire reports
    REPORT_DIR="$PROJECT_DIR/target/surefire-reports"
    if [ -d "$REPORT_DIR" ]; then
        for report in "$REPORT_DIR"/*.xml; do
            if [ -f "$report" ]; then
                TR=$(grep -oP 'tests="\K[0-9]+' "$report" | head -1)
                TF=$(grep -oP 'failures="\K[0-9]+' "$report" | head -1)
                TE=$(grep -oP 'errors="\K[0-9]+' "$report" | head -1)
                TESTS_RUN=$((TESTS_RUN + ${TR:-0}))
                TESTS_FAILED=$((TESTS_FAILED + ${TF:-0}))
                TESTS_ERRORS=$((TESTS_ERRORS + ${TE:-0}))
            fi
        done
    fi
fi

# 4. Check if service file was modified
FILE_MODIFIED="false"
if [ -f "$SERVICE_FILE" ] && [ -f /tmp/initial_source_hash.txt ]; then
    CURRENT_HASH=$(md5sum "$SERVICE_FILE" | awk '{print $1}')
    INITIAL_HASH=$(awk '{print $1}' /tmp/initial_source_hash.txt)
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Escape content for JSON safely
SERVICE_ESCAPED=$(echo "$SERVICE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OUTPUT_ESCAPED=$(echo "$TEST_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "service_content": $SERVICE_ESCAPED,
    "test_output": $OUTPUT_ESCAPED,
    "mvn_exit_code": $TEST_EXIT_CODE,
    "tests_run": $TESTS_RUN,
    "tests_failed": $TESTS_FAILED,
    "tests_errors": $TESTS_ERRORS,
    "test_file_modified": $TEST_MODIFIED,
    "service_file_modified": $FILE_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="