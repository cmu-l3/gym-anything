#!/bin/bash
set -e
echo "=== Exporting Lake Bled Area Measurement Results ==="

export DISPLAY=${DISPLAY:-:1}

# ============================================================
# Record task end time
# ============================================================
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_DURATION=$((TASK_END - TASK_START))

echo "Task duration: ${TASK_DURATION} seconds"

# ============================================================
# Take final screenshot before checking results
# ============================================================
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    FINAL_SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# ============================================================
# Check output file
# ============================================================
OUTPUT_PATH="/home/ga/lake_bled_measurement.png"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during the task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "Output file was created during task"
    else
        echo "WARNING: Output file exists but was NOT created during task"
    fi
    
    echo "Output file found: $OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $(date -d @$OUTPUT_MTIME 2>/dev/null || echo $OUTPUT_MTIME)"
else
    echo "Output file NOT found: $OUTPUT_PATH"
fi

# ============================================================
# Check Google Earth state
# ============================================================
GOOGLE_EARTH_RUNNING="false"
GOOGLE_EARTH_PID=""
GOOGLE_EARTH_WINDOW=""

if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GOOGLE_EARTH_RUNNING="true"
    GOOGLE_EARTH_PID=$(pgrep -f google-earth-pro | head -1)
    echo "Google Earth Pro is running (PID: $GOOGLE_EARTH_PID)"
fi

# Get window title
GOOGLE_EARTH_WINDOW=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
echo "Google Earth window: $GOOGLE_EARTH_WINDOW"

# ============================================================
# Check for ruler/measurement tool artifacts
# ============================================================
# Google Earth stores some state in ~/.googleearth/
RULER_USED="unknown"
if [ -d "/home/ga/.googleearth" ]; then
    # Check for recent activity in Google Earth directory
    GE_DIR_MTIME=$(stat -c %Y /home/ga/.googleearth 2>/dev/null || echo "0")
    if [ "$GE_DIR_MTIME" -gt "$TASK_START" ]; then
        RULER_USED="likely"
    fi
fi

# ============================================================
# Analyze output image if it exists
# ============================================================
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"
IMAGE_FORMAT="unknown"

if [ "$OUTPUT_EXISTS" = "true" ] && [ "$OUTPUT_SIZE" -gt "0" ]; then
    # Try to get image dimensions using Python/PIL
    IMAGE_INFO=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/lake_bled_measurement.png")
    print(json.dumps({
        "width": img.width,
        "height": img.height,
        "format": img.format or "unknown",
        "mode": img.mode
    }))
except Exception as e:
    print(json.dumps({"error": str(e), "width": 0, "height": 0, "format": "error", "mode": "unknown"}))
PYEOF
)
    IMAGE_WIDTH=$(echo "$IMAGE_INFO" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$IMAGE_INFO" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    IMAGE_FORMAT=$(echo "$IMAGE_INFO" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
    
    echo "Image dimensions: ${IMAGE_WIDTH}x${IMAGE_HEIGHT} (${IMAGE_FORMAT})"
fi

# ============================================================
# Create JSON result
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $TASK_DURATION,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_format": "$IMAGE_FORMAT",
    "google_earth_running": $GOOGLE_EARTH_RUNNING,
    "google_earth_pid": "$GOOGLE_EARTH_PID",
    "google_earth_window": "$GOOGLE_EARTH_WINDOW",
    "ruler_used": "$RULER_USED",
    "final_screenshot_path": "/tmp/task_final.png",
    "final_screenshot_size": $FINAL_SCREENSHOT_SIZE,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="