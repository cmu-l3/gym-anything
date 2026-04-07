#!/bin/bash
set -euo pipefail

echo "=== Exporting Clinical Trial ICF Format Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Read Task Start
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_PATH="/home/ga/Documents/final_icf_v2.docx"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

# Check output file and timestamps
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy file to /tmp to make it accessible for the verifier
    cp "$OUTPUT_PATH" /tmp/final_icf_v2.docx
    chmod 666 /tmp/final_icf_v2.docx
fi

APP_RUNNING=$(pgrep -f "wps" > /dev/null && echo "true" || echo "false")

# Build export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure clean move
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON written to /tmp/task_result.json"

# Close WPS Writer cleanly if it is running
echo "Closing WPS Writer..."
DISPLAY=:1 xdotool key --delay 200 alt+F4 2>/dev/null || true
sleep 2
DISPLAY=:1 xdotool key --delay 100 Tab 2>/dev/null || true
sleep 0.3
DISPLAY=:1 xdotool key --delay 100 Return 2>/dev/null || true
sleep 0.5
if pgrep -f "wps" > /dev/null; then
    DISPLAY=:1 xdotool key --delay 200 ctrl+q 2>/dev/null || true
fi

echo "=== Export Complete ==="