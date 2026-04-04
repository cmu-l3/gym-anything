#!/bin/bash
echo "=== Exporting create_server_rack_diagram results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
EDDX_PATH="/home/ga/Documents/rack_elevation.eddx"
PNG_PATH="/home/ga/Documents/rack_elevation.png"

# Check EDDX file
if [ -f "$EDDX_PATH" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_PATH" 2>/dev/null || echo "0")
    EDDX_MTIME=$(stat -c %Y "$EDDX_PATH" 2>/dev/null || echo "0")
else
    EDDX_EXISTS="false"
    EDDX_SIZE="0"
    EDDX_MTIME="0"
fi

# Check PNG file
if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")
    
    # Get image dimensions using python (if available) or identify
    PNG_DIMS=$(identify -format "%w %h" "$PNG_PATH" 2>/dev/null || echo "0 0")
    PNG_WIDTH=$(echo "$PNG_DIMS" | cut -d' ' -f1)
    PNG_HEIGHT=$(echo "$PNG_DIMS" | cut -d' ' -f2)
else
    PNG_EXISTS="false"
    PNG_SIZE="0"
    PNG_MTIME="0"
    PNG_WIDTH="0"
    PNG_HEIGHT="0"
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
    "eddx_size": $EDDX_SIZE,
    "eddx_mtime": $EDDX_MTIME,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "png_mtime": $PNG_MTIME,
    "png_width": $PNG_WIDTH,
    "png_height": $PNG_HEIGHT,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="