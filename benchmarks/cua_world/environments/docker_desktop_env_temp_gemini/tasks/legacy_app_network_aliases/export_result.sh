#!/bin/bash
# Export script for legacy_app_network_aliases task

echo "=== Exporting legacy_app_network_aliases result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

PROJECT_DIR="/home/ga/legacy-migration"
cd "$PROJECT_DIR" || exit 1

# Check file modification
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
COMPOSE_MODIFIED="false"
if [ -f "$COMPOSE_FILE" ]; then
    MTIME=$(stat -c %Y "$COMPOSE_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        COMPOSE_MODIFIED="true"
    fi
fi

# Get container IDs
APP_ID=$(docker compose ps -q app 2>/dev/null || echo "")
DB_ID=$(docker compose ps -q postgres 2>/dev/null || echo "")
REDIS_ID=$(docker compose ps -q redis 2>/dev/null || echo "")
AUTH_ID=$(docker compose ps -q mock-auth 2>/dev/null || echo "")

# Check App Status
APP_RUNNING="false"
APP_LOGS=""
if [ -n "$APP_ID" ]; then
    STATUS=$(docker inspect --format '{{.State.Status}}' "$APP_ID" 2>/dev/null)
    if [ "$STATUS" == "running" ]; then
        APP_RUNNING="true"
    fi
    # Get recent logs to check for success message
    APP_LOGS=$(docker logs "$APP_ID" 2>&1 | tail -n 20)
fi

# Check Network Aliases
# We inspect each dependency container to see if it has the correct alias on ANY network
check_alias() {
    local container_id="$1"
    local expected_alias="$2"
    
    if [ -z "$container_id" ]; then
        echo "false"
        return
    fi
    
    # Inspect network settings and look for the alias in the Aliases array of any network
    if docker inspect "$container_id" --format '{{range .NetworkSettings.Networks}}{{println .Aliases}}{{end}}' 2>/dev/null | grep -q "$expected_alias"; then
        echo "true"
    else
        echo "false"
    fi
}

DB_ALIAS_CORRECT=$(check_alias "$DB_ID" "db.inventory.local")
REDIS_ALIAS_CORRECT=$(check_alias "$REDIS_ID" "cache.inventory.local")
AUTH_ALIAS_CORRECT=$(check_alias "$AUTH_ID" "auth.provider.external")

# Manual DNS resolution check from inside app container (if running)
DNS_CHECK_SUCCESS="false"
if [ "$APP_RUNNING" == "true" ]; then
    if docker exec "$APP_ID" getent hosts db.inventory.local >/dev/null 2>&1; then
        DNS_CHECK_SUCCESS="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "app_running": $APP_RUNNING,
    "compose_modified": $COMPOSE_MODIFIED,
    "db_alias_correct": $DB_ALIAS_CORRECT,
    "redis_alias_correct": $REDIS_ALIAS_CORRECT,
    "auth_alias_correct": $AUTH_ALIAS_CORRECT,
    "dns_check_success": $DNS_CHECK_SUCCESS,
    "app_logs": $(echo "$APP_LOGS" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
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