#!/bin/bash
# Export script for secure_dind_socket_access task

echo "=== Exporting secure_dind_socket_access result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

CONTAINER_NAME="build-agent"
SOCKET_PATH="/var/run/docker.sock"

# 1. Check Container Status
CONTAINER_RUNNING="false"
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" = "true" ]; then
    CONTAINER_RUNNING="true"
fi

# 2. Check User ID inside container
CONTAINER_UID="-1"
if [ "$CONTAINER_RUNNING" = "true" ]; then
    CONTAINER_UID=$(docker exec "$CONTAINER_NAME" id -u 2>/dev/null || echo "-1")
fi

# 3. Check Docker Socket Access inside container
DOCKER_ACCESS="false"
DOCKER_ERROR=""
if [ "$CONTAINER_RUNNING" = "true" ]; then
    if docker exec "$CONTAINER_NAME" docker ps > /dev/null 2>&1; then
        DOCKER_ACCESS="true"
    else
        # Capture error for feedback
        DOCKER_ERROR=$(docker exec "$CONTAINER_NAME" docker ps 2>&1 | head -n 1)
    fi
fi

# 4. Check Host Socket Permissions (Security Check)
# Must NOT be world-writable (x6x or xx6 or 777)
CURRENT_SOCKET_PERMS=$(stat -c %a "$SOCKET_PATH" 2>/dev/null || echo "000")
INITIAL_SOCKET_PERMS=$(cat /tmp/initial_socket_perms 2>/dev/null || echo "660")
SOCKET_SECURE="true"

# Check if permissions changed to something insecure (like 666 or 777)
if [ "$CURRENT_SOCKET_PERMS" != "$INITIAL_SOCKET_PERMS" ]; then
    # If it was changed, check if it's world writable
    if [[ "$CURRENT_SOCKET_PERMS" == *6 ]] || [[ "$CURRENT_SOCKET_PERMS" == *7 ]]; then
        SOCKET_SECURE="false"
    fi
fi

# 5. Check compose usage (via labels or inspection)
COMPOSE_USED="false"
if docker inspect "$CONTAINER_NAME" 2>/dev/null | grep -q "com.docker.compose.project"; then
    COMPOSE_USED="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "container_running": $CONTAINER_RUNNING,
    "container_uid": $CONTAINER_UID,
    "docker_access": $DOCKER_ACCESS,
    "docker_error": "$(json_escape "$DOCKER_ERROR")",
    "socket_secure": $SOCKET_SECURE,
    "current_socket_perms": "$CURRENT_SOCKET_PERMS",
    "compose_used": $COMPOSE_USED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="