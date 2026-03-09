#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
EDDX_PATH="/home/ga/Documents/build_vs_buy_tree.eddx"
PNG_PATH="/home/ga/Documents/build_vs_buy_tree.png"

# Check EDDX file
if [ -f "$EDDX_PATH" ]; then
    EDDX_MTIME=$(stat -c %Y "$EDDX_PATH" 2>/dev/null || echo "0")
    if [ "$EDDX_MTIME" -gt "$TASK_START" ]; then
        EDDX_CREATED_DURING_TASK="true"
    else
        EDDX_CREATED_DURING_TASK="false"
    fi
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_PATH" 2>/dev/null || echo "0")
else
    EDDX_EXISTS="false"
    EDDX_CREATED_DURING_TASK="false"
    EDDX_SIZE="0"
fi

# Check PNG file
if [ -f "$PNG_PATH" ]; then
    PNG_MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING_TASK="true"
    else
        PNG_CREATED_DURING_TASK="false"
    fi
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
else
    PNG_EXISTS="false"
    PNG_CREATED_DURING_TASK="false"
    PNG_SIZE="0"
fi

# Check if application was running
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
    "eddx_path": "$EDDX_PATH",
    "eddx_created_during_task": $EDDX_CREATED_DURING_TASK,
    "eddx_size_bytes": $EDDX_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_path": "$PNG_PATH",
    "png_created_during_task": $PNG_CREATED_DURING_TASK,
    "png_size_bytes": $PNG_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="