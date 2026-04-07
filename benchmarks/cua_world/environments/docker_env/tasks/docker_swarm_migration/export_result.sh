#!/bin/bash
echo "=== Exporting Docker Swarm Migration Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper if shared utils missing
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Data
RESULT_DIR="/tmp/task_result_data"
mkdir -p "$RESULT_DIR"

# Task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Swarm State
SWARM_STATE=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null || echo "inactive")

# Stack Existence
docker stack ls --format '{{.Name}}' > "$RESULT_DIR/stacks.txt" 2>/dev/null || true
STACK_EXISTS=$(grep -c "acme-tools" "$RESULT_DIR/stacks.txt" || echo "0")

# Service Replica Counts
WEB_REPLICAS=$(docker service ls --filter "name=acme-tools_web" --format '{{.Replicas}}' 2>/dev/null || echo "0/0")
API_REPLICAS=$(docker service ls --filter "name=acme-tools_api" --format '{{.Replicas}}' 2>/dev/null || echo "0/0")
DB_REPLICAS=$(docker service ls --filter "name=acme-tools_db" --format '{{.Replicas}}' 2>/dev/null || echo "0/0")
CACHE_REPLICAS=$(docker service ls --filter "name=acme-tools_cache" --format '{{.Replicas}}' 2>/dev/null || echo "0/0")

# Service Configuration (Update Policy & Resources)
docker service inspect acme-tools_web --format '{{json .Spec.UpdateConfig}}' > "$RESULT_DIR/web_update_config.json" 2>/dev/null || echo "{}" > "$RESULT_DIR/web_update_config.json"
docker service inspect acme-tools_web --format '{{json .Spec.TaskTemplate.Resources}}' > "$RESULT_DIR/web_resources.json" 2>/dev/null || echo "{}" > "$RESULT_DIR/web_resources.json"
docker service inspect acme-tools_api --format '{{json .Spec.TaskTemplate.Resources}}' > "$RESULT_DIR/api_resources.json" 2>/dev/null || echo "{}" > "$RESULT_DIR/api_resources.json"

# Web Accessibility
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:8080/ 2>/dev/null || echo "000")
HTTP_BODY_SNIPPET=$(curl -s --max-time 5 http://localhost:8080/ 2>/dev/null | grep -o "AcmeCorp" | head -1 || echo "")

# Files created
STACK_FILE_EXISTS="false"
if [ -f "/home/ga/projects/acme-platform/docker-stack.yml" ]; then
    STACK_FILE_EXISTS="true"
fi

# Images built
IMG_WEB_EXISTS=$(docker images -q acme-web:1.0 2>/dev/null)
IMG_API_EXISTS=$(docker images -q acme-api:1.0 2>/dev/null)

# Prepare JSON
# Note: Using python to robustly create JSON to avoid escaping issues
python3 -c "
import json
import os

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'swarm_state': '$SWARM_STATE',
    'stack_exists': $STACK_EXISTS,
    'replicas': {
        'web': '$WEB_REPLICAS',
        'api': '$API_REPLICAS',
        'db': '$DB_REPLICAS',
        'cache': '$CACHE_REPLICAS'
    },
    'http_code': '$HTTP_CODE',
    'http_body_snippet': '$HTTP_BODY_SNIPPET',
    'stack_file_exists': $STACK_FILE_EXISTS,
    'images_built': {
        'web': bool('$IMG_WEB_EXISTS'),
        'api': bool('$IMG_API_EXISTS')
    },
    'update_config': json.load(open('$RESULT_DIR/web_update_config.json')) if os.path.exists('$RESULT_DIR/web_update_config.json') else {},
    'web_resources': json.load(open('$RESULT_DIR/web_resources.json')) if os.path.exists('$RESULT_DIR/web_resources.json') else {},
    'api_resources': json.load(open('$RESULT_DIR/api_resources.json')) if os.path.exists('$RESULT_DIR/api_resources.json') else {}
}
with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json
echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="