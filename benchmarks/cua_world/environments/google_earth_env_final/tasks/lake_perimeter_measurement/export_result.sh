#!/bin/bash
set -euo pipefail

echo "=== Exporting Lake Perimeter Measurement task result ==="

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
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
fi

# Check expected output file
EXPECTED_OUTPUT="/home/ga/Documents/crater_lake_perimeter.kml"

if [ -f "$EXPECTED_OUTPUT" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    
    # Check if file was created/modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Copy the KML file content for verification
    cp "$EXPECTED_OUTPUT" /tmp/crater_lake_perimeter.kml 2>/dev/null || true
    
    # Extract basic info from KML
    KML_HAS_LINESTRING="false"
    KML_HAS_COORDINATES="false"
    COORD_COUNT=0
    
    if grep -q "LineString" "$EXPECTED_OUTPUT" 2>/dev/null; then
        KML_HAS_LINESTRING="true"
    fi
    
    if grep -q "<coordinates>" "$EXPECTED_OUTPUT" 2>/dev/null; then
        KML_HAS_COORDINATES="true"
        # Count approximate number of coordinate points
        COORD_COUNT=$(grep -o "," "$EXPECTED_OUTPUT" 2>/dev/null | wc -l || echo "0")
    fi
    
    echo "KML file found: $OUTPUT_SIZE bytes, modified at $OUTPUT_MTIME"
    echo "Has LineString: $KML_HAS_LINESTRING, Has coordinates: $KML_HAS_COORDINATES"
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    KML_HAS_LINESTRING="false"
    KML_HAS_COORDINATES="false"
    COORD_COUNT=0
    echo "WARNING: Expected output file not found at $EXPECTED_OUTPUT"
fi

# Check for alternative KML files in Documents
ALT_KML_FILES=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
ALT_KML_LIST=""
if [ "$ALT_KML_FILES" -gt "0" ]; then
    ALT_KML_LIST=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | tr '\n' ',' || echo "")
    echo "Found $ALT_KML_FILES KML files in Documents: $ALT_KML_LIST"
fi

# Check Google Earth state
GOOGLE_EARTH_RUNNING="false"
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GOOGLE_EARTH_RUNNING="true"
fi

# Get window title
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# Check Google Earth recent places
MYPLACES_EXISTS="false"
MYPLACES_HAS_CRATER="false"
if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
    MYPLACES_EXISTS="true"
    if grep -qi "crater" "/home/ga/.googleearth/myplaces.kml" 2>/dev/null; then
        MYPLACES_HAS_CRATER="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "kml_has_linestring": $KML_HAS_LINESTRING,
    "kml_has_coordinates": $KML_HAS_COORDINATES,
    "approx_coord_count": $COORD_COUNT,
    "alt_kml_count": $ALT_KML_FILES,
    "alt_kml_files": "$ALT_KML_LIST",
    "google_earth_running": $GOOGLE_EARTH_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "myplaces_exists": $MYPLACES_EXISTS,
    "myplaces_has_crater": $MYPLACES_HAS_CRATER,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json