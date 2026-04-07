#!/bin/bash
# Export script for statefulset_database_cluster_restoration
# Queries the data-platform namespace for StatefulSet configuration state

echo "=== Exporting statefulset_database_cluster_restoration result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/statefulset_database_cluster_restoration_end.png

TASK_START=$(cat /tmp/statefulset_database_cluster_restoration_start_ts 2>/dev/null || echo "0")

# ── Criterion 1: StatefulSet image tag must be postgres:15-alpine ─────────────
echo "Checking StatefulSet image..."

STS_IMAGE=$(docker exec rancher kubectl get statefulset postgres-cluster -n data-platform \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "not-found")
[ -z "$STS_IMAGE" ] && STS_IMAGE="not-found"

# ── Criterion 2: Secret must have key 'POSTGRES_PASSWORD' ────────────────────
echo "Checking postgres-credentials Secret keys..."

SECRET_KEYS=$(docker exec rancher kubectl get secret postgres-credentials -n data-platform \
    -o jsonpath='{.data}' 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    keys = list(data.keys())
    print(json.dumps(keys))
except Exception:
    print('[]')
" 2>/dev/null || echo "[]")
[ -z "$SECRET_KEYS" ] && SECRET_KEYS="[]"

HAS_POSTGRES_PASSWORD=$(echo "$SECRET_KEYS" | python3 -c "
import json, sys
try:
    keys = json.load(sys.stdin)
    print('true' if 'POSTGRES_PASSWORD' in keys else 'false')
except Exception:
    print('false')
" 2>/dev/null || echo "false")

# ── Criterion 3: StatefulSet containers must have resource requests ────────────
echo "Checking StatefulSet resource requests..."

STS_CPU_REQUEST=$(docker exec rancher kubectl get statefulset postgres-cluster -n data-platform \
    -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "")
[ -z "$STS_CPU_REQUEST" ] && STS_CPU_REQUEST=""

STS_MEM_REQUEST=$(docker exec rancher kubectl get statefulset postgres-cluster -n data-platform \
    -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "")
[ -z "$STS_MEM_REQUEST" ] && STS_MEM_REQUEST=""

# ── Criterion 4: Headless Service must have clusterIP: None ──────────────────
echo "Checking postgres-cluster Service clusterIP..."

SVC_CLUSTER_IP=$(docker exec rancher kubectl get service postgres-cluster -n data-platform \
    -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "not-found")
[ -z "$SVC_CLUSTER_IP" ] && SVC_CLUSTER_IP="not-found"

# ── Check StatefulSet replicas and pod health ─────────────────────────────────
STS_REPLICAS=$(docker exec rancher kubectl get statefulset postgres-cluster -n data-platform \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
[ -z "$STS_REPLICAS" ] && STS_REPLICAS=0

TOTAL_RUNNING=$(docker exec rancher kubectl get pods -n data-platform --no-headers 2>/dev/null | grep -c "Running" || true)
[ -z "$TOTAL_RUNNING" ] && TOTAL_RUNNING=0

# ── Write result JSON ─────────────────────────────────────────────────────────
cat > /tmp/statefulset_database_cluster_restoration_result.json << EOF
{
  "task_start": $TASK_START,
  "namespace": "data-platform",
  "statefulset": {
    "image": "$STS_IMAGE",
    "replicas": $STS_REPLICAS,
    "cpu_request": "$STS_CPU_REQUEST",
    "memory_request": "$STS_MEM_REQUEST"
  },
  "secret": {
    "has_postgres_password": $HAS_POSTGRES_PASSWORD,
    "keys": $SECRET_KEYS
  },
  "headless_service": {
    "cluster_ip": "$SVC_CLUSTER_IP"
  },
  "total_pods_running": $TOTAL_RUNNING
}
EOF

echo "Result JSON written."
echo "StatefulSet image=$STS_IMAGE"
echo "Secret has POSTGRES_PASSWORD=$HAS_POSTGRES_PASSWORD, keys=$SECRET_KEYS"
echo "StatefulSet cpu_request=$STS_CPU_REQUEST, mem_request=$STS_MEM_REQUEST"
echo "Service clusterIP=$SVC_CLUSTER_IP"

echo "=== Export Complete ==="
