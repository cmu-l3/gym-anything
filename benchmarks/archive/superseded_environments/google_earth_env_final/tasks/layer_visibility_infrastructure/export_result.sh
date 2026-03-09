#!/bin/bash
echo "=== Exporting layer_visibility_infrastructure task result ==="

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
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
    FINAL_SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    FINAL_SCREENSHOT_EXISTS="false"
    FINAL_SCREENSHOT_SIZE="0"
fi

# Check output file status
OUTPUT_PATH="/home/ga/Documents/sf_infrastructure.png"
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Get image dimensions using Python/PIL
    IMAGE_INFO=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/Documents/sf_infrastructure.png")
    print(json.dumps({
        "width": img.width,
        "height": img.height,
        "format": img.format or "unknown",
        "mode": img.mode,
        "valid": True
    }))
except Exception as e:
    print(json.dumps({
        "width": 0,
        "height": 0,
        "format": "unknown",
        "mode": "unknown",
        "valid": False,
        "error": str(e)
    }))
PYEOF
)
    IMAGE_WIDTH=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    IMAGE_FORMAT=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
    IMAGE_VALID=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('valid', False)).lower())" 2>/dev/null || echo "false")
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    IMAGE_WIDTH="0"
    IMAGE_HEIGHT="0"
    IMAGE_FORMAT="none"
    IMAGE_VALID="false"
fi

# Check if Google Earth is running
GOOGLE_EARTH_RUNNING="false"
GOOGLE_EARTH_PID=""
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GOOGLE_EARTH_RUNNING="true"
    GOOGLE_EARTH_PID=$(pgrep -f "google-earth" | head -1)
fi

# Get Google Earth window title
WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")

# Copy output file to /tmp for easier access by verifier
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" /tmp/sf_infrastructure_output.png 2>/dev/null || true
    chmod 644 /tmp/sf_infrastructure_output.png 2>/dev/null || true
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
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_format": "$IMAGE_FORMAT",
    "image_valid": $IMAGE_VALID,
    "google_earth_running": $GOOGLE_EARTH_RUNNING,
    "google_earth_pid": "$GOOGLE_EARTH_PID",
    "window_title": "$WINDOW_TITLE",
    "final_screenshot_exists": $FINAL_SCREENSHOT_EXISTS,
    "final_screenshot_path": "/tmp/task_final_state.png",
    "output_copy_path": "/tmp/sf_infrastructure_output.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="