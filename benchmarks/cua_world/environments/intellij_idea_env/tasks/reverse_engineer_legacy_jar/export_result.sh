#!/bin/bash
echo "=== Exporting reverse_engineer_legacy_jar result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/payment-gateway"
TEST_FILE="$PROJECT_DIR/src/test/java/com/payment/gateway/TransactionTest.java"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Capture Test File Content
TEST_CONTENT=""
if [ -f "$TEST_FILE" ]; then
    TEST_CONTENT=$(cat "$TEST_FILE")
fi

# 2. Run Tests to verify
# We use 'mvn test' to authoritative check if the agent's code actually works
echo "Running validation tests..."
TEST_OUTPUT=""
TEST_RESULT="unknown"
TESTS_PASSED=0

if [ -f "$PROJECT_DIR/pom.xml" ]; then
    cd "$PROJECT_DIR"
    # Capture both stdout and stderr
    TEST_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -Dtest=TransactionTest 2>&1)
    MVN_EXIT_CODE=$?
    
    if [ $MVN_EXIT_CODE -eq 0 ]; then
        TEST_RESULT="pass"
        TESTS_PASSED=1
    else
        TEST_RESULT="fail"
    fi
fi

# 3. Check modification status
FILE_MODIFIED="false"
if [ -f /tmp/initial_test_hash.txt ]; then
    CURRENT_HASH=$(md5sum "$TEST_FILE" | awk '{print $1}')
    INITIAL_HASH=$(awk '{print $1}' /tmp/initial_test_hash.txt)
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Prepare JSON result
# Escape content for JSON safety using python
TEST_ESCAPED=$(echo "$TEST_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OUTPUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -n 50 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON
cat > /tmp/result_data.json << EOF
{
    "test_file_exists": $([ -f "$TEST_FILE" ] && echo "true" || echo "false"),
    "test_content": $TEST_ESCAPED,
    "test_output": $OUTPUT_ESCAPED,
    "mvn_exit_code": ${MVN_EXIT_CODE:-1},
    "test_result": "$TEST_RESULT",
    "file_modified": $FILE_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF

write_json_result "$(cat /tmp/result_data.json)" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="