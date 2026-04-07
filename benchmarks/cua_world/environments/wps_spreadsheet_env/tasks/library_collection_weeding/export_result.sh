#!/bin/bash
echo "=== Exporting task result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_mtime.txt 2>/dev/null || echo "0")
INVENTORY_FILE="/home/ga/Documents/library_inventory.xlsx"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check file status
FILE_EXISTS="false"
FILE_MODIFIED="false"
CURRENT_MTIME="0"
FILE_SIZE="0"

if [ -f "$INVENTORY_FILE" ]; then
    FILE_EXISTS="true"
    CURRENT_MTIME=$(stat -c %Y "$INVENTORY_FILE" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c %s "$INVENTORY_FILE" 2>/dev/null || echo "0")
    
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$INITIAL_MTIME" != "0" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Determine if WPS is running
APP_RUNNING="false"
if pgrep -x "et" > /dev/null 2>&1; then
    APP_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "initial_mtime": $INITIAL_MTIME,
    "current_mtime": $CURRENT_MTIME,
    "file_size_bytes": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safely move JSON to world-readable location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="