#!/system/bin/sh
# Export script for lookup_past_flight_status task

echo "=== Exporting results ==="

# 1. Capture final state for debugging/verification
screencap -p /sdcard/final_screenshot.png

# 2. Dump UI hierarchy to check for text (Flight number, Date)
uiautomator dump /sdcard/ui_dump.xml > /dev/null 2>&1

# 3. Check for the agent-generated screenshot
OUTPUT_PATH="/sdcard/past_flight_result.png"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(ls -l "$OUTPUT_PATH" | awk '{print $5}')
    
    # Check modification time (simple check since Android `stat` varies)
    # We'll rely on the fact that we deleted it in setup
    FILE_CREATED_DURING_TASK="true"
fi

# 4. Create JSON result
# Note: creating JSON in shell is fragile, doing best effort
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"output_exists\": $OUTPUT_EXISTS," >> /sdcard/task_result.json
echo "  \"output_size\": $OUTPUT_SIZE," >> /sdcard/task_result.json
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"final_screenshot_path\": \"/sdcard/final_screenshot.png\"" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

echo "Export complete. Result:"
cat /sdcard/task_result.json