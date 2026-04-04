#!/bin/bash
echo "=== Exporting enforce_hd_video_defaults results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Agent Evidence File
EVIDENCE_FILE="/home/ga/served_config.js"
EVIDENCE_EXISTS="false"
EVIDENCE_SIZE="0"
if [ -f "$EVIDENCE_FILE" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_SIZE=$(stat -c %s "$EVIDENCE_FILE" 2>/dev/null || echo "0")
fi

# 3. Fetch ACTUAL served config (Ground Truth)
# We use curl to see what the server is actually sending to clients
ACTUAL_CONFIG_PATH="/tmp/ground_truth_config.js"
if curl -s "http://localhost:8080/config.js" > "$ACTUAL_CONFIG_PATH"; then
    echo "Fetched ground truth config from server"
else
    echo "Failed to fetch config from server"
    echo "// Fetch failed" > "$ACTUAL_CONFIG_PATH"
fi

# 4. Check Container Status
# We want to see if the web container is running
CONTAINER_RUNNING=$(docker ps --format '{{.Names}}' | grep -q "jitsi-meet-web" && echo "true" || echo "false")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_size": $EVIDENCE_SIZE,
    "container_running": $CONTAINER_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "actual_config_path": "$ACTUAL_CONFIG_PATH"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="