#!/bin/bash
echo "=== Exporting configure_silent_join results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

CONFIG_PATH="/home/ga/.jitsi-meet-cfg/web/custom-config.js"
RESULT_PATH="/home/ga/silent_join_result.txt"

# 1. Check Config File Existence & Stats
CONFIG_EXISTS="false"
CONFIG_MODIFIED_DURING_TASK="false"
if [ -f "$CONFIG_PATH" ]; then
    CONFIG_EXISTS="true"
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_PATH" 2>/dev/null || echo "0")
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED_DURING_TASK="true"
    fi
fi

# 2. Check Result File
RESULT_FILE_EXISTS="false"
if [ -f "$RESULT_PATH" ]; then
    RESULT_FILE_EXISTS="true"
fi

# 3. Check Docker Container Status
# We expect all 4 main components to be Up
CONTAINERS_RUNNING="false"
RUNNING_COUNT=$(docker ps --format '{{.Names}}' | grep -E "jitsi-meet-(web|prosody|jicofo|jvb)" | wc -l)
if [ "$RUNNING_COUNT" -ge 4 ]; then
    CONTAINERS_RUNNING="true"
fi

# 4. Fetch Effective Config from Web Container
# We curl the config.js endpoint to see if our changes are reflected in the served file
# Note: config.js is generated. custom-config.js is usually loaded separately or appended. 
# We'll try to fetch the raw config.js to see if settings appear there, or if custom-config.js is accessible.
# In standard Jitsi images, config.js typically includes the custom config.
curl -s -k "http://localhost:8080/config.js" > /tmp/served_config.js || echo "Failed to fetch config" > /tmp/served_config.js

# 5. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create Export JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_exists": $CONFIG_EXISTS,
    "config_modified_during_task": $CONFIG_MODIFIED_DURING_TASK,
    "containers_running": $CONTAINERS_RUNNING,
    "result_file_exists": $RESULT_FILE_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "config_path": "$CONFIG_PATH",
    "served_config_path": "/tmp/served_config.js"
}
EOF

# Move result to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="