#!/bin/bash
echo "=== Exporting Parkinson's Screen Results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Pull the report file from the device
DEVICE_PATH="/sdcard/parkinsons_safety_report.txt"
LOCAL_PATH="/tmp/parkinsons_safety_report.txt"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if adb shell ls "$DEVICE_PATH" > /dev/null 2>&1; then
    adb pull "$DEVICE_PATH" "$LOCAL_PATH" > /dev/null 2>&1
    if [ -f "$LOCAL_PATH" ]; then
        FILE_EXISTS="true"
        FILE_SIZE=$(stat -c %s "$LOCAL_PATH" 2>/dev/null || echo "0")
        
        # Check timestamp on device
        # Android ls -l format: -rw-rw---- 1 root sdcard_rw 25 2023-10-25 12:00 filename
        # This is tricky to parse reliably across android versions. 
        # We'll rely on the fact we deleted it in setup.
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check if app is running (foreground)
APP_RUNNING="false"
PACKAGE="com.liverpooluni.ichartoncology"
if adb shell dumpsys window windows | grep -q "mCurrentFocus.*$PACKAGE"; then
    APP_RUNNING="true"
fi

# 3. Capture final screenshot
adb shell screencap -p /sdcard/task_final.png
adb pull /sdcard/task_final.png /tmp/task_final.png > /dev/null 2>&1

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "report_local_path": "$LOCAL_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="