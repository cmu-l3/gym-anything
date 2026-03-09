#!/bin/bash
echo "=== Exporting Create String Query Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_odb_mtime.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE closing app (to see if they left it open)
take_screenshot /tmp/task_final.png

# Check if LO is running
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# CRITICAL: Close LibreOffice to flush changes to the ODB zip file
# If we don't close it, the .odb file might be locked or not fully written
echo "Closing LibreOffice to save state..."
kill_libreoffice
sleep 2

# Check ODB file status
ODB_PATH="/home/ga/chinook.odb"
ODB_EXISTS="false"
ODB_MODIFIED="false"
ODB_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH")
    CURRENT_MTIME=$(stat -c %Y "$ODB_PATH")
    
    # Check modification time
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        ODB_MODIFIED="true"
    fi
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_size": $ODB_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Copy ODB file for verification
# We rename it to result.odb to be clear it's the output
if [ "$ODB_EXISTS" = "true" ]; then
    cp "$ODB_PATH" /tmp/result.odb
    chmod 644 /tmp/result.odb
fi

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result export complete."
cat /tmp/task_result.json