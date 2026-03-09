#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

CONFIG_PATH="/home/ga/.jitsi-meet-cfg/web/config.js"
EVIDENCE_PATH="/home/ga/bandwidth_test_evidence.png"

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Check if Config was modified
CONFIG_MODIFIED="false"
if [ -f "$CONFIG_PATH" ]; then
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_PATH" 2>/dev/null || echo "0")
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED="true"
    fi
    # Copy config for verification
    cp "$CONFIG_PATH" /tmp/final_config.js
    chmod 644 /tmp/final_config.js
else
    echo "ERROR: Config file missing!"
    echo "" > /tmp/final_config.js
fi

# 3. Check Web Container Uptime (to verify restart)
# Get start time of the web container
# We look for a container name containing 'web'
CONTAINER_ID=$(docker ps -qf "name=web" | head -n 1)
CONTAINER_RESTARTED="false"
CONTAINER_UPTIME_SEC=0

if [ -n "$CONTAINER_ID" ]; then
    # Get container start time in seconds since epoch
    CONTAINER_START_TS=$(docker inspect --format='{{.State.StartedAt}}' "$CONTAINER_ID" | xargs date +%s -d)
    CURRENT_TS=$(date +%s)
    CONTAINER_UPTIME_SEC=$((CURRENT_TS - CONTAINER_START_TS))
    
    # If container started AFTER task started, it was restarted
    if [ "$CONTAINER_START_TS" -gt "$TASK_START" ]; then
        CONTAINER_RESTARTED="true"
    fi
fi

# 4. Check Evidence Screenshot
EVIDENCE_EXISTS="false"
if [ -f "$EVIDENCE_PATH" ]; then
    EVIDENCE_EXISTS="true"
    # Copy for verification
    cp "$EVIDENCE_PATH" /tmp/evidence.png
    chmod 644 /tmp/evidence.png
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_modified": $CONFIG_MODIFIED,
    "container_restarted": $CONTAINER_RESTARTED,
    "container_uptime_sec": $CONTAINER_UPTIME_SEC,
    "evidence_exists": $EVIDENCE_EXISTS,
    "config_file_path": "/tmp/final_config.js",
    "evidence_file_path": "/tmp/evidence.png"
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="