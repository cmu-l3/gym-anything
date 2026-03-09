#!/bin/bash
# Export script for stop_container task (post_task hook)
# Gathers verification data and saves to JSON

echo "=== Exporting stop_container task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get initial state
INITIAL_RUNNING=$(cat /tmp/initial_container_running 2>/dev/null || echo "unknown")
INITIAL_RUNNING_COUNT=$(cat /tmp/initial_running_count 2>/dev/null || echo "0")

# Get current state
CURRENT_RUNNING_COUNT=$(get_container_count "running")

# Target container details
TARGET_NAME="test-web-server"
CONTAINER_EXISTS="false"
CONTAINER_STOPPED="false"
CONTAINER_STATUS=""

# Check container state
if container_exists "$TARGET_NAME"; then
    CONTAINER_EXISTS="true"
    CONTAINER_STATUS=$(docker ps -a --filter "name=^${TARGET_NAME}$" --format '{{.Status}}' 2>/dev/null)

    # Check if container is stopped (not running)
    if ! container_running "$TARGET_NAME"; then
        CONTAINER_STOPPED="true"
    fi
else
    # Container doesn't exist at all (was removed, which is acceptable)
    CONTAINER_STOPPED="true"
fi

# Check if Docker Desktop is running (check multiple possible process names)
DOCKER_DESKTOP_RUNNING="false"
if pgrep -f "com.docker.backend" > /dev/null 2>&1 || \
   pgrep -f "/opt/docker-desktop/Docker" > /dev/null 2>&1; then
    DOCKER_DESKTOP_RUNNING="true"
fi

# Check if Docker daemon is working
DOCKER_DAEMON_READY="false"
if timeout 5 docker info > /dev/null 2>&1; then
    DOCKER_DAEMON_READY="true"
fi

# Get list of running containers
RUNNING_CONTAINERS=$(docker ps --format '{{.Names}}' 2>/dev/null | tr '\n' ',' | sed 's/,$//')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task": "stop_container",
    "target_container": "$TARGET_NAME",
    "container_exists": $CONTAINER_EXISTS,
    "container_stopped": $CONTAINER_STOPPED,
    "container_status": "$(echo "$CONTAINER_STATUS" | sed 's/"/\\"/g')",
    "initial_container_running": "$INITIAL_RUNNING",
    "initial_running_count": $INITIAL_RUNNING_COUNT,
    "current_running_count": $CURRENT_RUNNING_COUNT,
    "running_containers": "$RUNNING_CONTAINERS",
    "docker_desktop_running": $DOCKER_DESKTOP_RUNNING,
    "docker_daemon_ready": $DOCKER_DAEMON_READY,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with fallbacks
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="
