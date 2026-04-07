#!/bin/bash
set -e
echo "=== Exporting Mars Olympus Exploration result ==="

export DISPLAY=${DISPLAY:-:1}

# Take final screenshot FIRST (before any other operations)
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task start: $TASK_START"
echo "Task end: $TASK_END"

# ================================================================
# Check for output file
# ================================================================
OUTPUT_DIR="/home/ga/Documents"
OUTPUT_EXISTS="false"
OUTPUT_PATH=""
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
FILE_CREATED_DURING_TASK="false"

# Check for valid output files
for ext in png jpg jpeg; do
    CANDIDATE="$OUTPUT_DIR/olympus_mons.$ext"
    if [ -f "$CANDIDATE" ]; then
        OUTPUT_EXISTS="true"
        OUTPUT_PATH="$CANDIDATE"
        OUTPUT_SIZE=$(stat -c %s "$CANDIDATE" 2>/dev/null || echo "0")
        OUTPUT_MTIME=$(stat -c %Y "$CANDIDATE" 2>/dev/null || echo "0")
        
        # Check if file was created during task (ANTI-GAMING)
        if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
        break
    fi
done

echo "Output exists: $OUTPUT_EXISTS"
echo "Output path: $OUTPUT_PATH"
echo "Output size: $OUTPUT_SIZE bytes"
echo "File created during task: $FILE_CREATED_DURING_TASK"

# ================================================================
# Get image properties if output exists
# ================================================================
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"
IMAGE_FORMAT="none"
AVG_RED="0"
AVG_GREEN="0"
AVG_BLUE="0"
RED_DOMINANCE="0"

if [ "$OUTPUT_EXISTS" = "true" ] && [ -f "$OUTPUT_PATH" ]; then
    # Get image dimensions and color analysis
    IMAGE_INFO=$(python3 << PYEOF
import json
try:
    from PIL import Image
    import numpy as np
    
    img = Image.open("$OUTPUT_PATH")
    result = {
        "width": img.width,
        "height": img.height,
        "format": img.format or "unknown",
        "mode": img.mode
    }
    
    # Color analysis to detect Mars (reddish terrain)
    if img.mode in ['RGB', 'RGBA']:
        arr = np.array(img.convert('RGB'))
        avg_red = float(np.mean(arr[:,:,0]))
        avg_green = float(np.mean(arr[:,:,1]))
        avg_blue = float(np.mean(arr[:,:,2]))
        result["avg_red"] = avg_red
        result["avg_green"] = avg_green
        result["avg_blue"] = avg_blue
        result["red_dominance"] = avg_red - avg_blue
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e), "width": 0, "height": 0, "format": "error"}))
PYEOF
)
    
    IMAGE_WIDTH=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    IMAGE_FORMAT=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
    AVG_RED=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('avg_red', 0))" 2>/dev/null || echo "0")
    AVG_GREEN=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('avg_green', 0))" 2>/dev/null || echo "0")
    AVG_BLUE=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('avg_blue', 0))" 2>/dev/null || echo "0")
    RED_DOMINANCE=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('red_dominance', 0))" 2>/dev/null || echo "0")
fi

# ================================================================
# Check Google Earth state
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get window title (may indicate Mars mode)
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

echo "Google Earth running: $GE_RUNNING"
echo "Window title: $GE_WINDOW_TITLE"

# ================================================================
# Create JSON result file
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_id": "mars_olympus_exploration@1",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output": {
        "exists": $OUTPUT_EXISTS,
        "path": "$OUTPUT_PATH",
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK
    },
    "image": {
        "width": $IMAGE_WIDTH,
        "height": $IMAGE_HEIGHT,
        "format": "$IMAGE_FORMAT",
        "avg_red": $AVG_RED,
        "avg_green": $AVG_GREEN,
        "avg_blue": $AVG_BLUE,
        "red_dominance": $RED_DOMINANCE
    },
    "application": {
        "google_earth_running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE"
    },
    "screenshots": {
        "initial": "/tmp/task_initial_state.png",
        "final": "/tmp/task_final_state.png"
    }
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json