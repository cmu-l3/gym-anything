#!/bin/bash
echo "=== Exporting Docker Capabilities Hardening Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONTAINER_NAME="net-monitor"

# 1. Check if container is running
IS_RUNNING=0
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    IS_RUNNING=1
fi

# 2. Get User ID inside container
CONTAINER_UID="unknown"
if [ "$IS_RUNNING" -eq 1 ]; then
    CONTAINER_UID=$(docker exec "$CONTAINER_NAME" id -u 2>/dev/null || echo "error")
fi

# 3. Get Capability Configuration via Docker Inspect
# Note: JSON output needs careful parsing.
INSPECT_JSON=$(docker inspect "$CONTAINER_NAME" 2>/dev/null || echo "{}")

# Parse CapAdd (Expect ["NET_BIND_SERVICE", "NET_RAW"])
CAP_ADD=$(echo "$INSPECT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)[0]['HostConfig']['CapAdd'])" 2>/dev/null || echo "None")

# Parse CapDrop (Expect ["ALL"])
CAP_DROP=$(echo "$INSPECT_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin)[0]['HostConfig']['CapDrop'])" 2>/dev/null || echo "None")

# 4. Functional Checks
WEB_STATUS=0
PING_STATUS=0

if [ "$IS_RUNNING" -eq 1 ]; then
    # Check Web Root (Port 80 binding)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80/ 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" -eq 200 ]; then
        WEB_STATUS=1
    fi

    # Check Ping (NET_RAW)
    # Ping localhost to verify ICMP capability works
    PING_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:80/ping?target=127.0.0.1" 2>/dev/null || echo "000")
    if [ "$PING_HTTP_CODE" -eq 200 ]; then
        PING_STATUS=1
    fi
fi

# 5. Check Dockerfile/Compose contents (Anti-gaming: ensure user isn't just root)
DOCKERFILE_USER_CHECK=$(grep -i "USER" /home/ga/projects/net-monitor/Dockerfile 2>/dev/null || echo "")
COMPOSE_USER_CHECK=$(grep -i "user:" /home/ga/projects/net-monitor/docker-compose.yml 2>/dev/null || echo "")

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "is_running": $IS_RUNNING,
    "container_uid": "$CONTAINER_UID",
    "cap_add": "$CAP_ADD",
    "cap_drop": "$CAP_DROP",
    "web_status": $WEB_STATUS,
    "ping_status": $PING_STATUS,
    "dockerfile_user_instruction": "$DOCKERFILE_USER_CHECK",
    "compose_user_instruction": "$COMPOSE_USER_CHECK",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json