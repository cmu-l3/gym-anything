#!/bin/bash
echo "=== Exporting Configure HiFi Music Mode results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONFIG_FILE="/home/ga/.jitsi-meet-cfg/web/custom-config.js"
EVIDENCE_SCREENSHOT="/home/ga/music_mode_verification.png"

# Capture final state
take_screenshot /tmp/task_final.png

# 1. Check Config File Existence and Modification Time
CONFIG_EXISTS="false"
CONFIG_MODIFIED="false"
CONFIG_CONTENT=""

if [ -f "$CONFIG_FILE" ]; then
    CONFIG_EXISTS="true"
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
    
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED="true"
    fi
    
    # Read content for verifier to parse (base64 to avoid JSON escaping issues)
    CONFIG_CONTENT=$(cat "$CONFIG_FILE" | base64 -w 0)
fi

# 2. Check Evidence Screenshot
SCREENSHOT_EXISTS="false"
if [ -f "$EVIDENCE_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    # Copy to tmp for export if needed, though usually verifier reads from container
fi

# 3. Check Docker Container Status (Did they restart it?)
# We can check the uptime of the 'web' container. If it's less than (NOW - TASK_START), it was restarted.
WEB_CONTAINER_UPTIME=0
CONTAINER_RESTARTED="false"

# Get the container ID for the web service
WEB_CID=$(docker compose -f /home/ga/jitsi/docker-compose.yml ps -q web 2>/dev/null || true)

if [ -n "$WEB_CID" ]; then
    # Get start time of container in seconds since epoch
    WEB_START_TIME=$(docker inspect --format='{{.State.StartedAt}}' "$WEB_CID" | xargs date +%s -d 2>/dev/null || echo "0")
    
    if [ "$WEB_START_TIME" -gt "$TASK_START" ]; then
        CONTAINER_RESTARTED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "config_exists": $CONFIG_EXISTS,
    "config_modified": $CONFIG_MODIFIED,
    "config_content_b64": "$CONFIG_CONTENT",
    "evidence_screenshot_exists": $SCREENSHOT_EXISTS,
    "container_restarted": $CONTAINER_RESTARTED,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"