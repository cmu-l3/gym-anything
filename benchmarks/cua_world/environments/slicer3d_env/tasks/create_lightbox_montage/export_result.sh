#!/bin/bash
echo "=== Exporting Create Lightbox Montage task results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Expected output path
OUTPUT_PATH="/home/ga/Documents/SlicerData/Exports/brain_montage.png"
EXPORT_DIR="/home/ga/Documents/SlicerData/Exports"

# Take final screenshot first
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
fi

# Initialize result variables
MONTAGE_EXISTS="false"
MONTAGE_SIZE_BYTES=0
MONTAGE_SIZE_KB=0
MONTAGE_WIDTH=0
MONTAGE_HEIGHT=0
MONTAGE_FORMAT="none"
MONTAGE_COLORS=0
CREATED_AFTER_START="false"
FILE_MTIME=0

# Check montage file
if [ -f "$OUTPUT_PATH" ]; then
    MONTAGE_EXISTS="true"
    MONTAGE_SIZE_BYTES=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    MONTAGE_SIZE_KB=$((MONTAGE_SIZE_BYTES / 1024))
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    echo "Montage file found: $OUTPUT_PATH"
    echo "  Size: $MONTAGE_SIZE_KB KB"
    echo "  Modified: $(date -d @$FILE_MTIME 2>/dev/null || echo 'unknown')"
    
    # Check if created after task start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_AFTER_START="true"
        echo "  Created during task: YES"
    else
        echo "  Created during task: NO (file existed before task)"
    fi
    
    # Get image properties using Python/PIL
    DIMS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/Documents/SlicerData/Exports/brain_montage.png")
    
    # Count unique colors (sample for large images)
    if img.width * img.height > 100000:
        img_small = img.resize((200, 200))
        colors = len(set(img_small.getdata()))
    else:
        colors = len(set(img.getdata()))
    
    result = {
        "width": img.width,
        "height": img.height,
        "format": img.format or "PNG",
        "mode": img.mode,
        "colors": colors
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e), "width": 0, "height": 0, "format": "unknown", "mode": "unknown", "colors": 0}))
PYEOF
)
    
    MONTAGE_WIDTH=$(echo "$DIMS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    MONTAGE_HEIGHT=$(echo "$DIMS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")
    MONTAGE_FORMAT=$(echo "$DIMS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('format', 'unknown'))" 2>/dev/null || echo "unknown")
    MONTAGE_COLORS=$(echo "$DIMS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('colors', 0))" 2>/dev/null || echo "0")
    
    echo "  Dimensions: ${MONTAGE_WIDTH}x${MONTAGE_HEIGHT}"
    echo "  Format: $MONTAGE_FORMAT"
    echo "  Unique colors (sampled): $MONTAGE_COLORS"
    
    # Copy montage to /tmp for verification
    cp "$OUTPUT_PATH" /tmp/brain_montage_output.png 2>/dev/null || true
else
    echo "Montage file NOT found at: $OUTPUT_PATH"
    
    # Check if any PNG files were created in export directory
    echo "Checking for other PNG files in export directory..."
    ls -la "$EXPORT_DIR"/*.png 2>/dev/null || echo "  No PNG files found"
    
    # Check if file was saved elsewhere
    echo "Searching for recently created montage files..."
    find /home/ga -name "*.png" -newer /tmp/task_start_time.txt 2>/dev/null | head -5
fi

# Check what windows are open (for debugging)
echo ""
echo "Open windows:"
DISPLAY=:1 wmctrl -l 2>/dev/null | head -10 || echo "  Could not list windows"

# Check if Screen Capture module was likely accessed (by looking for temp files)
SCREEN_CAPTURE_USED="false"
if ls /tmp/Slicer*/ScreenCapture* 2>/dev/null || ls /home/ga/.config/NA-MIC/Slicer*/*ScreenCapture* 2>/dev/null; then
    SCREEN_CAPTURE_USED="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "montage_exists": $MONTAGE_EXISTS,
    "montage_size_bytes": $MONTAGE_SIZE_BYTES,
    "montage_size_kb": $MONTAGE_SIZE_KB,
    "montage_width": $MONTAGE_WIDTH,
    "montage_height": $MONTAGE_HEIGHT,
    "montage_format": "$MONTAGE_FORMAT",
    "montage_colors": $MONTAGE_COLORS,
    "created_after_task_start": $CREATED_AFTER_START,
    "file_mtime": $FILE_MTIME,
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "screen_capture_used": $SCREEN_CAPTURE_USED,
    "output_path": "$OUTPUT_PATH",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Results exported to /tmp/task_result.json ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="