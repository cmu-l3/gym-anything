#!/bin/bash
echo "=== Exporting Brenner Pass Saddle Documentation result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot FIRST (for VLM verification)
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
fi

# ================================================================
# CHECK OUTPUT KML FILE
# ================================================================
OUTPUT_PATH="/home/ga/Documents/brenner_pass_saddle.kml"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during the task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KML file was created during task (valid)"
    else
        FILE_CREATED_DURING_TASK="false"
        echo "WARNING: KML file exists but was not created during task"
    fi
    
    # Read KML content for parsing (first 10KB)
    KML_CONTENT=$(head -c 10240 "$OUTPUT_PATH" 2>/dev/null | base64 -w 0)
    
    # Try to extract key elements from KML
    PLACEMARK_NAME=$(grep -oP '(?<=<name>)[^<]+(?=</name>)' "$OUTPUT_PATH" 2>/dev/null | head -1 || echo "")
    PLACEMARK_DESC=$(grep -oP '(?<=<description>)[^<]+(?=</description>)' "$OUTPUT_PATH" 2>/dev/null | head -1 || echo "")
    COORDINATES=$(grep -oP '(?<=<coordinates>)[^<]+(?=</coordinates>)' "$OUTPUT_PATH" 2>/dev/null | head -1 || echo "")
    
    echo "Placemark name: $PLACEMARK_NAME"
    echo "Coordinates found: $COORDINATES"
    echo "Description preview: ${PLACEMARK_DESC:0:100}..."
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    KML_CONTENT=""
    PLACEMARK_NAME=""
    PLACEMARK_DESC=""
    COORDINATES=""
    echo "KML file NOT found at $OUTPUT_PATH"
fi

# ================================================================
# CHECK FOR ANY KML FILES IN DOCUMENTS
# ================================================================
KML_FILES_FOUND=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | wc -l || echo "0")
OTHER_KML_FILES=$(ls -1 /home/ga/Documents/*.kml 2>/dev/null | grep -v "brenner_pass_saddle.kml" || echo "")

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
fi

# Check Google Earth's myplaces for evidence
MYPLACES_UPDATED="false"
if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
    MYPLACES_MTIME=$(stat -c %Y "/home/ga/.googleearth/myplaces.kml" 2>/dev/null || echo "0")
    if [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        MYPLACES_UPDATED="true"
    fi
fi

# ================================================================
# CREATE JSON RESULT
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_id": "saddle_point_analysis@1",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_file": {
        "path": "$OUTPUT_PATH",
        "exists": $OUTPUT_EXISTS,
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK
    },
    "kml_data": {
        "placemark_name": "$PLACEMARK_NAME",
        "placemark_description": "$(echo "$PLACEMARK_DESC" | sed 's/"/\\"/g' | tr '\n' ' ')",
        "coordinates_raw": "$COORDINATES"
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE",
        "myplaces_updated": $MYPLACES_UPDATED
    },
    "screenshots": {
        "initial": "/tmp/task_initial.png",
        "final": "/tmp/task_final.png",
        "final_exists": $SCREENSHOT_EXISTS
    },
    "kml_files_in_documents": $KML_FILES_FOUND
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="