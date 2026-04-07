#!/bin/bash
set -euo pipefail

echo "=== Exporting Hawaii Elevation Profile task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task timing: Start=$TASK_START, End=$TASK_END"

# Capture final screenshot BEFORE any other operations
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    FINAL_SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# Check output file
OUTPUT_PATH="/home/ga/hawaii_elevation_profile.png"
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
    
    # Get image dimensions using Python/PIL
    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/hawaii_elevation_profile.png")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format or "unknown", "mode": img.mode}))
except Exception as e:
    print(json.dumps({"error": str(e), "width": 0, "height": 0, "format": "unknown", "mode": "unknown"}))
PYEOF
)
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    IMAGE_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    IMAGE_WIDTH="0"
    IMAGE_HEIGHT="0"
    IMAGE_FORMAT="none"
fi

echo "Output file check: exists=$OUTPUT_EXISTS, size=$OUTPUT_SIZE, created_during_task=$FILE_CREATED_DURING_TASK"

# Check if Google Earth is running
GE_RUNNING="false"
GE_PID=""
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth" | head -1)
fi

# Get window information
WINDOW_TITLE=""
WINDOW_INFO=""
if wmctrl -l 2>/dev/null | grep -qi "Google Earth"; then
    WINDOW_TITLE=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
    WINDOW_INFO="visible"
else
    WINDOW_INFO="not_found"
fi

# Check for elevation profile window (may be a separate window)
ELEVATION_WINDOW_VISIBLE="false"
if wmctrl -l 2>/dev/null | grep -qi "elevation\|profile"; then
    ELEVATION_WINDOW_VISIBLE="true"
fi

# Check Google Earth saved places for Hawaii-related paths
SAVED_PLACES_FOUND="false"
HAWAII_PATH_SAVED="false"
if [ -d "/home/ga/.googleearth" ]; then
    # Check myplaces.kml for Hawaii references
    if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
        SAVED_PLACES_FOUND="true"
        if grep -qi "hawaii\|cross-section\|hilo\|kona\|mauna" /home/ga/.googleearth/myplaces.kml 2>/dev/null; then
            HAWAII_PATH_SAVED="true"
        fi
    fi
    
    # Also check for any recent KML files
    RECENT_KML=$(find /home/ga/.googleearth -name "*.kml" -mmin -30 2>/dev/null | head -1 || echo "")
    if [ -n "$RECENT_KML" ]; then
        if grep -qi "hawaii\|cross-section" "$RECENT_KML" 2>/dev/null; then
            HAWAII_PATH_SAVED="true"
        fi
    fi
fi

# Check for any KML files saved in home directory
HOME_KML_FILES=$(find /home/ga -maxdepth 1 -name "*.kml" -o -name "*.kmz" 2>/dev/null | wc -l || echo "0")

echo "Google Earth state: running=$GE_RUNNING, window=$WINDOW_INFO, elevation_window=$ELEVATION_WINDOW_VISIBLE"
echo "Saved places: found=$SAVED_PLACES_FOUND, hawaii_path=$HAWAII_PATH_SAVED, home_kml=$HOME_KML_FILES"

# Create JSON result
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
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_format": "$IMAGE_FORMAT",
    "google_earth_running": $GE_RUNNING,
    "google_earth_pid": "$GE_PID",
    "window_title": "$WINDOW_TITLE",
    "window_info": "$WINDOW_INFO",
    "elevation_window_visible": $ELEVATION_WINDOW_VISIBLE,
    "saved_places_found": $SAVED_PLACES_FOUND,
    "hawaii_path_saved": $HAWAII_PATH_SAVED,
    "home_kml_files": $HOME_KML_FILES,
    "final_screenshot_path": "/tmp/task_final.png",
    "final_screenshot_size": $FINAL_SCREENSHOT_SIZE
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json