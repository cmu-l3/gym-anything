#!/bin/bash
echo "=== Exporting broken_compose_diagnosis Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

APP_DIR="/home/ga/app-debug"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# --- Check compose file modification time ---
COMPOSE_FILE="$APP_DIR/docker-compose.yml"
COMPOSE_MODIFIED="false"
if [ -f "$COMPOSE_FILE" ]; then
    COMPOSE_MTIME=$(stat -c %Y "$COMPOSE_FILE" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(cat /tmp/initial_compose_mtime 2>/dev/null || echo "0")
    if [ "$COMPOSE_MTIME" -gt "$INITIAL_MTIME" ] && [ "$TASK_START" -gt "0" ]; then
        COMPOSE_MODIFIED="true"
    fi
fi

# --- Check running services via docker compose ---
cd "$APP_DIR" 2>/dev/null || { echo "App dir missing"; cd /tmp; }

FLASK_RUNNING="false"
NGINX_RUNNING="false"
DB_RUNNING="false"

if docker compose ps --format "{{.Service}}:{{.State}}" 2>/dev/null | grep -q "flask:running"; then
    FLASK_RUNNING="true"
fi
if docker compose ps --format "{{.Service}}:{{.State}}" 2>/dev/null | grep -q "nginx:running"; then
    NGINX_RUNNING="true"
fi
if docker compose ps --format "{{.Service}}:{{.State}}" 2>/dev/null | grep -q "db:running"; then
    DB_RUNNING="true"
fi

# Also check with alternative docker ps (handles different compose versions)
if [ "$FLASK_RUNNING" = "false" ]; then
    if docker ps --format "{{.Names}}:{{.Status}}" 2>/dev/null | grep -iE "flask.*Up|appDebug.*flask|app-debug.*flask" | grep -q "Up"; then
        FLASK_RUNNING="true"
    fi
fi
if [ "$NGINX_RUNNING" = "false" ]; then
    if docker ps --format "{{.Names}}:{{.Status}}" 2>/dev/null | grep -iE "nginx.*Up|appDebug.*nginx|app-debug.*nginx" | grep -q "Up"; then
        NGINX_RUNNING="true"
    fi
fi
if [ "$DB_RUNNING" = "false" ]; then
    if docker ps --format "{{.Names}}:{{.Status}}" 2>/dev/null | grep -iE "db.*Up|appDebug.*db|app-debug.*db|mysql.*Up" | grep -q "Up"; then
        DB_RUNNING="true"
    fi
fi

# --- Check nginx accessibility ---
NGINX_HTTP_CODE="000"
for i in 1 2 3 4 5; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 http://localhost:8080 2>/dev/null || echo "000")
    if [ "$CODE" = "200" ] || [ "$CODE" = "302" ] || [ "$CODE" = "301" ]; then
        NGINX_HTTP_CODE="$CODE"
        break
    fi
    sleep 2
done

# --- Check flask container MYSQL_HOST env var ---
FLASK_MYSQL_HOST=""
FLASK_CONTAINER=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -iE "flask" | head -1)
if [ -n "$FLASK_CONTAINER" ]; then
    FLASK_MYSQL_HOST=$(docker inspect "$FLASK_CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep "MYSQL_HOST" | cut -d= -f2 | tr -d ' \n\r')
fi

# --- Check flask container network membership ---
FLASK_ON_BACKNET="false"
if [ -n "$FLASK_CONTAINER" ]; then
    FLASK_NETWORKS=$(docker inspect "$FLASK_CONTAINER" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "")
    if echo "$FLASK_NETWORKS" | grep -qi "backnet\|back"; then
        FLASK_ON_BACKNET="true"
    fi
fi

# --- Check volumes section in compose file ---
HAS_VOLUMES_SECTION="false"
if grep -qE "^volumes:" "$COMPOSE_FILE" 2>/dev/null; then
    HAS_VOLUMES_SECTION="true"
fi

# --- Current running count ---
CURRENT_RUNNING=$(docker ps --format "{{.Names}}" 2>/dev/null | wc -l | tr -d ' ')
INITIAL_RUNNING=$(cat /tmp/initial_running_count 2>/dev/null || echo "0")

# Write result JSON
cat > /tmp/broken_compose_diagnosis_result.json << JSONEOF
{
    "flask_running": $FLASK_RUNNING,
    "nginx_running": $NGINX_RUNNING,
    "db_running": $DB_RUNNING,
    "nginx_http_code": "$NGINX_HTTP_CODE",
    "flask_mysql_host": "$FLASK_MYSQL_HOST",
    "flask_on_backnet": $FLASK_ON_BACKNET,
    "has_volumes_section": $HAS_VOLUMES_SECTION,
    "compose_modified": $COMPOSE_MODIFIED,
    "initial_running": $INITIAL_RUNNING,
    "current_running": $CURRENT_RUNNING,
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "=== Export Complete ==="
cat /tmp/broken_compose_diagnosis_result.json
