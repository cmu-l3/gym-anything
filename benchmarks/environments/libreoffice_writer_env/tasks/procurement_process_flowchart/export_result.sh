#!/bin/bash
echo "=== Exporting Procurement Flowchart Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/procurement_flow.odt"

# Check output file status
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if created/modified during task
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

# Capture final screenshot for VLM verification
echo "Capturing final screenshot..."
# Ensure Writer is focused for the screenshot
WID=$(get_writer_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 0.5
fi
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# JSON Result Generation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "file_created_during_task": $FILE_VALID_TIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="