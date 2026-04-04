#!/bin/bash
echo "=== Exporting raycasting_bone_visualization result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

OUTPUT_PATH="/home/ga/Documents/volume_render_bone.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot (evidence of screen state)
take_screenshot /tmp/task_final.png

# Check if output file exists and get stats
OUTPUT_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
IS_VALID_PNG="false"
IMG_WIDTH="0"
IMG_HEIGHT="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check for PNG magic bytes
    MAGIC=$(head -c 8 "$OUTPUT_PATH" | xxd -p)
    if [ "$MAGIC" = "89504e470d0a1a0a" ]; then
        IS_VALID_PNG="true"
        
        # Get dimensions if python/PIL is available (likely in this env)
        DIMENSIONS=$(python3 -c "import sys; from PIL import Image; i=Image.open('$OUTPUT_PATH'); print(f'{i.width} {i.height}')" 2>/dev/null || echo "0 0")
        IMG_WIDTH=$(echo "$DIMENSIONS" | cut -d' ' -f1)
        IMG_HEIGHT=$(echo "$DIMENSIONS" | cut -d' ' -f2)
    fi
fi

# Check timestamps for anti-gaming
FILE_CREATED_DURING_TASK="false"
if [ "$OUTPUT_EXISTS" = "true" ] && [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "is_valid_png": $IS_VALID_PNG,
    "image_width": $IMG_WIDTH,
    "image_height": $IMG_HEIGHT,
    "output_path": "$OUTPUT_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to accessible location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="