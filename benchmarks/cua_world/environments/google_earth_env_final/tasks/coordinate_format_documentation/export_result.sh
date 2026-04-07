#!/bin/bash
set -euo pipefail

echo "=== Exporting Coordinate Format Documentation task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other processing
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_final_screenshot.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
fi

# Check output file
OUTPUT_PATH="/home/ga/Documents/mont_blanc_coordinates.txt"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during the task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "Output file was created during task execution"
    else
        echo "WARNING: Output file timestamp predates task start"
    fi
    
    # Read file content (escape for JSON)
    FILE_CONTENT=$(cat "$OUTPUT_PATH" 2>/dev/null | head -c 5000 | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
    echo "Output file content length: $OUTPUT_SIZE bytes"
else
    FILE_CONTENT='""'
    echo "Output file does NOT exist"
fi

# Check Google Earth state
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
fi

# Get list of all windows for debugging
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null | head -10 || echo "none")

# Create JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << JSONEOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_file": {
        "exists": $OUTPUT_EXISTS,
        "path": "$OUTPUT_PATH",
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "content": $FILE_CONTENT
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE"
    },
    "screenshot": {
        "exists": $SCREENSHOT_EXISTS,
        "path": "/tmp/task_final_screenshot.png"
    },
    "windows": "$(echo "$WINDOW_LIST" | tr '\n' ' ' | sed 's/"/\\"/g')"
}
JSONEOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json