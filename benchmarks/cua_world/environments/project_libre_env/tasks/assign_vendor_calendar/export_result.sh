#!/bin/bash
echo "=== Exporting assign_vendor_calendar results ==="

# Define paths
OUTPUT_PATH="/home/ga/Projects/vendor_schedule_project.xml"
TASK_START_FILE="/tmp/task_start_time.txt"
RESULT_JSON="/tmp/task_result.json"

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

# Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Check if application is still running
APP_RUNNING=$(pgrep -f "projectlibre" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Generate result JSON
# Note: We do NOT parse the XML here; we leave that to the Python verifier for robustness
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_path": "$OUTPUT_PATH",
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location safely
rm -f "$RESULT_JSON" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="