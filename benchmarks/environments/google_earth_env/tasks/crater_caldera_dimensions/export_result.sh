#!/bin/bash
set -e
echo "=== Exporting Crater Lake Caldera Dimensions task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other operations
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# ================================================================
# CHECK OUTPUT KML FILE
# ================================================================
OUTPUT_PATH="/home/ga/Documents/crater_lake_dimensions.kml"

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
KML_CONTENT=""
PLACEMARK_COUNT="0"
HAS_FOLDER="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task (anti-gaming)
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KML file was created during task execution"
    else
        echo "WARNING: KML file existed before task started"
    fi
    
    # Read KML content for verification (first 50KB)
    KML_CONTENT=$(head -c 51200 "$OUTPUT_PATH" 2>/dev/null | base64 -w 0 || echo "")
    
    # Count placemarks in KML
    PLACEMARK_COUNT=$(grep -c "<Placemark>" "$OUTPUT_PATH" 2>/dev/null || echo "0")
    echo "Placemark count in KML: $PLACEMARK_COUNT"
    
    # Check for folder structure
    if grep -q "<Folder>" "$OUTPUT_PATH" 2>/dev/null; then
        HAS_FOLDER="true"
        echo "Folder structure detected in KML"
    fi
    
    # Extract placemark names
    echo "--- Placemark names found ---"
    grep -o "<name>[^<]*</name>" "$OUTPUT_PATH" 2>/dev/null | head -10 || true
    
else
    echo "KML file NOT found at: $OUTPUT_PATH"
    
    # Check if any KML files exist in Documents
    echo "Checking for any KML files in Documents..."
    ls -la /home/ga/Documents/*.kml 2>/dev/null || echo "No KML files found"
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "unknown")
    echo "Google Earth is running: $GE_WINDOW_TITLE"
fi

# ================================================================
# CHECK MY PLACES FOR SAVED PLACEMARKS
# ================================================================
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
MYPLACES_PLACEMARKS="0"
MYPLACES_HAS_CRATER="false"

if [ -f "$MYPLACES_PATH" ]; then
    MYPLACES_PLACEMARKS=$(grep -c "<Placemark>" "$MYPLACES_PATH" 2>/dev/null || echo "0")
    if grep -qi "crater" "$MYPLACES_PATH" 2>/dev/null; then
        MYPLACES_HAS_CRATER="true"
    fi
    echo "My Places placemarks: $MYPLACES_PLACEMARKS"
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "placemark_count": $PLACEMARK_COUNT,
    "has_folder_structure": $HAS_FOLDER,
    "kml_content_base64": "$KML_CONTENT",
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "myplaces_placemarks": $MYPLACES_PLACEMARKS,
    "myplaces_has_crater_ref": $MYPLACES_HAS_CRATER,
    "initial_screenshot_path": "/tmp/task_initial.png",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json