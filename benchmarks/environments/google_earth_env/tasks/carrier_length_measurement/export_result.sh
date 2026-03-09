#!/bin/bash
echo "=== Exporting carrier_length_measurement task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot FIRST (before any other operations)
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
fi

# Check the expected output file
OUTPUT_PATH="/home/ga/Documents/carrier_measurement.kml"
KML_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KML file was created during task execution"
    else
        FILE_CREATED_DURING_TASK="false"
        echo "WARNING: KML file predates task start"
    fi
    
    # Read KML content (for coordinate extraction in verifier)
    KML_CONTENT=$(cat "$OUTPUT_PATH" 2>/dev/null | base64 -w 0 || echo "")
    echo "KML file found: $OUTPUT_SIZE bytes"
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    echo "KML file NOT found at expected path"
fi

# Check if Google Earth is running
GE_RUNNING="false"
GE_PID=""
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth-pro" | head -1)
fi

# Get window title (might contain location info)
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")

# Check for any ruler-related windows or dialogs
RULER_WINDOW_VISIBLE="false"
if echo "$GE_WINDOWS" | grep -qi "ruler"; then
    RULER_WINDOW_VISIBLE="true"
fi

# Count KML files to detect if new ones were created
FINAL_KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
INITIAL_KML_COUNT=$(cat /tmp/initial_kml_count.txt 2>/dev/null || echo "0")
NEW_KML_FILES=$((FINAL_KML_COUNT - INITIAL_KML_COUNT))

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "kml_content_base64": "$KML_CONTENT",
    "google_earth_running": $GE_RUNNING,
    "google_earth_pid": "$GE_PID",
    "window_title": "$WINDOW_TITLE",
    "ruler_window_visible": $RULER_WINDOW_VISIBLE,
    "new_kml_files_created": $NEW_KML_FILES,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_size_bytes": $SCREENSHOT_SIZE
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Task result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="