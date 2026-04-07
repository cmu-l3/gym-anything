#!/bin/bash
# Export script for docker_compose_env_debugging

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/projects/finance-core"

# 1. Check Container Status
CONTAINER_RUNNING="false"
if docker ps --format '{{.Names}}' | grep -q "^finance-app$"; then
    CONTAINER_RUNNING="true"
fi

# 2. Inspect Environment Variables inside container
# We look for the values that SHOULD be there from .env.prod
ENV_JSON=$(docker inspect finance-app --format '{{json .Config.Env}}' 2>/dev/null || echo "[]")

HOST_VALUE=""
PASS_VALUE=""
REGION_VALUE=""

# Parse JSON env vars using python for reliability
read -r HOST_VALUE PASS_VALUE REGION_VALUE <<< $(python3 -c "
import sys, json
env = json.loads('$ENV_JSON') if '$ENV_JSON' != '[]' else []
env_dict = dict(item.split('=', 1) for item in env if '=' in item)
print(f\"{env_dict.get('DB_HOST', '')} {env_dict.get('DB_PASSWORD', '')} {env_dict.get('API_REGION', '')}\")
")

# 3. Check Logs for Success Message
LOG_SUCCESS="false"
if [ "$CONTAINER_RUNNING" = "true" ]; then
    if docker logs finance-app 2>&1 | grep -q "CONNECTION ESTABLISHED to prod-db-01"; then
        LOG_SUCCESS="true"
    fi
fi

# 4. Check docker-compose.yml content (Static Analysis)
# Did they remove the hardcoded values?
YAML_FIXED="false"
YAML_CONTENT=$(cat "$PROJECT_DIR/docker-compose.yml" 2>/dev/null || echo "")

# Logic: Valid config should use pass-through (e.g. "- DB_HOST") OR interpolation (e.g. "${DB_HOST}")
# It should NOT have "=dev-db"
if echo "$YAML_CONTENT" | grep -q "DB_HOST=dev-db"; then
    YAML_FIXED="false"
elif echo "$YAML_CONTENT" | grep -q "DB_PASSWORD=devpass"; then
    YAML_FIXED="false"
else
    # Simple check: pass if hardcodes are gone.
    # We rely on Runtime check (ENV_JSON) to prove it actually works.
    YAML_FIXED="true"
fi

# 5. Export JSON
cat > /tmp/env_debug_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "container_running": $CONTAINER_RUNNING,
    "env_host": "$HOST_VALUE",
    "env_pass": "$PASS_VALUE",
    "env_region": "$REGION_VALUE",
    "log_success": $LOG_SUCCESS,
    "yaml_fixed_static": $YAML_FIXED,
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "Result saved to /tmp/env_debug_result.json"
cat /tmp/env_debug_result.json
echo "=== Export Complete ==="