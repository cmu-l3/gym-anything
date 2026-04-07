#!/bin/bash
set -e
echo "=== Exporting Grid Navigation to Bermuda Triangle task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task end time: $TASK_END"
echo "Task start time: $TASK_START"

# Take final screenshot
echo "Capturing final screenshot..."
scrot /tmp/task_final_screenshot.png 2>/dev/null || true

if [ -f /tmp/task_final_screenshot.png ]; then
    FINAL_SIZE=$(stat -c %s /tmp/task_final_screenshot.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SIZE} bytes"
else
    echo "WARNING: Could not capture final screenshot"
fi

# ================================================================
# CHECK OUTPUT FILE
# ================================================================
OUTPUT_PATH="/home/ga/Pictures/bermuda_grid.png"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    echo "Output file found:"
    echo "  Path: $OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Mtime: $OUTPUT_MTIME"
    
    # Check if file was created during task (anti-gaming)
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "  Created during task: YES"
    else
        echo "  Created during task: NO (file predates task)"
    fi
else
    echo "Output file NOT found at $OUTPUT_PATH"
fi

# ================================================================
# GET IMAGE DIMENSIONS (if file exists)
# ================================================================
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"
IMAGE_FORMAT="none"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/Pictures/bermuda_grid.png")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format or "unknown", "mode": img.mode}))
except Exception as e:
    print(json.dumps({"error": str(e), "width": 0, "height": 0, "format": "error", "mode": "unknown"}))
PYEOF
)
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    IMAGE_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
    
    echo "  Dimensions: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}"
    echo "  Format: $IMAGE_FORMAT"
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GOOGLE_EARTH_RUNNING="false"
WINDOW_TITLE=""

if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GOOGLE_EARTH_RUNNING="true"
fi

# Get window title
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# Check for grid setting in config (if accessible)
GRID_IN_CONFIG="unknown"
EARTH_CONF="/home/ga/.config/Google/GoogleEarthPro.conf"
if [ -f "$EARTH_CONF" ]; then
    if grep -q "GridVisible=true" "$EARTH_CONF" 2>/dev/null; then
        GRID_IN_CONFIG="true"
    elif grep -q "GridVisible=false" "$EARTH_CONF" 2>/dev/null; then
        GRID_IN_CONFIG="false"
    fi
fi

# List all visible windows for debugging
echo ""
echo "Visible windows:"
wmctrl -l 2>/dev/null || echo "wmctrl not available"

# ================================================================
# CREATE JSON RESULT
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$OUTPUT_PATH",
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_format": "$IMAGE_FORMAT",
    "google_earth_running": $GOOGLE_EARTH_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "grid_in_config": "$GRID_IN_CONFIG",
    "final_screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task Result JSON ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="