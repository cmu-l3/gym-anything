#!/bin/bash
echo "=== Exporting Dual Axis Macro Plot results ==="

source /workspace/scripts/task_utils.sh

# Define paths
PNG_PATH="/home/ga/Documents/gretl_output/growth_inflation_plot.png"
PLT_PATH="/home/ga/Documents/gretl_output/growth_inflation_plot.plt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check PNG
PNG_EXISTS="false"
PNG_CREATED_DURING_TASK="false"
PNG_SIZE="0"
if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH")
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING_TASK="true"
    fi
fi

# Check PLT
PLT_EXISTS="false"
PLT_CREATED_DURING_TASK="false"
if [ -f "$PLT_PATH" ]; then
    PLT_EXISTS="true"
    PLT_MTIME=$(stat -c %Y "$PLT_PATH")
    if [ "$PLT_MTIME" -gt "$TASK_START" ]; then
        PLT_CREATED_DURING_TASK="true"
    fi
fi

# Check if Gretl is still running
APP_RUNNING=$(pgrep -f "gretl" > /dev/null && echo "true" || echo "false")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "png_exists": $PNG_EXISTS,
    "png_created_during_task": $PNG_CREATED_DURING_TASK,
    "png_size_bytes": $PNG_SIZE,
    "plt_exists": $PLT_EXISTS,
    "plt_created_during_task": $PLT_CREATED_DURING_TASK,
    "plt_path": "$PLT_PATH",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# If PLT exists, ensure it is readable by the verifier (verifier runs as different user sometimes)
if [ -f "$PLT_PATH" ]; then
    chmod 644 "$PLT_PATH"
fi

echo "Result exported to /tmp/task_result.json"