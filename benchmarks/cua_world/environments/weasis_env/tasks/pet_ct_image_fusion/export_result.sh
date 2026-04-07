#!/bin/bash
echo "=== Exporting PET/CT Image Fusion results ==="

# Record task end and start times
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE closing anything
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

OUTPUT_PATH="/home/ga/DICOM/exports/fusion_view.jpg"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

# Fallback: Allow PNG if the agent explicitly exported as PNG instead of JPEG
if [ ! -f "$OUTPUT_PATH" ] && [ -f "/home/ga/DICOM/exports/fusion_view.png" ]; then
    OUTPUT_PATH="/home/ga/DICOM/exports/fusion_view.png"
fi

# Check for exported file properties
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Anti-gaming: Ensure file was made AFTER the task began
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
fi

# Verify the app was actually running at the end
APP_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

# Create JSON result payload using temp file for permission safety
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "output_path": "$OUTPUT_PATH",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy into target extraction point
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="