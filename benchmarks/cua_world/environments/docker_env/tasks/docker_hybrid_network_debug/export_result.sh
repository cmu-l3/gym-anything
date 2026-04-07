#!/bin/bash
echo "=== Exporting Hybrid Network Debug Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/projects/hybrid-migration"

# 1. Functional Test: Curl the Frontend
# We expect the full chain: Frontend -> Backend -> Host
RESPONSE_BODY=$(curl -s --max-time 5 http://localhost:8080 || echo "")
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:8080 || echo "000")

# Check if response contains data from Legacy Service
HAS_LEGACY_DATA=0
if echo "$RESPONSE_BODY" | grep -q "Retro Lamp"; then
    HAS_LEGACY_DATA=1
fi

# Check if response contains data from Frontend
HAS_FRONTEND_DATA=0
if echo "$RESPONSE_BODY" | grep -q "Shop Frontend"; then
    HAS_FRONTEND_DATA=1
fi

# 2. Configuration Inspection

# Check Backend Configuration (Host Access)
BACKEND_INSPECT=$(docker inspect shop-backend 2>/dev/null || echo "{}")
# Check for extra_hosts (host.docker.internal:host-gateway)
HAS_EXTRA_HOSTS=0
if echo "$BACKEND_INSPECT" | grep -q "host-gateway"; then
    HAS_EXTRA_HOSTS=1
fi
# Check env var for host address
HAS_CORRECT_INVENTORY_URL=0
if echo "$BACKEND_INSPECT" | grep -q "host.docker.internal"; then
    HAS_CORRECT_INVENTORY_URL=1
# Allow raw IP usage (172.17.0.1 is default docker bridge gateway)
elif echo "$BACKEND_INSPECT" | grep -q "172.17.0.1"; then
    HAS_CORRECT_INVENTORY_URL=1
fi

# Check Frontend Configuration (Service Discovery & Port)
FRONTEND_INSPECT=$(docker inspect shop-frontend 2>/dev/null || echo "{}")
# Check Port Mapping (8080->3000)
HAS_CORRECT_PORT_MAP=0
if echo "$FRONTEND_INSPECT" | grep -q '"HostPort": "8080"' && echo "$FRONTEND_INSPECT" | grep -q '"ContainerPort": "3000"'; then
    HAS_CORRECT_PORT_MAP=1
fi
# Check Env Var (Service Discovery)
HAS_CORRECT_API_URL=0
if echo "$FRONTEND_INSPECT" | grep -q "shop-backend"; then
    HAS_CORRECT_API_URL=1
fi

# 3. Check Host Service Status
HOST_SERVICE_RUNNING=0
if pgrep -f "legacy_inventory.py" > /dev/null; then
    HOST_SERVICE_RUNNING=1
fi

# 4. Generate Result JSON
cat > /tmp/hybrid_network_result.json <<EOF
{
  "task_start": $TASK_START,
  "http_code": "$HTTP_CODE",
  "has_legacy_data": $HAS_LEGACY_DATA,
  "has_frontend_data": $HAS_FRONTEND_DATA,
  "backend_extra_hosts": $HAS_EXTRA_HOSTS,
  "backend_inventory_url_fixed": $HAS_CORRECT_INVENTORY_URL,
  "frontend_port_map_fixed": $HAS_CORRECT_PORT_MAP,
  "frontend_api_url_fixed": $HAS_CORRECT_API_URL,
  "host_service_running": $HOST_SERVICE_RUNNING,
  "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result generated:"
cat /tmp/hybrid_network_result.json
echo "=== Export Complete ==="