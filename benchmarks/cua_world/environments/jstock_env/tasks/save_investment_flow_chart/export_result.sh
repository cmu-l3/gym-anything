#!/bin/bash
echo "=== Exporting save_investment_flow_chart result ==="

# Define paths
OUTPUT_PATH="/home/ga/Documents/investment_flow.png"
TASK_START_FILE="/tmp/task_start_time.txt"
RESULT_JSON="/tmp/task_result.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

# Initialize result variables
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
IS_PNG="false"
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"

# Check output file
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")

    # Anti-gaming: Check if file was modified after task start
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check for valid PNG magic bytes
    if file "$OUTPUT_PATH" | grep -q "PNG image data"; then
        IS_PNG="true"
        
        # Extract dimensions using file command or identify
        # Example output: "PNG image data, 800 x 600, 8-bit/color..."
        DIMENSIONS=$(file "$OUTPUT_PATH" | grep -oE '[0-9]+ x [0-9]+' | head -1)
        if [ -n "$DIMENSIONS" ]; then
            IMAGE_WIDTH=$(echo "$DIMENSIONS" | awk '{print $1}')
            IMAGE_HEIGHT=$(echo "$DIMENSIONS" | awk '{print $3}')
        fi
    fi
fi

# Check if application is still running
APP_RUNNING=$(pgrep -f "jstock.jar" > /dev/null && echo "true" || echo "false")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_path": "$OUTPUT_PATH",
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "is_png": $IS_PNG,
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "app_was_running": $APP_RUNNING
}
EOF

# Move to final location safely
rm -f "$RESULT_JSON" 2>/dev/null || sudo rm -f "$RESULT_JSON" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_JSON" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON" 2>/dev/null || sudo chmod 666 "$RESULT_JSON" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="