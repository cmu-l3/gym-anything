#!/bin/bash
set -e

echo "=== Exporting enforce_global_lobby result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/config.js"
RESULT_JSON="/tmp/task_result.json"

# 1. Read the config file content
if [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE" | base64 -w 0)
    CONFIG_EXISTS="true"
else
    CONFIG_CONTENT=""
    CONFIG_EXISTS="false"
fi

# 2. Check Container Restart Time
# We need to see if the container was restarted AFTER the task began.
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Get container start time (ISO 8601)
# Note: "jitsi-web" is the container name defined in docker-compose, might be prefixed with directory name
# We try to find the web container ID first.
WEB_CONTAINER_ID=$(docker ps -q --filter "name=web" | head -n 1)

if [ -n "$WEB_CONTAINER_ID" ]; then
    CONTAINER_START_TIMESTAMP=$(docker inspect --format='{{.State.StartedAt}}' "$WEB_CONTAINER_ID")
    CONTAINER_RUNNING="true"
else
    CONTAINER_START_TIMESTAMP=""
    CONTAINER_RUNNING="false"
fi

# 3. Check if meeting is active in browser (simple URL check)
# We can check if the current URL is not the homepage
CURRENT_URL_FILE="/tmp/firefox_url.txt"
# This requires a way to get the URL, which xdotool/scrot can't do directly without OCR or extension.
# We will rely on VLM for meeting verification, but we can check if Firefox is running.
FIREFOX_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Create JSON result
# We use python to safely generate JSON
python3 -c "
import json
import os

data = {
    'config_exists': '$CONFIG_EXISTS' == 'true',
    'config_content_b64': '$CONFIG_CONTENT',
    'task_start_ts': $TASK_START_TIME,
    'container_start_iso': '$CONTAINER_START_TIMESTAMP',
    'container_running': '$CONTAINER_RUNNING' == 'true',
    'firefox_running': '$FIREFOX_RUNNING' == 'true',
    'screenshot_path': '/tmp/task_final.png'
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(data, f)
"

# Set permissions so we can copy it out
chmod 666 "$RESULT_JSON"
chmod 666 /tmp/task_final.png

echo "Export complete. Result saved to $RESULT_JSON"