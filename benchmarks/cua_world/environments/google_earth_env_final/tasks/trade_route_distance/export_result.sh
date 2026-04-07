#!/bin/bash
set -euo pipefail

echo "=== Exporting trade_route_distance task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task end time: $TASK_END"
echo "Task start time: $TASK_START"

# Take final screenshot BEFORE any other processing
echo "Capturing final state screenshot..."
scrot /tmp/task_final.png 2>/dev/null || \
    import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
else
    FINAL_SCREENSHOT_SIZE="0"
    echo "WARNING: Could not capture final screenshot"
fi

# ================================================================
# CHECK OUTPUT FILE
# ================================================================
OUTPUT_PATH="/home/ga/trade_route_measurement.png"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created/modified DURING the task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Validate image file
    IMAGE_VALID="false"
    IMAGE_WIDTH="0"
    IMAGE_HEIGHT="0"
    IMAGE_FORMAT="unknown"
    
    if command -v python3 &> /dev/null; then
        DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/trade_route_measurement.png")
    print(json.dumps({
        "width": img.width,
        "height": img.height,
        "format": img.format or "unknown",
        "mode": img.mode,
        "valid": True
    }))
except Exception as e:
    print(json.dumps({
        "error": str(e),
        "width": 0,
        "height": 0,
        "format": "unknown",
        "mode": "unknown",
        "valid": False
    }))
PYEOF
)
        IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))")
        IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))")
        IMAGE_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))")
        IMAGE_VALID=$(echo "$DIMENSIONS" | python3 -c "import json, sys; v=json.load(sys.stdin).get('valid', False); print('true' if v else 'false')")
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    IMAGE_VALID="false"
    IMAGE_WIDTH="0"
    IMAGE_HEIGHT="0"
    IMAGE_FORMAT="none"
fi

echo "Output file exists: $OUTPUT_EXISTS"
echo "Output file size: $OUTPUT_SIZE bytes"
echo "Created during task: $FILE_CREATED_DURING_TASK"

# ================================================================
# CHECK INITIAL STATE FOR COMPARISON
# ================================================================
INITIAL_EXISTS="false"
INITIAL_SIZE="0"
INITIAL_MTIME="0"

if [ -f /tmp/initial_state.json ]; then
    INITIAL_EXISTS=$(python3 -c "import json; v=json.load(open('/tmp/initial_state.json')).get('output_exists', False); print('true' if v else 'false')" 2>/dev/null || echo "false")
    INITIAL_SIZE=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('output_size', 0))" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('output_mtime', 0))" 2>/dev/null || echo "0")
fi

# Determine if file was newly created vs pre-existing
FILE_NEWLY_CREATED="false"
FILE_MODIFIED="false"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    if [ "$INITIAL_EXISTS" = "false" ]; then
        FILE_NEWLY_CREATED="true"
    elif [ "$OUTPUT_MTIME" != "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOWS=$(wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# Check for Ruler window (indicates measurement tool was used)
RULER_WINDOW_VISIBLE="false"
if wmctrl -l 2>/dev/null | grep -qi "ruler\|measure"; then
    RULER_WINDOW_VISIBLE="true"
fi

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_file": {
        "exists": $OUTPUT_EXISTS,
        "path": "$OUTPUT_PATH",
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "newly_created": $FILE_NEWLY_CREATED,
        "modified": $FILE_MODIFIED,
        "image_valid": $IMAGE_VALID,
        "image_width": $IMAGE_WIDTH,
        "image_height": $IMAGE_HEIGHT,
        "image_format": "$IMAGE_FORMAT"
    },
    "initial_state": {
        "output_existed": $INITIAL_EXISTS,
        "output_size": $INITIAL_SIZE,
        "output_mtime": $INITIAL_MTIME
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE",
        "ruler_window_visible": $RULER_WINDOW_VISIBLE
    },
    "screenshots": {
        "final_screenshot": "/tmp/task_final.png",
        "final_screenshot_size": $FINAL_SCREENSHOT_SIZE,
        "initial_screenshot": "/tmp/task_initial.png"
    }
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Task Result Summary ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="