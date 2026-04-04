#!/bin/bash
set -euo pipefail

echo "=== Exporting Pentagon Area Measurement Task Result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_DURATION=$((TASK_END - TASK_START))

echo "Task duration: ${TASK_DURATION} seconds"

# Capture final screenshot BEFORE any other operations
echo "Capturing final screenshot..."
sleep 1
scrot /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    SCREENSHOT_EXISTS="true"
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
else
    SCREENSHOT_SIZE="0"
    SCREENSHOT_EXISTS="false"
    echo "WARNING: Could not capture final screenshot"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
GE_WINDOW_TITLE=""
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_WINDOW_TITLE=$(wmctrl -l | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
fi

# Check for Ruler window (indicates tool was used)
RULER_WINDOW_VISIBLE="false"
if wmctrl -l | grep -qi "Ruler"; then
    RULER_WINDOW_VISIBLE="true"
    echo "Ruler window detected"
fi

# Get list of all windows for debugging
ALL_WINDOWS=$(wmctrl -l 2>/dev/null | grep -v "^$" || echo "")

# Check Google Earth state files for any evidence of activity
GE_STATE_DIR="/home/ga/.googleearth"
MYPLACES_MODIFIED="false"
MYPLACES_MTIME="0"

if [ -f "$GE_STATE_DIR/myplaces.kml" ]; then
    MYPLACES_MTIME=$(stat -c %Y "$GE_STATE_DIR/myplaces.kml" 2>/dev/null || echo "0")
    if [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        MYPLACES_MODIFIED="true"
    fi
fi

# Check for any KML/KMZ files that might contain polygon data
KML_FILES_COUNT=$(find /home/ga -name "*.kml" -o -name "*.kmz" 2>/dev/null | wc -l || echo "0")

# Create JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_id": "pentagon_area_measurement@1",
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $TASK_DURATION,
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "ruler_window_visible": $RULER_WINDOW_VISIBLE,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_bytes": $SCREENSHOT_SIZE,
    "screenshot_path": "/tmp/task_final.png",
    "initial_screenshot_path": "/tmp/task_initial.png",
    "myplaces_modified": $MYPLACES_MODIFIED,
    "myplaces_mtime": $MYPLACES_MTIME,
    "kml_files_count": $KML_FILES_COUNT,
    "all_windows": "$(echo "$ALL_WINDOWS" | tr '\n' '|' | sed 's/"/\\"/g')"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="