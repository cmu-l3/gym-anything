#!/bin/bash
echo "=== Exporting Decomposition Product Screening Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/decomposition_report.txt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check report file status
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT_BASE64=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Encode content for safe JSON transfer (avoid escaping issues)
    # Using base64 to ensure all characters are preserved
    REPORT_CONTENT_BASE64=$(base64 -w 0 "$REPORT_PATH")
fi

# Check if Firefox is still running (good signal, though not strictly required)
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE,
    "report_content_base64": "$REPORT_CONTENT_BASE64",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="