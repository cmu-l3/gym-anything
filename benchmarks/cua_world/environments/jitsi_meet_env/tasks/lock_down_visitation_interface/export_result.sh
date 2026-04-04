#!/bin/bash
set -e
echo "=== Exporting Lock Down Visitation Interface result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot (Evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Check Configuration File
CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/interface_config.js"
CONFIG_EXISTS="false"
CONFIG_MODIFIED="false"
CONFIG_MTIME=0

if [ -f "$CONFIG_FILE" ]; then
    CONFIG_EXISTS="true"
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_FILE")
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED="true"
    fi
    # Copy config to temp for verifier to read safely
    cp "$CONFIG_FILE" /tmp/interface_config_submitted.js
    chmod 644 /tmp/interface_config_submitted.js
fi

# 3. Check Service Restart (Container Uptime)
# We look for the jitsi web container
WEB_CONTAINER_ID=$(docker ps -q --filter "name=jitsi-web" | head -n 1)
CONTAINER_RESTARTED="false"
CONTAINER_START_TIME=""

if [ -n "$WEB_CONTAINER_ID" ]; then
    # Get container start time in ISO format
    CONTAINER_START_ISO=$(docker inspect --format='{{.State.StartedAt}}' "$WEB_CONTAINER_ID")
    # Convert to timestamp
    CONTAINER_START_TS=$(date -d "$CONTAINER_START_ISO" +%s)
    
    if [ "$CONTAINER_START_TS" -gt "$TASK_START" ]; then
        CONTAINER_RESTARTED="true"
    fi
    CONTAINER_START_TIME="$CONTAINER_START_TS"
fi

# 4. Check if we are in the correct meeting room
# We can check window title or URL in firefox
CURRENT_URL=""
# Try to get URL from window title or xdotool hacks if possible, 
# but rely mostly on screenshot.
# Simple check: is Firefox running?
FIREFOX_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_exists": $CONFIG_EXISTS,
    "config_modified": $CONFIG_MODIFIED,
    "config_mtime": $CONFIG_MTIME,
    "container_restarted": $CONTAINER_RESTARTED,
    "container_start_ts": "$CONTAINER_START_TIME",
    "firefox_running": $FIREFOX_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "config_copy_path": "/tmp/interface_config_submitted.js"
}
EOF

# Move result to expected location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"