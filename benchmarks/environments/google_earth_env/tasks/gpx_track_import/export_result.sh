#!/bin/bash
set -e
echo "=== Exporting GPX Track Import task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task start: $TASK_START"
echo "Task end: $TASK_END"
echo "Duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot FIRST (before any other operations)
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    FINAL_SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# Check output file existence and properties
OUTPUT_PATH="/home/ga/Documents/angels_landing_visualization.jpg"
GPX_PATH="/home/ga/Documents/angels_landing_trail.gpx"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task (anti-gaming)
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
    img = Image.open("/home/ga/Documents/angels_landing_visualization.jpg")
    print(json.dumps({
        "width": img.width,
        "height": img.height,
        "format": img.format or "unknown",
        "mode": img.mode
    }))
except Exception as e:
    print(json.dumps({
        "width": 0,
        "height": 0,
        "format": "error",
        "mode": "unknown",
        "error": str(e)
    }))
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

echo "Output file exists: $OUTPUT_EXISTS"
echo "Output file size: $OUTPUT_SIZE bytes"
echo "File created during task: $FILE_CREATED_DURING_TASK"
echo "Image dimensions: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}"

# Check if GPX file still exists
if [ -f "$GPX_PATH" ]; then
    GPX_EXISTS="true"
else
    GPX_EXISTS="false"
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

# Check for any KML/KMZ files that might have been created (evidence of GPX import)
TEMP_PLACES_DIR="/home/ga/.googleearth"
IMPORTED_FILES=""
if [ -d "$TEMP_PLACES_DIR" ]; then
    # Check for recently modified files that might indicate import
    RECENT_FILES=$(find "$TEMP_PLACES_DIR" -type f -mmin -10 2>/dev/null | head -5 || echo "")
    IMPORTED_FILES="$RECENT_FILES"
fi

# Check myplaces.kml for evidence of the imported track
TRACK_IN_MYPLACES="false"
if [ -f "$TEMP_PLACES_DIR/myplaces.kml" ]; then
    if grep -qi "angel" "$TEMP_PLACES_DIR/myplaces.kml" 2>/dev/null || \
       grep -qi "landing" "$TEMP_PLACES_DIR/myplaces.kml" 2>/dev/null || \
       grep -qi "zion" "$TEMP_PLACES_DIR/myplaces.kml" 2>/dev/null; then
        TRACK_IN_MYPLACES="true"
    fi
fi

# Create comprehensive result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_file": {
        "exists": $OUTPUT_EXISTS,
        "path": "$OUTPUT_PATH",
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "width": $IMAGE_WIDTH,
        "height": $IMAGE_HEIGHT,
        "format": "$IMAGE_FORMAT"
    },
    "gpx_file": {
        "exists": $GPX_EXISTS,
        "path": "$GPX_PATH"
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "pid": "$GE_PID",
        "window_title": "$GE_WINDOW_TITLE"
    },
    "evidence": {
        "track_in_myplaces": $TRACK_IN_MYPLACES,
        "final_screenshot_path": "/tmp/task_final_state.png",
        "final_screenshot_size": $FINAL_SCREENSHOT_SIZE
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task result exported ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="