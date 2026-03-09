#!/bin/bash
echo "=== Exporting Taal Lake Annulus Polygon task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task timing: Start=$TASK_START, End=$TASK_END"

# Take final screenshot before any other operations
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
fi

# Check output KML file
OUTPUT_PATH="/home/ga/Documents/taal_lake_polygon.kml"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
KML_CONTENT=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KML file was created during task execution"
    else
        echo "WARNING: KML file exists but was not modified during task"
    fi
    
    # Read KML content for verification
    KML_CONTENT=$(cat "$OUTPUT_PATH" 2>/dev/null | head -c 50000 || echo "")
    
    echo "KML file details:"
    echo "  - Path: $OUTPUT_PATH"
    echo "  - Size: $OUTPUT_SIZE bytes"
    echo "  - Modified: $OUTPUT_MTIME"
else
    echo "KML file not found at $OUTPUT_PATH"
fi

# Also check for KMZ format (Google Earth sometimes saves as KMZ)
KMZ_PATH="/home/ga/Documents/taal_lake_polygon.kmz"
KMZ_EXISTS="false"
if [ -f "$KMZ_PATH" ]; then
    KMZ_EXISTS="true"
    echo "Found KMZ file at $KMZ_PATH"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
GE_PID=""
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth-pro" | head -1)
fi

# Get Google Earth window info
GE_WINDOW_TITLE=""
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# Check My Places for saved polygon
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
POLYGON_IN_MYPLACES="false"
MYPLACES_CONTENT=""
if [ -f "$MYPLACES_PATH" ]; then
    MYPLACES_CONTENT=$(cat "$MYPLACES_PATH" 2>/dev/null | head -c 50000 || echo "")
    if echo "$MYPLACES_CONTENT" | grep -qi "Taal"; then
        POLYGON_IN_MYPLACES="true"
        echo "Found Taal-related content in myplaces.kml"
    fi
fi

# Create comprehensive JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use Python for proper JSON escaping
python3 << PYEOF > "$TEMP_JSON"
import json
import sys

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $TASK_END - $TASK_START,
    "output_exists": $( [ "$OUTPUT_EXISTS" = "true" ] && echo "true" || echo "false" ),
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $( [ "$FILE_CREATED_DURING_TASK" = "true" ] && echo "true" || echo "false" ),
    "kmz_exists": $( [ "$KMZ_EXISTS" = "true" ] && echo "true" || echo "false" ),
    "google_earth_running": $( [ "$GE_RUNNING" = "true" ] && echo "true" || echo "false" ),
    "google_earth_pid": "$GE_PID" if "$GE_PID" else None,
    "google_earth_window_title": """$GE_WINDOW_TITLE""",
    "polygon_in_myplaces": $( [ "$POLYGON_IN_MYPLACES" = "true" ] && echo "true" || echo "false" ),
    "screenshot_exists": $( [ "$SCREENSHOT_EXISTS" = "true" ] && echo "true" || echo "false" ),
    "screenshot_path": "/tmp/task_final_state.png",
    "kml_file_path": "$OUTPUT_PATH"
}

# Add KML content if it exists
kml_content = """$KML_CONTENT"""
if kml_content:
    result["kml_content"] = kml_content[:50000]  # Limit size

# Add myplaces content if relevant
myplaces_content = """$MYPLACES_CONTENT"""
if myplaces_content and "$POLYGON_IN_MYPLACES" == "true":
    result["myplaces_content"] = myplaces_content[:20000]

print(json.dumps(result, indent=2))
PYEOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also copy the KML file to /tmp for easier access
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" /tmp/taal_lake_polygon.kml 2>/dev/null || true
    chmod 666 /tmp/taal_lake_polygon.kml 2>/dev/null || true
fi

echo ""
echo "=== Export Results ==="
echo "Result JSON saved to: /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="