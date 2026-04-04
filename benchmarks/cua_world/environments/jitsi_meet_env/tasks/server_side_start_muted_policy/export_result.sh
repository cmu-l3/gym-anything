#!/bin/bash
echo "=== Exporting server_side_start_muted_policy result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/config.js"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_config_mtime.txt 2>/dev/null || echo "0")

# 1. Check File Modification
FILE_MODIFIED="false"
CURRENT_MTIME="0"
if [ -f "$CONFIG_FILE" ]; then
    CURRENT_MTIME=$(stat -c %Y "$CONFIG_FILE")
    if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 2. Read Configuration Values
# We use grep to extract the lines. This is a basic check; robust parsing happens in verifier.py
AUDIO_CONFIG_LINE=$(grep "startWithAudioMuted" "$CONFIG_FILE" | head -n 1 || echo "")
VIDEO_CONFIG_LINE=$(grep "startWithVideoMuted" "$CONFIG_FILE" | head -n 1 || echo "")

# 3. Check Browser State (Visual)
# Take final screenshot for VLM to check for muted icons
take_screenshot /tmp/task_final.png

# 4. Check if Jitsi is running/accessible
JITSI_RUNNING="false"
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200"; then
    JITSI_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_modified": $FILE_MODIFIED,
    "config_file_exists": true,
    "audio_config_line": "$(echo "$AUDIO_CONFIG_LINE" | sed 's/"/\\"/g')",
    "video_config_line": "$(echo "$VIDEO_CONFIG_LINE" | sed 's/"/\\"/g')",
    "jitsi_running": $JITSI_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="