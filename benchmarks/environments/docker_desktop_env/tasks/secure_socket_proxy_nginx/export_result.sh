#!/bin/bash
echo "=== Exporting Secure Socket Proxy Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

PROJECT_DIR="/home/ga/Documents/docker-projects/monitor-stack"
cd "$PROJECT_DIR" || exit 1

# 1. Identify containers
# We use docker compose ps to find the actual IDs regardless of naming
MONITOR_ID=$(docker compose ps -q monitor 2>/dev/null || echo "")
PROXY_ID=$(docker compose ps -q proxy 2>/dev/null || echo "")

echo "Monitor ID: $MONITOR_ID"
echo "Proxy ID: $PROXY_ID"

# 2. Check Socket Mounts
MONITOR_HAS_SOCKET="false"
if [ -n "$MONITOR_ID" ]; then
    if docker inspect "$MONITOR_ID" | grep -q "/var/run/docker.sock"; then
        MONITOR_HAS_SOCKET="true"
    fi
fi

PROXY_HAS_SOCKET="false"
if [ -n "$PROXY_ID" ]; then
    if docker inspect "$PROXY_ID" | grep -q "/var/run/docker.sock"; then
        PROXY_HAS_SOCKET="true"
    fi
fi

# 3. Functional Testing (Connectivity & Security)
# We execute these checks from INSIDE the monitor container (or a temp one) 
# to verify internal docker network connectivity.
CONNECTIVITY_TEST_PASSED="false"
SECURITY_TEST_PASSED="false"
HTTP_CODE_GET="000"
HTTP_CODE_POST="000"

if [ -n "$MONITOR_ID" ] && [ -n "$PROXY_ID" ]; then
    # Get the proxy hostname that monitor is using
    # It should be 'proxy' or whatever the service name is.
    # We'll assume the agent configured DOCKER_HOST.
    
    # Check DOCKER_HOST env in monitor
    MONITOR_ENV=$(docker inspect "$MONITOR_ID" --format '{{range .Config.Env}}{{println .}}{{end}}')
    DOCKER_HOST_VAL=$(echo "$MONITOR_ENV" | grep "DOCKER_HOST" | cut -d= -f2 || echo "")
    
    echo "Monitor DOCKER_HOST: $DOCKER_HOST_VAL"

    if [[ "$DOCKER_HOST_VAL" == tcp://* ]]; then
        # Extract host:port
        TARGET=$(echo "$DOCKER_HOST_VAL" | sed 's/tcp:\/\///')
        
        # Test GET (Should be 200)
        echo "Testing GET request to $TARGET..."
        HTTP_CODE_GET=$(docker exec "$MONITOR_ID" curl -s -o /dev/null -w "%{http_code}" "http://$TARGET/containers/json" || echo "000")
        
        # Test POST (Should be 403, 405, or 401 - Blocked)
        echo "Testing POST request to $TARGET..."
        # Trying to create a container (requires POST)
        HTTP_CODE_POST=$(docker exec "$MONITOR_ID" curl -s -o /dev/null -w "%{http_code}" -X POST "http://$TARGET/containers/create" || echo "000")
        
        if [ "$HTTP_CODE_GET" == "200" ]; then
            CONNECTIVITY_TEST_PASSED="true"
        fi
        
        # Acceptable blocking codes: 403 Forbidden, 405 Method Not Allowed, 401 Unauthorized (if configured)
        # 200/201 would be a FAIL (security breach)
        if [[ "$HTTP_CODE_POST" == "403" || "$HTTP_CODE_POST" == "405" || "$HTTP_CODE_POST" == "401" ]]; then
            SECURITY_TEST_PASSED="true"
        fi
    fi
fi

# 4. Log Analysis
# Check if monitor is happy
MONITOR_LOGS_OK="false"
if [ -n "$MONITOR_ID" ]; then
    # Look for success message in the last 20 lines
    if docker logs --tail 20 "$MONITOR_ID" 2>&1 | grep -q "Successfully retrieved container count"; then
        MONITOR_LOGS_OK="true"
    fi
fi

# 5. Check if Nginx config exists (sanity check)
NGINX_CONF_FOUND="false"
if [ -n "$PROXY_ID" ]; then
    # Check if a custom config is mounted or present
    if docker exec "$PROXY_ID" ls /etc/nginx/conf.d/default.conf >/dev/null 2>&1 || \
       docker exec "$PROXY_ID" ls /etc/nginx/nginx.conf >/dev/null 2>&1; then
        NGINX_CONF_FOUND="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "monitor_running": $([ -n "$MONITOR_ID" ] && echo "true" || echo "false"),
    "proxy_running": $([ -n "$PROXY_ID" ] && echo "true" || echo "false"),
    "monitor_has_socket": $MONITOR_HAS_SOCKET,
    "proxy_has_socket": $PROXY_HAS_SOCKET,
    "connectivity_passed": $CONNECTIVITY_TEST_PASSED,
    "security_test_passed": $SECURITY_TEST_PASSED,
    "http_get_code": "$HTTP_CODE_GET",
    "http_post_code": "$HTTP_CODE_POST",
    "monitor_logs_ok": $MONITOR_LOGS_OK,
    "nginx_conf_found": $NGINX_CONF_FOUND,
    "docker_host_env": "$DOCKER_HOST_VAL",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export Complete ==="