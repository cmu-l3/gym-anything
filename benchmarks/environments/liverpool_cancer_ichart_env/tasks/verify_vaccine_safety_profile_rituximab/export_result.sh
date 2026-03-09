#!/system/bin/sh
echo "=== Exporting Task Result ==="

# 1. Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/sdcard/rituximab_vaccine_report.txt"

# 2. Check output file status
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    # Verify file was modified AFTER task started
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Take final screenshot
screencap -p /sdcard/task_final.png

# 4. Create JSON result
# Note: Android shell (sh) JSON creation is manual
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"file_exists\": $FILE_EXISTS," >> /sdcard/task_result.json
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"file_size_bytes\": $FILE_SIZE," >> /sdcard/task_result.json
echo "  \"final_screenshot_path\": \"/sdcard/task_final.png\"," >> /sdcard/task_result.json
echo "  \"report_file_path\": \"$OUTPUT_FILE\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

# 5. Set permissions so host can read
chmod 666 /sdcard/task_result.json 2>/dev/null
chmod 666 "$OUTPUT_FILE" 2>/dev/null
chmod 666 /sdcard/task_final.png 2>/dev/null

echo "Result exported to /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export Complete ==="