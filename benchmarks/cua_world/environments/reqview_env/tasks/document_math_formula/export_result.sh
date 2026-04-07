#!/bin/bash
set -e
echo "=== Exporting document_math_formula results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define path to the SRS document JSON (where the data should be saved)
# Note: The project name matches what was set in setup_task.sh
SRS_PATH="/home/ga/Documents/ReqView/math_formula_project/documents/SRS.json"

# Check if output file was created/modified during task
if [ -f "$SRS_PATH" ]; then
    OUTPUT_MTIME=$(stat -c %Y "$SRS_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    else
        FILE_MODIFIED_DURING_TASK="false"
    fi
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$SRS_PATH" 2>/dev/null || echo "0")
else
    OUTPUT_EXISTS="false"
    FILE_MODIFIED_DURING_TASK="false"
    OUTPUT_SIZE="0"
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "reqview" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "srs_file_exists": $OUTPUT_EXISTS,
    "srs_file_modified": $FILE_MODIFIED_DURING_TASK,
    "srs_file_path": "$SRS_PATH",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="