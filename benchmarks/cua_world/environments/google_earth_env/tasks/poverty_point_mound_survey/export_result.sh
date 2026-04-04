#!/bin/bash
set -e
echo "=== Exporting Poverty Point Archaeological Survey result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any state changes
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_final_screenshot.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
fi

# ================================================================
# CHECK OUTPUT KML FILE
# ================================================================
OUTPUT_PATH="/home/ga/Documents/poverty_point_survey.kml"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created/modified during the task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Copy KML content for verification (first 10KB to avoid huge files)
    head -c 10240 "$OUTPUT_PATH" > /tmp/kml_content.txt 2>/dev/null || true
    
    # Count placemarks and paths in KML
    PLACEMARK_COUNT=$(grep -ci "<Placemark>" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    PATH_COUNT=$(grep -ci "<LineString>" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    COORDINATE_COUNT=$(grep -ci "<coordinates>" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check for expected placemark names
    HAS_MOUND_A=$(grep -qi "mound.*a\|bird.*mound" "$OUTPUT_PATH" 2>/dev/null && echo "true" || echo "false")
    HAS_PLAZA=$(grep -qi "plaza\|central" "$OUTPUT_PATH" 2>/dev/null && echo "true" || echo "false")
    HAS_RIDGE=$(grep -qi "ridge\|arc\|outer" "$OUTPUT_PATH" 2>/dev/null && echo "true" || echo "false")
    
    echo "KML file found:"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $OUTPUT_MTIME"
    echo "  Placemarks: $PLACEMARK_COUNT"
    echo "  LineStrings: $PATH_COUNT"
    echo "  Has Mound A reference: $HAS_MOUND_A"
    echo "  Has Plaza reference: $HAS_PLAZA"
    echo "  Has Ridge reference: $HAS_RIDGE"
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    PLACEMARK_COUNT="0"
    PATH_COUNT="0"
    COORDINATE_COUNT="0"
    HAS_MOUND_A="false"
    HAS_PLAZA="false"
    HAS_RIDGE="false"
    echo "KML file NOT found at $OUTPUT_PATH"
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth" | head -1)
fi

# Get window title
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

echo ""
echo "Google Earth state:"
echo "  Running: $GE_RUNNING"
echo "  Window: $GE_WINDOW_TITLE"

# ================================================================
# CHECK MY PLACES FOR ADDITIONAL EVIDENCE
# ================================================================
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
MYPLACES_EXISTS="false"
MYPLACES_UPDATED="false"

if [ -f "$MYPLACES_PATH" ]; then
    MYPLACES_EXISTS="true"
    MYPLACES_MTIME=$(stat -c%Y "$MYPLACES_PATH" 2>/dev/null || echo "0")
    if [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        MYPLACES_UPDATED="true"
    fi
    # Copy relevant content
    head -c 5120 "$MYPLACES_PATH" > /tmp/myplaces_content.txt 2>/dev/null || true
fi

# ================================================================
# CREATE JSON RESULT
# ================================================================
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
    "placemark_count": $PLACEMARK_COUNT,
    "path_count": $PATH_COUNT,
    "coordinate_count": $COORDINATE_COUNT,
    "has_mound_a_reference": $HAS_MOUND_A,
    "has_plaza_reference": $HAS_PLAZA,
    "has_ridge_reference": $HAS_RIDGE,
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "myplaces_exists": $MYPLACES_EXISTS,
    "myplaces_updated": $MYPLACES_UPDATED,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "kml_content_path": "/tmp/kml_content.txt"
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