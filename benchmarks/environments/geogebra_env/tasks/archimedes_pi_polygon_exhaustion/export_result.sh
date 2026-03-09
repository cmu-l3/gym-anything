#!/bin/bash
set -o pipefail
echo "=== Exporting Archimedes Pi task results ==="

# Source utilities if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

# Paths
OUTPUT_FILE="/home/ga/Documents/GeoGebra/projects/archimedes_pi.ggb"
START_TIME_FILE="/tmp/task_start_time.txt"
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Initialize variables
FILE_EXISTS=false
FILE_SIZE=0
FILE_MTIME=0
TASK_START_TIME=0
FILE_CREATED_DURING_TASK=false
APP_RUNNING=false

# Check if GeoGebra is running
if pgrep -f "geogebra" > /dev/null; then
    APP_RUNNING=true
fi

# Read task start time
if [ -f "$START_TIME_FILE" ]; then
    TASK_START_TIME=$(cat "$START_TIME_FILE")
fi

# Check the output file
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS=true
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo 0)
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo 0)
    
    # Verify file was created/modified AFTER task start
    if [ "$TASK_START_TIME" -gt 0 ] && [ "$FILE_MTIME" -ge "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK=true
    fi
    
    echo "Found output file: $OUTPUT_FILE ($FILE_SIZE bytes)"
else
    echo "Output file NOT found at $OUTPUT_FILE"
    # Check if saved elsewhere nearby
    FOUND_ALT=$(find /home/ga/Documents/GeoGebra -name "archimedes_pi.ggb" -print -quit)
    if [ -n "$FOUND_ALT" ]; then
        echo "Found file at alternate location: $FOUND_ALT"
        # We won't move it, but we'll note it. The verifier might not find it 
        # unless it looks at the exact path, but strict path following is part of the task.
        # However, for fairness, let's copy it to the expected location if missing
        cp "$FOUND_ALT" "$OUTPUT_FILE"
        FILE_EXISTS=true
        FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo 0)
        FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo 0)
        if [ "$TASK_START_TIME" -gt 0 ] && [ "$FILE_MTIME" -ge "$TASK_START_TIME" ]; then
            FILE_CREATED_DURING_TASK=true
        fi
    fi
fi

# Create result JSON
# We use python to ensure valid JSON formatting
python3 -c "
import json
import os

data = {
    'file_exists': $FILE_EXISTS is True,  # Shell variable substitution
    'file_path': '$OUTPUT_FILE',
    'file_size': $FILE_SIZE,
    'file_mtime': $FILE_MTIME,
    'task_start_time': $TASK_START_TIME,
    'file_created_during_task': $FILE_CREATED_DURING_TASK is True,
    'app_running': $APP_RUNNING is True,
    'screenshot_path': '/tmp/task_final.png'
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(data, f)
"

# Set permissions so verifier (running as different user potentially) can read
chmod 666 "$RESULT_JSON" 2>/dev/null || true
if [ -f "$OUTPUT_FILE" ]; then
    chmod 666 "$OUTPUT_FILE" 2>/dev/null || true
fi
if [ -f "/tmp/task_final.png" ]; then
    chmod 666 "/tmp/task_final.png" 2>/dev/null || true
fi

echo "Result JSON saved to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="