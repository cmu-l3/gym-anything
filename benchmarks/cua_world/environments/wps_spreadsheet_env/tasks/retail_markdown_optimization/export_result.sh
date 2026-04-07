#!/bin/bash
echo "=== Exporting retail_markdown_optimization task result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INVENTORY_FILE="/home/ga/Documents/retail_inventory.xlsx"
RESULT_FILE="/tmp/task_result.json"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$INVENTORY_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$INVENTORY_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$INVENTORY_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

APP_RUNNING="false"
if pgrep -f "et" > /dev/null; then
    APP_RUNNING="true"
fi

cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false")
}
EOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Export complete. Results:"
cat "$RESULT_FILE"