#!/system/bin/sh
# Export script for cable_reel_capacity task
echo "=== Exporting Task Results ==="

TASK_START=$(cat /sdcard/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/sdcard/reel_capacity.txt"
SCREENSHOT_FILE="/sdcard/reel_capacity_evidence.png"

# 1. Check Output File
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE")
    
    # Check timestamp (Android ls -l format varies, using basic check)
    # Ideally we'd use stat, but it's not always available on minimal Android shells.
    # We will trust the existence check + verifier logic for this environment.
    # If possible, we check if file is newer than start file.
    if [ "$OUTPUT_FILE" -nt "/sdcard/task_start_time.txt" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Screenshot
SCREENSHOT_EXISTS="false"
if [ -f "$SCREENSHOT_FILE" ]; then
    SCREENSHOT_EXISTS="true"
fi

# 3. Check App State
APP_RUNNING="false"
if dumpsys window | grep -q "mCurrentFocus.*com.hsn.electricalcalculations"; then
    APP_RUNNING="true"
fi

# 4. Create JSON Result
# We construct JSON manually as 'jq' might not be installed on Android
echo "{" > /sdcard/task_result.json
echo "  \"task_start\": $TASK_START," >> /sdcard/task_result.json
echo "  \"task_end\": $TASK_END," >> /sdcard/task_result.json
echo "  \"output_exists\": $OUTPUT_EXISTS," >> /sdcard/task_result.json
echo "  \"output_content\": \"$OUTPUT_CONTENT\"," >> /sdcard/task_result.json
echo "  \"file_created_during_task\": $FILE_CREATED_DURING_TASK," >> /sdcard/task_result.json
echo "  \"screenshot_exists\": $SCREENSHOT_EXISTS," >> /sdcard/task_result.json
echo "  \"app_running\": $APP_RUNNING" >> /sdcard/task_result.json
echo "}" >> /sdcard/task_result.json

# 5. Capture Final State for VLM
screencap -p /sdcard/task_final.png

echo "Export complete. Result saved to /sdcard/task_result.json"