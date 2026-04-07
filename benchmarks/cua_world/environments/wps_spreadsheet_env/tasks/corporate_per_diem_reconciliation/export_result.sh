#!/bin/bash
echo "=== Exporting corporate_per_diem_reconciliation result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
WORKBOOK_PATH="/home/ga/Documents/travel_reconciliation.xlsx"

# Take final screenshot BEFORE closing anything
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file modification
OUTPUT_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$WORKBOOK_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$WORKBOOK_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$WORKBOOK_PATH" 2>/dev/null || echo "0")
    
    # Give a 2-second grace period for setup script writes
    if [ "$OUTPUT_MTIME" -gt "$((TASK_START + 2))" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# Check if WPS was running
APP_RUNNING=$(pgrep -f "et" > /dev/null && echo "true" || echo "false")

# Create JSON result
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

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="