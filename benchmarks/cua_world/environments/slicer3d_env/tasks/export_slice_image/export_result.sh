#!/bin/bash
echo "=== Exporting Export Slice Image Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Expected output path
OUTPUT_PATH="/home/ga/Documents/SlicerData/Exports/ventricles_axial.png"

# Get initial state
INITIAL_EXISTS="false"
INITIAL_SIZE="0"
INITIAL_MTIME="0"
if [ -f /tmp/initial_state.json ]; then
    INITIAL_EXISTS=$(python3 -c "import json; d=json.load(open('/tmp/initial_state.json')); print('true' if d.get('output_exists') else 'false')" 2>/dev/null || echo "false")
    INITIAL_SIZE=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('output_size', 0))" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(python3 -c "import json; print(json.load(open('/tmp/initial_state.json')).get('output_mtime', 0))" 2>/dev/null || echo "0")
fi

# Check output file
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"
IMAGE_FORMAT="none"
FILE_CREATED_DURING_TASK="false"
FILE_MODIFIED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    echo "Output file found: $OUTPUT_PATH"
    echo "  Size: $OUTPUT_SIZE bytes"
    echo "  Modified: $OUTPUT_MTIME"
    
    # Check if file was created/modified during task
    if [ "$INITIAL_EXISTS" = "false" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "  Status: NEWLY CREATED during task"
    elif [ "$OUTPUT_MTIME" -gt "$INITIAL_MTIME" ]; then
        FILE_MODIFIED_DURING_TASK="true"
        echo "  Status: MODIFIED during task"
    else
        echo "  Status: EXISTS but NOT modified (pre-existing file)"
    fi
    
    # Also verify it was created after task start
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        echo "  Timestamp verification: Created AFTER task start time"
    else
        echo "  WARNING: File timestamp is BEFORE task start time"
        FILE_CREATED_DURING_TASK="false"
        FILE_MODIFIED_DURING_TASK="false"
    fi
    
    # Get image dimensions using Python/PIL
    IMAGE_INFO=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/Documents/SlicerData/Exports/ventricles_axial.png")
    print(json.dumps({
        "width": img.width,
        "height": img.height,
        "format": img.format or "unknown",
        "mode": img.mode,
        "valid": True
    }))
    img.close()
except Exception as e:
    print(json.dumps({
        "width": 0,
        "height": 0,
        "format": "error",
        "mode": "unknown",
        "valid": False,
        "error": str(e)
    }))
PYEOF
)
    
    IMAGE_WIDTH=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    IMAGE_FORMAT=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
    IMAGE_VALID=$(echo "$IMAGE_INFO" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('valid') else 'false')" 2>/dev/null || echo "false")
    
    echo "  Dimensions: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}"
    echo "  Format: $IMAGE_FORMAT"
    
    # Copy output file for verification
    cp "$OUTPUT_PATH" /tmp/exported_slice.png 2>/dev/null || true
    
else
    echo "Output file NOT FOUND at: $OUTPUT_PATH"
    
    # Search for any PNG files that might have been created
    echo "Searching for recently created PNG files..."
    EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"
    SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
    
    for search_dir in "$EXPORT_DIR" "$SCREENSHOT_DIR" "/home/ga" "/home/ga/Desktop"; do
        if [ -d "$search_dir" ]; then
            FOUND_FILES=$(find "$search_dir" -maxdepth 2 -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | head -5)
            if [ -n "$FOUND_FILES" ]; then
                echo "  Found in $search_dir:"
                echo "$FOUND_FILES"
            fi
        fi
    done
fi

# Check if Slicer is running
SLICER_RUNNING="false"
SLICER_PID=""
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
fi

# Check what windows are open
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
SCREEN_CAPTURE_OPEN="false"
if echo "$WINDOW_LIST" | grep -qi "Screen Capture\|ScreenCapture"; then
    SCREEN_CAPTURE_OPEN="true"
fi

echo ""
echo "Slicer running: $SLICER_RUNNING"
echo "Screen Capture module open: $SCREEN_CAPTURE_OPEN"

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_path": "$OUTPUT_PATH",
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_modified_during_task": $FILE_MODIFIED_DURING_TASK,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_format": "$IMAGE_FORMAT",
    "slicer_was_running": $SLICER_RUNNING,
    "screen_capture_module_used": $SCREEN_CAPTURE_OPEN,
    "initial_file_existed": $INITIAL_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "exported_image_path": "/tmp/exported_slice.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/task_result.json:"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="