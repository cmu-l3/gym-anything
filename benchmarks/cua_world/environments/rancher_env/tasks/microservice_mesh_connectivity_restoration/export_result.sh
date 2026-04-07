#!/bin/bash
# Export script for microservice_mesh_connectivity_restoration
# Queries the ecommerce-platform namespace for connectivity state of each microservice

echo "=== Exporting microservice_mesh_connectivity_restoration result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/microservice_mesh_connectivity_restoration_end.png

TASK_START=$(cat /tmp/microservice_mesh_connectivity_restoration_start_ts 2>/dev/null || echo "0")

# ── Criterion 1: api-gateway Service must have >= 1 endpoint address ──────────
echo "Checking api-gateway Service endpoints..."

API_GW_ENDPOINTS=$(docker exec rancher kubectl get endpoints api-gateway -n ecommerce-platform \
    -o jsonpath='{.subsets[0].addresses}' 2>/dev/null || echo "")
API_GW_ENDPOINT_COUNT=0
if [ -n "$API_GW_ENDPOINTS" ] && [ "$API_GW_ENDPOINTS" != "null" ] && [ "$API_GW_ENDPOINTS" != "[]" ]; then
    API_GW_ENDPOINT_COUNT=$(docker exec rancher kubectl get endpoints api-gateway -n ecommerce-platform \
        -o jsonpath='{range .subsets[*]}{range .addresses[*]}{.ip}{"\n"}{end}{end}' 2>/dev/null | grep -c "." || echo "0")
fi
[ -z "$API_GW_ENDPOINT_COUNT" ] && API_GW_ENDPOINT_COUNT=0

# Also capture the Service selector for feedback
API_GW_SELECTOR=$(docker exec rancher kubectl get service api-gateway -n ecommerce-platform \
    -o jsonpath='{.spec.selector}' 2>/dev/null || echo "{}")

# ── Criterion 2: product-service INVENTORY_HOST must contain 'ecommerce-platform' ────
echo "Checking product-service env vars..."

INVENTORY_HOST=$(docker exec rancher kubectl get deployment product-service -n ecommerce-platform \
    -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="INVENTORY_HOST")].value}' 2>/dev/null || echo "")
[ -z "$INVENTORY_HOST" ] && INVENTORY_HOST="not-set"

# ── Criterion 3: NetworkPolicy must allow port 3000 egress from cart-service ──
echo "Checking NetworkPolicy for cart-service egress..."

# Get the restrict-cart-egress NetworkPolicy egress rules as JSON
CART_NETPOL_JSON=$(docker exec rancher kubectl get networkpolicy restrict-cart-egress \
    -n ecommerce-platform -o json 2>/dev/null || echo "{}")

# Check if port 3000 appears in egress rules
NETPOL_ALLOWS_3000=$(echo "$CART_NETPOL_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
egress = data.get('spec', {}).get('egress', [])
for rule in egress:
    ports = rule.get('ports', [])
    for p in ports:
        if str(p.get('port', '')) == '3000':
            print('true')
            sys.exit()
print('false')
" 2>/dev/null || echo "false")

# Check if the NetworkPolicy exists at all
NETPOL_EXISTS=$(docker exec rancher kubectl get networkpolicy restrict-cart-egress \
    -n ecommerce-platform --no-headers 2>/dev/null | grep -c "restrict-cart-egress" || echo "0")

# ── Criterion 4: payment-config ConfigMap NOTIFICATION_HOST must contain 'ecommerce-platform' ──
echo "Checking payment-config ConfigMap..."

NOTIFICATION_HOST=$(docker exec rancher kubectl get configmap payment-config \
    -n ecommerce-platform \
    -o jsonpath='{.data.NOTIFICATION_HOST}' 2>/dev/null || echo "")
[ -z "$NOTIFICATION_HOST" ] && NOTIFICATION_HOST="not-set"

# ── Criterion 5: inventory-db Service must expose port 5432 ──────────────────
echo "Checking inventory-db Service port..."

INVENTORY_DB_PORT=$(docker exec rancher kubectl get service inventory-db \
    -n ecommerce-platform \
    -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "")
[ -z "$INVENTORY_DB_PORT" ] && INVENTORY_DB_PORT="0"

# ── Check overall pod health ──────────────────────────────────────────────────
TOTAL_RUNNING=$(docker exec rancher kubectl get pods -n ecommerce-platform --no-headers 2>/dev/null | grep -c "Running" || true)
[ -z "$TOTAL_RUNNING" ] && TOTAL_RUNNING=0

# ── Write result JSON ─────────────────────────────────────────────────────────
cat > /tmp/microservice_mesh_connectivity_restoration_result.json << EOF
{
  "task_start": $TASK_START,
  "namespace": "ecommerce-platform",
  "api_gateway": {
    "endpoint_count": $API_GW_ENDPOINT_COUNT,
    "service_selector": $(echo "$API_GW_SELECTOR" | python3 -c "import json,sys; d=sys.stdin.read().strip(); print(json.dumps(d))" 2>/dev/null || echo "\"{}\"")
  },
  "product_service": {
    "inventory_host": "$INVENTORY_HOST"
  },
  "cart_service_netpol": {
    "policy_exists": $NETPOL_EXISTS,
    "allows_port_3000": $NETPOL_ALLOWS_3000
  },
  "payment_config": {
    "notification_host": "$NOTIFICATION_HOST"
  },
  "inventory_db": {
    "service_port": $INVENTORY_DB_PORT
  },
  "total_pods_running": $TOTAL_RUNNING
}
EOF

echo "Result JSON written."
echo "api-gateway endpoints=$API_GW_ENDPOINT_COUNT, selector=$API_GW_SELECTOR"
echo "product-service INVENTORY_HOST=$INVENTORY_HOST"
echo "cart-service NetworkPolicy allows port 3000: $NETPOL_ALLOWS_3000"
echo "payment-config NOTIFICATION_HOST=$NOTIFICATION_HOST"
echo "inventory-db Service port=$INVENTORY_DB_PORT"

echo "=== Export Complete ==="
