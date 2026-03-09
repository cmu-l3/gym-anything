#!/bin/bash
echo "=== Exporting create_map_layout results ==="

source /workspace/scripts/task_utils.sh

OUTPUT_PATH="/home/ga/gvsig_data/exports/world_map_layout.png"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. File Verification
FILE_EXISTS="false"
FILE_SIZE_BYTES=0
FILE_CREATED_DURING_TASK="false"
IMAGE_WIDTH=0
IMAGE_HEIGHT=0
IS_VALID_IMAGE="false"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    # Check timestamp
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check image validity and dimensions using identify (ImageMagick)
    if command -v identify >/dev/null 2>&1; then
        IMG_INFO=$(identify -format "%w %h" "$OUTPUT_PATH" 2>/dev/null)
        if [ $? -eq 0 ]; then
            IS_VALID_IMAGE="true"
            IMAGE_WIDTH=$(echo "$IMG_INFO" | cut -d' ' -f1)
            IMAGE_HEIGHT=$(echo "$IMG_INFO" | cut -d' ' -f2)
        fi
    fi
fi

# 2. Application State
APP_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_RUNNING="true"
fi

# 3. Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_path": "$OUTPUT_PATH",
    "file_size_bytes": $FILE_SIZE_BYTES,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "is_valid_image": $IS_VALID_IMAGE,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "app_running": $APP_RUNNING
}
EOF

# Move to standard location with lenient permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy the exported image to /tmp so verifier can easily access it via copy_from_env
if [ "$FILE_EXISTS" == "true" ]; then
    cp "$OUTPUT_PATH" /tmp/exported_map.png
    chmod 666 /tmp/exported_map.png
fi

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="