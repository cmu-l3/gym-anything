#!/bin/bash
set -e
echo "=== Exporting Flight Simulator Grand Canyon task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other operations
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if the expected output file exists
OUTPUT_PATH="/home/ga/grand_canyon_flight.png"
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
        echo "Output file was created during task execution"
    else
        echo "WARNING: Output file predates task start"
    fi
    
    echo "Output file found: $OUTPUT_PATH ($OUTPUT_SIZE bytes)"
else
    echo "Output file NOT found at: $OUTPUT_PATH"
    
    # Check for alternative locations
    echo "Checking alternative locations..."
    for alt_path in /home/ga/Pictures/*.png /home/ga/Desktop/*.png /tmp/*.png; do
        if [ -f "$alt_path" ]; then
            alt_mtime=$(stat -c %Y "$alt_path" 2>/dev/null || echo "0")
            if [ "$alt_mtime" -gt "$TASK_START" ]; then
                echo "Found recent screenshot: $alt_path"
            fi
        fi
    done 2>/dev/null || true
fi

# Get image dimensions if file exists
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"
IMAGE_FORMAT="none"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/grand_canyon_flight.png")
    print(json.dumps({"width": img.width, "height": img.height, "format": img.format or "unknown"}))
except Exception as e:
    print(json.dumps({"width": 0, "height": 0, "format": "error", "error": str(e)}))
PYEOF
    )
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    IMAGE_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
fi

# Check if Google Earth is still running
GE_RUNNING="false"
GE_WINDOW_TITLE=""
if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" | head -1 | cut -d' ' -f5- || echo "")
fi

# Check for flight simulator indicators in window title
FLIGHT_SIM_ACTIVE="false"
if echo "$GE_WINDOW_TITLE" | grep -qi "flight\|simulator\|F-16\|SR22"; then
    FLIGHT_SIM_ACTIVE="true"
fi

# Check all window titles for flight simulator
ALL_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
if echo "$ALL_WINDOWS" | grep -qi "flight simulator"; then
    FLIGHT_SIM_ACTIVE="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_id": "flight_simulator_grand_canyon@1",
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
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "flight_simulator_detected": $FLIGHT_SIM_ACTIVE,
    "final_screenshot_path": "/tmp/task_final.png",
    "initial_screenshot_path": "/tmp/task_initial.png"
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