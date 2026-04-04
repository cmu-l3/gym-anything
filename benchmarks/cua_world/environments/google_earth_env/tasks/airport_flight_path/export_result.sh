#!/bin/bash
set -e
echo "=== Exporting airport_flight_path task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task end time: $TASK_END"
echo "Task start time: $TASK_START"

# Take final screenshot BEFORE any state changes
echo "Capturing final screenshot..."
scrot /tmp/task_evidence/final_state.png 2>/dev/null || true

if [ -f /tmp/task_evidence/final_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_evidence/final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# ================================================================
# CHECK OUTPUT FILE
# ================================================================
OUTPUT_PATH="/home/ga/Documents/flight_path.kml"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created/modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Copy the KML file for verification
    cp "$OUTPUT_PATH" /tmp/task_evidence/flight_path.kml 2>/dev/null || true
    
    # Extract KML content summary (first 2000 chars for debugging)
    KML_PREVIEW=$(head -c 2000 "$OUTPUT_PATH" 2>/dev/null | tr '\n' ' ' | tr '"' "'" || echo "")
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    KML_PREVIEW=""
fi

echo "Output file exists: $OUTPUT_EXISTS"
echo "Output file size: $OUTPUT_SIZE bytes"
echo "File created during task: $FILE_CREATED_DURING_TASK"

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get Google Earth window title
GE_WINDOWS=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

echo "Google Earth running: $GE_RUNNING"
echo "Google Earth window: $GE_WINDOW_TITLE"

# ================================================================
# CHECK MY PLACES FOR CREATED PATH
# ================================================================
MYPLACES_HAS_PATH="false"
MYPLACES_PATH_NAME=""

if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
    # Check if myplaces contains a path with our name
    if grep -qi "KSFO.*KLAX\|SFO.*LAX" /home/ga/.googleearth/myplaces.kml 2>/dev/null; then
        MYPLACES_HAS_PATH="true"
        MYPLACES_PATH_NAME=$(grep -o '<name>[^<]*KSFO[^<]*KLAX[^<]*</name>\|<name>[^<]*SFO[^<]*LAX[^<]*</name>' /home/ga/.googleearth/myplaces.kml 2>/dev/null | head -1 || echo "")
    fi
    
    # Also check for LineString (path geometry)
    if grep -q "<LineString>" /home/ga/.googleearth/myplaces.kml 2>/dev/null; then
        MYPLACES_HAS_LINESTRING="true"
    else
        MYPLACES_HAS_LINESTRING="false"
    fi
    
    # Copy myplaces for verification
    cp /home/ga/.googleearth/myplaces.kml /tmp/task_evidence/myplaces.kml 2>/dev/null || true
else
    MYPLACES_HAS_LINESTRING="false"
fi

echo "My Places has path: $MYPLACES_HAS_PATH"
echo "My Places has LineString: $MYPLACES_HAS_LINESTRING"

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_sec": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "myplaces_has_path": $MYPLACES_HAS_PATH,
    "myplaces_has_linestring": $MYPLACES_HAS_LINESTRING,
    "myplaces_path_name": "$MYPLACES_PATH_NAME",
    "kml_preview": "$KML_PREVIEW",
    "final_screenshot": "/tmp/task_evidence/final_state.png",
    "initial_screenshot": "/tmp/task_evidence/initial_state.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task Result JSON ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="