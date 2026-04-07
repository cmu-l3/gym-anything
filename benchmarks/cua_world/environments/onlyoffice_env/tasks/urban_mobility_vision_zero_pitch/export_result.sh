#!/bin/bash
set -euo pipefail

echo "=== Exporting Vision Zero Pitch Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_PATH="/home/ga/Documents/Presentations/Vision_Zero/vision_zero_pitch.pptx"

# Take final screenshot BEFORE closing ONLYOFFICE
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Attempt to save cleanly if ONLYOFFICE is running
if pgrep -f "onlyoffice" > /dev/null; then
    # Focus and send Ctrl+S just in case the agent forgot to save at the very end
    DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 2
    
    # Send Ctrl+Q to close
    DISPLAY=:1 xdotool key ctrl+q 2>/dev/null || true
    sleep 2
fi

# Hard kill if it's still running
pkill -f "onlyoffice" 2>/dev/null || true
sleep 1

# Check output file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Generate result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_path": "$OUTPUT_PATH"
}
EOF

# Move JSON to final accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export completed. Results saved to /tmp/task_result.json:"
cat /tmp/task_result.json