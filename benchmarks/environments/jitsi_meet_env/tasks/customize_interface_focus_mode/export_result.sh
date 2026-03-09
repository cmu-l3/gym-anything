#!/bin/bash
set -e
echo "=== Exporting Jitsi Focus Mode results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Check for Config File
CONFIG_PATH="/home/ga/.jitsi-meet-cfg/web/custom-interface_config.js"
CONFIG_EXISTS="false"
CONFIG_CONTENT=""
CONFIG_MTIME="0"

if [ -f "$CONFIG_PATH" ]; then
    CONFIG_EXISTS="true"
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_PATH")
    # Read content safely, escaping quotes for JSON
    CONFIG_CONTENT=$(cat "$CONFIG_PATH" | base64 -w 0)
fi

# 3. Check for User Screenshots
TOOLBAR_SCREENSHOT_EXISTS="false"
if [ -f "/home/ga/Documents/focus_mode_toolbar.png" ]; then
    TOOLBAR_SCREENSHOT_EXISTS="true"
fi

BRANDING_SCREENSHOT_EXISTS="false"
if [ -f "/home/ga/Documents/focus_mode_branding.png" ]; then
    BRANDING_SCREENSHOT_EXISTS="true"
fi

# 4. Check if Jitsi Web Container is running
CONTAINER_RUNNING=$(docker ps --filter "name=jitsi-web" --format "{{.Status}}" | grep -q "Up" && echo "true" || echo "false")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_exists": $CONFIG_EXISTS,
    "config_mtime": $CONFIG_MTIME,
    "config_content_base64": "$CONFIG_CONTENT",
    "toolbar_screenshot_exists": $TOOLBAR_SCREENSHOT_EXISTS,
    "branding_screenshot_exists": $BRANDING_SCREENSHOT_EXISTS,
    "container_running": $CONTAINER_RUNNING,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"