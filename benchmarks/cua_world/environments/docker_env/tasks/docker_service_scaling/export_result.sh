#!/bin/bash
# Export script for docker_service_scaling task

echo "=== Exporting Docker Service Scaling Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/projects/acme-storefront"

# 1. Check Replica Count
echo "Checking API replicas..."
API_REPLICAS=$(docker compose -f "$PROJECT_DIR/docker-compose.yml" ps --format json 2>/dev/null | grep -c "\"Service\": \"api\"" || echo "0")
echo "Found $API_REPLICAS API replicas."

# 2. Verify Load Balancing (Curl Test)
echo "Testing load balancing..."
HOSTNAMES_JSON="[]"
DISTINCT_COUNT=0
API_WORKS=0

if [ "$API_REPLICAS" -gt 0 ]; then
    # Curl 20 times to get distribution
    HOSTNAMES=$(for i in {1..20}; do curl -sI http://localhost:8080/api/health | grep -i "X-Served-By" | awk '{print $2}' | tr -d '\r'; done | sort | uniq)
    
    # Count distinct hostnames
    if [ -n "$HOSTNAMES" ]; then
        DISTINCT_COUNT=$(echo "$HOSTNAMES" | wc -l)
        # Convert to JSON array
        HOSTNAMES_JSON=$(echo "$HOSTNAMES" | python3 -c 'import sys, json; print(json.dumps([l.strip() for l in sys.stdin]))')
        API_WORKS=1
    fi
fi
echo "Distinct hostnames observed: $DISTINCT_COUNT"

# 3. Failover Test
echo "Testing failover..."
FAILOVER_SUCCESS="false"
if [ "$API_REPLICAS" -ge 2 ]; then
    # Find one API container ID
    CONTAINER_TO_KILL=$(docker ps --filter "name=acme-storefront-api-" -q | head -1)
    
    if [ -n "$CONTAINER_TO_KILL" ]; then
        echo "Stopping container $CONTAINER_TO_KILL..."
        docker stop "$CONTAINER_TO_KILL" >/dev/null
        sleep 3
        
        # Test if API still responds
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/health || echo "000")
        if [ "$HTTP_CODE" = "200" ]; then
            FAILOVER_SUCCESS="true"
            echo "Failover test PASSED: API returned 200 after stopping one replica."
        else
            echo "Failover test FAILED: API returned $HTTP_CODE."
        fi
        
        # Restart it to be nice (optional)
        docker start "$CONTAINER_TO_KILL" >/dev/null
    else
        echo "Could not find container to kill."
    fi
else
    echo "Skipping failover test (not enough replicas)."
fi

# 4. Check Nginx Config Content
echo "Checking Nginx configuration..."
NGINX_CONF="$PROJECT_DIR/nginx/nginx.conf"
HAS_RESOLVER="false"
HAS_UPSTREAM="false"
HAS_VARIABLES="false"

if [ -f "$NGINX_CONF" ]; then
    grep -q "resolver 127.0.0.11" "$NGINX_CONF" && HAS_RESOLVER="true"
    grep -q "upstream" "$NGINX_CONF" && HAS_UPSTREAM="true"
    # Check for variable usage which forces resolution, e.g., set $backend ... proxy_pass $backend
    grep -E "set \\$.*;.*proxy_pass \\$" "$NGINX_CONF" && HAS_VARIABLES="true"
fi

# 5. Check Report
REPORT_PATH="/home/ga/Desktop/scaling_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo "0")
fi

# Prepare result JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "api_replicas": $API_REPLICAS,
    "distinct_hostnames_count": $DISTINCT_COUNT,
    "observed_hostnames": $HOSTNAMES_JSON,
    "api_working": $API_WORKS,
    "failover_success": $FAILOVER_SUCCESS,
    "nginx_has_resolver": $HAS_RESOLVER,
    "nginx_has_upstream": $HAS_UPSTREAM,
    "nginx_has_variables": $HAS_VARIABLES,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="