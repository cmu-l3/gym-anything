#!/bin/bash
echo "=== Exporting Measure Galaxy Physical Diameter Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

OUTPUT_DIR="/home/ga/AstroImages/uit_galaxy"
JSON_FILE="$OUTPUT_DIR/galaxy_diameter_report.json"
IMAGE_FILE="$OUTPUT_DIR/measurement_overlay.jpg"

# 1. Check JSON report
JSON_EXISTS="false"
JSON_CREATED_DURING_TASK="false"
JSON_CONTENT="{}"

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -ge "$TASK_START" ]; then
        JSON_CREATED_DURING_TASK="true"
    fi
    # Read the JSON safely, escaping quotes if necessary
    # We will embed it as a string to avoid nested JSON parsing issues in bash
    JSON_CONTENT=$(cat "$JSON_FILE" | tr -d '\n' | sed 's/"/\\"/g')
fi

# 2. Check annotated image
IMAGE_EXISTS="false"
IMAGE_CREATED_DURING_TASK="false"
IMAGE_SIZE="0"

if [ -f "$IMAGE_FILE" ]; then
    IMAGE_EXISTS="true"
    IMAGE_MTIME=$(stat -c %Y "$IMAGE_FILE" 2>/dev/null || echo "0")
    if [ "$IMAGE_MTIME" -ge "$TASK_START" ]; then
        IMAGE_CREATED_DURING_TASK="true"
    fi
    IMAGE_SIZE=$(stat -c %s "$IMAGE_FILE" 2>/dev/null || echo "0")
fi

# Check if AIJ is running
AIJ_RUNNING="false"
if is_aij_running; then
    AIJ_RUNNING="true"
fi

# Create export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "aij_was_running": $AIJ_RUNNING,
    "json_exists": $JSON_EXISTS,
    "json_created_during_task": $JSON_CREATED_DURING_TASK,
    "json_content_string": "$JSON_CONTENT",
    "image_exists": $IMAGE_EXISTS,
    "image_created_during_task": $IMAGE_CREATED_DURING_TASK,
    "image_size_bytes": $IMAGE_SIZE,
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

echo "=== Export Complete ==="