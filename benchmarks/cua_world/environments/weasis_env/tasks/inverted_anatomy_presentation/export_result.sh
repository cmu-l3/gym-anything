#!/bin/bash
echo "=== Exporting inverted_anatomy_presentation task result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

IMAGE_PATH="/home/ga/DICOM/exports/lecture_slide.jpg"
TEXT_PATH="/home/ga/DICOM/exports/measurement.txt"

IMAGE_EXISTS="false"
IMAGE_CREATED_DURING_TASK="false"
IMAGE_SIZE=0

TEXT_EXISTS="false"
TEXT_CREATED_DURING_TASK="false"
TEXT_CONTENT=""

# Evaluate image export
if [ -f "$IMAGE_PATH" ]; then
    IMAGE_EXISTS="true"
    IMAGE_MTIME=$(stat -c %Y "$IMAGE_PATH" 2>/dev/null || echo "0")
    if [ "$IMAGE_MTIME" -gt "$TASK_START" ]; then
        IMAGE_CREATED_DURING_TASK="true"
    fi
    IMAGE_SIZE=$(stat -c %s "$IMAGE_PATH" 2>/dev/null || echo "0")
fi

# Evaluate text measurement report
if [ -f "$TEXT_PATH" ]; then
    TEXT_EXISTS="true"
    TEXT_MTIME=$(stat -c %Y "$TEXT_PATH" 2>/dev/null || echo "0")
    if [ "$TEXT_MTIME" -gt "$TASK_START" ]; then
        TEXT_CREATED_DURING_TASK="true"
    fi
    # Extract up to 100 characters from the text file for parsing in verifier
    TEXT_CONTENT=$(head -c 100 "$TEXT_PATH" | tr -d '\n' | tr -d '\r' | sed 's/"/\\"/g')
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "image_exists": $IMAGE_EXISTS,
    "image_created_during_task": $IMAGE_CREATED_DURING_TASK,
    "image_size_bytes": $IMAGE_SIZE,
    "text_exists": $TEXT_EXISTS,
    "text_created_during_task": $TEXT_CREATED_DURING_TASK,
    "text_content": "$TEXT_CONTENT",
    "app_was_running": $APP_RUNNING,
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