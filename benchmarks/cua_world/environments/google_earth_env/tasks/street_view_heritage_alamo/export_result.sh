#!/bin/bash
set -e
echo "=== Exporting Street View Heritage Alamo task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other processing
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    FINAL_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SIZE} bytes"
fi

# Check for output file at expected locations
OUTPUT_PATH="/home/ga/Documents/alamo_streetview.png"
ALT_OUTPUT_PATH="/home/ga/Documents/alamo_streetview.jpg"

OUTPUT_EXISTS="false"
OUTPUT_FILE=""
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"
IMAGE_FORMAT="none"

# Check primary path
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_FILE="$OUTPUT_PATH"
# Check alternate path
elif [ -f "$ALT_OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_FILE="$ALT_OUTPUT_PATH"
fi

# If output exists, get details
if [ "$OUTPUT_EXISTS" = "true" ]; then
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check if file was created during task (anti-gaming)
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "File was created during task execution"
    else
        echo "WARNING: File modification time ($OUTPUT_MTIME) is before task start ($TASK_START)"
    fi
    
    # Get image dimensions using Python/PIL
    DIMENSIONS=$(python3 << PYEOF
import json
try:
    from PIL import Image
    img = Image.open("$OUTPUT_FILE")
    print(json.dumps({
        "width": img.width,
        "height": img.height,
        "format": img.format or "unknown",
        "mode": img.mode
    }))
except Exception as e:
    print(json.dumps({
        "error": str(e),
        "width": 0,
        "height": 0,
        "format": "error",
        "mode": "unknown"
    }))
PYEOF
)
    
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    IMAGE_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
    
    echo "Output file: $OUTPUT_FILE"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Dimensions: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}"
    echo "  Format: $IMAGE_FORMAT"
else
    echo "No output file found at expected locations"
    # Check if there are any image files in Documents that might be the output
    echo "Files in ~/Documents:"
    ls -la /home/ga/Documents/ 2>/dev/null || true
fi

# Check if Google Earth is still running
GE_RUNNING="false"
GE_PID=""
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth" | head -1)
fi

# Get window information
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
GE_WINDOW_FOUND="false"
GE_WINDOW_TITLE=""
if echo "$WINDOW_LIST" | grep -qi "google earth"; then
    GE_WINDOW_FOUND="true"
    GE_WINDOW_TITLE=$(echo "$WINDOW_LIST" | grep -i "google earth" | head -1 | cut -d' ' -f5-)
fi

# Check for Street View indicators in window title
STREET_VIEW_INDICATED="false"
if echo "$GE_WINDOW_TITLE" | grep -qi "street view"; then
    STREET_VIEW_INDICATED="true"
fi

# Create JSON result (use temp file for safety)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_id": "street_view_heritage_alamo@1",
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_file": "$OUTPUT_FILE",
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_format": "$IMAGE_FORMAT",
    "google_earth_running": $GE_RUNNING,
    "google_earth_pid": "$GE_PID",
    "google_earth_window_found": $GE_WINDOW_FOUND,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "street_view_in_title": $STREET_VIEW_INDICATED,
    "final_screenshot": "/tmp/task_final_state.png",
    "initial_screenshot": "/tmp/task_initial_state.png"
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