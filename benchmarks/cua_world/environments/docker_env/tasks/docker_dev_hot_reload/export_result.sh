#!/bin/bash
echo "=== Exporting Task Results ==="

# Load helpers if available
source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/projects/inventory-service"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORIGINAL_CHECKSUM=$(cat /tmp/original_compose_checksum.txt 2>/dev/null || echo "none")

# Take final screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_final.png
else
    DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
fi

# 1. Check Immutability
CURRENT_CHECKSUM=$(md5sum "$PROJECT_DIR/docker-compose.yml" 2>/dev/null | awk '{print $1}' || echo "missing")
IMMUTABLE_CHECK="false"
if [ "$CURRENT_CHECKSUM" == "$ORIGINAL_CHECKSUM" ]; then
    IMMUTABLE_CHECK="true"
fi

# 2. Check Override File
OVERRIDE_EXISTS="false"
OVERRIDE_CONTENT=""
if [ -f "$PROJECT_DIR/docker-compose.override.yml" ]; then
    OVERRIDE_EXISTS="true"
    # Read content, escape double quotes for JSON
    OVERRIDE_CONTENT=$(cat "$PROJECT_DIR/docker-compose.override.yml" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
else
    OVERRIDE_CONTENT="\"\""
fi

# 3. Check Running State
IS_RUNNING="false"
CONTAINER_ID=""
if docker compose -f "$PROJECT_DIR/docker-compose.yml" ps -q inventory-api > /dev/null 2>&1; then
    IS_RUNNING="true"
    CONTAINER_ID=$(docker compose -f "$PROJECT_DIR/docker-compose.yml" ps -q inventory-api)
fi

# 4. Inspect Container Config
ENV_HAS_DEBUG="false"
CMD_IS_FLASK="false"
HAS_MOUNT="false"
PORT_EXPOSED="false"

if [ -n "$CONTAINER_ID" ]; then
    # Check Env
    if docker inspect "$CONTAINER_ID" | grep -q "FLASK_DEBUG=1"; then
        ENV_HAS_DEBUG="true"
    fi
    
    # Check Cmd (look for flask)
    if docker inspect "$CONTAINER_ID" --format '{{.Config.Cmd}}' | grep -qi "flask"; then
        CMD_IS_FLASK="true"
    fi
    
    # Check Mounts (look for /app binding)
    # We check if Source contains the project dir and Target is /app
    if docker inspect "$CONTAINER_ID" --format '{{json .Mounts}}' | grep -q "$PROJECT_DIR/app"; then
        HAS_MOUNT="true"
    fi
    
    # Check Ports (5000->5000)
    # Looking for "5000/tcp":[{"HostIp":"0.0.0.0","HostPort":"5000"}]
    if docker inspect "$CONTAINER_ID" --format '{{json .NetworkSettings.Ports}}' | grep -q '"HostPort":"5000"'; then
        PORT_EXPOSED="true"
    fi
fi

# 5. HOT RELOAD TEST
# We perform the active test here inside the environment
HOT_RELOAD_SUCCESS="false"
RESPONSE_BEFORE=""
RESPONSE_AFTER=""
CONTAINER_RESTARTED="false"

if [ "$IS_RUNNING" == "true" ] && [ "$PORT_EXPOSED" == "true" ]; then
    echo "Starting Hot Reload Test..."
    
    # Get initial start time
    START_TIME_1=$(docker inspect "$CONTAINER_ID" --format '{{.State.StartedAt}}')
    
    # Check baseline response
    RESPONSE_BEFORE=$(curl -s --max-time 2 http://localhost:5000/ || echo "error")
    
    # Modify code
    TEST_TOKEN="TOKEN_$(date +%s)"
    sed -i "s/Production Instance/$TEST_TOKEN/" "$PROJECT_DIR/app/main.py"
    
    # Wait for reload (Flask reloader usually takes < 1s)
    sleep 3
    
    # Check response again
    RESPONSE_AFTER=$(curl -s --max-time 2 http://localhost:5000/ || echo "error")
    
    # Check if container restarted
    START_TIME_2=$(docker inspect "$CONTAINER_ID" --format '{{.State.StartedAt}}')
    if [ "$START_TIME_1" != "$START_TIME_2" ]; then
        CONTAINER_RESTARTED="true"
    fi
    
    # Verify logic
    if [[ "$RESPONSE_AFTER" == *"$TEST_TOKEN"* ]] && [ "$CONTAINER_RESTARTED" == "false" ]; then
        HOT_RELOAD_SUCCESS="true"
    fi
    
    # Clean up modification
    sed -i "s/$TEST_TOKEN/Production Instance/" "$PROJECT_DIR/app/main.py"
fi

# Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "immutable_check": $IMMUTABLE_CHECK,
    "override_exists": $OVERRIDE_EXISTS,
    "override_content": $OVERRIDE_CONTENT,
    "is_running": $IS_RUNNING,
    "env_has_debug": $ENV_HAS_DEBUG,
    "cmd_is_flask": $CMD_IS_FLASK,
    "has_mount": $HAS_MOUNT,
    "port_exposed": $PORT_EXPOSED,
    "hot_reload_success": $HOT_RELOAD_SUCCESS,
    "hot_reload_restarted": $CONTAINER_RESTARTED,
    "response_before": "$(echo $RESPONSE_BEFORE | tr -d '"')",
    "response_after": "$(echo $RESPONSE_AFTER | tr -d '"')",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Handle permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json