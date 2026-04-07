#!/bin/bash
echo "=== Exporting digital_ad_roas_analysis task results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_FILE="/home/ga/Documents/digital_ad_performance.xlsx"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

if [ -f "$TARGET_FILE" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    else
        FILE_MODIFIED_DURING_TASK="false"
    fi
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
else
    OUTPUT_EXISTS="false"
    FILE_MODIFIED_DURING_TASK="false"
    OUTPUT_SIZE="0"
fi

APP_RUNNING=$(pgrep -x "et" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="