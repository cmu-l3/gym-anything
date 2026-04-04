#!/bin/bash
set -e
echo "=== Exporting create_temporal_query results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE killing the app (to show the agent's final view)
echo "Capturing final state..."
take_screenshot /tmp/task_final.png

# Check if LibreOffice was running
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# Gracefully close LibreOffice to ensure ODB changes are flushed to disk
# We attempt to save via UI shortcut first? No, reliable way is to hope agent saved.
# But we can try to close gracefully.
pkill -f "soffice" 2>/dev/null || true
sleep 2
# Force kill if still running
pkill -9 -f "soffice" 2>/dev/null || true
sleep 1

# Check ODB file status
ODB_PATH="/home/ga/chinook.odb"
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $FILE_EXISTS,
    "odb_modified_during_task": $FILE_MODIFIED,
    "odb_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="