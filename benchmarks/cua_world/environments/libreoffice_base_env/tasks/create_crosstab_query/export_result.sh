#!/bin/bash
echo "=== Exporting Create Crosstab Query Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Check if LibreOffice is still running
APP_RUNNING=$(pgrep -f "soffice" > /dev/null && echo "true" || echo "false")

# 3. Save the ODB file for analysis
# We need to check if the file was actually modified
ODB_PATH="/home/ga/chinook.odb"
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
ODB_SIZE="0"

if [ -f "$ODB_PATH" ]; then
    OUTPUT_EXISTS="true"
    ODB_SIZE=$(stat -c %s "$ODB_PATH")
    OUTPUT_MTIME=$(stat -c %Y "$ODB_PATH")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Copy the ODB file to temp for the verifier to inspect
# The verifier runs outside the container, so we stage files in /tmp 
# (or rely on the framework to pull them, but copying to a known name helps)
cp "$ODB_PATH" /tmp/chinook_result.odb 2>/dev/null || true
chmod 644 /tmp/chinook_result.odb 2>/dev/null || true

# 5. Create JSON result
# We include metadata about the file execution state
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "odb_exists": $OUTPUT_EXISTS,
    "odb_modified_during_task": $FILE_MODIFIED,
    "odb_size_bytes": $ODB_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "odb_path": "/tmp/chinook_result.odb"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="