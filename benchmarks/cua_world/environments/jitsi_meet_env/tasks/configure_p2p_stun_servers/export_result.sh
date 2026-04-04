#!/bin/bash
echo "=== Exporting Configure STUN Servers results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONFIG_PATH="/home/ga/.jitsi-meet-cfg/web/config.js"

# 1. Check if config file was modified
CONFIG_MODIFIED="false"
CONFIG_SIZE=0
if [ -f "$CONFIG_PATH" ]; then
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_PATH" 2>/dev/null || echo "0")
    CONFIG_SIZE=$(stat -c %s "$CONFIG_PATH" 2>/dev/null || echo "0")
    
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED="true"
    fi
fi

# 2. Check if Jitsi Web is running (agent should have restarted it)
WEB_CONTAINER_RUNNING="false"
if docker ps --format '{{.Names}}' | grep -q "jitsi-web"; then
    WEB_CONTAINER_RUNNING="true"
fi

# 3. Check if service is actually reachable (valid config)
SERVICE_REACHABLE="false"
if curl -sfk -m 5 "${JITSI_BASE_URL:-http://localhost:8080}/config.js" > /dev/null 2>&1; then
    SERVICE_REACHABLE="true"
fi

# 4. Check for verification screenshot
SCREENSHOT_PATH="/home/ga/Documents/stun_config_verified.png"
SCREENSHOT_EXISTS="false"
if [ -f "$SCREENSHOT_PATH" ]; then
    SCREENSHOT_EXISTS="true"
fi

# 5. Capture final state
take_screenshot /tmp/task_final.png

# 6. Copy config file to temp for extraction (avoid permissions issues)
cp "$CONFIG_PATH" /tmp/config_final.js 2>/dev/null || true
chmod 644 /tmp/config_final.js 2>/dev/null || true

# 7. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_modified": $CONFIG_MODIFIED,
    "config_size": $CONFIG_SIZE,
    "web_container_running": $WEB_CONTAINER_RUNNING,
    "service_reachable": $SERVICE_REACHABLE,
    "agent_screenshot_exists": $SCREENSHOT_EXISTS,
    "config_path": "/tmp/config_final.js"
}
EOF

# Move to standard result location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="