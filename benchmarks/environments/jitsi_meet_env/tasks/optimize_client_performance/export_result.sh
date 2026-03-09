#!/bin/bash
echo "=== Exporting optimize_client_performance result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/config.js"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check if file exists
FILE_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"
CONTENT_SNIPPET=""

if [ -f "$CONFIG_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$CONFIG_FILE")
    FILE_MTIME=$(stat -c %Y "$CONFIG_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi

    # Read the file content for verification (base64 encoded to avoid json issues)
    # We only care about the lines containing our keys to keep the payload small
    CONTENT_SNIPPET=$(grep -E "disableAudioLevels|enableNoisyMicDetection|startAudioOnly" "$CONFIG_FILE" | base64 -w 0)
else
    echo "ERROR: Config file not found at $CONFIG_FILE"
fi

# 2. Take final screenshot (VLM might check if editor is open or if they browsed to the page)
take_screenshot /tmp/task_final.png

# 3. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_modified_during_task": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "config_content_base64": "$CONTENT_SNIPPET",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"