#!/bin/bash
# Export script for platform_capacity_governance_implementation
# Queries the payments-prod namespace for capacity governance controls

echo "=== Exporting platform_capacity_governance_implementation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/platform_capacity_governance_implementation_end.png

TASK_START=$(cat /tmp/platform_capacity_governance_implementation_start_ts 2>/dev/null || echo "0")

# ── Criterion 1: ResourceQuota 'payments-quota' ───────────────────────────────
echo "Checking ResourceQuota payments-quota..."

RQ_CPU=$(docker exec rancher kubectl get resourcequota payments-quota -n payments-prod \
    -o jsonpath='{.spec.hard.limits\.cpu}' 2>/dev/null || echo "")
[ -z "$RQ_CPU" ] && RQ_CPU="not-found"

RQ_MEM=$(docker exec rancher kubectl get resourcequota payments-quota -n payments-prod \
    -o jsonpath='{.spec.hard.limits\.memory}' 2>/dev/null || echo "")
[ -z "$RQ_MEM" ] && RQ_MEM="not-found"

RQ_PODS=$(docker exec rancher kubectl get resourcequota payments-quota -n payments-prod \
    -o jsonpath='{.spec.hard.pods}' 2>/dev/null || echo "")
[ -z "$RQ_PODS" ] && RQ_PODS="not-found"

RQ_SVCS=$(docker exec rancher kubectl get resourcequota payments-quota -n payments-prod \
    -o jsonpath='{.spec.hard.services}' 2>/dev/null || echo "")
[ -z "$RQ_SVCS" ] && RQ_SVCS="not-found"

RQ_EXISTS=$(docker exec rancher kubectl get resourcequota payments-quota -n payments-prod \
    --no-headers 2>/dev/null | grep -c "payments-quota" || echo "0")

# ── Criterion 2: LimitRange 'payments-limits' ─────────────────────────────────
echo "Checking LimitRange payments-limits..."

LR_EXISTS=$(docker exec rancher kubectl get limitrange payments-limits -n payments-prod \
    --no-headers 2>/dev/null | grep -c "payments-limits" || echo "0")

LR_CPU_DEFAULT=$(docker exec rancher kubectl get limitrange payments-limits -n payments-prod \
    -o jsonpath='{.spec.limits[?(@.type=="Container")].default.cpu}' 2>/dev/null || echo "")
[ -z "$LR_CPU_DEFAULT" ] && LR_CPU_DEFAULT="not-found"

LR_MEM_DEFAULT=$(docker exec rancher kubectl get limitrange payments-limits -n payments-prod \
    -o jsonpath='{.spec.limits[?(@.type=="Container")].default.memory}' 2>/dev/null || echo "")
[ -z "$LR_MEM_DEFAULT" ] && LR_MEM_DEFAULT="not-found"

# ── Criterion 3: HPA 'transaction-processor-hpa' ─────────────────────────────
echo "Checking HPA transaction-processor-hpa..."

HPA_EXISTS=$(docker exec rancher kubectl get hpa transaction-processor-hpa -n payments-prod \
    --no-headers 2>/dev/null | grep -c "transaction-processor-hpa" || echo "0")

HPA_MIN=$(docker exec rancher kubectl get hpa transaction-processor-hpa -n payments-prod \
    -o jsonpath='{.spec.minReplicas}' 2>/dev/null || echo "")
[ -z "$HPA_MIN" ] && HPA_MIN="0"

HPA_MAX=$(docker exec rancher kubectl get hpa transaction-processor-hpa -n payments-prod \
    -o jsonpath='{.spec.maxReplicas}' 2>/dev/null || echo "")
[ -z "$HPA_MAX" ] && HPA_MAX="0"

# Check CPU target — try v2 metrics path first, then v1
HPA_CPU_TARGET=$(docker exec rancher kubectl get hpa transaction-processor-hpa -n payments-prod \
    -o json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
spec = data.get('spec', {})
# Try autoscaling/v2 metrics
metrics = spec.get('metrics', [])
for m in metrics:
    if m.get('type') == 'Resource':
        res = m.get('resource', {})
        if res.get('name') == 'cpu':
            target = res.get('target', {})
            val = target.get('averageUtilization', target.get('averageValue', ''))
            print(str(val))
            sys.exit()
# Try v1 targetCPUUtilizationPercentage
v1 = spec.get('targetCPUUtilizationPercentage', '')
if v1:
    print(str(v1))
    sys.exit()
print('not-found')
" 2>/dev/null || echo "not-found")
[ -z "$HPA_CPU_TARGET" ] && HPA_CPU_TARGET="not-found"

HPA_TARGET_REF=$(docker exec rancher kubectl get hpa transaction-processor-hpa -n payments-prod \
    -o jsonpath='{.spec.scaleTargetRef.name}' 2>/dev/null || echo "")
[ -z "$HPA_TARGET_REF" ] && HPA_TARGET_REF="not-found"

# ── Criterion 4: PodDisruptionBudget 'payment-gateway-pdb' ───────────────────
echo "Checking PodDisruptionBudget payment-gateway-pdb..."

PDB_EXISTS=$(docker exec rancher kubectl get pdb payment-gateway-pdb -n payments-prod \
    --no-headers 2>/dev/null | grep -c "payment-gateway-pdb" || echo "0")

PDB_MIN_AVAILABLE=$(docker exec rancher kubectl get pdb payment-gateway-pdb -n payments-prod \
    -o jsonpath='{.spec.minAvailable}' 2>/dev/null || echo "")
[ -z "$PDB_MIN_AVAILABLE" ] && PDB_MIN_AVAILABLE="not-found"

PDB_SELECTOR=$(docker exec rancher kubectl get pdb payment-gateway-pdb -n payments-prod \
    -o jsonpath='{.spec.selector.matchLabels}' 2>/dev/null || echo "")
[ -z "$PDB_SELECTOR" ] && PDB_SELECTOR="not-found"

# ── Check overall workload health ─────────────────────────────────────────────
TOTAL_RUNNING=$(docker exec rancher kubectl get pods -n payments-prod --no-headers 2>/dev/null | grep -c "Running" || true)
[ -z "$TOTAL_RUNNING" ] && TOTAL_RUNNING=0

# ── Write result JSON ─────────────────────────────────────────────────────────
cat > /tmp/platform_capacity_governance_implementation_result.json << EOF
{
  "task_start": $TASK_START,
  "namespace": "payments-prod",
  "resource_quota": {
    "exists": $RQ_EXISTS,
    "cpu_limit": "$RQ_CPU",
    "memory_limit": "$RQ_MEM",
    "pods": "$RQ_PODS",
    "services": "$RQ_SVCS"
  },
  "limit_range": {
    "exists": $LR_EXISTS,
    "default_cpu": "$LR_CPU_DEFAULT",
    "default_memory": "$LR_MEM_DEFAULT"
  },
  "hpa": {
    "exists": $HPA_EXISTS,
    "min_replicas": $HPA_MIN,
    "max_replicas": $HPA_MAX,
    "cpu_target": "$HPA_CPU_TARGET",
    "target_ref": "$HPA_TARGET_REF"
  },
  "pdb": {
    "exists": $PDB_EXISTS,
    "min_available": "$PDB_MIN_AVAILABLE",
    "selector": $(echo "$PDB_SELECTOR" | python3 -c "import json,sys; d=sys.stdin.read().strip(); print(json.dumps(d))" 2>/dev/null || echo "\"not-found\"")
  },
  "total_pods_running": $TOTAL_RUNNING
}
EOF

echo "Result JSON written."
echo "ResourceQuota: exists=$RQ_EXISTS, cpu=$RQ_CPU, mem=$RQ_MEM, pods=$RQ_PODS"
echo "LimitRange: exists=$LR_EXISTS, cpu_default=$LR_CPU_DEFAULT, mem_default=$LR_MEM_DEFAULT"
echo "HPA: exists=$HPA_EXISTS, min=$HPA_MIN, max=$HPA_MAX, cpu=$HPA_CPU_TARGET"
echo "PDB: exists=$PDB_EXISTS, minAvailable=$PDB_MIN_AVAILABLE"

echo "=== Export Complete ==="
