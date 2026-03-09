#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Favorite Volumes Result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Configuration XML Content
CONFIG_CONTENT=""
CONFIG_PATH=""

# Check common config locations
if [ -f "/home/ga/.config/VeraCrypt/Configuration.xml" ]; then
    CONFIG_PATH="/home/ga/.config/VeraCrypt/Configuration.xml"
elif [ -f "/home/ga/.VeraCrypt/Configuration.xml" ]; then
    CONFIG_PATH="/home/ga/.VeraCrypt/Configuration.xml"
fi

if [ -n "$CONFIG_PATH" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_PATH")
fi

# 2. Capture Active Mounts (System level)
MOUNT_OUTPUT=$(mount | grep veracrypt || echo "")

# 3. Capture VeraCrypt Internal List
VC_LIST_OUTPUT=$(veracrypt --text --list --non-interactive 2>&1 || echo "")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Escape content for JSON inclusion
CONFIG_CONTENT_JSON=$(echo "$CONFIG_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
MOUNT_OUTPUT_JSON=$(echo "$MOUNT_OUTPUT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
VC_LIST_OUTPUT_JSON=$(echo "$VC_LIST_OUTPUT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_path": "$CONFIG_PATH",
    "config_content": $CONFIG_CONTENT_JSON,
    "system_mounts": $MOUNT_OUTPUT_JSON,
    "veracrypt_list": $VC_LIST_OUTPUT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="