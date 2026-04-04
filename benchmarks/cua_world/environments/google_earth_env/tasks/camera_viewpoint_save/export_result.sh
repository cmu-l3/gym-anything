#!/bin/bash
set -e
echo "=== Exporting camera_viewpoint_save task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Taking final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Check myplaces.kml
MYPLACES="/home/ga/.googleearth/myplaces.kml"
MYPLACES_EXISTS="false"
MYPLACES_MTIME="0"
MYPLACES_SIZE="0"
FILE_MODIFIED_DURING_TASK="false"
PLACEMARK_COUNT="0"

if [ -f "$MYPLACES" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES" 2>/dev/null || echo "0")
    MYPLACES_SIZE=$(stat -c %s "$MYPLACES" 2>/dev/null || echo "0")
    PLACEMARK_COUNT=$(grep -c "<Placemark>" "$MYPLACES" 2>/dev/null || echo "0")
    
    # Check if file was modified during task
    if [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
fi

# Get initial state for comparison
INITIAL_COUNT="0"
INITIAL_MTIME="0"
if [ -f /tmp/initial_state.json ]; then
    INITIAL_COUNT=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_placemark_count', 0))" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('initial_mtime', 0))" 2>/dev/null || echo "0")
fi

# Calculate new placemarks
NEW_PLACEMARKS=$((PLACEMARK_COUNT - INITIAL_COUNT))

# Check if Google Earth is still running
GE_RUNNING="false"
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get window title
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# Copy myplaces.kml to accessible location for verification
if [ -f "$MYPLACES" ]; then
    cp "$MYPLACES" /tmp/myplaces_final.kml 2>/dev/null || true
    chmod 644 /tmp/myplaces_final.kml 2>/dev/null || true
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "myplaces_exists": $MYPLACES_EXISTS,
    "myplaces_mtime": $MYPLACES_MTIME,
    "myplaces_size_bytes": $MYPLACES_SIZE,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "initial_placemark_count": $INITIAL_COUNT,
    "final_placemark_count": $PLACEMARK_COUNT,
    "new_placemarks_created": $NEW_PLACEMARKS,
    "google_earth_running": $GE_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "final_screenshot": "/tmp/task_final_state.png",
    "myplaces_copy": "/tmp/myplaces_final.kml"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task Result Summary ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="