#!/bin/bash
echo "=== Exporting Containerize Host Integration Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

PROJECT_DIR="/home/ga/Documents/docker-projects/migration-task"
RESULT_FILE="/tmp/task_result.json"

# 1. Check if legacy server is still running on host
LEGACY_RUNNING=$(pgrep -f "legacy_server.py" > /dev/null && echo "true" || echo "false")

# 2. Check if frontend container is running
CONTAINER_RUNNING=$(docker ps --filter "name=frontend-app" --format '{{.Status}}' | grep -q "Up" && echo "true" || echo "false")

# 3. Check App Integrity (Did user modify source code?)
CURRENT_CHECKSUM=$(md5sum "$PROJECT_DIR/app/app.py" 2>/dev/null || echo "deleted")
INITIAL_CHECKSUM=$(cat /tmp/app_checksum.txt 2>/dev/null || echo "missing")
CODE_MODIFIED="true"
if [ "$CURRENT_CHECKSUM" == "$INITIAL_CHECKSUM" ]; then
    CODE_MODIFIED="false"
fi

# 4. Functional Test: Curl the frontend
FRONTEND_RESPONSE_CODE="000"
FRONTEND_RESPONSE_BODY=""
if [ "$CONTAINER_RUNNING" == "true" ]; then
    FRONTEND_RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>/dev/null || echo "000")
    FRONTEND_RESPONSE_BODY=$(curl -s http://localhost:8080/ 2>/dev/null || echo "")
fi

# 5. Configuration Inspection: Check extra_hosts
EXTRA_HOSTS_CONFIGURED="false"
HOST_MAPPING=""
if [ "$CONTAINER_RUNNING" == "true" ]; then
    # Inspect HostConfig.ExtraHosts
    # Expected format in inspection: "backend.legacy.internal:host-gateway" (resolved IP may appear depending on docker version)
    HOST_MAPPING=$(docker inspect frontend-app --format '{{json .HostConfig.ExtraHosts}}' 2>/dev/null)
    
    # Check if target hostname is in the mapping
    if echo "$HOST_MAPPING" | grep -q "backend.legacy.internal"; then
        EXTRA_HOSTS_CONFIGURED="true"
    fi
fi

# 6. Check if Docker Compose file was modified
COMPOSE_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
COMPOSE_MTIME=$(stat -c %Y "$PROJECT_DIR/docker-compose.yml" 2>/dev/null || echo "0")

if [ "$COMPOSE_MTIME" -gt "$TASK_START" ]; then
    COMPOSE_MODIFIED="true"
fi

# Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "legacy_server_running": $LEGACY_RUNNING,
    "container_running": $CONTAINER_RUNNING,
    "code_modified": $CODE_MODIFIED,
    "compose_modified": $COMPOSE_MODIFIED,
    "frontend_http_code": "$FRONTEND_RESPONSE_CODE",
    "frontend_response_body": $(echo "$FRONTEND_RESPONSE_BODY" | jq -R .),
    "extra_hosts_configured": $EXTRA_HOSTS_CONFIGURED,
    "host_mapping_raw": $(echo "$HOST_MAPPING" | jq -R .),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="