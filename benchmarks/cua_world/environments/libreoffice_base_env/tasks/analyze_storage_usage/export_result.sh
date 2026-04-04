#!/bin/bash
echo "=== Exporting analyze_storage_usage task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Kill LibreOffice to ensure buffers are flushed to disk
kill_libreoffice

# Take final screenshot (after closing app, to show desktop state or before? 
# Usually better before, but we need the file saved. 
# Let's take one before killing in case the user left it open)
# Ideally framework takes one, but we do it here too.
# Since we just killed it, we can't take a screenshot of the app, 
# but the ODB file analysis is the primary verification.

ODB_PATH="/home/ga/chinook.odb"
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
ODB_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    OUTPUT_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH" 2>/dev/null || echo "0")
    
    CURRENT_MTIME=$(stat -c %Y "$ODB_PATH" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(cat /tmp/initial_odb_mtime.txt 2>/dev/null || echo "0")
    
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $OUTPUT_EXISTS,
    "odb_modified": $FILE_MODIFIED,
    "odb_size_bytes": $ODB_SIZE,
    "odb_path": "$ODB_PATH"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="