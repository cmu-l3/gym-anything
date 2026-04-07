#!/bin/bash
echo "=== Exporting Giza Pyramids Export task result ==="

export DISPLAY=${DISPLAY:-:1}

# ============================================================
# Take final screenshot FIRST (before any state changes)
# ============================================================
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
fi

# ============================================================
# Get task timing information
# ============================================================
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task timing: start=$TASK_START, end=$TASK_END"

# ============================================================
# Check output file
# ============================================================
OUTPUT_PATH="/home/ga/Desktop/giza_pyramids.png"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"
IMAGE_FORMAT="unknown"
IMAGE_MODE="unknown"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    echo "Output file found: $OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $OUTPUT_MTIME"
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "  Created during task: YES"
    else
        echo "  Created during task: NO (predates task start)"
    fi
    
    # Get image dimensions using Python/PIL
    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/Desktop/giza_pyramids.png")
    result = {
        "width": img.width,
        "height": img.height,
        "format": img.format or "unknown",
        "mode": img.mode or "unknown"
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"width": 0, "height": 0, "format": "error", "mode": "error", "error": str(e)}))
PYEOF
)
    
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    IMAGE_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
    IMAGE_MODE=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('mode', 'unknown'))" 2>/dev/null || echo "unknown")
    
    echo "  Dimensions: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}"
    echo "  Format: $IMAGE_FORMAT"
    echo "  Mode: $IMAGE_MODE"
else
    echo "Output file NOT found at: $OUTPUT_PATH"
    
    # Check alternative locations
    echo "Checking alternative locations..."
    for ALT_PATH in "/home/ga/Desktop/giza_pyramids.jpg" "/home/ga/giza_pyramids.png" "/home/ga/Documents/giza_pyramids.png"; do
        if [ -f "$ALT_PATH" ]; then
            echo "  Found at alternative location: $ALT_PATH"
        fi
    done
fi

# ============================================================
# Check Google Earth state
# ============================================================
GE_RUNNING="false"
GE_PID=""
GE_WINDOW_TITLE=""

if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth-pro" | head -1)
    echo "Google Earth Pro running: PID $GE_PID"
fi

# Get window title
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | sed 's/^[^ ]* *[^ ]* *[^ ]* *//')
    echo "Window title: $GE_WINDOW_TITLE"
fi

# ============================================================
# Check for color diversity (non-trivial image check)
# ============================================================
COLOR_DIVERSITY="0"
if [ -f "$OUTPUT_PATH" ]; then
    COLOR_DIVERSITY=$(python3 << 'PYEOF'
try:
    from PIL import Image
    img = Image.open("/home/ga/Desktop/giza_pyramids.png")
    img_small = img.resize((100, 100))
    colors = img_small.getcolors(maxcolors=10000)
    if colors is None:
        print("10000")  # More than 10000 unique colors
    else:
        print(len(colors))
except:
    print("0")
PYEOF
)
    echo "Color diversity: $COLOR_DIVERSITY unique colors"
fi

# ============================================================
# Create JSON result file
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_path": "$OUTPUT_PATH",
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_format": "$IMAGE_FORMAT",
    "image_mode": "$IMAGE_MODE",
    "color_diversity": $COLOR_DIVERSITY,
    "google_earth_running": $GE_RUNNING,
    "google_earth_pid": "$GE_PID",
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task result exported ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="