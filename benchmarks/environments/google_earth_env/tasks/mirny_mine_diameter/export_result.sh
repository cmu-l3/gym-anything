#!/bin/bash
echo "=== Exporting Mirny Mine Diameter Measurement Result ==="

export DISPLAY=${DISPLAY:-:1}

# ================================================================
# CAPTURE FINAL SCREENSHOT FIRST (before any state changes)
# ================================================================
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
    FINAL_SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    FINAL_SCREENSHOT_EXISTS="false"
    FINAL_SCREENSHOT_SIZE="0"
fi

# ================================================================
# GET TIMING INFORMATION
# ================================================================
TASK_END_TIME=$(date +%s)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ================================================================
# CHECK OUTPUT FILE (SCREENSHOT)
# ================================================================
OUTPUT_PATH="/home/ga/mirny_measurement.png"
ALT_OUTPUT_PATHS=(
    "/home/ga/mirny_measurement.png"
    "/root/mirny_measurement.png"
    "/tmp/mirny_measurement.png"
    "/home/ga/Desktop/mirny_measurement.png"
    "/home/ga/Pictures/mirny_measurement.png"
)

OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
ACTUAL_OUTPUT_PATH=""

# Check primary path first
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    ACTUAL_OUTPUT_PATH="$OUTPUT_PATH"
    echo "Output file found at: $OUTPUT_PATH"
else
    # Check alternate paths
    for ALT_PATH in "${ALT_OUTPUT_PATHS[@]}"; do
        if [ -f "$ALT_PATH" ]; then
            OUTPUT_EXISTS="true"
            OUTPUT_SIZE=$(stat -c%s "$ALT_PATH" 2>/dev/null || echo "0")
            OUTPUT_MTIME=$(stat -c%Y "$ALT_PATH" 2>/dev/null || echo "0")
            ACTUAL_OUTPUT_PATH="$ALT_PATH"
            echo "Output file found at alternate path: $ALT_PATH"
            break
        fi
    done
fi

if [ "$OUTPUT_EXISTS" = "false" ]; then
    echo "Output file NOT found at any expected location"
fi

# ================================================================
# CHECK IF FILE WAS CREATED DURING TASK
# ================================================================
FILE_CREATED_DURING_TASK="false"
if [ "$OUTPUT_EXISTS" = "true" ] && [ "$TASK_START_TIME" != "0" ]; then
    if [ "$OUTPUT_MTIME" -gt "$TASK_START_TIME" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "File was created during task execution"
    else
        echo "WARNING: File may have existed before task started"
    fi
fi

# ================================================================
# GET IMAGE DIMENSIONS (if file exists)
# ================================================================
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"
IMAGE_FORMAT="unknown"

if [ "$OUTPUT_EXISTS" = "true" ] && [ -n "$ACTUAL_OUTPUT_PATH" ]; then
    # Try using Python/PIL
    DIMENSIONS=$(python3 << PYEOF 2>/dev/null || echo '{"width": 0, "height": 0, "format": "unknown"}'
import json
try:
    from PIL import Image
    img = Image.open("$ACTUAL_OUTPUT_PATH")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format or "unknown"}))
except Exception as e:
    print(json.dumps({"width": 0, "height": 0, "format": "error", "error": str(e)}))
PYEOF
)
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    IMAGE_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
    
    echo "Image dimensions: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}, format: ${IMAGE_FORMAT}"
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
    echo "Google Earth Pro is running"
fi

# Get window title
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
    echo "Google Earth window title: $GE_WINDOW_TITLE"
fi

# Check for Ruler window (indicates measurement tool was used)
RULER_WINDOW_VISIBLE="false"
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "ruler"; then
    RULER_WINDOW_VISIBLE="true"
    echo "Ruler tool window detected"
fi

# ================================================================
# CHECK GOOGLE EARTH CACHE FOR RECENT ACTIVITY
# ================================================================
CACHE_ACTIVITY="false"
CACHE_DIR="/home/ga/.googleearth/Cache"
if [ -d "$CACHE_DIR" ]; then
    # Check if any cache files were modified during task
    RECENT_CACHE=$(find "$CACHE_DIR" -type f -newer /tmp/task_initial.png 2>/dev/null | wc -l || echo "0")
    if [ "$RECENT_CACHE" -gt "0" ]; then
        CACHE_ACTIVITY="true"
        echo "Cache activity detected: $RECENT_CACHE files modified"
    fi
fi

# ================================================================
# CREATE JSON RESULT
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "task_end_time": $TASK_END_TIME,
    "output_file": {
        "exists": $OUTPUT_EXISTS,
        "path": "$ACTUAL_OUTPUT_PATH",
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "image_width": $IMAGE_WIDTH,
        "image_height": $IMAGE_HEIGHT,
        "image_format": "$IMAGE_FORMAT"
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE",
        "ruler_window_visible": $RULER_WINDOW_VISIBLE,
        "cache_activity": $CACHE_ACTIVITY
    },
    "screenshots": {
        "final_exists": $FINAL_SCREENSHOT_EXISTS,
        "final_size_bytes": $FINAL_SCREENSHOT_SIZE,
        "final_path": "/tmp/task_final.png"
    }
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Result JSON ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="