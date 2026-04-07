#!/bin/bash
echo "=== Exporting measure_orthopedic_cobb_angle task result ==="

source /workspace/scripts/task_utils.sh

# Take final snapshot of desktop environment
take_screenshot /tmp/task_end.png

# Paths expected by the task
IMAGE_PATH="/home/ga/DICOM/exports/cobb_angle_result.png"
TEXT_PATH="/home/ga/DICOM/exports/measurement_type.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check Image
IMAGE_EXISTS="false"
IMAGE_SIZE=0
IMAGE_CREATED_DURING_TASK="false"

if [ -f "$IMAGE_PATH" ]; then
    IMAGE_EXISTS="true"
    IMAGE_SIZE=$(stat -c %s "$IMAGE_PATH" 2>/dev/null || echo "0")
    IMAGE_MTIME=$(stat -c %Y "$IMAGE_PATH" 2>/dev/null || echo "0")
    
    if [ "$IMAGE_MTIME" -ge "$TASK_START" ]; then
        IMAGE_CREATED_DURING_TASK="true"
    fi
fi

# Check Text File
TEXT_EXISTS="false"
TEXT_CONTENT=""
TEXT_CREATED_DURING_TASK="false"

if [ -f "$TEXT_PATH" ]; then
    TEXT_EXISTS="true"
    TEXT_MTIME=$(stat -c %Y "$TEXT_PATH" 2>/dev/null || echo "0")
    
    if [ "$TEXT_MTIME" -ge "$TASK_START" ]; then
        TEXT_CREATED_DURING_TASK="true"
    fi
    
    # Read the first 100 characters to prevent huge payload
    TEXT_CONTENT=$(head -c 100 "$TEXT_PATH" | tr -d '\n' | tr -d '\r' | sed 's/"/\\"/g' 2>/dev/null || echo "")
fi

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "image_exists": $IMAGE_EXISTS,
    "image_size_bytes": $IMAGE_SIZE,
    "image_created_during_task": $IMAGE_CREATED_DURING_TASK,
    "text_exists": $TEXT_EXISTS,
    "text_created_during_task": $TEXT_CREATED_DURING_TASK,
    "text_content": "$TEXT_CONTENT",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy to /tmp for verifier reading
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="