#!/bin/bash
echo "=== Exporting extract_bolivia_raster results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Define Paths
OUTPUT_PATH="/home/ga/gvsig_data/exports/bolivia_relief.tif"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Analyze Output File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE_BYTES=0
IMG_WIDTH=0
IMG_HEIGHT=0
IMG_STD_DEV=0
FILE_FORMAT="unknown"

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    # Check timestamp
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Use ImageMagick (identify) to get image details
    # Returns: WIDTH HEIGHT STD_DEV FORMAT
    # StdDev is useful to ensure it's not a solid black/white rectangle
    IMG_INFO=$(identify -format "%w %h %[standard_deviation] %m" "$OUTPUT_PATH" 2>/dev/null || echo "0 0 0 unknown")
    
    IMG_WIDTH=$(echo "$IMG_INFO" | awk '{print $1}')
    IMG_HEIGHT=$(echo "$IMG_INFO" | awk '{print $2}')
    IMG_STD_DEV=$(echo "$IMG_INFO" | awk '{print $3}')
    FILE_FORMAT=$(echo "$IMG_INFO" | awk '{print $4}')
fi

# 4. Check App State
APP_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Prepare JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_path": "$OUTPUT_PATH",
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "image_width": $IMG_WIDTH,
    "image_height": $IMG_HEIGHT,
    "image_std_dev": "$IMG_STD_DEV",
    "image_format": "$FILE_FORMAT",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json