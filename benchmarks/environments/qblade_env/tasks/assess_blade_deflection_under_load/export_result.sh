#!/bin/bash
echo "=== Exporting assess_blade_deflection_under_load result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check Report File
REPORT_PATH="/home/ga/Documents/deflection_report.txt"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content safely (limit size)
    CONTENT=$(head -n 20 "$REPORT_PATH" | base64 -w 0)
fi

# 4. Check if QBlade is running
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $FILE_EXISTS,
    "report_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content_base64": "$CONTENT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Save to final location
write_result_json "$(cat $TEMP_JSON)" "/tmp/task_result.json"
rm -f "$TEMP_JSON"

echo "=== Export complete ==="