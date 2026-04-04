#!/bin/bash
# Export script for entrypoint_debugging task

echo "=== Exporting entrypoint_debugging result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/entrypoint-debug"
cd "$PROJECT_DIR" || exit 1

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Container Status
# -----------------------
GATEWAY_STATUS=$(docker compose ps --format '{{.State}}' gateway 2>/dev/null || echo "missing")
API_STATUS=$(docker compose ps --format '{{.State}}' api 2>/dev/null || echo "missing")
WORKER_STATUS=$(docker compose ps --format '{{.State}}' worker 2>/dev/null || echo "missing")

# 2. Check Service Functionality
# ----------------------------

# Gateway (should return 200)
GATEWAY_HTTP=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 http://localhost:8080 2>/dev/null || echo "000")

# API (should return 200 and JSON)
API_RESPONSE=$(curl -s --connect-timeout 2 http://localhost:5000/health 2>/dev/null || echo "")
API_HEALTHY="false"
if echo "$API_RESPONSE" | grep -q "ok"; then
    API_HEALTHY="true"
fi

# Worker (logs should show interval=5, not default 60)
WORKER_LOGS=$(docker compose logs worker --tail=20 2>&1)
WORKER_INTERVAL_CORRECT="false"
if echo "$WORKER_LOGS" | grep -q "interval=5"; then
    WORKER_INTERVAL_CORRECT="true"
fi

# 3. Check for specific fixes (Implementation checks)
# -------------------------------------------------

# Gateway: Check if entrypoint is executable inside image
GATEWAY_EXEC_CHECK="false"
if [ "$GATEWAY_STATUS" = "running" ]; then
    if docker compose exec gateway test -x /entrypoint.sh; then
        GATEWAY_EXEC_CHECK="true"
    fi
fi

# API: Check if bound to 0.0.0.0
API_BIND_CHECK="false"
if [ "$API_STATUS" = "running" ]; then
    # Check netstat/ss inside container or check logs for binding address
    API_LOGS=$(docker compose logs api --tail=20 2>&1)
    if echo "$API_LOGS" | grep -q "0.0.0.0"; then
        API_BIND_CHECK="true"
    fi
fi

# Worker: Check Dockerfile for exec form ENTRYPOINT
# Look for ["..."] brackets
WORKER_DOCKERFILE_FIXED="false"
if grep -qE 'ENTRYPOINT\s*\[' "$PROJECT_DIR/worker/Dockerfile"; then
    WORKER_DOCKERFILE_FIXED="true"
fi

# 4. Anti-Gaming (File modification checks)
# ---------------------------------------
INITIAL_GATEWAY_MTIME=$(cat /tmp/initial_gateway_dockerfile_mtime 2>/dev/null || echo "0")
CURRENT_GATEWAY_MTIME=$(stat -c %Y "$PROJECT_DIR/gateway/Dockerfile" 2>/dev/null || echo "0")

INITIAL_API_MTIME=$(cat /tmp/initial_api_dockerfile_mtime 2>/dev/null || echo "0")
CURRENT_API_MTIME=$(stat -c %Y "$PROJECT_DIR/api/Dockerfile" 2>/dev/null || echo "0")

INITIAL_WORKER_MTIME=$(cat /tmp/initial_worker_dockerfile_mtime 2>/dev/null || echo "0")
CURRENT_WORKER_MTIME=$(stat -c %Y "$PROJECT_DIR/worker/Dockerfile" 2>/dev/null || echo "0")

FILES_MODIFIED="false"
if [ "$CURRENT_GATEWAY_MTIME" != "$INITIAL_GATEWAY_MTIME" ] || \
   [ "$CURRENT_API_MTIME" != "$INITIAL_API_MTIME" ] || \
   [ "$CURRENT_WORKER_MTIME" != "$INITIAL_WORKER_MTIME" ]; then
    FILES_MODIFIED="true"
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "gateway_status": "$GATEWAY_STATUS",
    "api_status": "$API_STATUS",
    "worker_status": "$WORKER_STATUS",
    "gateway_http_code": "$GATEWAY_HTTP",
    "api_healthy": $API_HEALTHY,
    "worker_interval_correct": $WORKER_INTERVAL_CORRECT,
    "gateway_exec_fix": $GATEWAY_EXEC_CHECK,
    "api_bind_fix": $API_BIND_CHECK,
    "worker_dockerfile_fix": $WORKER_DOCKERFILE_FIXED,
    "files_modified": $FILES_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="