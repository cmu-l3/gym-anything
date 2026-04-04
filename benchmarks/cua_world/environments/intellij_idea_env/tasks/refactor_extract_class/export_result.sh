#!/bin/bash
echo "=== Exporting refactor_extract_class result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/ecommerce-legacy"
SERVICE_PKG_DIR="$PROJECT_DIR/src/main/java/com/ecommerce/service"
GOD_CLASS="$SERVICE_PKG_DIR/CustomerService.java"
NEW_CLASS="$SERVICE_PKG_DIR/AddressValidator.java"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if new class exists
NEW_CLASS_EXISTS="false"
if [ -f "$NEW_CLASS" ]; then
    NEW_CLASS_EXISTS="true"
fi

# 3. Read file contents
GOD_CLASS_CONTENT=""
if [ -f "$GOD_CLASS" ]; then
    GOD_CLASS_CONTENT=$(cat "$GOD_CLASS" 2>/dev/null)
fi

NEW_CLASS_CONTENT=""
if [ -f "$NEW_CLASS" ]; then
    NEW_CLASS_CONTENT=$(cat "$NEW_CLASS" 2>/dev/null)
fi

# 4. Run Tests to verify logic didn't break
TEST_RESULT="unknown"
TEST_OUTPUT=""
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    cd "$PROJECT_DIR"
    # Capture output, allow failure
    TEST_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean test 2>&1)
    if [ $? -eq 0 ]; then
        TEST_RESULT="pass"
    else
        TEST_RESULT="fail"
    fi
fi

# 5. Check Modification Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED_DURING_TASK="false"
if [ -f "$GOD_CLASS" ]; then
    MOD_TIME=$(stat -c %Y "$GOD_CLASS" 2>/dev/null || echo "0")
    if [ "$MOD_TIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# 6. Escape for JSON
GOD_ESCAPED=$(echo "$GOD_CLASS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
NEW_ESCAPED=$(echo "$NEW_CLASS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OUTPUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -n 20 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# 7. Write Result
RESULT_JSON=$(cat << EOF
{
    "new_class_exists": $NEW_CLASS_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "test_result": "$TEST_RESULT",
    "test_output": $OUTPUT_ESCAPED,
    "god_class_content": $GOD_ESCAPED,
    "new_class_content": $NEW_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="