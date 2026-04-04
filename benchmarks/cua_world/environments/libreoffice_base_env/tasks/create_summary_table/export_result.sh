#!/bin/bash
echo "=== Exporting create_summary_table result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_HASH=$(cat /tmp/initial_odb_hash.txt 2>/dev/null || echo "0")

ODB_PATH="/home/ga/chinook.odb"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file status
if [ -f "$ODB_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    CURRENT_HASH=$(md5sum "$ODB_PATH" 2>/dev/null | awk '{print $1}')
    
    # Verify modification
    if [ "$FILE_MTIME" -gt "$TASK_START" ] && [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
else
    FILE_EXISTS="false"
    FILE_SIZE="0"
    FILE_MODIFIED="false"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "odb_path": "$ODB_PATH"
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# CRITICAL: Copy the ODB file to /tmp/task_output.odb so verifier can access it
# (The verifier runs on host and needs to 'copy_from_env' this file)
if [ "$FILE_EXISTS" = "true" ]; then
    cp "$ODB_PATH" /tmp/task_output.odb
    chmod 666 /tmp/task_output.odb
fi

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="