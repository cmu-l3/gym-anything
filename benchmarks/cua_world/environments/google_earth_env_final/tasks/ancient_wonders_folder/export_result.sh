#!/bin/bash
set -e
echo "=== Exporting Ancient Wonders Folder task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot FIRST (before any state changes)
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_final_screenshot.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
else
    echo "WARNING: Could not capture final screenshot"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
GE_PID=""
if pgrep -f google-earth-pro > /dev/null; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f google-earth-pro | head -1)
    echo "Google Earth Pro is running (PID: $GE_PID)"
else
    echo "WARNING: Google Earth Pro is not running"
fi

# Force Google Earth to save places before we read them
if [ "$GE_RUNNING" = "true" ]; then
    echo "Triggering save in Google Earth..."
    # Focus window and send Ctrl+S to save
    DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
    sleep 1
    DISPLAY=:1 xdotool key ctrl+s 2>/dev/null || true
    sleep 2
fi

# Find myplaces.kml file
MYPLACES_FILE=""
MYPLACES_PRIMARY="/home/ga/.googleearth/myplaces.kml"
MYPLACES_ALT="/home/ga/.config/Google/googleearth/myplaces.kml"

if [ -f "$MYPLACES_PRIMARY" ]; then
    MYPLACES_FILE="$MYPLACES_PRIMARY"
elif [ -f "$MYPLACES_ALT" ]; then
    MYPLACES_FILE="$MYPLACES_ALT"
fi

# Get myplaces file information
MYPLACES_EXISTS="false"
MYPLACES_MTIME="0"
MYPLACES_SIZE="0"
MYPLACES_CONTENT=""

if [ -n "$MYPLACES_FILE" ] && [ -f "$MYPLACES_FILE" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
    MYPLACES_SIZE=$(stat -c %s "$MYPLACES_FILE" 2>/dev/null || echo "0")
    
    # Copy to accessible location for verifier
    cp "$MYPLACES_FILE" /tmp/myplaces_final.kml 2>/dev/null || true
    chmod 666 /tmp/myplaces_final.kml 2>/dev/null || true
    
    echo "myplaces.kml found: $MYPLACES_FILE"
    echo "  Size: $MYPLACES_SIZE bytes"
    echo "  Modified: $MYPLACES_MTIME"
fi

# Compare with initial state
INITIAL_MTIME=$(cat /tmp/myplaces_initial_mtime.txt 2>/dev/null || echo "0")
INITIAL_SIZE=$(cat /tmp/myplaces_initial_size.txt 2>/dev/null || echo "0")
INITIAL_PLACEMARK_COUNT=$(cat /tmp/initial_placemark_count.txt 2>/dev/null || echo "0")

FILE_MODIFIED="false"
if [ "$MYPLACES_MTIME" -gt "$INITIAL_MTIME" ]; then
    FILE_MODIFIED="true"
    echo "myplaces.kml was modified during task"
elif [ "$MYPLACES_SIZE" -ne "$INITIAL_SIZE" ]; then
    FILE_MODIFIED="true"
    echo "myplaces.kml size changed during task"
fi

# Count current placemarks
CURRENT_PLACEMARK_COUNT="0"
if [ -f /tmp/myplaces_final.kml ]; then
    CURRENT_PLACEMARK_COUNT=$(grep -c "<Placemark" /tmp/myplaces_final.kml 2>/dev/null || echo "0")
fi
echo "Current placemark count: $CURRENT_PLACEMARK_COUNT (was: $INITIAL_PLACEMARK_COUNT)"

# Check for Ancient Wonders folder
FOLDER_EXISTS="false"
if [ -f /tmp/myplaces_final.kml ]; then
    if grep -qi "ancient.*wonders" /tmp/myplaces_final.kml 2>/dev/null; then
        FOLDER_EXISTS="true"
        echo "Ancient Wonders folder detected in KML"
    fi
fi

# Get window titles for evidence
WINDOW_TITLES=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "google earth" || echo "none")
echo "Google Earth windows: $WINDOW_TITLES"

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "google_earth_running": $GE_RUNNING,
    "myplaces_exists": $MYPLACES_EXISTS,
    "myplaces_path": "$MYPLACES_FILE",
    "myplaces_mtime": $MYPLACES_MTIME,
    "myplaces_size": $MYPLACES_SIZE,
    "initial_mtime": $INITIAL_MTIME,
    "initial_size": $INITIAL_SIZE,
    "file_modified": $FILE_MODIFIED,
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "current_placemark_count": $CURRENT_PLACEMARK_COUNT,
    "folder_exists": $FOLDER_EXISTS,
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "myplaces_kml_path": "/tmp/myplaces_final.kml",
    "timestamp": "$(date -Iseconds)"
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