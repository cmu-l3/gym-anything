#!/bin/bash
echo "=== Exporting Configure Kiosk Toolbar result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

CONFIG_PATH="/home/ga/.jitsi-meet-cfg/web/custom-config.js"

# 1. Check Configuration File
CONFIG_EXISTS="false"
CONFIG_MODIFIED="false"
CONFIG_CONTENT=""

if [ -f "$CONFIG_PATH" ]; then
    CONFIG_EXISTS="true"
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_PATH" 2>/dev/null || echo "0")
    
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED="true"
    fi
    
    # Read content, escape double quotes for JSON safety
    # We will copy the file itself for the verifier, but keeping a snippet in JSON is useful
    CONFIG_CONTENT=$(cat "$CONFIG_PATH" | head -n 50 | base64 -w 0) 
fi

# 2. Check Jitsi Web Container Status (Restart check)
# We check if the container uptime is less than the task duration, implying a restart
CONTAINER_RESTARTED="false"
WEB_CONTAINER_START=$(docker inspect --format='{{.State.StartedAt}}' $(docker compose -f /home/ga/jitsi/docker-compose.yml ps -q web) 2>/dev/null || echo "")
if [ -n "$WEB_CONTAINER_START" ]; then
    # Convert ISO8601 to timestamp (requires date parsing, doing a simpler check)
    # Check if container is running
    if docker compose -f /home/ga/jitsi/docker-compose.yml ps --services --filter "status=running" | grep -q "web"; then
        # Logic: We can't easily parse date in minimal bash, so we rely on file timestamps and functional checks
        # But we can check if it's currently running
        CONTAINER_RUNNING="true"
    else
        CONTAINER_RUNNING="false"
    fi
else
    CONTAINER_RUNNING="false"
fi

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_exists": $CONFIG_EXISTS,
    "config_modified": $CONFIG_MODIFIED,
    "container_running": $CONTAINER_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "config_path": "$CONFIG_PATH"
}
EOF

# Move result to expected location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# 5. Prepare Config File for Extraction
# Copy the config file to /tmp so verifier can grab it easily without permission issues
if [ -f "$CONFIG_PATH" ]; then
    cp "$CONFIG_PATH" /tmp/submitted_config.js
    chmod 666 /tmp/submitted_config.js
fi

echo "=== Export complete ==="