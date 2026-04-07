#!/bin/bash
set -euo pipefail

echo "=== Exporting Ngorongoro Crater Polygon task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other operations
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

# Check output KML file
OUTPUT_PATH="/home/ga/Documents/ngorongoro_habitat.kml"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
KML_CONTENT_PREVIEW=""

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during the task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KML file was created during task execution"
    else
        echo "WARNING: KML file exists but was NOT created during task"
    fi
    
    # Get KML content preview (first 2000 chars)
    KML_CONTENT_PREVIEW=$(head -c 2000 "$OUTPUT_PATH" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g' || echo "")
    
    echo "KML file found: $OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $(date -d @$OUTPUT_MTIME 2>/dev/null || echo 'unknown')"
else
    echo "KML file NOT found at $OUTPUT_PATH"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
GE_WINDOW_TITLE=""
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_WINDOW_TITLE=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
    echo "Google Earth is running"
    echo "  Window title: $GE_WINDOW_TITLE"
else
    echo "Google Earth is NOT running"
fi

# Check Google Earth's Places/MyPlaces for evidence
MYPLACES_PATH="/home/ga/.googleearth/myplaces.kml"
MYPLACES_HAS_POLYGON="false"
MYPLACES_HAS_NGORONGORO="false"

if [ -f "$MYPLACES_PATH" ]; then
    if grep -qi "polygon" "$MYPLACES_PATH" 2>/dev/null; then
        MYPLACES_HAS_POLYGON="true"
    fi
    if grep -qi "ngorongoro" "$MYPLACES_PATH" 2>/dev/null; then
        MYPLACES_HAS_NGORONGORO="true"
    fi
    echo "MyPlaces check: polygon=$MYPLACES_HAS_POLYGON, ngorongoro=$MYPLACES_HAS_NGORONGORO"
fi

# Create JSON result file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_path": "$OUTPUT_PATH",
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "myplaces_has_polygon": $MYPLACES_HAS_POLYGON,
    "myplaces_has_ngorongoro": $MYPLACES_HAS_NGORONGORO,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final_screenshot.png",
    "kml_content_preview": "$KML_CONTENT_PREVIEW"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also copy the KML file to /tmp for easier access
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" /tmp/ngorongoro_habitat.kml 2>/dev/null || true
    chmod 666 /tmp/ngorongoro_habitat.kml 2>/dev/null || true
fi

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json