#!/bin/bash
# Export script for docker_cross_stack_networking task

echo "=== Exporting Cross-Stack Networking Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Functional Connectivity Test
echo "Testing connectivity..."
# We expect the storefront to return product data now
RESPONSE_BODY=$(curl -s http://localhost:3000 --max-time 5 || echo "")
HAS_PRODUCT_DATA=0
if echo "$RESPONSE_BODY" | grep -q "Quantum Widget"; then
    HAS_PRODUCT_DATA=1
    echo "SUCCESS: Product data found."
else
    echo "FAIL: Product data not found."
fi

# 2. Inspect Container Networking
echo "Inspecting containers..."

# Get network config for inventory-api
INV_NETWORKS=$(docker inspect inventory-api --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "")
# Get network config for storefront-web
STORE_NETWORKS=$(docker inspect storefront-web --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null || echo "")

# Find common networks (intersection)
COMMON_NETWORK=""
SHARED_NETWORK_EXISTS=0
for net in $INV_NETWORKS; do
    if [[ "$STORE_NETWORKS" == *"$net"* ]]; then
        # Ignore default networks created by compose (usually named <dir>_default)
        if [[ "$net" != *"_default"* ]] && [[ "$net" != "bridge" ]] && [[ "$net" != "host" ]] && [[ "$net" != "none" ]]; then
            COMMON_NETWORK="$net"
            SHARED_NETWORK_EXISTS=1
            break
        fi
    fi
done
echo "Common external network: $COMMON_NETWORK"

# 3. Check for Anti-Pattern: Host Networking
USING_HOST_NET=0
if [[ "$INV_NETWORKS" == *"host"* ]] || [[ "$STORE_NETWORKS" == *"host"* ]]; then
    USING_HOST_NET=1
    echo "WARNING: Host networking detected."
fi

# 4. Check Environment Variable Configuration
# The storefront should be using a hostname, not an IP or localhost
API_URL_ENV=$(docker inspect storefront-web --format '{{range .Config.Env}}{{ifWithPrefix . "API_URL="}}{{.}}{{end}}{{end}}' 2>/dev/null || echo "")
API_URL_VALUE=${API_URL_ENV#API_URL=}
echo "Storefront API_URL: $API_URL_VALUE"

API_URL_CORRECT=0
if [[ "$API_URL_VALUE" != *"localhost"* ]] && [[ "$API_URL_VALUE" != *"127.0.0.1"* ]] && [[ -n "$API_URL_VALUE" ]]; then
    # It should assume http if protocol not present, but usually expects http://<hostname>:5000
    API_URL_CORRECT=1
fi

# 5. Verify Compose Files Integrity (Are they still separate?)
INV_COMPOSE="/home/ga/projects/inventory-service/docker-compose.yml"
STORE_COMPOSE="/home/ga/projects/storefront-app/docker-compose.yml"
FILES_EXIST=0
if [ -f "$INV_COMPOSE" ] && [ -f "$STORE_COMPOSE" ]; then
    FILES_EXIST=1
fi

# 6. Verify containers are actually running
INV_RUNNING=0
STORE_RUNNING=0
docker ps --format '{{.Names}}' | grep -q "inventory-api" && INV_RUNNING=1
docker ps --format '{{.Names}}' | grep -q "storefront-web" && STORE_RUNNING=1

cat > /tmp/networking_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "has_product_data": $HAS_PRODUCT_DATA,
    "shared_network_exists": $SHARED_NETWORK_EXISTS,
    "common_network_name": "$COMMON_NETWORK",
    "using_host_net": $USING_HOST_NET,
    "api_url_value": "$API_URL_VALUE",
    "api_url_correct": $API_URL_CORRECT,
    "compose_files_separate": $FILES_EXIST,
    "inventory_running": $INV_RUNNING,
    "storefront_running": $STORE_RUNNING,
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "Result JSON written."
cat /tmp/networking_result.json
echo "=== Export Complete ==="