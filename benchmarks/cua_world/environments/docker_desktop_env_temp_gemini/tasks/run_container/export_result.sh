#!/bin/bash
# Export script for run_container task (post_task hook)
# Gathers verification data and saves to JSON

echo "=== Exporting run_container task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get initial counts
INITIAL_COUNT=$(cat /tmp/initial_container_count 2>/dev/null || echo "0")
INITIAL_RUNNING=$(cat /tmp/initial_running_count 2>/dev/null || echo "0")

# Get current counts
CURRENT_COUNT=$(get_container_count "all")
CURRENT_RUNNING=$(get_container_count "running")

# Target container details
TARGET_NAME="my-nginx-server"
CONTAINER_FOUND="false"
CONTAINER_RUNNING="false"
CONTAINER_ID=""
CONTAINER_IMAGE=""
CONTAINER_PORTS=""
CONTAINER_STATUS=""
PORT_MAPPING_CORRECT="false"
WEB_ACCESSIBLE="false"

# Check if target container exists
if container_exists "$TARGET_NAME"; then
    CONTAINER_FOUND="true"

    # Get container details
    CONTAINER_INFO=$(docker inspect "$TARGET_NAME" 2>/dev/null)
    CONTAINER_ID=$(docker ps -a --filter "name=^${TARGET_NAME}$" --format '{{.ID}}' 2>/dev/null)
    CONTAINER_IMAGE=$(docker ps -a --filter "name=^${TARGET_NAME}$" --format '{{.Image}}' 2>/dev/null)
    CONTAINER_STATUS=$(docker ps -a --filter "name=^${TARGET_NAME}$" --format '{{.Status}}' 2>/dev/null)
    CONTAINER_PORTS=$(docker ps -a --filter "name=^${TARGET_NAME}$" --format '{{.Ports}}' 2>/dev/null)

    # Check if running
    if container_running "$TARGET_NAME"; then
        CONTAINER_RUNNING="true"
    fi

    # Check port mapping (8888:80) - must be specifically 8888->80/tcp mapping
    # Pattern: "0.0.0.0:8888->80/tcp" or "8888->80/tcp"
    if echo "$CONTAINER_PORTS" | grep -qE "8888->80/tcp"; then
        PORT_MAPPING_CORRECT="true"
    fi

    # Try to access the web server with retry logic (if running and port mapped)
    if [ "$CONTAINER_RUNNING" = "true" ] && [ "$PORT_MAPPING_CORRECT" = "true" ]; then
        for attempt in 1 2 3 4 5; do
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://localhost:8888 2>/dev/null || echo "000")
            if [ "$HTTP_CODE" = "200" ]; then
                WEB_ACCESSIBLE="true"
                break
            fi
            sleep 2
        done
    fi
fi

# Get list of all containers for debugging
ALL_CONTAINERS=$(docker ps -a --format '{{.Names}}:{{.Status}}' 2>/dev/null | head -10 | tr '\n' ',' | sed 's/,$//')

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

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task": "run_container",
    "target_container": "$TARGET_NAME",
    "container_found": $CONTAINER_FOUND,
    "container_running": $CONTAINER_RUNNING,
    "container_id": "$CONTAINER_ID",
    "container_image": "$CONTAINER_IMAGE",
    "container_status": "$(echo "$CONTAINER_STATUS" | sed 's/"/\\"/g')",
    "container_ports": "$CONTAINER_PORTS",
    "port_mapping_correct": $PORT_MAPPING_CORRECT,
    "web_accessible": $WEB_ACCESSIBLE,
    "initial_container_count": $INITIAL_COUNT,
    "current_container_count": $CURRENT_COUNT,
    "initial_running_count": $INITIAL_RUNNING,
    "current_running_count": $CURRENT_RUNNING,
    "all_containers_sample": "$ALL_CONTAINERS",
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
