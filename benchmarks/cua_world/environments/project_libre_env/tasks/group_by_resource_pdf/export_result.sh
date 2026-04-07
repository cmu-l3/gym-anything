#!/bin/bash
echo "=== Exporting group_by_resource_pdf results ==="

# 1. Take final screenshot (Evidence of view state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if output file exists and get stats
OUTPUT_PATH="/home/ga/Desktop/resource_report.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

EXISTS="false"
FILE_SIZE="0"
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was modified after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 3. Check if App is still running
APP_RUNNING=$(pgrep -f "projectlibre" > /dev/null && echo "true" || echo "false")

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "output_exists": $EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_size_bytes": $FILE_SIZE,
    "file_created_during_task": $CREATED_DURING_TASK,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="