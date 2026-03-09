#!/bin/bash
set -e
echo "=== Exporting Meteor Crater Annotation task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other operations
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# ================================================================
# Check output KML file
# ================================================================
OUTPUT_PATH="/home/ga/Documents/meteor_crater.kml"
OUTPUT_PATH_KMZ="/home/ga/Documents/meteor_crater.kmz"

OUTPUT_EXISTS="false"
OUTPUT_IS_KMZ="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
KML_CONTENT=""

# Check for KML file
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Extract KML content (first 10000 chars for analysis)
    KML_CONTENT=$(head -c 10000 "$OUTPUT_PATH" 2>/dev/null | base64 -w 0 || echo "")
    
# Check for KMZ file (Google Earth sometimes saves as KMZ)
elif [ -f "$OUTPUT_PATH_KMZ" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_IS_KMZ="true"
    OUTPUT_PATH="$OUTPUT_PATH_KMZ"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH_KMZ" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH_KMZ" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Extract KML from KMZ (it's a zip file)
    TEMP_DIR=$(mktemp -d)
    unzip -q "$OUTPUT_PATH_KMZ" -d "$TEMP_DIR" 2>/dev/null || true
    if [ -f "$TEMP_DIR/doc.kml" ]; then
        KML_CONTENT=$(head -c 10000 "$TEMP_DIR/doc.kml" 2>/dev/null | base64 -w 0 || echo "")
    fi
    rm -rf "$TEMP_DIR"
fi

echo "Output file exists: $OUTPUT_EXISTS"
echo "Output is KMZ: $OUTPUT_IS_KMZ"
echo "Output size: $OUTPUT_SIZE bytes"
echo "File created during task: $FILE_CREATED_DURING_TASK"

# ================================================================
# Check Google Earth state
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get window title
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "google earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

echo "Google Earth running: $GE_RUNNING"
echo "Window title: $GE_WINDOW_TITLE"

# ================================================================
# Check My Places for the polygon
# ================================================================
MYPLACES_CONTENT=""
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
if [ -f "$MYPLACES_PATH" ]; then
    # Look for our polygon in myplaces
    if grep -qi "barringer\|meteor.*crater" "$MYPLACES_PATH" 2>/dev/null; then
        echo "Found crater polygon reference in myplaces.kml"
        MYPLACES_CONTENT=$(grep -A 50 -i "barringer\|meteor.*crater" "$MYPLACES_PATH" 2>/dev/null | head -100 | base64 -w 0 || echo "")
    fi
fi

# ================================================================
# Create JSON result
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use Python for proper JSON escaping
python3 << PYEOF
import json
import base64

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $TASK_END - $TASK_START,
    "output_exists": $( [ "$OUTPUT_EXISTS" = "true" ] && echo "true" || echo "false" ),
    "output_is_kmz": $( [ "$OUTPUT_IS_KMZ" = "true" ] && echo "true" || echo "false" ),
    "output_path": "$OUTPUT_PATH",
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $( [ "$FILE_CREATED_DURING_TASK" = "true" ] && echo "true" || echo "false" ),
    "google_earth_running": $( [ "$GE_RUNNING" = "true" ] && echo "true" || echo "false" ),
    "window_title": "$GE_WINDOW_TITLE",
    "kml_content_base64": "$KML_CONTENT",
    "myplaces_content_base64": "$MYPLACES_CONTENT",
    "final_screenshot": "/tmp/task_final_state.png"
}

with open("$TEMP_JSON", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json