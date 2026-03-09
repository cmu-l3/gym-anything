#!/system/bin/sh
echo "=== Exporting Voltage Drop Branch Circuit Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/sdcard/voltage_drop_result.txt"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_CONTENT=""
FILE_SIZE="0"

# Check output file
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content (escape quotes for JSON)
    FILE_CONTENT=$(cat "$OUTPUT_PATH" | sed 's/"/\\"/g' | tr '\n' '\\n')
fi

# Check if app is running in foreground
APP_RUNNING="false"
if dumpsys window windows | grep -q "mCurrentFocus.*com.hsn.electricalcalculations"; then
    APP_RUNNING="true"
fi

# Take final screenshot
screencap -p /sdcard/task_final.png

# Create result JSON
# Note: creating temp file in /sdcard since /tmp might not exist on Android
TEMP_JSON="/sdcard/temp_result.json"
echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"output_exists\": $OUTPUT_EXISTS," >> "$TEMP_JSON"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> "$TEMP_JSON"
echo "  \"file_content\": \"$FILE_CONTENT\"," >> "$TEMP_JSON"
echo "  \"app_running\": $APP_RUNNING," >> "$TEMP_JSON"
echo "  \"final_screenshot_path\": \"/sdcard/task_final.png\"" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# Move to final location
mv "$TEMP_JSON" /sdcard/task_result.json
chmod 666 /sdcard/task_result.json

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="