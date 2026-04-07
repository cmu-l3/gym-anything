#!/bin/bash
set -euo pipefail

echo "=== Exporting animated_architecture_tour task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true

# Check primary output file (KMZ)
KMZ_PATH="/home/ga/Documents/architecture_tour.kmz"
KML_PATH="/home/ga/Documents/architecture_tour.kml"

OUTPUT_EXISTS="false"
OUTPUT_PATH=""
OUTPUT_FORMAT=""
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$KMZ_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_PATH="$KMZ_PATH"
    OUTPUT_FORMAT="kmz"
    OUTPUT_SIZE=$(stat -c %s "$KMZ_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$KMZ_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Found KMZ file: $KMZ_PATH (${OUTPUT_SIZE} bytes)"
elif [ -f "$KML_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_PATH="$KML_PATH"
    OUTPUT_FORMAT="kml"
    OUTPUT_SIZE=$(stat -c %s "$KML_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$KML_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Found KML file: $KML_PATH (${OUTPUT_SIZE} bytes)"
else
    echo "No output file found at $KMZ_PATH or $KML_PATH"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get current window info
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# Check Google Earth's myplaces.kml for created placemarks
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
MYPLACES_HAS_PLACEMARKS="false"
PLACEMARK_COUNT="0"
FOLDER_EXISTS="false"

if [ -f "$MYPLACES_PATH" ]; then
    PLACEMARK_COUNT=$(grep -c "<Placemark>" "$MYPLACES_PATH" 2>/dev/null || echo "0")
    if [ "$PLACEMARK_COUNT" -gt "0" ]; then
        MYPLACES_HAS_PLACEMARKS="true"
    fi
    
    if grep -qi "Modern Architecture Tour" "$MYPLACES_PATH" 2>/dev/null; then
        FOLDER_EXISTS="true"
    fi
    
    echo "MyPlaces has $PLACEMARK_COUNT placemarks, folder exists: $FOLDER_EXISTS"
fi

# List any KMZ/KML files in Documents
echo "Listing KMZ/KML files in Documents:"
ls -la /home/ga/Documents/*.kmz /home/ga/Documents/*.kml 2>/dev/null || echo "  (none found)"

# Create JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_format": "$OUTPUT_FORMAT",
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "google_earth_running": $GE_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "myplaces_has_placemarks": $MYPLACES_HAS_PLACEMARKS,
    "placemark_count_in_myplaces": $PLACEMARK_COUNT,
    "folder_exists_in_myplaces": $FOLDER_EXISTS,
    "final_screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="