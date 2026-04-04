#!/bin/bash
echo "=== Exporting fix_volume_shadowed_dependencies result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

CONTAINER_NAME="shadow-app"
PROJECT_DIR="/home/ga/projects/shadow-bug"

# 1. Check if Container is Running
CONTAINER_RUNNING="false"
if [ "$(get_container_status "$CONTAINER_NAME")" == "running" ]; then
    CONTAINER_RUNNING="true"
fi

# 2. Check HTTP Response
APP_RESPONSE=""
HTTP_STATUS="000"
if [ "$CONTAINER_RUNNING" == "true" ]; then
    # Try multiple times as app might be starting
    for i in {1..5}; do
        HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 || echo "000")
        if [ "$HTTP_STATUS" == "200" ]; then
            APP_RESPONSE=$(curl -s http://localhost:3000)
            break
        fi
        sleep 1
    done
fi

# 3. Inspect Mounts (The Core Check)
# We need to export the raw inspection data to python for complex logic
INSPECT_JSON="{}"
if container_exists "$CONTAINER_NAME"; then
    INSPECT_JSON=$(docker inspect "$CONTAINER_NAME" 2>/dev/null)
fi

# 4. Check host directory for node_modules
# (If user ran 'npm install' on host, they cheated/bypassed the volume fix requirement)
HOST_NODE_MODULES_EXISTS="false"
if [ -d "$PROJECT_DIR/node_modules" ]; then
    HOST_NODE_MODULES_EXISTS="true"
fi

# 5. Check if compose file was modified
COMPOSE_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
COMPOSE_MTIME=$(stat -c %Y "$PROJECT_DIR/docker-compose.yml" 2>/dev/null || echo "0")
if [ "$COMPOSE_MTIME" -gt "$TASK_START" ]; then
    COMPOSE_MODIFIED="true"
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "container_running": $CONTAINER_RUNNING,
    "http_status": "$HTTP_STATUS",
    "app_response": "$(json_escape "$APP_RESPONSE")",
    "inspect_data": $INSPECT_JSON,
    "host_node_modules_exists": $HOST_NODE_MODULES_EXISTS,
    "compose_modified": $COMPOSE_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"