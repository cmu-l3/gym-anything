#!/bin/bash
echo "=== Exporting estimate_weibull_aep result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Task Execution Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/Documents/aep_report.txt"

# Check Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read content safely (limit size to prevent issues)
    REPORT_CONTENT=$(head -c 1000 "$REPORT_PATH")
fi

# Check QBlade State
APP_RUNNING=$(is_qblade_running)
QBLADE_WAS_RUNNING="false"
if [ "$APP_RUNNING" -gt "0" ]; then
    QBLADE_WAS_RUNNING="true"
fi

# 3. Create JSON Result
# We embed the file content into the JSON so the verifier can parse it
# Escaping content for JSON safety
SAFE_CONTENT=$(echo "$REPORT_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "report_content": $SAFE_CONTENT,
    "app_was_running": $QBLADE_WAS_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with proper permissions
write_result_json "$(cat $TEMP_JSON)" "/tmp/task_result.json"
rm -f "$TEMP_JSON"

echo "=== Export complete ==="