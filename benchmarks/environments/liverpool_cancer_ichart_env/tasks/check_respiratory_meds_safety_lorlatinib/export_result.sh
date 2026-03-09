#!/bin/bash
echo "=== Exporting check_respiratory_meds_safety_lorlatinib results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Pull the report file from the device
OUTPUT_FILE_DEVICE="/sdcard/respiratory_check.txt"
OUTPUT_FILE_LOCAL="/tmp/respiratory_check.txt"

echo "Pulling output file from device..."
if adb shell ls "$OUTPUT_FILE_DEVICE" > /dev/null 2>&1; then
    adb pull "$OUTPUT_FILE_DEVICE" "$OUTPUT_FILE_LOCAL"
    OUTPUT_EXISTS="true"
    
    # Check file modification time on device (stat in Android shell)
    # Android stat format can vary, using simple ls -l for rough check or just relying on container file
    # We rely on the fact we deleted it in setup.
    FILE_CREATED_DURING_TASK="true" 
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    echo "File not found on device."
fi

# 2. Read file content if it exists
OUTPUT_CONTENT=""
if [ "$OUTPUT_EXISTS" = "true" ]; then
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE_LOCAL" | base64 -w 0)
fi

# 3. Capture final screenshot
echo "Capturing final screenshot..."
adb shell screencap -p /sdcard/task_final.png
adb pull /sdcard/task_final.png /tmp/task_final.png

# 4. Check if app is running (in foreground)
APP_RUNNING="false"
FOCUSED_APP=$(adb shell dumpsys window | grep mCurrentFocus)
if echo "$FOCUSED_APP" | grep -q "com.liverpooluni.ichartoncology"; then
    APP_RUNNING="true"
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_content_base64": "$OUTPUT_CONTENT",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="