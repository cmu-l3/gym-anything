#!/bin/bash
echo "=== Exporting Gas/Vapor Detection Profile Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/Desktop/gas_detection_profiles.txt"

# Check output file status
if [ -f "$REPORT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Read content for verification (limited to 10KB to prevent bloat)
    # Using base64 to safely transport text in JSON
    OUTPUT_CONTENT_B64=$(base64 -w 0 "$REPORT_PATH" 2>/dev/null || echo "")
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    FILE_CREATED_DURING_TASK="false"
    OUTPUT_CONTENT_B64=""
fi

# Check if Firefox was still running (good indicator of activity)
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
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_content_b64": "$OUTPUT_CONTENT_B64",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="