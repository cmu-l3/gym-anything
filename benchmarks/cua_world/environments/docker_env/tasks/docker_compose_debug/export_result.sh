#!/bin/bash
# Export script for docker_compose_debug task

echo "=== Exporting Docker Compose Debug Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Check which services are running
DB_RUNNING=0
docker ps --format '{{.Names}}' | grep -qx "acme-db" && DB_RUNNING=1
CACHE_RUNNING=0
docker ps --format '{{.Names}}' | grep -qx "acme-cache" && CACHE_RUNNING=1
API_RUNNING=0
docker ps --format '{{.Names}}' | grep -qx "acme-api" && API_RUNNING=1
NGINX_RUNNING=0
docker ps --format '{{.Names}}' | grep -qx "acme-nginx" && NGINX_RUNNING=1
WORKER_RUNNING=0
docker ps --format '{{.Names}}' | grep -qx "acme-worker" && WORKER_RUNNING=1

# Get health status
DB_HEALTHY=0
DB_HEALTH=$(docker inspect acme-db --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")
[ "$DB_HEALTH" = "healthy" ] && DB_HEALTHY=1

CACHE_HEALTHY=0
CACHE_HEALTH=$(docker inspect acme-cache --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")
[ "$CACHE_HEALTH" = "healthy" ] && CACHE_HEALTHY=1

API_HEALTHY=0
API_HEALTH=$(docker inspect acme-api --format '{{.State.Health.Status}}' 2>/dev/null || echo "none")
[ "$API_HEALTH" = "healthy" ] && API_HEALTHY=1

# Wait up to 30s for services to stabilize before testing endpoint
if [ "$NGINX_RUNNING" = "1" ] && [ "$API_RUNNING" = "1" ]; then
    sleep 5
fi

# Test the API through nginx
API_RESPONDS=0
API_STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/products 2>/dev/null || echo "000")
[ "$API_STATUS_CODE" = "200" ] && API_RESPONDS=1

API_RESPONSE_BODY=""
if [ "$API_RESPONDS" = "1" ]; then
    API_RESPONSE_BODY=$(curl -s http://localhost:8080/api/products 2>/dev/null | head -c 500 || echo "")
fi

# Check if response has products array
HAS_PRODUCTS_JSON=0
echo "$API_RESPONSE_BODY" | grep -qi "products\|laptop\|mouse\|keyboard" && HAS_PRODUCTS_JSON=1

# Inspect docker-compose.yml for the specific bugs being fixed
COMPOSE_FILE="/home/ga/projects/ecommerce-app/docker-compose.yml"
BUG1_FIXED=0   # POSTGRES_DB used (not POSTGRES_DATABASE)
BUG2_FIXED=0   # api uses app-network (not backend-net)
BUG3_FIXED=0   # REDIS_URL scheme correct
BUG4_FIXED=0   # nginx upstream port is 3000
BUG5_FIXED=0   # worker command correct

if [ -f "$COMPOSE_FILE" ]; then
    grep -q "POSTGRES_DB:" "$COMPOSE_FILE" 2>/dev/null && BUG1_FIXED=1
    # Bug 2: no reference to non-existent backend-net
    grep -q "backend-net" "$COMPOSE_FILE" 2>/dev/null || BUG2_FIXED=1
    grep -qi "redis://cache:6379\|redis://cache:" "$COMPOSE_FILE" 2>/dev/null && BUG3_FIXED=1
    grep -q "worker.tasks" "$COMPOSE_FILE" 2>/dev/null && BUG5_FIXED=1
fi

NGINX_CONF="/home/ga/projects/ecommerce-app/nginx/nginx.conf"
if [ -f "$NGINX_CONF" ]; then
    grep -q "api:3000" "$NGINX_CONF" 2>/dev/null && BUG4_FIXED=1
fi

cat > /tmp/docker_compose_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "db_running": $DB_RUNNING,
    "db_healthy": $DB_HEALTHY,
    "cache_running": $CACHE_RUNNING,
    "cache_healthy": $CACHE_HEALTHY,
    "api_running": $API_RUNNING,
    "api_healthy": $API_HEALTHY,
    "nginx_running": $NGINX_RUNNING,
    "worker_running": $WORKER_RUNNING,
    "api_responds": $API_RESPONDS,
    "api_status_code": "$API_STATUS_CODE",
    "has_products_json": $HAS_PRODUCTS_JSON,
    "bug1_fixed_postgres_db": $BUG1_FIXED,
    "bug2_fixed_network": $BUG2_FIXED,
    "bug3_fixed_redis_url": $BUG3_FIXED,
    "bug4_fixed_nginx_port": $BUG4_FIXED,
    "bug5_fixed_worker_cmd": $BUG5_FIXED,
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "Compose debug results:"
cat /tmp/docker_compose_result.json
echo "=== Export Complete ==="
