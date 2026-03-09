#!/bin/bash
echo "=== Exporting customize_compliance_links result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
CONFIG_PATH="/home/ga/.jitsi-meet-cfg/web/custom-interface_config.js"

# 1. Check if config file exists and was modified
CONFIG_EXISTS="false"
CONFIG_MODIFIED_DURING_TASK="false"
CONFIG_SIZE="0"

if [ -f "$CONFIG_PATH" ]; then
    CONFIG_EXISTS="true"
    CONFIG_SIZE=$(stat -c %s "$CONFIG_PATH")
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_PATH")
    
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED_DURING_TASK="true"
    fi
    
    # Copy config for verification
    cp "$CONFIG_PATH" /tmp/submitted_config.js
    chmod 644 /tmp/submitted_config.js
else
    # Create empty file to avoid copy errors
    touch /tmp/submitted_config.js
fi

# 2. Check if Web service is running (agent should have restarted it)
SERVICE_RUNNING="false"
if curl -sfk "http://localhost:8080" >/dev/null 2>&1; then
    SERVICE_RUNNING="true"
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_exists": $CONFIG_EXISTS,
    "config_modified_during_task": $CONFIG_MODIFIED_DURING_TASK,
    "config_size_bytes": $CONFIG_SIZE,
    "service_running": $SERVICE_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"