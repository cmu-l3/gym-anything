#!/bin/bash
set -euo pipefail

echo "=== Exporting cartographic_export_scalebar task result ==="

export DISPLAY=${DISPLAY:-:1}

# ================================================================
# Record task end time
# ================================================================
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task start: $TASK_START"
echo "Task end: $TASK_END"
echo "Duration: $((TASK_END - TASK_START)) seconds"

# ================================================================
# Take final screenshot BEFORE any other operations
# ================================================================
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

FINAL_SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final_state.png ]; then
    FINAL_SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
fi

# ================================================================
# Check output file status
# ================================================================
OUTPUT_PATH="/home/ga/Documents/nile_delta_map.jpg"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"
IMAGE_FORMAT="unknown"
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"

# Also check for alternate extensions agent might have used
ALTERNATE_PATHS=(
    "/home/ga/Documents/nile_delta_map.png"
    "/home/ga/Documents/nile_delta_map.jpeg"
    "/home/ga/Documents/nile_delta_map.JPG"
)

ACTUAL_OUTPUT_PATH="$OUTPUT_PATH"

# First check the expected path
if [ -f "$OUTPUT_PATH" ]; then
    ACTUAL_OUTPUT_PATH="$OUTPUT_PATH"
else
    # Check alternates
    for alt_path in "${ALTERNATE_PATHS[@]}"; do
        if [ -f "$alt_path" ]; then
            ACTUAL_OUTPUT_PATH="$alt_path"
            echo "Found output at alternate path: $alt_path"
            break
        fi
    done
fi

if [ -f "$ACTUAL_OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$ACTUAL_OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$ACTUAL_OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "File was created during task execution"
    else
        echo "WARNING: File exists but was NOT created during task"
    fi
    
    # Get image format and dimensions using file command and Python/PIL
    IMAGE_FORMAT=$(file --mime-type "$ACTUAL_OUTPUT_PATH" 2>/dev/null | awk -F'/' '{print $2}' || echo "unknown")
    
    # Get dimensions using Python PIL
    DIMENSIONS=$(python3 << PYEOF 2>/dev/null || echo '{"width": 0, "height": 0}')
import json
try:
    from PIL import Image
    img = Image.open("$ACTUAL_OUTPUT_PATH")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format or "unknown", "mode": img.mode}))
except Exception as e:
    print(json.dumps({"width": 0, "height": 0, "format": "unknown", "mode": "unknown", "error": str(e)}))
PYEOF

    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    
    echo "Output file details:"
    echo "  Path: $ACTUAL_OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Format: $IMAGE_FORMAT"
    echo "  Dimensions: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}"
fi

# ================================================================
# Check Google Earth state
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get window title
GE_WINDOW_TITLE=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")

# ================================================================
# Check for scale legend in Google Earth config (if accessible)
# ================================================================
SCALE_LEGEND_ENABLED="unknown"
# Google Earth stores some preferences, but scale legend state may not be easily queryable
# This will be verified primarily through VLM analysis of the exported image

# ================================================================
# Create JSON result file
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_path": "$ACTUAL_OUTPUT_PATH",
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "image_format": "$IMAGE_FORMAT",
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "final_screenshot_exists": $FINAL_SCREENSHOT_EXISTS,
    "final_screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="