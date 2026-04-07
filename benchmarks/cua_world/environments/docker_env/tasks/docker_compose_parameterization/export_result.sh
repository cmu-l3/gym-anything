#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/projects/inventory-system"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
ENV_FILE="$PROJECT_DIR/.env.prod"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_TIME=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Capture File Contents (for static analysis)
COMPOSE_CONTENT=""
if [ -f "$COMPOSE_FILE" ]; then
    COMPOSE_CONTENT=$(cat "$COMPOSE_FILE" | base64 -w 0)
fi

ENV_CONTENT=""
if [ -f "$ENV_FILE" ]; then
    ENV_CONTENT=$(cat "$ENV_FILE" | base64 -w 0)
fi

# 2. Inspect Running Containers (Runtime verification)
# We look for containers that might belong to this project
DB_CONTAINER=$(docker ps -q --filter "name=inventory-db")
WEB_CONTAINER=$(docker ps -q --filter "name=inventory-web")

DB_INFO="{}"
WEB_INFO="{}"

if [ -n "$DB_CONTAINER" ]; then
    DB_INFO=$(docker inspect "$DB_CONTAINER" --format '{{json .}}')
fi

if [ -n "$WEB_CONTAINER" ]; then
    WEB_INFO=$(docker inspect "$WEB_CONTAINER" --format '{{json .}}')
fi

# 3. Check Connectivity
# Try to reach the app on Port 80 (Production requirement)
HTTP_STATUS_80=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 2>/dev/null || echo "000")
# Try to reach the app on Port 3000 (Dev default, shouldn't be accessible if mapped to 80, unless mapped to both)
HTTP_STATUS_3000=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")

# 4. Check App Response Content (to verify APP_MODE env var inside the app)
APP_RESPONSE=""
if [ "$HTTP_STATUS_80" == "200" ]; then
    APP_RESPONSE=$(curl -s http://localhost:80)
fi

# Create JSON Output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "task_start": $TASK_START,
  "export_time": $EXPORT_TIME,
  "compose_file_exists": $([ -f "$COMPOSE_FILE" ] && echo "true" || echo "false"),
  "env_file_exists": $([ -f "$ENV_FILE" ] && echo "true" || echo "false"),
  "compose_content_b64": "$COMPOSE_CONTENT",
  "env_content_b64": "$ENV_CONTENT",
  "db_container_running": $([ -n "$DB_CONTAINER" ] && echo "true" || echo "false"),
  "web_container_running": $([ -n "$WEB_CONTAINER" ] && echo "true" || echo "false"),
  "http_status_80": "$HTTP_STATUS_80",
  "http_status_3000": "$HTTP_STATUS_3000",
  "app_response_b64": "$(echo "$APP_RESPONSE" | base64 -w 0)",
  "db_inspect": $DB_INFO,
  "web_inspect": $WEB_INFO
}
EOF

# Safe move to export location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"