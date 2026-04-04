#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Fetch the currently served config via HTTP
# This proves the server was actually restarted and is serving the new config
echo "Fetching served config..."
curl -s -k "http://localhost:8080/config.js" > /tmp/served_config.js || echo "Failed to fetch config"

# 2. Check the physical file on disk
PHYSICAL_CONFIG_PATH="/home/ga/.jitsi-meet-cfg/web/config.js"
if [ -f "$PHYSICAL_CONFIG_PATH" ]; then
    cp "$PHYSICAL_CONFIG_PATH" /tmp/physical_config.js
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$PHYSICAL_CONFIG_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi
else
    echo "Physical config file not found"
    FILE_MODIFIED="false"
fi

# 3. Check if service is reachable
HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}\n" -k http://localhost:8080/ || echo "000")
if [ "$HTTP_STATUS" == "200" ]; then
    SERVICE_UP="true"
else
    SERVICE_UP="false"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "service_up": $SERVICE_UP,
    "file_modified_during_task": $FILE_MODIFIED,
    "served_config_exists": $([ -f /tmp/served_config.js ] && echo "true" || echo "false"),
    "physical_config_exists": $([ -f /tmp/physical_config.js ] && echo "true" || echo "false")
}
EOF

# Move files for extraction
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json /tmp/served_config.js /tmp/physical_config.js /tmp/task_final.png 2>/dev/null || true

echo "=== Export complete ==="