#!/bin/bash
echo "=== Exporting create_logger_live_template result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Locate IntelliJ config directory (handle version wildcard)
# e.g., /home/ga/.config/JetBrains/IdeaIC2023.2
CONFIG_DIR=$(find /home/ga/.config/JetBrains -maxdepth 1 -name "IdeaIC*" | head -1)
TEMPLATE_FILE="$CONFIG_DIR/templates/Custom.xml"

# Check if template file exists
TEMPLATE_EXISTS="false"
TEMPLATE_CONTENT=""
if [ -n "$CONFIG_DIR" ] && [ -f "$TEMPLATE_FILE" ]; then
    TEMPLATE_EXISTS="true"
    TEMPLATE_CONTENT=$(cat "$TEMPLATE_FILE")
fi

# Check Java file content
JAVA_FILE="/home/ga/IdeaProjects/payment-service/src/main/java/com/example/payment/PaymentService.java"
JAVA_CONTENT=""
if [ -f "$JAVA_FILE" ]; then
    JAVA_CONTENT=$(cat "$JAVA_FILE")
fi

# Check timestamps to ensure work was done during task
FILE_MODIFIED_DURING_TASK="false"
if [ "$TEMPLATE_EXISTS" = "true" ]; then
    FILE_MTIME=$(stat -c %Y "$TEMPLATE_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# Escape content for JSON safely using python
TEMPLATE_ESCAPED=$(echo "$TEMPLATE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
JAVA_ESCAPED=$(echo "$JAVA_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "template_file_exists": $TEMPLATE_EXISTS,
    "template_file_path": "$TEMPLATE_FILE",
    "template_file_content": $TEMPLATE_ESCAPED,
    "java_file_content": $JAVA_ESCAPED,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with permissions
write_json_result "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="