#!/system/bin/sh
echo "=== Exporting CML Polypharmacy Consultation Result ==="

# Define paths
OUTPUT_FILE="/sdcard/Download/cml_drug_safety_report.txt"
JSON_RESULT="/sdcard/task_result.json"
START_TIME_FILE="/sdcard/task_start_time.txt"

# Get task start time
TASK_START=0
if [ -f "$START_TIME_FILE" ]; then
    TASK_START=$(cat "$START_TIME_FILE")
fi
TASK_END=$(date +%s)

# Take a final screenshot
screencap -p /sdcard/final_screenshot.png

# Initialize variables
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MTIME=0
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0

# Check the output file
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(ls -l "$OUTPUT_FILE" | awk '{print $4}')
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")

    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Read content with JSON-safe escaping (truncate to 4096 bytes for large reports)
    FILE_CONTENT=$(head -c 4096 "$OUTPUT_FILE" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
fi

# Write result JSON
echo "{"                                                                > "$JSON_RESULT"
echo "  \"task_start\": $TASK_START,"                                 >> "$JSON_RESULT"
echo "  \"task_end\": $TASK_END,"                                     >> "$JSON_RESULT"
echo "  \"file_exists\": $FILE_EXISTS,"                               >> "$JSON_RESULT"
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK,"    >> "$JSON_RESULT"
echo "  \"file_mtime\": $FILE_MTIME,"                                >> "$JSON_RESULT"
echo "  \"file_size\": $FILE_SIZE,"                                   >> "$JSON_RESULT"
echo "  \"file_content\": \"$FILE_CONTENT\""                          >> "$JSON_RESULT"
echo "}"                                                              >> "$JSON_RESULT"

echo "Export complete. Result saved to $JSON_RESULT"
cat "$JSON_RESULT"
