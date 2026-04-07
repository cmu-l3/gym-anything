#!/bin/bash
echo "=== Exporting generate_event_map_python results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

IMAGE_PATH="/home/ga/noto_event_map.png"
SCRIPT_PATH="/home/ga/plot_event_map.py"

# 1. Check Image Output
IMG_EXISTS="false"
IMG_SIZE=0
IMG_CREATED_DURING_TASK="false"

if [ -f "$IMAGE_PATH" ]; then
    IMG_EXISTS="true"
    IMG_SIZE=$(stat -c %s "$IMAGE_PATH" 2>/dev/null || echo "0")
    IMG_MTIME=$(stat -c %Y "$IMAGE_PATH" 2>/dev/null || echo "0")
    if [ "$IMG_MTIME" -ge "$TASK_START" ]; then
        IMG_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Script Output
SCRIPT_EXISTS="false"
SCRIPT_CREATED_DURING_TASK="false"
SCRIPT_CONTENT_B64=""

if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -ge "$TASK_START" ]; then
        SCRIPT_CREATED_DURING_TASK="true"
    fi
    # Base64 encode the script so we can safely pass it in JSON
    SCRIPT_CONTENT_B64=$(base64 -w 0 "$SCRIPT_PATH" 2>/dev/null || echo "")
fi

# 3. Check if matplotlib is now installed
MATPLOTLIB_INSTALLED="false"
if su - ga -c "python3 -c 'import matplotlib'" 2>/dev/null; then
    MATPLOTLIB_INSTALLED="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "image_exists": $IMG_EXISTS,
    "image_size_bytes": $IMG_SIZE,
    "image_created_during_task": $IMG_CREATED_DURING_TASK,
    "script_exists": $SCRIPT_EXISTS,
    "script_created_during_task": $SCRIPT_CREATED_DURING_TASK,
    "script_content_b64": "$SCRIPT_CONTENT_B64",
    "matplotlib_installed": $MATPLOTLIB_INSTALLED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="