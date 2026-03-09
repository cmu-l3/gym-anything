#!/bin/bash
echo "=== Exporting Delete Playlist Records Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if ODB file was modified
ODB_PATH="/home/ga/chinook.odb"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ODB_MODIFIED="false"
ODB_MTIME=0
ODB_SIZE=0

if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    ODB_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
    
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        ODB_MODIFIED="true"
    fi
fi

# 3. Check if LibreOffice is still running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# 4. Read initial state
INITIAL_STATE=$(cat /tmp/initial_state.json 2>/dev/null || echo "{}")

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "odb_modified": $ODB_MODIFIED,
    "odb_mtime": $ODB_MTIME,
    "odb_size": $ODB_SIZE,
    "app_was_running": $APP_RUNNING,
    "initial_state": $INITIAL_STATE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="