#!/system/bin/sh
echo "=== Exporting Air Core Inductor Design Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
RESULT_FILE="/sdcard/inductor_result.txt"

# Check if result file exists and get stats
if [ -f "$RESULT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$RESULT_FILE")
    OUTPUT_MTIME=$(stat -c %Y "$RESULT_FILE")
    
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

# Capture final screenshot
screencap -p /sdcard/task_final.png

# Create JSON result
# Note: Android shell might have limited JSON tools, so we construct manually
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"output_exists\": $OUTPUT_EXISTS," >> /sdcard/task_result.json
echo "  \"output_size\": $OUTPUT_SIZE," >> /sdcard/task_result.json
echo "  \"created_during_task\": $CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"screenshot_path\": \"/sdcard/task_final.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Result JSON created at /sdcard/task_result.json"
cat /sdcard/task_result.json
echo "=== Export complete ==="