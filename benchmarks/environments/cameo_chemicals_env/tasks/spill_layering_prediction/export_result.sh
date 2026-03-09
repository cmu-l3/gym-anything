#!/bin/bash
echo "=== Exporting Spill Layering Prediction Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

OUTPUT_FILE="/home/ga/Desktop/spill_layering_results.txt"

# Check output file status
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Anti-gaming: Check if file was modified after task started
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_VALID_TIME="true"
    else
        FILE_VALID_TIME="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_VALID_TIME="false"
fi

# Check if Firefox is still running (good indicator of activity)
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_valid_time": $FILE_VALID_TIME,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to final location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result summary saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="