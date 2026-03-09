#!/bin/bash
echo "=== Exporting create_uml_activity_diagram results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected output paths
EDDX_PATH="/home/ga/Documents/order_processing_activity.eddx"
PNG_PATH="/home/ga/Documents/order_processing_activity.png"

# Check EDDX file
EDDX_EXISTS="false"
EDDX_CREATED_DURING="false"
EDDX_SIZE="0"

if [ -f "$EDDX_PATH" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_PATH" 2>/dev/null || echo "0")
    EDDX_MTIME=$(stat -c %Y "$EDDX_PATH" 2>/dev/null || echo "0")
    if [ "$EDDX_MTIME" -gt "$TASK_START" ]; then
        EDDX_CREATED_DURING="true"
    fi
fi

# Check PNG file
PNG_EXISTS="false"
PNG_CREATED_DURING="false"
PNG_SIZE="0"
PNG_WIDTH="0"
PNG_HEIGHT="0"

if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING="true"
    fi
    
    # Get image dimensions using identify (ImageMagick)
    if command -v identify >/dev/null 2>&1; then
        DIMS=$(identify -format "%w %h" "$PNG_PATH" 2>/dev/null || echo "0 0")
        PNG_WIDTH=$(echo "$DIMS" | cut -d' ' -f1)
        PNG_HEIGHT=$(echo "$DIMS" | cut -d' ' -f2)
    fi
fi

# Check if app is running
APP_RUNNING=$(pgrep -f "EdrawMax" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_exists": $EDDX_EXISTS,
    "eddx_created_during_task": $EDDX_CREATED_DURING,
    "eddx_size_bytes": $EDDX_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_created_during_task": $PNG_CREATED_DURING,
    "png_size_bytes": $PNG_SIZE,
    "png_width": $PNG_WIDTH,
    "png_height": $PNG_HEIGHT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="