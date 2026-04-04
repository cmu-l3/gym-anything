#!/bin/bash
set -e
echo "=== Exporting Date Line Measurement Task Result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot FIRST (before any state changes)
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
    FINAL_SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    FINAL_SCREENSHOT_EXISTS="false"
    FINAL_SCREENSHOT_SIZE="0"
fi

# Check if KML output file exists
OUTPUT_PATH="/home/ga/Documents/diomede_measurement.kml"
KML_EXISTS="false"
KML_SIZE="0"
KML_MTIME="0"
FILE_CREATED_DURING_TASK="false"
KML_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    KML_EXISTS="true"
    KML_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    KML_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task (anti-gaming)
    if [ "$KML_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KML file was created during task execution"
    else
        echo "WARNING: KML file exists but was NOT created during task"
    fi
    
    # Read KML content for verification (escape for JSON)
    KML_CONTENT=$(cat "$OUTPUT_PATH" 2>/dev/null | head -c 50000 | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
    echo "KML file found: $OUTPUT_PATH ($KML_SIZE bytes)"
else
    echo "KML file NOT found at $OUTPUT_PATH"
    KML_CONTENT='""'
fi

# Also check for KMZ format (compressed KML)
KMZ_PATH="/home/ga/Documents/diomede_measurement.kmz"
KMZ_EXISTS="false"
if [ -f "$KMZ_PATH" ]; then
    KMZ_EXISTS="true"
    echo "KMZ file also found: $KMZ_PATH"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
GE_PID=""
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f google-earth-pro | head -1)
    echo "Google Earth is running (PID: $GE_PID)"
else
    echo "Google Earth is NOT running"
fi

# Get current window title
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
echo "Active window: $WINDOW_TITLE"

# Check Google Earth's myplaces.kml for recent changes
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
MYPLACES_EXISTS="false"
MYPLACES_MTIME="0"
MYPLACES_MODIFIED_DURING_TASK="false"

if [ -f "$MYPLACES_PATH" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    if [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        MYPLACES_MODIFIED_DURING_TASK="true"
        echo "myplaces.kml was modified during task"
    fi
fi

# List all KML/KMZ files in Documents directory
echo ""
echo "KML/KMZ files in Documents:"
ls -la /home/ga/Documents/*.kml /home/ga/Documents/*.kmz 2>/dev/null || echo "None found"

# Create JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "kml_exists": $KML_EXISTS,
    "kml_size_bytes": $KML_SIZE,
    "kml_mtime": $KML_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "kml_content": $KML_CONTENT,
    "kmz_exists": $KMZ_EXISTS,
    "google_earth_running": $GE_RUNNING,
    "google_earth_pid": "$GE_PID",
    "window_title": "$WINDOW_TITLE",
    "myplaces_exists": $MYPLACES_EXISTS,
    "myplaces_mtime": $MYPLACES_MTIME,
    "myplaces_modified_during_task": $MYPLACES_MODIFIED_DURING_TASK,
    "final_screenshot_exists": $FINAL_SCREENSHOT_EXISTS,
    "final_screenshot_size": $FINAL_SCREENSHOT_SIZE,
    "output_path": "$OUTPUT_PATH"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result Summary ==="
cat /tmp/task_result.json | python3 -m json.tool 2>/dev/null || cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="