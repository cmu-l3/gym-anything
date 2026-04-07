#!/bin/bash
echo "=== Exporting dam_crest_measurement_itaipu task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot of application state
echo "Capturing final state screenshot..."
scrot /tmp/task_final_state.png 2>/dev/null || \
    import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    FINAL_SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# Check measurement file
MEASUREMENT_FILE="/home/ga/dam_measurement.txt"
if [ -f "$MEASUREMENT_FILE" ]; then
    MEASUREMENT_EXISTS="true"
    MEASUREMENT_SIZE=$(stat -c %s "$MEASUREMENT_FILE" 2>/dev/null || echo "0")
    MEASUREMENT_MTIME=$(stat -c %Y "$MEASUREMENT_FILE" 2>/dev/null || echo "0")
    MEASUREMENT_CONTENT=$(cat "$MEASUREMENT_FILE" 2>/dev/null | head -20 || echo "")
    
    # Check if file was created during task
    if [ "$MEASUREMENT_MTIME" -gt "$TASK_START" ]; then
        MEASUREMENT_CREATED_DURING_TASK="true"
    else
        MEASUREMENT_CREATED_DURING_TASK="false"
    fi
    
    # Extract measured value using grep/sed
    MEASURED_VALUE=$(grep -i "Measured Length:" "$MEASUREMENT_FILE" 2>/dev/null | \
        sed 's/.*Measured Length:[[:space:]]*\([0-9,.]*\).*/\1/' | \
        tr -d ',' || echo "")
    
    echo "Measurement file found:"
    echo "  Size: ${MEASUREMENT_SIZE} bytes"
    echo "  Modified: ${MEASUREMENT_MTIME}"
    echo "  Created during task: ${MEASUREMENT_CREATED_DURING_TASK}"
    echo "  Extracted value: ${MEASURED_VALUE}"
else
    MEASUREMENT_EXISTS="false"
    MEASUREMENT_SIZE="0"
    MEASUREMENT_MTIME="0"
    MEASUREMENT_CONTENT=""
    MEASUREMENT_CREATED_DURING_TASK="false"
    MEASURED_VALUE=""
    echo "Measurement file NOT found"
fi

# Check screenshot file
SCREENSHOT_FILE="/home/ga/dam_screenshot.png"
if [ -f "$SCREENSHOT_FILE" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$SCREENSHOT_FILE" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c %Y "$SCREENSHOT_FILE" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    else
        SCREENSHOT_CREATED_DURING_TASK="false"
    fi
    
    # Verify it's a valid image
    if file "$SCREENSHOT_FILE" 2>/dev/null | grep -qi "image\|png\|jpeg"; then
        SCREENSHOT_VALID="true"
    else
        SCREENSHOT_VALID="false"
    fi
    
    echo "Screenshot file found:"
    echo "  Size: ${SCREENSHOT_SIZE} bytes"
    echo "  Modified: ${SCREENSHOT_MTIME}"
    echo "  Created during task: ${SCREENSHOT_CREATED_DURING_TASK}"
    echo "  Valid image: ${SCREENSHOT_VALID}"
else
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
    SCREENSHOT_MTIME="0"
    SCREENSHOT_CREATED_DURING_TASK="false"
    SCREENSHOT_VALID="false"
    echo "Screenshot file NOT found"
fi

# Check if Google Earth is still running
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GOOGLE_EARTH_RUNNING="true"
else
    GOOGLE_EARTH_RUNNING="false"
fi

# Get Google Earth window title if available
GE_WINDOW_TITLE=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")

# Create JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape content for JSON
ESCAPED_CONTENT=$(echo "$MEASUREMENT_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')

cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "measurement_file": {
        "exists": $MEASUREMENT_EXISTS,
        "size_bytes": $MEASUREMENT_SIZE,
        "mtime": $MEASUREMENT_MTIME,
        "created_during_task": $MEASUREMENT_CREATED_DURING_TASK,
        "measured_value": "$MEASURED_VALUE",
        "content": $ESCAPED_CONTENT
    },
    "screenshot_file": {
        "exists": $SCREENSHOT_EXISTS,
        "size_bytes": $SCREENSHOT_SIZE,
        "mtime": $SCREENSHOT_MTIME,
        "created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
        "valid_image": $SCREENSHOT_VALID
    },
    "google_earth_running": $GOOGLE_EARTH_RUNNING,
    "window_title": "$GE_WINDOW_TITLE",
    "final_screenshot_path": "/tmp/task_final_state.png",
    "final_screenshot_size": $FINAL_SCREENSHOT_SIZE
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json