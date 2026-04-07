#!/bin/bash
# Export script for docker_socket_proxy task

echo "=== Exporting Docker Socket Proxy Results ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/projects/monitor-stack"
cd "$PROJECT_DIR" || exit 1

# 1. Inspect 'dashboard' service
# Should NOT have the socket mounted anymore
DASHBOARD_ID=$(docker compose ps -q dashboard 2>/dev/null || echo "")
DASHBOARD_MOUNTS="[]"
DASHBOARD_ENV="[]"
DASHBOARD_RUNNING=0

if [ -n "$DASHBOARD_ID" ]; then
    DASHBOARD_RUNNING=1
    DASHBOARD_MOUNTS=$(docker inspect "$DASHBOARD_ID" --format '{{json .Mounts}}')
    DASHBOARD_ENV=$(docker inspect "$DASHBOARD_ID" --format '{{json .Config.Env}}')
fi

# Check if socket is in mounts
SOCKET_REMOVED=0
if ! echo "$DASHBOARD_MOUNTS" | grep -q "/var/run/docker.sock"; then
    SOCKET_REMOVED=1
fi

# Check if DOCKER_HOST is set to tcp://
PROXY_CONFIGURED=0
if echo "$DASHBOARD_ENV" | grep -q "DOCKER_HOST=tcp://"; then
    PROXY_CONFIGURED=1
fi

# 2. Inspect 'proxy' service
# Should exist, be running, and HAVE the socket mounted
PROXY_ID=$(docker compose ps -q proxy 2>/dev/null || echo "")
PROXY_RUNNING=0
PROXY_HAS_SOCKET=0

if [ -n "$PROXY_ID" ]; then
    PROXY_RUNNING=1
    PROXY_MOUNTS=$(docker inspect "$PROXY_ID" --format '{{json .Mounts}}')
    if echo "$PROXY_MOUNTS" | grep -q "/var/run/docker.sock"; then
        PROXY_HAS_SOCKET=1
    fi
fi

# 3. Functional Testing: Security Probe
# We launch a temporary tester container on the same network to curl the proxy
NETWORK_NAME=$(docker inspect "$DASHBOARD_ID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null || echo "monitor-stack_default")

echo "Probing proxy on network: $NETWORK_NAME"

# Probe 1: Allowed Request (GET /containers/json)
TEST_ALLOWED_CODE="000"
if [ "$PROXY_RUNNING" = "1" ]; then
    TEST_ALLOWED_CODE=$(docker run --rm --network "$NETWORK_NAME" curlimages/curl:latest \
        -s -o /dev/null -w "%{http_code}" \
        http://proxy:2375/containers/json || echo "error")
fi

# Probe 2: Blocked Method (POST /containers/create)
TEST_BLOCKED_METHOD_CODE="000"
if [ "$PROXY_RUNNING" = "1" ]; then
    TEST_BLOCKED_METHOD_CODE=$(docker run --rm --network "$NETWORK_NAME" curlimages/curl:latest \
        -s -o /dev/null -w "%{http_code}" -X POST \
        http://proxy:2375/containers/create || echo "error")
fi

# Probe 3: Blocked Path (GET /secrets)
TEST_BLOCKED_PATH_CODE="000"
if [ "$PROXY_RUNNING" = "1" ]; then
    TEST_BLOCKED_PATH_CODE=$(docker run --rm --network "$NETWORK_NAME" curlimages/curl:latest \
        -s -o /dev/null -w "%{http_code}" \
        http://proxy:2375/secrets || echo "error")
fi

# 4. Check Dashboard Logs for Success
# Look for recent "Monitoring X containers" messages
DASHBOARD_LOGS_OK=0
if [ "$DASHBOARD_RUNNING" = "1" ]; then
    # Check logs since last minute
    LOGS=$(docker compose logs --since 1m dashboard 2>&1)
    if echo "$LOGS" | grep -q "\[SUCCESS\]"; then
        DASHBOARD_LOGS_OK=1
    fi
fi

# 5. Check if nginx.conf exists and is mounted (heuristic)
NGINX_CONF_EXISTS=0
if [ -f "$PROJECT_DIR/nginx.conf" ]; then
    NGINX_CONF_EXISTS=1
fi

# Export result
cat > /tmp/socket_proxy_result.json <<EOF
{
    "task_start": $TASK_START,
    "dashboard_running": $DASHBOARD_RUNNING,
    "socket_removed_from_dashboard": $SOCKET_REMOVED,
    "dashboard_proxy_configured": $PROXY_CONFIGURED,
    "proxy_running": $PROXY_RUNNING,
    "proxy_has_socket": $PROXY_HAS_SOCKET,
    "test_allowed_code": "$TEST_ALLOWED_CODE",
    "test_blocked_method_code": "$TEST_BLOCKED_METHOD_CODE",
    "test_blocked_path_code": "$TEST_BLOCKED_PATH_CODE",
    "dashboard_logs_success": $DASHBOARD_LOGS_OK,
    "nginx_conf_exists": $NGINX_CONF_EXISTS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/socket_proxy_result.json
echo "=== Export Complete ==="