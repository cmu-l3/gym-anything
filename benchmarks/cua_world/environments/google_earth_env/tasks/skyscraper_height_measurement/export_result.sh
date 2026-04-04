#!/bin/bash
set -euo pipefail

echo "=== Exporting skyscraper_height_measurement task result ==="

export DISPLAY=${DISPLAY:-:1}

# ================================================================
# Take final screenshot FIRST (before any state changes)
# ================================================================
echo "Capturing final screenshot..."
scrot /tmp/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_final_screenshot.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
fi

# ================================================================
# Record task end time
# ================================================================
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_PLACEMARK_COUNT=$(cat /tmp/initial_placemark_count.txt 2>/dev/null || echo "0")
INITIAL_MYPLACES_MTIME=$(cat /tmp/initial_myplaces_mtime.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# ================================================================
# Check for Google Earth placemark files
# ================================================================
MYPLACES_PATHS=(
    "/home/ga/.googleearth/myplaces.kml"
    "/home/ga/.config/Google/GoogleEarthPro/myplaces.kml"
    "/home/ga/.local/share/Google/GoogleEarthPro/myplaces.kml"
)

MYPLACES_FOUND=""
FINAL_PLACEMARK_COUNT=0
FINAL_MYPLACES_MTIME=0
MYPLACES_MODIFIED="false"
NEW_PLACEMARKS_CREATED="false"

for path in "${MYPLACES_PATHS[@]}"; do
    if [ -f "$path" ]; then
        MYPLACES_FOUND="$path"
        COUNT=$(grep -c "<Placemark>" "$path" 2>/dev/null || echo "0")
        FINAL_PLACEMARK_COUNT=$((FINAL_PLACEMARK_COUNT + COUNT))
        MTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$MTIME" -gt "$FINAL_MYPLACES_MTIME" ]; then
            FINAL_MYPLACES_MTIME="$MTIME"
        fi
        echo "Found myplaces at $path: $COUNT placemarks, mtime=$MTIME"
    fi
done

# Check if file was modified during task
if [ "$FINAL_MYPLACES_MTIME" -gt "$TASK_START" ]; then
    MYPLACES_MODIFIED="true"
    echo "Myplaces file was modified during task"
fi

# Check if new placemarks were created
if [ "$FINAL_PLACEMARK_COUNT" -gt "$INITIAL_PLACEMARK_COUNT" ]; then
    NEW_PLACEMARKS_CREATED="true"
    echo "New placemarks created: $((FINAL_PLACEMARK_COUNT - INITIAL_PLACEMARK_COUNT))"
fi

# ================================================================
# Copy the myplaces.kml file for verification
# ================================================================
if [ -n "$MYPLACES_FOUND" ]; then
    cp "$MYPLACES_FOUND" /tmp/myplaces_export.kml 2>/dev/null || true
    chmod 644 /tmp/myplaces_export.kml 2>/dev/null || true
    echo "Copied myplaces.kml to /tmp/myplaces_export.kml"
fi

# ================================================================
# Check if Google Earth is still running
# ================================================================
GE_RUNNING="false"
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# ================================================================
# Get window information
# ================================================================
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
GE_WINDOWS=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")

# ================================================================
# Create result JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
    "final_placemark_count": $FINAL_PLACEMARK_COUNT,
    "initial_myplaces_mtime": $INITIAL_MYPLACES_MTIME,
    "final_myplaces_mtime": $FINAL_MYPLACES_MTIME,
    "myplaces_modified": $MYPLACES_MODIFIED,
    "new_placemarks_created": $NEW_PLACEMARKS_CREATED,
    "myplaces_path": "$MYPLACES_FOUND",
    "google_earth_running": $GE_RUNNING,
    "active_window_title": "$WINDOW_TITLE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size": $SCREENSHOT_SIZE
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""