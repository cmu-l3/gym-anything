#!/bin/bash
echo "=== Exporting Accounts Receivable task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
FILE_PATH="/home/ga/Documents/ar_data.xlsx"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if file was saved/modified
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check if app is still running
APP_RUNNING="false"
if pgrep -x "et" > /dev/null; then
    APP_RUNNING="true"
fi

# Write metadata to result JSON
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING
}
EOF

# Move to standard location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="