#!/bin/bash
set -e

echo "=== Exporting customize_branding results ==="

source /workspace/scripts/task_utils.sh

TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONFIG_DIR="/home/ga/.jitsi-meet-cfg/web"
INTERFACE_CONFIG="$CONFIG_DIR/custom-interface_config.js"
CONFIG_FILE="$CONFIG_DIR/custom-config.js"
SCREENSHOT_PATH="/home/ga/Documents/branding_verification.png"
REPORT_PATH="/home/ga/Documents/branding_report.txt"

# 1. Check Configuration Files
INTERFACE_CONFIG_EXISTS="false"
CONFIG_FILE_EXISTS="false"

if [ -f "$INTERFACE_CONFIG" ]; then
    INTERFACE_CONFIG_EXISTS="true"
    cp "$INTERFACE_CONFIG" /tmp/custom-interface_config.js
    chmod 666 /tmp/custom-interface_config.js
fi

if [ -f "$CONFIG_FILE" ]; then
    CONFIG_FILE_EXISTS="true"
    cp "$CONFIG_FILE" /tmp/custom-config.js
    chmod 666 /tmp/custom-config.js
fi

# 2. Check Container Restart Status
# We check the start time of the 'jitsi-web-1' or 'web' container
WEB_CONTAINER_ID=$(docker ps -q -f "name=web" | head -n 1)
CONTAINER_START_TIMESTAMP="0"
CONTAINER_RESTARTED="false"

if [ -n "$WEB_CONTAINER_ID" ]; then
    # Get StartedAt timestamp in ISO format
    STARTED_AT_ISO=$(docker inspect --format='{{.State.StartedAt}}' "$WEB_CONTAINER_ID")
    # Convert to unix timestamp (requires date utility to handle ISO8601)
    CONTAINER_START_TIMESTAMP=$(date -d "$STARTED_AT_ISO" +%s 2>/dev/null || echo "0")
    
    if [ "$CONTAINER_START_TIMESTAMP" -gt "$TASK_START_TIME" ]; then
        CONTAINER_RESTARTED="true"
    fi
fi

# 3. Check Visual Evidence (Agent's Screenshot)
EVIDENCE_SCREENSHOT_EXISTS="false"
if [ -f "$SCREENSHOT_PATH" ]; then
    EVIDENCE_SCREENSHOT_EXISTS="true"
    EVIDENCE_SIZE=$(stat -c%s "$SCREENSHOT_PATH" 2>/dev/null || echo "0")
fi

# 4. Check Report
REPORT_EXISTS="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    cp "$REPORT_PATH" /tmp/agent_report.txt
    chmod 666 /tmp/agent_report.txt
fi

# 5. Check Service Availability (Did they break it?)
SERVICE_AVAILABLE="false"
if curl -s -f -o /dev/null --max-time 5 "http://localhost:8080"; then
    SERVICE_AVAILABLE="true"
fi

# 6. Fetch Page Source (to verify propagation if container restarted)
# We look for the branding string in the returned HTML/JS
BRANDING_PROPAGATED="false"
if [ "$SERVICE_AVAILABLE" == "true" ]; then
    PAGE_CONTENT=$(curl -s "http://localhost:8080")
    if echo "$PAGE_CONTENT" | grep -q "FitConnect Pro"; then
        BRANDING_PROPAGATED="true"
    fi
fi

# 7. Take Final System Screenshot
take_screenshot /tmp/task_final.png

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START_TIME,
    "interface_config_exists": $INTERFACE_CONFIG_EXISTS,
    "config_file_exists": $CONFIG_FILE_EXISTS,
    "container_restarted": $CONTAINER_RESTARTED,
    "container_start_timestamp": $CONTAINER_START_TIMESTAMP,
    "evidence_screenshot_exists": $EVIDENCE_SCREENSHOT_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "service_available": $SERVICE_AVAILABLE,
    "branding_propagated": $BRANDING_PROPAGATED,
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json