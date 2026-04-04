#!/bin/bash
set -e
echo "=== Exporting scale_jvb_horizontal result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

cd /home/ga/jitsi

# 1. Capture docker-compose.yml content
COMPOSE_CONTENT_B64=$(base64 -w 0 docker-compose.yml)

# 2. Check running containers
JVB_CONTAINERS=$(docker ps --format "{{.Names}}" | grep "jitsi-jvb" | sort)
RUNNING_COUNT=$(echo "$JVB_CONTAINERS" | wc -l)
JVB2_RUNNING=$(docker ps --filter "name=jitsi-jvb2" --format "{{.Status}}" | grep -q "Up" && echo "true" || echo "false")

# 3. Inspect jvb2 configuration if it exists
JVB2_INSPECT="{}"
if [ "$JVB2_RUNNING" = "true" ]; then
    JVB2_INSPECT=$(docker inspect jitsi-jvb2)
fi

# 4. Check JVB2 logs for registration success
JVB2_LOG_SUCCESS="false"
if [ "$JVB2_RUNNING" = "true" ]; then
    # Look for successful connection to XMPP
    if docker logs jitsi-jvb2 2>&1 | grep -iE "Connected|Registered"; then
        JVB2_LOG_SUCCESS="true"
    fi
fi

# 5. Check report file
REPORT_FILE="/home/ga/jvb_scale_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | base64 -w 0)
    
    # Check creation time
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    else
        REPORT_CREATED_DURING_TASK="false"
    fi
else
    REPORT_CREATED_DURING_TASK="false"
fi

# 6. Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "compose_content_b64": "$COMPOSE_CONTENT_B64",
    "running_jvb_count": $RUNNING_COUNT,
    "jvb2_running": $JVB2_RUNNING,
    "jvb2_inspect": $JVB2_INSPECT,
    "jvb2_log_success": $JVB2_LOG_SUCCESS,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"