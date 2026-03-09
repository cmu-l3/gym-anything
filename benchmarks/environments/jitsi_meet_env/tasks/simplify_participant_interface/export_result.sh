#!/bin/bash
echo "=== Exporting Simplify Participant Interface results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONFIG_DIR="/home/ga/.jitsi-meet-cfg/web"
CONFIG_FILE="$CONFIG_DIR/config.js"
INTERFACE_FILE="$CONFIG_DIR/interface_config.js"

# Capture final state screenshot
take_screenshot /tmp/task_final.png

# Check if config file exists and was modified
FILE_MODIFIED="false"
CONFIG_CONTENT=""
TARGET_FILE=""

# Determine which file the agent modified (checking both config.js and interface_config.js)
if [ -f "$CONFIG_FILE" ]; then
    MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
        TARGET_FILE="config.js"
        # Read the file content, specifically looking for toolbarButtons
        CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    fi
fi

# If config.js wasn't modified, check interface_config.js
if [ "$FILE_MODIFIED" = "false" ] && [ -f "$INTERFACE_FILE" ]; then
    MTIME=$(stat -c %Y "$INTERFACE_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
        TARGET_FILE="interface_config.js"
        CONFIG_CONTENT=$(cat "$INTERFACE_FILE")
    fi
fi

# If neither modified, grab config.js content anyway for verification (maybe they modified it but timestamp is weird)
if [ -z "$CONFIG_CONTENT" ] && [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    TARGET_FILE="config.js"
fi

# Encode content to base64 to avoid JSON escaping issues
CONFIG_BASE64=""
if [ -n "$CONFIG_CONTENT" ]; then
    CONFIG_BASE64=$(echo "$CONFIG_CONTENT" | base64 -w 0)
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_modified": $FILE_MODIFIED,
    "target_file": "$TARGET_FILE",
    "config_content_b64": "$CONFIG_BASE64",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"