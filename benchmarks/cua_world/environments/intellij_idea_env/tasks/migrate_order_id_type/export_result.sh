#!/bin/bash
echo "=== Exporting migrate_order_id_type result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/order-service"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Read file contents for verifier (Order.java and OrderRepository.java)
ORDER_CONTENT=""
if [ -f "$PROJECT_DIR/src/main/java/com/ecommerce/model/Order.java" ]; then
    ORDER_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/ecommerce/model/Order.java" 2>/dev/null)
fi

REPO_CONTENT=""
if [ -f "$PROJECT_DIR/src/main/java/com/ecommerce/repository/OrderRepository.java" ]; then
    REPO_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/ecommerce/repository/OrderRepository.java" 2>/dev/null)
fi

# Run Build and Tests
# We do this here to avoid complex exec commands in the verifier
echo "Running Maven build..."
cd "$PROJECT_DIR"
mvn clean compile > /tmp/compile.log 2>&1
COMPILE_EXIT_CODE=$?

echo "Running Maven tests..."
mvn test > /tmp/test.log 2>&1
TEST_EXIT_CODE=$?

# Capture logs
COMPILE_LOG=$(tail -n 20 /tmp/compile.log | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
TEST_LOG=$(tail -n 20 /tmp/test.log | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Check timestamp
FILE_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c %Y "$PROJECT_DIR/src/main/java/com/ecommerce/model/Order.java" 2>/dev/null || echo "0")

if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# Escape content for JSON
ORDER_ESCAPED=$(echo "$ORDER_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
REPO_ESCAPED=$(echo "$REPO_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
RESULT_JSON=$(cat << EOF
{
    "compile_exit_code": $COMPILE_EXIT_CODE,
    "test_exit_code": $TEST_EXIT_CODE,
    "order_java_content": $ORDER_ESCAPED,
    "repository_java_content": $REPO_ESCAPED,
    "compile_log": $COMPILE_LOG,
    "test_log": $TEST_LOG,
    "file_modified_during_task": $FILE_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="