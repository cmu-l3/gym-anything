#!/bin/bash
echo "=== Exporting inspect_with_lens_tool task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record execution times
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Set up variables to check agent's output
OUTPUT_PATH="/home/ga/DICOM/exports/lens_inspection.png"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
VALID_PNG="false"

# Check if the output file exists
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")

    # Anti-gaming: Ensure file was created AFTER task setup
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Confirm it's actually a valid PNG file, not an empty or text file
    if file "$OUTPUT_PATH" | grep -qi "PNG image data"; then
        VALID_PNG="true"
    fi
fi

# Check if Weasis was running
APP_RUNNING="false"
if pgrep -f "weasis" > /dev/null; then
    APP_RUNNING="true"
fi

# Take final screenshot (fallback evidence)
take_screenshot /tmp/task_final.png

# Write the collected metrics to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "valid_png": $VALID_PNG,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="