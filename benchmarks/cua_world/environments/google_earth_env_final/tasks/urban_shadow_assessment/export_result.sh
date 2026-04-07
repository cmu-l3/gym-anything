#!/bin/bash
set -e
echo "=== Exporting Urban Shadow Assessment task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot BEFORE any other operations
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    FINAL_SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${FINAL_SCREENSHOT_SIZE} bytes"
    FINAL_SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    FINAL_SCREENSHOT_EXISTS="false"
    FINAL_SCREENSHOT_SIZE="0"
fi

# Check output file
OUTPUT_PATH="/home/ga/shadow_assessment.png"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created DURING the task (anti-gaming)
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
    
    # Get image dimensions using Python/PIL
    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/shadow_assessment.png")
    print(json.dumps({
        "width": img.width, 
        "height": img.height, 
        "format": img.format or "unknown", 
        "mode": img.mode
    }))
except Exception as e:
    print(json.dumps({"error": str(e), "width": 0, "height": 0, "format": "unknown", "mode": "unknown"}))
PYEOF
)
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))")
    IMAGE_FORMAT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('format', 'unknown'))")
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    OUTPUT_MTIME="0"
    FILE_CREATED_DURING_TASK="false"
    IMAGE_WIDTH="0"
    IMAGE_HEIGHT="0"
    IMAGE_FORMAT="none"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
GE_PID=""
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
    GE_PID=$(pgrep -f "google-earth" | head -1)
fi

# Get Google Earth window title (may contain location info)
GE_WINDOW_TITLE=""
GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "google earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# Check for any KML/state changes in Google Earth directory
KML_MODIFIED="false"
if [ -f "/home/ga/.googleearth/myplaces.kml" ]; then
    KML_MTIME=$(stat -c%Y "/home/ga/.googleearth/myplaces.kml" 2>/dev/null || echo "0")
    if [ "$KML_MTIME" -gt "$TASK_START" ]; then
        KML_MODIFIED="true"
    fi
fi

# Create comprehensive JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_id": "urban_shadow_assessment@1",
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_file": {
        "path": "$OUTPUT_PATH",
        "exists": $OUTPUT_EXISTS,
        "size_bytes": $OUTPUT_SIZE,
        "mtime": $OUTPUT_MTIME,
        "created_during_task": $FILE_CREATED_DURING_TASK,
        "width": $IMAGE_WIDTH,
        "height": $IMAGE_HEIGHT,
        "format": "$IMAGE_FORMAT"
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "pid": "$GE_PID",
        "window_title": "$GE_WINDOW_TITLE",
        "kml_modified": $KML_MODIFIED
    },
    "screenshots": {
        "final_exists": $FINAL_SCREENSHOT_EXISTS,
        "final_size": $FINAL_SCREENSHOT_SIZE,
        "final_path": "/tmp/task_final_state.png",
        "initial_path": "/tmp/task_initial_state.png"
    },
    "verification_timestamp": "$(date -Iseconds)"
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