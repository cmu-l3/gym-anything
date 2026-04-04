#!/bin/bash
echo "=== Exporting create_user_story_map results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot (critical for VLM verification)
take_screenshot /tmp/task_final.png

# 2. Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check EDDX File
EDDX_PATH="/home/ga/Documents/skyhigh_story_map.eddx"
if [ -f "$EDDX_PATH" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_PATH" 2>/dev/null || echo "0")
    EDDX_MTIME=$(stat -c %Y "$EDDX_PATH" 2>/dev/null || echo "0")
    
    if [ "$EDDX_MTIME" -gt "$TASK_START" ]; then
        EDDX_CREATED_DURING_TASK="true"
    else
        EDDX_CREATED_DURING_TASK="false"
    fi
else
    EDDX_EXISTS="false"
    EDDX_SIZE="0"
    EDDX_CREATED_DURING_TASK="false"
fi

# 4. Check PNG File
PNG_PATH="/home/ga/Documents/skyhigh_story_map.png"
if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")
    
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING_TASK="true"
    else
        PNG_CREATED_DURING_TASK="false"
    fi
    
    # Get dimensions if ImageMagick is available
    PNG_DIMS=$(identify -format "%wx%h" "$PNG_PATH" 2>/dev/null || echo "0x0")
else
    PNG_EXISTS="false"
    PNG_SIZE="0"
    PNG_CREATED_DURING_TASK="false"
    PNG_DIMS="0x0"
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_exists": $EDDX_EXISTS,
    "eddx_size": $EDDX_SIZE,
    "eddx_created_during_task": $EDDX_CREATED_DURING_TASK,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "png_created_during_task": $PNG_CREATED_DURING_TASK,
    "png_dimensions": "$PNG_DIMS",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move JSON to standard location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="