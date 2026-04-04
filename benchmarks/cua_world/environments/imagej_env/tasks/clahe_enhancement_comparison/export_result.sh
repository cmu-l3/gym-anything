#!/bin/bash
# Export script for CLAHE Enhancement Comparison task

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting CLAHE Comparison Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Path to expected output
OUTPUT_FILE="/home/ga/ImageJ_Data/results/clahe_comparison.png"
TIMESTAMP_FILE="/tmp/task_start_timestamp"

# Initialize variables
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
IMAGE_WIDTH=0
IMAGE_HEIGHT=0

# Check file existence and timestamp
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    # Check if created after task start
    if [ -f "$TIMESTAMP_FILE" ]; then
        START_TIME=$(cat "$TIMESTAMP_FILE")
        if [ "$FILE_MTIME" -ge "$START_TIME" ]; then
            FILE_CREATED_DURING_TASK="true"
        fi
    else
        # Fallback if timestamp missing (shouldn't happen)
        FILE_CREATED_DURING_TASK="true"
    fi

    # Get image dimensions using Python
    DIMENSIONS=$(python3 -c "
try:
    from PIL import Image
    img = Image.open('$OUTPUT_FILE')
    print(f'{img.width} {img.height}')
except:
    print('0 0')
")
    IMAGE_WIDTH=$(echo $DIMENSIONS | awk '{print $1}')
    IMAGE_HEIGHT=$(echo $DIMENSIONS | awk '{print $2}')
fi

# Check if Fiji is still running
FIJI_RUNNING=$(pgrep -f "ImageJ|Fiji" > /dev/null && echo "true" || echo "false")

# Create JSON result
# Using a temp file to avoid permission issues during write
TEMP_JSON=$(mktemp /tmp/clahe_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "created_during_task": $FILE_CREATED_DURING_TASK,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "fiji_was_running": $FIJI_RUNNING,
    "output_path": "$OUTPUT_FILE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location with lenient permissions
mv "$TEMP_JSON" /tmp/clahe_task_result.json
chmod 666 /tmp/clahe_task_result.json

echo "Result exported to /tmp/clahe_task_result.json"
cat /tmp/clahe_task_result.json
echo "=== Export Complete ==="