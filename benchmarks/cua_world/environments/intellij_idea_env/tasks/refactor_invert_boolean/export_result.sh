#!/bin/bash
echo "=== Exporting refactor_invert_boolean result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/order-processing-system"
ORDER_FILE="$PROJECT_DIR/src/main/java/com/example/orders/model/Order.java"
SERVICE_FILE="$PROJECT_DIR/src/main/java/com/example/orders/service/OrderService.java"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Run Maven Tests (Behavior check)
TESTS_PASSED="false"
TEST_OUTPUT=""
if [ -d "$PROJECT_DIR" ]; then
    cd "$PROJECT_DIR"
    TEST_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -q 2>&1)
    if [ $? -eq 0 ]; then
        TESTS_PASSED="true"
    fi
fi

# 2. Read file contents (Structure check)
ORDER_CONTENT=""
SERVICE_CONTENT=""
ORDER_MODIFIED="false"

if [ -f "$ORDER_FILE" ]; then
    ORDER_CONTENT=$(cat "$ORDER_FILE" 2>/dev/null)
    # Check modification time vs start time
    START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_TIME=$(stat -c %Y "$ORDER_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$START_TIME" ]; then
        ORDER_MODIFIED="true"
    fi
fi

if [ -f "$SERVICE_FILE" ]; then
    SERVICE_CONTENT=$(cat "$SERVICE_FILE" 2>/dev/null)
fi

# 3. Escape content for JSON
ORDER_ESCAPED=$(echo "$ORDER_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
SERVICE_ESCAPED=$(echo "$SERVICE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
TEST_OUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -10 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# 4. Create Result JSON
RESULT_JSON=$(cat << EOF
{
    "tests_passed": $TESTS_PASSED,
    "order_content": $ORDER_ESCAPED,
    "service_content": $SERVICE_ESCAPED,
    "order_modified": $ORDER_MODIFIED,
    "test_output_tail": $TEST_OUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="