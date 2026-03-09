#!/bin/bash
echo "=== Exporting task results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/jitsi_audit_report.txt"

# 1. Gather Ground Truth State (for verification)
echo "Gathering ground truth system state..."

# Get Docker Container List (JSON format for easy parsing in python)
# We use a custom format to get Name, Image, Status
DOCKER_STATE=$(docker ps --format '{{json .}}' | jq -s '.')

# Get Network Info
NETWORK_NAME=$(docker network ls --filter "name=jitsi" --format "{{.Name}}" | head -n 1)
NETWORK_SUBNET=""
if [ -n "$NETWORK_NAME" ]; then
    NETWORK_SUBNET=$(docker network inspect "$NETWORK_NAME" | jq -r '.[0].IPAM.Config[0].Subnet')
fi

# Check Service Health (Internal check)
# Web
WEB_STATUS="not accessible"
if curl -sf "http://localhost:8080" >/dev/null 2>&1; then
    WEB_STATUS="accessible"
fi

# JVB (Check if process running in container or health endpoint)
JVB_STATUS="not running"
if docker ps | grep -q "jitsi-jvb"; then
    # Simple check: is container running?
    # Deeper check: curl localhost:8080/colibri/stats inside container?
    # For this task, container running + web accessible is usually sufficient for "running" status
    JVB_STATUS="running"
fi

# Prosody
PROSODY_STATUS="not running"
if docker ps | grep -q "jitsi-prosody"; then
    PROSODY_STATUS="running"
fi

# Jicofo
JICOFO_STATUS="not running"
if docker ps | grep -q "jitsi-jicofo"; then
    JICOFO_STATUS="running"
fi

# 2. Check Agent's Report File
REPORT_EXISTS="false"
REPORT_CONTENT=""
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0) # Base64 encode to safely pass in JSON
    FILE_SIZE=$(stat -c %s "$REPORT_PATH")
    FILE_MTIME=$(stat -c %Y "$REPORT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $FILE_CREATED_DURING_TASK,
    "report_size_bytes": $FILE_SIZE,
    "report_content_b64": "$REPORT_CONTENT",
    "ground_truth": {
        "containers": $DOCKER_STATE,
        "network": {
            "name": "$NETWORK_NAME",
            "subnet": "$NETWORK_SUBNET"
        },
        "services": {
            "web": "$WEB_STATUS",
            "jvb": "$JVB_STATUS",
            "prosody": "$PROSODY_STATUS",
            "jicofo": "$JICOFO_STATUS"
        }
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="