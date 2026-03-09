#!/bin/bash
set -e
echo "=== Exporting task results: create_customer_journey_map ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

EDDX_FILE="/home/ga/Diagrams/customer_journey_map.eddx"
PNG_FILE="/home/ga/Diagrams/customer_journey_map.png"

# Check EDDX file
EDDX_EXISTS="false"
EDDX_SIZE="0"
EDDX_CREATED_DURING_TASK="false"

if [ -f "$EDDX_FILE" ]; then
    EDDX_EXISTS="true"
    EDDX_SIZE=$(stat -c%s "$EDDX_FILE" 2>/dev/null || echo "0")
    EDDX_MTIME=$(stat -c%Y "$EDDX_FILE" 2>/dev/null || echo "0")
    if [ "$EDDX_MTIME" -gt "$TASK_START" ]; then
        EDDX_CREATED_DURING_TASK="true"
    fi
fi

# Check PNG file
PNG_EXISTS="false"
PNG_SIZE="0"
PNG_WIDTH="0"
PNG_HEIGHT="0"
PNG_CREATED_DURING_TASK="false"

if [ -f "$PNG_FILE" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c%s "$PNG_FILE" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c%Y "$PNG_FILE" 2>/dev/null || echo "0")
    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING_TASK="true"
    fi
    
    # Get dimensions if imagemagick is available
    if command -v identify >/dev/null 2>&1; then
        DIMS=$(identify -format "%wx%h" "$PNG_FILE" 2>/dev/null || echo "0x0")
        PNG_WIDTH=$(echo "$DIMS" | cut -d'x' -f1)
        PNG_HEIGHT=$(echo "$DIMS" | cut -d'x' -f2)
    fi
fi

# Take final screenshot of the desktop
take_screenshot /tmp/task_final_state.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "eddx_exists": $EDDX_EXISTS,
    "eddx_size_bytes": $EDDX_SIZE,
    "eddx_created_during_task": $EDDX_CREATED_DURING_TASK,
    "png_exists": $PNG_EXISTS,
    "png_size_bytes": $PNG_SIZE,
    "png_width": $PNG_WIDTH,
    "png_height": $PNG_HEIGHT,
    "png_created_during_task": $PNG_CREATED_DURING_TASK,
    "final_screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to standard location with lenient permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="