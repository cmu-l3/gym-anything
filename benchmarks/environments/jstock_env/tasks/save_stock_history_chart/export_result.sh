#!/bin/bash
echo "=== Exporting save_stock_history_chart result ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/NVDA_chart.png"

# 1. Check file existence and metadata
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")

    # Anti-gaming: Check if file was created AFTER task start
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi

    # 2. Check Image properties (using ImageMagick identify)
    # Returns format, width, height (e.g., "PNG 800 600")
    IMG_INFO=$(identify -format "%m %w %h" "$OUTPUT_PATH" 2>/dev/null || echo "UNKNOWN 0 0")
    IMG_FORMAT=$(echo "$IMG_INFO" | awk '{print $1}')
    IMG_WIDTH=$(echo "$IMG_INFO" | awk '{print $2}')
    IMG_HEIGHT=$(echo "$IMG_INFO" | awk '{print $3}')

else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
    IMG_FORMAT="NONE"
    IMG_WIDTH="0"
    IMG_HEIGHT="0"
fi

# 3. Check if JStock is still running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "image_format": "$IMG_FORMAT",
    "image_width": $IMG_WIDTH,
    "image_height": $IMG_HEIGHT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with safe permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="