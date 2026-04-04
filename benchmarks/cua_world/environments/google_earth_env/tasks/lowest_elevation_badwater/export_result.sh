#!/bin/bash
set -e
echo "=== Exporting Badwater Basin task results ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot FIRST (before any other operations)
echo "Capturing final state screenshot..."
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
# CHECK OUTPUT FILE
# ================================================================
OUTPUT_PATH="/home/ga/Documents/badwater_basin.kml"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created/modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KML file was created during task execution"
    else
        FILE_CREATED_DURING_TASK="false"
        echo "WARNING: KML file predates task start"
    fi
    
    # Extract basic KML content for verification
    KML_CONTENT=$(cat "$OUTPUT_PATH" 2>/dev/null | head -100 || echo "")
    
    # Check if it's valid XML/KML
    if echo "$KML_CONTENT" | grep -q "<kml"; then
        VALID_KML="true"
    else
        VALID_KML="false"
    fi
    
    # Extract placemark name if present
    PLACEMARK_NAME=$(echo "$KML_CONTENT" | grep -oP '(?<=<name>)[^<]+' | head -1 || echo "")
    
    # Extract coordinates if present
    COORDINATES=$(echo "$KML_CONTENT" | grep -oP '(?<=<coordinates>)[^<]+' | head -1 || echo "")
    
    # Extract description if present
    DESCRIPTION=$(cat "$OUTPUT_PATH" 2>/dev/null | grep -oP '(?<=<description>)[\s\S]*?(?=</description>)' | head -1 || echo "")
    
    echo "KML file found: $OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Placemark name: $PLACEMARK_NAME"
    echo "  Coordinates: $COORDINATES"
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    VALID_KML="false"
    PLACEMARK_NAME=""
    COORDINATES=""
    DESCRIPTION=""
    echo "KML file NOT found at $OUTPUT_PATH"
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# ================================================================
# CHECK MY PLACES FOR PLACEMARKS
# ================================================================
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
MYPLACES_HAS_BADWATER="false"

if [ -f "$MYPLACES_PATH" ]; then
    if grep -qi "badwater\|lowest\|death valley" "$MYPLACES_PATH" 2>/dev/null; then
        MYPLACES_HAS_BADWATER="true"
        echo "Found Badwater-related placemark in myplaces.kml"
    fi
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Escape strings for JSON
PLACEMARK_NAME_ESCAPED=$(echo "$PLACEMARK_NAME" | sed 's/"/\\"/g' | tr -d '\n')
COORDINATES_ESCAPED=$(echo "$COORDINATES" | sed 's/"/\\"/g' | tr -d '\n')
DESCRIPTION_ESCAPED=$(echo "$DESCRIPTION" | sed 's/"/\\"/g' | tr -d '\n' | head -c 500)
GE_WINDOW_TITLE_ESCAPED=$(echo "$GE_WINDOW_TITLE" | sed 's/"/\\"/g' | tr -d '\n')

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "valid_kml": $VALID_KML,
    "placemark_name": "$PLACEMARK_NAME_ESCAPED",
    "coordinates": "$COORDINATES_ESCAPED",
    "description": "$DESCRIPTION_ESCAPED",
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE_ESCAPED",
    "myplaces_has_badwater": $MYPLACES_HAS_BADWATER,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="