#!/bin/bash
echo "=== Exporting create_case_query results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ODB_PATH="/home/ga/chinook.odb"

# Take final screenshot BEFORE closing the app
take_screenshot /tmp/task_final.png

# Check if LibreOffice is currently running
APP_RUNNING="false"
if is_libreoffice_running; then
    APP_RUNNING="true"
    # CRITICAL: We must close LibreOffice to ensure the ODB file (zip) is fully flushed to disk
    # and not locked, otherwise the verifier might read a corrupt/incomplete file.
    echo "Closing LibreOffice to flush changes to disk..."
    kill_libreoffice
fi

# Check file modification
FILE_MODIFIED="false"
FILE_HASH_CHANGED="false"
ODB_SIZE_BYTES="0"

if [ -f "$ODB_PATH" ]; then
    ODB_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    ODB_SIZE_BYTES=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
    
    # Check if modified after start
    if [ "$ODB_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Check if content actually changed (hash comparison)
    CURRENT_HASH=$(md5sum "$ODB_PATH" | awk '{print $1}')
    INITIAL_HASH=$(cat /tmp/initial_odb_hash.txt 2>/dev/null || echo "")
    
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        FILE_HASH_CHANGED="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "odb_path": "$ODB_PATH",
    "odb_size_bytes": $ODB_SIZE_BYTES,
    "file_modified_timestamp": $FILE_MODIFIED,
    "file_content_changed": $FILE_HASH_CHANGED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="