#!/bin/bash
echo "=== Exporting create_warehouse_layout results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EDDX_PATH="/home/ga/Diagrams/warehouse_layout.eddx"
PNG_PATH="/home/ga/Diagrams/warehouse_layout.png"

# Check EDDX file
if [ -f "$EDDX_PATH" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c %s "$EDDX_PATH")
    EDDX_MTIME=$(stat -c %Y "$EDDX_PATH")
    if [ "$EDDX_MTIME" -gt "$TASK_START" ]; then
        EDDX_CREATED_DURING="true"
    else
        EDDX_CREATED_DURING="false"
    fi
else
    EDDX_EXISTS="false"
    EDDX_SIZE="0"
    EDDX_CREATED_DURING="false"
fi

# Check PNG file
if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH")
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

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_exists": $EDDX_EXISTS,
    "eddx_size": $EDDX_SIZE,
    "eddx_created_during_task": $EDDX_CREATED_DURING,
    "png_exists": $PNG_EXISTS,
    "png_size": $PNG_SIZE,
    "png_created_during_task": $PNG_CREATED_DURING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json