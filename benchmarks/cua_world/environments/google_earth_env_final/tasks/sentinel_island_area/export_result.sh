#!/bin/bash
set -euo pipefail

echo "=== Exporting North Sentinel Island Area Measurement Result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other operations
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
    SCREENSHOT_SIZE="0"
fi

# Check output KML file
OUTPUT_PATH="/home/ga/Documents/north_sentinel_boundary.kml"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
KML_VALID="false"
HAS_POLYGON="false"
HAS_COORDINATES="false"
POLYGON_NAME=""
COORDINATE_COUNT="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task (anti-gaming check)
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KML file was created during task execution"
    else
        echo "WARNING: KML file timestamp predates task start"
    fi
    
    # Validate KML structure
    if grep -q "<?xml" "$OUTPUT_PATH" 2>/dev/null; then
        KML_VALID="true"
    fi
    
    # Check for Polygon element
    if grep -qi "<Polygon>" "$OUTPUT_PATH" 2>/dev/null || grep -qi "<LinearRing>" "$OUTPUT_PATH" 2>/dev/null; then
        HAS_POLYGON="true"
    fi
    
    # Check for coordinates
    if grep -qi "<coordinates>" "$OUTPUT_PATH" 2>/dev/null; then
        HAS_COORDINATES="true"
        # Count coordinate points (rough estimate)
        COORD_TEXT=$(grep -oP '(?<=<coordinates>).*?(?=</coordinates>)' "$OUTPUT_PATH" 2>/dev/null | head -1 || echo "")
        if [ -n "$COORD_TEXT" ]; then
            COORDINATE_COUNT=$(echo "$COORD_TEXT" | tr ' ' '\n' | grep -c ',' 2>/dev/null || echo "0")
        fi
    fi
    
    # Extract polygon name
    POLYGON_NAME=$(grep -oP '(?<=<name>).*?(?=</name>)' "$OUTPUT_PATH" 2>/dev/null | head -1 || echo "")
    
    echo "KML file found: $OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Valid XML: $KML_VALID"
    echo "  Has polygon: $HAS_POLYGON"
    echo "  Has coordinates: $HAS_COORDINATES"
    echo "  Coordinate count: $COORDINATE_COUNT"
    echo "  Polygon name: $POLYGON_NAME"
else
    echo "KML file NOT found at: $OUTPUT_PATH"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
GE_PID=""
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth-pro" | head -1)
fi

# Check for Google Earth window
GE_WINDOW_TITLE=""
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Google Earth"; then
    GE_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
fi

# Check myplaces.kml for saved polygon
MYPLACES_HAS_POLYGON="false"
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
if [ -f "$MYPLACES_PATH" ]; then
    if grep -qi "North_Sentinel\|Sentinel.*Island\|sentinel" "$MYPLACES_PATH" 2>/dev/null; then
        MYPLACES_HAS_POLYGON="true"
        echo "Found polygon reference in myplaces.kml"
    fi
fi

# Copy KML file to /tmp for verification (if it exists)
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" /tmp/exported_polygon.kml 2>/dev/null || true
    chmod 644 /tmp/exported_polygon.kml 2>/dev/null || true
fi

# Create JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "kml_valid": $KML_VALID,
    "has_polygon": $HAS_POLYGON,
    "has_coordinates": $HAS_COORDINATES,
    "coordinate_count": $COORDINATE_COUNT,
    "polygon_name": "$POLYGON_NAME",
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "myplaces_has_polygon": $MYPLACES_HAS_POLYGON,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="