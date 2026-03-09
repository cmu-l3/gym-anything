#!/bin/bash
echo "=== Exporting create_indexes result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check ODB file status
ODB_PATH="/home/ga/chinook.odb"
ODB_EXISTS="false"
ODB_MODIFIED="false"
ODB_SIZE="0"
ODB_MTIME="0"

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    
    # Check if modified during task
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
fi

# 2. Check if LibreOffice is still running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS="false"
if [ -f "/tmp/task_final.png" ]; then
    SCREENSHOT_EXISTS="true"
fi

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $ODB_EXISTS,
    "odb_modified_during_task": $ODB_MODIFIED,
    "odb_size_bytes": $ODB_SIZE,
    "odb_mtime": $ODB_MTIME,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="