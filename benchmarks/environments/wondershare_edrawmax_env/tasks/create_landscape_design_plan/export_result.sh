#!/bin/bash
echo "=== Exporting create_landscape_design_plan result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
EDDX_PATH="/home/ga/Documents/Johnson_Landscape_Plan.eddx"
PNG_PATH="/home/ga/Documents/Johnson_Landscape_Plan.png"

# Check EDDX File
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

# Check PNG File
if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING_TASK="true"
    else
        PNG_CREATED_DURING_TASK="false"
    fi
else
    PNG_EXISTS="false"
    PNG_SIZE="0"
    PNG_CREATED_DURING_TASK="false"
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "EdrawMax" > /dev/null && echo "true" || echo "false")

# Take final screenshot (backup for VLM if export failed)
take_screenshot /tmp/task_final.png

# Create JSON result
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
    "app_was_running": $APP_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png",
    "png_path": "$PNG_PATH",
    "eddx_path": "$EDDX_PATH"
}
EOF

# Move to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="