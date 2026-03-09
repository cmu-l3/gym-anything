#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if the report file was created
REPORT_PATH="/home/ga/fps_config_report.txt"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
else
    REPORT_EXISTS="false"
    REPORT_SIZE="0"
fi

# 3. Check if Jitsi Web container is running
if docker ps --format '{{.Names}}' | grep -q "jitsi-web"; then
    WEB_CONTAINER_RUNNING="true"
else
    WEB_CONTAINER_RUNNING="false"
fi

# 4. Check if the Web UI is actually reachable (200 OK)
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 || echo "000")
if [ "$HTTP_STATUS" == "200" ]; then
    WEB_REACHABLE="true"
else
    WEB_REACHABLE="false"
fi

# 5. Prepare the config file for the verifier
# We copy it to /tmp so the verifier can access it via copy_from_env
CONFIG_PATH="/home/ga/.jitsi-meet-cfg/web/config.js"
if [ -f "$CONFIG_PATH" ]; then
    cp "$CONFIG_PATH" /tmp/final_config.js
    chmod 644 /tmp/final_config.js
    CONFIG_EXISTS="true"
else
    CONFIG_EXISTS="false"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_size_bytes": $REPORT_SIZE,
    "web_container_running": $WEB_CONTAINER_RUNNING,
    "web_reachable": $WEB_REACHABLE,
    "config_exists": $CONFIG_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="