#!/bin/bash
set -e
echo "=== Exporting Task Results ==="

# Define variables
OUTPUT_FILE_DEVICE="/sdcard/vandetanib_depression_plan.txt"
RESULT_JSON="/tmp/task_result.json"
TASK_START_FILE="/tmp/task_start_time.txt"

# 1. Capture final screenshot
adb shell screencap -p /sdcard/task_final.png
adb pull /sdcard/task_final.png /tmp/task_final.png >/dev/null 2>&1 || echo "Screenshot failed"

# 2. Check if output file exists on device
if adb shell "[ -f $OUTPUT_FILE_DEVICE ]"; then
    FILE_EXISTS="true"
    
    # Get file content
    adb pull "$OUTPUT_FILE_DEVICE" /tmp/vandetanib_plan.txt >/dev/null 2>&1
    
    # Get file modification time from device (stat format depends on Android version, using ls -l as fallback or stat)
    # Android's stat -c %Y works on modern versions.
    FILE_MTIME=$(adb shell stat -c %Y "$OUTPUT_FILE_DEVICE" 2>/dev/null || echo "0")
else
    FILE_EXISTS="false"
    FILE_MTIME="0"
    echo "" > /tmp/vandetanib_plan.txt
fi

# 3. Get Task Start Time
if [ -f "$TASK_START_FILE" ]; then
    TASK_START=$(cat "$TASK_START_FILE")
else
    TASK_START="0"
fi

# 4. Check if app is still running (optional but good context)
APP_RUNNING=$(adb shell pidof com.liverpooluni.ichartoncology >/dev/null && echo "true" || echo "false")

# 5. Create Result JSON
# We include the raw content of the text file in the JSON for easier parsing in Python
FILE_CONTENT_JSON=$(cat /tmp/vandetanib_plan.txt | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))')

cat > "$RESULT_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "file_mtime": $FILE_MTIME,
    "file_exists": $FILE_EXISTS,
    "app_running_at_end": $APP_RUNNING,
    "file_content": $FILE_CONTENT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Clean up temp text file
rm -f /tmp/vandetanib_plan.txt

echo "Export complete. Result saved to $RESULT_JSON"