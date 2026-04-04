#!/bin/bash
echo "=== Exporting Task Result ==="

# Source utilities for screenshot and process checks
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot (Trajectory Evidence)
take_screenshot /tmp/task_final.png

# 2. Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check if LibreOffice is still running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
    # Close it gracefully to ensure ODB is fully flushed to disk
    # (LibreOffice sometimes holds a lock or temp files until close)
    # We use xdotool to try to close it via UI first (Ctrl+Q)
    DISPLAY=:1 xdotool key ctrl+q 2>/dev/null || true
    sleep 2
    kill_libreoffice
fi

# 4. Check the Database File
ODB_PATH="/home/ga/chinook.odb"
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
OUTPUT_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    
    # Verify it was modified during the task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 5. Create Result JSON
# We don't analyze the ODB here (it's complex XML in a ZIP).
# We export the file status and let the Python verifier handle the parsing.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $OUTPUT_EXISTS,
    "odb_modified_during_task": $FILE_MODIFIED,
    "odb_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "odb_path": "$ODB_PATH"
}
EOF

# 6. Save Result and Clean Up
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="