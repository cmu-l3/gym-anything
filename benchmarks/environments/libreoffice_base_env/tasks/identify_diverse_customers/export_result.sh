#!/bin/bash
set -e
echo "=== Exporting Identify Diverse Customers Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check ODB file status
ODB_PATH="/home/ga/chinook.odb"
ODB_EXISTS="false"
ODB_MODIFIED="false"
ODB_SIZE=0

if [ -f "$ODB_PATH" ]; then
    ODB_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH")
    
    # Check modification time
    CURRENT_MTIME=$(stat -c %Y "$ODB_PATH")
    INITIAL_MTIME=$(cat /tmp/initial_odb_mtime.txt 2>/dev/null || echo "0")
    
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        ODB_MODIFIED="true"
    fi
fi

# 3. Check if LibreOffice is still running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
fi

# 4. Gracefully close LibreOffice to flush buffers to disk
# (Important because ODB is a zip file and LO holds a lock)
echo "Closing LibreOffice to ensure data is saved..."
kill_libreoffice
sleep 2

# 5. Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $ODB_EXISTS,
    "odb_modified": $ODB_MODIFIED,
    "odb_size": $ODB_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "odb_path": "$ODB_PATH"
}
EOF

# 6. Move result JSON to final location
rm -f /tmp/task_result.json
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# 7. Copy the ODB file to tmp for the verifier to access easily
if [ "$ODB_EXISTS" = "true" ]; then
    cp "$ODB_PATH" /tmp/submitted_chinook.odb
    chmod 666 /tmp/submitted_chinook.odb
fi

echo "=== Export complete ==="