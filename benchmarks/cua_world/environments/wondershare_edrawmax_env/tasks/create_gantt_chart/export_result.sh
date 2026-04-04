#!/bin/bash
set -e
echo "=== Exporting create_gantt_chart results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check EDDX File
EDDX_PATH="/home/ga/migration_gantt.eddx"
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
    EDDX_MTIME="0"
    EDDX_CREATED_DURING_TASK="false"
fi

# 2. Check PNG Export
PNG_PATH="/home/ga/migration_gantt.png"
if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")
    
    # Get image dimensions if ImageMagick is available
    PNG_DIMS=$(identify -format "%wx%h" "$PNG_PATH" 2>/dev/null || echo "0x0")
    
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING_TASK="true"
    else
        PNG_CREATED_DURING_TASK="false"
    fi
else
    PNG_EXISTS="false"
    PNG_SIZE="0"
    PNG_MTIME="0"
    PNG_DIMS="0x0"
    PNG_CREATED_DURING_TASK="false"
fi

# 3. Check App State
APP_RUNNING=$(pgrep -f "EdrawMax" > /dev/null && echo "true" || echo "false")

# 4. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "eddx_file": {
        "exists": $EDDX_EXISTS,
        "path": "$EDDX_PATH",
        "size_bytes": $EDDX_SIZE,
        "created_during_task": $EDDX_CREATED_DURING_TASK
    },
    "png_file": {
        "exists": $PNG_EXISTS,
        "path": "$PNG_PATH",
        "size_bytes": $PNG_SIZE,
        "dimensions": "$PNG_DIMS",
        "created_during_task": $PNG_CREATED_DURING_TASK
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="