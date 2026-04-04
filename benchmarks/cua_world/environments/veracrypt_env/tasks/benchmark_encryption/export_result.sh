#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Benchmark Result ==="

REPORT_PATH="/home/ga/Documents/benchmark_report.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Report File Stats
REPORT_EXISTS="false"
REPORT_SIZE=0
FILE_CREATED_DURING_TASK="false"
REPORT_CONTENT_B64=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c%Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Read content and encode to base64 to safely embed in JSON
    # (Avoids issues with newlines/quotes in the report text)
    REPORT_CONTENT_B64=$(base64 -w 0 "$REPORT_PATH")
fi

# 3. Check if VeraCrypt is still running
APP_RUNNING="false"
if is_veracrypt_running; then
    APP_RUNNING="true"
fi

# 4. Create JSON Result
# We use a temp file and move it to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_size_bytes": $REPORT_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_content_base64": "$REPORT_CONTENT_B64",
    "app_running": $APP_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="