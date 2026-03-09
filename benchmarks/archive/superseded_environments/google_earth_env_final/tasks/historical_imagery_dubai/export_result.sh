#!/bin/bash
echo "=== Exporting Historical Imagery Dubai task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other checks
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

# ================================================================
# CHECK OUTPUT FILE
# ================================================================
OUTPUT_PATH="/home/ga/Documents/palm_jumeirah_2002.jpg"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_MODIFIED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created/modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "Output file was created during task"
    else
        echo "WARNING: Output file exists but was NOT created during task"
    fi
    
    # Check initial state to determine if file was modified
    INITIAL_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('output_mtime', 0))" 2>/dev/null || echo "0")
    if [ "$INITIAL_MTIME" != "0" ] && [ "$OUTPUT_MTIME" != "$INITIAL_MTIME" ]; then
        FILE_MODIFIED_DURING_TASK="true"
    fi
    
    echo "Output file: $OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $(date -d @$OUTPUT_MTIME 2>/dev/null || echo 'unknown')"
else
    echo "Output file NOT found at: $OUTPUT_PATH"
    
    # Check for alternative locations/formats
    echo "Checking for alternative outputs..."
    ls -la /home/ga/Documents/*.jpg /home/ga/Documents/*.png 2>/dev/null || echo "No image files in Documents"
fi

# ================================================================
# CHECK IMAGE PROPERTIES (if file exists)
# ================================================================
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"
IMAGE_FORMAT="none"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/Documents/palm_jumeirah_2002.jpg")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format or "unknown", "mode": img.mode}))
except Exception as e:
    print(json.dumps({"error": str(e), "width": 0, "height": 0, "format": "error", "mode": "unknown"}))
PYEOF
)
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    IMAGE_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
    echo "Image dimensions: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}, format: $IMAGE_FORMAT"
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_PID=""
GE_WINDOW_TITLE=""

if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f google-earth-pro | head -1)
    echo "Google Earth is running (PID: $GE_PID)"
fi

# Get window titles
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
    echo "Google Earth window: $GE_WINDOW_TITLE"
fi

# ================================================================
# CREATE JSON RESULT
# ================================================================
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
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_format": "$IMAGE_FORMAT",
    "google_earth_running": $GE_RUNNING,
    "google_earth_pid": "$GE_PID",
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "final_screenshot_path": "/tmp/task_final.png",
    "final_screenshot_size": $FINAL_SCREENSHOT_SIZE
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task Result JSON ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="