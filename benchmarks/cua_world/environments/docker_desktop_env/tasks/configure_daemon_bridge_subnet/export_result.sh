#!/bin/bash
echo "=== Exporting configure_daemon_bridge_subnet result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check Docker Daemon status
DAEMON_RUNNING="false"
if docker info > /dev/null 2>&1; then
    DAEMON_RUNNING="true"
fi

# Get current bridge network configuration
CURRENT_SUBNET=""
CURRENT_GATEWAY=""

if [ "$DAEMON_RUNNING" = "true" ]; then
    CURRENT_SUBNET=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || echo "")
    CURRENT_GATEWAY=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || echo "")
fi

# Get initial state for comparison
INITIAL_SUBNET=$(cat /tmp/initial_subnet.txt 2>/dev/null || echo "")

# Check if settings file was modified (secondary evidence)
# Docker Desktop for Linux stores settings in ~/.docker/desktop/settings.json 
# but engine config is often in internal VM. We check if user modified settings.json
SETTINGS_FILE="/home/ga/.docker/desktop/settings.json"
SETTINGS_MODIFIED="false"
if [ -f "$SETTINGS_FILE" ]; then
    SETTINGS_MTIME=$(stat -c %Y "$SETTINGS_FILE" 2>/dev/null || echo "0")
    if [ "$SETTINGS_MTIME" -gt "$TASK_START" ]; then
        SETTINGS_MODIFIED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "daemon_running": $DAEMON_RUNNING,
    "initial_subnet": "$INITIAL_SUBNET",
    "current_subnet": "$CURRENT_SUBNET",
    "current_gateway": "$CURRENT_GATEWAY",
    "settings_modified": $SETTINGS_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="