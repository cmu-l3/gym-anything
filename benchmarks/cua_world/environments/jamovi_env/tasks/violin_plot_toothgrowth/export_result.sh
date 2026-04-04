#!/bin/bash
echo "=== Exporting task results ==="

# Source timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OMV_PATH="/home/ga/Documents/Jamovi/ToothGrowth_Violin.omv"
PNG_PATH="/home/ga/Documents/Jamovi/violin_distribution.png"

# Check OMV File
if [ -f "$OMV_PATH" ]; then
    OMV_EXISTS="true"
    OMV_SIZE=$(stat -c %s "$OMV_PATH" 2>/dev/null || echo "0")
    OMV_MTIME=$(stat -c %Y "$OMV_PATH" 2>/dev/null || echo "0")
    if [ "$OMV_MTIME" -gt "$TASK_START" ]; then
        OMV_CREATED_DURING="true"
    else
        OMV_CREATED_DURING="false"
    fi
else
    OMV_EXISTS="false"
    OMV_SIZE="0"
    OMV_CREATED_DURING="false"
fi

# Check PNG File
if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING="true"
    else
        PNG_CREATED_DURING="false"
    fi
else
    PNG_EXISTS="false"
    PNG_SIZE="0"
    PNG_CREATED_DURING="false"
fi

# Check if App is running
APP_RUNNING=$(pgrep -f "jamovi" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Prepare files for extraction by verifier
# We copy them to /tmp so they are easily accessible via copy_from_env
# regardless of user permissions in home dir
if [ "$OMV_EXISTS" = "true" ]; then
    cp "$OMV_PATH" /tmp/submission.omv
    chmod 644 /tmp/submission.omv
fi
if [ "$PNG_EXISTS" = "true" ]; then
    cp "$PNG_PATH" /tmp/submission.png
    chmod 644 /tmp/submission.png
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "omv_exists": $OMV_EXISTS,
    "omv_created_during_task": $OMV_CREATED_DURING,
    "omv_size": $OMV_SIZE,
    "omv_path": "/tmp/submission.omv",
    "png_exists": $PNG_EXISTS,
    "png_created_during_task": $PNG_CREATED_DURING,
    "png_size": $PNG_SIZE,
    "png_path": "/tmp/submission.png",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON saved."
cat /tmp/task_result.json
echo "=== Export complete ==="