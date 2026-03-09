#!/bin/bash
echo "=== Exporting enable_whiteboard results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ENV_FILE="/home/ga/jitsi/.env"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Configuration File
CONFIG_CONTENT=""
if [ -f "$ENV_FILE" ]; then
    # Read relevant lines only
    CONFIG_CONTENT=$(grep -E "WHITEBOARD_ENABLED|WHITEBOARD_COLLAB_SERVER_PUBLIC_URL" "$ENV_FILE" || echo "")
fi

# 3. Check Container Restart Time
# Get the web container ID
cd /home/ga/jitsi
WEB_CONTAINER_ID=$(docker compose ps -q web 2>/dev/null || echo "")
CONTAINER_START_TIMESTAMP="0"

if [ -n "$WEB_CONTAINER_ID" ]; then
    # Get StartedAt timestamp in ISO format
    STARTED_AT_ISO=$(docker inspect --format='{{.State.StartedAt}}' "$WEB_CONTAINER_ID" 2>/dev/null || echo "")
    
    # Convert to unix timestamp for comparison (handling potential parsing errors)
    if [ -n "$STARTED_AT_ISO" ]; then
        CONTAINER_START_TIMESTAMP=$(date -d "$STARTED_AT_ISO" +%s 2>/dev/null || echo "0")
    fi
fi

# 4. Check Web Service Health
WEB_HEALTHY="false"
if curl -sfk "http://localhost:8080" >/dev/null 2>&1; then
    WEB_HEALTHY="true"
fi

# 5. Check Completion Signal File
SIGNAL_FILE_EXISTS="false"
SIGNAL_CONTENT=""
if [ -f "/tmp/whiteboard_enabled.txt" ]; then
    SIGNAL_FILE_EXISTS="true"
    SIGNAL_CONTENT=$(cat "/tmp/whiteboard_enabled.txt")
fi

# 6. Get Current URL (best effort via xdotool/clipboard or assumption)
# Since we can't easily get URL from Firefox via CLI without extensions, we rely on VLM.
# But we can check if firefox is running.
FIREFOX_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "container_start_time": $CONTAINER_START_TIMESTAMP,
    "config_content": "$(echo "$CONFIG_CONTENT" | sed 's/"/\\"/g' | tr '\n' ';')",
    "web_healthy": $WEB_HEALTHY,
    "signal_file_exists": $SIGNAL_FILE_EXISTS,
    "signal_content": "$SIGNAL_CONTENT",
    "firefox_running": $FIREFOX_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json