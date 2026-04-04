#!/bin/bash
set -e
echo "=== Exporting coordinate_polygon_entry task result ==="

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
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
fi

# Check if output KML file exists
OUTPUT_PATH="/home/ga/Documents/tfr_zone_alpha.kml"
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Copy the KML file to /tmp for easier access by verifier
    cp "$OUTPUT_PATH" /tmp/tfr_zone_alpha.kml 2>/dev/null || true
    chmod 644 /tmp/tfr_zone_alpha.kml 2>/dev/null || true
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
fi

echo "Output file exists: $OUTPUT_EXISTS"
echo "Output file size: $OUTPUT_SIZE bytes"
echo "File created during task: $FILE_CREATED_DURING_TASK"

# Also check for KMZ format (in case agent saved as KMZ)
KMZ_PATH="/home/ga/Documents/tfr_zone_alpha.kmz"
if [ -f "$KMZ_PATH" ]; then
    KMZ_EXISTS="true"
    KMZ_SIZE=$(stat -c %s "$KMZ_PATH" 2>/dev/null || echo "0")
    KMZ_MTIME=$(stat -c %Y "$KMZ_PATH" 2>/dev/null || echo "0")
    cp "$KMZ_PATH" /tmp/tfr_zone_alpha.kmz 2>/dev/null || true
else
    KMZ_EXISTS="false"
    KMZ_SIZE="0"
    KMZ_MTIME="0"
fi

# Check Google Earth My Places for the polygon
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
if [ -f "$MYPLACES_PATH" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_SIZE=$(stat -c %s "$MYPLACES_PATH" 2>/dev/null || echo "0")
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    
    # Copy myplaces.kml to /tmp for verifier access
    cp "$MYPLACES_PATH" /tmp/myplaces.kml 2>/dev/null || true
    chmod 644 /tmp/myplaces.kml 2>/dev/null || true
    
    # Check if TFR Zone Alpha is mentioned
    if grep -qi "TFR Zone Alpha" "$MYPLACES_PATH" 2>/dev/null; then
        POLYGON_IN_MYPLACES="true"
    else
        POLYGON_IN_MYPLACES="false"
    fi
else
    MYPLACES_EXISTS="false"
    MYPLACES_SIZE="0"
    MYPLACES_MTIME="0"
    POLYGON_IN_MYPLACES="false"
fi

# Check if Google Earth is still running
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# Get window information
WINDOW_INFO=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$WINDOW_INFO" ]; then
    GE_WINDOW_VISIBLE="true"
else
    GE_WINDOW_VISIBLE="false"
fi

# Create comprehensive result JSON
RESULT_FILE="/tmp/task_result.json"
cat > "$RESULT_FILE" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_file": {
        "path": "$OUTPUT_PATH",
        "exists": $OUTPUT_EXISTS,
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK
    },
    "kmz_file": {
        "exists": $KMZ_EXISTS,
        "size_bytes": $KMZ_SIZE,
        "mtime": $KMZ_MTIME
    },
    "myplaces": {
        "exists": $MYPLACES_EXISTS,
        "size_bytes": $MYPLACES_SIZE,
        "mtime": $MYPLACES_MTIME,
        "contains_polygon": $POLYGON_IN_MYPLACES
    },
    "app_state": {
        "google_earth_running": $APP_RUNNING,
        "window_visible": $GE_WINDOW_VISIBLE
    },
    "screenshot": {
        "exists": $SCREENSHOT_EXISTS,
        "path": "/tmp/task_final_state.png",
        "size_bytes": $SCREENSHOT_SIZE
    }
}
EOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo ""
echo "=== Task Result Summary ==="
cat "$RESULT_FILE"
echo ""
echo "=== Export complete ==="