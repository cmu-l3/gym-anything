#!/bin/bash
set -e
echo "=== Exporting Create Form Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE closing app (to see if form is open)
take_screenshot /tmp/task_final.png

# Check if app was running
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# Save the database (force save might not be possible via script, assume agent saved)
# We need to kill LibreOffice to ensure the ODB file lock is released and data flushed to ZIP
kill_libreoffice

# Check ODB file
ODB_PATH="/home/ga/chinook.odb"
if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH")
    ODB_MTIME=$(stat -c %Y "$ODB_PATH")
    
    # Check if file was modified
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
else
    ODB_EXISTS="false"
    ODB_SIZE=0
    FILE_MODIFIED="false"
fi

# Prepare result for export
# We copy the ODB to a temp location that the verifier can access easily via copy_from_env
cp "$ODB_PATH" /tmp/submission.odb 2>/dev/null || true
chmod 644 /tmp/submission.odb 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $FILE_MODIFIED,
    "odb_size": $ODB_SIZE,
    "app_was_running": $APP_RUNNING,
    "submission_path": "/tmp/submission.odb"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"