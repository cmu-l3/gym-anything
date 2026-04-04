#!/bin/bash
set -e
echo "=== Exporting Stonehenge Solstice Shadows task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task timing: start=$TASK_START, end=$TASK_END"

# Take final screenshot BEFORE any other operations
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_evidence/final_screenshot.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_evidence/final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_evidence/final_screenshot.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_evidence/final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    echo "WARNING: Could not capture final screenshot"
    FINAL_SCREENSHOT_SIZE="0"
fi

# Check output file
OUTPUT_PATH="/home/ga/Pictures/stonehenge_solstice.png"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
IMAGE_VALID="false"
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"
IMAGE_FORMAT="none"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "Output file was created during task execution"
    else
        echo "WARNING: Output file exists but was NOT created during task"
    fi
    
    # Validate image format and get dimensions
    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/Pictures/stonehenge_solstice.png")
    print(json.dumps({
        "valid": True,
        "width": img.width,
        "height": img.height,
        "format": img.format or "unknown",
        "mode": img.mode
    }))
except Exception as e:
    print(json.dumps({
        "valid": False,
        "width": 0,
        "height": 0,
        "format": "error",
        "mode": "unknown",
        "error": str(e)
    }))
PYEOF
)
    
    IMAGE_VALID=$(echo "$DIMENSIONS" | python3 -c "import json,sys; print(str(json.load(sys.stdin).get('valid', False)).lower())")
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('width', 0))")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('height', 0))")
    IMAGE_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('format', 'unknown'))")
    
    echo "Image dimensions: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}, format: ${IMAGE_FORMAT}"
else
    echo "Output file not found at: $OUTPUT_PATH"
fi

# Check Google Earth state
GE_RUNNING="false"
GE_WINDOW_TITLE=""
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_WINDOW_TITLE=$(wmctrl -l | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "unknown")
fi

# Check for any Google Earth state files that might indicate activity
GE_CACHE_ACTIVITY="false"
if [ -d "/home/ga/.googleearth/Cache" ]; then
    # Check if cache was modified during task
    RECENT_CACHE=$(find /home/ga/.googleearth/Cache -type f -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    if [ -n "$RECENT_CACHE" ]; then
        GE_CACHE_ACTIVITY="true"
    fi
fi

# Copy output file to evidence directory for verification
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" /tmp/task_evidence/output_copy.png 2>/dev/null || true
fi

# Create comprehensive result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_id": "stonehenge_solstice_shadows@1",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output": {
        "path": "$OUTPUT_PATH",
        "exists": $OUTPUT_EXISTS,
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "image_valid": $IMAGE_VALID,
        "image_width": $IMAGE_WIDTH,
        "image_height": $IMAGE_HEIGHT,
        "image_format": "$IMAGE_FORMAT"
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE",
        "cache_activity": $GE_CACHE_ACTIVITY
    },
    "evidence": {
        "initial_screenshot": "/tmp/task_evidence/initial_screenshot.png",
        "final_screenshot": "/tmp/task_evidence/final_screenshot.png",
        "output_copy": "/tmp/task_evidence/output_copy.png"
    }
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task Result Summary ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="