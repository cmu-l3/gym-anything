#!/bin/bash
# Export script for production_incident_response task
# Queries the ecommerce namespace for each service's health state

echo "=== Exporting production_incident_response result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/production_incident_response_end.png

TASK_START=$(cat /tmp/production_incident_response_start_ts 2>/dev/null || echo "0")

# ── Criterion 1: api-gateway pods Running ───────────────────────────────────
echo "Checking api-gateway pod state..."
API_RUNNING=0
API_RUNNING=$(docker exec rancher kubectl get pods -n ecommerce -l app=api-gateway --no-headers 2>/dev/null | grep -c "Running" || true)
[ -z "$API_RUNNING" ] && API_RUNNING=0

# Also check current image (should not be the broken image)
API_IMAGE=$(docker exec rancher kubectl get deployment api-gateway -n ecommerce \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")

# ── Criterion 2: web-frontend Service has endpoints ─────────────────────────
echo "Checking web-frontend Service endpoints..."
FRONTEND_ENDPOINT_COUNT=0
FRONTEND_SUBSETS=$(docker exec rancher kubectl get endpoints web-frontend -n ecommerce \
    -o jsonpath='{.subsets}' 2>/dev/null || echo "")
if [ -n "$FRONTEND_SUBSETS" ] && [ "$FRONTEND_SUBSETS" != "null" ] && [ "$FRONTEND_SUBSETS" != "" ]; then
    # Count endpoint addresses
    FRONTEND_ENDPOINT_COUNT=$(docker exec rancher kubectl get endpoints web-frontend -n ecommerce \
        -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null | grep -c "." || true)
fi
[ -z "$FRONTEND_ENDPOINT_COUNT" ] && FRONTEND_ENDPOINT_COUNT=0

# ── Criterion 3: cache-layer ConfigMap REDIS_PORT ───────────────────────────
echo "Checking cache-layer ConfigMap REDIS_PORT..."
CACHE_REDIS_PORT=$(docker exec rancher kubectl get configmap cache-config -n ecommerce \
    -o jsonpath='{.data.REDIS_PORT}' 2>/dev/null || echo "")
[ -z "$CACHE_REDIS_PORT" ] && CACHE_REDIS_PORT="unknown"

# ── Criterion 4: batch-processor pods Running ────────────────────────────────
echo "Checking batch-processor pod state..."
BATCH_RUNNING=0
BATCH_RUNNING=$(docker exec rancher kubectl get pods -n ecommerce -l app=batch-processor --no-headers 2>/dev/null | grep -c "Running" || true)
[ -z "$BATCH_RUNNING" ] && BATCH_RUNNING=0

# Check memory request (should be reduced from 32Gi)
BATCH_MEM_REQUEST=$(docker exec rancher kubectl get deployment batch-processor -n ecommerce \
    -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "")
[ -z "$BATCH_MEM_REQUEST" ] && BATCH_MEM_REQUEST="unknown"

# ── Check all pods in namespace (summary) ────────────────────────────────────
ALL_PODS_STATUS=$(docker exec rancher kubectl get pods -n ecommerce --no-headers 2>/dev/null | head -20 || echo "")
TOTAL_RUNNING=$(docker exec rancher kubectl get pods -n ecommerce --no-headers 2>/dev/null | grep -c "Running" || true)
[ -z "$TOTAL_RUNNING" ] && TOTAL_RUNNING=0

# ── Write result JSON ────────────────────────────────────────────────────────
cat > /tmp/production_incident_response_result.json <<EOF
{
  "task_start": $TASK_START,
  "namespace": "ecommerce",
  "api_gateway": {
    "pods_running": $API_RUNNING,
    "current_image": "$API_IMAGE"
  },
  "web_frontend": {
    "endpoint_count": $FRONTEND_ENDPOINT_COUNT,
    "has_endpoints": $([ "$FRONTEND_ENDPOINT_COUNT" -gt 0 ] && echo "true" || echo "false")
  },
  "cache_layer": {
    "redis_port": "$CACHE_REDIS_PORT",
    "port_correct": $([ "$CACHE_REDIS_PORT" = "6379" ] && echo "true" || echo "false")
  },
  "batch_processor": {
    "pods_running": $BATCH_RUNNING,
    "memory_request": "$BATCH_MEM_REQUEST"
  },
  "total_pods_running": $TOTAL_RUNNING
}
EOF

echo "Result JSON written to /tmp/production_incident_response_result.json"
echo "Summary: api_running=$API_RUNNING, frontend_endpoints=$FRONTEND_ENDPOINT_COUNT, cache_port=$CACHE_REDIS_PORT, batch_running=$BATCH_RUNNING"

echo "=== Export Complete ==="
