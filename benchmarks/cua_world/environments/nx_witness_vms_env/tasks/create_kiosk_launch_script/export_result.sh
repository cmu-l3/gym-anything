#!/bin/bash
echo "=== Exporting create_kiosk_launch_script result ==="

TARGET_FILE="/home/ga/Desktop/launch_kiosk.sh"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize result variables
FILE_EXISTS="false"
IS_EXECUTABLE="false"
FILE_CONTENT=""
FILE_MTIME="0"

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check executable permission
    if [ -x "$TARGET_FILE" ]; then
        IS_EXECUTABLE="true"
    fi
    
    # Read content (base64 encode to safely transport via JSON)
    FILE_CONTENT=$(cat "$TARGET_FILE" | base64 -w 0)
    
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "is_executable": $IS_EXECUTABLE,
    "file_content_b64": "$FILE_CONTENT",
    "file_mtime": $FILE_MTIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"