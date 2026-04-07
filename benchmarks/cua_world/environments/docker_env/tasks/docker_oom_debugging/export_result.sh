#!/bin/bash
# Export script for docker_oom_debugging task
set -e

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONTAINER_NAME="acme-worker"
PROJECT_DIR="/home/ga/projects/acme-worker-service"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Inspect Container State
echo "Inspecting container state..."
INSPECT_JSON=$(docker inspect "$CONTAINER_NAME" 2>/dev/null || echo "[]")

# Extract key metrics using python (more reliable than direct jq in minimal envs)
STATE_INFO=$(echo "$INSPECT_JSON" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)[0]
    state = data.get('State', {})
    config = data.get('HostConfig', {})
    env = data.get('Config', {}).get('Env', [])
    
    # Find MAX_ALLOCATION_MB in env
    alloc_mb = 0
    for e in env:
        if e.startswith('MAX_ALLOCATION_MB='):
            try:
                alloc_mb = int(e.split('=')[1])
            except:
                pass
                
    print(json.dumps({
        'running': state.get('Running', False),
        'oom_killed': state.get('OOMKilled', False),
        'exit_code': state.get('ExitCode', 0),
        'restart_count': state.get('RestartCount', 0),
        'memory_limit': config.get('Memory', 0),
        'env_alloc_mb': alloc_mb
    }))
except Exception as e:
    print(json.dumps({'error': str(e)}))
")

# 2. Inspect docker-compose.yml file (to check static config)
echo "Inspecting docker-compose.yml..."
COMPOSE_PATH="$PROJECT_DIR/docker-compose.yml"
FILE_ALLOC_MB="0"
FILE_MEM_LIMIT_PRESENT="false"

if [ -f "$COMPOSE_PATH" ]; then
    # Grep for the value
    FILE_ALLOC_MB=$(grep "MAX_ALLOCATION_MB=" "$COMPOSE_PATH" | cut -d'=' -f2 | tr -d ' ' || echo "0")
    if grep -q "memory: 300M" "$COMPOSE_PATH" || grep -q "memory: 300m" "$COMPOSE_PATH"; then
        FILE_MEM_LIMIT_PRESENT="true"
    fi
fi

# 3. Wait a moment to ensure it's stable (not just between crashes)
# If it's running now, wait 5s and check again
IS_STABLE="false"
IS_RUNNING=$(echo "$STATE_INFO" | grep -o '"running": true' || true)

if [ -n "$IS_RUNNING" ]; then
    sleep 5
    # Check again
    STABLE_CHECK=$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || echo "false")
    if [ "$STABLE_CHECK" = "true" ]; then
        IS_STABLE="true"
    fi
fi

# Combine into result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "container_state": $STATE_INFO,
    "file_config": {
        "alloc_mb": "$FILE_ALLOC_MB",
        "mem_limit_present": $FILE_MEM_LIMIT_PRESENT
    },
    "is_stable": $IS_STABLE
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json