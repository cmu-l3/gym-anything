#!/bin/bash
echo "=== Exporting download_picture_rendition results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DOWNLOAD_PATH="/home/ga/Downloads/event_medium.jpg"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Stats
if [ -f "$DOWNLOAD_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$DOWNLOAD_PATH")
    FILE_MTIME=$(stat -c%Y "$DOWNLOAD_PATH")
    
    # Check if created during task
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
    
    # 3. Analyze Image Dimensions (using ImageMagick inside container)
    # identify format: WIDTH HEIGHT FORMAT
    IMG_INFO=$(identify -format "%w %h %m" "$DOWNLOAD_PATH" 2>/dev/null || echo "0 0 UNKNOWN")
    IMG_WIDTH=$(echo "$IMG_INFO" | awk '{print $1}')
    IMG_HEIGHT=$(echo "$IMG_INFO" | awk '{print $2}')
    IMG_FORMAT=$(echo "$IMG_INFO" | awk '{print $3}')
else
    FILE_EXISTS="false"
    FILE_SIZE=0
    CREATED_DURING_TASK="false"
    IMG_WIDTH=0
    IMG_HEIGHT=0
    IMG_FORMAT="NONE"
fi

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "image_width": $IMG_WIDTH,
    "image_height": $IMG_HEIGHT,
    "image_format": "$IMG_FORMAT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="