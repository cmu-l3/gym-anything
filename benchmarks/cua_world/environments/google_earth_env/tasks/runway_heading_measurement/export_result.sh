#!/bin/bash
set -euo pipefail

echo "=== Exporting runway_heading_measurement task result ==="

export DISPLAY=${DISPLAY:-:1}

# Take final screenshot FIRST (before any other operations)
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true
if [ -f /tmp/task_final_screenshot.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    FINAL_SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# ================================================================
# CHECK OUTPUT FILE
# ================================================================
OUTPUT_PATH="/home/ga/Documents/runway_34L_heading.kml"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created/modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Read KML content for parsing
    KML_CONTENT=$(cat "$OUTPUT_PATH" 2>/dev/null | head -200 || echo "")
    
    # Try to extract placemark name
    PLACEMARK_NAME=$(echo "$KML_CONTENT" | grep -oP '(?<=<name>)[^<]+(?=</name>)' | head -1 || echo "")
    
    # Try to extract description
    PLACEMARK_DESC=$(echo "$KML_CONTENT" | grep -oP '(?<=<description>)[^<]+(?=</description>)' | head -1 || echo "")
    
    # Try to extract coordinates (format: lon,lat,alt)
    COORDINATES=$(echo "$KML_CONTENT" | grep -oP '(?<=<coordinates>)[^<]+(?=</coordinates>)' | head -1 | tr -d '[:space:]' || echo "")
    
    # Parse latitude and longitude from coordinates
    if [ -n "$COORDINATES" ]; then
        PARSED_LON=$(echo "$COORDINATES" | cut -d',' -f1 || echo "")
        PARSED_LAT=$(echo "$COORDINATES" | cut -d',' -f2 || echo "")
    else
        PARSED_LON=""
        PARSED_LAT=""
    fi
    
    # Try to extract heading value from description
    HEADING_VALUE=$(echo "$PLACEMARK_DESC" | grep -oP '\d{2,3}' | head -1 || echo "")
    
    echo "KML file found:"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $OUTPUT_MTIME"
    echo "  Created during task: $FILE_CREATED_DURING_TASK"
    echo "  Placemark name: $PLACEMARK_NAME"
    echo "  Description: $PLACEMARK_DESC"
    echo "  Coordinates: $COORDINATES"
    echo "  Parsed lat: $PARSED_LAT, lon: $PARSED_LON"
    echo "  Heading value: $HEADING_VALUE"
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    KML_CONTENT=""
    PLACEMARK_NAME=""
    PLACEMARK_DESC=""
    COORDINATES=""
    PARSED_LAT=""
    PARSED_LON=""
    HEADING_VALUE=""
    echo "KML file NOT found at $OUTPUT_PATH"
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================

# Check if Google Earth is still running
GE_RUNNING="false"
GE_PID=""
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f google-earth-pro | head -1)
fi

# Get Google Earth window info
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "earth" || echo "")
GE_WINDOW_TITLE=""
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

echo ""
echo "Google Earth state:"
echo "  Running: $GE_RUNNING"
echo "  PID: $GE_PID"
echo "  Window title: $GE_WINDOW_TITLE"

# ================================================================
# CHECK FOR ANY KML FILES IN DOCUMENTS
# ================================================================
KML_FILES_FOUND=""
KML_COUNT=0
if ls /home/ga/Documents/*.kml 2>/dev/null; then
    KML_FILES_FOUND=$(ls -la /home/ga/Documents/*.kml 2>/dev/null || echo "")
    KML_COUNT=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
fi

echo ""
echo "KML files in Documents:"
echo "$KML_FILES_FOUND"

# ================================================================
# CREATE RESULT JSON
# ================================================================

# Escape special characters for JSON
PLACEMARK_NAME_ESCAPED=$(echo "$PLACEMARK_NAME" | sed 's/"/\\"/g' | tr -d '\n' || echo "")
PLACEMARK_DESC_ESCAPED=$(echo "$PLACEMARK_DESC" | sed 's/"/\\"/g' | tr -d '\n' || echo "")
GE_WINDOW_TITLE_ESCAPED=$(echo "$GE_WINDOW_TITLE" | sed 's/"/\\"/g' | tr -d '\n' || echo "")

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
    "placemark_name": "$PLACEMARK_NAME_ESCAPED",
    "placemark_description": "$PLACEMARK_DESC_ESCAPED",
    "coordinates_raw": "$COORDINATES",
    "parsed_latitude": "$PARSED_LAT",
    "parsed_longitude": "$PARSED_LON",
    "heading_value": "$HEADING_VALUE",
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE_ESCAPED",
    "kml_file_count": $KML_COUNT,
    "final_screenshot_size": $FINAL_SCREENSHOT_SIZE
}
EOF

# Copy to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result JSON:"
cat /tmp/task_result.json