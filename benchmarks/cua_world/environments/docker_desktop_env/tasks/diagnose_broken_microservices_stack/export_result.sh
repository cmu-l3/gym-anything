#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting diagnose_broken_microservices_stack results ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

PROJECT_DIR="/home/ga/microservices-debug"
cd "$PROJECT_DIR" 2>/dev/null || cd /home/ga 2>/dev/null || true

# Find which Docker daemon has our compose containers.
# Try: (1) current DOCKER_HOST from task_utils.sh, (2) Docker Desktop socket,
# (3) system Docker socket.
_has_compose_containers() {
    timeout 5 docker compose -f "$PROJECT_DIR/docker-compose.yml" ps -q 2>/dev/null | head -1 | grep -q .
}
if ! _has_compose_containers; then
    # Try Docker Desktop socket explicitly
    export DOCKER_HOST=unix:///home/ga/.docker/desktop/docker.sock
    if ! _has_compose_containers; then
        # Try system Docker socket
        export DOCKER_HOST=unix:///var/run/docker.sock
        if ! _has_compose_containers; then
            # Last resort: unset and let Docker choose
            unset DOCKER_HOST
        fi
    fi
fi
echo "export_result.sh using DOCKER_HOST=${DOCKER_HOST:-default}"

# Clean stale intermediate files from any previous runs
rm -f /tmp/health_response.json /tmp/items_response.json 2>/dev/null || true

# ================================================================
# Check which services are running
# ================================================================
NGINX_RUNNING=$(docker compose -f "$PROJECT_DIR/docker-compose.yml" ps --format '{{.State}}' nginx 2>/dev/null | head -1 | grep -qi "running" && echo "true" || echo "false")
FLASK_RUNNING=$(docker compose -f "$PROJECT_DIR/docker-compose.yml" ps --format '{{.State}}' flask-app 2>/dev/null | head -1 | grep -qi "running" && echo "true" || echo "false")
DB_RUNNING=$(docker compose -f "$PROJECT_DIR/docker-compose.yml" ps --format '{{.State}}' db 2>/dev/null | head -1 | grep -qi "running" && echo "true" || echo "false")
REDIS_RUNNING=$(docker compose -f "$PROJECT_DIR/docker-compose.yml" ps --format '{{.State}}' redis 2>/dev/null | head -1 | grep -qi "running" && echo "true" || echo "false")

RUNNING_COUNT=0
[ "$NGINX_RUNNING" = "true" ] && RUNNING_COUNT=$((RUNNING_COUNT + 1))
[ "$FLASK_RUNNING" = "true" ] && RUNNING_COUNT=$((RUNNING_COUNT + 1))
[ "$DB_RUNNING" = "true" ] && RUNNING_COUNT=$((RUNNING_COUNT + 1))
[ "$REDIS_RUNNING" = "true" ] && RUNNING_COUNT=$((RUNNING_COUNT + 1))

# ================================================================
# Test health endpoint
# ================================================================
HEALTH_CODE=$(curl -s -o /tmp/health_response.json -w '%{http_code}' --max-time 10 http://localhost:80/api/health 2>/dev/null || echo "000")
HEALTH_BODY=$(cat /tmp/health_response.json 2>/dev/null || echo "{}")

# Parse health response fields safely
DB_STATUS=$(echo "$HEALTH_BODY" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('database', 'unknown'))
except:
    print('unknown')
" 2>/dev/null || echo "unknown")

CACHE_STATUS=$(echo "$HEALTH_BODY" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('cache', 'unknown'))
except:
    print('unknown')
" 2>/dev/null || echo "unknown")

OVERALL_STATUS=$(echo "$HEALTH_BODY" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('status', 'unknown'))
except:
    print('unknown')
" 2>/dev/null || echo "unknown")

# ================================================================
# Test items endpoint
# ================================================================
ITEMS_CODE=$(curl -s -o /tmp/items_response.json -w '%{http_code}' --max-time 10 http://localhost:80/api/items 2>/dev/null || echo "000")
ITEMS_BODY=$(cat /tmp/items_response.json 2>/dev/null || echo "[]")

ITEMS_COUNT=$(echo "$ITEMS_BODY" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(len(d) if isinstance(d, list) else 0)
except:
    print(0)
" 2>/dev/null || echo "0")

ITEMS_VALID=$(echo "$ITEMS_BODY" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    if isinstance(d, list) and len(d) >= 3:
        if all('id' in i and 'name' in i and 'price' in i for i in d):
            print('true')
        else:
            print('false')
    else:
        print('false')
except:
    print('false')
" 2>/dev/null || echo "false")

# ================================================================
# Check if config files were modified after task start
# ================================================================
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

COMPOSE_MODIFIED="false"
if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    COMPOSE_MTIME=$(stat -c %Y "$PROJECT_DIR/docker-compose.yml" 2>/dev/null || echo "0")
    if [ "$COMPOSE_MTIME" -gt "$START_TIME" ] 2>/dev/null; then
        COMPOSE_MODIFIED="true"
    fi
fi

NGINX_MODIFIED="false"
if [ -f "$PROJECT_DIR/nginx/nginx.conf" ]; then
    NGINX_MTIME=$(stat -c %Y "$PROJECT_DIR/nginx/nginx.conf" 2>/dev/null || echo "0")
    if [ "$NGINX_MTIME" -gt "$START_TIME" ] 2>/dev/null; then
        NGINX_MODIFIED="true"
    fi
fi

# ================================================================
# Write result JSON atomically
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << RESULTEOF
{
  "nginx_running": $NGINX_RUNNING,
  "flask_running": $FLASK_RUNNING,
  "db_running": $DB_RUNNING,
  "redis_running": $REDIS_RUNNING,
  "running_count": $RUNNING_COUNT,
  "health_http_code": "$HEALTH_CODE",
  "health_status": "$(json_escape "$OVERALL_STATUS")",
  "database_status": "$(json_escape "$DB_STATUS")",
  "cache_status": "$(json_escape "$CACHE_STATUS")",
  "items_http_code": "$ITEMS_CODE",
  "items_count": $ITEMS_COUNT,
  "items_valid": $ITEMS_VALID,
  "compose_modified": $COMPOSE_MODIFIED,
  "nginx_modified": $NGINX_MODIFIED
}
RESULTEOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
