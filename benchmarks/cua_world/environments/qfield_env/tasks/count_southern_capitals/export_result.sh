#!/system/bin/sh
echo "=== Exporting task results ==="

# Define paths
OUTPUT_FILE="/sdcard/southern_hemisphere_capitals.txt"
RESULT_JSON="/sdcard/task_result.json"
TASK_START_FILE="/sdcard/task_start_time.txt"

# Get timestamps
TASK_END=$(date +%s)
TASK_START=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

# Check output file status
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(ls -l "$OUTPUT_FILE" | awk '{print $4}')
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "$TASK_END")
    
    # Check if created during task
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# Check if QField is currently running
if ps -A | grep -q "ch.opengis.qfield"; then
    APP_RUNNING="true"
else
    APP_RUNNING="false"
fi

# Capture final screenshot
screencap -p /sdcard/task_final.png

# Create JSON result
# Note: creating temp file then moving to avoid partial writes
TEMP_JSON="/sdcard/task_result_temp.json"
echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"output_exists\": $OUTPUT_EXISTS," >> "$TEMP_JSON"
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> "$TEMP_JSON"
echo "  \"output_size\": $OUTPUT_SIZE," >> "$TEMP_JSON"
echo "  \"app_running\": $APP_RUNNING" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

mv "$TEMP_JSON" "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"