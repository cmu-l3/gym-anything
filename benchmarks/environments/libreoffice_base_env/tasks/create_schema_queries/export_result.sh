#!/bin/bash
echo "=== Exporting create_schema_queries result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_odb_mtime.txt 2>/dev/null || echo "0")

ODB_PATH="/home/ga/chinook.odb"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if application was running
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# Gracefully close LibreOffice to ensure ODB is flushed to disk
# (ODB files inside ZIP might not update until save/close)
echo "Closing LibreOffice to flush buffers..."
pkill -f "soffice" 2>/dev/null || true
sleep 3

# Check file status
if [ -f "$ODB_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    
    # Check if modified
    if [ "$OUTPUT_MTIME" -gt "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_MODIFIED="false"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "odb_path": "$ODB_PATH"
}
EOF

# Save result JSON
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Copy the ODB file to tmp for the verifier to access easily
# We rename it to ensure no conflict
if [ -f "$ODB_PATH" ]; then
    cp "$ODB_PATH" /tmp/submitted_chinook.odb
    chmod 644 /tmp/submitted_chinook.odb
fi

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="