#!/bin/bash
echo "=== Exporting MPR Thick Slab task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot BEFORE checking files
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/DICOM/exports"

# Verify PNG Screenshot
SCREENSHOT_PATH="$EXPORT_DIR/mip_slab_view.png"
PNG_EXISTS="false"
PNG_CREATED_DURING_TASK="false"
PNG_SIZE=0

if [ -f "$SCREENSHOT_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
    
    if [ "$PNG_MTIME" -ge "$TASK_START" ]; then
        PNG_CREATED_DURING_TASK="true"
    fi
fi

# Verify TXT Settings File
TXT_PATH="$EXPORT_DIR/mpr_settings.txt"
TXT_EXISTS="false"
TXT_CREATED_DURING_TASK="false"
TXT_CONTENT=""

if [ -f "$TXT_PATH" ]; then
    TXT_EXISTS="true"
    TXT_MTIME=$(stat -c %Y "$TXT_PATH" 2>/dev/null || echo "0")
    TXT_CONTENT=$(head -n 5 "$TXT_PATH" | tr '\n' ' ' | sed 's/"/\\"/g' 2>/dev/null)
    
    if [ "$TXT_MTIME" -ge "$TASK_START" ]; then
        TXT_CREATED_DURING_TASK="true"
    fi
fi

# Application state
APP_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "app_running": $APP_RUNNING,
    "png_exists": $PNG_EXISTS,
    "png_created_during_task": $PNG_CREATED_DURING_TASK,
    "png_size_bytes": $PNG_SIZE,
    "txt_exists": $TXT_EXISTS,
    "txt_created_during_task": $TXT_CREATED_DURING_TASK,
    "txt_content": "$TXT_CONTENT",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="