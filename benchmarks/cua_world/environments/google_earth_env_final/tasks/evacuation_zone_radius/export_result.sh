#!/bin/bash
set -euo pipefail

echo "=== Exporting evacuation_zone_radius task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other operations
echo "Capturing final screenshot..."
scrot /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Check KML output file
KML_OUTPUT="/home/ga/evacuation_zone.kml"

if [ -f "$KML_OUTPUT" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$KML_OUTPUT" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$KML_OUTPUT" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Check if file is valid XML/KML
    if head -5 "$KML_OUTPUT" | grep -qi "kml\|xml"; then
        VALID_KML_FORMAT="true"
    else
        VALID_KML_FORMAT="false"
    fi
    
    # Extract some KML content info
    KML_HAS_POLYGON="false"
    KML_HAS_COORDINATES="false"
    KML_HAS_NAME="false"
    
    if grep -qi "polygon\|linearring" "$KML_OUTPUT" 2>/dev/null; then
        KML_HAS_POLYGON="true"
    fi
    
    if grep -qi "coordinates" "$KML_OUTPUT" 2>/dev/null; then
        KML_HAS_COORDINATES="true"
    fi
    
    if grep -qi "TMI\|emergency\|evacuation\|zone\|planning" "$KML_OUTPUT" 2>/dev/null; then
        KML_HAS_NAME="true"
    fi
    
    # Count coordinate points (rough estimate of circle complexity)
    COORD_COUNT=$(grep -o "," "$KML_OUTPUT" 2>/dev/null | wc -l || echo "0")
    
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    VALID_KML_FORMAT="false"
    KML_HAS_POLYGON="false"
    KML_HAS_COORDINATES="false"
    KML_HAS_NAME="false"
    COORD_COUNT="0"
fi

# Check if Google Earth is running
GE_RUNNING="false"
GE_WINDOW_TITLE=""
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_WINDOW_TITLE=$(wmctrl -l | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
fi

# Check for My Places file updates
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
MYPLACES_MODIFIED="false"
if [ -f "$MYPLACES_FILE" ]; then
    MYPLACES_MTIME=$(stat -c%Y "$MYPLACES_FILE" 2>/dev/null || echo "0")
    if [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        MYPLACES_MODIFIED="true"
    fi
fi

# Create JSON result with safe file handling
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "kml_output": {
        "exists": $OUTPUT_EXISTS,
        "path": "$KML_OUTPUT",
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "valid_kml_format": $VALID_KML_FORMAT,
        "has_polygon": $KML_HAS_POLYGON,
        "has_coordinates": $KML_HAS_COORDINATES,
        "has_appropriate_name": $KML_HAS_NAME,
        "coordinate_count_estimate": $COORD_COUNT
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE"
    },
    "myplaces_modified": $MYPLACES_MODIFIED,
    "screenshots": {
        "initial": "/tmp/task_initial_state.png",
        "final": "/tmp/task_final.png"
    }
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task Result Summary ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="