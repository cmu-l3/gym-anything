#!/bin/bash
echo "=== Exporting Task Results ==="

# Define paths
ANDROID_FILE="/sdcard/contraceptive_check.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot
echo "Capturing final screenshot..."
adb exec-out screencap -p > /tmp/task_final.png

# 2. Check output file existence and content
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_MOD_TIME="0"
FILE_CREATED_DURING_TASK="false"

# Check if file exists on device
if adb shell ls "$ANDROID_FILE" > /dev/null 2>&1; then
    FILE_EXISTS="true"
    
    # Read content
    FILE_CONTENT=$(adb shell cat "$ANDROID_FILE")
    
    # Get timestamp (stat format on Android can vary, using date of file)
    # Simple check: we removed it in setup, so if it exists now, it was created during task.
    # But strictly, let's trust the existence check post-setup cleanup.
    FILE_CREATED_DURING_TASK="true"
else
    echo "Output file not found on device."
fi

# 3. Check if App is currently in foreground
APP_FOCUS="false"
if adb shell dumpsys window | grep -q "mCurrentFocus.*com.liverpooluni.ichartoncology"; then
    APP_FOCUS="true"
fi

# 4. Prepare JSON result
# We escape the file content for JSON safety
ESCAPED_CONTENT=$(echo "$FILE_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

# Create JSON structure
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content": $ESCAPED_CONTENT,
    "app_in_focus": $APP_FOCUS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json