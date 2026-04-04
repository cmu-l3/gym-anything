#!/bin/bash
echo "=== Exporting container_security_hardening Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

APP_DIR="/home/ga/insecure-app"

# We check the HARDENED container, not the insecure one.
# The agent must have:
# 1. Fixed the Dockerfile (added non-root USER)
# 2. Fixed the compose (removed socket mount, removed privileged, added limits)
# 3. Rebuilt the image as secure-web:hardened
# 4. Started the hardened container

# Find the HARDENED container only — never use the insecure baseline container.
# The agent must have rebuilt and redeployed with a hardened image.
HARDENED_CONTAINER=""

# Primary: look for the exact hardened image tag 'secure-web:hardened'
HARDENED_CONTAINER=$(docker ps --format "{{.Names}}:{{.Image}}" 2>/dev/null | grep "secure-web:hardened" | head -1 | cut -d: -f1)

# Secondary: look for container names that explicitly include 'hardened'
if [ -z "$HARDENED_CONTAINER" ]; then
    HARDENED_CONTAINER=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -i "hardened" | grep -vi "insecure" | head -1)
fi

# IMPORTANT: Do NOT fall back further. The original 'insecure-web' container must NOT be used.
# If HARDENED_CONTAINER is still empty, the agent has not completed the task.

echo "Inspecting container: $HARDENED_CONTAINER"

# --- Check 1: Non-root user ---
RUNS_AS_ROOT="true"
CONTAINER_USER="root"
if [ -n "$HARDENED_CONTAINER" ]; then
    # Get running user via exec (most reliable)
    CONTAINER_USER=$(docker exec "$HARDENED_CONTAINER" id -u 2>/dev/null || echo "0")
    if [ "$CONTAINER_USER" != "0" ] && [ -n "$CONTAINER_USER" ]; then
        RUNS_AS_ROOT="false"
    fi
    # Also check config user
    CONFIG_USER=$(docker inspect "$HARDENED_CONTAINER" --format '{{.Config.User}}' 2>/dev/null || echo "")
    if [ "$CONFIG_USER" != "" ] && [ "$CONFIG_USER" != "root" ] && [ "$CONFIG_USER" != "0" ]; then
        RUNS_AS_ROOT="false"
    fi
fi

# --- Check 2: No Docker socket mount ---
HAS_DOCKER_SOCKET="false"
if [ -n "$HARDENED_CONTAINER" ]; then
    MOUNTS=$(docker inspect "$HARDENED_CONTAINER" --format '{{range .Mounts}}{{.Source}} {{end}}' 2>/dev/null || echo "")
    if echo "$MOUNTS" | grep -q "/var/run/docker.sock"; then
        HAS_DOCKER_SOCKET="true"
    fi
fi

# --- Check 3: Not privileged ---
IS_PRIVILEGED="false"
if [ -n "$HARDENED_CONTAINER" ]; then
    PRIV=$(docker inspect "$HARDENED_CONTAINER" --format '{{.HostConfig.Privileged}}' 2>/dev/null || echo "false")
    if [ "$PRIV" = "true" ]; then
        IS_PRIVILEGED="true"
    fi
fi

# --- Check 4: Resource limits ---
HAS_MEMORY_LIMIT="false"
MEMORY_LIMIT_BYTES=0
if [ -n "$HARDENED_CONTAINER" ]; then
    MEM=$(docker inspect "$HARDENED_CONTAINER" --format '{{.HostConfig.Memory}}' 2>/dev/null || echo "0")
    if [ "$MEM" != "0" ] && [ -n "$MEM" ]; then
        HAS_MEMORY_LIMIT="true"
        MEMORY_LIMIT_BYTES="$MEM"
    fi
fi

# --- Check 5: App still functional ---
APP_HTTP_CODE="000"
for i in 1 2 3; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 http://localhost:8090 2>/dev/null || echo "000")
    if [ "$CODE" = "200" ]; then
        APP_HTTP_CODE="$CODE"
        break
    fi
    sleep 2
done

# --- Also check if hardened image exists ---
HARDENED_IMAGE_EXISTS="false"
if docker image inspect secure-web:hardened >/dev/null 2>&1; then
    HARDENED_IMAGE_EXISTS="true"
fi

cat > /tmp/container_security_hardening_result.json << JSONEOF
{
    "hardened_container": "$HARDENED_CONTAINER",
    "runs_as_root": $RUNS_AS_ROOT,
    "container_user": "$CONTAINER_USER",
    "has_docker_socket": $HAS_DOCKER_SOCKET,
    "is_privileged": $IS_PRIVILEGED,
    "has_memory_limit": $HAS_MEMORY_LIMIT,
    "memory_limit_bytes": $MEMORY_LIMIT_BYTES,
    "app_http_code": "$APP_HTTP_CODE",
    "hardened_image_exists": $HARDENED_IMAGE_EXISTS,
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "=== Export Complete ==="
cat /tmp/container_security_hardening_result.json
