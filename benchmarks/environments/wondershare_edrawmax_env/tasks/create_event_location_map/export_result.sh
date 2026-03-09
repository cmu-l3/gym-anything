#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timings
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Verify Output Files
EDDX_PATH="/home/ga/Documents/event_map.eddx"
PNG_PATH="/home/ga/Documents/event_map.png"

# Check .eddx
EDDX_EXISTS="false"
EDDX_CREATED_DURING="false"
EDDX_SIZE="0"
if [ -f "$EDDX_PATH" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_PATH")
    EDDX_MTIME=$(stat -c %Y "$EDDX_PATH")
    if [ "$EDDX_MTIME" -gt "$TASK_START" ]; then
        EDDX_CREATED_DURING="true"
    fi
fi

# Check .png
PNG_EXISTS="false"
PNG_CREATED_DURING="false"
PNG_SIZE="0"
if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH")
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING="true"
    fi
fi

# 4. Check if App is still running
APP_RUNNING="false"
if is_edrawmax_running; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "eddx_exists": $EDDX_EXISTS,
    "eddx_created_during_task": $EDDX_CREATED_DURING,
    "eddx_size_bytes": $EDDX_SIZE,
    "png_exists": $PNG_EXISTS,
    "png_created_during_task": $PNG_CREATED_DURING,
    "png_size_bytes": $PNG_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="