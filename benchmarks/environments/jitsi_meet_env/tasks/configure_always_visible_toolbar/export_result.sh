#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Load task start time
TASK_START_TIMESTAMP=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Configuration File
CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/custom-interface_config.js"
CONFIG_EXISTS="false"
CONFIG_CONTENT=""
CONFIG_MODIFIED="false"

if [ -f "$CONFIG_FILE" ]; then
    CONFIG_EXISTS="true"
    CONFIG_CONTENT=$(cat "$CONFIG_FILE" | base64 -w 0) # Encode to avoid JSON breaking
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START_TIMESTAMP" ]; then
        CONFIG_MODIFIED="true"
    fi
fi

# 2. Check Container Restart Status
# We check if the 'jitsi-web-1' container started AFTER the task began
CONTAINER_NAME="jitsi-web-1"
CONTAINER_RESTARTED="false"
CONTAINER_START_TIME=""

if command -v docker >/dev/null; then
    # Get container start time in ISO format
    CONTAINER_START_ISO=$(docker inspect --format='{{.State.StartedAt}}' "$CONTAINER_NAME" 2>/dev/null || echo "")
    
    if [ -n "$CONTAINER_START_ISO" ]; then
        # Convert ISO to unix timestamp for comparison
        # Note: 'date' in the container might be UTC, verify timezone alignment if needed. 
        # Usually docker inspect returns UTC. date -d handles ISO 8601.
        CONTAINER_START_TS=$(date -d "$CONTAINER_START_ISO" +%s 2>/dev/null || echo "0")
        
        CONTAINER_START_TIME="$CONTAINER_START_ISO"
        
        # Allow a small buffer (e.g. 5 seconds) in case of clock skew, though local is usually synced
        if [ "$CONTAINER_START_TS" -gt "$TASK_START_TIMESTAMP" ]; then
            CONTAINER_RESTARTED="true"
        fi
    fi
fi

# 3. Check for Evidence Screenshot
EVIDENCE_PATH="/home/ga/Documents/persistent_toolbar.png"
EVIDENCE_EXISTS="false"
if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    # Copy to tmp for copy_from_env
    cp "$EVIDENCE_PATH" /tmp/evidence_screenshot.png
fi

# 4. Take final system screenshot (for VLM verification of current state)
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START_TIMESTAMP,
    "config_exists": $CONFIG_EXISTS,
    "config_content_base64": "$CONFIG_CONTENT",
    "config_modified_during_task": $CONFIG_MODIFIED,
    "container_restarted_during_task": $CONTAINER_RESTARTED,
    "container_start_time": "$CONTAINER_START_TIME",
    "evidence_screenshot_exists": $EVIDENCE_EXISTS,
    "evidence_screenshot_path": "/tmp/evidence_screenshot.png",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "=== Export complete ==="