#!/bin/bash
set -e
echo "=== Exporting customize_server_config result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONFIG_PATH="/home/ga/.jitsi-meet-cfg/web/custom-config.js"
SCREENSHOT_PATH="/home/ga/jitsi_config_verification.png"
SERVED_TXT_PATH="/home/ga/custom_config_served.txt"

# 1. Take final system screenshot (fallback)
take_screenshot /tmp/task_final.png

# 2. Check Config File
CONFIG_EXISTS="false"
CONFIG_CONTENT=""
if [ -f "$CONFIG_PATH" ]; then
    CONFIG_EXISTS="true"
    CONFIG_CONTENT=$(cat "$CONFIG_PATH" | base64 -w 0)
fi

# 3. Check HTTP Serving
HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" http://localhost:8080/custom-config.js || echo "000")
HTTP_CONTENT=""
if [ "$HTTP_STATUS" == "200" ]; then
    HTTP_CONTENT=$(curl -s http://localhost:8080/custom-config.js | base64 -w 0)
fi

# 4. Check Container Restart
cd /home/ga/jitsi
WEB_CONTAINER_ID=$(docker compose ps -q web 2>/dev/null || echo "")
CONTAINER_RESTARTED="false"
CURRENT_START_TIME=""

if [ -n "$WEB_CONTAINER_ID" ]; then
    # Get start time in Unix timestamp for easier comparison
    CURRENT_START_TS=$(docker inspect --format='{{.State.StartedAt}}' "$WEB_CONTAINER_ID" | xargs -I{} date -d {} +%s)
    
    if [ "$CURRENT_START_TS" -gt "$TASK_START" ]; then
        CONTAINER_RESTARTED="true"
    fi
    CURRENT_START_TIME="$CURRENT_START_TS"
fi

# 5. Check User Verification Files
USER_SCREENSHOT_EXISTS="false"
if [ -f "$SCREENSHOT_PATH" ]; then
    USER_SCREENSHOT_EXISTS="true"
fi

USER_TXT_EXISTS="false"
if [ -f "$SERVED_TXT_PATH" ]; then
    USER_TXT_EXISTS="true"
fi

# 6. Verify Jitsi is actually accessible
JITSI_ACCESSIBLE="false"
if curl -s http://localhost:8080 > /dev/null; then
    JITSI_ACCESSIBLE="true"
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config_exists": $CONFIG_EXISTS,
    "config_content_b64": "$CONFIG_CONTENT",
    "http_status": "$HTTP_STATUS",
    "http_content_b64": "$HTTP_CONTENT",
    "container_restarted": $CONTAINER_RESTARTED,
    "container_start_ts": "$CURRENT_START_TIME",
    "task_start_ts": $TASK_START,
    "user_screenshot_exists": $USER_SCREENSHOT_EXISTS,
    "user_screenshot_path": "$SCREENSHOT_PATH",
    "user_txt_exists": $USER_TXT_EXISTS,
    "jitsi_accessible": $JITSI_ACCESSIBLE,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json