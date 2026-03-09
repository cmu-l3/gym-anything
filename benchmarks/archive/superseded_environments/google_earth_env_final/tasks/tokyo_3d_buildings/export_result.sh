#!/bin/bash
set -euo pipefail

echo "=== Exporting tokyo_3d_buildings task result ==="

export DISPLAY=${DISPLAY:-:1}

# ============================================================
# Record task end time
# ============================================================
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_DURATION=$((TASK_END - TASK_START))

echo "Task duration: ${TASK_DURATION} seconds"

# ============================================================
# Take final screenshot FIRST (before any state changes)
# ============================================================
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

FINAL_SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final_state.png ]; then
    FINAL_SCREENSHOT_EXISTS="true"
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    FINAL_SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# ============================================================
# Check output file status
# ============================================================
OUTPUT_FILE="/home/ga/Documents/tokyo_skyline_3d.png"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"
IMAGE_FORMAT="none"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    echo "Output file found: $OUTPUT_FILE"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $OUTPUT_MTIME"
    
    # Check if file was created/modified during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "  Created during task: YES"
    else
        echo "  Created during task: NO (pre-existing file)"
    fi
    
    # Get image dimensions using Python/PIL
    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/Documents/tokyo_skyline_3d.png")
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
    
    echo "  Dimensions: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}"
    echo "  Format: $IMAGE_FORMAT"
else
    echo "Output file NOT found: $OUTPUT_FILE"
fi

# ============================================================
# Check Google Earth state
# ============================================================
GE_RUNNING="false"
GE_PID=""
GE_WINDOW_TITLE=""

if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f google-earth-pro | head -1)
    echo "Google Earth is running (PID: $GE_PID)"
fi

# Get window information
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
    echo "Google Earth window: $GE_WINDOW_TITLE"
fi

# ============================================================
# Check Google Earth cache for activity (indicates data was loaded)
# ============================================================
CACHE_ACTIVITY="0"
if [ -d "/home/ga/.googleearth/Cache" ]; then
    # Count files modified during the task
    CACHE_ACTIVITY=$(find /home/ga/.googleearth/Cache -type f -newermt "@$TASK_START" 2>/dev/null | wc -l || echo "0")
    echo "Cache files modified during task: $CACHE_ACTIVITY"
fi

# ============================================================
# List Documents directory contents
# ============================================================
echo ""
echo "Documents directory contents:"
ls -la /home/ga/Documents/ 2>/dev/null || echo "(empty or not accessible)"

# ============================================================
# Create JSON result file
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_id": "tokyo_3d_buildings@1",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $TASK_DURATION,
    "output_file": {
        "path": "$OUTPUT_FILE",
        "exists": $OUTPUT_EXISTS,
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "image_width": $IMAGE_WIDTH,
        "image_height": $IMAGE_HEIGHT,
        "image_format": "$IMAGE_FORMAT"
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "pid": "$GE_PID",
        "window_title": "$GE_WINDOW_TITLE",
        "cache_activity": $CACHE_ACTIVITY
    },
    "screenshots": {
        "final_exists": $FINAL_SCREENSHOT_EXISTS,
        "final_path": "/tmp/task_final_state.png",
        "final_size": $FINAL_SCREENSHOT_SIZE
    }
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json