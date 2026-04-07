#!/bin/bash
echo "=== Exporting multi_window_trauma_layout task result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/DICOM/exports"

# Take final system screenshot
take_screenshot /tmp/task_final.png

# Check for text file
TEXT_FILE="$EXPORT_DIR/window_levels.txt"
TEXT_EXISTS="false"
TEXT_CREATED_DURING_TASK="false"
TEXT_CONTENT=""

if [ -f "$TEXT_FILE" ]; then
    TEXT_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$TEXT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        TEXT_CREATED_DURING_TASK="true"
    fi
    TEXT_CONTENT=$(cat "$TEXT_FILE" | head -n 20) # Capture up to 20 lines
fi

# Check for image file
IMAGE_FILE="$EXPORT_DIR/trauma_layout.png"
IMAGE_EXISTS="false"
IMAGE_CREATED_DURING_TASK="false"

if [ -f "$IMAGE_FILE" ]; then
    IMAGE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$IMAGE_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IMAGE_CREATED_DURING_TASK="true"
    fi
fi

# Escape text content for JSON
TEXT_CONTENT_ESCAPED=$(echo "$TEXT_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "text_file_exists": $TEXT_EXISTS,
    "text_file_created_during_task": $TEXT_CREATED_DURING_TASK,
    "text_content": $TEXT_CONTENT_ESCAPED,
    "image_file_exists": $IMAGE_EXISTS,
    "image_file_created_during_task": $IMAGE_CREATED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
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