#!/bin/bash
set -e
echo "=== Exporting fix_zombie_process_leak results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

CONTAINER_NAME="job-worker"
PROJECT_DIR="/home/ga/zombie-debug"

# 1. Check if container is running
IS_RUNNING="false"
if [ "$(docker inspect -f '{{.State.Running}}' $CONTAINER_NAME 2>/dev/null)" == "true" ]; then
    IS_RUNNING="true"
fi

# 2. Check if Init is enabled in HostConfig
# This is the definitive check for "init: true"
INIT_ENABLED="false"
INIT_VALUE=$(docker inspect -f '{{.HostConfig.Init}}' $CONTAINER_NAME 2>/dev/null || echo "false")
if [ "$INIT_VALUE" == "true" ]; then
    INIT_ENABLED="true"
fi

# 3. Check for Zombie processes
# We run ps aux inside the container
ZOMBIE_COUNT="0"
PROCESS_LIST=""
if [ "$IS_RUNNING" == "true" ]; then
    # Count lines with status 'Z' (zombie) or 'defunct'
    # ps aux output: USER PID %CPU %MEM VSZ RSS TTY STAT START TIME COMMAND
    # STAT column contains 'Z' for zombies
    ZOMBIE_COUNT=$(docker exec $CONTAINER_NAME ps aux | awk '{print $8}' | grep -c 'Z' || echo "0")
    
    # Get raw process list for evidence
    PROCESS_LIST=$(docker exec $CONTAINER_NAME ps aux | head -n 10)
else
    ZOMBIE_COUNT="-1" # Container not running
fi

# 4. Check application logs (to ensure it wasn't just broken/stopped)
LOGS_ACTIVE="false"
# Check last 10 lines for "Spawning" message which indicates loop is running
if docker logs --tail 10 $CONTAINER_NAME 2>&1 | grep -q "Spawning"; then
    LOGS_ACTIVE="true"
fi

# 5. Check docker-compose.yml content
COMPOSE_CONTENT=""
if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    COMPOSE_CONTENT=$(cat "$PROJECT_DIR/docker-compose.yml" | base64 -w 0)
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "is_running": $IS_RUNNING,
    "init_enabled": $INIT_ENABLED,
    "zombie_count": $ZOMBIE_COUNT,
    "logs_active": $LOGS_ACTIVE,
    "process_list": "$(echo "$PROCESS_LIST" | base64 -w 0)",
    "compose_content_b64": "$COMPOSE_CONTENT",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="